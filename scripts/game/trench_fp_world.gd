extends SubViewportContainer
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — COUCHE 2 : LE MONDE 3D (vue PURE, aucun réseau, aucune règle).
#
# Le `SubViewport` transparent du chantier — c'est le pattern de `hero_viewport_3d.gd` porté à
# plus grande échelle (§2.3) : `transparent_bg` + `own_world_3d` + Environment en BG_CLEAR_COLOR
# (JAMAIS BG_SKY, qui rendrait un fond OPAQUE et masquerait le décor de la couche 1 —
# piège déjà payé une fois sur ce dépôt).
#
# CE QUI VIT ICI : le blockout (repères + greybox), le soldat adverse, les traçantes, les
# grenades et leurs marqueurs au sol, le laser du CONDOR, et le VIEWMODEL.
#
# ┌─ §8.138 — LE SOLDAT EST UN SPRITE PEINT (billboard à frames) ─────────────────────────────────┐
# │ La couche PERSONNAGES est passée des modèles 3D aux BILLBOARDS de sprites peints : le décor    │
# │ étant pré-rendu au pinceau (img2img FLUX), un personnage 3D éclairé en temps réel jurerait     │
# │ contre lui. Seule la REPRÉSENTATION change — placement, échelle et perspective restent 3D,     │
# │ portés par le blockout, donc la table angulaire et la visée serveur ne bougent pas d'un iota.  │
# │ Sans fichiers déposés, le placeholder capsule + casque reprend INTÉGRALEMENT le service.       │
# └───────────────────────────────────────────────────────────────────────────────────────────────┘
#
# ┌─ POURQUOI LE VIEWMODEL EST DANS *CE* VIEWPORT (choix motivé, §2.3) ───────────────────────────┐
# │ Un FPS met d'ordinaire les mains dans un second viewport pour qu'elles ne s'enfoncent pas     │
# │ dans les murs. Ici, on s'en passe, pour trois raisons vérifiables :                           │
# │   1. il n'y a AUCUNE géométrie à moins de 2 m devant les yeux (le no man's land fait 35 m) —  │
# │      le clipping qu'on chercherait à éviter ne peut pas se produire ;                         │
# │   2. GL Compatibility + un viewport en moins = le budget de recette du §5.7 tient largement ; │
# │   3. une seule scène = un seul éclairage : les mains ne « flottent » pas dans une lumière     │
# │      différente de celle du décor.                                                            │
# │ Si un jour l'arène gagne un obstacle proche, c'est CE commentaire qu'il faudra rouvrir.       │
# └───────────────────────────────────────────────────────────────────────────────────────────────┘
#
# CONTRAT : l'hôte (`trench_fp.gd`) pousse un VIEW-MODEL complet à chaque frame (`render_world`).
# Ce script ne lit ni `NetworkManager`, ni `GameState` — il ne sait même pas qu'il y a un duel.
# =================================================================================================

const Geo := preload("res://scripts/game/trench_geometry.gd")
const Sprites := preload("res://scripts/game/trench_sprites.gd")
const BlockoutScene := preload("res://scenes/game/trench_arena_blockout.tscn")
const ExplosionScene := preload("res://scenes/game/trench_explosion.tscn")
const Springs := preload("res://scripts/game/trench_springs.gd")

# Champ de vision VERTICAL de la caméra ⚙. À 9 m (§8.141), la silhouette adverse EXPOSÉE fait
# 3,44° de large sur 3,47° de haut, soit ~67 × 68 px en 1080p : elle se VISE, elle ne se devine plus.
# (Rappel de l'échelle parcourue : ~19 px à 35 m, ~51 px à 12 m.)
const CAMERA_FOV := 55.0
# Le proche est très court : le viewmodel vit à ~0,4 m de l'œil.
const CAMERA_NEAR := 0.05

# Transitions de pose (§5.1) : fondu-filé latéral et travelling vertical.
const MOVE_TRANSITION := 0.15
const STANCE_TRANSITION := 0.12
# Suivi de caméra par la visée (§1.1) : la tête accompagne le réticule, le CORPS ne tourne pas.
# ╔═ LA CAMÉRA SUIT LA VISÉE, ET ELLE LA SUIT ENTIÈREMENT (§8.139.1) ════════════════════════════╗
# ║ ⚠️⚠️ RÉGLAGE D'ORIGINE : 0,25 plafonné à 6°. Sur ±32° de visée, la caméra ne tournait donc que ║
# ║ de ±6° : le reste du débattement n'était qu'un RÉTICULE qui glissait sur l'écran. C'était      ║
# ║ tenable tant que le paysage était le blockout 3D — il tournait, on voyait quelque chose bouger.║
# ║ Depuis qu'un décor PEINT le remplace, le paysage est une image FIXE : on bougeait la souris et ║
# ║ plus rien ne bougeait. Verdict du testeur : « le mouvement de la souris est inversé et pas du  ║
# ║ tout facile à gérer » — et c'est exactement ce que produit une vue qui ne répond pas.          ║
# ║                                                                                                ║
# ║ ⚠️ CE N'EST PAS UN CHANGEMENT DE RÈGLE. Le lacet/site ENVOYÉS au serveur sont inchangés ; la   ║
# ║ table angulaire reste seule juge de la touche. On ne change que ce que la caméra MONTRE.       ║
# ║ Les POSES restent fixes : c'est la position de l'œil qui ne bouge pas, pas son regard.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ╔═ ET DEPUIS LE PIVOT « MONDE 3D + CIEL PEINT », ELLE PEUT ENFIN LA SUIVRE ═════════════════════╗
# ║ Ce réglage était JUSTE dans son principe et FAUX dans son contexte : faire tourner la caméra   ║
# ║ devant un décor peint FIXE ne pouvait que détacher le paysage de la scène. Le monde est        ║
# ║ maintenant de la vraie 3D jusqu'à l'horizon — il répond de lui-même, sans shader ni pan.       ║
# ║ ⚠️ Ces deux valeurs sont désormais des VALEURS INITIALES, pas des vérités : c'est Hakim qui    ║
# ║ règle la sensation dans le panneau F10, en jouant. Voir `apply_tuning()` plus bas.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const AIM_FOLLOW := 1.0
# Borne de sécurité : elle n'écrête jamais en jeu, elle empêche seulement une visée aberrante de
# faire pivoter la caméra à l'envers du monde.
# ╔═ ⚠️ ELLE DOIT RESTER AU-DESSUS DU DÉBATTEMENT DE VISÉE — ET C'EST MAINTENANT MÉCANIQUE ═══════╗
# ║ Sinon la caméra cesse de suivre le réticule dans les derniers degrés : le joueur vise une      ║
# ║ cible que sa propre vue refuse de rejoindre. C'est EXACTEMENT le défaut §7.1 du rapport de     ║
# ║ pivot, vécu avec un réglage persisté à 45° pour un débattement monté à 58°. On avait alors     ║
# ║ versionné les réglages ; on retire ici la deuxième moitié du piège, celle qui restait dans le  ║
# ║ CODE : le plafond sort de `Geo.camera_follow_max_deg()`, donc de la géométrie, plutôt que d'un ║
# ║ nombre reposé à la main après chaque rapprochement.                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

# ╔═ LA BRUME DE PROFONDEUR EST DANS L'ENVIRONNEMENT, PAS SUR L'ÉCRAN ════════════════════════════╗
# ║ `trench_ambient.gd` peint deux nappes de brume à hauteur d'horizon — en 2D, donc à une         ║
# ║ ordonnée d'écran FIXE. Tant que la caméra ne bougeait pas, ça tenait ; une caméra qui pique du ║
# ║ nez emporterait l'horizon et laisserait la brume derrière. On ajoute donc ici la seule brume   ║
# ║ qui ne peut pas se tromper : celle du moteur, indexée sur la PROFONDEUR. C'est elle qui fond   ║
# ║ le sol lointain dans le bas du panorama — le raccord peinture/3D que tout le lot cherche.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ⚠️ CETTE COULEUR EST RELEVÉE SUR LE PANORAMA, PAS CHOISIE. C'est la moyenne de sa bande basse,
# celle qui touche la ligne d'horizon (mesure : RGB 71 / 86 / 92). Le sol lointain s'y fond donc
# EXACTEMENT là où l'arc de ciel commence : c'est ce raccord de teinte, et lui seul, qui fait que
# la peinture et la 3D se lisent comme une seule image. Toute retouche du panorama impose de
# reprendre cette mesure — `tools/trench_asset_factory.py` la sort en deux lignes.
const FOG_COLOR := Color(0.279, 0.338, 0.361)
# Elle ne commence qu'APRÈS le duel : à 80 m, la tranchée adverse (9 m depuis §8.141) et son soldat
# sont encore parfaitement nets. Voiler la cible serait changer le jeu, pas l'habiller.
# ⚠️ VÉRIFIÉ PAR LA MESURE au rapprochement, et pas par le raisonnement : `probe_trench_soldier`
# rend EXACTEMENT le même RGB pour le soldat avec et sans les couches d'habillage (98/76/71 dans les
# deux cas au relevé du §8.141). La brume ne le touche pas — la marge est même passée de 45 m à 71 m.
const FOG_BEGIN := 80.0
const FOG_END := 320.0

const COL_ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const COL_GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const COL_DANGER := Color(0.839216, 0.270588, 0.247059, 1)

# TEINTE DE FACTION du sprite (§8.138) ⚙. Les frames sont produites en uniforme GRIS NEUTRE : on
# MÉLANGE l'accent au blanc plutôt que de multiplier le sprite par lui. À 1,0 la peinture disparaît
# sous une couche de couleur unie ; à 0,35 la faction se lit sans effacer le travail du pinceau.
const ENEMY_TINT_MIX := 0.35
# Éclair de touche : on pousse la teinte vers le blanc. Le sprite a déjà sa frame `hit` — ce flash
# n'est qu'un renfort, il ne doit donc pas saturer l'image.
const ENEMY_HIT_WHITEN := 0.6

const TRACER_POOL := 24
# Distance au-delà de laquelle MA traçante devient visible : elle naît à l'œil du tireur, il faut
# donc la laisser sortir du cadre proche avant de la dessiner ⚙.
# ⚠️ EN MÈTRES ABSOLUS, et c'est VOULU — contrairement à la longueur ci-dessous. Le critère est
# ANGULAIRE : une boîte de 6 cm couvre ~10° à 35 cm de l'œil (le défaut §7.2) et 1,7° à 2 m. Ce
# seuil ne dépend donc pas de la portée de l'arène, et l'exprimer en fraction le ferait fondre à
# chaque rapprochement jusqu'à ramener la boîte devant la pupille.
const MUZZLE_CLEAR := 2.0
# Longueur apparente de la balle ⚙, en FRACTION de la portée. Elle porte la lisibilité du vol : trop
# courte, la traçante est un point qui saute d'une frame à l'autre ; trop longue, c'est un trait fixe
# entre les tranchées — et c'est précisément ce que 3 m en dur seraient devenus sur 9 m de no man's
# land (un tiers du terrain, occupé en permanence). Un quart de la portée garde le même rapport
# qu'à 12 m, où le réglage avait été jugé bon.
# ⚠️ 0,25 → 0,45 AVEC LE VOL À 1 TICK (§8.141.2) : la balle traverse le no man's land en 100 ms,
# soit ~6 images à 60 Hz. Une traçante courte y devient un point qui clignote une fois et que l'œil
# ne relie à rien. Une STRIE LONGUE est ce qui rend un projectile rapide lisible — c'est la même
# raison qui fait qu'on dessine une comète avec une queue.
const TRACER_LENGTH_RATIO := 0.45
const GRENADE_POOL := 6
# Hauteur du PLANCHER DE TRANCHÉE (+ un rien pour éviter le z-fighting avec le sol). C'est là que
# tombent les grenades et que se posent leurs marqueurs — pas au niveau du no man's land.
const MARKER_Y := 0.04

