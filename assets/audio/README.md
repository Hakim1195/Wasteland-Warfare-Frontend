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
│   ├── impact.ogg     ← coup encaissé / pertes révélées au combat (§8.66)
│   ├── explosion.ogg  ← impact de la FLÈCHE DE GUERRE (refonte UI arène, lot D)
│   ├── chat_ping.ogg  ← message de chat reçu dans une conversation non affichée (lot B)
│   ├── finisher_steel.ogg    ← sting du finisher « Barrage d'acier »   (lot D/G)
│   ├── finisher_orbital.ogg  ← sting du finisher « Frappe orbitale »   (lot D/G)
│   ├── finisher_ash.ogg      ← sting du finisher « Nuage de cendres »  (lot D/G)
│   ├── radio_crackle.ogg     ← craquement de talkie AVANT chat_ping    (§8.122 lot C)
│   ├── thunder_far.ogg       ← tonnerre lointain (éclair de zone)      (§8.122 lot D)
│   └── promotion.ogg         ← sting de montée de division (hub)       (§8.122 lot F)
├── amb/                      ← ⚠️ DOSSIER NEUF (§8.122 lot C) — bus `Ambience`, boucles
│   ├── geiger.ogg            ← compteur Geiger (clics apériodiques)
│   ├── wind.ogg              ← vent du wasteland (arène)
│   └── radio_hub.ogg         ← radio militaire du QG (menu principal)
└── music/
    ├── menu_ambient.ogg     ← MUSIQUE des menus (BOUCLÉE automatiquement)
    ├── battle_ambient.ogg   ← MUSIQUE de l'arène / combat (BOUCLÉE, §8.66)
    ├── battle_base.ogg      ← ⚠️ MUSIQUE DYNAMIQUE, couche 1/3 (§8.122 lot B)
    ├── battle_mid.ogg       ← ⚠️ MUSIQUE DYNAMIQUE, couche 2/3
    └── battle_high.ogg      ← ⚠️ MUSIQUE DYNAMIQUE, couche 3/3
