# 🔊 Assets audio — dépose-les ici (override automatique)

L'autoload **`AudioManager`** (`scripts/managers/audio_manager.gd`) charge en priorité les **vrais
fichiers** présents dans ce dossier ; **à défaut**, il retombe sur des **placeholders procéduraux**
synthétisés au démarrage. **Aucune ligne de code à modifier** : il suffit de déposer les fichiers
avec le **bon nom** ci-dessous, puis de **réimporter** le projet
(`Godot…_console.exe --headless --path . --import`) ou de rouvrir l'éditeur.

## 📁 Arborescence & noms attendus

```
assets/audio/
├── sfx/
│   ├── hover.ogg      ← survol de bouton (très court, discret)
│   ├── click.ogg      ← clic d'interface
│   ├── confirm.ogg    ← validation (START, achat, confirmation de phase)
│   ├── back.ogg       ← retour / annulation
│   ├── sting.ogg      ← « reveal » du logo (Splash d'ouverture)
│   ├── die_lock.ogg   ← claque d'arrêt d'un dé (Split-Screen VS de combat, §8.66)
│   └── impact.ogg     ← coup encaissé / pertes révélées au combat (§8.66)
└── music/
    ├── menu_ambient.ogg     ← MUSIQUE des menus (BOUCLÉE automatiquement)
    └── battle_ambient.ogg   ← MUSIQUE de l'arène / combat (BOUCLÉE, §8.66)
```

> 🎵 **`menu_ambient` actuel (§8.67)** = brano **dark melodic trap** ORIGINAL (808 glissés saturés,
> hi-hats roulés, clap demi-temps, cloche menaçante, pad sombre, ré mineur, 27,4 s, stéréo,
> **boucle sans jointure**), généré par [`../../tools/gen_menu_trap.gd`](../../tools/gen_menu_trap.gd).
> ⚠️ **Œuvre originale** (inspirée du *genre*, jamais d'un titre existant → **aucun copyright**).
> L'ancien thème « Interstellar » (heavy rock, §8.65) reste disponible en **alternative archivée** via
> [`../../tools/gen_menu_music.gd`](../../tools/gen_menu_music.gd) — les deux outils visent CE fichier,
> **n'en lancer qu'un**. Pour mettre ton propre morceau, dépose simplement `menu_ambient.ogg`/`.wav` ici.
>
> 🎵 **`battle_ambient` actuel** = **musique de combat** synthétisée (tambours de guerre, pédale-sub
> de dread, cordes dissonantes, stabs heavy rock épars, ré mineur i–VI–iv–V, 38,4 s, stéréo,
> **boucle sans jointure**), générée par
> [`../../tools/gen_battle_music.gd`](../../tools/gen_battle_music.gd) — voir journal §8.66. L'arène
> (`scenes/game/main.tscn`) la lance via `AudioManager.start_battle_ambient()` (bascule depuis la
> musique de menu, lecteur unique). Remplaçable de même par `battle_ambient.ogg`/`.wav`.

- **Extensions acceptées** (par ordre de préférence) : `.ogg`, `.wav`, `.mp3`. La première trouvée
  pour un nom donné gagne. **`.ogg` recommandé** (bon compromis taille/qualité, bouclage natif).
- Le **nom de base** doit être **exactement** celui de la liste (sensible à la casse).
- `menu_ambient` est **forcé en boucle** par le code (`loop = true`) — inutile de configurer la
  boucle dans le `.import`, mais ça ne gêne pas si tu le fais.

## 🎚️ Routage & volume

- Les **SFX** sortent sur le bus **`SFX`**, la musique sur le bus **`Music`**
  (`default_bus_layout.tres`). Les **volumes sont pilotés par l'écran Paramètres** via
  `SettingsManager` → rien à régler ici.
- Garde les niveaux **normalisés** (pic ≈ -3 dB) et les SFX **courts** (hover/click < 0,1 s) pour
  rester cohérent avec le rythme de l'UI.

## ✅ Après dépôt

1. Réimporter (`--import`) — Godot génère le `.import`/`.ctex` audio.
2. Relancer le client : `AudioManager` détecte et joue les vrais fichiers à la place des
   placeholders, **sans changement de code**.

> Tant que ce dossier est vide, le jeu reste **100 % fonctionnel** grâce aux placeholders
> procéduraux (cf. journal `FRONTEND_INTERFACES.md` R6 / §8.64).