# ╔═ §8.141 — LE DÉCALQUE DE VISÉE : POURQUOI IL N'A QU'UN SEUL DEGRÉ DE LIBERTÉ ═════════════════╗
# ║ Le bon de commande décrit un décalque « au point visé », validé contre une bande de profondeur ║
# ║ de ±1,5 m autour de la tranchée adverse. Le premier montage l'a pris au pied de la lettre — et  ║
# ║ le harnais l'a mis au rouge sur un cas trivial (viser à −8° tombait à z = 11,3 m, hors bande).  ║
# ║ En cherchant pourquoi, DEUX faits de géométrie sont sortis, et ils condamnent la lecture        ║
# ║ littérale :                                                                                     ║
# ║                                                                                                 ║
# ║  1. UNE BANDE DE PROFONDEUR EST UNE FENÊTRE ANGULAIRE MINUSCULE. Depuis un œil à 1,70 m, le    ║
# ║     plancher de la tranchée d'en face couvre à peine **2,9° de site** entre les deux bords de   ║
# ║     la bande. Demander au joueur d'y loger son réticule, c'est lui demander un geste de         ║
# ║     précision au pixel pour une arme de ZONE — l'inverse de ce que le chantier cherche.         ║
# ║  2. LE POINT D'IMPACT EST INVISIBLE. La ligne de vue qui rase l'arête du parapet adverse coupe  ║
# ║     à 1,194 m au plan des soldats : TOUT ce qui est plus bas est occulté par les sacs. Le       ║
# ║     plancher de la tranchée d'en face (y ≈ 0) ne peut donc PAS être vu debout — un décalque     ║
# ║     posé dessus serait derrière un mur.                                                          ║
# ║                                                                                                 ║
# ║ ⚠️ ET SURTOUT : LA PROFONDEUR N'EST PAS UNE VARIABLE DU JEU. Le contrat serveur ne transporte    ║
# ║ que `target_x` — la grenade tombe TOUJOURS dans la tranchée adverse. Faire viser en profondeur  ║
# ║ demanderait au joueur un effort qui ne change RIEN, et lui laisserait croire l'inverse.          ║
# ║                                                                                                 ║
# ║ Le décalque est donc posé au plan des soldats adverses, et son abscisse suit le LACET — le seul ║
# ║ axe qui compte. Le site ne sert qu'à deux garde-fous honnêtes : ne pas viser le ciel, ne pas     ║
# ║ viser ses propres pieds. Le cercle reste alors sous le réticule et la lecture est immédiate.     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Fraction du no man's land que la ligne de visée doit AU MOINS atteindre au sol ⚙ — voir la mesure
# dans `grenade_aim_point`, où deux seuils plus « évidents » se sont révélés l'un trop strict et
# l'autre inatteignable.
const GRENADE_MIN_REACH := 0.4
# Au-dessus de ce site, on vise le ciel ⚙ — un chouïa au-dessus de l'horizontale, parce qu'une
# cloche part LÉGÈREMENT vers le haut et qu'un seuil pile à 0° passerait au rouge à chaque lancer
# tendu.
const SKY_TOLERANCE_DEG := 2.0
const COL_GRENADE_OK := Color(0.94, 0.76, 0.32)
const COL_GRENADE_OUT := Color(0.86, 0.29, 0.25)
# Deux explosions simultanées au maximum (bon de commande §C.2) : au-delà, ce sont deux grenades
# tombées à 0,1 s l'une de l'autre, et la troisième n'ajouterait que du bruit.
const EXPLOSION_POOL := 2
# ╔═ LA SECOUSSE — MODÈLE « TRAUMA » CONSERVÉ, SORTIE RE-FONDÉE EN ÉCRAN (§8.151 LOT B) ══════════╗
# ║ v1 (§8.141) translatait l'ŒIL 3D : la ligne de mire restait juste (aucune rotation), mais le   ║
# ║ RÉTICULE — projeté depuis une DIRECTION, invariante par translation — ne suivait PAS le monde  ║
# ║ secoué : jusqu'à ~7 px de désaccord transitoire entre la croix et l'image, au moment précis    ║
# ║ d'une riposte. Le cahier §4.2 tranche : on translate l'IMAGE ENTIÈRE, monde + réticule         ║
# ║ ENSEMBLE. La caméra ne bouge donc PLUS DU TOUT (ni translation, ni lacet/site — §8.141.6) :    ║
# ║ ce script AVANCE le trauma (impulsions et décroissance inchangées) et PUBLIE un décalage       ║
# ║ ÉCRAN (`shake_screen_px`) que l'hôte applique d'un seul geste aux couches ET au réticule.      ║
# ║ Le bruit vient de `hash_noise` (déterministe, aucun RNG global) : les captures du LOT E        ║
# ║ rejouent la même secousse au bit près — un `sin` d'horloge accumulée l'aurait permis aussi,    ║
# ║ mais le cahier §4.1 impose la même source de bruit pour TOUT le feel.                          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const SHAKE_DECAY := 3.2          # décroissance exponentielle du « trauma » ⚙
# Amplitude ÉCRAN ⚙, en fraction de hauteur : l'équivalent MESURÉ de l'ancienne translation d'œil
# (0,06 m à ~10 m = atan(0.06/10) = 0,34° ≈ 6,7 px en 1080p — la conversion du bon de commande).
const SHAKE_PX_RATIO := 6.7 / 1080.0
# Cadence du bruit ⚙ : ~9 cellules de hash_noise par seconde ≈ l'ancien sin à 26 rad/s (4,1 Hz)
# une fois le lissage de Hermite passé ; 1,37 d'écart entre axes — à cadence égale, l'œil lirait
# une diagonale rectiligne (« glissement »), pas une secousse.
const SHAKE_NOISE_RATE := 9.0
const SHAKE_SEED_X := 8151
const SHAKE_SEED_Y := 8152
# Impulsions ⚙ : dans le rayon · ma tranchée touchée ailleurs · au-delà, rien.
const SHAKE_ON_ME := 0.4
const SHAKE_ON_MY_TRENCH := 0.15
const SHAKE_RANGE := 15.0
# ╔═ LE FEEL DE CAMÉRA (poussé par l'hôte, §8.151) — LES DEUX SEULES LIBERTÉS DE LA CAMÉRA ═══════╗
# ║ ROULIS : rotation autour de l'AXE DE VISÉE (le Z local), plafonnée ±0,3° ICI, à l'application  ║
# ║ — aucun appelant ne peut dépasser. Le centre de l'image est invariant par ce roulis, et le     ║
# ║ réticule (projeté par la même caméra) tourne AVEC le monde : la relation visée/pixel tient.    ║
# ║ PUNCH DE FOV : le rayon CENTRAL est invariant par FOV ; l'écartement de dispersion du réticule ║
# ║ suit `camera_fov()`, donc le vrai FOV du moment — l'honnêteté de §5.4 est conservée.           ║
# ║ Un offset de LACET/SITE, lui, déplacerait le centre : c'est le §8.141.6, et c'est NON.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const FEEL_ROLL_CAP_DEG := 0.3
const FEEL_FOV_OFFSET_MAX := 3.0

var _viewport: SubViewport
var _root: Node3D
var _camera: Camera3D
var _blockout: Node3D
var _enemy: Node3D
var _enemy_placeholder: Node3D
var _enemy_mesh: MeshInstance3D
var _enemy_helmet: MeshInstance3D
var _enemy_sprite: Sprite3D
var _viewmodel: Node3D
var _laser: MeshInstance3D
var _tracers: Array[MeshInstance3D] = []
var _grenades: Array[MeshInstance3D] = []
var _markers: Array[Node3D] = []
# --- §8.141 : la visée de grenade, les explosions, la secousse ------------------------------------
var _aim_decal: Node3D
var _explosions: Array = []
# Traçantes LOCALES : dessinées dès le clic, sans attendre l'aller-retour serveur (cf. le pavé de
# `notify_local_shot`). Elles ne décident aucune touche — elles disent seulement « j'ai tiré ».
var _local_tracers: Array = []
# RAYON D'ACTION EN MÈTRES-MONDE — posé par l'hôte depuis `rules.grenade.radius_m`. La valeur de
# départ n'est qu'un repli le temps que `trench_init` arrive : dès la première frame de duel réel,
# c'est le registre SERVEUR qui décide de ce qui est dessiné (invariant d'honnêteté §C.1).
var _grenade_radius := 2.5
var _shake := 0.0                 # « trauma » courant, 0..1
var _shake_time := 0.0            # horloge de secousse : n'avance QUE pendant le trauma (delta cumulés)
var _shake_px := Vector2.ZERO     # décalage ÉCRAN publié à l'hôte — l'œil 3D, lui, ne bouge plus
var _shake_scale := 1.0           # intensité F10 (`feel_shake`, 0..2)
var _feel_roll_deg := 0.0         # roulis courant (±0,3° max), poussé par l'hôte
var _feel_fov_offset := 0.0       # punch de FOV courant (degrés au-dessus du FOV réglé)
var _fov_base := CAMERA_FOV       # le FOV du panneau F10 — `_camera.fov` = base + punch

# Pose courante, INTERPOLÉE (la caméra ne saute jamais d'une position à l'autre).
var _pose_pos := 2
var _pose_stance := "up"
var _cam_target := Vector3.ZERO
var _cam_current := Vector3.ZERO
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _reduced_motion := false
var _enemy_alpha := 0.0
var _enemy_last_pos := 2.0
var _enemy_x := 0.0                # abscisse RENDUE, tweenée par pas discrets (cf. `_stepped_enemy_x`)
# Réglages VIVANTS, posés par le panneau F10 (`apply_tuning`). Les constantes ne sont que leur
# valeur de départ.
var _follow := AIM_FOLLOW
var _follow_max := Geo.camera_follow_max_deg()

# --- Machine à frames du soldat (§8.138) ----------------------------------------------------------
# `_enemy_painted` = TRUE quand `enemy_idle.png` existe. C'est un OU EXCLUSIF assumé : soit tout le
# soldat est peint, soit tout le soldat est en primitives. Jamais un panaché.
var _enemy_painted := false
var _enemy_frame := Sprites.ENEMY_IDLE
var _enemy_frame_left := 0.0
var _enemy_dying := false
var _enemy_aiming := false
var _enemy_aiming_prev := false   # §8.153 : pour VOIR la bascule, pas seulement l etat
var _enemy_dead := false
var _enemy_tint := COL_DANGER

# --- §8.141 : LE PAS QUI COÛTE, ET LA SILHOUETTE QUI SE DÉTACHE ----------------------------------
# ╔═ POURQUOI CES QUATRE NŒUDS EXISTENT ══════════════════════════════════════════════════════════╗
# ║ Ralentir la simulation (`move_ticks` 3 → 4) répond à « il bouge trop vite » côté RÈGLE. Mais un ║
# ║ pas qui ne coûte RIEN à l'œil se lit encore comme une téléportation, même à 2,5 pas/s : entre    ║
# ║ deux poses discrètes il n'y avait qu'un fondu de 0,15 s, sans aucun événement. On donne donc un  ║
# ║ PRIX visuel et sonore à chaque pas — poussière, affaissement, bruit sourd — pour que l'œil       ║
# ║ compte les pas au lieu de constater des positions.                                               ║
# ║ Et le LISERÉ répond à l'autre moitié du verdict : à 67 px sur un parapet de jute très texturé,   ║
# ║ la silhouette se CONFOND. Un rim clair, c'est ce qui fait la différence entre « je le vois » et  ║
# ║ « je le cherche ». Il n'apparaît QUE quand l'adversaire est rendu — c'est-à-dire debout et       ║
# ║ révélé — donc il ne trahit jamais un accroupi (l'invariant §1.6 n'est pas contournable ici : le  ║
# ║ client n'a même pas la position d'un accroupi).                                                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
var _enemy_rim: Sprite3D
var _enemy_dust: GPUParticles3D
var _enemy_muzzle: MeshInstance3D
# Dernière position ENTIÈRE observée : c'est son changement qui définit « un pas », pas le glissé.
var _enemy_step_pos := -1
var _enemy_dip := 0.0          # affaissement vertical résiduel (m), décroissant
# §8.153 — LA FOULÉE. Une horloge de pas, et une trainee de frame. Voir `_animer_foulee`.
var _enemy_stride := 0.0       # temps ÉCOULÉ dans la foulée en cours (s) ; < 0 = aucune
var _enemy_breath := 0.0       # phase de respiration, en secondes, jamais remise a zero
var _enemy_fade: Sprite3D      # la frame SORTANTE, qui s efface — la trainee
var _enemy_fade_left := 0.0
var _enemy_muzzle_left := 0.0  # durée restante du départ de feu adverse (s)

# Épaisseur du liseré ⚙, en fraction de la demi-largeur du sprite. 0,045 rend ~1,5 px au plus près
# et ~0,9 px au coin le plus lointain : « 1 px » au sens du bon de commande, sur toute l'arène.
const ENEMY_RIM_GROW := 0.045
# Or DÉSATURÉ : assez clair pour trancher sur le jute, assez éteint pour ne pas ressembler à une
# surbrillance de jeu d'arcade — on souligne une silhouette, on ne la sélectionne pas.
const ENEMY_RIM_COLOR := Color(0.82, 0.76, 0.60)
# Profondeur de l'affaissement au poser du pied ⚙ et sa constante de rappel. 4 cm sur une silhouette
# de 1,80 m : invisible en photo, parfaitement lisible en mouvement — c'est le but.
# ╔═ 🎞 §8.153 — « FLUIDIFIER LES FRAMES DE L ADVERSAIRE » ════════════════════════════════════╗
# ║ Verdict de Hakim : le soldat adverse manque de mouvement. Il n a que SIX images peintes, et  ║
# ║ deux seulement sont des etats permanents (`idle`, `aim`) : entre les deux, un CHANGEMENT SEC.║
# ║ Pendant ce temps sa POSITION glisse en continu — c est ce desaccord qui se lit « il flotte ».║
# ║                                                                                              ║
# ║ ⛔ CE QU ON NE PEUT PAS FAIRE, ET POURQUOI. Toute animation LATERALE ou VERS LE HAUT de la   ║
# ║ silhouette rendue est un MENSONGE sur la fenetre de tir : le serveur resout les touches sur  ║
# ║ une boite fixe (`SILHOUETTE_HALF_WIDTH` vaut exactement la demi-largeur du sprite depuis le  ║
# ║ §8.141.8). Un simple roulis de 3° elargirait la silhouette rendue de 2,9 cm au-dela de sa     ║
# ║ fenetre — la meme famille de defaut que le billboard du §8.141.7, en plus petit.             ║
# ║ ⭐ Le mouvement VERS LE BAS, lui, est honnete : il rend la cible PLUS PETITE que sa fenetre,  ║
# ║ jamais plus grande. C est deja le principe de `_enemy_dip`, et c est le seul axe qu on       ║
# ║ s autorise. Toute la fluidite se joue donc dans le TEMPS, pas dans l espace.                 ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════════╝
# Duree d une foulee ⚙ — celle du `PAS_TOURNANT` de la bibliotheque de clips. Au-dela, une
# foulee deborderait sur la suivante aux ~2,2 pas/s du bot et redeviendrait une marche continue,
# c est-a-dire le glisse que le §8.141 a justement retire.
const ENEMY_STRIDE_TIME := 0.42
# Respiration : 4,2 s par cycle (14 respirations/min, un homme au repos mais tendu), amplitude
# 8 mm. ⚠️ Vers le BAS uniquement, comme tout le reste.
const ENEMY_BREATH_PERIOD := 4.2
const ENEMY_BREATH_DIP := 0.008
# Duree de la trainee entre deux frames ⚙. 0,10 s = 6 images a 60 Hz : assez pour que l oeil lise
# un passage et non un clignement, assez court pour ne pas laisser un fantome lisible.
const ENEMY_FADE_TIME := 0.10
const ENEMY_STEP_DIP := 0.04
const ENEMY_STEP_DIP_DECAY := 14.0
# Durée du départ de feu adverse ⚙ — deux frames à 60 Hz. Plus long, ça devient une lampe.
const ENEMY_MUZZLE_TIME := 0.035
# Au-delà de cette distance, le pas adverse est INAUDIBLE ⚙ (au-delà du front le plus large).
const STEP_AUDIBLE_RANGE := 22.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport = $SubViewport
	_root = $SubViewport/Arena
	_build()


func _build() -> void:
	_blockout = BlockoutScene.instantiate()
	_root.add_child(_blockout)

	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.near = CAMERA_NEAR
	_camera.far = 400.0
	_root.add_child(_camera)
	_cam_current = Geo.eye_position(_pose_pos, _pose_stance)
	_cam_target = _cam_current

	_build_fog()
	_build_enemy()
	_build_viewmodel()
	_build_pools()


