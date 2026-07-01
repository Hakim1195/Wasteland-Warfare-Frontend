# CLAUDE.md — Guide de travail (client Godot « Wasteland Warfare »)

> Dépôt **frontend isolé** du jeu **Wasteland Warfare** (« Doomsday Risk ») : client **Godot 4.7**,
> jeu **100 % multijoueur en ligne** (aucun mode hors ligne) de type Risk post-apocalyptique.
> Ce fichier est le point d'entrée pour toute IA/contributeur. La **source de vérité frontend
> détaillée** est [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md).

---

## ⛔ DIRECTIVES ABSOLUES

1. **NE JAMAIS COMMITTER NI PUSH.** L'utilisateur gère lui-même tous les commits. On ne lance
   jamais `git commit`, `git push`, `git add` en vue d'un commit, ni aucune opération qui écrit
   dans l'historique git — même si le travail est « terminé ». On laisse les changements dans la
   working tree et on s'arrête là.
2. **L'utilisateur communique en italien.** Lui répondre en italien. La **documentation et les
   commentaires de code du projet sont en français** (à conserver pour la cohérence).
3. **Toujours valider** une modification de scène/script avant de la déclarer faite (voir
   « Validation headless » ci-dessous).

---

## 📚 Documentation

- [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md) — **SOURCE DE VÉRITÉ** : charte graphique, flux
  de navigation, structure des scènes, HUD, shaders, helpers, **journal §8** et **feuille de route**.
  À mettre à jour à CHAQUE modification de scène / shader / HUD / helper.
  - **⚠️ DOUBLE EXEMPLAIRE — TOUJOURS SYNCHRONISER.** Ce fichier existe **aussi à la racine du
	projet** (`../FRONTEND_INTERFACES.md`). L'utilisateur fait **deux commits séparés** : un du
    **projet entier** (racine, backend+frontend) et un du **frontend isolé** (pour son collègue).
	Après toute édition de la copie `frontend/` (source de vérité), **recopier à l'identique** vers
	la racine — les deux fichiers doivent avoir le **même hash** (`Copy-Item -Force` puis
	`Get-FileHash`). Vaut pour **tout doc partagé** présent dans les deux emplacements.
- Les docs `CONTEXTE.md`, `ARCHITECTURE_ET_REGLES.md`, `CONTRAT_RESEAU.md`,
  `PIPELINE_ET_BOOTLOADER.md` sont référencées mais vivent dans le **dépôt backend** — elles ne
  sont **PAS présentes** ici. Ne pas tenter de les ouvrir dans ce dépôt.

---

## 🎨 Charte « Warzone Command » (cf. `FRONTEND_INTERFACES.md` §2)

Langage visuel **Call of Duty: Warzone**. Palette canonique :

| Rôle | Hex | `Color(...)` Godot |
|------|-----|--------------------|
| Fond gunmetal | `#0F1318` (α≈0.9) | `Color(0.058824, 0.07451, 0.094118, 0.9)` |
| Surface secondaire | `#1A2028` | `Color(0.101961, 0.12549, 0.156863, 1)` |
| **Accent cyan tactique** (interactif) | `#36C5D9` | `Color(0.211765, 0.772549, 0.85098, 1)` |
| Or (récompense) | `#E0B249` | `Color(0.878431, 0.698039, 0.286275, 1)` |
| Texte primaire (blanc froid) | `#EEF3F7` | `Color(0.933333, 0.952941, 0.968627, 1)` |
| Texte muet (acier) | `#8A97A5` | `Color(0.541176, 0.592157, 0.647059, 1)` |
| Danger (rouge) | `#D6453F` | `Color(0.839216, 0.270588, 0.247059, 1)` |
| Contamination (vert) | `#7FFF00` | — |