```

---

## 🎚️ MUSIQUE DYNAMIQUE À COUCHES (§8.122, lot B) — bon de commande

L'arène ne joue plus une piste fixe : **trois stems jouent EN PARALLÈLE** et sont crossfadés par
`war_intensity` (jauge de tension 0→1 calculée côté client). Plus la partie se tend, plus il y a de
couches audibles.

| Fichier | Rôle | Entre à | Sort à | Niveau audible |
|---|---|---|---|---|
| `music/battle_base.ogg` | Lit de base — toujours présent | dès le début | jamais | `MUSIC_TARGET_DB` (−4 dB) |
| `music/battle_mid.ogg` | Percussions / tension moyenne | intensité **> 0,35** | **< 0,30** | −6 dB |
| `music/battle_high.ogg` | Cuivres / urgence, fin de partie | intensité **> 0,65** | **< 0,60** | −6 dB |

> Les seuils d'entrée et de sortie diffèrent volontairement (hystérésis 0,05) : sans cette bande
> morte, une intensité qui oscille autour du seuil ferait « pomper » la couche en boucle.

**⚠️ CONTRAINTES DE PRODUCTION — non négociables :**

1. **DURÉE STRICTEMENT IDENTIQUE** pour les 3 fichiers (à l'échantillon près) et **MÊME BPM**. Les
   trois lecteurs partent dans la même frame et ne sont jamais relancés : un écart de durée les
   désynchroniserait à chaque bouclage.
2. **Boucle propre** (pas de silence ni de clic au raccord) — même exigence que `menu_ambient`.
3. Les trois pistes doivent **s'empiler** musicalement : `mid` et `high` sont des ADDITIONS à
   `base`, pas des variantes. Mixer chaque stem pour qu'il sonne juste seul ET superposé.
4. **Format `.ogg`**, pic normalisé ≈ −3 dB.

**Comportement de repli (aucun de ces fichiers n'est requis pour livrer) :** si **un seul** des trois
manque, le jeu reste sur `battle_ambient` — comportement historique **strictement inchangé**, sans le
moindre log d'erreur. Il n'y a **jamais** de lecture partielle (2 stems sur 3).

Un mécanisme de **resynchronisation défensive** vérifie toutes les 60 s que les couches n'ont pas
dérivé de plus de 50 ms et les recale sur `battle_base` le cas échéant (log `print` silencieux).

---

## 🌫️ AMBIANCES DIÉGÉTIQUES (§8.122, lot C) — dossier `amb/`

Boucles **continues** routées sur le bus **`Ambience`** (slider « AMBIANCE » dans Paramètres, défaut
−12 dB). Séparées des SFX parce qu'elles ne ponctuent rien : elles habitent le monde.

| Fichier | Rôle | Où | Niveau cible (lecteur) |
|---|---|---|---|
| `amb/geiger.ogg` | Compteur Geiger — **le son signature du jeu** | Arène | **−6 dB** (zone chez moi) · **−14 dB** (à 1 territoire) · **−22 dB** (à 2) · coupé au-delà |
| `amb/wind.ogg` | Vent du wasteland, permanent | Arène | −18 dB (fixe) |
| `amb/radio_hub.ogg` | Radio militaire — souffle, bips, voix indistinctes | QG **uniquement** | −20 dB (fixe) |

> 🔊 **Le Geiger doit rester UTILISABLE, pas décoratif** : son volume dit « la radioactivité est à N
> territoires de chez moi ». Livrer une boucle de **clics apériodiques** (irréguliers) — un train
> régulier sonnerait comme un métronome et perdrait toute lisibilité d'information.
> Boucle courte (3–5 s) suffisante, sans motif reconnaissable qui trahirait le point de bouclage.

> 🗣️ **`radio_hub` : aucune parole intelligible.** Des fragments de voix, jamais un mot —
> sans quoi il faudrait le produire en FR/EN/IT.

**Repli :** dossier vide → placeholders synthétisés (Poisson pour le Geiger, bruit filtré + LFO pour
le vent, souffle + bips + formants pour la radio). Le jeu est **100 % fonctionnel sans ces fichiers**.

> ⚔️ **Ambiance de guerre (refonte UI arène, lot F).** Déposer `music/battle_ambient.{ogg,wav,mp3}`
> **remplace TOUT** — aucune ligne de code à toucher (mécanique `_load_override`). À défaut, le repli
> synthétisé `_make_battle_pad()` fournit désormais une boucle de **9,6 s** (drone grave à battement
> lent, tom martelé, **percussions lointaines** à graine fixe → boucle sans discontinuité).
> La piste entre en **fondu de 2 s** (`MUSIC_FADE_TIME`) et se cale sur `MUSIC_TARGET_DB` (−4 dB) :
> discrète mais **audible**, les volumes de l'écran Paramètres restant souverains au-dessus.
> ⚠️ **Aucun asset externe sous licence douteuse** : uniquement des overrides locaux et de la synthèse.

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

- Les **SFX** sortent sur le bus **`SFX`**, la musique (couches comprises) sur le bus **`Music`**,
  les **ambiances** sur le bus **`Ambience`** (`default_bus_layout.tres`). Les **volumes sont
  pilotés par l'écran Paramètres** via `SettingsManager` → rien à régler ici.
- Garde les niveaux **normalisés** (pic ≈ -3 dB) et les SFX **courts** (hover/click < 0,1 s) pour
  rester cohérent avec le rythme de l'UI.

## ✅ Après dépôt

1. Réimporter (`--import`) — Godot génère le `.import`/`.ctex` audio.
2. Relancer le client : `AudioManager` détecte et joue les vrais fichiers à la place des
   placeholders, **sans changement de code**.

> Tant que ce dossier est vide, le jeu reste **100 % fonctionnel** grâce aux placeholders
> procéduraux (cf. journal `FRONTEND_INTERFACES.md` R6 / §8.64).