# La brume de profondeur, posée sur l'Environment de la scène. En code plutôt que dans le `.tscn`
# pour qu'elle vive à côté des cotes qui la justifient (`FOG_BEGIN` se lit contre les 35 m du no
# man's land) — et parce que ce chantier est 100 % code-driven de bout en bout.
func _build_fog() -> void:
	var holder := _root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if holder == null or holder.environment == null:
		return
	var env := holder.environment
	# L'AMBIANCE, accordée au panorama elle aussi : sa teinte est relevée sur le ciel MÉDIAN (RGB
	# 117/139/145). À 1,35 en gris neutre — le réglage d'avant le pivot — la boue ressortait plus
	# claire que le ciel derrière elle et se lisait comme du béton pâle. Une lumière de ciel couvert
	# est douce ET froide : c'est la teinte qui fait le travail, pas l'énergie.
	env.ambient_light_color = Color(0.460, 0.543, 0.568)
	env.ambient_light_energy = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = FOG_COLOR
	env.fog_depth_begin = FOG_BEGIN
	env.fog_depth_end = FOG_END
	env.fog_depth_curve = 0.85
	env.fog_sky_affect = 0.0
	# ⚙ DENSITÉ RELEVÉE À 3,0 PAR LA MESURE, PAS PAR LA DOCUMENTATION. À 1,0, le sol sortait à
	# RGB 112/113/112 au ras de l'horizon quand le ciel qui le touche vaut 69/87/97 : un liseré
	# clair et neutre courait le long de la ligne d'horizon, exactement là où la 3D doit se fondre
	# dans la peinture. La proportion de brume atteinte à 300 m se mesurait à ~50 %, pas ~93 % :
	# `fog_density` n'est pas un simple facteur, elle entre dans une exponentielle. À 3,0 on obtient
	# les ~94 % voulus. (Mesure refaite à chaque retouche : cf. le contrôle d'horizon de
	# `preview_trench.gd`.)
	env.fog_density = 3.0
	# ╔═ ⚠️⚠️ `fog_sky_affect` NE PROTÈGE PAS NOTRE CIEL — VU EN CAPTURE, PAS AUTREMENT ══════════╗
	# ║ Ce réglage ne concerne que le CIEL DE L'ENVIRONNEMENT (`BG_SKY`). Le nôtre est un MAILLAGE  ║
	# ║ posé à 300 m : pour le moteur, c'est de la géométrie lointaine comme une autre, et la brume ║
	# ║ s'y applique à ~95 %. Résultat de la première capture : un aplat gris uniforme, ni nuages,  ║
	# ║ ni ruines, ni cheminées — le panorama qu'on venait de payer, intégralement effacé. Aucune   ║
	# ║ ERROR, aucun test au rouge : il fallait REGARDER l'image.                                   ║
	# ║ On exempte donc l'arc de ciel, matériau par matériau (`disable_fog`), et c'est la brume qui  ║
	# ║ vient à LUI : `FOG_COLOR` est relevée sur sa bande d'horizon.                                ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝


# =================================================================================================
# PLACEHOLDERS — le jeu est JOUABLE avant le premier asset (doctrine du dépôt)
# =================================================================================================
func _material(color: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# Le SOLDAT ADVERSE — DEUX corps possibles sous le même nœud, et un seul allumé (§8.138) :
#   (a) le SPRITE PEINT billboard, dès que `enemy_idle.png` est déposé ;
#   (b) le PLACEHOLDER capsule + casque, sinon — le duel reste jouable et recettable sans un asset.
# Le nœud `_enemy` lui-même est aux PIEDS du soldat (ancrage `enemy_p{i}` du blockout) : c'est la
# seule chose que le reste du script manipule, les deux corps se débrouillent avec leur hauteur.
func _build_enemy() -> void:
	_enemy = Node3D.new()
	_enemy.name = "EnemySoldier"
	_root.add_child(_enemy)

	_enemy_placeholder = Node3D.new()
	_enemy_placeholder.name = "Placeholder"
	_enemy.add_child(_enemy_placeholder)

	var body := CapsuleMesh.new()
	body.radius = Geo.SILHOUETTE_HALF_WIDTH
	body.height = 1.75
	_enemy_mesh = MeshInstance3D.new()
	_enemy_mesh.mesh = body
	_enemy_mesh.material_override = _enemy_material(COL_DANGER)
	_enemy_mesh.position = Vector3(0.0, 0.875, 0.0)
	_enemy_placeholder.add_child(_enemy_mesh)

	var helmet := SphereMesh.new()
	helmet.radius = 0.19
	helmet.height = 0.30
	_enemy_helmet = MeshInstance3D.new()
	_enemy_helmet.mesh = helmet
	_enemy_helmet.material_override = _enemy_material(COL_DANGER.darkened(0.35))
	_enemy_helmet.position = Vector3(0.0, 1.78, 0.0)
	_enemy_placeholder.add_child(_enemy_helmet)

	_build_enemy_sprite()
	_build_enemy_perception()
	_enemy_painted = Sprites.enemy_available()
	_enemy_placeholder.visible = not _enemy_painted
	_enemy_sprite.visible = _enemy_painted
	_enemy_rim.visible = _enemy_painted
	_apply_enemy_frame()
	_enemy.visible = false


# Le BILLBOARD. Trois réglages portent tout le lot — chacun a une raison d'être exactement celle-là.
func _build_enemy_sprite() -> void:
	_enemy_sprite = Sprite3D.new()
	_enemy_sprite.name = "PaintedSoldier"
	# 1. BILLBOARD : la frame fait toujours FACE à la caméra. C'est ce qui rend le flip horizontal
	#    inutile — le quad est reconstruit depuis la base de la vue, la texture n'est jamais miroir,
	#    et un sprite « facing the viewer » (convention du guide de production) fait donc bien face
	#    au joueur depuis la tranchée d'en face, quelle que soit la position occupée.
	# ⚠️ FIXED_Y et non ENABLED (§8.141) : un billboard PLEIN pivote aussi autour de l'horizontale,
	#    donc il se COUCHE vers la caméra dès qu'elle pique du nez. Sa hauteur projetée reste alors
	#    constante quel que soit le site — c'est-à-dire que le soldat ne s'enfonce PLUS derrière le
	#    parapet quand on lève les yeux, alors que la table angulaire du serveur, elle, continue de
	#    l'occulter. Le rendu mentirait sur la découpe qui décide des touches. Verrouillé sur la
	#    verticale, le soldat tourne pour me faire face et reste DEBOUT : l'image et la règle
	#    disent la même chose. (Le débattement de site est de ±14°, et le panneau F10 peut faire
	#    tourner la caméra bien au-delà — l'écart n'a rien de théorique.)
	# ╔═ ⚠️⚠️ PLUS DE BILLBOARD DU TOUT — IL RENDAIT LES CÔTÉS INVISABLES (§8.141.7) ═══════════════╗
	# ║ Verdict de partie réelle : « quand je vise à droite ou à gauche, impossible de toucher le    ║
	# ║ soldat ; je vois le projectile partir vers lui, il ne lui fait aucun dégât ».                 ║
	# ║ MESURÉ (`probe_trench_aim`), largeur ANGULAIRE de la silhouette RENDUE contre la fenêtre de   ║
	# ║ tir que le serveur résout, depuis la pose centrale :                                          ║
	# ║      position 2 (en face) 4,68° contre 3,44° → **1,36×**                                      ║
	# ║      position 4 (au bord) 4,93° contre 2,35° → **2,10×**                                      ║
	# ║                                                                                               ║
	# ║ LA CAUSE EST GÉOMÉTRIQUE, PAS COSMÉTIQUE. La table angulaire décrit une silhouette PLANE à Z  ║
	# ║ constant, large de 0,60 m SUR L'AXE X du monde. Vue de biais, sa largeur apparente se réduit  ║
	# ║ en `0,60 × cos(θ)` — à 34° de lacet, 0,50 m. Un BILLBOARD, lui, pivote pour faire toujours    ║
	# ║ FACE à l'œil : il présente sa largeur PLEINE quel que soit l'angle. Plus on vise sur le côté, ║
	# ║ plus l'image ment — et le joueur vise un soldat deux fois plus large que sa fenêtre réelle.   ║
	# ║                                                                                               ║
	# ║ ⚠️ On retire donc le billboard et on fixe le sprite DANS LE PLAN DE LA TABLE (demi-tour pour  ║
	# ║ faire face à ma tranchée). Il se raccourcit alors exactement comme la fenêtre : l'image et la ║
	# ║ règle disent enfin la même chose. Et c'est aussi plus juste au sens du monde — un soldat dans ║
	# ║ une tranchée fait face au no man's land, pas à moi personnellement.                            ║
	# ║ ⚠️ Le §8.141 avait mis FIXED_Y « pour ne pas mentir sur la découpe du parapet » : c'était la  ║
	# ║ bonne intuition (l'image doit suivre la règle) appliquée au mauvais axe. Elle vaut aussi en   ║
	# ║ LARGEUR, et en largeur seule la suppression du billboard la respecte.                          ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	_enemy_sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# Demi-tour : un `Sprite3D` non-billboard regarde +Z, c'est-à-dire l'ARRIÈRE de sa tranchée.
	_enemy_sprite.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	# 2. ALPHA_CUT_DISABLED = fondu alpha classique, et NON `DISCARD`/`OPAQUE_PREPASS` :
	#    • les bords sont DOUX (sortie rembg antialiasée) — un seuil les redécouperait en escalier ;
	#    • c'est la SEULE option qui laisse vivre le fondu de redaction (`modulate.a`) : sous un
	#      seuil, l'adversaire ne s'effacerait pas, il DISPARAÎTRAIT d'un coup à mi-fondu.
	#    L'occultation par le parapet reste juste : un objet transparent est TESTÉ en profondeur même
	#    s'il n'y écrit pas, et le parapet est opaque. Le tri n'est pas un sujet : il y a UN sprite.
	# ⚠️ ARBITRAGE §8.141 : le bon de commande demandait d'essayer `alpha_scissor` (seuil 0,5)
	#    D'ABORD, et de ne garder le blend que si le seuil crénelait à l'œil. Le départage n'est pas
	#    esthétique, il est FONCTIONNEL, et il tombe avant la capture : un seuil rend le fondu de
	#    redaction BINAIRE. L'adversaire qui s'accroupit ne s'effacerait plus derrière son parapet —
	#    il clignerait hors d'existence à mi-fondu, ce qui se lit comme un décrochage réseau. La
	#    sonde a mesuré les deux (quad scissor 61/61/59, quad blend 61/62/60) : à qualité d'image
	#    égale, on garde celui qui préserve une information de jeu. Le coût de tri est nul — il y a
	#    UN sprite dans la scène.
	_enemy_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	# 3. NON ÉCLAIRÉ, comme le placeholder et pour la MÊME raison (défaut n° 3 vu en CAPTURE) : à
	#    35 m la part exposée du soldat fait ~0,9°, soit une vingtaine de pixels. Éclairé, il tombe
	#    dans l'ombre du parapet et devient littéralement invisible. La lumière du personnage est
	#    DÉJÀ PEINTE dans la frame — la rééclairer serait de toute façon la peindre deux fois.
	_enemy_sprite.shaded = false
	_enemy_sprite.double_sided = true
	# ╔═ ⚠️⚠️ « LE SOLDAT EST UN RECTANGLE BLANC » — DIAGNOSTIC INFIRMÉ PAR LA MESURE (§8.141) ════╗
	# ║ Le §8 du rapport de pivot concluait que le sprite s'échantillonnait en blanc opaque, sur la  ║
	# ║ foi d'un relevé « pixels rendus ≈ modulation × BLANC », et léguait une piste : remplacer le  ║
	# ║ `Sprite3D` par un quad + `StandardMaterial3D`. Les deux ont été éprouvés avant d'être crus.  ║
	# ║                                                                                               ║
	# ║ `tools/probe_trench_quad.tscn` — même texture, même SubViewport, quatre modes de rendu côte  ║
	# ║ à côte : `Sprite3D` tel qu'en jeu **58/59/58**, quad scissor 61/61/59, quad blend 61/62/60,  ║
	# ║ `Sprite3D` en NEAREST 59/60/58 — pour une source à 60/61/60. Les QUATRE peignent, écart-type ║
	# ║ de luminance 0,13. Le mode de rendu n'a jamais été en cause.                                  ║
	# ║ `tools/probe_trench_soldier.tscn` — dans le VRAI duel, par différence (sprite visible /       ║
	# ║ masqué), aux trois profondeurs (monde 3D seul · écran habillé · écran nu) : RGB 98/76/71,    ║
	# ║ σ 0,17, une image peinte. La loupe ×8 montre un homme au casque, l'arme à l'épaule.           ║
	# ║                                                                                               ║
	# ║ ⚠️ CE QUE LE §8 A PROBABLEMENT MESURÉ : le PARAPET DE JUTE, teinté `COVER_TINT` (1,70/1,67/  ║
	# ║ 1,62 — un multiplicateur d'albédo SUPÉRIEUR À 1). Il occupe la majeure partie du quad du      ║
	# ║ sprite, il est tan clair, et il donne exactement le « blanc teinté d'or » relevé. Le harnais  ║
	# ║ de l'époque n'y aidait pas : il ne poussait qu'UN état, donc `_enemy_alpha` plafonnait à      ║
	# ║ 0,12 et le soldat restait ENFONCÉ de 0,48 m derrière les sacs — invisible pour de bon.        ║
	# ║ ⚠️ LA LEÇON : une mesure qui ne SOUSTRAIT pas le fond ne mesure pas le sujet. Les deux        ║
	# ║ sondes ci-dessus travaillent par DIFFÉRENCE, et c'est pour cela qu'elles ont tranché.         ║
	# ║ Le vrai défaut de taille était ailleurs, et il est réel : cf. `Sprites.pixel_size_for()`.     ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	_enemy_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_enemy_sprite.pixel_size = Sprites.PIXEL_SIZE
	_enemy_sprite.centered = true
	_enemy.add_child(_enemy_sprite)


# LE LISERÉ, LA POUSSIÈRE ET LE DÉPART DE FEU (§8.141).
func _build_enemy_perception() -> void:
	# --- LISERÉ : un DOUBLE du sprite, à peine plus grand, teinté, dessiné DESSOUS ---------------
	# ⚖ ARBITRAGE — le bon de commande demandait « un shader outline sur le quad ». Un `Sprite3D`
	# construit son propre matériau (billboard, texture, alpha) : lui poser un `material_override`
	# le remplacerait ENTIÈREMENT, donc il faudrait réécrire le billboard et le sampling à la main
	# pour gagner un contour. Un double homothétique donne le même résultat visible avec une
	# géométrie qu'on maîtrise, et il hérite gratuitement de toutes les propriétés qu'on vient de
	# régler sur l'original — filtre, billboard vertical, mode alpha. C'est le même dessin, et c'est
	# une pièce de moins qui peut diverger.
	# ⚠️ `render_priority` NÉGATIF : deux quads coplanaires transparents ne sont pas départagés par
	# le tampon de profondeur (l'alpha n'y écrit pas). Sans priorité explicite, l'ordre de dessin
	# dépendrait de l'ordre de la scène — et un liseré dessiné PAR-DESSUS le soldat le repeindrait.
	_enemy_rim = Sprite3D.new()
	_enemy_rim.name = "PaintedSoldierRim"
	_enemy_rim.billboard = _enemy_sprite.billboard
	_enemy_rim.rotation_degrees = _enemy_sprite.rotation_degrees
	_enemy_rim.alpha_cut = _enemy_sprite.alpha_cut
	_enemy_rim.shaded = false
	_enemy_rim.double_sided = true
	_enemy_rim.texture_filter = _enemy_sprite.texture_filter
	_enemy_rim.centered = true
	_enemy_rim.render_priority = -1
	_enemy_rim.scale = Vector3(1.0 + ENEMY_RIM_GROW, 1.0 + ENEMY_RIM_GROW, 1.0)
	_enemy.add_child(_enemy_rim)

	# --- LA TRAINEE (§8.153) : la frame SORTANTE, qui s efface sous la nouvelle ----------------
	# ⚠️ La NOUVELLE frame est posee a pleine opacite tout de suite, et c est l ANCIENNE qui
	# s efface par-dessous. Un vrai fondu croise (les deux a mi-alpha) additionnerait deux
	# silhouettes differentes et donnerait un homme a deux tetes pendant 0,1 s. Ici la pose
	# courante est toujours FRANCHE ; ce qui traine, c est celle qu on vient de quitter.
	# ⛔ `render_priority` 0 contre 1 pour le sprite : deux quads coplanaires transparents ne sont
	# pas departages par la profondeur, il faut le dire explicitement (meme piege que le lisere).
	_enemy_fade = Sprite3D.new()
	_enemy_fade.name = "PaintedSoldierFade"
	_enemy_fade.billboard = _enemy_sprite.billboard
	_enemy_fade.rotation_degrees = _enemy_sprite.rotation_degrees
	_enemy_fade.alpha_cut = _enemy_sprite.alpha_cut
	_enemy_fade.shaded = false
	_enemy_fade.double_sided = true
	_enemy_fade.texture_filter = _enemy_sprite.texture_filter
	_enemy_fade.centered = true
	_enemy_fade.render_priority = 0
	_enemy_fade.visible = false
	_enemy.add_child(_enemy_fade)
	_enemy_sprite.render_priority = 1

	# --- POUSSIÈRE AU PIED : 8 grains, 0,3 s, UN SEUL COUP par pas ------------------------------
	# ⚠️ `one_shot` + `restart()` et non un émetteur permanent : un nuage continu ferait un soldat
	# qui fume en permanence, et surtout il ne dirait plus RIEN — un signal qui ne s'éteint jamais
	# n'est pas un signal.
	_enemy_dust = GPUParticles3D.new()
	_enemy_dust.name = "StepDust"
	_enemy_dust.amount = 8
	_enemy_dust.lifetime = 0.30
	_enemy_dust.one_shot = true
	_enemy_dust.emitting = false
	_enemy_dust.explosiveness = 1.0
	var dust_mesh := QuadMesh.new()
	dust_mesh.size = Vector2(0.10, 0.10)
	_enemy_dust.draw_pass_1 = dust_mesh
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.52, 0.46, 0.38, 0.55)
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.disable_fog = true
	dust_mat.vertex_color_use_as_albedo = true
	_enemy_dust.draw_pass_1.surface_set_material(0, dust_mat)
	var dust_process := ParticleProcessMaterial.new()
	dust_process.direction = Vector3(0.0, 1.0, 0.0)
	dust_process.spread = 55.0
	dust_process.initial_velocity_min = 0.25
	dust_process.initial_velocity_max = 0.60
	dust_process.gravity = Vector3(0.0, -1.2, 0.0)     # elle retombe : c'est de la terre, pas de la fumée
	dust_process.scale_min = 0.6
	dust_process.scale_max = 1.5
	dust_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	dust_process.emission_sphere_radius = 0.16
	# Fondu jusqu'à zéro : un grain qui disparaît d'un coup se lit comme un défaut d'affichage.
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	dust_process.color_ramp = ramp
	_enemy_dust.process_material = dust_process
	_enemy.add_child(_enemy_dust)

	# --- DÉPART DE FEU ADVERSE : la parité d'information -----------------------------------------
	# Le bot « voit » que je tire (ma traçante part de ma position). Sans cette lueur, je n'avais que
	# le SON pour savoir que lui tirait — alors que la traçante adverse, elle, met un temps de vol à
	# arriver. Un duel où l'un des deux camps dispose d'une information que l'autre n'a pas n'est
	# plus un duel : c'est un déséquilibre déguisé en habillage.
	var flash := SphereMesh.new()
	flash.radius = 0.10
	flash.height = 0.20
	flash.radial_segments = 8
	flash.rings = 4
	_enemy_muzzle = MeshInstance3D.new()
	_enemy_muzzle.name = "EnemyMuzzle"
	_enemy_muzzle.mesh = flash
	_enemy_muzzle.material_override = _material(Color(1.0, 0.88, 0.55), true)
	_enemy_muzzle.visible = false
	_root.add_child(_enemy_muzzle)