- **Police** : `SystemFont` condensé `Bahnschrift → Oswald → Saira Condensed → Arial Narrow → Arial`, poids 700, **MAJUSCULES**.
- **ADN angulaire** : `corner_radius = 0`, **encoches de coin biseautées** cyan, **filets fins** cyan (1-2 px), **chevrons `❯`** comme puces, rythme **eyebrow → valeur**, boutons CTA style « START » (bordure cyan + lueur au survol).
- ✅ Tous les écrans de menu sont **déjà migrés** vers cette charte (l'orange `#d35400` legacy a disparu de l'UI ; il ne survit que comme **couleur d'accent de certaines factions**, conservée à dessein).

---

## 🧩 Conventions de code

- **Règle d'Or §6.1** : l'UI ne contient **jamais** de logique de jeu brute → tout passe par des
  **signaux** vers le contrôleur (`main.gd`) ou les managers (`AuthManager`, `NetworkManager`,
  `GameState`). Le HUD/les écrans sont des **Vues** pures.
- **`@export` + NodePath** : on câble les nœuds via `@export var x: Type` assigné dans la scène
  (drag-drop éditeur) plutôt que des `$chemin` codés en dur → évite les bugs « Node not found ».
- **Factions data-driven** : `resources/factions/*.tres` (10 factions). Chargement robuste :
  scan `DirAccess` export-safe (gère `.remap`) **+ `FALLBACK_PATHS`** + **duck-typing**
  (`res.get("id") != null`, pas de dépendance au `class_name` global). Mêmes ids que le backend.
- **Piège JSON float (§5)** : `JSON.parse_string` renvoie les nombres en `float`. Toujours
  `int(...)` sur les ids de salle / de joueur / valeurs avant affichage ou clé de Dictionary.
- **Helper UI partagé** : [`scripts/ui/warzone_ui.gd`](scripts/ui/warzone_ui.gd) — ornements de
  charte (`add_corner_notches(panel)`). **Chargé par `preload`** dans chaque écran (pas via
  `class_name`, par prudence vis-à-vis du cache d'import — même logique que `faction_selection.gd`).

---

## 🎮 Flux de navigation

```
bootloader → title_splash → auth_screen → main_menu → lobby_screen
   → waiting_room → faction_selection → game/main.tscn
```
Détail dans `FRONTEND_INTERFACES.md` §3. `run/main_scene = bootloader.tscn`.
> ⚠️ **Ouverture refondue (§8.44).** L'ancienne `intro_video.tscn` (lecteur vidéo) est **retirée**
> au profit du **Splash Eroïque animé** `title_splash.tscn` (option C : hex-grid + radar shader,
> reveal du logo, cendres, dactylographie, audio sting). Transitions de scène en **fondu** via
> l'autoload `TransitionManager` ; SFX/ambiance via l'autoload `AudioManager` (placeholders
> procéduraux, R6).

---

## 🗂️ Structure

- `scenes/ui/` — écrans de menu (auth, main_menu, lobby, waiting_room, bootloader, **title_splash**, shop, profile, leaderboard, settings).
- `scenes/faction_selection/`, `scenes/game/` — draft de faction, arène (`main.tscn`), board, VS, rapport.
- `scripts/ui/`, `scripts/game/`, `scripts/managers/` — scripts (autoloads dans `scripts/managers/`).
- `resources/factions/*.tres` — données de factions. `shaders/` — `.gdshader`. `assets/images/` — visuels.

---

## 🔧 Environnement & validation headless

- **Moteur** : Godot **4.7-stable**. Binaires (sur cette machine) :
  - GUI : `C:\Users\Hamdi\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe`
  - **Console (stdout, à privilégier pour la CLI)** : `…\Godot_v4.7-stable_win64_console.exe`
- **Addon MCP `godot_ai`** : outillage **local**, **gitignoré** (`.gitignore` → `/addons/`). Il est
  enregistré dans `project.godot` comme **autoload** (`_mcp_game_helper`) **et** plugin éditeur.
  - ⚠️ **Sans cet addon installé**, l'autoload manque → le **boot runtime échoue** au démarrage
	(`Failed to instantiate an autoload`). L'`--import` headless, lui, **reste OK** (il n'instancie
	pas les autoloads). Contournement de secours pour valider un boot sans l'addon : créer un stub
	`addons/godot_ai/runtime/game_helper.gd` (`extends Node`), valider, puis le supprimer (gitignoré
	→ aucune trace). *(L'addon réel étant désormais installé, ce contournement n'est plus nécessaire.)*
- **Validation type** (depuis la racine du projet) :
  ```sh
  # 1) Réimport (compile tous les scripts, valide le chargement des scènes) :
  Godot…_console.exe --headless --path . --import
  # 2) Boot runtime d'une scène (quelques frames) pour vérifier _ready / runtime :
  Godot…_console.exe --headless --path . res://scenes/ui/main_menu.tscn --quit-after 30
  ```
  Un boot propre = **0 ligne `ERROR`**.
- **Pas de Python/Pillow** sur cette machine (l'alias `python` est le stub du Microsoft Store). Pour
  toute **manipulation d'image** (recoloration d'asset, etc.), utiliser **Godot** : un script
  `extends SceneTree` lancé en `--script` **sans `--path`** (donc sans autoload) avec
  `Image.load_from_file()` / `Image.save_png()` sur des chemins OS absolus.