# Pose la texture de la frame courante, SON ÉCHELLE, et l'ancrage au sol qui en découle.
# ⚠️ Le quad est CENTRÉ sur son origine : pour que les PIEDS tombent sur l'ancrage du blockout, on
# remonte le sprite d'une demi-hauteur.
# ⚠️⚠️ L'ÉCHELLE EST DÉSORMAIS PAR ÉTAT (`Sprites.pixel_size_for`), et ce n'est pas un raffinement :
# la frame `aim` était livrée à 880 px pour un contrat à 1024, et l'adversaire perdait 25 cm — donc
# 43 % de sa part exposée — au moment précis où il devient une cible. Le pavé de `trench_sprites.gd`
# porte la mesure des six frames.
func _apply_enemy_frame() -> void:
	if not _enemy_painted or _enemy_sprite == null:
		return
	var frame := Sprites.enemy_texture(_enemy_frame)
	if frame == null:
		return
	# On garde la frame SORTANTE avec sa propre echelle et son propre ancrage : les six images
	# n ont ni la meme hauteur en pixels ni le meme centre, et recopier seulement la texture
	# ferait sauter la trainee d une pose a l autre.
	if _enemy_fade != null and _enemy_sprite.texture != null \
			and _enemy_sprite.texture != frame:
		_enemy_fade.texture = _enemy_sprite.texture
		_enemy_fade.pixel_size = _enemy_sprite.pixel_size
		_enemy_fade.position = _enemy_sprite.position
		_enemy_fade_left = ENEMY_FADE_TIME
	var pixel_size: float = Sprites.pixel_size_for(_enemy_frame, frame.get_height())
	_enemy_sprite.texture = frame
	_enemy_sprite.pixel_size = pixel_size
	_enemy_sprite.position = Vector3(0.0, float(frame.get_height()) * pixel_size * 0.5, 0.0)
	# Le liseré suit la frame COURANTE, sinon un soldat qui épaule porterait le contour de sa pose
	# précédente — un fantôme d'une frame de retard, visible précisément quand on le regarde.
	if _enemy_rim != null:
		_enemy_rim.texture = frame
		_enemy_rim.pixel_size = pixel_size
		_enemy_rim.position = _enemy_sprite.position


# Matériau du soldat PLACEHOLDER : NON ÉCLAIRÉ, à dessein.
# ⚠️ À 35 m, la part exposée de la silhouette ne fait qu'environ 0,9° — soit une vingtaine de
# pixels en 1920. Un placeholder ÉCLAIRÉ tombait dans l'ombre du parapet et devenait littéralement
# invisible en greybox (vu en CAPTURE) : impossible de recetter le duel sans assets, alors que
# « jouable en placeholders » est une exigence du chantier. Le vrai `enemy_soldier.glb` (§7.2)
# apportera son propre matériau éclairé — cette ligne ne le concerne pas.
func _enemy_material(color: Color) -> StandardMaterial3D:
	var m := _material(color)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# Le VIEWMODEL — primitives assemblées, une silhouette par arme (§5.4). Enfant de la CAMÉRA :
# il suit donc la pose et le suivi de visée sans une ligne de synchronisation.
func _build_viewmodel() -> void:
	_viewmodel = Node3D.new()
	_viewmodel.name = "Viewmodel"
	_camera.add_child(_viewmodel)
	# ⚠️ CADRAGE : à 0,45 m de l'œil, l'arme occupait un quart de l'écran en bloc gris illisible
	# (vu en CAPTURE). À 0,72 m et légèrement rentrée, sa SILHOUETTE se lit — ce qui est tout ce
	# qu'on demande à un placeholder, et ce qui permet de recetter l'escalade sans assets.
	# ⚠️ CADRAGE, deux fois repris EN CAPTURE. Une arme posée dans l'axe de la vue se voit
	# quasiment BOUT-À-BOUT : la perspective en fait un bloc gris sans forme, et on ne distingue
	# plus une VIPÈRE d'un CONDOR — or reconnaître son arme d'un coup d'œil est ce qui permet de
	# recetter l'escalade AVANT le premier asset. On la décale donc en bas à droite et on la
	# présente de TROIS QUARTS : c'est la silhouette qui porte l'information, pas le volume.
	_viewmodel.position = Vector3(0.30, -0.27, -0.52)
	_viewmodel.rotation_degrees = Vector3(-6.0, -17.0, 0.0)
	set_weapon("vipere")


# Silhouettes DISTINCTES pour les 4 armes — le joueur doit reconnaître son arme au coup d'œil,
# même en placeholder (c'est la condition pour recetter l'escalade sans assets).
func set_weapon(weapon_id: String) -> void:
	if _viewmodel == null:
		return
	for child in _viewmodel.get_children():
		child.queue_free()
	# LONGUEUR = la variable qui porte l'identité : plus l'arme monte dans l'escalade, plus son
	# canon s'allonge et s'assombrit. Un coup d'œil au coin bas-droit suffit à savoir où on en est.
	var profiles := {
		"vipere": {"len": 0.20, "thick": 0.030, "color": Color(0.52, 0.54, 0.57)},
		"frelon": {"len": 0.32, "thick": 0.034, "color": Color(0.44, 0.48, 0.52)},
		"chacal": {"len": 0.46, "thick": 0.030, "color": Color(0.38, 0.42, 0.46)},
		"condor": {"len": 0.62, "thick": 0.024, "color": Color(0.32, 0.35, 0.39)},
	}
	var p: Dictionary = profiles.get(weapon_id, profiles["vipere"])
	var length := float(p["len"])
	var thick := float(p["thick"])

	var barrel := BoxMesh.new()
	barrel.size = Vector3(thick, thick, length)
	var barrel_node := MeshInstance3D.new()
	barrel_node.mesh = barrel
	barrel_node.material_override = _material(p["color"])
	barrel_node.position = Vector3(0.0, 0.0, -length * 0.5)
	_viewmodel.add_child(barrel_node)

	# Le « corps » de l'arme + la main gantée (deux blocs suffisent à lire la prise en main).
	var stock := BoxMesh.new()
	stock.size = Vector3(0.045, 0.070, 0.14)
	var stock_node := MeshInstance3D.new()
	stock_node.mesh = stock
	stock_node.material_override = _material(Color(0.24, 0.26, 0.29))
	stock_node.position = Vector3(0.0, -0.028, 0.035)
	_viewmodel.add_child(stock_node)

	var glove := BoxMesh.new()
	glove.size = Vector3(0.050, 0.055, 0.065)
	var hand := MeshInstance3D.new()
	hand.mesh = glove
	hand.material_override = _material(Color(0.17, 0.16, 0.15))
	hand.position = Vector3(-0.005, -0.055, -length * 0.42)
	_viewmodel.add_child(hand)

	# Le CONDOR porte une lunette : sa silhouette doit crier « précision » de loin.
	if weapon_id == "condor":
		var scope := CylinderMesh.new()
		scope.top_radius = 0.018
		scope.bottom_radius = 0.018
		scope.height = 0.16
		var scope_node := MeshInstance3D.new()
		scope_node.mesh = scope
		scope_node.material_override = _material(Color(0.15, 0.17, 0.20))
		scope_node.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		scope_node.position = Vector3(0.0, 0.038, -0.07)
		_viewmodel.add_child(scope_node)


# La maille UNITAIRE des cercles de zone : un tore plat de rayon extérieur 1,0 m, que `scale` ouvre
# au rayon réel. ⚠️ Unitaire, et c'est le point : une maille déjà dimensionnée obligerait à
# reconstruire le maillage à chaque changement de barème — donc à avoir un endroit de plus où le
# rayon dessiné peut cesser de valoir le rayon des dégâts.
# ╔═ ⚠️⚠️ LES CERCLES DE ZONE SE VOIENT À TRAVERS LES SACS — ET C'EST OBLIGATOIRE ════════════════╗
# ║ Mesuré en posant le décalque : la ligne de vue qui rase l'arête du parapet adverse coupe à     ║
# ║ **1,194 m** au plan des soldats. Le plancher de la tranchée d'en face (y ≈ 0), donc le point    ║
# ║ d'impact d'une grenade, est INTÉGRALEMENT occulté depuis un œil debout. Un cercle soumis au     ║
# ║ tampon de profondeur y serait donc invisible — c'est-à-dire inexistant, dans un lot dont TOUT   ║
# ║ l'objet est de rendre la zone lisible.                                                          ║
# ║ On coupe donc le test de profondeur pour les cercles de zone, et pour eux seuls.                ║
# ║ ⚠️ AUCUNE INFORMATION N'EST DIVULGUÉE : le décalque de VISÉE ne montre que ma propre visée, et  ║
# ║ le marqueur de VOL est déjà public par décision de design (§1.6 : « esquiver DOIT rester        ║
# ║ possible, sinon la grenade cesse d'être l'arme anti-camping et devient une loterie »). On ne    ║
# ║ voit pas à travers un mur : on voit une MENACE que le jeu a décidé d'annoncer.                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _see_through(material: StandardMaterial3D) -> void:
	material.no_depth_test = true
	# Sans priorité explicite, un objet sans test de profondeur se dessine dans un ordre arbitraire
	# par rapport aux autres transparents (traçantes, soldat) : il clignoterait derrière eux.
	material.render_priority = 8


func _ring_mesh() -> TorusMesh:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.90
	ring.outer_radius = 1.0
	ring.rings = 40
	ring.ring_segments = 6
	return ring


# ╔═ ⚠️⚠️ UN CERCLE AU SOL NE SUFFIT PAS : IL FAUT DIRE QU'IL EST *DERRIÈRE* LES SACS ════════════╗
# ║ Verdict de partie réelle : « la grenade n'a pas l'air d'arriver dans la tranchée au niveau du  ║
# ║ soldat, mais plutôt au milieu entre les deux tranchées ». **Hakim a raison, et c'est l'image    ║
# ║ qui ment — pas la règle.** Calcul de projection, œil à 1,70 m, arène 9 m :                     ║
# ║                                                                                                 ║
# ║     sommet du parapet adverse ............ y =  597 px                                          ║
# ║     sol du no man's land, À MI-CHEMIN .... y =  696 px                                          ║
# ║     **le cercle d'impact** ............... y =  725 px   ← 128 px SOUS le parapet               ║
# ║                                                                                                 ║
# ║ Le plancher de la tranchée d'en face se projette DANS LA MÊME BANDE D'ÉCRAN que le sol du       ║
# ║ milieu du terrain. Et comme on a retiré le test de profondeur (sans quoi le cercle serait       ║
# ║ invisible, cf. `_see_through`), plus RIEN ne dit qu'il est derrière les sacs. L'œil le lit donc  ║
# ║ exactement là où Hakim l'a lu. On avait rendu le cercle visible en lui retirant sa profondeur — ║
# ║ il fallait la lui rendre autrement.                                                             ║
# ║                                                                                                 ║
# ║ LA COLONNE : un cylindre OUVERT (sans couvercles) monté du point d'impact jusqu'AU-DESSUS du    ║
# ║ parapet. Sa partie haute émerge donc dans une zone d'écran que le joueur sait être « au-delà    ║
# ║ des sacs », et elle est reliée sans ambiguïté au cercle par sa paroi. La profondeur redevient   ║
# ║ lisible sans qu'on ait touché à un seul mètre du rayon — l'invariant §C.1 est intact.           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Hauteur de la colonne ⚙ : elle doit dépasser franchement le sommet du parapet (1,25 m) tout en
# restant sous la silhouette d'un soldat debout (1,80 m), qu'elle n'a pas à masquer.
const ZONE_COLUMN_HEIGHT := 1.55


func _zone_marker(node_name: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = node_name

	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = _ring_mesh()
	ring.material_override = _zone_material(color, 0.85)
	root.add_child(ring)

	var wall := CylinderMesh.new()
	wall.top_radius = 1.0
	wall.bottom_radius = 1.0
	wall.height = ZONE_COLUMN_HEIGHT
	wall.radial_segments = 40
	# ⚠️ SANS COUVERCLES : un cylindre plein masquerait le soldat qui se tient dans la zone —
	# c'est-à-dire exactement ce qu'on demande au joueur de regarder.
	wall.cap_top = false
	wall.cap_bottom = false
	var column := MeshInstance3D.new()
	column.name = "Column"
	column.mesh = wall
	# La paroi est BEAUCOUP plus discrète que l'anneau : elle porte la profondeur, pas la zone.
	column.material_override = _zone_material(color, 0.16)
	column.position = Vector3(0.0, ZONE_COLUMN_HEIGHT * 0.5, 0.0)
	root.add_child(column)
	return root


func _zone_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := _material(Color(color.r, color.g, color.b, alpha), true)
	_see_through(mat)
	return mat


# Repeint un marqueur de zone (anneau + colonne) sans reconstruire ses matériaux.
func _tint_zone(marker: Node3D, color: Color, ring_alpha: float) -> void:
	var ring_mat: StandardMaterial3D = (marker.get_node("Ring") as MeshInstance3D).material_override
	var column_mat: StandardMaterial3D = \
		(marker.get_node("Column") as MeshInstance3D).material_override
	ring_mat.albedo_color = Color(color.r, color.g, color.b, ring_alpha)
	ring_mat.emission = color
	column_mat.albedo_color = Color(color.r, color.g, color.b, ring_alpha * 0.19)
	column_mat.emission = color


func _build_pools() -> void:
	# Traçantes : des boîtes très étirées, non éclairées — lisibles de jour comme de nuit.
	for i in range(TRACER_POOL):
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, 0.06, 1.0)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = _material(COL_GOLD, true)
		node.visible = false
		_root.add_child(node)
		_tracers.append(node)

	for i in range(GRENADE_POOL):
		var sphere := SphereMesh.new()
		sphere.radius = 0.11
		sphere.height = 0.22
		var node := MeshInstance3D.new()
		node.mesh = sphere
		node.material_override = _material(Color(0.35, 0.42, 0.30))
		node.visible = false
		_root.add_child(node)
		_grenades.append(node)

		# Le MARQUEUR D'IMPACT AU SOL : un anneau pulsant, visible DÈS LE LANCER (règle d'or).
		# ╔═ ⚠️⚠️ IL VALAIT 1,6 m EN DUR POUR UNE ARME QUI EN COUVRAIT 2 × 4 m (§8.141) ═════════╗
		# ║ L'ancien barème frappait la position visée ET ses deux voisines : la zone RÉELLE       ║
		# ║ mesurait 8 m de large quand le disque en annonçait 3,2. Le joueur voyait donc un        ║
		# ║ marqueur à côté duquel il se croyait en sécurité, et prenait 15 dégâts. Le visuel        ║
		# ║ mentait — pas par excès de zèle, par une constante posée sans être reliée à la règle.   ║
		# ║ Le rayon est désormais celui du REGISTRE SERVEUR (`set_grenade_radius`), et la maille   ║
		# ║ est unitaire (rayon 1) : c'est `scale` qui l'ouvre. Une seule valeur, une seule vérité. ║
		# ║ ⚠️ UN ANNEAU, pas un disque : un disque plein posé sur une position masque les pieds de ║
		# ║ celui qui s'y trouve, c'est-à-dire l'information qu'on vient regarder.                  ║
		# ╚═══════════════════════════════════════════════════════════════════════════════════════╝
		var marker := _zone_marker("GrenadeMarker_%d" % i, COL_DANGER)
		marker.visible = false
		_root.add_child(marker)
		_markers.append(marker)

	# LE DÉCALQUE DE VISÉE (§B.1) — le mien, celui que je pose en maintenant la touche. Même maille
	# et même rayon que les marqueurs de vol : ce que je vise et ce qui explose sont le même cercle.
	_aim_decal = _zone_marker("GrenadeAimDecal", COL_GRENADE_OK)
	_aim_decal.visible = false
	_root.add_child(_aim_decal)

	for i in range(EXPLOSION_POOL):
		var boom := ExplosionScene.instantiate()
		boom.set_reduced_motion(_reduced_motion)
		_root.add_child(boom)
		_explosions.append(boom)

	var beam := BoxMesh.new()
	beam.size = Vector3(0.02, 0.02, 1.0)
	_laser = MeshInstance3D.new()
	_laser.mesh = beam
	_laser.material_override = _material(Color(1.0, 0.25, 0.2, 0.9), true)
	_laser.visible = false
	_root.add_child(_laser)


# =================================================================================================
# API PUBLIQUE — appelée par `trench_fp.gd`
# =================================================================================================
func set_reduced_motion(reduced: bool) -> void:
	_reduced_motion = reduced
	for boom in _explosions:
		boom.set_reduced_motion(reduced)


# ╔═ LE RAYON D'ACTION VIENT DU SERVEUR, ET DE NULLE PART AILLEURS (§C.1) ════════════════════════╗
# ║ `trench_init.rules.grenade.radius_m` est la valeur qui DÉCIDE des dégâts. C'est elle, et pas    ║
# ║ une constante de présentation, qui ouvre les cercles de visée, les marqueurs de vol et l'anneau ║
# ║ de choc. Le visuel n'a donc pas de valeur propre à faire diverger : il ne PEUT pas mentir.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func set_grenade_radius(radius: float) -> void:
	_grenade_radius = maxf(0.1, radius)


func grenade_radius() -> float:
	return _grenade_radius


# ╔═ OÙ LA GRENADE VA-T-ELLE TOMBER ? — le raycast du réticule dans le monde 3D (§B.1.1) ═════════╗
# ║ On intersecte la ligne de visée avec le PLANCHER de la tranchée adverse, puis on regarde si le  ║
# ║ point tombe dans la bande utile. Sinon, on AIMANTE : on reprend la même ligne de visée à la     ║
# ║ profondeur la plus proche de la bande, et on le signale en ROUGE.                                ║
# ║ ⚠️ L'AIMANTATION N'EST PAS UNE CORRECTION SILENCIEUSE. Le décalque change de couleur, donc le    ║
# ║ joueur SAIT qu'il vise en dehors et voit exactement où sa grenade partirait s'il lâchait. Une    ║
# ║ aide qui corrige sans le dire est une aide qui trahit — le joueur croirait avoir visé là.        ║
# ║ ⚠️ Le serveur ne reçoit QUE `target_x` : la profondeur ne quitte jamais le client. Cette bande   ║
# ║ est donc du CONFORT DE GESTE, pas une règle — un client modifié qui l'ignorerait ne gagnerait    ║
# ║ rien du tout, le clamp serveur ayant le dernier mot sur la seule coordonnée qui compte.          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func grenade_aim_point(yaw_deg: float, pitch_deg: float, limit_x: float) -> Dictionary:
	var target_z: float = Geo.far_soldier_z()
	if _camera == null:
		return {"x": 0.0, "z": target_z, "valid": false}
	var origin := _camera.global_position
	var dir := _direction(yaw_deg, pitch_deg)
	# ⚠️ `dir.z` est TOUJOURS positif ici : le débattement borne le lacet à ±60° et le site à ±14°,
	# donc `cos(yaw)·cos(pitch) > 0`. La division est sûre, mais on la garde du garde.
	var x := 0.0
	if absf(dir.z) > 0.0001:
		x = origin.x + dir.x * ((target_z - origin.z) / dir.z)
	var bounded: float = clampf(x, -limit_x, limit_x)
	var valid: bool = absf(bounded - x) <= 0.0001

	# --- LA VALIDITÉ EN PROFONDEUR : deux garde-fous, et rien de plus ---------------------------
	# Ne pas viser LE CIEL : au-dessus de l'horizontale, le geste n'a plus de sens (et la grenade
	# partirait quand même, puisque seul `target_x` voyage — le joueur doit le savoir).
	if pitch_deg > SKY_TOLERANCE_DEG:
		valid = false
	# Ne pas viser LA BOUE DEVANT SON PROPRE PARAPET.
	# ╔═ ⚠️ LE SEUIL EST MESURÉ, PAS DÉCRÉTÉ — ET UNE PREMIÈRE VERSION NE POUVAIT JAMAIS MORDRE ══╗
	# ║ Premier essai : « la ligne de visée doit atteindre le parapet adverse ». Mesure : il faut   ║
	# ║ pour cela un site au-dessus de **−5,4°**, alors que viser le torse de l'adversaire demande   ║
	# ║ déjà −2,4° et que le débattement descend à −14°. La moitié du geste normal serait passée au  ║
	# ║ rouge. Second essai, inverse : « la ligne doit dépasser mon propre parapet » — mesure : à    ║
	# ║ ±14° de site c'est TOUJOURS vrai (il faudrait piquer à 32° pour le rater). Un garde-fou qui  ║
	# ║ ne peut jamais mordre n'est pas un garde-fou, c'est un mensonge de plus dans le code.        ║
	# ║ Le seuil retenu tombe entre les deux, en FRACTION du no man's land : la ligne de visée doit  ║
	# ║ toucher le sol au-delà de 40 % de la traversée, soit un site au-dessus de ~−9,5°. En deçà,   ║
	# ║ on regarde vraiment la boue à deux mètres de ses bottes.                                     ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	elif dir.y < -0.0005:
		var ground: float = origin.z + dir.z * ((Geo.GROUND_Y - origin.y) / dir.y)
		if ground < Geo.NO_MANS_LAND * GRENADE_MIN_REACH:
			valid = false
	return {"x": bounded, "z": target_z, "valid": valid}


# Le décalque de MA visée : allumé pendant le maintien, éteint sinon. OR = ce point est bon,
# ROUGE = j'ai débordé et la grenade partirait au point aimanté (celui qui est dessiné).
func show_grenade_aim(active: bool, at_x: float = 0.0, at_z: float = 0.0,
		valid: bool = true) -> void:
	if _aim_decal == null:
		return
	_aim_decal.visible = active
	if not active:
		return
	_aim_decal.position = Vector3(at_x, MARKER_Y, at_z)
	# ⚠️ Seuls X et Z portent le rayon : la COLONNE garde sa hauteur, sinon un grand rayon la
	# ferait monter jusqu'au ciel et un petit la ferait disparaître sous les sacs.
	_aim_decal.scale = Vector3(_grenade_radius, 1.0, _grenade_radius)
	_tint_zone(_aim_decal, COL_GRENADE_OK if valid else COL_GRENADE_OUT, 0.85)


# ╔═ L'EXPLOSION — DÉCLENCHÉE PAR L'ÉVÉNEMENT `impact` DU SERVEUR, JAMAIS PAR UNE HORLOGE LOCALE ═╗
# ║ Le client connaît le tick d'impact dès le lancer et pourrait « jouer l'explosion à l'heure ».   ║
# ║ Il ne le fait pas : ce serait rejouer la simulation, et une désynchronisation de 100 ms ferait  ║
# ║ exploser une grenade avant que le serveur ne l'ait résolue — donc un joueur qui se voit épargné ║
# ║ puis meurt. C'est l'événement qui commande, comme le hitmarker (§5.5).                          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func play_explosion(at_x: float, on_my_side: bool) -> void:
	var z: float = Geo.near_soldier_z() if on_my_side else Geo.far_soldier_z()
	var at := Vector3(at_x, MARKER_Y, z)
	var free_slot = null
	for boom in _explosions:
		if not boom.is_busy():
			free_slot = boom
			break
	# Pool SATURÉE : on réarme la PLUS ANCIENNE plutôt que d'ignorer l'explosion. Une grenade qui
	# tombe sans rien montrer serait pire qu'une animation coupée — le joueur perdrait la seule
	# information qui lui dit où la zone était.
	if free_slot == null:
		free_slot = _explosions[0]
		for boom in _explosions:
			if boom.elapsed() > free_slot.elapsed():
				free_slot = boom
	free_slot.play(at, _grenade_radius)
	_apply_shake(at)
	_play_explosion_audio(at)


# LA SECOUSSE, en « trauma » : une impulsion qui s'ajoute et décroît, jamais une durée fixe. Deux
# grenades coup sur coup secouent donc PLUS que deux fois une, ce qui est juste.
func _apply_shake(at: Vector3) -> void:
	if _reduced_motion or _camera == null:
		return
	var distance := _camera.global_position.distance_to(at)
	if distance > SHAKE_RANGE:
		return
	# Dans le rayon d'action = j'y étais. Ma tranchée touchée ailleurs = je l'entends dans le sol.
	var impulse: float = SHAKE_ON_ME if distance <= _grenade_radius else SHAKE_ON_MY_TRENCH
	# … et elle s'atténue AUSSI avec la distance au-delà du rayon : une grenade à 14 m ne doit pas
	# secouer autant qu'une à 4 m.
	if distance > _grenade_radius:
		impulse *= clampf(1.0 - (distance - _grenade_radius) / SHAKE_RANGE, 0.0, 1.0)
	_shake = clampf(_shake + impulse, 0.0, 1.0)


func _play_explosion_audio(at: Vector3) -> void:
	if _camera == null:
		return
	var distance := _camera.global_position.distance_to(at)
	# ⚠️ DEUX SONS, PAS UN SEUL BAISSÉ. Un son lointain est un son plus SOMBRE, pas juste plus
	# faible : c'est le TIMBRE qui dit au joueur « ce n'est pas tombé sur moi », et il le dit avant
	# qu'il ait eu le temps de regarder ses PV. Le seuil de 6 m est celui du bon de commande ⚙.
	if distance < 6.0:
		AudioManager.play_sfx("trench_explosion_near", -2.0)
	else:
		AudioManager.play_sfx("trench_explosion_far",
			lerpf(-4.0, -18.0, clampf(distance / 30.0, 0.0, 1.0)))
	# Les RETOMBÉES, 0,4 s après : c'est ce qui donne une durée à l'événement. Un `SceneTreeTimer`
	# plutôt qu'un compteur de frame — il survit à un changement de cadence d'affichage.
	var quiet: float = lerpf(-6.0, -22.0, clampf(distance / 30.0, 0.0, 1.0))
	get_tree().create_timer(0.4).timeout.connect(func():
		if is_inside_tree():
			AudioManager.play_sfx("trench_debris", quiet))


# Le champ de vision de la caméra, exposé à l'hôte : c'est lui qui convertit la dispersion d'une
# arme (en degrés) en écartement de réticule (en pixels). Une seule source pour le FOV.
func camera_fov() -> float:
	return _camera.fov if _camera != null else CAMERA_FOV


# ╔═ `show_blockout_geometry()` A DISPARU AVEC LES DÉCORS PEINTS ═════════════════════════════════╗
# ║ Elle éteignait le monde 3D dès qu'un décor était déposé. C'est CETTE bascule qui masquait      ║
# ║ `NearParapet` — « le parapet de sacs qui décide de tout le jeu » — et laissait le joueur       ║
# ║ debout en terrain découvert derrière une bande peinte de 77 px. Le monde texturé étant         ║
# ║ désormais le rendu nominal, il n'y a plus rien à éteindre : le défaut est devenu impossible    ║
# ║ à écrire, ce qui vaut mieux que de le corriger.                                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝


# ╔═ LES RÉGLAGES DE SENSATION VIENNENT DU JOUEUR, PAS DU CODE (règle de fer n° 2) ═══════════════╗
# ║ Suivi de visée, plafond d'angle et champ de vision se règlent EN JEU, au panneau F10, pendant  ║
# ║ une partie d'entraînement. Le code ne devine plus une sensation qu'il ne peut pas éprouver :   ║
# ║ il expose des bornes et applique ce que Hakim décide. Les valeurs qu'il retiendra deviendront  ║
# ║ les défauts d'usine à la clôture du chantier.                                                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func apply_tuning(tuning: Dictionary) -> void:
	var ceiling: float = Geo.camera_follow_max_deg()
	_follow = clampf(float(tuning.get("aim_follow", AIM_FOLLOW)), 0.0, 1.0)
	# ⚠️ La borne HAUTE du clamp est la borne dérivée, pas un 80 en dur : un panneau qui pourrait
	# poser plus que le plafond de sécurité rendrait ce plafond décoratif.
	_follow_max = clampf(float(tuning.get("follow_max_deg", ceiling)), 5.0, ceiling)
	# §8.151 : l'intensité de secousse du panneau F10, et le FOV réglé qui devient la BASE sur
	# laquelle le punch de tir s'ajoute (les deux écritures de `_camera.fov` passent par le même
	# point — deux mains sur le même champ finiraient par s'écraser l'une l'autre).
	_shake_scale = clampf(float(tuning.get("feel_shake", _shake_scale)), 0.0, 2.0)
	_fov_base = clampf(float(tuning.get("fov", _fov_base)), 50.0, 100.0)
	_apply_camera_fov()


# §8.151 — LE FEEL DE CAMÉRA, poussé par l'hôte à chaque frame. Les plafonds vivent ICI, à
# l'application : aucun appelant — panneau compris — ne peut faire dépasser le roulis de ±0,3°.
func set_camera_feel(roll_deg: float, fov_offset_deg: float) -> void:
	_feel_roll_deg = clampf(roll_deg, -FEEL_ROLL_CAP_DEG, FEEL_ROLL_CAP_DEG)
	var offset := clampf(fov_offset_deg, 0.0, FEEL_FOV_OFFSET_MAX)
	if offset != _feel_fov_offset:
		_feel_fov_offset = offset
		_apply_camera_fov()


func _apply_camera_fov() -> void:
	if _camera != null:
		_camera.fov = _fov_base + _feel_fov_offset


# Le décalage de secousse, en px d'ÉCRAN — consommé par l'hôte qui l'applique aux couches ET au
# réticule d'un seul geste (monde + réticule ENSEMBLE, cahier §4.2). ZÉRO exact au repos.
func shake_screen_px() -> Vector2:
	return _shake_px


# Teinte le soldat adverse à l'accent de SA faction (système d'accents existant, §5.2).
# Le PLACEHOLDER est repeint en plein (il n'a aucune information à préserver) ; le SPRITE, lui,
# ne reçoit qu'un mélange doux (`ENEMY_TINT_MIX`) appliqué au rendu — la peinture reste visible.
func set_enemy_accent(color: Color) -> void:
	_enemy_tint = color
	if _enemy_mesh != null:
		_enemy_mesh.material_override = _enemy_material(color)
	if _enemy_helmet != null:
		_enemy_helmet.material_override = _enemy_material(color.darkened(0.35))


# Un ACTE de l'adversaire, poussé par l'hôte depuis un ÉVÉNEMENT serveur (`grenade_thrown`, `hit`).
# ⚠️ Ce sont des états TRANSITOIRES : ils ne décrivent pas une situation qu'on pourrait relire dans
# l'état, mais un instant. D'où l'entrée par appel plutôt que par le view-model de la frame.
func set_enemy_action(kind: String) -> void:
	if not _enemy_painted or _enemy_dying or not Sprites.is_transient(kind):
		return
	# « hit » interrompt tout sauf la mort ; « throw » ne coupe donc PAS un « hit » en cours —
	# encaisser une balle en pleine armée de grenade se lit d'abord comme un coup encaissé.
	if kind == "throw" and _enemy_frame == "hit" and _enemy_frame_left > 0.0:
		return
	_enemy_frame = kind
	_enemy_frame_left = Sprites.frame_duration(kind)
	_apply_enemy_frame()


# LA MACHINE À FRAMES. Priorité : mort > transitoire en cours > ambiant (`aim` ou `idle`).
# La mort est la seule CHAÎNE (`death_a` -> `death_b`, puis statique au sol) ; tout le reste rend la
# main à l'état ambiant, qui est la seule vérité lisible dans l'état serveur.
func _advance_enemy_frames(delta: float) -> void:
	if not _enemy_painted:
		return
	var wanted := _enemy_frame
	if _enemy_dead:
		if not _enemy_dying:
			_enemy_dying = true
			wanted = Sprites.ENEMY_DEATH_FIRST
			_enemy_frame_left = Sprites.frame_duration(wanted)
		elif _enemy_frame_left > 0.0:
			_enemy_frame_left = maxf(0.0, _enemy_frame_left - delta)
			if _enemy_frame_left <= 0.0:
				wanted = Sprites.frame_next(_enemy_frame)
	else:
		# Manche suivante : l'adversaire revient vivant, la chaîne de mort se réarme.
		_enemy_dying = false
		# ⭐ §8.153 — L IMAGE DE PASSAGE. La machine ne connaissait que DEUX etats permanents et
		# basculait de l un a l autre d un seul coup, pendant que la position, elle, glissait en
		# continu. On insere donc une pose a mi-chemin quand la visee CHANGE.
		# ⚠️ On observe la BASCULE, pas l etat : reagir a `_enemy_aiming` seul reinsererait la
		# frame a chaque image tant qu il vise, et le soldat resterait bloque a mi-chemin.
		# 🩸 ON ECRIT DANS `wanted`, PAS DANS `_enemy_frame`. Premiere version : elle posait la frame
		# directement et appelait `_apply_enemy_frame()` — et la fin de cette fonction la REMETTAIT
		# aussitot a `wanted`, capture AVANT l insertion. L image de passage n etait donc jamais
		# jouee : le soldat gardait exactement le comportement d avant, sans une seule erreur.
		# ⚠️ Un cablage qui a l air juste et ne fait RIEN est le pire des defauts a relire : il ne
		# laisse aucune trace. Seul un controle FONCTIONNEL (« la frame vaut-elle aim_rise ? ») l a vu.
		if _enemy_aiming != _enemy_aiming_prev:
			_enemy_aiming_prev = _enemy_aiming
			if Sprites.has_frame(Sprites.ENEMY_AIM_RISE):
				wanted = Sprites.ENEMY_AIM_RISE
				_enemy_frame_left = Sprites.frame_duration(Sprites.ENEMY_AIM_RISE)
		if _enemy_frame_left > 0.0:
			_enemy_frame_left = maxf(0.0, _enemy_frame_left - delta)
		if _enemy_frame_left <= 0.0:
			wanted = Sprites.ambient_state(_enemy_aiming)
	if wanted != _enemy_frame and wanted != "":
		_enemy_frame = wanted
		_apply_enemy_frame()


# Bascule entre le viewmodel en PRIMITIVES (ce viewport) et le viewmodel PEINT (couche 2D de
# l'hôte, §8.138). Un seul des deux est allumé — jamais les deux, jamais aucun.
func set_viewmodel_visible(show_primitives: bool) -> void:
	if _viewmodel != null:
		_viewmodel.visible = show_primitives


# Pose de caméra. `instant` (ou `reduced_motion`) = coupe sèche, sinon transition douce.
func set_pose(pos_index: int, stance: String, instant := false) -> void:
	_pose_pos = clampi(pos_index, 0, Geo.POSITIONS - 1)
	_pose_stance = stance
	_cam_target = _blockout.pose_transform(_pose_pos, _pose_stance).origin \
		if _blockout != null else Geo.eye_position(_pose_pos, _pose_stance)
	if instant or _reduced_motion:
		_cam_current = _cam_target


# Direction de visée du joueur, en degrés dans le repère de l'arène.
func set_aim(yaw_deg: float, pitch_deg: float) -> void:
	_aim_yaw = yaw_deg
	_aim_pitch = pitch_deg


func _process(delta: float) -> void:
	# La machine à frames tourne MÊME quand le soldat est masqué par la redaction : il peut mourir
	# d'une grenade hors de vue, et il ne doit pas ressusciter debout en réapparaissant.
	_advance_enemy_frames(delta)
	_advance_local_tracers(delta)
	# Rappel exponentiel de l'affaissement du pas, et extinction du départ de feu adverse.
	_enemy_dip = maxf(0.0, _enemy_dip - _enemy_dip * ENEMY_STEP_DIP_DECAY * delta - 0.0005)
	_animer_foulee(delta)
	if _enemy_muzzle_left > 0.0:
		_enemy_muzzle_left = maxf(0.0, _enemy_muzzle_left - delta)
		if _enemy_muzzle_left <= 0.0 and _enemy_muzzle != null:
			_enemy_muzzle.visible = false
	if _camera == null:
		return
	# Transition de pose : latéral et vertical ont des durées DIFFÉRENTES (§5.1) — se baisser est
	# plus vif qu'un pas de côté, et le corps doit le faire sentir.
	var lateral: float = 1.0 if MOVE_TRANSITION <= 0.0 else minf(1.0, delta / MOVE_TRANSITION)
	var vertical: float = 1.0 if STANCE_TRANSITION <= 0.0 else minf(1.0, delta / STANCE_TRANSITION)
	if _reduced_motion:
		_cam_current = _cam_target
	else:
		_cam_current.x = lerpf(_cam_current.x, _cam_target.x, lateral)
		_cam_current.z = lerpf(_cam_current.z, _cam_target.z, lateral)
		_cam_current.y = lerpf(_cam_current.y, _cam_target.y, vertical)

	# SUIVI DE VISÉE (§1.1) : la caméra accompagne le réticule d'une fraction, plafonnée. Le
	# reste du débattement se lit sur l'écran, pas dans la rotation — les poses restent FIXES.
	_cam_yaw = clampf(_aim_yaw * _follow, -_follow_max, _follow_max)
	_cam_pitch = clampf(_aim_pitch * _follow, -_follow_max, _follow_max)
	# ╔═ §8.151 — LA SECOUSSE NE TOUCHE PLUS LA CAMÉRA DU TOUT ═════════════════════════════════╗
	# ║ Ni rotation (elle déplacerait la visée rendue — §8.141.6), ni translation (le réticule,    ║
	# ║ projeté depuis une direction, ne suivait pas le monde translaté : ~7 px de désaccord).     ║
	# ║ Le trauma avance ici et SORT en px d'écran (`shake_screen_px`) ; l'hôte translate les      ║
	# ║ couches et le réticule ENSEMBLE. La seule liberté angulaire est le ROULIS ±0,3° autour de  ║
	# ║ l'axe de visée, appliqué APRÈS `look_at` : le centre de l'image est invariant, et le       ║
	# ║ réticule projeté par cette même caméra tourne AVEC le monde.                               ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	_advance_shake(delta)
	var eye := _cam_current
	_camera.position = eye
	_camera.look_at(eye + _direction(_cam_yaw, _cam_pitch), Vector3.UP)
	if _feel_roll_deg != 0.0:
		_camera.rotate_object_local(Vector3(0.0, 0.0, 1.0), deg_to_rad(_feel_roll_deg))


# DÉCROISSANCE EXPONENTIELLE du trauma, et bruit à deux cadences légèrement différentes sur les
# deux axes : à cadence égale, l'œil suivrait une diagonale rectiligne et lirait « glissement »
# plutôt que « secousse ». L'amplitude est le CARRÉ du trauma — c'est ce qui rend une petite
# détonation discrète et une grosse franche, au lieu d'un continuum plat.
# §8.151 : sortie en PX D'ÉCRAN par `hash_noise` (déterministe — LOT E) ; `_shake_time` n'avance
# que pendant le trauma, donc deux exécutions du même scénario rejouent la même phase.
func _advance_shake(delta: float) -> void:
	if _shake <= 0.0001:
		_shake = 0.0
		_shake_px = Vector2.ZERO
		return
	_shake_time += delta
	_shake = maxf(0.0, _shake - _shake * SHAKE_DECAY * delta - 0.001)
	var amplitude: float = SHAKE_PX_RATIO * size.y * _shake * _shake * _shake_scale
	_shake_px = Vector2(
		Springs.hash_noise(_shake_time * SHAKE_NOISE_RATE, SHAKE_SEED_X),
		Springs.hash_noise(_shake_time * SHAKE_NOISE_RATE * 1.37, SHAKE_SEED_Y) * 0.75) \
		* amplitude


# Direction unitaire d'un couple (lacet, site) exprimé en degrés dans le repère de l'arène
# (+Z = la tranchée adverse). MIROIR EXACT de `trench_geometry.yaw_to`/`pitch_to`.
func _direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))


# Position ÉCRAN de la visée — c'est elle qui place le réticule du HUD. On projette un point
# lointain plutôt que de refaire la trigonométrie du champ de vision : `unproject_position` tient
# compte de l'aspect, du FOV et de la rotation de suivi, sans qu'on ait à les recopier.
func project_aim(yaw_deg: float, pitch_deg: float) -> Vector2:
	if _camera == null:
		return size * 0.5
	var point := _camera.global_position + _direction(yaw_deg, pitch_deg) * Geo.NO_MANS_LAND
	if _camera.is_position_behind(point):
		return size * 0.5
	return _camera.unproject_position(point)


# =================================================================================================
# LE VIEW-MODEL DE LA FRAME (poussé par l'hôte)
# =================================================================================================
# `view` = {
#   enemy: {visible: bool, pos: float, hit: float},          # pos INTERPOLÉE, -1 = inconnue
#   tracers: [{from_pos, mine, yaw, pitch, t}],              # t = 0..1 le long du vol
#   grenades: [{from_pos, target_pos, mine, t}],
#   markers:  [{target_pos, on_my_side, eta}],
#   laser:    {active, from_pos, mine, yaw, pitch} | {},
# }
func render_world(view: Dictionary) -> void:
	_render_enemy(view.get("enemy", {}))
	_render_tracers(view.get("tracers", []))
	_render_grenades(view.get("grenades", []), view.get("markers", []))
	_render_laser(view.get("laser", {}))


func _render_enemy(enemy: Dictionary) -> void:
	if _enemy == null:
		return
	# LU AVANT le repli de visibilité ci-dessous : la machine à frames doit continuer de tourner
	# même quand l'adversaire est caché (cf. `_process`).
	_enemy_aiming = bool(enemy.get("aiming", false))
	_enemy_dead = bool(enemy.get("dead", false))
	var wants: bool = bool(enemy.get("visible", false))
	# APPARITION / DISPARITION EN FONDU (§5.2) — jamais de pop sec : quand la redaction masque
	# l'adversaire, il s'efface là où on l'a vu pour la dernière fois, comme s'il se baissait.
	var step: float = 1.0 if _reduced_motion else 0.12
	_enemy_alpha = clampf(_enemy_alpha + (step if wants else -step), 0.0, 1.0)
	if wants:
		_enemy_last_pos = float(enemy.get("pos", _enemy_last_pos))
	_enemy.visible = _enemy_alpha > 0.01
	if not _enemy.visible:
		return
	var x := _stepped_enemy_x()
	# En s'effaçant, il s'enfonce derrière le parapet : la disparition RACONTE quelque chose.
	var sink := (1.0 - _enemy_alpha) * 0.55
	# … et il s'affaisse d'un rien au poser du pied (§8.141) : c'est ce qui donne un POIDS au pas.
	_enemy.position = Vector3(x, -sink - _enfoncement(), Geo.far_soldier_z())
	var flash: float = clampf(float(enemy.get("hit", 0.0)), 0.0, 1.0)
	if _enemy_painted:
		# TEINTE DE FACTION + fondu de redaction + éclair de touche, en une seule couleur : sur un
		# `Sprite3D`, `modulate` est le point d'entrée unique (il n'y a pas de matériau à repeindre).
		var tint := Color.WHITE.lerp(_enemy_tint, ENEMY_TINT_MIX)
		if flash > 0.0:
			tint = tint.lerp(Color.WHITE, flash * ENEMY_HIT_WHITEN)
		tint.a = _enemy_alpha
		_enemy_sprite.modulate = tint
		# Le liseré partage le fondu de redaction : il doit s'effacer AVEC lui, jamais après — un
		# contour qui survivrait d'une frame dessinerait la silhouette d'un homme qui n'est plus là.
		var rim := ENEMY_RIM_COLOR
		rim.a = _enemy_alpha
		_enemy_rim.modulate = rim
		# LA TRAÎNÉE : la pose qu on vient de quitter, qui s efface sous la nouvelle.
		# ⚠️ Elle porte la MÊME teinte que le sprite — sans quoi un soldat en train de changer de
		# pose porterait deux couleurs de faction pendant un dixième de seconde.
		if _enemy_fade != null:
			var reste: float = 0.0 if _reduced_motion \
				else clampf(_enemy_fade_left / ENEMY_FADE_TIME, 0.0, 1.0)
			_enemy_fade.visible = reste > 0.001 and _enemy_fade.texture != null
			var trace := tint
			trace.a = _enemy_alpha * reste
			_enemy_fade.modulate = trace
		return
	for mesh in [_enemy_mesh, _enemy_helmet]:
		if mesh != null and mesh.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mesh.material_override
			mat.albedo_color.a = _enemy_alpha
			mat.emission_enabled = flash > 0.0
			mat.emission = Color(1, 1, 1)
			mat.emission_energy_multiplier = flash * 3.0


# ╔═ ⚠️ L'ADVERSAIRE SE DÉPLACE COMME MOI, PAS EN GLISSANT ═══════════════════════════════════════╗
# ║ Verdict de partie réelle : « le mouvement du bot est trop rapide, je ne sais pas si ça          ║
# ║ correspond bien au mouvement de mon soldat ». VÉRIFIÉ CÔTÉ SERVEUR : il n'est PAS plus rapide.  ║
# ║ `_apply_input` fait passer le bot par la MÊME porte que moi (`move_ready_tick`, 3 ticks), et il ║
# ║ ne tente un pas qu'avec une probabilité de 0,22 par tick — soit ~2,2 pas/s là où un joueur qui  ║
# ║ tient sa flèche en demande à chaque envoi et atteint le plafond de 3,33 pas/s. Mécaniquement,   ║
# ║ c'est le JOUEUR le plus rapide.                                                                 ║
# ║                                                                                                 ║
# ║ Ce qui différait, c'est le RENDU. Sa position était interpolée en continu entre deux états      ║
# ║ serveur : il TRAVERSAIT le front d'un glissé fluide. La mienne, elle, est une suite de poses    ║
# ║ discrètes reliées par un fondu de 0,15 s. Un adversaire qui glisse se lit « rapide » ; un       ║
# ║ soldat qui pose ses pas se lit « lent ». On aligne donc les deux lectures sur la MÊME mécanique.║
# ║ ⚠️ Et c'est aussi plus FIDÈLE : la position serveur est un ENTIER — le glissé était l'artefact. ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _stepped_enemy_x() -> float:
	var whole: int = int(round(_enemy_last_pos))
	_notice_step(whole)
	var target: float = Geo.position_x(whole)
	if _reduced_motion or MOVE_TRANSITION <= 0.0:
		_enemy_x = target
		return _enemy_x
	var step: float = minf(1.0, get_process_delta_time() / MOVE_TRANSITION)
	_enemy_x = lerpf(_enemy_x, target, step)
	return _enemy_x


# ╔═ UN PAS SE PAIE : POUSSIÈRE, AFFAISSEMENT, BRUIT SOURD (§8.141) ══════════════════════════════╗
# ║ ⚠️ UN PAS EST UN ÉCART DE **EXACTEMENT** UNE POSITION, et cette condition n'est pas cosmétique. ║
# ║ Trois choses déplacent l'adversaire d'un cran ou plus SANS qu'il ait marché :                   ║
# ║   • le début de manche le RAMÈNE au centre (jusqu'à 2 crans d'un coup) ;                        ║
# ║   • il RÉAPPARAÎT ailleurs après s'être caché (la redaction §1.6 n'a rien diffusé entre-temps) ;║
# ║   • une reconnexion resynchronise la partie.                                                    ║
# ║ Sans le garde, chacun de ces trois cas lèverait un nuage de poussière et un bruit de botte pour ║
# ║ un pas qui n'a jamais eu lieu — c'est-à-dire une INFORMATION FAUSSE dans un jeu où le bruit de   ║
# ║ pas est justement là pour dire où est l'ennemi. Un saut de 2 crans ne fait donc RIEN, et         ║
# ║ `-1` (jamais vu) ne fait rien non plus : on ne raconte que ce qu'on a vraiment observé.          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ── LA FOULÉE, LA RESPIRATION ET LA TRAÎNÉE (§8.153) ─────────────────────────────────────────
# ⛔ TOUT SE PASSE VERS LE BAS. Un mouvement latéral ou vers le haut élargirait la silhouette
# rendue au-delà de la fenêtre que le serveur résout (cf. le pavé de `ENEMY_STRIDE_TIME`).
# La foulée est donc une COURBE DE TEMPS sur un seul axe — et c est suffisant, parce que ce qui
# manquait n était pas de l amplitude, c était de la CONTINUITÉ.
#
# ⚠️ Deux creux par foulée, pas un. Un pas humain enfonce DEUX fois : à la pose du talon, puis
# au transfert du poids sur la jambe avant. Un seul creux se lit comme un sautillement ; deux
# se lisent comme une marche. C est le détail qui fait tout le travail, et il ne coûte qu un
# sinus de plus.
func _animer_foulee(delta: float) -> void:
	if _enemy_fade_left > 0.0:
		_enemy_fade_left = maxf(0.0, _enemy_fade_left - delta)
	# La respiration ne s arrête jamais : elle tourne même masqué, sinon l adversaire
	# réapparaîtrait toujours au même instant de son cycle.
	_enemy_breath = fmod(_enemy_breath + delta, ENEMY_BREATH_PERIOD)
	if _enemy_stride >= 0.0:
		_enemy_stride += delta
		if _enemy_stride >= ENEMY_STRIDE_TIME:
			_enemy_stride = -1.0


# L enfoncement TOTAL du soldat, en mètres, toujours positif (donc toujours vers le bas).
func _enfoncement() -> float:
	if _reduced_motion:
		return 0.0
	var respire: float = ENEMY_BREATH_DIP * 0.5 * (1.0 - cos(
		TAU * _enemy_breath / ENEMY_BREATH_PERIOD))
	var foulee := 0.0
	if _enemy_stride >= 0.0:
		var t: float = clampf(_enemy_stride / ENEMY_STRIDE_TIME, 0.0, 1.0)
		# Deux creux (`sin` sur deux demi-périodes), pondérés par une enveloppe qui s éteint : le
		# second appui est plus léger que le premier, comme un pas réel.
		foulee = ENEMY_STEP_DIP * absf(sin(TAU * t)) * (1.0 - t * 0.45)
	return respire + foulee + _enemy_dip


func _notice_step(whole: int) -> void:
	var previous := _enemy_step_pos
	_enemy_step_pos = whole
	if previous < 0 or absi(whole - previous) != 1 or _enemy_dead:
		return
	# `reduced_motion` coupe le SPECTACLE (poussière, affaissement) et garde l'INFORMATION (le son).
	# C'est la règle maison : on n'ampute jamais la lecture du jeu au titre du confort.
	if not _reduced_motion:
		_enemy_stride = 0.0
		_enemy_dip = ENEMY_STEP_DIP
		if _enemy_dust != null:
			_enemy_dust.restart()
	if _camera == null:
		return
	# ATTÉNUATION PAR LA DISTANCE, calculée sur la position RÉELLE : un pas au bout opposé du front
	# est à 17 m, un pas en face à 10 m. Le joueur doit pouvoir entendre OÙ il marche, pas seulement
	# QU'il marche — sinon le son ajoute du bruit et pas de l'information.
	var at := Vector3(Geo.position_x(whole), 0.0, Geo.far_soldier_z())
	var distance := _camera.global_position.distance_to(at)
	if distance >= STEP_AUDIBLE_RANGE:
		return
	AudioManager.play_sfx("trench_step",
		lerpf(-6.0, -26.0, clampf(distance / STEP_AUDIBLE_RANGE, 0.0, 1.0)))


# LE DÉPART DE FEU ADVERSE — poussé par l'hôte depuis l'événement serveur `fire` de l'autre camp.
# ⚠️ `from_pos` vient de l'ÉVÉNEMENT et non de l'état : au moment où l'hôte le reçoit, l'adversaire
# peut déjà s'être accroupi, donc sa position aurait disparu de la vue redactée. Un tir TRAHIT son
# auteur (c'est la règle assumée du §1.6, la même qui rend le `from_pos` des projectiles public) —
# mais il ne le trahit qu'à l'instant où il a tiré.
# §8.151 (2bis) — appelé UNE FOIS PAR PROJECTILE de la rafale adverse (crans cadencés par l'hôte
# sur les `launch_tick` serveur) : re-poser `_enemy_muzzle_left` à chaque cran fait PULSER la lueur
# (0,035 s de vie ≪ 100 ms d'espacement) au vrai rythme de la mitraille — trois éclats, pas un.
func notify_enemy_fire(from_pos: int) -> void:
	if _enemy_muzzle == null:
		return
	_enemy_muzzle.position = _muzzle_origin(from_pos, false)
	_enemy_muzzle.visible = true
	_enemy_muzzle_left = ENEMY_MUZZLE_TIME
	# §8.153 — ET LE CORPS TIRE, LUI AUSSI. Jusqu ici un tir adverse ne produisait qu une sphere
	# de lueur : le soldat restait parfaitement immobile pendant qu une balle partait de lui.
	# ⚠️ On passe par `set_enemy_action`, donc par la machine a frames et ses priorites (« hit »
	# interrompt tout sauf la mort). Ecrire la frame directement contournerait cette regle-la.
	set_enemy_action(Sprites.ENEMY_FIRE)


# Origine d'un tir : l'œil du tireur, dans SA tranchée.
func _muzzle_origin(from_pos: int, mine: bool) -> Vector3:
	var z: float = Geo.near_soldier_z() if mine else Geo.far_soldier_z()
	return Vector3(Geo.position_x(from_pos), Geo.EYE_UP, z)


# ╔═ ⚠️ UNE GRENADE NE SORT PAS D'UN ŒIL — ELLE SORT D'UNE MAIN (leçon §7.2) ════════════════════╗
# ║ Le §7.2 du rapport de pivot a coûté un défaut vu en capture : la traçante naissait à            ║
# ║ `_muzzle_origin`, c'est-à-dire à la position de l'ŒIL, et la boîte dorée couvrait un carré de   ║
# ║ ~10° au milieu de l'écran. Pour une balle, on a masqué le premier mètre. Pour une GRENADE, ce   ║
# ║ remède ne marche pas : elle part LENTEMENT et en cloche, elle passerait donc plusieurs dixièmes ║
# ║ de seconde devant la pupille avant de se dégager, et la masquer reviendrait à ne plus montrer   ║
# ║ le début de son arc — c'est-à-dire l'information qui rend le lancer lisible.                     ║
# ║ On la fait donc naître LÀ OÙ ELLE NAÎT : à la main, en bas à droite du champ ⚙.                  ║
# ║ ⚠️ LE SIGNE : « à droite de l'ÉCRAN » vaut −X dans le repère droitier de l'arène (le pavé de     ║
# ║ `trench_geometry.gd` — « +X sort à GAUCHE », mesuré, et ça a coûté une partie entière). Pour le  ║
# ║ lanceur d'en face, sa droite est notre gauche : le signe s'inverse, exactement comme dans        ║
# ║ `_shot_direction`.                                                                               ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const HAND_LATERAL := 0.35
const HAND_VERTICAL := -0.25


func _grenade_origin(from_pos: int, mine: bool) -> Vector3:
	var eye := _muzzle_origin(from_pos, mine)
	var lateral: float = -HAND_LATERAL if mine else HAND_LATERAL
	return eye + Vector3(lateral, HAND_VERTICAL, 0.0)


# Direction d'un tir dans MON repère.
# ⚠️ MIROIR : le tireur d'en face vise dans SON repère, dont le +Z pointe vers moi. Le passage
# d'un repère à l'autre est la réflexion (x, y, z) → (x, y, NO_MANS_LAND − z) : elle laisse le lacet
# inchangé et RETOURNE la composante en Z. D'où le signe ci-dessous — c'est la même convention de
# miroir que la table angulaire, qui sert aux deux camps sans inversion d'index.
func _shot_direction(yaw_deg: float, pitch_deg: float, mine: bool) -> Vector3:
	var dir := _direction(yaw_deg, pitch_deg)
	return dir if mine else Vector3(dir.x, dir.y, -dir.z)


# ╔═ ⚠️⚠️ MA TRAÇANTE ÉTAIT DESSINÉE APRÈS LE HITMARKER — L'ORDRE ÉTAIT INVERSÉ ══════════════════╗
# ║ Mesuré en relisant le chemin complet : le HITMARKER part de l'ÉVÉNEMENT `hit`, joué DÈS que le ║
# ║ message d'état arrive (~246 ms après le clic). La TRAÇANTE, elle, était bâtie depuis la paire  ║
# ║ de rendu RETARDÉE (`render_tick`, un tick en arrière) : elle apparaissait ~100 ms PLUS TARD.   ║
# ║ Le joueur voyait donc, dans cet ordre : son clic → la confirmation qu'il a touché → et ENFIN   ║
# ║ la balle qui part. Aucun réglage de vitesse ne peut réparer ça : c'est une inversion, pas une  ║
# ║ lenteur — et elle explique une bonne part du « c'est mou » ressenti.                            ║
# ║                                                                                                 ║
# ║ ⚠️ ON NE DÉCIDE TOUJOURS AUCUNE TOUCHE. Cette traçante dit « J'AI TIRÉ », et le joueur le sait ║
# ║ déjà — il vient de cliquer. C'est exactement le raisonnement de `_local_fire_feedback` pour le  ║
# ║ recul, la détonation et le départ de feu (§6.3 du rapport de pivot). Le HITMARKER, lui, dit    ║
# ║ « J'AI TOUCHÉ » : ça, seul le serveur le sait, et il reste strictement serveur.                 ║
# ║ ⚠️ Tant qu'une traçante LOCALE vit, les traçantes MIENNES venues de l'état sont supprimées —    ║
# ║ sans quoi le même tir serait dessiné deux fois, à 100 ms d'écart.                               ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ╔═ §8.151 (2bis) — LA RAFALE EST CADENCÉE PAR L'HÔTE, PAS ICI ═════════════════════════════════╗
# ║ Depuis l'effet mitraillette (§4bis.4), `trench_fp.gd` appelle cette fonction UNE FOIS PAR      ║
# ║ PROJECTILE, à l'instant où le serveur fait réellement partir chaque balle (`burst_gap_ticks`   ║
# ║ du registre côté local, `launch_tick` par projectile côté événement) : chaque cran a SA        ║
# ║ traçante, née à son heure — plus une gerbe superposée au clic. Le paramètre `rounds` reste en  ║
# ║ REPLI pour un appelant qui présenterait encore une rafale d'un bloc : le décalage cosmétique    ║
# ║ de -0,03 n'existe que pour que ces traçantes-là ne se confondent pas au pixel près.            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func notify_local_shot(from_pos: int, yaw_deg: float, pitch_deg: float, seconds: float,
		rounds: int) -> void:
	for i in range(maxi(1, rounds)):
		_local_tracers.append({"from_pos": int(from_pos), "yaw": yaw_deg, "pitch": pitch_deg,
			"t": -0.03 * float(i), "life": maxf(0.05, seconds)})


func _advance_local_tracers(delta: float) -> void:
	if _local_tracers.is_empty():
		return
	var alive: Array = []
	for shot in _local_tracers:
		shot["t"] = float(shot["t"]) + delta / float(shot["life"])
		if float(shot["t"]) < 1.0:
			alive.append(shot)
	_local_tracers = alive


func _render_tracers(tracers: Array) -> void:
	# LES LOCALES D'ABORD, puis celles de l'état — desquelles on retire les MIENNES tant qu'une
	# locale vit, pour ne pas dessiner deux fois le même tir à 100 ms d'écart.
	var shots: Array = []
	for local in _local_tracers:
		shots.append({"from_pos": int(local["from_pos"]), "mine": true,
			"t": clampf(float(local["t"]), 0.0, 1.0),
			"yaw": float(local["yaw"]), "pitch": float(local["pitch"])})
	var mute_mine: bool = not _local_tracers.is_empty()
	for entry in tracers:
		if mute_mine and bool((entry as Dictionary).get("mine", false)):
			continue
		shots.append(entry)

	for i in range(_tracers.size()):
		var node := _tracers[i]
		if i >= shots.size():
			node.visible = false
			continue
		var shot: Dictionary = shots[i]
		var mine := bool(shot.get("mine", false))
		var origin := _muzzle_origin(int(shot.get("from_pos", 2)), mine)
		var dir := _shot_direction(float(shot.get("yaw", 0.0)), float(shot.get("pitch", 0.0)), mine)
		var travelled: float = clampf(float(shot.get("t", 0.0)), 0.0, 1.0) * Geo.NO_MANS_LAND
		var head := origin + dir * travelled
		# ╔═ ⚠️⚠️ MA PROPRE TRAÇANTE NAÎT DANS MON ŒIL — VU EN CAPTURE ═════════════════════════╗
		# ║ L'origine d'un tir est `_muzzle_origin`, c'est-à-dire l'ŒIL du tireur. Pour l'ADVERSE ║
		# ║ c'est sans conséquence (il est en face) ; pour le MIEN, la boîte dorée se retrouve à  ║
		# ║ quelques centimètres de la caméra et, vue de face, elle couvre un carré de ~10° au    ║
		# ║ milieu de l'écran. Le rapprochement de l'arène à 12 m l'a AGGRAVÉ : à `t` égal, la    ║
		# ║ balle a parcouru trois fois moins de mètres, donc elle s'attarde trois fois plus      ║
		# ║ longtemps devant l'œil. On ne la montre donc qu'une fois le canon dégagé.             ║
		# ╚═══════════════════════════════════════════════════════════════════════════════════════╝
		if mine and travelled < MUZZLE_CLEAR:
			node.visible = false
			continue
		# La traçante est un SEGMENT (la balle a une longueur apparente), pas un point. Sa queue ne
		# recule jamais en deçà du canon dégagé, sinon elle repointerait vers l'œil.
		var tail_at: float = maxf(MUZZLE_CLEAR if mine else 0.0,
			travelled - Geo.NO_MANS_LAND * TRACER_LENGTH_RATIO)
		var tail := origin + dir * tail_at
		node.visible = true
		node.position = (head + tail) * 0.5
		# ╔═ ⚠️⚠️ `look_at(head)` ÉCHOUAIT 849 FOIS PAR PARTIE — TROUVÉ DANS `user://logs/godot.log` ═╗
		# ║ « Node origin and target are in the same position, look_at() failed. » En début de vol,   ║
		# ║ `travelled == tail_at` : la tête et la queue sont CONFONDUES, donc `position == head` et  ║
		# ║ `look_at` reçoit une cible à distance nulle. Ça se produit à CHAQUE traçante adverse au   ║
		# ║ tick de son lancer, et à chaque traçante mienne à l'instant où elle dégage le canon —     ║
		# ║ soit des centaines d'erreurs par duel, crachées depuis `_process`.                        ║
		# ║ ⚠️ La ligne suivante avait DÉJÀ son garde (`maxf(0.4, …)` sur l'échelle) : le cas          ║
		# ║ dégénéré était connu d'une ligne et oublié de l'autre.                                    ║
		# ║ On oriente donc sur la DIRECTION DE TIR — un vecteur unitaire, jamais nul — au lieu d'un  ║
		# ║ point qui peut coïncider avec l'origine. C'est aussi plus juste : l'axe d'une traçante    ║
		# ║ EST sa trajectoire, pas le segment qu'il lui reste à parcourir.                           ║
		# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
		node.look_at(node.position + dir, Vector3.UP)
		node.scale = Vector3(1.0, 1.0, maxf(0.4, head.distance_to(tail)))


func _render_grenades(grenades: Array, markers: Array) -> void:
	for i in range(_grenades.size()):
		var node := _grenades[i]
		if i >= grenades.size():
			node.visible = false
			continue
		var g: Dictionary = grenades[i]
		var mine := bool(g.get("mine", false))
		var origin := _grenade_origin(int(g.get("from_pos", 2)), mine)
		var land_z: float = Geo.far_soldier_z() if mine else Geo.near_soldier_z()
		# ⚠️ LA GRENADE TOMBE AU FOND DE LA TRANCHÉE (y ≈ 0), PAS au niveau du no man's land :
		# les positions du duel sont DANS les tranchées. Défaut vu en CAPTURE seulement — posé à
		# `GROUND_Y` (1,0 m), le marqueur passait AU-DESSUS des yeux d'un accroupi (0,90 m) et
		# noyait tout l'écran de rouge. Un boot headless ne l'aurait jamais montré.
		# ⚠️ `target_x` EN MÈTRES, et non plus l'abscisse d'une case (§8.141) : la grenade tombe
		# exactement là où le décalque l'annonçait depuis le lancer. Reconstruire le point depuis
		# `target_pos` ferait dériver la cloche jusqu'à 1,7 m du cercle affiché — c'est-à-dire les
		# deux tiers du rayon d'action, dans une arme dont TOUTE la lisibilité est ce rayon.
		var target := Vector3(float(g.get("target_x", 0.0)), MARKER_Y, land_z)
		var t: float = clampf(float(g.get("t", 0.0)), 0.0, 1.0)
		# CLOCHE : une parabole franche — c'est elle qui rend le temps de vol lisible à l'œil.
		# ⚠️ Sa hauteur est une FRACTION de la portée, pas 6 m en dur : avec le passage de 35 m à
		# 12 m (§8.140.1), une cloche de 6 m sur 12 m de portée aurait envoyé la grenade quasiment
		# à la verticale — une lune, pas un lancer.
		var flat := origin.lerp(target, t)
		flat.y += sin(t * PI) * Geo.NO_MANS_LAND * 0.17
		node.visible = true
		node.position = flat

	for i in range(_markers.size()):
		var node := _markers[i]
		if i >= markers.size():
			node.visible = false
			continue
		var m: Dictionary = markers[i]
		var on_my_side := bool(m.get("on_my_side", false))
		var z: float = Geo.near_soldier_z() if on_my_side else Geo.far_soldier_z()
		node.visible = true
		node.position = Vector3(float(m.get("target_x", 0.0)), MARKER_Y, z)
		var incoming: bool = bool(m.get("on_my_side", false))
		# ╔═ L'ANNEAU PULSE, MAIS SON RAYON MOYEN NE MENT PAS ═══════════════════════════════════╗
		# ║ La pulsation accélère à l'approche de l'impact — c'est la lecture de la menace sans   ║
		# ║ chiffre ni compte à rebours. Mais elle bat AUTOUR du rayon réel (±8 %), et non de 75 % ║
		# ║ à 100 % de celui-ci comme le faisait l'ancien disque : un cercle qui passe la moitié   ║
		# ║ de son temps SOUS sa taille réelle promet une zone plus petite que la vraie, et c'est  ║
		# ║ précisément ce qu'on vient de corriger. La respiration est cosmétique, le rayon non.   ║
		# ╚═══════════════════════════════════════════════════════════════════════════════════════╝
		var eta: float = clampf(float(m.get("eta", 1.0)), 0.0, 1.0)
		var pulse: float = 1.0 if _reduced_motion else (1.0 + 0.08 * sin((1.0 - eta) * 26.0))
		var open: float = _grenade_radius * pulse
		node.scale = Vector3(open, 1.0, open)
		# ⚠️ ROUGE quand elle tombe CHEZ MOI, OR quand elle tombe chez lui. Un marqueur d'une seule
		# couleur laissait le joueur décider, en pleine action, si le cercle qu'il voit est une
		# menace ou son propre lancer — deux lectures opposées pour la même image.
		_tint_zone(node, COL_DANGER if incoming else COL_GRENADE_OK,
			0.30 + 0.45 * (1.0 - eta))


func _render_laser(laser: Dictionary) -> void:
	if _laser == null:
		return
	if not bool(laser.get("active", false)):
		_laser.visible = false
		return
	var mine := bool(laser.get("mine", false))
	var origin := _muzzle_origin(int(laser.get("from_pos", 2)), mine)
	var dir := _shot_direction(float(laser.get("yaw", 0.0)), float(laser.get("pitch", 0.0)), mine)
	var tip := origin + dir * Geo.NO_MANS_LAND
	_laser.visible = true
	_laser.position = (origin + tip) * 0.5
	_laser.look_at(tip, Vector3.UP)
	_laser.scale = Vector3(1.0, 1.0, origin.distance_to(tip))


# =================================================================================================
# LECTURES — réservées au harnais de recette (§8.138). Aucune logique de jeu ne les appelle.
# =================================================================================================
func enemy_frame() -> String:
	return _enemy_frame


func enemy_is_painted() -> bool:
	return _enemy_painted


func enemy_sprite_node() -> Sprite3D:
	return _enemy_sprite


func enemy_root_node() -> Node3D:
	return _enemy
