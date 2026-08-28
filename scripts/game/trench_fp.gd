extends Control
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — CONTRÔLEUR du duel en VUE À LA PREMIÈRE PERSONNE.
#
# Remplace la vue de côté v1 (§1.7). La scène est 100 % code-driven (patron company_screen /
# events_screen / trench_duel v1) et se compose en QUATRE COUCHES (§2.3) :
#
#   COUCHE 1  décor PRÉ-RENDU de la pose courante (`TextureRect` plein écran)
#             → absent ? on montre le GREYBOX du blockout, aligné PAR DÉFINITION (c'est la même
#               caméra qui a servi à générer les décors — cf. tools/gen_trench_renders.gd).
#   COUCHE 2  `trench_fp_world.tscn` : SubViewport 3D transparent — blockout, soldat adverse,
#             traçantes, grenades + marqueurs au sol, laser, ET le viewmodel (choix motivé sur place).
#   COUCHE 3  le VIEWMODEL PEINT (§8.138) — `trench_viewmodel.gd`, couche 2D à frames en bas-droite.
#             → arme sans fichiers ? ce nœud s'efface et le viewmodel en PRIMITIVES du SubViewport
#               (couche 2) reprend le service pour CETTE arme. Aiguillage unique : `_apply_weapon`.
#   COUCHE 4  le HUD (LOT D).
#
# ╔═ CE QUE CE SCRIPT NE FAIT JAMAIS ═════════════════════════════════════════════════════════════╗
# ║ • Il ne DÉCIDE aucune touche. Il envoie une DIRECTION DE VISÉE ; le serveur résout contre sa   ║
# ║   table angulaire et son état. Le hitmarker ne s'allume que sur un événement `hit` CONFIRMÉ —  ║
# ║   jamais en optimiste (l'honnêteté du feedback est une règle maison, pas un détail).           ║
# ║ • Il ne devine pas une position masquée. Quand la redaction §1.6 renvoie `pos: null`,          ║
# ║   l'adversaire s'efface en fondu là où on l'a vu — et le client N'A PAS l'information.         ║
# ║ • Il n'embarque AUCUN barème : armes, chargeurs, dispersion, cotes d'arène et bandage          ║
# ║   arrivent tous dans `trench_init.rules` (`public_rules()` serveur).                           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ENTRÉES (§5.6) : Q/D ou ◀▶ = position · S ou CTRL = posture (bascule) · SOURIS = visée ·
# clic gauche = tir · G ou clic droit MAINTENU = grenade (jauge + arc) · R = rechargement ·
# 2 = bandage · 1/2 = choix d'arme pendant la fenêtre · ÉCHAP = abandon (confirmation).
# =================================================================================================

const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")
const WorldScene := preload("res://scenes/game/trench_fp_world.tscn")
# §8.152 (lot 3D-H) — **LA BASCULE TIENT EN CETTE LIGNE.** L'hôte 3D présente exactement
# l'API du viewmodel 2D peint et traduit vers le rig en interne. Les huit sites d'appel de
# ce fichier n'ont pas bougé d'un caractère — ce qui veut dire que **le retour arrière tient
# lui aussi en cette ligne**, et c'est la seule raison pour laquelle un remplacement de cette
# ampleur peut se faire sans filet.
# ⚠️ L'ancien reste en place et compile : `trench_viewmodel.gd` n'est PAS supprimé tant que
# les captures avant/après n'ont pas été jugées.
const ViewmodelScript := preload("res://scripts/game/trench_viewmodel3d_host.gd")
const AmbientScript := preload("res://scripts/game/trench_ambient.gd")
const TuningScript := preload("res://scripts/game/trench_tuning.gd")
const CelebrationScript := preload("res://scripts/ui/unlock_celebration.gd")
const Springs := preload("res://scripts/game/trench_springs.gd")
const FlinchShader := preload("res://shaders/trench_flinch.gdshader")

# Arme de départ du duel (miroir de `trench_sim.STARTING_WEAPON`) — sert AVANT le premier état,
# le temps que le serveur nous dise où en est l'escalade.
const STARTING_WEAPON := "vipere"

# Cadence d'envoi : STRICTEMENT sous les 10 msg/s du serveur (anti-flood §2.3) — à 0,1 s pile, la
# gigue ferait parfois tomber 11 messages dans la même seconde serveur et le 11ᵉ (peut-être un
# TIR) serait jeté. 0,105 s garantit <= 10 par seconde pleine. (Leçon conservée de la v1.)
const SEND_INTERVAL := 0.105
# ╔═ RETARD DE RENDU — 150 → 100 ms AVEC LE VOL À 1 TICK (§8.141.2) ══════════════════════════════╗
# ║ C'est un tampon de gigue : à 10 Hz, rendre en retard garantit qu'on a toujours deux états      ║
# ║ entre lesquels interpoler même si l'un arrive en retard. Il coûtait 150 ms sur les 696 ms du   ║
# ║ budget clic → touche, et il coûtait DEUX FOIS : il retarde la touche, et il fait viser une     ║
# ║ image vieille de 150 ms — c'est-à-dire, mot pour mot, « dès que je clique il s'est déjà        ║
# ║ déplacé ».                                                                                      ║
# ║ ⚠️ 100 ms = EXACTEMENT un tick : c'est le plancher défendable, pas un chiffre rond. En dessous ║
# ║ on n'a plus d'état d'avance du tout et la moindre gigue fait figer l'adversaire.                ║
# ║ ⚠️ Ce qu'on peut se permettre depuis le §8.140 : l'adversaire est rendu par PAS DISCRETS, plus ║
# ║ par un glissé continu — il a donc bien moins besoin d'interpolation qu'avant.                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const RENDER_DELAY := 0.05
const RECONNECT_DELAY := 2.0

# --- Visée ---------------------------------------------------------------------------------------
# ╔═ LA SENSIBILITÉ N'EST PLUS UNE CONSTANTE : ELLE SE RÈGLE EN JEU (touche F10) ═════════════════╗
# ║ 0,055 puis 0,040 °/px ont été choisis par raisonnement, sans jamais avoir été éprouvés — et le ║
# ║ verdict du seul essai réel a été « le mouvement de la souris est inversé et pas du tout facile ║
# ║ à gérer ». Le code cesse donc de deviner : `trench_tuning.gd` expose sensibilité, inversion Y, ║
# ║ suivi de caméra, plafond et FOV à Hakim, qui règle en jouant. 0,040 reste la valeur de départ. ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
var _sensitivity: float = TuningScript.defaults()["mouse_sensitivity"]
var _invert_y: bool = TuningScript.defaults()["invert_y"]
# Le plafond de lacet, résolu une fois : c'est une conséquence de la géométrie, pas un réglage
# (cf. `aim_yaw_limit()` plus bas). Le relire à chaque événement souris serait refaire 25 arc-
# tangentes par mouvement de main.
var _yaw_limit: float = aim_yaw_limit()

# ╔═ ⚠️⚠️ LE +X DU MONDE EST À GAUCHE DE L'ÉCRAN — MESURÉ, PAS SUPPOSÉ ═══════════════════════════╗
# ║ `trench_geometry.gd` annonce « +X = ma droite » depuis le §8.137. Personne ne l'avait jamais    ║
# ║ vérifié CONTRE LA CAMÉRA, et c'est faux : on regarde vers +Z, et dans un repère DROITIER un     ║
# ║ observateur tourné vers +Z avec +Y en haut a sa droite en −X. Mesure au harnais, position       ║
# ║ centrale, visée nulle : la position adverse 4 (x = +8 m) se projette à 719 px et la position 0  ║
# ║ (x = −8 m) à 1201 px. Le « +X » du registre sort donc bel et bien à GAUCHE.                     ║
# ║                                                                                                 ║
# ║ Conséquence, et c'est UNE SEULE CAUSE pour DEUX symptômes rapportés en partie réelle :          ║
# ║   • « quand je bouge la souris vers la droite, le soldat vise vers la gauche » ;                ║
# ║   • « les flèches droite et gauche sont également inversées ».                                  ║
# ║ Le §8.139.1 ne pouvait pas le voir : à 6° de rotation de caméra, rien ne tournait assez pour    ║
# ║ qu'un sens s'affirme. Le pivot, en rendant la caméra libre, a rendu le défaut évident.          ║
# ║                                                                                                 ║
# ║ ⚠️ ON CORRIGE À L'ENTRÉE, PAS DANS LA GÉOMÉTRIE. `trench_geometry.gd` est la source de vérité   ║
# ║ PARTAGÉE AVEC LE SERVEUR : y toucher au signe rendrait la table angulaire fausse et imposerait  ║
# ║ un redéploiement pour un défaut de PRÉSENTATION. Le lacet et le déplacement envoyés restent     ║
# ║ ceux du monde ; on ne change que la façon dont la main du joueur s'y traduit.                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const SCREEN_TO_WORLD_X := -1.0
# ╔═ LE DÉBATTEMENT N'EST PLUS UNE CONSTANTE — IL SORT DE LA GÉOMÉTRIE (§8.141) ══════════════════╗
# ║ Il a valu 32°, puis 58°, chaque fois reposé À LA MAIN après un changement de cote. La première ║
# ║ fois, l'oublier aurait rendu trois positions sur cinq mécaniquement INJOIGNABLES depuis les    ║
# ║ bords : le joueur aurait visé une cible que son propre plafond lui interdisait d'atteindre, et ║
# ║ la balle n'aurait même pas pu être déclarée. Un chiffre qu'il faut penser à remettre à jour est ║
# ║ un chiffre qui sera oublié — celui-ci est donc DÉRIVÉ du plus grand lacet que les fenêtres de  ║
# ║ tir réclament (`Geo.max_window_yaw_deg()`), plus une marge.                                    ║
# ║ La marge elle-même vit dans le registre (`Geo.AIM_YAW_MARGIN`), avec les cotes dont elle       ║
# ║ dépend. Valeurs du jour : fenêtres à ±54,3° → débattement ±60,3°.                              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Le site reste étroit — il n'y a rien à viser au ciel.
const AIM_PITCH_LIMIT := 14.0


# STATIQUE, et pas une variable d'instance : les harnais de recette et l'aperçu s'y réfèrent SANS
# instancier de duel, exactement comme ils le faisaient de l'ancienne constante.
static func aim_yaw_limit() -> float:
	return Geo.aim_yaw_limit_deg()
# Quantum d'envoi (§2.4) : la visée part arrondie au dixième de degré, et SEULEMENT si elle a bougé.
const AIM_QUANTUM := 0.1

const COL_ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const COL_GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const COL_TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const COL_MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const COL_DANGER := Color(0.839216, 0.270588, 0.247059, 1)
const COL_PANEL := Color(0.058824, 0.07451, 0.094118, 0.92)

# Salle à rejoindre, posée par l'écran Événements AVANT le changement de scène (patron
# `CompanyScreen.target_tag`). "" = arrivée hors flux (retour hub immédiat).
static var pending_room_id: String = ""

# --- Réseau / état -------------------------------------------------------------------------------
var _rules: Dictionary = {}
var _my_slot: int = 1
var _training := false
var _opponent: Dictionary = {}
var _buffer: Array = []
var _result: Dictionary = {}
var _match_over := false
var _tick_rate := 10.0
var _positions := 5

# --- Prédiction locale (position/posture UNIQUEMENT — §2.4) --------------------------------------
var _pred_pos: int = 2
var _pred_stance: String = "up"
var _pred_move_ready := 0.0
var _mismatch_streak := 0

# --- Visée ---------------------------------------------------------------------------------------
var _aim_yaw := 0.0
var _aim_pitch := 0.0
var _sent_aim := Vector2(9999.0, 9999.0)
# Visée FIGÉE à l'instant du clic — c'est elle qui part avec le tir, pas celle de l'envoi.
var _fire_aim := Vector2.ZERO
# Fenêtre pendant laquelle l'événement `fire` du serveur ne REJOUE pas le retour d'arme déjà joué
# localement. Un seul événement `fire` par pression côté serveur (la rafale naît dedans), donc une
# fenêtre suffit — elle n'avalera jamais un second tir légitime.
# ⚠️ §8.151 (2bis) : elle n'est posée QUE lorsqu'un retour d'arme a RÉELLEMENT été joué au clic —
# donc jamais pour un tir télégraphié (CONDOR), dont le clic ne joue rien. Elle ne court plus
# jamais contre `laser_lead_ticks` : c'était la course que le condor perdait.
var _fire_fx_mute := 0.0

# ╔═ §8.151 (VAGUE 2bis) — L'« EFFET MITRAILLETTE » : la rafale se PRÉSENTE par projectile ═══════╗
# ║ AVANT : un tir à `burst > 1` (FRELON ×3, CHACAL ×2) était AGRÉGÉ en UNE détonation, UN kick et  ║
# ║ des traçantes superposées au même instant — alors que le serveur espace ses projectiles de      ║
# ║ `burst_gap_ticks` (2 ticks = 100 ms : `_fire_burst`, launch = tick + i × gap). C'est LE défaut  ║
# ║ nommé par le cahier §4bis.4. Désormais chaque projectile a SA détonation (round-robin de la     ║
# ║ famille de l'arme), SA traçante, SON flash et SON cran de recul (réduit, cumul borné).          ║
# ║ CADENCEMENT — deux sources, jamais une minuterie inventée :                                     ║
# ║  • côté LOCAL (mon clic, prédit §8.141.9) : `burst_gap_ticks` LU au registre `trench_init`      ║
# ║    (§8.137 : aucune valeur d'arme en dur) — le serveur cadencera EXACTEMENT pareil ;            ║
# ║  • côté ADVERSE : les `launch_tick` PAR PROJECTILE du flux d'états font foi (l'état du même     ║
# ║    message que l'événement `fire` porte déjà toute la rafale) ; le registre n'est qu'un repli.  ║
# ║ Un clic REFUSÉ ne planifie RIEN (§8.141.9) : la file ne se remplit que depuis un tir accepté    ║
# ║ par la prédiction ou confirmé par le serveur. Elle se vide en < 0,25 s (2 crans × 100 ms).      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Cran de rafale : kick RÉDUIT de ~40 % par coup suiveur (le premier coup garde le kick plein). Le
# cumul reste borné par l'existant : roulis plafonné ROLL_CAP_DEG, punch de FOV posé en VALEUR (pas
# additionné), ressorts du viewmodel à décroissance entre deux crans (API feel INCHANGÉE).
const BURST_KICK_SCALE := 0.6
# Volume du télégraphe CONDOR audible (§3.6) : discret — un avertissement, pas une sirène.
const LASER_WARN_DB := -6.0
# Crans de rafale EN ATTENTE : {due, mode local|mine_event|enemy, weapon, pos, yaw, pitch, flight_s}.
var _burst_queue: Array = []
# Verrou « une fois par visée » du télégraphe CONDOR audible — armé sur le front MONTANT du signal
# de rendu du laser ADVERSE, relâché quand le rayon s'éteint (tir parti, annulation, accroupi).
var _laser_warn_latch := false
# Jeton de la voix qui porte ce bourdonnement (§8.151 2bis) : il sert à le COUPER quand le rayon
# s'éteint, et à lui seul — si la voix a été reprise entre temps, l'arrêt est un no-op. −1 = aucune.
var _laser_warn_token := -1

# --- Entrées coalescées entre deux envois --------------------------------------------------------
var _send_accum := 0.0
var _sent_at: Array = []           # horodatages des envois de la dernière seconde (anti-flood)
var _fire_queued := false

# ╔═ §8.152.1 — LES DEUX CAUSES DE « LE CONDOR RATE DES TIRS » ═══════════════════════╗
# ║ Verdict de partie réelle : « la latence entre le clic et le tir effectif, et des fois ça  ║
# ║ tire même pas ». Deux défauts distincts, tous deux CÔTÉ CLIENT — aucune règle en cause :  ║
# ║                                                                                            ║
# ║ **(a) LE CLIC PERDU.** `_queue_fire()` interroge `_fire_refusal()` ; si la cadence n'est  ║
# ║ pas échue, le clic est **jeté** avec un clac de refus. Le condor a `cooldown_ticks = 22`  ║
# ║ à 20 Hz, soit **1,10 s** où TOUT clic disparaît. Un joueur qui anticipe de 150 ms perd son ║
# ║ tir et doit recliquer — c'est le « ça tire même pas ».                                   ║
# ║                                                                                            ║
# ║ **(b) LE CLIC SANS ACCUSÉ DE RÉCEPTION.** Un tir télégraphié ne produit RIEN localement au  ║
# ║ clic (c'est la règle du §8.151-2bis, et elle est JUSTE : pas de faux coup). Le pavé        ║
# ║ affirmait que « le retour immédiat existe déjà : c'est le rayon laser » — **mais le rayon  ║
# ║ est rendu depuis l'ÉTAT SERVEUR.** Il n'apparaît donc qu'après un aller-retour réseau,     ║
# ║ par-dessus les 0,5 s de télégraphe. Entre les deux : le silence complet.                   ║
# ║                                                                                            ║
# ║ ⛔ CE QUI N'EST PAS TOUCHÉ : la cadence, le télégraphe, la dispersion. Hakim accepte la     ║
# ║ latence ENTRE les tirs (« ça reste un sniper ») — ce qui n'est pas acceptable, c'est de   ║
# ║ PERDRE un tir. Le tampon ne fait jamais tirer plus vite : il ne fait que déplacer un clic  ║
# ║ au premier instant OÙ IL EST LÉGAL, et le serveur reste seul juge.                         ║
# ╚══════════════════════════════════════════════════════════════════════════════════════════╝
#
# La fenêtre de tampon. ⚠️ Elle n'est pas choisie au goût : l'anticipation humaine sur un signal
# attendu se situe vers **150 à 250 ms**, et 250 ms couvrent 5 pas de simulation à 20 Hz et deux
# envois du budget anti-flood (9 msg/s). En deçà, un joueur précis perd encore des tirs ; au-delà,
# le tampon commencerait à ressembler à du tir automatique et à tirer à la place du joueur.
const FIRE_BUFFER := 0.25
var _fire_buffer_until := 0.0

# Prédiction locale du rayon laser — même nature que `_pred_fire_ready` et `_pred_pos`, qui sont
# prédits depuis toujours dans ce fichier. Elle est BORNÉE : passée la fenêtre, seul l'état
# serveur parle. Si le serveur refuse le tir, le rayon prédit disparaît — comme toute prédiction.
var _laser_pred_until := 0.0
var _laser_pred_aim := Vector2.ZERO
var _laser_pred_pos := 2
var _throw_queued: Dictionary = {}
var _pick_queued := ""
var _reload_queued := false
var _item_queued := ""
# --- §8.141 : LE GESTE DE GRENADE (la jauge de charge est abandonnée) ---------------------------
# `_aiming_grenade` = la touche est maintenue et le décalque est à l'écran.
# `_grenade_point`  = l'abscisse VISÉE, en mètres sur l'axe du front, recalculée à chaque frame.
# `_grenade_cancelled` = verrou d'annulation, levé seulement quand la touche est VRAIMENT relâchée.
# `_grenade_refuse` = durée restante du refus visuel (stock vide) — jamais un silence.
var _aiming_grenade := false

# ╔═ §8.152 (lot 3D-H) — LA VISÉE À L'ŒIL ═════════════════════════════════╗
# ║ ⚠️ 100 % CONFORT, AUCUN AVANTAGE — et c'est vérifiable, pas promis. La visée resserre    ║
# ║ le champ du viewmodel et la sensibilité de la souris. Elle ne touche **ni la dispersion, ║
# ║ ni la cadence, ni la fenêtre de touche** : ce que le serveur reçoit est bit-identique     ║
# ║ qu'on vise ou non, et `probe_trench_feel_aim` le prouve déjà pour le reste du confort.  ║
# ║                                                                                            ║
# ║ ⛔ Le rig 3D ne détient PAS cette valeur, il la REÇOIT. Chez la référence, `adsT` vit dans ║
# ║ le viewmodel et la dispersion le lit (`index.js:223` puis `:662`) — la précision dépend    ║
# ║ alors d'une variable d'animation. C'est l'inversion que le §8.141.6 interdit.              ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════╝
var _ads_active := false
var _ads_held_prev := false
var _ads_toggle: bool = TuningScript.defaults()["ads_toggle"]

# Poussés depuis `_refresh_hud` : le rig est une VUE, il ne relit jamais l'état serveur.
# (Même contrat que le viewmodel peint — « on le lui pousse ».)
var _rig_weapon := ""
var _rig_empty := false
var _grenade_point := 0.0
var _grenade_cancelled := false
var _grenade_refuse := 0.0
# ⚠️ LA CADENCE EST PRÉDITE, PAS LUE : `fire_ready_tick` n'est PAS diffusé dans l'état (cf.
# `public_state`). On la tient donc localement, comme `_pred_move_ready` pour le déplacement, et on
# la RÉCONCILIE sur l'événement `fire` du serveur — la seule source qui dise « ce tir est parti ».
var _pred_fire_ready := 0.0
var _fire_refuse := 0.0
# §8.151 (LOT A) : la CULASSE du réarmement. Armée UNIQUEMENT par un tir RÉEL (retour d'arme local
# prédit, ou tir confirmé par l'événement `fire` du serveur) — JAMAIS par un clic refusé
# (§8.141.9 : un refus ne joue rien de balistique). Le clac part quand `_clock` franchit
# `_pred_fire_ready`, la porte de cadence prédite — elle-même dérivée du registre des règles
# (`cooldown_ticks / tick_rate`), aucun barème recopié.
var _bolt_armed := false
var _stance_toggle := false

# --- FX éphémères --------------------------------------------------------------------------------
# Durée de vie du hitmarker, en secondes — UNE seule constante pour la pose et pour le fondu (les
# deux valaient 0,35 en dur à deux endroits, et un jour l'une des deux aurait bougé sans l'autre).
const HITMARKER_TIME := 0.35
var _hitmarker := 0.0
# §8.151 (2ter, §4bis.2) — CE QUE LE HITMARKER DIT DE PLUS, et rien qu'à partir de l'événement.
# `_hitmarker_kill` : ce coup a mis la cible à 0 PV (`hp` de l'événement `hit`) → croix ROUGE.
# `_hitmarker_scale` : échelle DISCRÈTE du coup = dégâts de l'événement rapportés à `hp_max` du
# registre (jamais un barème d'arme recopié). Les deux sont POSÉS par l'événement serveur et par
# lui seul — un tir refusé, une balle qui manque ou un dégât SUBI n'y écrivent jamais.
var _hitmarker_kill := false
var _hitmarker_scale := 1.0
var _hurt_flash := 0.0
var _hurt_dir := 0.0
var _enemy_hit := 0.0
var _known_projectiles: Dictionary = {}
var _reduced_motion := false
var _clock := 0.0
var _last_seen_enemy_pos := 2.0

# ╔═ §8.151 (VAGUE 2ter) — LE HUD DE COMBAT : IL NE MONTRE QUE DES MÉCANIQUES RÉELLES (§1.9) ═════╗
# ║ Trois ajouts, une seule règle. Chacun n'affiche QUE ce que la simulation possède vraiment :     ║
# ║  1. RÉTICULE PAR ARME — son écartement EST le cône `dispersion_deg` de l'arme courante, LU au   ║
# ║     registre `trench_init.rules.weapons` et projeté par la MÊME fonction que la visée           ║
# ║     (`_world.project_aim`, cf. `_dispersion_pixels`). ⛔ AUCUN BLOOM PROGRESSIF : la sim n'a    ║
# ║     pas de dispersion qui grossit en tirant ; en dessiner une serait exactement le mensonge     ║
# ║     que §8.141.6 a coûté une partie. Le seul mouvement admis est un PULSE cosmétique bref au    ║
# ║     tir, POSÉ (jamais cumulé) et éteint bien avant que la cadence n'autorise le coup suivant.   ║
# ║  2. HITMARKER — enrichi, mais toujours sur le SEUL événement `hit` serveur (croix de KILL       ║
# ║     rouge quand `hp` tombe à 0, échelle discrète selon `damage`).                                ║
# ║  3. DÉGÂTS FLOTTANTS — un chiffre par touche CONFIRMÉE, jamais un chiffre prédit.                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Le PULSE du réticule (§4bis.1). Ressort CRITIQUE (zeta 1) posé à 1.0 au tir : (1+wt)e⁻ʷᵗ à 8 Hz
# ≈ 4 % restants à 100 ms — donc éteint TRÈS avant la cadence la plus rapide du registre (le CHACAL,
# 16 ticks = 0,80 s). Posé en VALEUR (`set_value`) comme le punch de FOV : une rafale de 3 coups
# repart du même plafond au lieu de s'empiler — un réticule qui s'ouvrirait à chaque balle SERAIT
# le bloom interdit.
const RETICLE_PULSE_FREQ := 8.0
const RETICLE_PULSE_PX := 5.0
var _reticle_pulse := Springs.TrenchSpring.new(RETICLE_PULSE_FREQ, 1.0, 0.0)

# ╔═ §8.151 (2ter, §4bis.3) — LES DÉGÂTS FLOTTANTS : POOL PRÉALLOUÉ, TEMPS DE SCÈNE ══════════════╗
# ║ ⚠️ AUCUN `Label.new()` HORS DE LA CONSTRUCTION. Le pool est bâti une fois dans `_build_hud`     ║
# ║ (`DAMAGE_POOL` étiquettes, taille POSÉE — 8ᵉ récidive du `size = (0,0)` d'un Control créé par   ║
# ║ code, cf. §8.140.3), et un chiffre qui naît RECYCLE le plus ancien plutôt que d'allouer. Une    ║
# ║ rafale de FRELON peut placer 3 balles en 200 ms, deux rafales se recouvrent : 12 places est le  ║
# ║ premier multiple confortable au-dessus du minimum de 8 du cahier.                               ║
# ║ ⚠️ PILOTÉ PAR LE TEMPS DE SCÈNE (`_clock`, avancé par `_process(delta)`) et jamais par           ║
# ║ `Time.get_ticks_msec()` : l'horloge murale est la cause n° 1 des baselines instables du         ║
# ║ §8.151.0, et une capture à frame fixe doit rejouer le même pixel.                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const DAMAGE_POOL := 12
const DAMAGE_RISE_S := 0.6          # montée + fondu (cahier : « ~0,6 s »)
const DAMAGE_RISE_PX := 46.0        # de combien le chiffre monte sur toute sa vie
const DAMAGE_BOX := Vector2(96, 26) # taille POSÉE de chaque étiquette du pool
const DAMAGE_JITTER_PX := 26.0      # décalage latéral d'un chiffre à l'autre (lisibilité §4bis.3)
const DAMAGE_SEED := 81513          # graine du décalage — hash_noise déterministe, aucun RNG global
var _damage_pool: Array = []        # les Labels préalloués — sa TAILLE ne change JAMAIS après _ready
# ⚠️ LA LISTE DES LIBRES EST OBLIGATOIRE, ET C'EST UN CORRECTIF. La première écriture prenait
# `_damage_pool[_damage_live.size()]` : dès qu'un chiffre du MILIEU expirait (le plus ancien n'est
# pas toujours celui qui part en premier quand une rafale recouvre une rafale), l'index retombait
# sur une étiquette ENCORE EN VOL — deux entrées vivantes partageaient un Label, et l'expiration de
# la première éteignait le chiffre de la seconde en plein écran. Un pool sans liste de libres n'est
# pas un pool, c'est un compteur.
var _damage_free: Array = []        # les Labels DISPONIBLES (invariant : libres ∪ en vol = pool)
var _damage_live: Array = []        # {node, born, from, jitter} — les chiffres en vol
var _damage_spawned := 0            # compteur de naissances : la clé du décalage déterministe

# ╔═ §8.151 (2ter, §4bis.5 / décision §1.8) — LE TIR MAINTENU, ACTIF PAR DÉFAUT ══════════════════╗
# ║ Maintenir le clic enchaîne les tirs à la cadence AUTORISÉE PAR LE SERVEUR. Mécaniquement        ║
# ║ NEUTRE : la sim impose déjà `cooldown_ticks`, un cliqueur rapide obtenait exactement ce rythme  ║
# ║ (c'est même le scénario de `probe_trench_falseshot`). Ce qui change est le CONFORT, pas la      ║
# ║ cadence — et surtout PAS la visée : le tir maintenu n'écrit dans aucune variable de visée, il   ║
# ║ ne décide QUE de l'instant d'émission (`probe_trench_aim`/`probe_trench_feel_aim` restent       ║
# ║ vertes, c'est la contre-épreuve nommée du cahier).                                              ║
# ║ ⚠️ ON N'ÉMET JAMAIS UN TIR VOUÉ AU REJET : chaque frame tenue repasse par la prédiction des SIX ║
# ║ refus (`_fire_refusal`, miroir de `trench_sim.step`). Sans elle, une gâchette tenue enverrait   ║
# ║ ~60 messages/s dans un budget anti-flood de 9 — et le premier tir LÉGAL serait celui qu'on      ║
# ║ jetterait. Le refus SONORE, lui, reste réservé au geste VOLONTAIRE (le clic, front montant) :   ║
# ║ un maintien qui claquerait `trench_refused` 7 fois par seconde serait un hachoir.                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
var _auto_fire: bool = TuningScript.defaults()["auto_fire"]
var _fire_hold_pad_prev := false    # front montant de la gâchette manette (le clic a `_input`)
var _hold_empty_latch := false      # « chargeur vide » n'envoie qu'UN déclencheur de rechargement

# ╔═ §8.151 LOT B — LE FEEL DE L'HÔTE : roulis, punch de FOV, secousse d'image entière ═══════════╗
# ║ RE-FONDATION de l'existant, pas superposition. Ce qui disparaît, et pourquoi :                 ║
# ║  • `_recoil` (0→1, décru linéairement à 6/s) : le kick vit désormais dans les ressorts du      ║
# ║    viewmodel (`notify_fire`), qui montent d'un coup et se POSENT (deux étages §4.1).           ║
# ║  • le KICK DE RÉTICULE (`aim_screen.y -= _recoil * 10`) : SUPPRIMÉ SANS REMPLAÇANT DIRECT.     ║
# ║    Il décalait la croix de 10 px SANS bouger le monde : pendant chaque recul, le réticule      ║
# ║    montrait un point que la balle ne visait pas — un mensonge de 10 px en contradiction        ║
# ║    frontale avec §8.141.6. La secousse, elle, translate monde + réticule ENSEMBLE.             ║
# ║ Ce qui arrive, et dans quelles limites (le catalogue AUTORISÉ du cahier §4.2) :                ║
# ║  • ROULIS au tir : rotation autour de l'axe de visée SEULEMENT, plafonnée ±0,3° — le centre    ║
# ║    de l'image est invariant. JAMAIS d'offset de lacet/site caméra (§8.141.6).                  ║
# ║  • PUNCH DE FOV au tir (+1,5° ~100 ms, interrupteur F10) : le rayon central est invariant      ║
# ║    par FOV — le réticule central reste vrai, et l'écartement de dispersion suit le vrai FOV.   ║
# ║  • SECOUSSE : le monde garde son modèle « trauma » (impulsions/décroissance inchangées) mais   ║
# ║    publie un décalage ÉCRAN (`shake_screen_px`) appliqué ICI aux couches ET au réticule d'un   ║
# ║    seul geste — la relation visée/pixel est préservée à l'octet près.                          ║
# ║ RIEN de tout cela n'écrit dans `_aim_yaw`/`_aim_pitch`/`_fire_aim` : `probe_trench_feel_aim`   ║
# ║ le prouve à chaque passe, octet par octet.                                                     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Roulis ⚙ : même forme deux étages que le kick du viewmodel (§4.1), tau résiduel 0,2 s pour rendre
# le calme avant la cadence minimale du registre (0,8 s) — mesuré par la sonde.
const ROLL_KICK_DEG := 0.22
const ROLL_CAP_DEG := 0.3
const ROLL_FREQ := 9.5
const ROLL_ZETA := 0.52
const ROLL_RESIDUAL_TAU := 0.2
const ROLL_RESIDUAL_SHARE := 0.34
const ROLL_SIDE_SEED := 8153       # graine du côté du roulis — hash_noise, aucun RNG global
const FOV_PUNCH_DEG := 1.5         # « +1-2° pendant ~100 ms » (§4.2) — défaut modéré
const FOV_PUNCH_FREQ := 8.0        # ressort CRITIQUE : (1+wt)e⁻ʷᵗ ≈ 4 % restants à 100 ms
var _cam_roll := Springs.TrenchRecoilAxis.new(ROLL_FREQ, ROLL_ZETA,
	ROLL_RESIDUAL_TAU, ROLL_RESIDUAL_SHARE)
var _fov_punch := Springs.TrenchSpring.new(FOV_PUNCH_FREQ, 1.0, 0.0)
var _shot_count := 0
var _shake_px := Vector2.ZERO      # le décalage appliqué CETTE frame (couches + réticule ensemble)
var _feel_recoil: float = TuningScript.defaults()["feel_recoil"]
var _feel_flinch: float = TuningScript.defaults()["feel_flinch"]
var _feel_fov_punch: bool = TuningScript.defaults()["fov_punch"]
# Visée du DERNIER laser adverse annoncé (§5.3) : le serveur la joint à l'événement `laser`, sans
# quoi le rayon pointerait au hasard et le télégraphe mentirait sur qui est visé.
var _enemy_laser_yaw := 0.0
var _enemy_laser_pitch := 0.0
var _enemy_laser_pos := 2

# --- Nœuds ---------------------------------------------------------------------------------------
var _sky: TextureRect
var _world: Control
var _ambient: Control
var _grade: ColorRect
var _tuning: Control
var _viewmodel: Control
var _hud: Control
var _reticle: Control
var _my_hp_fill: ColorRect
var _my_hp_label: Label
var _their_hp_fill: ColorRect
var _their_name: Label
var _timer_label: Label
var _score_label: Label
var _round_label: Label
var _ammo_label: Label
var _reload_label: Label
var _weapon_label: Label
var _progress_label: Label
var _slot_grenade: Label
var _slot_bandage: Label
var _banner: Label
var _waiting_label: Label
var _conn_banner: Label
var _geometry_banner: Label   # désynchronisation client/serveur (§8.141.6)
var _tune_hint: Label
var _help_panel: PanelContainer   # guide des commandes (F1)
var _help_hint: Label
var _help_shown_once := false
var _diag: Label            # bandeau de diagnostic F3 — les DEUX modes, lecture seule
var _hurt_overlay: ColorRect
var _low_hp_vignette: ColorRect
var _choice_panel: PanelContainer
var _choice_title: Label
var _choice_countdown: Label
var _choice_buttons: Array = []
var _abandon_overlay: Control
var _result_overlay: Control
var _banner_tween: Tween
# LA DÉCISION DE CAPTURE, gardée à côté de l'appel plateforme — cf. le pavé de `_capture_mouse`.
var _mouse_captured := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_reduced_motion = bool(SettingsManager.get_comfort("reduced_motion"))

	_build_layers()
	_build_hud()

	NetworkManager.trench_init_received.connect(_on_init)
	NetworkManager.trench_state_received.connect(_on_state)
	NetworkManager.trench_result_received.connect(_on_result)
	NetworkManager.server_connection_lost.connect(_on_connection_lost)
	NetworkManager.server_connected.connect(_on_reconnected)
	NetworkManager.game_error.connect(_on_game_error)

	if pending_room_id == "":
		_back_to_hub()
		return
	# ⚠️ LE SON NE CHANGEAIT PAS EN ENTRANT EN PARTIE — verdict de partie réelle. Ce n'était pas un
	# réglage à corriger : le duel n'appelait tout simplement JAMAIS `AudioManager`, et jouait donc
	# sur la nappe des menus, du début à la fin. La bascule existe pourtant depuis le §8.66 et les
	# autres modes s'en servent ; celui-ci l'avait oubliée.
	AudioManager.start_battle_ambient()
	_capture_mouse(true)
	NetworkManager.connect_to_server(pending_room_id)


func _exit_tree() -> void:
	pending_room_id = ""
	_capture_mouse(false)
	# On rend la radio du QG en sortant : sans ça, la musique de combat suivrait le joueur dans les
	# menus (symétrique exact de `start_battle_ambient`).
	AudioManager.start_menu_ambient()


# La souris est CAPTURÉE pendant le duel (c'est une visée libre) et RELÂCHÉE dès qu'un panneau
# demande un clic — confirmation d'abandon, choix d'arme, écran de fin.
# ⚠️ `_mouse_captured` N'EST PAS UN DOUBLON DÉCORATIF de `Input.mouse_mode` : sous `--headless` le
# pilote est MUET et ne retient RIEN (mesuré — on lui demande `CAPTURED`, il rend `VISIBLE`). Une
# sonde qui ne lirait que la plateforme serait donc VERTE quoi qu'on fasse. On garde ici la
# DÉCISION du client ; la sonde la lit sous pilote muet, et la recolle à `Input.mouse_mode` sous
# pilote réel (section 2quater) — l'état ET son image, jamais l'un sans l'autre.
func _capture_mouse(capture: bool) -> void:
	_mouse_captured = capture
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE


# ╔═ §8.151 (2quinquies, CORRECTIF) — REFERMER UN PANNEAU NE REND PAS LA SOURIS AU DUEL ══════════╗
# ║ 🩸 LE CURSEUR DISPARAISSAIT SUR UNE INTERFACE QUI ATTEND UN CLIC. `_capture_mouse` est un      ║
# ║ poseur NU, et ses cinq appelants raisonnaient chacun sur LEUR seul panneau                     ║
# ║ (`not _tuning.visible`, `not _abandon_overlay.visible`, `not _match_over`…). Chemin le plus    ║
# ║ court, avec le réflexe le plus naturel qui soit, en ENTRAÎNEMENT : F10 ouvre les réglages      ║
# ║ (souris relâchée) → ÉCHAP (le réflexe pour fermer un panneau) ouvre en fait la boîte           ║
# ║ « abandonner ? » → ÉCHAP à nouveau la referme et RECAPTURAIT la souris alors que le panneau    ║
# ║ F10 était TOUJOURS à l'écran : plus de curseur, plus un seul réglage cliquable. Même classe en ║
# ║ duel CLASSÉ, où le panneau de CHOIX D'ARME s'ouvre TOUT SEUL : ÉCHAP + ÉCHAP par-dessus lui et ║
# ║ ses deux boutons devenaient inatteignables à la souris.                                        ║
# ║ ⚠️ LA QUESTION « QUI TIENT L'ÉCRAN ? » A UNE SEULE RÉPONSE, et c'est `_ui_blocks_actions()` —   ║
# ║ exactement la liste des panneaux qui relâchent le curseur. Nier UN drapeau, c'était répondre à ║
# ║ la question « mon panneau à moi est-il fermé ? », qui n'est pas la même.                        ║
# ║ ⚠️ UN SEUL SITE DE DÉCISION : tout ce qui OUVRE ou FERME un panneau appelle cette fonction —    ║
# ║ elle rend la souris au duel si l'écran est libre, la laisse au joueur sinon. Les seuls          ║
# ║ `_capture_mouse` restants sont les inconditionnels (entrée en duel, sortie, écran de fin).      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _restore_mouse() -> void:
	_capture_mouse(not _ui_blocks_actions())


# =================================================================================================
# COUCHES 1 & 2
# =================================================================================================
func _build_layers() -> void:
	# COUCHE 0 — LE CIEL DE DERNIER RECOURS. Le SubViewport 3D est TRANSPARENT : partout où le
	# monde 3D ne peint rien, c'est la couleur d'effacement de la fenêtre qui sort. Depuis le
	# pivot, l'arc de ciel peint couvre ±100° sur 56° de haut et ne peut pas laisser de trou — ce
	# dégradé n'est donc plus qu'un filet de sécurité, coûtant un quad. Il reste TOUJOURS allumé :
	# la seule façon de le voir est un défaut, et un défaut doit se voir en gris, pas en néant.
	var sky := TextureRect.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.18, 0.19, 0.22))     # haut : ciel de cendres
	gradient.set_color(1, Color(0.46, 0.38, 0.30))     # bas  : brume basse sur les terres brûlées
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.0, 0.0)
	gradient_texture.fill_to = Vector2(0.0, 1.0)
	sky.texture = gradient_texture
	add_child(sky)
	_sky = sky

	# ╔═ LA COUCHE « DÉCOR PRÉ-RENDU » A ÉTÉ RETIRÉE ════════════════════════════════════════════╗
	# ║ C'était un `TextureRect` plein écran portant l'un des 10 décors peints, et depuis §8.139.1 ║
	# ║ un shader qui tentait de le faire suivre la caméra. Deux défauts s'y logeaient, tous deux  ║
	# ║ mesurés dans le code : la parallaxe de position comptée DEUX FOIS (32 px de découpe + 146  ║
	# ║ px de shader), et un décalage LINÉAIRE opposé à une projection en TANGENTE (~11 % à 32°).  ║
	# ║ Aucun réglage ne les réconciliait : une image plate ne peut pas suivre une caméra libre.   ║
	# ║ Le monde 3D texturé la remplace intégralement — il répond juste parce qu'il EST le monde.  ║
	# ║ Les 10 PNG restent sur disque : ils ne sont plus chargés, ils sont une réserve (§6.4).     ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝

	# COUCHE 1 — le monde 3D transparent. Il porte désormais TOUT ce qui se voit : le sol jusqu'à
	# l'horizon, les deux parapets, les barbelés, et le ciel peint sur son arc à 300 m.
	_world = WorldScene.instantiate()
	add_child(_world)
	_world.set_reduced_motion(_reduced_motion)
	_world.set_pose(_pred_pos, _pred_stance, true)

	# COUCHE 2 bis — L'HABILLAGE PROCÉDURAL (§8.139) : brume de profondeur, cendres, braises.
	# Il s'intercale ICI, entre le monde et le viewmodel, et les deux bornes sont motivées dans
	# `trench_ambient.gd` (la brume doit voiler le soldat à 35 m, jamais mon arme à 0,60 m).
	_ambient = AmbientScript.new()
	add_child(_ambient)
	_ambient.set_reduced_motion(_reduced_motion)

	# COUCHE 3 — LE VIEWMODEL PEINT (§8.138). Il vit dans la couche ÉCRAN, AU-DESSUS du SubViewport
	# et SOUS le HUD : c'est l'ORDRE D'AJOUT qui décide, et `_build_hud()` est appelé après nous.
	# Sans fichiers pour l'arme courante, ce nœud s'efface et le viewmodel en primitives du monde 3D
	# reprend le service — d'où l'aiguillage unique `_apply_weapon()`.
	_viewmodel = ViewmodelScript.new()
	add_child(_viewmodel)
	# ⛔ LA DURÉE DE RECHARGEMENT EST UNE RÈGLE : on ne la DONNE pas à l'hôte, on lui donne
	# de quoi la DEMANDER. La différence est tout le lot : `_apply_weapon` tourne dans
	# `_ready()`, **avant** que le registre serveur n'existe. Une valeur passée ici serait
	# figée à zéro pour toujours ; un fournisseur, lui, redonne la bonne dès qu'elle arrive.
	if _viewmodel.has_method("_reload_seconds"):
		_viewmodel.reload_source = Callable(self, "_reload_seconds")
	_viewmodel.set_reduced_motion(_reduced_motion)
	_apply_weapon(STARTING_WEAPON)

	# COUCHE 3 bis — L'ÉTALONNAGE UNIFIANT (§8.139). Il LIT L'ÉCRAN : il doit donc venir après tout
	# ce qu'il teinte (décor, monde, ambiance, viewmodel) et avant le HUD — que `_build_hud()`
	# ajoutera juste après. Le HUD reste HORS étalonnage : son cyan est une convention de lecture,
	# pas une image, et l'aplatir reviendrait à dégrader la lisibilité pour un gain esthétique.
	_grade = AmbientScript.make_grade_layer()
	add_child(_grade)

	# COUCHE 3 ter — LE PANNEAU DE RÉGLAGE (F10). Au-dessus de l'étalonnage : c'est un outil, pas
	# une image du jeu — le teinter reviendrait à rendre moins lisibles les chiffres qu'on règle.
	# Il reste caché jusqu'à ce que `_on_init` sache qu'on est bien en ENTRAÎNEMENT.
	_tuning = TuningScript.new()
	add_child(_tuning)
	_tuning.changed.connect(_apply_tuning)
	_apply_tuning(_tuning.values())


# L'AIGUILLAGE peint / primitives, en UN seul endroit : les deux viewmodels ne doivent jamais être
# allumés ensemble, ni éteints ensemble.
func _apply_weapon(weapon_id: String) -> void:
	_apply_weapon_check(weapon_id)


# Même aiguillage, mais il REND ce qu'il a décidé : `true` = viewmodel peint, `false` = repli en
# primitives. Le jeu n'a pas besoin de cette réponse ; le harnais de recette, si — sans elle il
# capturerait un viewmodel de repli en croyant recetter un asset peint (§8.139).
func _apply_weapon_check(weapon_id: String) -> bool:
	if weapon_id == "" or _world == null or _viewmodel == null:
		return false
	_world.set_weapon(weapon_id)
	var painted: bool = _viewmodel.set_weapon(weapon_id)
	_world.set_viewmodel_visible(not painted)
	return painted


# =================================================================================================
# LA POSE A CHANGÉ — CE QUI RESTE À FAIRE CÔTÉ VUE
# =================================================================================================
# ╔═ IL N'Y A PLUS RIEN À RECALER, ET C'EST TOUT L'INTÉRÊT DU PIVOT ══════════════════════════════╗
# ║ Cette fonction chargeait un décor peint, poussait sa texture dans un shader, éteignait le      ║
# ║ greybox et rallumait un ciel de repli — quatre états à tenir synchronisés à chaque pas de      ║
# ║ côté. C'est là que le défaut « il n'y a pas de tranchée » s'est logé.                          ║
# ║ La caméra TRANSLATE désormais physiquement entre les positions (`set_pose`) dans un monde qui  ║
# ║ existe : la parallaxe d'un pas de côté est celle du monde réel, gratuite et juste. Il ne reste ║
# ║ donc à prévenir que l'habillage, qui suit la POSTURE — accroupi, il n'y a plus de lointain.    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _refresh_pose_view() -> void:
	if _ambient != null:
		_ambient.set_stance(_pred_stance)


# =================================================================================================
# RÉSEAU
# =================================================================================================
func _on_init(msg: Dictionary) -> void:
	_rules = msg.get("rules", {})
	_my_slot = int(msg.get("your_slot", 1))
	_training = bool(msg.get("training", false))
	_opponent = msg.get("opponent", {})
	_tick_rate = float(_rules.get("tick_rate_hz", 10))
	_positions = int(_rules.get("positions", 5))
	_pred_pos = _positions / 2
	_world.set_pose(_pred_pos, _pred_stance, true)
	_world.set_enemy_accent(_enemy_accent())
	# ⚠️ L'INVARIANT D'HONNÊTETÉ (§C.1) PASSE PAR ICI, ET PAR NULLE PART AILLEURS. Le rayon
	# dessiné — décalque de visée, marqueurs de vol, anneau de choc — est CELUI DU REGISTRE
	# SERVEUR, qui décide des dégâts. Un rayon recopié côté client aurait sa propre vie et
	# finirait par mentir : c'est exactement ce que faisait l'ancien disque de 1,6 m pour une zone
	# qui en couvrait quatre.
	var grenade_rules: Dictionary = _rules.get("grenade", {})
	_world.set_grenade_radius(float(grenade_rules.get("radius_m", 2.5)))
	_check_geometry_match()
	_refresh_pose_view()

	var opp_name := str(_opponent.get("name", ""))
	if bool(_opponent.get("is_bot", false)) or opp_name == "":
		opp_name = tr("TRENCH_BOT_NAME")
	_their_name.text = opp_name + ("  ·  " + tr("TRENCH_VS_BOT_NOTE") if _training else "")
	if _tune_hint != null:
		_tune_hint.visible = _training
	var state = msg.get("state")
	if typeof(state) == TYPE_DICTIONARY:
		_push_state(state)
		# L'arme vient de l'ÉTAT, pas d'un événement : à la reconnexion en pleine manche, l'escalade
		# a déjà eu lieu et son événement est passé depuis longtemps.
		_apply_weapon(str(_player_of(state, _my_slot).get("weapon", STARTING_WEAPON)))
		_waiting_label.visible = false
	else:
		_waiting_label.text = tr("TRENCH_WAITING_OPPONENT")
		_waiting_label.visible = true


# ╔═ ⚠️⚠️ LE CLIENT ET LE SERVEUR PARLENT-ILS DE LA MÊME ARÈNE ? (§8.141.6) ══════════════════════╗
# ║ LE DÉFAUT QUE CE CONTRÔLE AURAIT ÉVITÉ, ET QUI A COÛTÉ UNE PARTIE ENTIÈRE :                    ║
# ║ verdict de partie réelle — « je vois par A+B que j'ai touché le soldat, mais pour le jeu je ne  ║
# ║ l'ai JAMAIS touché · à chaque clic un coup part, aucun ne fait de dégâts · le bot ne rate       ║
# ║ AUCUN coup ». Trois symptômes, UNE cause : le serveur résolvait les touches sur une table       ║
# ║ angulaire d'une AUTRE arène que celle que le client dessine.                                    ║
# ║                                                                                                 ║
# ║ Mesuré : quand le joueur centre son réticule sur le soldat il envoie ~(yaw 0,00 · pitch −1,16). ║
# ║   fenêtre centrale, table v3 (9 m, celle du client) : yaw [−1,72, 1,72] · pitch [−2,89, 0,57]   ║
# ║   fenêtre centrale, table v1 (35 m, celle de la PROD) : yaw [−0,48, 0,48] · pitch [−0,74, 0,16] ║
# ║ Le pitch seul suffit : **−1,16 est hors de [−0,74 ; 0,16], donc AUCUN tir ne peut toucher**,    ║
# ║ quelle que soit la qualité de la visée. Le BOT, lui, vise le centre des fenêtres du SERVEUR :   ║
# ║ il ne rate jamais. Le duel devient « je tire dans le vide, il me touche à tous les coups ».      ║
# ║                                                                                                 ║
# ║ ⚠️ TOUT LE CHANTIER RÉPÉTAIT « client et serveur doivent partir ENSEMBLE », et un test compare  ║
# ║ déjà les DEUX COPIES DU FICHIER sur disque. Mais RIEN ne comparait le serveur qui TOURNE au     ║
# ║ client qui TOURNE — et c'est le seul des deux qui compte au moment de jouer. Le contrôle        ║
# ║ manquait exactement là où le mode d'emploi disait qu'il fallait faire attention.                ║
# ║ Le serveur envoie déjà sa version dans `trench_init.rules.geometry` : il n'y avait qu'à la lire.║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _check_geometry_match() -> void:
	var geometry: Dictionary = _rules.get("geometry", {})
	if geometry.is_empty():
		return
	var server_version := int(geometry.get("version", 0))
	var server_depth := float(geometry.get("no_mans_land", 0.0))
	if server_version == Geo.TABLE_VERSION and absf(server_depth - Geo.NO_MANS_LAND) < 0.01:
		return
	# ⚠️ ON NE CORRIGE PAS, ON DÉNONCE. Le client ne PEUT pas se réaligner : sa géométrie est bâtie
	# dans le blockout 3D, dans les poses de caméra et dans la table locale. Rendre une arène de
	# 35 m parce que le serveur en parle demanderait de tout reconstruire à chaud — et masquerait
	# le vrai problème, qui est qu'un déploiement n'a pas eu lieu. On le dit, en grand, en rouge.
	push_error("[TRANCHÉE] DÉSYNCHRONISATION GÉOMÉTRIQUE : serveur table v%d (%.1f m) / client v%d "
		% [server_version, server_depth, Geo.TABLE_VERSION]
		+ "(%.1f m). AUCUN TIR NE PEUT TOUCHER. Redéploie le backend." % Geo.NO_MANS_LAND)
	_geometry_banner.text = tr("TRENCH_GEOMETRY_MISMATCH") % [server_version, Geo.TABLE_VERSION]
	_geometry_banner.visible = true


# Accent de faction du soldat d'en face (§1.8 : « l'accent de couleur d'une faction du jeu »).
# ⚙ Le duel ne transporte pas encore la faction de l'adversaire : on en dérive une STABLE depuis
# son pseudo, pour que le même adversaire porte toujours la même couleur. Le jour où `trench_init`
# gagnera un champ `faction`, c'est cette seule fonction qu'il faudra rouvrir.
func _enemy_accent() -> Color:
	var accents: Array = []
	var dir := DirAccess.open("res://resources/factions/")
	if dir != null:
		for file in dir.get_files():
			var clean := file.replace(".remap", "")
			if not clean.ends_with(".tres"):
				continue
			var res = load("res://resources/factions/" + clean)
			if res != null and res.get("accent_color") != null:
				accents.append(res.get("accent_color"))
	if accents.is_empty():
		return COL_DANGER
	var key := str(_opponent.get("name", "")) + str(3 - _my_slot)
	return accents[absi(key.hash()) % accents.size()]


func _on_state(msg: Dictionary) -> void:
	_waiting_label.visible = false
	_push_state(msg)
	for event in msg.get("events", []):
		if typeof(event) == TYPE_DICTIONARY:
			_on_duel_event(event)


func _push_state(state: Dictionary) -> void:
	_buffer.append({"at": _now(), "data": state})
	while _buffer.size() > 16:
		_buffer.pop_front()
	# Réconciliation SILENCIEUSE (§2.4) : si le serveur me voit ailleurs que ma prédiction deux
	# états de suite, c'est lui qui a raison — on se cale sans un mot.
	var me := _player_of(state, _my_slot)
	if not me.is_empty() and me.get("pos") != null:
		if int(me.get("pos")) != _pred_pos:
			_mismatch_streak += 1
			if _mismatch_streak >= 2:
				_pred_pos = int(me.get("pos"))
				_refresh_pose_view()
				_mismatch_streak = 0
		else:
			_mismatch_streak = 0
	# Mémoire des projectiles (pour rien perdre d'un impact entre deux états).
	var seen := {}
	for proj in state.get("projectiles", []):
		seen[int(proj.get("id", 0))] = true
		_known_projectiles[int(proj.get("id", 0))] = proj
	for pid in _known_projectiles.keys().duplicate():
		if not seen.has(pid):
			_known_projectiles.erase(pid)


func _on_duel_event(event: Dictionary) -> void:
	var kind := str(event.get("type", ""))
	match kind:
		"round_start":
			# ⚠️ LE GUIDE SE REFERME SEUL AU COUP D'ENVOI. Un panneau qu'il faut penser à fermer
			# pour jouer serait un obstacle, pas une aide — et le joueur qui le lit encore n'a pas
			# à choisir entre finir sa lecture et rater le début de la manche.
			if _help_panel != null:
				_help_panel.visible = false
			_show_banner(tr("TRENCH_ROUND") % int(event.get("round_no", 1)), COL_ACCENT)
		"fire":
			if int(event.get("slot", 0)) == _my_slot:
				# ⚠️ Le retour d'arme a DÉJÀ été joué au clic (`_local_fire_feedback`) : attendre
				# l'aller-retour serveur laissait ~250 ms de silence après la pression, et le tir
				# paraissait « en retard » même quand il ne l'était pas. On ne le rejoue donc ici
				# que si le tir ne vient PAS de ma main — reconnexion en pleine manche, ou tir que
				# le client n'avait pas anticipé (chargeur que je croyais vide, par exemple).
				# ⚠️ RÉCONCILIATION DE LA CADENCE. Le serveur vient de confirmer qu'un tir est parti :
				# c'est LUI qui a raison sur le moment où le suivant sera permis. Sans ce recalage,
				# une dérive d'horloge finirait par rendre la prédiction trop permissive — et le
				# faux coup reviendrait par la porte de derrière.
				# §8.151 (2bis, correctif) : ce qui RESTE de la cadence, pas la cadence ENTIÈRE —
				# le serveur a posé sa porte au CLIC, qui précède cet événement de
				# `laser_lead_ticks` pour une arme télégraphiée (cf. `_cadence_remaining_seconds`).
				_pred_fire_ready = _clock + _cadence_remaining_seconds(str(event.get("weapon", "")))
				_arm_bolt()          # §8.151 : le serveur confirme un tir → le réarmement s'entendra
				if _fire_fx_mute <= 0.0:
					# Depuis §8.138 le recul s'applique au VIEWMODEL 2D peint — et depuis §8.151
					# il vit dans SES ressorts ; ici on n'arme plus que le feel de caméra.
					# §8.151 (2bis) : détonation dans la VOIX de l'arme (repli générique), et les
					# coups 2..N de la rafale non anticipée sont planifiés eux aussi — cadencés par
					# les `launch_tick` serveur du même message (mode mine_event : kick + son, pas
					# de traçante locale — celles de l'état suffisent à ce tir-là, comme avant).
					_fire_feel_kick()
					_viewmodel.notify_fire()
					AudioManager.play_sfx(_shot_sfx_key(str(event.get("weapon", ""))))
					_schedule_burst_followups("mine_event", event)
			else:
				# LE DÉPART DE FEU ADVERSE — le danger s'annonce à l'oreille avant de se voir.
				# §8.151 : le SIFFLEMENT de cette balle (si elle me manque) ne part PAS d'ici — au
				# départ, personne ne sait encore si elle touche. Il part de l'événement `impact`
				# (damage == 0), que le serveur émet à la fin du même vol que la traçante.
				# §8.151 (2bis) : la détonation prend la VOIX de l'arme de l'événement (`frelon`
				# ne sonne plus comme `condor`), et une rafale adverse fait N départs de feu — les
				# crans 2..N sont planifiés sur les `launch_tick` PAR PROJECTILE du flux d'états
				# (le même message porte déjà toute la rafale) : le serveur fait foi, pas une
				# minuterie locale.
				AudioManager.play_sfx(_shot_sfx_key(str(event.get("weapon", ""))))
				# … ET À L'ŒIL (§8.141). Le bot voit MON tir — ma traçante naît à ma position, et
				# `from_pos` la trahit. Moi je n'avais que le SON du sien, alors que sa balle met un
				# temps de vol à arriver : je savais qu'on tirait, jamais d'où. Une lueur de deux
				# frames à son canon rétablit la parité d'information, et elle ne révèle rien qui ne
				# le soit déjà — tirer, c'est se montrer (§1.6, la même règle que le `from_pos` des
				# projectiles, publics eux aussi). §8.151 (2bis) : re-déclenchée par cran → la lueur
				# PULSE au rythme réel de la rafale au canon d'en face.
				_world.notify_enemy_fire(int(round(_last_seen_enemy_pos)))
				_schedule_burst_followups("enemy", event)
		"impact":
			# ╔═ L'EXPLOSION NAÎT DE L'ÉVÉNEMENT SERVEUR, JAMAIS D'UNE HORLOGE LOCALE ═════════╗
			# ║ Le client connaît le tick d'impact dès le lancer : il POURRAIT jouer l'explosion ║
			# ║ « à l'heure ». Il ne le fait pas — ce serait rejouer la simulation, et 100 ms de  ║
			# ║ dérive feraient exploser la grenade avant que le serveur ne l'ait résolue. Le     ║
			# ║ joueur se verrait épargné, puis mourrait. C'est la règle du hitmarker (§5.5),     ║
			# ║ appliquée à la seule autre chose qui annonce un dégât.                            ║
			# ╚═════════════════════════════════════════════════════════════════════════════════╝
			if str(event.get("kind", "")) == "grenade":
				# `on_my_side` : la grenade tombe chez CELUI QUI N'EST PAS son lanceur.
				_world.play_explosion(float(event.get("target_x", 0.0)),
					int(event.get("slot", 0)) != _my_slot)
			elif int(event.get("slot", 0)) != _my_slot and int(event.get("damage", 0)) <= 0:
				# ╔═ §8.151 (LOT A) — LA BALLE ADVERSE QUI ME MANQUE SIFFLE EN PASSANT ═════════════╗
				# ║ « Minuscule, bon marché, énormément efficace pour rendre le feu ennemi           ║
				# ║ dangereux » (recette Claude-of-Duty). L'`impact` d'une BALLE est émis par le      ║
				# ║ serveur au tick d'ARRIVÉE (départ + flight_ticks) : le retard de vol est donc     ║
				# ║ DÉJÀ dans l'événement, calé sur la même horloge que la traçante adverse qui       ║
				# ║ achève sa course — aucune minuterie locale à inventer, même règle que             ║
				# ║ l'explosion ci-dessus. `damage == 0` = résolu MANQUÉ par la table angulaire :     ║
				# ║ un tir qui TOUCHE ne siffle pas (c'est `hit` qui parle — trench_hit, jamais les   ║
				# ║ deux). Pas de fichier `trench_whizz_*` ? La clé est inconnue et `play_sfx`        ║
				# ║ l'ignore en silence — le repli est le silence d'avant, pas un synthé inventé.     ║
				# ╚═════════════════════════════════════════════════════════════════════════════════╝
				AudioManager.play_sfx("trench_whizz")
		"grenade_thrown":
			# L'ADVERSAIRE arme et lance : frame `throw` du sprite peint (§8.138). Mon propre
			# lancer ne déclenche rien — je ne me vois pas lancer, je vois mes mains.
			AudioManager.play_sfx("trench_grenade")
			if int(event.get("slot", 0)) != _my_slot:
				_world.set_enemy_action("throw")
		"laser":
			# Le laser CONDOR adverse est rendu DÈS l'événement (la lisibilité de la menace est
			# une règle de design, §5.3) — avec la VRAIE direction du tireur.
			if int(event.get("slot", 0)) != _my_slot:
				_enemy_laser_yaw = float(event.get("aim_yaw", 0.0))
				_enemy_laser_pitch = float(event.get("aim_pitch", 0.0))
				_enemy_laser_pos = int(event.get("from_pos", 2))
		"hit":
			var victim := int(event.get("slot", 0))
			if victim != _my_slot:
				# Réaction de douleur du sprite peint (§8.138) — elle suit la VICTIME et non
				# l'auteur : une grenade peut toucher l'adversaire sans que ce soit mon tir.
				_world.set_enemy_action("hit")
			if int(event.get("by", 0)) == _my_slot:
				# HITMARKER — UNIQUEMENT sur confirmation serveur (§5.5). Jamais optimiste.
				# ⚠️ C'est LA seule chose qu'on refuse de jouer en avance : la détonation et le
				# recul disent « j'ai tiré », et le joueur le sait déjà — il vient de cliquer. Le
				# hitmarker, lui, dit « j'ai TOUCHÉ » : ça, seul le serveur le sait.
				# ⚠️ LE FILTRE EXISTANT EST PRÉSERVÉ TEL QUEL (`by == _my_slot`) : la sim ne blesse
				# jamais l'auteur d'un projectile (`victim = players[_other(owner_slot)]`, balles ET
				# grenades), donc cette seule condition suffit à exclure les dégâts SUBIS.
				# §8.151 (2ter, §4bis.2) — ce que l'ÉVÉNEMENT dit de plus, lu et jamais deviné :
				#   `damage` → l'échelle discrète du marqueur ET le chiffre flottant ;
				#   `hp`     → 0 = le coup était FATAL, croix ROUGE.
				var damage := int(event.get("damage", 0))
				var victim_hp := int(event.get("hp", 1))
				_hitmarker_kill = victim_hp <= 0
				_hitmarker_scale = _damage_scale(damage)
				_hitmarker = HITMARKER_TIME
				_enemy_hit = 0.35
				_spawn_damage_number(damage, _hitmarker_kill)
				AudioManager.play_sfx("trench_hitmarker")
			if victim == _my_slot:
				AudioManager.play_sfx("trench_hit")
				_hurt_flash = 0.5
				_hurt_dir = _last_seen_enemy_pos - float(_pred_pos)
				# §8.151 — le FLINCH : l'encaissement se sent dans les mains aussi (plongeon bref
				# du viewmodel) ; le pouls rouge directionnel, lui, est lu par `_refresh_hud`
				# depuis `_hurt_flash`/`_hurt_dir` (overlay dédié, shader `trench_flinch`).
				if _viewmodel != null:
					_viewmodel.notify_flinch()
		"escalation", "weapon_chosen":
			if int(event.get("slot", 0)) == _my_slot:
				_apply_weapon(str(event.get("weapon", STARTING_WEAPON)))
				if kind == "weapon_chosen":
					_choice_panel.visible = false
					_restore_mouse()
				_show_banner(tr("TRENCH_ESCALATION") % _weapon_name(str(event.get("weapon", ""))),
					COL_GOLD)
		"weapon_choice":
			if int(event.get("slot", 0)) == _my_slot:
				_open_choice(event)
		"round_end":
			var winner := int(event.get("winner_slot", 0))
			if winner == 0:
				_show_banner(tr("TRENCH_ROUND_TIE"), COL_MUTED)
			elif winner == _my_slot:
				_show_banner(tr("TRENCH_ROUND_WON"), COL_ACCENT)
			else:
				_show_banner(tr("TRENCH_ROUND_LOST"), COL_DANGER)
		"match_end":
			_match_over = true
			_aiming_grenade = false
			_world.show_grenade_aim(false)
			get_tree().create_timer(1.2).timeout.connect(func():
				if _result.is_empty():
					_show_result({}))


func _on_result(msg: Dictionary) -> void:
	_result = msg
	_show_result(msg)


func _on_connection_lost(_code: int) -> void:
	if _match_over:
		return
	_conn_banner.visible = true
	get_tree().create_timer(RECONNECT_DELAY).timeout.connect(func():
		if not _match_over and is_inside_tree():
			NetworkManager.retry_connection())


func _on_reconnected() -> void:
	_conn_banner.visible = false


func _on_game_error(message: String) -> void:
	if NetworkManager.last_error_reason == "trench_room_gone":
		_back_to_hub()
	elif message != "":
		_show_banner(message, COL_DANGER)


# =================================================================================================
# ENTRÉES
# =================================================================================================
# ╔═ §8.151 (2ter, CORRECTIF) — UNE SEULE LISTE DE PORTES POUR LES QUATRE CHEMINS D'ACTION ═══════╗
# ║ 🩸🩸 LE MÊME DÉFAUT, TROIS FOIS, PARCE QUE LA LISTE ÉTAIT RECOPIÉE. Le correctif précédent a    ║
# ║ refermé l'asymétrie entre le CLIC (`_input`) et le MAINTIEN (`_step_held_fire`) en RECOPIANT    ║
# ║ la liste des panneaux dans le second. Il restait un TROISIÈME chemin d'action issu du même      ║
# ║ `_process` : `_update_grenade_aim`, appelé juste AVANT `_step_held_fire`, qui ne testait NI     ║
# ║ `_tuning`, NI `_abandon_overlay`, NI `_choice_panel` — rien que la posture et le stock. Et      ║
# ║ comme il SONDE la plateforme (`Input.is_mouse_button_pressed(RIGHT)`, `Input.is_key_pressed(G)`)║
# ║ plutôt que d'attendre un événement, le relâchement du curseur (`_capture_mouse(false)`) ne le   ║
# ║ protégeait pas davantage.                                                                       ║
# ║ MESURÉ, et c'est le pire des trois : F10 ouvert en ENTRAÎNEMENT, un clic DROIT sur un curseur   ║
# ║ de réglage ARMAIT la visée (décalque au sol + viewmodel en pose de lancer) et le relâchement    ║
# ║ LANÇAIT une vraie grenade. Idem ÉCHAP (boîte « abandonner ? » à l'écran) et panneau de CHOIX    ║
# ║ D'ARME — qui, lui, s'ouvre TOUT SEUL à 10 touches, en plein combat, et relâche la souris. Le    ║
# ║ coût n'est pas un chargeur qui se recharge : `stock_start` = 2 et `regen_ticks` = 300 (15 s),   ║
# ║ c'est-à-dire LA MOITIÉ DU STOCK et une explosion à 40 dégâts, pour un geste jamais voulu.       ║
# ║                                                                                                 ║
# ║ ⚠️ LE CORRECTIF N'EST PAS « UNE TROISIÈME COPIE ». Recopier la liste une fois de plus, c'est    ║
# ║ programmer la quatrième divergence. Elle vit désormais ICI, à un seul endroit, et les trois     ║
# ║ chemins l'APPELLENT. La sonde, elle, continue de mesurer les trois SÉPARÉMENT — c'est           ║
# ║ l'asymétrie qui était le défaut, une garde qui n'en lirait qu'un laisserait les autres dériver. ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ╔═ §8.151 (2quater, CORRECTIF) — ET IL Y AVAIT UN QUATRIÈME CHEMIN : LE CLAVIER ════════════════╗
# ║ 🩸🩸 LE CORRECTIF PRÉCÉDENT S'EST ARRÊTÉ AUX GESTES OFFENSIFS. Les trois chemins refermés       ║
# ║ (clic, maintien, grenade) sont ceux qui TIRENT ou LANCENT. Restait tout ce que le SOLDAT fait   ║
# ║ d'autre, et qui partait exactement de la même façon, panneau ouvert :                           ║
# ║   • `_gather_move_dir()` — appelé par `_process`, il SONDE la plateforme                        ║
# ║     (`Input.is_key_pressed(KEY_LEFT/RIGHT/A/D/Q)`) : c'est le MOTIF EXACT qui rendait la        ║
# ║     grenade insensible au relâchement du curseur. Aucune porte de panneau.                      ║
# ║   • le bloc de touches d'`_input`, traité AU-DESSUS de la garde : `R` (rechargement),           ║
# ║     `S`/`CTRL`/`↑`/`↓` (posture) et `2` (pansement) armaient leurs drapeaux, et la charge       ║
# ║     coalescée les emportait sans conditionner quoi que ce soit au panneau.                      ║
# ║ CONSÉQUENCE, MESURÉE, PANNEAU F10 OUVERT : `pos 2 → 1` à la flèche DROITE, `posture = down` à   ║
# ║ la flèche BAS, `reload` et `item` VRAIMENT partis dans une charge passée à                      ║
# ║ `send_trench_input`. Les trois panneaux relâchent la souris : le joueur ne pouvait plus viser,  ║
# ║ mais son soldat marchait, s'accroupissait, rechargeait et se soignait. Pire, les HSlider du     ║
# ║ panneau F10 et les boutons des trois panneaux se pilotent AUX FLÈCHES (navigation de focus      ║
# ║ Godot) : régler un curseur faisait littéralement marcher le soldat, et un pansement — ressource ║
# ║ rare, 1 par manche — se dépensait sur un geste jamais voulu.                                    ║
# ║                                                                                                 ║
# ║ ⚠️ UNE PORTE PAR ACTION, JAMAIS UNE PORTE GLOBALE EN TÊTE D'`_input`. Un panneau qu'on ne peut  ║
# ║ plus FERMER serait un défaut pire que celui qu'on corrige : ÉCHAP, F10, F1 et F3 doivent        ║
# ║ continuer de répondre, et `1`/`2` doivent continuer de CHOISIR L'ARME tant que le panneau de    ║
# ║ choix est à l'écran — ce sont SES touches à lui. Le bloc de touches est donc coupé en          ║
# ║ deux : ce qui pilote les PANNEAUX répond toujours, ce qui agit sur le SOLDAT passe sous        ║
# ║ sa PROPRE porte (`_ui_blocks_survival()`, §8.151 2quinquies — pavé ci-dessous).                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ╔═ §8.151 (2quinquies, CORRECTIF) — ET LA PORTE PARTAGÉE GELAIT LE SOLDAT EN PLEIN COMBAT ══════╗
# ║ 🩸🩸 LE CORRECTIF PRÉCÉDENT A ÉTENDU CETTE LISTE — `_choice_panel` COMPRIS — À TOUT CE QUE FAIT ║
# ║ LE SOLDAT. Or le panneau de CHOIX D'ARME n'est pas un panneau comme F10 ou la boîte d'abandon : ║
# ║   • ce n'est pas le joueur qui l'ouvre, c'est le SERVEUR (`_credit_hit`, 10ᵉ coup au but) ;     ║
# ║   • il reste à l'écran 5,0 s pleines (`choice_window_ticks` = 100 à 20 Hz) ;                    ║
# ║   • et pendant ces 5 s LA SIMULATION CONTINUE : `trench_sim.step` applique `stance`, `move`,    ║
# ║     `reload` et `item` SANS aucune condition d'échéance, et l'adversaire joue normalement.      ║
# ║ Manette en main : Hakim place son 10ᵉ coup, le sélecteur s'affiche, et pendant qu'il lit        ║
# ║ « CHACAL ou CONDOR » son soldat ne marchait plus, ne s'accroupissait plus (la posture est LE    ║
# ║ bouton de panique du jeu), ne rechargeait plus et ne se soignait plus — sous le feu. Le client  ║
# ║ REFUSAIT des entrées que le serveur, lui, honore : une désynchronisation intention-joueur /     ║
# ║ simulation, exactement la famille de défaut qui a coûté la partie du §8.141.                    ║
# ║                                                                                                 ║
# ║ LE REMÈDE EST DANS LA DOCTRINE DU FICHIER (« une porte PAR ACTION ») — DEUX portes, une seule   ║
# ║ liste écrite, et leur différence tient en un panneau :                                          ║
# ║   • `_ui_blocks_survival()` — ce que le soldat fait pour SURVIVRE (pas, posture, rechargement,  ║
# ║     pansement). Ferme sous les panneaux que LE JOUEUR ouvre : leurs curseurs et leurs boutons   ║
# ║     se pilotent AUX FLÈCHES (navigation de focus Godot), régler un curseur ferait marcher le    ║
# ║     soldat. Le sélecteur, lui, n'y est PLUS.                                                    ║
# ║   • `_ui_blocks_actions()` — les gestes OFFENSIFS (clic, maintien, visée de grenade). La même   ║
# ║     liste PLUS le sélecteur : ces trois-là ont besoin de la SOURIS, et les trois panneaux la    ║
# ║     relâchent. C'est aussi, mot pour mot, « un panneau tient l'écran » — d'où son usage par     ║
# ║     `_restore_mouse()`.                                                                         ║
# ║ ⚠️ ET LE SÉLECTEUR NE VOLE PLUS LES FLÈCHES : ses deux boutons sont en `FOCUS_NONE`             ║
# ║ (`_build_choice_panel`), donc marcher pendant qu'il est à l'écran ne peut plus déplacer un      ║
# ║ focus ni choisir une arme par accident. `1`/`2` et la souris restent SES entrées à lui.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _ui_blocks_survival() -> bool:
	return _match_over or _abandon_overlay.visible or (_tuning != null and _tuning.visible)


func _ui_blocks_actions() -> bool:
	return _ui_blocks_survival() or _choice_panel.visible


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# ═══ 1) LES TOUCHES QUI PILOTENT LES PANNEAUX — elles répondent TOUJOURS ═══════════════════
		# Elles sont AU-DESSUS de la garde À DESSEIN : un panneau qu'on ouvre doit pouvoir se
		# refermer, et le panneau de CHOIX D'ARME garde SES touches (`1`/`2`) tant qu'il est à
		# l'écran. Rien ici ne touche au soldat — cf. le pavé « UNE PORTE PAR ACTION » ci-dessus.
		match event.keycode:
			KEY_ESCAPE:
				accept_event()
				# ⚠️ ÉCHAP ANNULE D'ABORD LA VISÉE DE GRENADE, et n'ouvre l'abandon qu'ensuite.
				# L'ordre n'est pas discutable : proposer « abandonner la partie ? » à quelqu'un
				# qui voulait juste ranger sa grenade serait une réponse absurde à son geste.
				if _aiming_grenade:
					_cancel_grenade()
					return
				if not _match_over:
					_abandon_overlay.visible = not _abandon_overlay.visible
					_restore_mouse()
				return
			KEY_G:
				# RE-TAPER G pendant la visée annule, comme ÉCHAP. Deux chemins pour un même geste :
				# celui qui vise à la souris (clic droit) lâchera ÉCHAP, celui qui vise au clavier
				# retapera sa touche. Aucun des deux ne doit coûter une grenade.
				if _aiming_grenade:
					accept_event()
					_cancel_grenade()
					return
			KEY_F1:
				# LE GUIDE DES COMMANDES — les DEUX modes, lecture seule, aucune pause, la souris
				# reste capturée. Il ne peut rien offrir à personne, donc rien ne justifierait de
				# l'interdire en duel classé (contrairement au panneau F10, qui relâche la souris).
				if _help_panel != null:
					accept_event()
					_help_panel.visible = not _help_panel.visible
					return
			KEY_F3:
				# LE BANDEAU DE DIAGNOSTIC — disponible DANS LES DEUX MODES (cf. `_log_input`).
				# Lecture seule : il ne relâche pas la souris et ne cloue pas le joueur sur place.
				# C'est l'outil qui manquait quand « les flèches ne fonctionnent pas ».
				if _diag != null:
					accept_event()
					_diag.visible = not _diag.visible
					return
			KEY_1:
				# LES TOUCHES DU PANNEAU DE CHOIX D'ARME. Elles n'agissent QUE quand il est ouvert —
				# et c'est précisément pour ça qu'elles vivent AU-DESSUS de la garde : le panneau de
				# choix EST l'un des trois panneaux bloquants, une porte globale rendrait le choix
				# d'arme injouable au clavier. Hors panneau, `1` ne fait rien (comme avant).
				if _choice_panel.visible:
					_queue_pick(0)
					return
			KEY_2:
				# `2` a DEUX rôles selon le contexte : arme n°2 quand le panneau est ouvert (ici),
				# PANSEMENT sinon (bloc 3, sous la garde). Le second est une dépense de ressource,
				# le premier une réponse à une question posée à l'écran.
				# ⚠️⚠️ LE `return` N'EST PAS DÉCORATIF, et la sonde l'a exigé : `_queue_pick()`
				# REFERME le panneau séance tenante, donc la garde ci-dessous ne bloque PLUS rien
				# quand elle est atteinte — sans ce retour, la même frappe choisissait l'arme ET
				# dépensait un pansement (MESURÉ : `arme = « condor »` + `file objet = « bandage »`).
				# Une touche = un geste : celle-ci a répondu à la question posée, elle s'arrête là.
				if _choice_panel.visible:
					_queue_pick(1)
					return
			KEY_F10:
				# LE PANNEAU DE RÉGLAGE — ENTRAÎNEMENT SEULEMENT. En duel, il relâcherait la souris
				# et clouerait le joueur sur place pendant qu'un adversaire, lui, continue de
				# jouer : ce serait offrir une manche par accident.
				if _training and _tuning != null and not _match_over:
					accept_event()
					_tuning.toggle()
					_restore_mouse()
					return
	# ═══ 2) LES TOUCHES QUI AGISSENT SUR LE SOLDAT — sous la porte des actions de SURVIE ═════
	# Elles ne posent que des drapeaux, mais ces drapeaux PARTENT : `_process` les recopie dans la
	# charge coalescée (`stance`, `reload`, `item`) et les vide juste après l'envoi. Un pansement est
	# une ressource rare ; le dépenser parce qu'un curseur de réglage avait le focus est exactement
	# l'incohérence de comportement que la garde de la grenade a déjà refermée.
	# ⚠️ §8.151 (2quinquies) — CE BLOC-CI NE FERME PLUS SOUS LE SÉLECTEUR D'ARME : celui-là s'ouvre TOUT
	# SEUL, en pleine manche, pour 5,0 s pendant lesquelles la sim continue de tourner et l'adversaire
	# de jouer. Se cacher, recharger et se soigner sont précisément ce qu'on fait pendant qu'on lit une
	# question sous le feu — cf. le pavé des DEUX portes, au-dessus de `_ui_blocks_survival()`.
	if event is InputEventKey and event.pressed and not event.echo:
		if _ui_blocks_survival():
			return
		match event.keycode:
			KEY_S, KEY_CTRL:
				# POSTURE = une BASCULE (§5.6), pas un maintien : le joueur doit pouvoir rester
				# à couvert sans garder un doigt en tension pendant 90 s.
				_stance_toggle = not _stance_toggle
			KEY_DOWN:
				# ⚠️ LA FLÈCHE BAS N'ÉTAIT LIÉE À RIEN — verdict de partie réelle : « la touche pour
				# se cacher ne fonctionne pas ». Ce n'était pas un bug, c'était une absence : le
				# §8.137 avait retenu S et CTRL, et il ne l'a écrit que dans un commentaire. Or un
				# joueur qui se déplace aux FLÈCHES cherche naturellement à s'accroupir avec ↓.
				# Bas = SE CACHER, Haut = SE RELEVER : deux touches EXPLICITES plutôt qu'une
				# bascule, parce qu'à couvert on ne se souvient plus dans quel état on est.
				_stance_toggle = true
			KEY_UP:
				_stance_toggle = false
			KEY_R:
				_reload_queued = true
			KEY_2:
				# ⚠️ LE PANSEMENT, et lui seul : le cas « panneau de choix ouvert » a déjà été traité
				# au-dessus, et le bloc 1 s'y ARRÊTE (`return`). Aucun des deux rôles de la
				# touche ne peut donc voler l'autre — la seule chose qui reste vraie du
				# sélecteur ici, depuis que la porte de SURVIE ne le lit plus.
				_item_queued = "bandage"
		return
	# ╔═ §8.151 (2ter, CORRECTIF) — LE CLIC ET LE MAINTIEN N'AVAIENT PAS LES MÊMES PORTES ═══════════╗
	# ║ 🩸 CE QUI N'ALLAIT PAS. Cette liste s'arrêtait à `_match_over / _abandon / _choice` : le       ║
	# ║ panneau F10 n'y figurait pas. Le chemin du MAINTIEN, lui, le fermait déjà (`_step_held_fire`, ║
	# ║ dont le commentaire écrit noir sur blanc « un glissé de curseur sur un réglage ne doit pas    ║
	# ║ vider un chargeur ») — le raisonnement était juste, il n'avait été appliqué qu'à UN des deux  ║
	# ║ chemins. Conséquence, manette en main : en ENTRAÎNEMENT, ouvrir F10 et cliquer sur un curseur ║
	# ║ de réglage ARMAIT un vrai tir — détonation, traçante, cran de recul, une munition consommée.  ║
	# ║ MESURÉ : panneau posé visible, état `playing`, cadence échue → `_input(clic gauche)` rendait  ║
	# ║ `_fire_queued = true` et `_shot_count = 1`, là où `_step_held_fire(true)` sur le MÊME état    ║
	# ║ rendait `false` / `0`.                                                                         ║
	# ║ ⚠️ CE N'EST PAS UN CHANGEMENT DE VISÉE : la branche de mouvement de souris ci-dessous est déjà ║
	# ║ inerte quand le panneau est ouvert (`_capture_mouse(false)` relâche le curseur, donc           ║
	# ║ `mouse_mode != CAPTURED`). Seule la porte du TIR change — les deux chemins ont désormais la    ║
	# ║ MÊME liste, et la sonde exige les deux ENSEMBLE pour que l'asymétrie ne se rouvre pas.        ║
	# ║ ⚠️ CETTE LISTE N'EST PLUS ÉCRITE ICI : elle vit dans `_ui_blocks_actions()`, partagée avec le  ║
	# ║ maintien ET la grenade (cf. le pavé au-dessus de cette fonction) — une copie de plus était     ║
	# ║ précisément ce qui a laissé le troisième chemin dériver.                                       ║
	# ║ ⚠️ §8.151 (2quater) — ELLE COUPE LE BLOC DE TOUCHES EN DEUX : ce qui pilote les PANNEAUX       ║
	# ║ répond TOUJOURS, ce qui agit sur le SOLDAT est passé AU-DESSUS de cette porte-ci, sous la     ║
	# ║ sienne (`_ui_blocks_survival()`, §8.151 2quinquies) : le SÉLECTEUR d'arme ne gèle plus le     ║
	# ║ soldat. Ne restent ici que la VISÉE et le TIR — les deux gestes qui ont besoin de la souris.  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	if _ui_blocks_actions():
		return
	# VISÉE : mouvement souris relatif → lacet/site, bornés.
	# ⚠️ Le SIGNE du site vient maintenant du panneau. Le testeur a rapporté « le mouvement de la
	# souris est inversé » sur un axe qui ne l'était pas — parce qu'une caméra qui ne tourne que de
	# 6° pour ±32° de visée donne exactement la même impression qu'un axe à l'envers. On lui donne
	# donc l'interrupteur plutôt qu'un avis, et on saura à la porte 1 lequel des deux c'était.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		var pitch_sign: float = 1.0 if _invert_y else -1.0
		_aim_yaw = clampf(_aim_yaw + SCREEN_TO_WORLD_X * motion.x * _sensitivity,
			-_yaw_limit, _yaw_limit)
		_aim_pitch = clampf(_aim_pitch + pitch_sign * motion.y * _sensitivity,
			-AIM_PITCH_LIMIT, AIM_PITCH_LIMIT)
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_queue_fire()


# ╔═ ⚠️⚠️ LE TIR PARTAIT OÙ LA SOURIS ÉTAIT AU MOMENT DE L'ENVOI, PAS DU CLIC ════════════════════╗
# ║ Verdict de partie réelle : « le projectile suit la variation de la souris qui se fait entre le  ║
# ║ clic et le démarrage du tir ». C'est exact, et c'était un vrai défaut : le clic ne posait qu'un ║
# ║ drapeau, et la visée jointe au message était relue jusqu'à 105 ms plus tard, à l'instant de     ║
# ║ l'envoi coalescé. Toute la souris parcourue dans l'intervalle déviait la balle — d'autant plus  ║
# ║ que le joueur suivait une cible.                                                                ║
# ║ On FIGE donc la visée à l'instant du clic et c'est ELLE qui part avec le tir. Le serveur reste  ║
# ║ seul juge de la touche : on ne change pas qui décide, on change QUELLE direction on déclare.    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ╔═ ⚠️⚠️ LE « FAUX COUP » : UN CLIC MONTRAIT UNE BALLE QUI NE PARTAIT PAS (§8.141.9) ═══════════╗
# ║ Verdict de Hakim : « chaque clic correspond à une balle VUE, mais pas forcément à une balle    ║
# ║ RÉELLE ». C'est un défaut que le §8.141.5 a INTRODUIT : pour supprimer les 100 ms de retard de ║
# ║ la traçante, on la joue au clic — mais le retour d'arme ne vérifiait QUE les munitions, alors  ║
# ║ que le serveur refuse un tir dans SIX cas. Le plus fréquent de loin est la CADENCE : la VIPÈRE ║
# ║ tire une fois par 0,9 s ; un joueur qui clique trois fois par seconde voyait donc trois        ║
# ║ traçantes pour une seule vraie balle.                                                          ║
# ║                                                                                                 ║
# ║ ⚠️ LA RÈGLE MAISON N'A PAS CHANGÉ, ON L'APPLIQUE MIEUX. Le client peut jouer ce qu'il SAIT      ║
# ║ (« j'ai tiré ») et jamais ce que seul le serveur sait (« j'ai touché »). Or « mon tir part-il » ║
# ║ EST connu du client : il a la posture, les munitions, le rechargement, le pansement et le laser ║
# ║ dans l'état reçu. Il n'a pas la cadence — `fire_ready_tick` n'est pas diffusé — alors il la     ║
# ║ PRÉDIT, exactement comme il prédit déjà le verrou de déplacement (`_pred_move_ready`).          ║
# ║ ⚠️ ET LE FILET EXISTE DÉJÀ : si le client refuse à tort, il ne pose pas `_fire_fx_mute`, donc   ║
# ║ l'événement `fire` du serveur rejoue le retour d'arme. Une prédiction trop prudente coûte un    ║
# ║ retour d'arme de 100 ms en retard ; une prédiction trop permissive coûte un mensonge.           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _queue_fire() -> void:
	if _fire_queued:
		return
	var refusal := _fire_refusal()
	if refusal != "":
		# ⚠️ ON N'ENVOIE MÊME PAS LE TIR. Le serveur le jetterait, et l'envoyer consommerait une
		# place dans le budget anti-flood de 9 msg/s — au détriment du prochain tir, celui-là légal.
		_refuse_fire(refusal)
		return
	_fire_queued = true
	_fire_aim = Vector2(_aim_yaw, _aim_pitch)
	_local_fire_feedback()


# =================================================================================================
# §8.151 (VAGUE 2ter, §4bis.5) — LE TIR MAINTENU (décision produit §1.8 : ACTIF PAR DÉFAUT)
# =================================================================================================
# ╔═ POURQUOI DEUX FONCTIONS, ET PAS UNE ═════════════════════════════════════════════════════════╗
# ║ `_fire_hold_active()` LIT la plateforme (souris, manette) ; `_step_held_fire()` DÉCIDE. La      ║
# ║ séparation n'est pas un ornement : elle rend la décision jouable par une sonde, alors que       ║
# ║ l'état d'un bouton physique ne l'est pas — et une règle de cadence qu'aucune garde ne peut      ║
# ║ rejouer est une règle qu'on croit sur parole. C'est le même découpage que `_fire_refusal()`,    ║
# ║ que `probe_trench_falseshot` appelle directement depuis 8.141.9.                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _fire_hold_active() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	return Input.get_connected_joypads().size() > 0 \
		and Input.is_joy_button_pressed(0, JOY_BUTTON_A)


# ╔═ LA RÈGLE : ON N'ÉMET QUE CE QUE LE SERVEUR ACCEPTERAIT ══════════════════════════════════════╗
# ║ Chaque frame tenue repasse par la prédiction des SIX refus. C'est ce qui rend le tir maintenu   ║
# ║ MÉCANIQUEMENT NEUTRE (§1.8) : le rythme obtenu est exactement `cooldown_ticks` du registre,     ║
# ║ celui qu'un cliqueur rapide obtenait déjà — et le budget anti-flood de 9 msg/s n'est jamais     ║
# ║ dépensé pour un tir que `trench_sim.step` jetterait.                                            ║
# ║ ⚠️ LE SON DE REFUS N'APPARTIENT QU'AU GESTE VOLONTAIRE. Un clic (front montant, `_input`) qui    ║
# ║ tombe pendant la cadence CLAQUE — c'est le §8.141.9, « un refus n'est jamais silencieux ». Un   ║
# ║ MAINTIEN, lui, n'est pas une demande répétée : c'est une demande CONTINUE, déjà exaucée dès     ║
# ║ que la porte s'ouvre. La claquer 7 fois par seconde en serait la caricature.                    ║
# ║ ⚠️ « chargeur vide » est le seul refus qui PRODUISE quelque chose côté serveur (il déclenche le  ║
# ║ rechargement) : le maintien l'envoie UNE fois — verrou `_hold_empty_latch`, relâché dès que le  ║
# ║ chargeur n'est plus vide. Sans ce verrou, une gâchette tenue sur un chargeur vide inonderait.    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _step_held_fire(held: bool) -> void:
	# LES MÊMES PORTES QUE `_input` ET QUE LA GRENADE — une seule liste, `_ui_blocks_actions()` :
	# un glissé de curseur sur un réglage ne doit pas vider un chargeur.
	if _ui_blocks_actions():
		_fire_hold_pad_prev = false
		_hold_empty_latch = false
		return
	# LE FRONT MONTANT DE LA MANETTE vaut un clic — refus audible compris. La souris, elle, a déjà
	# son front montant dans `_input` (`InputEventMouseButton.pressed`).
	var pad: bool = Input.get_connected_joypads().size() > 0 \
		and Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	var pad_edge: bool = pad and not _fire_hold_pad_prev
	_fire_hold_pad_prev = pad
	if pad_edge:
		_queue_fire()
		return
	if not held or not _auto_fire:
		_hold_empty_latch = false
		return
	var refusal := _fire_refusal()
	if refusal == "":
		_hold_empty_latch = false
		_queue_fire()
	elif refusal == "chargeur vide" and not _hold_empty_latch:
		_hold_empty_latch = true
		_queue_fire()


# LES HUIT REFUS DU SERVEUR, dans l'ordre où `trench_sim.step` les applique. Renvoie "" si le tir
# part vraiment. ⚠️ Miroir EXACT : toute condition ajoutée côté sim doit apparaître ici, sinon le
# faux coup revient — c'est pour ça qu'elles sont énumérées dans le même ordre et nommées pareil.
# ⚠️⚠️ ELLES ÉTAIENT SIX, ET IL EN MANQUAIT DEUX. Les deux oubliées ne sont pas des conditions du
# bloc de tir : ce sont deux `return`/`continue` ANTICIPÉS qui n'atteignent jamais ce bloc — donc
# exactement le genre de refus qu'une relecture du bloc de tir ne peut pas voir. Les deux sont
# devenus routiniers avec le TIR MAINTENU (§4bis.5, actif par défaut) : ce qui était un clic
# malheureux occasionnel est devenu une salve automatique à la cadence de l'arme.
func _fire_refusal() -> String:
	var latest := _latest()
	var me := _player_of(latest, _my_slot)
	if me.is_empty():
		return "attente"                                  # aucun état : on ne promet rien
	# ╔═ 7ᵉ REFUS — LA PHASE (`trench_sim.step`, tout en haut : deux `return` anticipés) ══════════╗
	# ║ `PHASE_OVER` rend la main immédiatement ; `PHASE_INTERMISSION` — le bandeau de 3 s          ║
	# ║ (`intermission_ticks` = 60) qui précède CHAQUE manche, la première comprise — ne traite que  ║
	# ║ le bookkeeping et `pick_weapon` avant de sortir. Tout `fire` de ces fenêtres est JETÉ, en    ║
	# ║ silence. Gâchette tenue, cela faisait une salve complète à chaque transition de manche :     ║
	# ║ détonation, traçante, cran de recul et frame d'arme joués pour des balles qui n'ont jamais   ║
	# ║ existé — le « faux coup » du §8.141.9 rentré par la porte de derrière.                       ║
	# ║ ⚠️ LE TEST PORTE SUR « LA MANCHE TOURNE », JAMAIS SUR LE NOM D'UNE PHASE PARTICULIÈRE : une   ║
	# ║ phase inconnue (ou ajoutée demain côté serveur) est traitée comme un refus, et un état sans  ║
	# ║ champ `phase` garde l'ancien comportement — le défaut par excès de prudence coûte un retour  ║
	# ║ d'arme de 100 ms rejoué par l'événement serveur, le défaut inverse coûte un mensonge.        ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	if str(latest.get("phase", "playing")) != "playing":
		return "hors manche"
	if _pred_stance != "up":
		return "accroupi"                                 # `step` : on ne tire pas accroupi
	# ╔═ 8ᵉ REFUS — LA GRENADE DÉJÀ EN FILE (`trench_sim.step`, branche de lancer) ════════════════╗
	# ║ Elle se termine par `continue  # lancer ce tick = pas de tir ce tick (un soldat n'a que      ║
	# ║ deux mains)` : le `fire` du MÊME message est écarté sans un mot. Or l'envoi est COALESCÉ sur ║
	# ║ 105 ms et `_step_held_fire` s'exécute juste APRÈS `_update_grenade_aim` dans `_process` —    ║
	# ║ toute grenade relâchée gâchette tenue tombait donc dans la même fenêtre, et le tir était     ║
	# ║ présenté au joueur avant d'être jeté par la sim. On ne l'arme plus tant que le lancer n'est  ║
	# ║ pas parti : il repassera à la frame suivante (l'attente est bornée — cf. l'exclusion         ║
	# ║ mutuelle à la construction de la charge utile, qui traite l'ordre inverse).                  ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	if not _throw_queued.is_empty():
		return "grenade"
	if int(me.get("laser_fire_tick", 0)) > 0:
		return "laser"                                    # CONDOR : le tir est déjà armé
	if int(me.get("reload_until_tick", 0)) > 0:
		return "rechargement"
	if int(me.get("bandage_until_tick", 0)) > 0:
		return "pansement"
	if int(me.get("ammo", 0)) <= 0:
		return "chargeur vide"                            # le clic déclenchera un rechargement
	if _clock < _pred_fire_ready:
		return "cadence"                                  # LE cas fréquent — voir le pavé ci-dessus
	return ""


# LE REFUS SE VOIT ET S'ENTEND — jamais un silence (même règle que le refus de grenade §B.1.3).
# ⚠️ « Chargeur vide » est le seul refus qui PRODUIT quelque chose côté serveur (il déclenche le
# rechargement, confort standard du genre) : on laisse donc le clic partir dans ce cas-là.
func _refuse_fire(reason: String) -> void:
	# ⚠️ LA CADENCE EST LE SEUL REFUS QU'ON MÉMORISE, et c'est délibéré : c'est le seul où
	# le joueur a raison sur le FOND (il veut tirer, il tirera) et se trompe seulement sur
	# l'INSTANT. Un clic pendant un rechargement, un pansement ou sous un panneau n'est pas
	# une anticipation : c'est un autre geste, et le mémoriser tirerait à la place du joueur.
	if reason == "cadence":
		_fire_buffer_until = _clock + FIRE_BUFFER
	if reason == "chargeur vide":
		_fire_queued = true
		_fire_aim = Vector2(_aim_yaw, _aim_pitch)
	if _fire_refuse > 0.0:
		return
	_fire_refuse = 0.14
	AudioManager.play_sfx("trench_refused", -10.0)


# Le RETOUR D'ARME, joué à l'instant du clic. Il ne prétend RIEN sur la touche — le hitmarker reste
# strictement serveur (règle maison §5.5). Mais attendre l'aller-retour pour bouger l'arme et faire
# le bruit, c'est ~250 ms de silence après un clic : le tir paraît « en retard » même quand il ne
# l'est pas. On garde donc l'honnêteté là où elle porte (la TOUCHE) et on rend la main immédiate.
# ⚠️ SAUF SI LE TIR EST TÉLÉGRAPHIÉ (CONDOR) : là, le clic n'a pas fait partir de balle — voir le
# pavé au milieu de cette fonction. Ce qu'il a VRAIMENT produit (cadence consommée, réarmement
# programmé) est posé avant la garde ; le reste attend le tir réel.
func _local_fire_feedback() -> void:
	if int(_my("ammo")) <= 0:
		return
	var weapon_id := str(_my("weapon"))
	var flight := 1.0
	var rounds := 1
	var cadence := 0.0
	var lead := 0.0
	var gap := 0.0
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			flight = float(weapon.get("flight_ticks", 1))
			rounds = int(weapon.get("burst", 1))
			cadence = float(weapon.get("cooldown_ticks", 0))
			lead = float(weapon.get("laser_lead_ticks", 0))
			# §8.151 (2bis) — l'espacement RÉEL des projectiles d'une rafale, diffusé par le
			# serveur depuis cette vague (patron dispersion_deg §8.137). Repli 0 (registre
			# d'avant cette vague) : les crans tombent ensemble, comme l'ancienne présentation.
			gap = float(weapon.get("burst_gap_ticks", 0))
			break
	# ⚠️ LA CADENCE EST CONSOMMÉE MÊME PAR UN TIR TÉLÉGRAPHIÉ : c'est ce que fait `step` (il pose
	# `fire_ready_tick` AVANT de brancher sur le laser). Sans ça le CONDOR laisserait cliquer en
	# rafale pendant son propre temps de visée. Elle est donc posée AVANT toute branche, et le
	# réarmement (`_arm_bolt`) avec elle : ce sont les deux seules choses qu'un clic télégraphié
	# a réellement produites côté serveur.
	_pred_fire_ready = _clock + cadence / _tick_rate
	_arm_bolt()          # §8.151 : un tir réel est parti → le réarmement s'entendra
	# ╔═ §8.151 (2bis) — LE CLIC DU CONDOR N'EST PAS LE COUP : IL ARME UN LASER ══════════════════╗
	# ║ ⚠️ DÉFAUT SOLDÉ ICI. Le code écrivait déjà la règle, en garde de la traçante (« PAS DE       ║
	# ║ TRAÇANTE POUR LE CONDOR : son clic ARME UN LASER, la balle ne part que 0,5 s plus tard ; en ║
	# ║ dessiner une tout de suite serait remplacer un faux coup par un autre ») — et il            ║
	# ║ l'enfreignait :                                                                             ║
	# ║ la garde ne protégeait QUE la traçante. Le faux coup VISUEL était refusé pendant que le     ║
	# ║ faux coup SONORE (détonation), le recul et la frame de tir partaient au clic. Puis          ║
	# ║ `_fire_fx_mute` expirait AVANT l'événement `fire` du serveur (émis `laser_lead_ticks` plus  ║
	# ║ tard, `_fire_burst` du tir laser échu) : le vrai tir rejouait TOUT. Un coup de CONDOR       ║
	# ║ valait DEUX détonations complètes de 1,15 s, recouvertes sur ~0,65 s.                       ║
	# ║ RÈGLE : un tir TÉLÉGRAPHIÉ (`laser_lead_ticks > 0`, LU au registre — jamais un id d'arme    ║
	# ║ codé en dur) ne produit RIEN de balistique au clic. Ni son, ni recul, ni frame d'arme, ni   ║
	# ║ traçante, ni cran de rafale — et surtout PAS de `_fire_fx_mute`, dont la seule raison       ║
	# ║ d'être est d'empêcher le rejeu d'un retour d'arme DÉJÀ JOUÉ. Le tir se voit et s'entend au  ║
	# ║ moment où il part VRAIMENT, sur l'événement `fire` du serveur (branche `_fire_fx_mute       ║
	# ║ <= 0.0` de `_on_duel_event`) : une seule détonation, à l'heure de la balle. Le retour       ║
	# ║ immédiat du clic, lui, existe déjà et il est HONNÊTE : c'est le rayon laser lui-même.       ║
	# ║ ⚠️ Aucune fenêtre à régler : la garde ne compare plus deux durées (0,45 s contre 0,50 s),    ║
	# ║ elle ne joue simplement rien. Retoucher le ⚙ `laser_lead_ticks` ne peut plus rien casser.   ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	if lead > 0.0:
		# ⚠️ ON NE JOUE TOUJOURS RIEN DE BALISTIQUE — ni détonation, ni recul, ni traçante :
		# la règle du §8.151-2bis tient. Ce qu'on rend immédiatement, c'est le RAYON, qui est
		# la seule chose que le clic a réellement produite côté serveur. Le pavé ci-dessus le
		# disait déjà — il se trompait seulement en le croyant IMMÉDIAT, alors qu'il attendait
		# un aller-retour réseau. On le prédit, exactement comme la cadence et la position.
		_laser_pred_until = _clock + FIRE_BUFFER + lead / _tick_rate
		_laser_pred_aim = _fire_aim
		_laser_pred_pos = _pred_pos
		return
	_fire_feel_kick()             # §8.151 : roulis + punch de FOV — cosmétiques, retour-à-zéro
	_fire_fx_mute = 0.45          # l'événement serveur de CE tir ne doit pas le rejouer
	if _viewmodel != null:
		_viewmodel.notify_fire()
	# §8.151 (2bis) — la détonation dans la VOIX de l'arme courante (repli : voix générique).
	AudioManager.play_sfx(_shot_sfx_key(weapon_id))
	# ⚠️ LA TRAÇANTE PART ELLE AUSSI TOUT DE SUITE (§8.141.5). Elle était bâtie depuis la paire de
	# rendu RETARDÉE et apparaissait donc ~100 ms APRÈS le hitmarker : le joueur voyait la
	# confirmation de sa touche AVANT la balle. On la joue au clic, avec la visée FIGÉE au clic —
	# même raisonnement que le recul et la détonation ci-dessus. Le hitmarker, lui, reste serveur.
	if _world != null:
		# §8.151 (2bis) — UN SEUL projectile part MAINTENANT : les suivants de la rafale ont
		# chacun leur cran (traçante comprise), planifiés ci-dessous au rythme du registre.
		_world.notify_local_shot(_pred_pos, _fire_aim.x, _fire_aim.y, flight / _tick_rate, 1)
	# §8.151 (2bis) — LES CRANS 2..N DE MA RAFALE, au rythme où le serveur les fera partir
	# (`launch = tick + i × burst_gap_ticks`, miroir de `_fire_burst`). Le nombre est borné par mes
	# munitions comme côté sim (`rounds = min(burst, ammo)`), la visée/position/arme sont FIGÉES au
	# clic (le serveur fige les siennes au tick du tir — un pas ou un pansement pendant les 200 ms
	# de rafale ne doit dévier ni le vrai projectile ni sa présentation). §8.141.9 tient : on
	# n'arrive ici QUE depuis un tir accepté par la prédiction des six refus.
	var real_rounds := mini(rounds, maxi(1, int(_my("ammo"))))
	for i in range(1, real_rounds):
		_burst_queue.append({"due": _clock + float(i) * gap / _tick_rate, "mode": "local",
			"weapon": weapon_id, "pos": _pred_pos, "yaw": _fire_aim.x, "pitch": _fire_aim.y,
			"flight_s": flight / _tick_rate})


# ╔═ §8.151 (LOT A) — LE RÉARMEMENT S'ENTEND : trench_bolt quand la cadence redevient disponible ═╗
# ║ Le clac de culasse est un REPÈRE DE RYTHME : il dit « prête » sans que le joueur regarde le     ║
# ║ HUD. Il n'est PAS la couche mécanique du tir (elle vit dans trench_shot_*.wav, 20-40 ms après   ║
# ║ le départ) : les cadences réelles vont de 0,8 à 2,5 s, il parle donc toujours loin du coup.     ║
# ║ ⚠️ Armé par un TIR RÉEL uniquement — `_local_fire_feedback` (prédit) ou l'événement `fire` du   ║
# ║ serveur (réconcilié) — donc JAMAIS par un clic refusé : `_refuse_fire` ne passe par aucun des   ║
# ║ deux chemins (§8.141.9 : un refus ne joue rien de balistique, seulement `trench_refused`).      ║
# ║ La garde de 0,1 s écarte le repli dégénéré (arme absente du registre → cadence 0) : un          ║
# ║ réarmement « immédiat » se confondrait avec la mécanique du tir et signalerait un faux rythme.  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const BOLT_MIN_DELAY := 0.1


func _arm_bolt() -> void:
	_bolt_armed = _pred_fire_ready > _clock + BOLT_MIN_DELAY


# ╔═ §8.151 — LE FEEL DE CAMÉRA AU TIR : roulis + punch de FOV, sur tir ACCEPTÉ SEULEMENT ════════╗
# ║ Appelé exactement là où `_recoil = 1.0` vivait : `_local_fire_feedback` (tir prédit accepté)   ║
# ║ et l'événement `fire` non prédit. Un clic refusé ne passe par AUCUN des deux (§8.141.9).       ║
# ║ Le côté du roulis alterne au hachage du compteur de tirs — déterministe, aucun RNG global.     ║
# ║ §8.151 (2bis) — `scale` : le cran d'un coup SUIVEUR de rafale kicke à BURST_KICK_SCALE (~40 %  ║
# ║ de moins) ; le cumul du roulis reste borné par le plafond ROLL_CAP_DEG existant, et le punch   ║
# ║ de FOV est POSÉ (set_value), donc re-tirer pendant le retour repart du plafond, sans s'empiler.║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _fire_feel_kick(scale := 1.0) -> void:
	if _reduced_motion:
		return          # le kick du viewmodel, lui, reste (réduit de moitié, géré chez lui)
	# §8.151 (2ter, §4bis.1) — LE PULSE DU RÉTICULE naît ICI et nulle part ailleurs : ce point est
	# déjà, par construction, « un projectile PRÉSENTÉ » (clic accepté, événement `fire` non prédit,
	# ou cran de rafale). Un clic REFUSÉ n'y passe pas — le réticule ne peut donc pas pulser pour un
	# coup qui n'existe pas. POSÉ, jamais cumulé : trois balles de FRELON = un plafond, pas un bloom.
	_reticle_pulse.set_value(1.0)
	_shot_count += 1
	var side: float = 1.0 if Springs.hash_noise(float(_shot_count), ROLL_SIDE_SEED) >= 0.0 else -1.0
	_cam_roll.kick(ROLL_KICK_DEG * side * _feel_recoil * scale)
	if _feel_fov_punch:
		# En DÉPLACEMENT (`set_value`), pas en impulsion : le punch est un saut qui revient, pas
		# une poussée qui gonfle. Un second tir pendant le retour repart simplement du plafond.
		_fov_punch.set_value(FOV_PUNCH_DEG * scale)


# =================================================================================================
# §8.151 (VAGUE 2bis) — L'EFFET MITRAILLETTE : voix par arme + crans de rafale (cahier §4bis.4/§3.6)
# =================================================================================================
# La CLÉ de détonation de l'arme : famille `trench_shot_<id>` si le manager peut la servir, sinon
# la voix générique `trench_shot` (repli d'arbre nu/headless — elle garde, elle, un synthé). L'id
# vient de l'ÉTAT ou de l'ÉVÉNEMENT serveur, jamais d'une table locale (§8.137).
func _shot_sfx_key(weapon_id: String) -> String:
	if weapon_id != "" and AudioManager.has_sfx("trench_shot_" + weapon_id):
		return "trench_shot_" + weapon_id
	return "trench_shot"


# Le facteur de vitesse qui fait TENIR le bourdonnement du télégraphe dans la fenêtre de danger :
# durée du fichier ÷ fenêtre (1,0 si l'une des deux est inconnue — un télégraphe muet ou une
# fenêtre nulle n'a rien à caler). La durée vient du manager, jamais d'une constante recopiée ;
# le bornage [SFX_PITCH_MIN, SFX_PITCH_MAX] est appliqué par le manager, à la pose du lecteur.
func _laser_warn_pitch(window_s: float) -> float:
	var length: float = AudioManager.sfx_length("trench_laser_warn")
	if length <= 0.0 or window_s <= 0.0:
		return 1.0
	return length / window_s


# Les crans 2..N d'une rafale ANNONCÉE par l'événement `fire` (adverse, ou mienne non prédite).
# CADENCEMENT : les `launch_tick` PAR PROJECTILE de l'état arrivé dans le MÊME message font foi
# (`_on_state` pousse l'état AVANT de dispatcher ses événements — l'ordre est garanti par le code,
# pas par la chance). Si l'état ne portait pas la rafale (harnais minimal, paquet exotique), le
# repli est l'espacement du REGISTRE — la valeur même que `_fire_burst` a utilisée.
func _schedule_burst_followups(mode: String, event: Dictionary) -> void:
	var rounds := int(event.get("rounds", 1))
	if rounds <= 1:
		return
	var weapon_id := str(event.get("weapon", ""))
	var slot := int(event.get("slot", 0))
	var state := _latest()
	var state_tick := int(state.get("tick", 0))
	# Les départs FUTURS de cette rafale : les projectiles de CE tireur lancés APRÈS le tick de
	# l'événement. Ceux d'une rafale précédente sont déjà partis (cooldown ≫ rafale) — le filtre
	# `launch_tick > state_tick` les écarte d'office, ainsi que le cran 1 (déjà joué à l'instant).
	var delays: Array = []
	for proj in state.get("projectiles", []):
		if int(proj.get("owner_slot", 0)) != slot or str(proj.get("kind", "")) == "grenade":
			continue
		var launch := int(proj.get("launch_tick", 0))
		if launch > state_tick:
			delays.append(float(launch - state_tick) / _tick_rate)
	delays.sort()
	# Repli registre pour les crans que l'état n'a pas montrés (jamais plus que `rounds - 1`).
	var gap := 0.0
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			gap = float(weapon.get("burst_gap_ticks", 0))
			break
	while delays.size() < rounds - 1:
		delays.append(float(delays.size() + 1) * gap / _tick_rate)
	var pos := int(round(_last_seen_enemy_pos))
	for i in range(rounds - 1):
		_burst_queue.append({"due": _clock + float(delays[i]), "mode": mode,
			"weapon": weapon_id, "pos": pos, "yaw": 0.0, "pitch": 0.0, "flight_s": 0.0})


# Le POMPAGE de la file, à chaque frame — y compris après la fin de match (un duel qui se termine
# SUR une rafale laisse ses derniers crans se poser, comme le serveur laisse voler ses derniers
# projectiles). La file se vide seule en moins d'un quart de seconde.
func _step_burst_queue() -> void:
	if _burst_queue.is_empty():
		return
	var still: Array = []
	for cran in _burst_queue:
		if _clock < float(cran["due"]):
			still.append(cran)
		else:
			_play_burst_cran(cran)
	_burst_queue = still


# UN cran de rafale — la présentation d'UN projectile suiveur (le cran 1 vit à son site d'origine :
# `_local_fire_feedback` ou l'événement `fire`). Toujours en aval d'un tir ACCEPTÉ/CONFIRMÉ :
# jamais d'écriture dans une variable de visée, la règle §8.141.6 ne bouge pas d'un octet.
func _play_burst_cran(cran: Dictionary) -> void:
	var weapon_id := str(cran.get("weapon", ""))
	AudioManager.play_sfx(_shot_sfx_key(weapon_id))
	match str(cran.get("mode", "")):
		"local":
			_fire_feel_kick(BURST_KICK_SCALE)
			if _viewmodel != null:
				_viewmodel.notify_fire()
			if _world != null:
				_world.notify_local_shot(int(cran.get("pos", 2)), float(cran.get("yaw", 0.0)),
					float(cran.get("pitch", 0.0)), maxf(0.05, float(cran.get("flight_s", 0.05))), 1)
		"mine_event":
			# Tir MIEN non anticipé (reconnexion…) : kick + frame d'arme, pas de traçante locale —
			# celles de l'état portent déjà ce tir-là (même contrat que le cran 1 de cette branche).
			_fire_feel_kick(BURST_KICK_SCALE)
			if _viewmodel != null:
				_viewmodel.notify_fire()
		"enemy":
			# La lueur re-déclenchée pulse au canon d'en face — `from_pos` figé au départ de la
			# rafale, comme les projectiles du serveur (ils partent tous de la MÊME position).
			if _world != null:
				_world.notify_enemy_fire(int(cran.get("pos", 2)))


# §8.151 — LE PAS DE FEEL, à chaque frame (même après la fin de match : les effets se POSENT).
# Il LIT la secousse publiée par le monde et l'applique à l'IMAGE ENTIÈRE — les couches visibles ET
# le réticule (via `_refresh_hud`) reçoivent LE MÊME vecteur : la relation visée/pixel est intacte.
# Le ciel de dernier recours (couche 0) ne bouge pas : c'est lui qui remplit les bords révélés.
func _step_feel(delta: float) -> void:
	_cam_roll.step(delta)
	_fov_punch.step(delta)
	# §8.151 (2ter) — le pulse du réticule suit la MÊME horloge que les autres ressorts : il se pose
	# aussi après la fin de match (un réticule figé ouvert serait un défaut de capture).
	_reticle_pulse.step(delta)
	if _world != null:
		_world.set_camera_feel(clampf(_cam_roll.value, -ROLL_CAP_DEG, ROLL_CAP_DEG),
			_fov_punch.value if _feel_fov_punch else 0.0)
		var px: Vector2 = _world.shake_screen_px()
		if px != _shake_px:
			_shake_px = px
			# Écrit SEULEMENT au changement : au repos la secousse est un ZÉRO exact (assèchement
			# du trauma) et plus rien n'est posé — la condition de bit-stabilité des captures.
			for layer: Control in [_world, _ambient, _viewmodel]:
				if layer != null:
					layer.position = px
	if _viewmodel != null:
		_viewmodel.set_aim(_aim_yaw, _aim_pitch)


# Les réglages du panneau F10, appliqués À LA FRAME. Le lacet et le site ENVOYÉS au serveur ne
# changent pas de nature : seules la vitesse à laquelle la souris les fait varier et ce que la
# caméra en montre vivent ici. Aucune règle, aucun barème, aucun message réseau n'en dépend —
# c'est la condition pour que ce panneau reste un réglage de CONFORT et pas un avantage.
func _apply_tuning(values: Dictionary) -> void:
	_sensitivity = float(values.get("mouse_sensitivity", _sensitivity))
	_ads_toggle = bool(values.get("ads_toggle", _ads_toggle))
	_invert_y = bool(values.get("invert_y", _invert_y))
	# §8.151 — les intensités de feel. Bornées ici aussi : le fichier de réglages est une
	# commodité, jamais une autorité. `feel_shake`/`feel_breath` transitent vers leurs
	# propriétaires (le monde pour la secousse, le viewmodel pour la respiration).
	_feel_recoil = clampf(float(values.get("feel_recoil", _feel_recoil)), 0.0, 2.0)
	_feel_flinch = clampf(float(values.get("feel_flinch", _feel_flinch)), 0.0, 2.0)
	_feel_fov_punch = bool(values.get("fov_punch", _feel_fov_punch))
	# §8.151 (2ter) — l'interrupteur du TIR MAINTENU (§4bis.5 : « réglage F10 pour le couper »).
	# Il ne touche ni la cadence ni la visée : coupé, un clic = un tir, exactement comme avant.
	_auto_fire = bool(values.get("auto_fire", _auto_fire))
	if _viewmodel != null:
		_viewmodel.set_feel_tuning(values)
	if _world != null:
		_world.apply_tuning(values)


func _gather_move_dir() -> int:
	# ╔═ §8.151 (2quater) — LE 4ᵉ CHEMIN D'ACTION, ET LE MÊME MOTIF QUE LA GRENADE ══════════════════╗
	# ║ Cette fonction SONDE la plateforme depuis `_process` (`Input.is_key_pressed`) au lieu          ║
	# ║ d'attendre un événement : la garde d'`_input` ne pouvait RIEN pour elle, et le relâchement du  ║
	# ║ curseur (`_capture_mouse(false)`) pas davantage. Panneau ouvert, le joueur ne pouvait plus     ║
	# ║ viser — mais son soldat MARCHAIT, et la charge coalescée emportait le `move` sans condition.   ║
	# ║ ⚠️ ET LE PANNEAU F10 SE PILOTE AUX FLÈCHES : la navigation de focus de Godot règle ses HSlider ║
	# ║ avec ←/→. Régler un curseur faisait littéralement faire des pas au soldat.                     ║
	# ║ ⚠️ ZÉRO, PAS « ON IGNORE » : la valeur rendue alimente à la fois la prédiction locale ET le    ║
	# ║ champ `move` du message. Rendre 0 les tient tous les deux d'un seul geste — un client qui      ║
	# ║ cesserait de prédire tout en continuant d'envoyer divergerait d'un pas à chaque appui.         ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	# ⚠️ §8.151 (2quinquies) — LA PORTE DE SURVIE, PAS CELLE DES GESTES OFFENSIFS. Marcher pendant que
	# le SÉLECTEUR d'arme est à l'écran est non seulement légitime, c'est ce que la simulation HONORE : elle
	# applique `move` sans regarder `choice_deadline_tick`, et l'adversaire, lui, joue pendant ces 5,0 s.
	if _ui_blocks_survival():
		return 0
	var dir := 0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_Q):
		dir -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir += 1
	if dir == 0 and Input.get_connected_joypads().size() > 0:
		var axis := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		if absf(axis) > 0.5:
			dir = 1 if axis > 0.0 else -1
		elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
			dir = -1
		elif Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
			dir = 1
	# ⚠️ La MÊME correction que pour la souris, au MÊME endroit unique : « flèche droite » doit
	# emmener le joueur vers la droite de son ÉCRAN, c'est-à-dire vers les x décroissants du monde.
	# ⚠️⚠️ Et elle s'applique AVANT que `dir` ne serve : la valeur corrigée alimente à la fois la
	# prédiction locale ET le champ `move` du message réseau. Corriger l'une sans l'autre ferait
	# diverger le client du serveur d'un pas à chaque appui — soit le pire des deux mondes.
	return int(SCREEN_TO_WORLD_X) * dir


func _process(delta: float) -> void:
	_clock += delta
	_decay(delta)
	# §8.151 — le feel se pose AUSSI après la fin de match : un roulis qui resterait figé sur
	# l'écran de résultat serait un défaut de capture ET une image penchée pour rien.
	_step_feel(delta)
	# §8.151 (2ter) — les chiffres de dégâts en vol avancent AUSSI après la fin de match : le coup
	# fatal est, par définition, celui qui la déclenche — son chiffre doit pouvoir finir sa montée.
	_step_damage_numbers()
	# §8.151 (2bis) — les crans de rafale en attente partent à leur heure (avant la porte de fin de
	# match : une manche gagnée SUR une rafale laisse ses derniers coups se poser, < 0,25 s).
	_step_burst_queue()
	if _match_over:
		_refresh_view(delta)
		return

	# §8.151 (LOT A) : le clac de culasse à l'instant où la cadence redevient disponible (le pavé
	# au-dessus de `_arm_bolt`). Après la fin de match, le bloc ci-dessus a déjà rendu la main.
	if _bolt_armed and _clock >= _pred_fire_ready:
		_bolt_armed = false
		AudioManager.play_sfx("trench_bolt")

	_vider_tampon_de_tir()
	_update_ads()
	# Le rig est une VUE : il ne relit jamais l'état, on le lui pousse. Le garde
	# `has_method` n'est pas de la prudence décorative — il rend le retour au viewmodel 2D
	# possible en changeant une seule ligne, sans toucher à celle-ci.
	if _viewmodel != null and _viewmodel.has_method("pousser_etat"):
		_viewmodel.pousser_etat(_rig_state())
	_update_grenade_aim(delta)
	# §8.151 (2ter, §4bis.5) — LE TIR MAINTENU. Il REMPLACE l'ancien appel manette inconditionnel
	# (`is_joy_button_pressed(A) → _queue_fire()` à chaque frame), qui claquait le son de refus ~7
	# fois par seconde dès que la cadence n'était pas échue. Voir `_step_held_fire`.
	_step_held_fire(_fire_hold_active())

	# --- Prédiction locale : posture et position immédiates (le ressenti ne dépend jamais du réseau) ---
	var wanted_stance := "down" if _stance_toggle else "up"
	var dir := _gather_move_dir()
	var pose_changed := false
	if wanted_stance != _pred_stance:
		_pred_stance = wanted_stance
		pose_changed = true
	# ╔═ ⚠️⚠️ ON NE PRÉDIT PAS TANT QUE LE SERVEUR NE SIMULE PAS ════════════════════════════════╗
	# ║ En COMPÉTITION, `_run_duel` attend que les DEUX humains soient connectés — jusqu'à 20 s   ║
	# ║ (`CONNECT_TIMEOUT_S`). Pendant cette attente `rt.state is None` : aucun tick ne tourne, et  ║
	# ║ les `trench_input` s'empilent dans un tampon plafonné à 30 avant d'être JETÉS. Le client,   ║
	# ║ lui, prédisait librement : le joueur faisait des pas, sa caméra bougeait… puis tout était    ║
	# ║ ramené au centre au coup d'envoi (`_begin_round`). En ENTRAÎNEMENT cette fenêtre est quasi   ║
	# ║ nulle (un seul humain à attendre), d'où un symptôme qui n'existe QU'EN COMPÉTITION.         ║
	# ║ On refuse donc de prédire un pas tant qu'aucun état serveur n'est arrivé : mieux vaut une    ║
	# ║ touche qui ne répond pas encore qu'une touche qui répond puis se dédit.                      ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	if dir != 0 and _clock >= _pred_move_ready and not _buffer.is_empty():
		var next_pos: int = clampi(_pred_pos + dir, 0, _positions - 1)
		if next_pos != _pred_pos:
			_pred_pos = next_pos
			# ⚠️ DÉFAUT À 4, PAS À 3 : le registre serveur est passé à 4 ticks (§8.141) et ce repli
			# était resté à l'ancienne valeur. Un client qui prédirait 3 quand le serveur applique 4
			# se croirait plus rapide qu'il n'est — donc ferait un pas de trop, puis se ferait
			# rappeler à l'ordre par la réconciliation. C'est-à-dire EXACTEMENT le symptôme « mes
			# flèches ne répondent pas ». Le repli n'est censé servir que si `trench_init` manque.
			_pred_move_ready = _clock + float(_rules.get("move_ticks", 10)) / _tick_rate
			pose_changed = true
	if pose_changed:
		_world.set_pose(_pred_pos, _pred_stance)
		_refresh_pose_view()

	# --- Envoi coalescé (10 Hz max) ---
	_send_accum += delta
	# ╔═ UN TIR NE FAIT PAS LA QUEUE ════════════════════════════════════════════════════════════╗
	# ║ La cadence de 0,105 s existe pour tenir SOUS les 10 msg/s de l'anti-flood serveur — pas    ║
	# ║ pour retarder les tirs. Une pression pouvait donc attendre jusqu'à 105 ms avant même de     ║
	# ║ partir, et ces 105 ms s'ajoutaient au tick serveur puis au retard de rendu.                 ║
	# ║ On autorise UN envoi anticipé quand un tir ou une grenade est en attente, mais seulement    ║
	# ║ si le budget de la seconde écoulée le permet — le plafond reste MATÉRIEL, pas déclaratif.   ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
	var urgent: bool = _fire_queued or not _throw_queued.is_empty()
	if _send_accum >= SEND_INTERVAL or (urgent and _send_budget_left()):
		_send_accum = 0.0
		# ⚠️ LA PURGE DE LA FENÊTRE GLISSANTE VIT ICI, PAS DANS `_send_budget_left()`. Elle n'était
		# faite que sur la branche URGENTE : sur une partie sans tir, `_sent_at` grossissait de 10
		# entrées par seconde sans jamais être élagué (~900 au bout d'une manche), et le budget
		# anti-flood se croyait épuisé pour toujours — donc plus aucun envoi anticipé.
		_prune_send_window()
		_sent_at.append(_clock)
		var payload := {"move": dir, "stance": _pred_stance}
		# La VISÉE ne part QUE si elle a bougé (§2.4), arrondie au quantum — moins d'octets, et
		# le serveur garde la dernière direction connue entre deux envois.
		var quantized := Vector2(snappedf(_aim_yaw, AIM_QUANTUM), snappedf(_aim_pitch, AIM_QUANTUM))
		if _fire_queued:
			# ⚠️ LE TIR IMPOSE SA PROPRE VISÉE, celle du CLIC, et elle écrase la visée courante
			# dans ce message. Sans ça, la balle partait là où la souris se trouvait à l'instant de
			# l'ENVOI — et le joueur qui suit sa cible voyait son tir dériver.
			quantized = Vector2(snappedf(_fire_aim.x, AIM_QUANTUM), snappedf(_fire_aim.y, AIM_QUANTUM))
		if not quantized.is_equal_approx(_sent_aim):
			payload["aim"] = {"yaw": quantized.x, "pitch": quantized.y}
			_sent_aim = quantized
		if _fire_queued:
			payload["fire"] = true
		# ╔═ UN SOLDAT N'A QUE DEUX MAINS — LE MESSAGE NON PLUS ══════════════════════════════════╗
		# ║ `trench_sim.step` traite le lancer AVANT le tir et sort par `continue` : les deux      ║
		# ║ champs dans le même message, c'est le TIR qui est jeté — alors qu'il a DÉJÀ été        ║
		# ║ présenté au joueur (`_local_fire_feedback` joue détonation, traçante et recul au clic).║
		# ║ Le 8ᵉ refus empêche d'ARMER un tir pendant qu'un lancer attend ; il reste l'ordre      ║
		# ║ inverse — le clic d'abord, la grenade relâchée ensuite dans la même fenêtre de         ║
		# ║ coalescence, ou un budget anti-flood épuisé qui fait patienter un tir déjà armé.       ║
		# ║ Là, c'est le LANCER qui cède le message, et la priorité est dans ce sens-là pour une   ║
		# ║ raison précise : le lancer n'a RIEN présenté localement (aucun son, aucune frame — la  ║
		# ║ grenade ne se voit qu'à l'événement serveur), donc le retarder d'un message ne ment à  ║
		# ║ personne, tandis que jeter le tir mentirait. Aucun des deux gestes n'est perdu :       ║
		# ║ `_throw_queued` n'est vidé que s'il est VRAIMENT parti, et `urgent` le fait repartir   ║
		# ║ dès la frame suivante — pendant laquelle le 8ᵉ refus interdit tout nouveau tir.        ║
		# ║ L'attente est donc bornée à UN message, jamais à une famine.                           ║
		# ╚═════════════════════════════════════════════════════════════════════════════════════╝
		elif not _throw_queued.is_empty():
			payload["throw"] = _throw_queued
		if _pick_queued != "":
			payload["pick_weapon"] = _pick_queued
		if _reload_queued:
			payload["reload"] = true
		if _item_queued != "":
			payload["item"] = _item_queued
		NetworkManager.send_trench_input(payload)
		_log_input(payload)
		_fire_queued = false
		# ⚠️ ON NE VIDE QUE CE QUI EST PARTI. Vider inconditionnellement, c'était perdre en silence
		# le lancer que l'exclusion ci-dessus vient de faire patienter — un geste du joueur avalé
		# par le client, exactement le symptôme « ma touche ne répond pas » du §8.140.1.
		if payload.has("throw"):
			_throw_queued = {}
		_pick_queued = ""
		_reload_queued = false
		_item_queued = ""

	_world.set_aim(_aim_yaw, _aim_pitch)
	_track_horizon()
	_refresh_view(delta)


# ╔═ LE JOURNAL DES ENTRÉES — POUR NE PLUS JAMAIS PERDRE UN SYMPTÔME ═════════════════════════════╗
# ║ « Les déplacements ne fonctionnent pas » a été rapporté en partie réelle et n'a JAMAIS été     ║
# ║ reproduit ni diagnostiqué : le chantier s'est arrêté avant. L'hypothèse retenue est que le     ║
# ║ mensonge visuel du fond peint le donnait à voir (un pas de côté décalait le décor de 2,5 %     ║
# ║ d'écran, invisible) — un monde 3D vrai devrait donc le faire disparaître.                      ║
# ║ Mais si le symptôme PERSISTE, on ne repartira pas pour une session d'hypothèses : ce journal   ║
# ║ montre à l'écran ce que le client croit envoyer, à côté de ce que le serveur lui répond.       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# =================================================================================================
# LA GRENADE : MAINTENIR POUR VISER, RELÂCHER POUR LANCER (§8.141)
# =================================================================================================
# ╔═ CE QUI REMPLACE LA JAUGE DE CHARGE, ET POURQUOI ═════════════════════════════════════════════╗
# ║ L'ancien geste : maintenir 1,2 s pour remplir une jauge dont la valeur choisissait une des cinq ║
# ║ positions adverses. Il demandait au joueur d'apprendre une correspondance abstraite, rendait la ║
# ║ souris inutile pendant tout le geste, et interdisait de viser ENTRE deux positions — c'est-à-  ║
# ║ dire là où un adversaire qui fait des pas de côté se trouve la moitié du temps.                 ║
# ║ Le geste neuf : on MAINTIENT pour voir où ça tombe (décalque au sol, au rayon RÉEL), on RELÂCHE ║
# ║ pour lancer. La trajectoire est FIGÉE à l'instant du relâchement — la souris n'a plus aucun     ║
# ║ effet sur le vol, et c'est déjà la physique de la simulation (lancement et impact sont fixés au ║
# ║ départ) : le client ne fait ici que ne pas mentir à ce sujet.                                    ║
# ║                                                                                                 ║
# ║ ⚠️ ANNULER NE COÛTE RIEN, et ce n'est pas une gentillesse : sans annulation, tout maintien       ║
# ║ accidentel (le clic droit est à un doigt du clic gauche) dépenserait une grenade sur deux. Un   ║
# ║ geste qu'on ne peut pas reprendre est un geste qu'on n'ose pas commencer.                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ⚠️ LA VISÉE, MAINTIEN OU BASCULE. Le maintien est le défaut (convention AAA).
# ⛔ Deux interdits, et ils ne sont pas cosmétiques : on ne vise pas une grenade à la main
# (les deux gestes se disputeraient le même bouton et la même pose de main), et on ne vise
# pas après la fin du match (une pose figée en visée serait un défaut de capture).
# ⚠️ LE TAMPON NE FAIT JAMAIS TIRER PLUS TÔT QUE LA RÈGLE. Il repasse par `_queue_fire()`,
# donc par les SIX refus au complet : si la cadence n'est pas échue, il ne se passe rien et le
# tampon attend la frame suivante. Il ne fait que convertir un clic PERDU en un clic HONORÉ
# au premier instant légal — et le serveur reste seul juge de ce qui part vraiment.
# ⚠️ Il est vidé DÈS qu'il a servi : sans ça, un seul clic anticipé armerait tous les tirs de
# la fenêtre suivante, ce qui SERAIT tirer à la place du joueur.
func _vider_tampon_de_tir() -> void:
	if _fire_buffer_until <= 0.0:
		return
	if _clock > _fire_buffer_until:
		_fire_buffer_until = 0.0
		return
	if _ui_blocks_actions() or _fire_queued:
		return
	if _fire_refusal() != "":
		return
	_fire_buffer_until = 0.0
	_queue_fire()


# ⚠️ SÉPARÉ EN DEUX À DESSEIN : la LECTURE du bouton d'un côté, la DÉCISION de l'autre.
# 🩸 Sans cette séparation, la sonde ne pouvait pas éprouver la décision — elle ne peut pas
# presser un bouton en headless — et elle en rejouait donc une COPIE. **Un contrôle qui teste sa
# propre copie de l'algorithme ne teste rien** : le sabotage qui supprimait les deux interdits
# la laissait VERTE. Depuis, elle appelle `_apply_ads()`, c'est-à-dire le vrai code.
# ⚠️ La leçon est générale : **une décision qu'on ne peut pas appeler depuis un test doit être
# séparée de son entrée.**
func _update_ads() -> void:
	_apply_ads(Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		or (Input.get_connected_joypads().size() > 0
			and Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)))


func _apply_ads(held: bool) -> void:
	if _ads_toggle:
		# Front MONTANT : sans le souvenir de l'image précédente, un maintien basculerait
		# soixante fois par seconde et la visée clignoterait.
		if held and not _ads_held_prev:
			_ads_active = not _ads_active
	else:
		_ads_active = held
	_ads_held_prev = held
	if _aiming_grenade or _match_over:
		_ads_active = false


# ╔═ L'ÉTAT POUSSÉ AU RIG 3D — tout ce qu'il a le droit de savoir, et rien d'autre ═══════╗
# ║ ⚠️ **LES ANGLES SONT EN RADIANS ICI, EN DEGRÉS LÀ-BAS.** `_aim_yaw` et `_aim_pitch` sont ║
# ║ en DEGRÉS (la sensibilité est en « degrés par pixel », le site est borné à 14). Le rig,   ║
# ║ lui, dérive une vitesse angulaire avec `wrap_pi`, donc en RADIANS. Pousser les degrés   ║
# ║ tels quels donnerait une vitesse **57 fois trop grande**, bornée à ±9 rad/s : la couche  ║
# ║ de traîne serait saturée en permanence, l'arme resterait collée en butée, et RIEN         ║
# ║ n'aurait l'air cassé — juste « bizarre ». C'est exactement le genre d'erreur d'unités     ║
# ║ qu'aucune compilation n'attrape.                                                          ║
# ║                                                                                          ║
# ║ ⛔ `cycle_time` est une CADENCE, donc une RÈGLE : elle passe par `_cadence_seconds`, qui ║
# ║ lit `public_rules`. Aucun barème en dur ne traverse cette fonction.                       ║
# ║ ⚠️ `crouch` N'EST PAS poussé : le rig ne le consomme pas (la posture change la hauteur   ║
# ║ de l'ŒIL, pas la pose de l'arme). Une clé annoncée que personne ne lit est pire qu'une   ║
# ║ clé absente : l'appelant la remplit et croit avoir branché quelque chose.                 ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════╝
func _rig_state() -> Dictionary:
	return {
		"ads": _ads_active,
		# Le joueur est CONFINÉ (§6 du cahier : pas de course, pas de saut, pas de strafe).
		# Les couches correspondantes du rig existent et resteront au repos — c'est ce qui
		# rend la contre-épreuve de bit-stabilité possible.
		"sprint": false,
		"speed": 0.0,
		"airborne": false,
		# Grenade en main = arme abaissée. La correspondance sémantique est exacte.
		"low_ready": _aiming_grenade,
		"trigger": _fire_hold_active(),
		"empty": _rig_empty,
		"cycle_time": _cadence_seconds(_rig_weapon),
		"yaw": deg_to_rad(_aim_yaw),
		"pitch": deg_to_rad(_aim_pitch),
	}


func _update_grenade_aim(_delta: float) -> void:
	# ⚠️ §8.152 (lot 3D-H) — LE CLIC DROIT A ÉTÉ RETIRÉ D'ICI, il sert maintenant à la VISÉE.
	# C'est la convention de tous les grands FPS (clic droit = épauler, G = grenade), et
	# ça ne coûte rien : `KEY_G` était DÉJÀ une liaison complète, le clic droit n'en était
	# qu'un doublon. Le pavé ci-dessus le disait lui-même : « le clic droit est à un doigt
	# du clic gauche » et dépensait des grenades par accident. Le libérer est donc AUSSI un
	# correctif, pas seulement un déplacement.
	var holding := Input.is_key_pressed(KEY_G) \
		or (Input.get_connected_joypads().size() > 0
			and Input.is_joy_button_pressed(0, JOY_BUTTON_X))
	# Une annulation (ÉCHAP ou re-tape de G) verrouille le maintien jusqu'à ce que la touche soit
	# VRAIMENT relâchée : sans ce verrou, garder G enfoncé après avoir annulé relancerait la visée
	# à la frame suivante et le geste d'annulation n'existerait pas.
	if _grenade_cancelled and not holding:
		_grenade_cancelled = false
	if _grenade_cancelled:
		holding = false

	# ╔═ §8.151 (2ter, CORRECTIF) — LE 3ᵉ CHEMIN D'ACTION PASSE PAR LA MÊME PORTE QUE LE TIR ════════╗
	# ║ Cf. le pavé de `_ui_blocks_actions()` : ce chemin-ci n'avait AUCUNE porte de panneau, et       ║
	# ║ c'était le seul des trois à DÉPENSER une ressource — la moitié du stock de grenades.           ║
	# ║ ⚠️ ON ANNULE, ON NE MET PAS EN PAUSE. Un panneau qui s'ouvre PENDANT la visée (le CHOIX        ║
	# ║ D'ARME s'ouvre tout seul, en plein combat) doit RANGER la grenade : la geler pour la rendre    ║
	# ║ à la fermeture relâcherait, des secondes plus tard, un lancer que le joueur ne vise plus. Le   ║
	# ║ verrou `_grenade_cancelled` finit le travail — rien ne se réarme tant que la touche n'a pas    ║
	# ║ été VRAIMENT relâchée, exactement comme après une annulation à ÉCHAP.                          ║
	# ║ ⚠️ ET ANNULER NE COÛTE RIEN : aucune grenade n'est consommée, `_throw_queued` reste vide.      ║
	# ║ ⚠️ §8.151 (2quinquies) — ELLE GARDE LA PORTE OFFENSIVE, LE SÉLECTEUR COMPRIS, là où le pas,    ║
	# ║ la posture, le rechargement et le pansement viennent d'en sortir. Ce n'est pas une            ║
	# ║ exception : viser demande LA SOURIS, et les trois panneaux la relâchent. Sous le              ║
	# ║ sélecteur, lacet et site sont GELÉS (`_input` n'écoute la souris que CAPTÉE) : le décalque    ║
	# ║ promettrait un point que le joueur ne peut plus corriger. Elle suit le TIR, mot pour          ║
	# ║ mot — et c'est déjà ce que les deux chemins de tir faisaient avant cette vague.               ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	if _ui_blocks_actions():
		if _aiming_grenade:
			_cancel_grenade()
		elif holding:
			_grenade_cancelled = true
		return

	if holding and not _aiming_grenade:
		if _pred_stance != "up":
			holding = false            # on ne lance pas accroupi (la sim le refuse aussi)
		elif int(_my("grenades")) <= 0:
			_refuse_grenade()
			holding = false
		else:
			_aiming_grenade = true
			_viewmodel.set_grenade_aim(true)

	if _aiming_grenade and holding:
		var point: Dictionary = _world.grenade_aim_point(_aim_yaw, _aim_pitch, _grenade_limit_x())
		_grenade_point = float(point.get("x", 0.0))
		_world.show_grenade_aim(true, _grenade_point, float(point.get("z", 0.0)),
			bool(point.get("valid", true)))
		return

	if _aiming_grenade and not holding:
		_aiming_grenade = false
		_world.show_grenade_aim(false)
		_viewmodel.set_grenade_aim(false)
		if not _grenade_cancelled:
			# ⚠️ LE POINT PART TEL QU'IL ÉTAIT À CET INSTANT, quantifié au décimètre (contrat §2).
			# C'est l'exacte transposition de la leçon du TIR FIGÉ AU CLIC (§6.3 du rapport de
			# pivot) : ce que le joueur voyait au moment de son geste est ce qui part.
			_throw_queued = {"target_x": snappedf(_grenade_point, 0.1)}


# La borne de visée, servie par le SERVEUR (`rules.grenade.target_margin_m` + les cotes de l'arène).
# ⚠️ Le client ne la recalcule pas depuis ses propres constantes : il la DÉRIVE des mêmes cotes que
# celles que le serveur clampe. Deux arithmétiques séparées finiraient par se contredire d'un
# décimètre, et le décalque promettrait un point que le serveur ramènerait ailleurs.
func _grenade_limit_x() -> float:
	var grenade: Dictionary = _rules.get("grenade", {})
	var geometry: Dictionary = _rules.get("geometry", {})
	var positions := int(geometry.get("positions", _positions))
	var spacing := float(geometry.get("position_spacing", Geo.POSITION_SPACING))
	var margin := float(grenade.get("target_margin_m", 1.5))
	return float(positions - 1) * spacing * 0.5 + margin


# LE REFUS, JAMAIS SILENCIEUX (§B.1.3). Une case qui tremble deux frames et un son sec : le joueur
# doit savoir que le jeu l'a ENTENDU et a dit non — sinon il croit à une touche qui ne répond pas,
# et c'est exactement le symptôme qu'il a rapporté pour la flèche bas (§6.2 du rapport de pivot).
func _refuse_grenade() -> void:
	if _grenade_refuse > 0.0:
		return
	_grenade_refuse = 0.18
	AudioManager.play_sfx("trench_refused", -4.0)


# ANNULER : on range la grenade, on éteint le décalque, et on VERROUILLE jusqu'au vrai relâchement
# de la touche. Sans le verrou, garder G enfoncé après ÉCHAP relancerait la visée à la frame
# suivante — l'annulation n'existerait tout simplement pas pour qui n'a pas les doigts rapides.
func _cancel_grenade() -> void:
	_aiming_grenade = false
	_grenade_cancelled = true
	_world.show_grenade_aim(false)
	_viewmodel.set_grenade_aim(false)


func _log_input(payload: Dictionary) -> void:
	var server_pos = _player_of(_latest(), _my_slot).get("pos")
	var line := "move %+d · pos %d (serveur %s) · %s · verrou %.2f s\naim %.1f / %.1f" \
		% [int(payload.get("move", 0)), _pred_pos,
			"?" if server_pos == null else str(int(server_pos)), _pred_stance,
			maxf(0.0, _pred_move_ready - _clock), _aim_yaw, _aim_pitch]
	if _tuning != null and _tuning.visible:
		_tuning.set_journal(line)
	if _diag != null and _diag.visible:
		# ╔═ ⚠️⚠️ CE JOURNAL ÉTAIT AVEUGLE DANS LE SEUL MODE OÙ LE DÉFAUT SE PRODUIT ════════════╗
		# ║ Il a été écrit au §8.140 précisément pour « les déplacements ne fonctionnent pas » —  ║
		# ║ un symptôme jamais reproduit. Mais il ne s'affichait QUE dans le panneau F10, lui-même ║
		# ║ réservé à l'ENTRAÎNEMENT… et le défaut, lui, n'apparaît QU'EN COMPÉTITION. L'outil de  ║
		# ║ diagnostic était donc éteint exactement là où il servait, et personne ne l'a vu parce  ║
		# ║ que les deux verrous sont dans deux fichiers différents.                               ║
		# ║ ⚠️ On ne lève PAS le verrou du panneau F10 pour autant : lui relâche la souris et       ║
		# ║ clouerait le joueur sur place pendant qu'un adversaire continue de jouer (§8.140). Ce   ║
		# ║ bandeau-ci est en LECTURE SEULE — aucun curseur, aucune capture de souris touchée. Il   ║
		# ║ ne peut rien offrir à personne, donc il n'a aucune raison d'être interdit en duel.      ║
		# ╚═══════════════════════════════════════════════════════════════════════════════════════╝
		_diag.text = "F3 · slot %d · %s\n%s\netat serveur : %s · phase %s" \
			% [_my_slot, "ENTRAINEMENT" if _training else "COMPETITION", line,
				"AUCUN (le serveur ne simule pas encore)" if _buffer.is_empty()
					else "%d recu(s)" % _buffer.size(),
				str(_latest().get("phase", "—"))]


# L'habillage 2D (brume, braises) est posé sur une ordonnée d'écran, pas dans le monde : il lui
# faut donc savoir où la caméra a emmené l'horizon. On ne la recalcule pas — on demande au monde 3D
# de PROJETER la direction de site nul, ce qui tient compte du FOV, de l'aspect et du suivi de
# visée d'un seul coup. Une seule source, comme partout ailleurs dans ce chantier.
func _track_horizon() -> void:
	if _ambient == null or _world == null or size.y <= 0.0:
		return
	_ambient.set_horizon_ratio(clampf(_world.project_aim(_aim_yaw, 0.0).y / size.y, -0.5, 1.5))


# Reste-t-il de la place sous les 10 msg/s du serveur pour un envoi ANTICIPÉ ?
# ⚠️ On compte les envois de la DERNIÈRE SECONDE GLISSANTE, pas depuis un compteur remis à zéro :
# c'est la seule mesure qui corresponde à ce que le serveur, lui, observe. On s'arrête à 9 et non à
# 10 — la marge d'un message absorbe la gigue, exactement comme les 0,105 s en absorbent déjà une.
const SEND_BUDGET_PER_SECOND := 9


func _prune_send_window() -> void:
	while not _sent_at.is_empty() and _clock - float(_sent_at[0]) > 1.0:
		_sent_at.pop_front()


func _send_budget_left() -> bool:
	_prune_send_window()
	return _sent_at.size() < SEND_BUDGET_PER_SECOND


func _decay(delta: float) -> void:
	_fire_fx_mute = maxf(0.0, _fire_fx_mute - delta)
	_grenade_refuse = maxf(0.0, _grenade_refuse - delta)
	_fire_refuse = maxf(0.0, _fire_refuse - delta)
	_hitmarker = maxf(0.0, _hitmarker - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	_enemy_hit = maxf(0.0, _enemy_hit - delta * 3.0)
	# §8.151 : `_recoil` (décru linéairement ici même) a disparu — le recul vit dans les ressorts
	# du viewmodel et de `_step_feel`, qui portent leur propre retour.


# =================================================================================================
# INTERPOLATION + VIEW-MODEL (150 ms derrière le serveur, §2.4)
# =================================================================================================
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _latest() -> Dictionary:
	return _buffer[-1]["data"] if not _buffer.is_empty() else {}


func _player_of(state: Dictionary, slot: int) -> Dictionary:
	for player in state.get("players", []):
		if int(player.get("slot", 0)) == slot:
			return player
	return {}


func _my(field: String):
	var me := _player_of(_latest(), _my_slot)
	return me.get(field, 0)


func _render_pair() -> Array:
	var target := _now() - RENDER_DELAY
	if _buffer.size() < 2:
		return [_latest(), _latest(), 1.0]
	for i in range(_buffer.size() - 1, 0, -1):
		if _buffer[i - 1]["at"] <= target:
			var a = _buffer[i - 1]
			var b = _buffer[i]
			var span: float = maxf(0.001, b["at"] - a["at"])
			return [a["data"], b["data"], clampf((target - a["at"]) / span, 0.0, 1.0)]
	return [_buffer[0]["data"], _buffer[0]["data"], 1.0]


func _refresh_view(delta: float) -> void:
	# ╔═ §8.151 (2ter, CORRECTIF) — LA CROIX SE POSE AVANT TOUTE GARDE D'ÉTAT ════════════════════╗
	# ║ 🩸 CE QUI N'ALLAIT PAS, ET LA DURÉE EXACTE DE LA FENÊTRE. La pose du réticule vivait 840   ║
	# ║ lignes plus bas, DERRIÈRE le `return` ci-dessous : tant qu'aucun `trench_state` n'était     ║
	# ║ arrivé, la croix gardait la position d'un `Control` neuf — (0, 0), c'est-à-dire le coin     ║
	# ║ HAUT-GAUCHE de l'écran. Pendant ce temps `_process` appelait `_world.set_aim()` sans        ║
	# ║ condition : la CAMÉRA suivait la souris, la croix NON. Le joueur regardait autour de lui    ║
	# ║ avec un viseur cloué dans le coin.                                                          ║
	# ║ ⚠️ ET LA FENÊTRE N'EST PAS UNE FRAME : `trench_runner.py` attend les DEUX humains jusqu'à   ║
	# ║ `CONNECT_TIMEOUT_S = 20 s` avant de créer l'état initial, et `_init_payload` envoie         ║
	# ║ « state: None » tant que la sim n'a pas démarré. Le PREMIER connecté d'un duel classé       ║
	# ║ voyait donc le coin de son écran jusqu'à VINGT SECONDES.                                     ║
	# ║ La croix ne dépend d'AUCUN état serveur — elle est la projection de la visée, qui est une   ║
	# ║ grandeur purement locale. Elle se pose donc AVANT la garde, et elle s'y pose à chaque       ║
	# ║ frame, état ou pas. (Section 0 de `probe_trench_hud` : registre ET tampon vides.)           ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	_place_reticle()
	var latest := _latest()
	if latest.is_empty():
		return
	var pair := _render_pair()
	var s0: Dictionary = pair[0]
	var s1: Dictionary = pair[1]
	var alpha: float = pair[2]
	var render_tick := lerpf(float(s0.get("tick", 0)), float(s1.get("tick", 0)), alpha)
	var their_slot := 3 - _my_slot

	# --- L'ADVERSAIRE : visible seulement si le serveur nous donne sa position (§1.6) ---
	var they0 := _player_of(s0, their_slot)
	var they1 := _player_of(s1, their_slot)
	var visible := they1.get("pos") != null
	if visible:
		var to_pos := float(they1.get("pos"))
		var from_pos: float = float(they0.get("pos")) if they0.get("pos") != null else to_pos
		_last_seen_enemy_pos = lerpf(from_pos, to_pos, alpha)

	# --- Projectiles : traçantes dans LEUR VRAIE DIRECTION, marqueurs de grenade toujours visibles ---
	var tracers: Array = []
	var grenades: Array = []
	var markers: Array = []
	# Le tick de l'état LU — c'est lui qui date les départs (cf. le pavé de la garde de rafale).
	var state_tick := int(s1.get("tick", 0))
	for proj in s1.get("projectiles", []):
		var launch := float(proj.get("launch_tick", 0))
		var impact := float(proj.get("impact_tick", launch + 1))
		var t := clampf((render_tick - launch) / maxf(1.0, impact - launch), 0.0, 1.0)
		var mine := int(proj.get("owner_slot", 1)) == _my_slot
		if str(proj.get("kind", "")) == "grenade":
			# ⚠️ `target_x` EN MÈTRES (§8.141) — le point exact, pas l'abscisse d'une case. C'est
			# la même valeur que le serveur utilise pour ses dégâts : le marqueur que la cible voit
			# et le cercle qui la blesse ne peuvent donc pas diverger.
			var impact_x := float(proj.get("target_x", 0.0))
			grenades.append({"from_pos": int(proj.get("from_pos", 2)),
				"target_x": impact_x, "mine": mine, "t": t})
			markers.append({"target_x": impact_x, "on_my_side": not mine,
				"eta": clampf((impact - render_tick) / maxf(1.0, impact - launch), 0.0, 1.0)})
		else:
			# ╔═ §8.151 (2bis, correctif) — UNE BALLE QUI N'EST PAS ENCORE PARTIE NE SE DESSINE PAS ═╗
			# ║ ⚠️ LE DEMI-CORRECTIF DE L'EFFET MITRAILLETTE, SOLDÉ ICI. Le son, la lueur de canon et  ║
			# ║ le cran de recul d'une rafale PULSAIENT bien par projectile (crans calés sur les       ║
			# ║ `launch_tick`) — mais les TRAÇANTES, elles, apparaissaient toutes au tick du clic. La   ║
			# ║ raison : `_fire_burst` fait naître les 3 balles du FRELON AU MÊME TICK (`_spawn` les    ║
			# ║ ajoute immédiatement à `state.projectiles`) et ne diffère que leur `launch_tick`        ║
			# ║ (T, T+2, T+4). L'état du tick T porte donc DÉJÀ toute la rafale, et cette boucle, sans  ║
			# ║ garde, produisait `t = clamp(négatif) = 0` pour les balles à venir : trois segments     ║
			# ║ VISIBLES au canon d'en face (0,4 d'échelle — la garde de dégagement `MUZZLE_CLEAR` ne   ║
			# ║ couvre que les MIENNES). La victime entendait 3 détonations sur 200 ms et voyait les    ║
			# ║ 3 balles dès la première frame : la présentation se contredisait elle-même.            ║
			# ║                                                                                        ║
			# ║ ⚠️⚠️ LA RÉFÉRENCE EST LE TICK DE L'ÉTAT, **PAS** `render_tick` — ET C'EST MESURÉ. Le    ║
			# ║ télégraphe laser, trois blocs plus bas, compare bien à `render_tick` : ça marche pour   ║
			# ║ LUI parce qu'un laser dure 10 ticks. Une balle, non : `flight_ticks` vaut 1 pour les    ║
			# ║ QUATRE armes, et la sim RETIRE le projectile au tick de son impact (`launch + 1`). Un   ║
			# ║ projectile n'est donc présent que dans des états dont le tick est ≤ à son `launch_tick`,║
			# ║ alors que `render_tick` vit UN TICK EN ARRIÈRE du plus récent (RENDER_DELAY) : il       ║
			# ║ n'atteint JAMAIS `launch` tant que la balle est encore dans la liste. Filtrer sur       ║
			# ║ `launch > render_tick` — la lettre du remède — n'aurait pas retardé les balles 2 et 3 : ║
			# ║ il aurait effacé TOUTES les traçantes adverses, la première comprise. On date donc le   ║
			# ║ départ avec l'horloge qui le décide : le tick de l'état que le serveur vient d'écrire.  ║
			# ║ Conséquence exacte : la balle 1 ne bouge pas d'une frame (elle était déjà rendue à      ║
			# ║ l'état T), les balles 2 et 3 se montrent aux états T+2 et T+4 — une traçante par        ║
			# ║ détonation, à 100 ms d'écart, comme au canon.                                          ║
			# ╚════════════════════════════════════════════════════════════════════════════════════════╝
			if int(launch) > state_tick:
				continue
			tracers.append({"from_pos": int(proj.get("from_pos", 2)), "mine": mine, "t": t,
				"yaw": float(proj.get("aim_yaw", 0.0)),
				"pitch": float(proj.get("aim_pitch", 0.0))})

	# --- Laser CONDOR : rendu DÈS l'événement serveur, dans la direction réelle du tireur ---
	var laser := {}
	# ⚠️ LE RAYON PRÉDIT, tant que l'état serveur n'a pas encore le mien. Il est ÉCRASÉ dès
	# que le serveur en annonce un (la boucle ci-dessous réécrit `laser`), et il expire tout
	# seul. C'est ce qui donne au clic un accusé de réception IMMÉDIAT sans rien inventer :
	# le rayon est exactement ce que le clic a produit côté serveur.
	if _clock < _laser_pred_until:
		laser = {"active": true, "mine": true, "from_pos": _laser_pred_pos,
			"yaw": _laser_pred_aim.x, "pitch": _laser_pred_aim.y}
	var enemy_laser_now := false
	# Le tick auquel la balle adverse PARTIRA — c'est lui qui borne l'avertissement sonore.
	var enemy_laser_tick := 0.0
	for player in s1.get("players", []):
		if int(player.get("laser_fire_tick", 0)) > int(render_tick):
			var mine := int(player.get("slot", 0)) == _my_slot
			if not mine:
				enemy_laser_now = true
				enemy_laser_tick = float(player.get("laser_fire_tick", 0))
			# Le mien suit ma visée en direct ; le SIEN suit la direction annoncée par son
			# événement `laser` — et il est forcément DEBOUT pour lasériser, donc jamais masqué.
			laser = {"active": true, "mine": mine,
				"from_pos": int(player.get("pos", 2)) if player.get("pos") != null
					else _enemy_laser_pos,
				"yaw": _aim_yaw if mine else _enemy_laser_yaw,
				"pitch": _aim_pitch if mine else _enemy_laser_pitch}
	# ╔═ §8.151 (2bis) — LE TÉLÉGRAPHE CONDOR S'ENTEND (§3.6) : « le danger annoncé doit           ═╗
	# ║ S'ENTENDRE, pas seulement se voir ». Le son se cale sur le MÊME signal que le rayon rendu    ║
	# ║ (`laser_fire_tick > render_tick`, lu dans l'état) — jamais une minuterie locale. FRONT       ║
	# ║ MONTANT + verrou : UNE lecture par visée, relâchée quand le rayon s'éteint (tir parti,       ║
	# ║ annulation, accroupi) — une nouvelle visée ré-avertit. ⚠️ ADVERSE SEULEMENT : c'est un       ║
	# ║ avertissement de CIBLE — MON propre laser ne me menace pas, il ne bipe pas (et le suivi est  ║
	# ║ fait PAR CAMP : mon télégraphe à moi ne masque pas l'alerte du sien).                        ║
	# ║ ⚠️ §8.151 (2bis, correctif) — LA FENÊTRE ANNONCÉE EST CELLE DE LA SIM, PAS CELLE DU FICHIER.  ║
	# ║ L'alerte était jouée en entier, à sa durée d'asset (0,620 s), pour annoncer une fenêtre de   ║
	# ║ `laser_lead_ticks / tick_rate` (0,500 s aujourd'hui, mais ⚙ AMENDABLE au registre) : elle    ║
	# ║ bourdonnait encore 120 ms APRÈS le départ de la balle, et un simple réglage serveur l'aurait ║
	# ║ fait déborder de 370 ms (5 ticks) ou se taire 400 ms trop tôt (20 ticks). L'oreille annonçait║
	# ║ une fenêtre qui n'était pas celle du danger — le §1.9 l'interdit à l'œil, il n'y a aucune    ║
	# ║ raison de le tolérer à l'oreille. Désormais la fenêtre est LUE dans l'état : le serveur      ║
	# ║ diffuse `laser_fire_tick`, le tick où la balle part ; il reste donc                          ║
	# ║ `(laser_fire_tick − render_tick) / tick_rate` — le temps de danger RÉEL, latence comprise,   ║
	# ║ meilleur encore que le barème nominal. Le bourdonnement est ÉTIRÉ/COMPRIMÉ sur cette fenêtre ║
	# ║ (pitch = durée du fichier ÷ fenêtre, borné par le manager) et il est COUPÉ à l'extinction du ║
	# ║ rayon : il ne peut plus survivre au tir, ni s'arrêter loin avant lui.                        ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	if enemy_laser_now and not _laser_warn_latch:
		var window: float = maxf(0.0, (enemy_laser_tick - render_tick) / _tick_rate)
		_laser_warn_token = AudioManager.play_sfx_tracked("trench_laser_warn", LASER_WARN_DB,
			_laser_warn_pitch(window))
	elif _laser_warn_latch and not enemy_laser_now:
		# Le rayon s'éteint (tir parti, annulation, accroupi) : le danger est passé, l'alerte se
		# tait AVEC lui. Jeton périmé (voix reprise entre temps) → l'arrêt ne fait rien.
		AudioManager.stop_sfx(_laser_warn_token)
		_laser_warn_token = -1
	_laser_warn_latch = enemy_laser_now

	# `aiming` et `dead` pilotent la MACHINE À FRAMES du sprite peint (§8.138). Les deux se LISENT
	# dans l'état déjà reçu — `aiming` est le drapeau de lisibilité du §8.137, `dead` se déduit des
	# PV. Aucun champ n'a été ajouté au protocole pour ce lot.
	_world.render_world({
		"enemy": {"visible": visible, "pos": _last_seen_enemy_pos, "hit": _enemy_hit,
			"aiming": bool(they1.get("aiming", false)),
			"dead": float(they1.get("hp", 1)) <= 0.0},
		"tracers": tracers, "grenades": grenades, "markers": markers, "laser": laser,
	})
	_refresh_hud(latest, _player_of(s1, _my_slot), they1, render_tick)


# =================================================================================================
# COUCHE 4 — LE HUD (LOT D)
# =================================================================================================
func _make_font(tabular := false) -> Font:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed",
		"Arial Narrow", "Arial"])
	base.font_weight = 700
	if not tabular:
		return base
	# CHIFFRES TABULAIRES (`tnum`) — le compteur de munitions et le chrono changent 10 fois par
	# seconde : sans chasse fixe, ils tressautent. Même recette que `countdown_label.gd` (§8.134) ;
	# si la police système ne porte pas la fonctionnalité, la ligne est un no-op silencieux, d'où
	# les largeurs minimales réservées plus bas.
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	if ts != null:
		fv.opentype_features = {ts.name_to_tag("tnum"): 1}
	return fv


func _label(text: String, size: int, color: Color = COL_TEXT, tabular := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _make_font(tabular))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ⚠️ DEUX PIÈGES D'ANCRAGE, tous deux vus en CAPTURE sur ce dépôt (invisibles au boot headless) :
#   1. `node.anchors_preset = X` est une commodité d'ÉDITEUR — assignée en code elle ne s'applique
#      pas : la MÉTHODE `set_anchors_preset()` fait foi ;
#   2. `position` est relatif au PARENT (elle RECALCULE les offsets) — pour placer relativement à
#      l'ANCRE, ce sont `offset_left/offset_top` qu'il faut poser.
func _anchored(node: Control, preset: int, off: Vector2, box := Vector2.ZERO) -> void:
	node.set_anchors_preset(preset)
	node.offset_left = off.x
	node.offset_top = off.y
	node.offset_right = off.x + box.x
	node.offset_bottom = off.y + box.y


func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	_build_damage_feedback()
	_build_vitals()
	_build_center()
	_build_ammo()
	_build_item_slots()
	_build_damage_numbers()
	_build_reticle()
	_build_help_panel()
	_build_choice_panel()
	_build_abandon_overlay()


# Flinch directionnel à l'encaissement + vignette rouge sous 25 PV (§5.5, refondu §8.151).
func _build_damage_feedback() -> void:
	# ╔═ §8.151 — L'OVERLAY DE FLINCH, DÉDIÉ ═════════════════════════════════════════════════════╗
	# ║ RE-FONDATION du flash plat (`color.a = _hurt_flash * 0.45`, sans direction — `_hurt_dir`   ║
	# ║ était calculé depuis §5.5 et JAMAIS lu) : le pouls et le côté vivent dans un shader à part ║
	# ║ (`trench_flinch.gdshader`), monté ICI, premier enfant du HUD — donc SOUS les éléments du   ║
	# ║ HUD et AU-DESSUS de l'étalonnage (`_grade` précède `_hud` dans l'ordre des couches). On ne ║
	# ║ touche PAS à `trench_grade.gdshader` : propriété exclusive du LOT C, zéro couture.         ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	_hurt_overlay = ColorRect.new()
	_hurt_overlay.color = Color(1, 1, 1, 1)      # le shader décide de tout, la teinte vit chez lui
	var flinch_mat := ShaderMaterial.new()
	flinch_mat.shader = FlinchShader
	_hurt_overlay.material = flinch_mat
	_hurt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠️ 8ᵉ récidive ÉVITÉE de « un Control créé par code garde size = (0,0) » (§8.140.3) : taille
	# POSÉE depuis le viewport + reconnexion `size_changed`. Ancres ÉGALES (TOP_LEFT) et non
	# FULL_RECT : des ancres opposées inégales + une taille posée à la main, c'est l'avertissement
	# « non-equal opposite anchors will have their size overridden » — l'autre moitié du piège.
	_hurt_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud.add_child(_hurt_overlay)
	_fit_hurt_overlay()
	get_viewport().size_changed.connect(_fit_hurt_overlay)

	_low_hp_vignette = ColorRect.new()
	_low_hp_vignette.color = Color(0.45, 0.05, 0.05, 0.0)
	_low_hp_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_hp_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_low_hp_vignette)


func _fit_hurt_overlay() -> void:
	if _hurt_overlay != null:
		_hurt_overlay.size = get_viewport_rect().size


# PV haut-gauche (barre + valeur) — §6.
func _build_vitals() -> void:
	var mine := _label(str(AuthManager.username), 15, COL_ACCENT)
	_hud.add_child(mine)
	_anchored(mine, Control.PRESET_TOP_LEFT, Vector2(26, 20), Vector2(280, 20))

	var back := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.55)
	sb.border_color = COL_MUTED
	sb.set_border_width_all(1)
	back.add_theme_stylebox_override("panel", sb)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(back)
	_anchored(back, Control.PRESET_TOP_LEFT, Vector2(26, 44), Vector2(240, 18))
	_my_hp_fill = ColorRect.new()
	_my_hp_fill.color = COL_ACCENT
	_my_hp_fill.position = Vector2(1, 1)
	_my_hp_fill.size = Vector2(238, 16)
	back.add_child(_my_hp_fill)
	_my_hp_label = _label("100", 15, COL_TEXT, true)
	_hud.add_child(_my_hp_label)
	_anchored(_my_hp_label, Control.PRESET_TOP_LEFT, Vector2(274, 43), Vector2(60, 20))

	# L'adversaire : nom + une barre FINE (l'information compte, pas la place qu'elle prend).
	_their_name = _label("", 14, COL_MUTED)
	_hud.add_child(_their_name)
	_anchored(_their_name, Control.PRESET_TOP_LEFT, Vector2(26, 72), Vector2(360, 18))
	var their_back := Panel.new()
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0.45)
	sb2.border_color = Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.55)
	sb2.set_border_width_all(1)
	their_back.add_theme_stylebox_override("panel", sb2)
	their_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(their_back)
	_anchored(their_back, Control.PRESET_TOP_LEFT, Vector2(26, 94), Vector2(180, 9))
	_their_hp_fill = ColorRect.new()
	_their_hp_fill.color = COL_DANGER
	_their_hp_fill.position = Vector2(1, 1)
	_their_hp_fill.size = Vector2(178, 7)
	their_back.add_child(_their_hp_fill)


# Manches / score + chrono haut-centre — §6.
func _build_center() -> void:
	_timer_label = _label("—", 30, COL_TEXT, true)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_timer_label)
	_anchored(_timer_label, Control.PRESET_CENTER_TOP, Vector2(-80, 16), Vector2(160, 34))

	_round_label = _label("", 13, COL_MUTED)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_round_label)
	_anchored(_round_label, Control.PRESET_CENTER_TOP, Vector2(-110, 52), Vector2(220, 18))

	_score_label = _label("", 17, COL_GOLD, true)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_score_label)
	_anchored(_score_label, Control.PRESET_CENTER_TOP, Vector2(-110, 72), Vector2(220, 22))

	_banner = _label("", 34, COL_ACCENT)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_hud.add_child(_banner)
	_anchored(_banner, Control.PRESET_CENTER, Vector2(-260, -190), Vector2(520, 46))

	_waiting_label = _label(tr("TRENCH_WAITING_OPPONENT"), 20, COL_MUTED)
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_waiting_label)
	_anchored(_waiting_label, Control.PRESET_CENTER, Vector2(-220, -20), Vector2(440, 30))

	_conn_banner = _label(tr("NET_CONNECTION_LOST"), 19, COL_DANGER)
	_conn_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_conn_banner.visible = false
	_hud.add_child(_conn_banner)
	_anchored(_conn_banner, Control.PRESET_CENTER_TOP, Vector2(-220, 108), Vector2(440, 26))

	# LE BANDEAU DE DÉSYNCHRONISATION — rouge, permanent, au centre. Il ne s'efface jamais tant que
	# le duel dure : ce n'est pas une alerte passagère, c'est « cette partie ne veut rien dire ».
	_geometry_banner = _label("", 18, COL_DANGER)
	_geometry_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_geometry_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_geometry_banner.visible = false
	_hud.add_child(_geometry_banner)
	_anchored(_geometry_banner, Control.PRESET_CENTER_TOP, Vector2(-420, 140), Vector2(840, 60))

	# Le rappel de la touche F10. Il ne s'allume qu'en ENTRAÎNEMENT, quand `_on_init` l'a confirmé :
	# annoncer un raccourci qui ne répond pas serait pire que de ne rien annoncer.
	_tune_hint = _label(tr("TRENCH_TUNE_HOTKEY"), 13, COL_MUTED)
	_tune_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tune_hint.visible = false
	_hud.add_child(_tune_hint)
	_anchored(_tune_hint, Control.PRESET_TOP_RIGHT, Vector2(-320, 22), Vector2(296, 20))

	# LE BANDEAU DE DIAGNOSTIC (F3) — éteint par défaut, disponible dans les DEUX modes.
	_diag = _label("", 13, COL_GOLD)
	_diag.visible = false
	_hud.add_child(_diag)
	_anchored(_diag, Control.PRESET_TOP_LEFT, Vector2(26, 118), Vector2(620, 90))


# Munitions bas-droite (« 06/15 », chiffres tabulaires) + arme courante — §6.
func _build_ammo() -> void:
	_ammo_label = _label("", 40, COL_TEXT, true)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_ammo_label)
	_anchored(_ammo_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -84), Vector2(230, 46))

	_reload_label = _label("", 14, COL_GOLD)
	_reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_reload_label)
	_anchored(_reload_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -38), Vector2(230, 20))

	_weapon_label = _label("", 19, COL_TEXT)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_weapon_label)
	_anchored(_weapon_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -112), Vector2(230, 24))

	_progress_label = _label("", 12, COL_MUTED)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_progress_label)
	_anchored(_progress_label, Control.PRESET_BOTTOM_RIGHT, Vector2(-260, -134), Vector2(230, 18))


# Cases d'objets bas-centre : 1 GRENADE (stock) · 2 BANDAGE (état) — §6.
func _build_item_slots() -> void:
	_slot_grenade = _label("", 15, COL_GOLD)
	_slot_grenade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_slot_grenade)
	_anchored(_slot_grenade, Control.PRESET_CENTER_BOTTOM, Vector2(-190, -52), Vector2(180, 22))

	_slot_bandage = _label("", 15, COL_MUTED)
	_slot_bandage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(_slot_bandage)
	_anchored(_slot_bandage, Control.PRESET_CENTER_BOTTOM, Vector2(10, -52), Vector2(180, 22))


# RÉTICULE — dessiné à la MAIN parce qu'il doit vivre : son écartement montre la dispersion de
# l'arme, et il passe au rouge chargeur vide (§6). Il suit la VISÉE, pas le centre de l'écran :
# c'est ce découplage qui permet des poses de caméra fixes avec une visée libre (§1.1).
func _build_reticle() -> void:
	_reticle = Control.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_reticle.size = Vector2(80, 80)
	# ⚠️ POSE INITIALE — un `Control` créé par code naît à (0, 0), c'est-à-dire dans le COIN
	# HAUT-GAUCHE, et il y reste jusqu'à ce que quelqu'un le déplace. `_place_reticle()` s'en
	# charge dès la première frame de `_process`, mais la frame qui SÉPARE `_ready()` du premier
	# `_process` est peinte, elle aussi : on ne la laisse pas montrer le coin. La taille vient du
	# VIEWPORT et non de `size` — les ancres du duel ne sont résolues qu'à la passe de mise en page
	# suivante, `size` vaut donc encore (0, 0) ici (8ᵉ récidive de §8.140.3, évitée).
	_reticle.position = get_viewport_rect().size * 0.5 - _reticle.size * 0.5
	_hud.add_child(_reticle)
	_reticle.draw.connect(_draw_reticle)


# ╔═ LA POSE DE LA CROIX — SON SEUL POINT D'ÉCRITURE, ET IL NE DÉPEND D'AUCUN ÉTAT SERVEUR ══════╗
# ║ Type ANNOTÉ explicitement : `_world` est typé `Control`, l'appel est donc « non sûr » aux     ║
# ║ yeux de l'analyseur et rend un Variant — sans annotation, `:=` ne peut rien inférer.          ║
# ║ ╔═ §8.151 — LE KICK DE RÉTICULE EST MORT, ET IL NE REVIENDRA PAS ═══════════════════════════╗ ║
# ║ ║ Ici vivait `aim_screen.y -= _recoil * 10` : dix pixels de croix déplacée SANS que le monde ║ ║
# ║ ║ bouge — pendant chaque recul, le réticule montrait un point que la balle ne visait pas.    ║ ║
# ║ ║ C'est le mensonge exact que §8.141.6 interdit. Le seul décalage admis est `_shake_px`,     ║ ║
# ║ ║ parce qu'il est appliqué AUSSI aux couches du monde : monde + réticule ENSEMBLE.           ║ ║
# ║ ╚═══════════════════════════════════════════════════════════════════════════════════════════╝ ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _place_reticle() -> void:
	var aim_screen: Vector2 = _world.project_aim(_aim_yaw, _aim_pitch)
	_reticle.position = aim_screen - _reticle.size * 0.5 + _shake_px
	_reticle.queue_redraw()


# =================================================================================================
# §8.151 (VAGUE 2ter, §4bis.3) — LES DÉGÂTS FLOTTANTS
# =================================================================================================
# ╔═ CE QU'ILS PEUVENT DIRE, ET CE QU'ILS NE DIRONT JAMAIS ═══════════════════════════════════════╗
# ║ Un chiffre ne naît QUE dans la branche `hit` de `_on_duel_event` — c'est-à-dire sur un          ║
# ║ événement SERVEUR, la même source unique que le hitmarker (§5.5). Le client sait « j'ai tiré » ;║
# ║ il ne sait PAS « j'ai touché », et il ne sait surtout pas COMBIEN : les dégâts dépendent de la  ║
# ║ table angulaire, de la posture de la cible et de son bandage. Un chiffre prédit serait le pire  ║
# ║ des mensonges de HUD — celui qu'on croit sur parole parce qu'il est chiffré.                    ║
# ║ Une RAFALE place N balles → le serveur émet N événements `hit` → N chiffres, décalés            ║
# ║ latéralement pour rester lisibles (le décalage vient de `hash_noise` sur le compteur de         ║
# ║ naissances : déterministe, donc une capture rejouée rend le même pixel).                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _build_damage_numbers() -> void:
	for i in range(DAMAGE_POOL):
		var node := _label("", 22, COL_GOLD, true)
		node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		node.visible = false
		_hud.add_child(node)
		# ⚠️ TAILLE POSÉE, ancres en POINT : un Control créé par code garde `size = (0,0)` et son
		# texte serait alors centré sur une boîte vide, donc collé au coin. 8ᵉ récidive évitée.
		_anchored(node, Control.PRESET_TOP_LEFT, Vector2.ZERO, DAMAGE_BOX)
		_damage_pool.append(node)
		_damage_free.append(node)


# L'ÉCHELLE DISCRÈTE d'un coup — dégâts rapportés au `hp_max` du REGISTRE (jamais un 100 en dur, ni
# un barème d'arme recopié : le §4ter va justement rebattre les dégâts par balle). Bornée pour que
# la différence se LISE sans que le marqueur devienne un panneau : un coup à 5 % des PV rend 0,85,
# un coup à 30 % rend ~1,35.
func _damage_scale(damage: int) -> float:
	var hp_max: float = maxf(1.0, float(_rules.get("hp_max", 100)))
	return clampf(0.75 + float(maxi(0, damage)) / hp_max * 2.0, 0.75, 1.4)


func _spawn_damage_number(damage: int, fatal: bool) -> void:
	if damage <= 0 or _damage_pool.is_empty():
		return
	# RECYCLAGE, jamais d'allocation : une étiquette LIBRE si le pool en a une, sinon on reprend le
	# plus ANCIEN chiffre encore en vol (une rafale qui recouvre une rafale). Aucun `Label.new()` ne
	# peut naître ici — c'est la seule chose que ce chemin garantit vraiment à chaque frame.
	var node: Label = null
	if not _damage_free.is_empty():
		node = _damage_free.pop_back()
	else:
		var oldest: Dictionary = _damage_live.pop_front()
		node = oldest["node"]
	_damage_spawned += 1
	var entry := {
		"node": node,
		"born": _clock,                       # TEMPS DE SCÈNE — jamais l'horloge murale
		"from": _enemy_screen_point(),
		"jitter": Springs.hash_noise(float(_damage_spawned), DAMAGE_SEED) * DAMAGE_JITTER_PX,
	}
	_damage_live.append(entry)
	node.text = str(damage)
	node.add_theme_color_override("font_color", COL_DANGER if fatal else COL_GOLD)
	node.add_theme_font_size_override("font_size", 30 if fatal else 22)
	node.visible = true
	# ⚠️ PLACÉ TOUT DE SUITE, ET C'EST UN CORRECTIF, PAS UNE COMMODITÉ. Un événement serveur arrive
	# par le rappel réseau, à un instant quelconque du tour de boucle : rendre l'étiquette VISIBLE
	# sans la placer la laisse une frame entière à sa position d'origine — le coin haut-gauche de
	# l'écran (`_anchored(..., Vector2.ZERO, ...)`). C'est très exactement la famille de défauts que
	# ce dépôt n'attrape qu'EN CAPTURE, jamais au boot headless (§8.140.3). La sonde le voit parce
	# qu'elle lit la position AVANT le premier pas.
	_place_damage_number(entry, 0.0)


# ╔═ D'OÙ PART LE CHIFFRE : LA SILHOUETTE ADVERSE, PROJETÉE COMME LA VISÉE ═══════════════════════╗
# ║ On ne peut pas demander sa position écran au monde 3D (`trench_fp_world.gd` n'est pas ouvert    ║
# ║ dans cette étape et n'expose pas de projection de nœud). On la DÉRIVE donc des cotes            ║
# ║ partagées — `Geo.yaw_to`/`pitch_to` depuis MON œil vers le milieu de la bande VISIBLE de la     ║
# ║ silhouette — puis on projette avec `project_aim`, la fonction de la visée. Une direction        ║
# ║ projetée est un POINT : peu importe la distance choisie le long du rayon, le pixel est le même. ║
# ║ ⚠️ `_shake_px` est ajouté comme pour le réticule : monde et HUD encaissent LE MÊME vecteur.     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _enemy_screen_point() -> Vector2:
	var fallback := size * 0.5
	if _world == null:
		return fallback
	var eye: Vector3 = Geo.eye_position(_pred_pos, _pred_stance)
	var their_stance := str(_player_of(_latest(), 3 - _my_slot).get("stance", "up"))
	var band: Array = Geo.visible_band(eye, their_stance)
	# Accroupi (bande vide) : rien ne dépasse du parapet — on vise alors le haut de la silhouette
	# accroupie, qui est l'endroit où une grenade vient de le trouver.
	var y: float = ((float(band[0]) + float(band[1])) * 0.5) if band.size() >= 2 \
		else Geo.SILHOUETTE_TOP_DOWN
	var at := Vector3(Geo.position_x(int(round(_last_seen_enemy_pos))), y, Geo.far_soldier_z())
	var screen: Vector2 = _world.project_aim(Geo.yaw_to(eye, at), Geo.pitch_to(eye, at))
	return screen + _shake_px


# LE PAS DES CHIFFRES — monte + fondu sur DAMAGE_RISE_S, piloté par le TEMPS DE SCÈNE. Il tourne
# aussi après la fin de match : un chiffre figé en plein vol sur l'écran de résultat serait le même
# défaut de capture qu'un roulis resté penché.
func _step_damage_numbers() -> void:
	var still: Array = []
	for entry: Dictionary in _damage_live:
		var node: Label = entry["node"]
		var age: float = _clock - float(entry["born"])
		if age >= DAMAGE_RISE_S:
			node.visible = false
			_damage_free.append(node)      # l'étiquette RETOURNE au pool : l'invariant tient
			continue
		_place_damage_number(entry, clampf(age / DAMAGE_RISE_S, 0.0, 1.0))
		still.append(entry)
	_damage_live = still


# LA POSE D'UN CHIFFRE À L'INSTANT `t` (0 = naissance, 1 = fin de vie) — un seul endroit, appelé par
# la naissance ET par le pas : deux poses séparées finiraient par se contredire d'une frame.
func _place_damage_number(entry: Dictionary, t: float) -> void:
	var node: Label = entry["node"]
	var from: Vector2 = entry["from"]
	# Montée qui DÉCÉLÈRE (1−(1−t)²) : le chiffre jaillit puis se pose — un déplacement linéaire se
	# lit « ascenseur ». Le fondu, lui, ne mord que sur le dernier tiers.
	var rise: float = (1.0 - (1.0 - t) * (1.0 - t)) * DAMAGE_RISE_PX
	node.position = from + Vector2(float(entry["jitter"]), -rise) - DAMAGE_BOX * 0.5
	node.modulate.a = clampf((1.0 - t) / 0.35, 0.0, 1.0)


const RETICLE_GAP_PX := 6.0        # écartement MINIMAL — le trou central de lisibilité
const RETICLE_ARM_PX := 7.0        # longueur d'un trait de croix (arme ordinaire)
const RETICLE_REFUSE_PX := 4.0     # l'écart SUPPLÉMENTAIRE du claquement de refus (§8.141.9)

# ╔═ §8.151 (2ter §4bis.1, CORRECTIF) — CE QUI EST PEINT EST UNE VALEUR, PAS UNE DÉCISION ════════╗
# ║ 🩸🩸 CE QUI N'ALLAIT PAS, ET QUI A ÉTÉ MESURÉ. `_draw_reticle()` calculait son propre           ║
# ║ écartement (`var spread := _reticle_spread_px()`) puis peignait ; la sonde, elle, lisait        ║
# ║ `_reticle_spread_px()`. Les deux ne se rejoignaient QUE par cette ligne-là. Remplacée par une   ║
# ║ constante décorative (« spread := 12.0 »), la sonde restait INTÉGRALEMENT VERTE — 84 PASS /     ║
# ║ 0 FAIL — sur un réticule sans plus AUCUN lien avec `dispersion_deg` : la propriété phare du lot ║
# ║ n'était pas gardée, elle était seulement récitée par une fonction que le dessin n'était pas     ║
# ║ tenu d'appeler.                                                                                 ║
# ║ ⚠️ ET AUCUN HARNAIS NE PEUT RELIRE CE QU'UN `CanvasItem` A PEINT : sous `--headless` le rendu    ║
# ║ est un pilote muet, et Godot n'expose de toute façon aucune relecture des primitives soumises.  ║
# ║ Tant que le PINCEAU décide de quoi que ce soit, ce qu'il décide est invérifiable — par          ║
# ║ construction, pas par paresse de la sonde.                                                      ║
# ║ LA CORRECTION EST DONC STRUCTURELLE, et c'est la seule qui referme vraiment : la géométrie      ║
# ║ peinte devient une VALEUR (`_reticle_paint_list()`, transcription littérale des appels de       ║
# ║ dessin), et le pinceau n'est plus qu'un rejeu mécanique — pas un chiffre, pas un axe, pas une   ║
# ║ couleur à lui. La sonde mesure la LISTE (donc ce qui est peint) et AUDITE la source des deux    ║
# ║ fonctions de rejeu : aucun littéral numérique, aucun argument de dessin qui ne vienne de la     ║
# ║ commande. Le sabotage « le pinceau ignore la formule » n'a plus d'endroit où s'écrire.          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Les CLÉS d'une commande de peinture, et les deux seules primitives du réticule. Des noms, jamais
# des chiffres : ils voyagent jusqu'au pinceau, qui n'a rien d'autre à savoir.
const PAINT_KIND := "kind"
const PAINT_A := "a"
const PAINT_B := "b"
const PAINT_COLOR := "color"
const PAINT_WIDTH := "width"
const PAINT_RADIUS := "radius"
const PAINT_LINE := "line"
const PAINT_DOT := "dot"


# LA GÉOMÉTRIE PEINTE DU RÉTICULE, dans l'ordre où elle est soumise. Tout ce qui décide de quelque
# chose vit ICI, et rien de ce qui vit ici n'échappe à la sonde.
func _reticle_paint_list() -> Array:
	var latest := _latest()
	var me := _player_of(latest, _my_slot)
	var empty := int(me.get("ammo", 1)) <= 0 or int(me.get("reload_until_tick", 0)) > 0
	# ⚠️ LE REFUS DE TIR SE VOIT AUSSI ICI (§8.141.9) : le réticule claque en rouge et s'écarte de
	# 4 px. Sans lui, un clic refusé pour CADENCE — le cas de loin le plus fréquent — ne produirait
	# qu'un son sec, et le joueur croirait à une touche qui ne répond pas. C'est exactement le
	# symptôme « la flèche bas ne fonctionne pas » du §8.140.1, et il ne se reproduira pas ici.
	var color := COL_DANGER if (empty or _fire_refuse > 0.0) else COL_ACCENT
	var center := _reticle.size * 0.5
	var spread := _reticle_spread_px()
	# ╔═ §8.151 (2ter, §4bis.1) — LE CONDOR À 0° A SA PROPRE CROIX, ET C'EST SA PROMESSE ══════════╗
	# ║ Une arme dont le cône vaut ZÉRO ne peut pas se dire avec le même dessin qu'une arme qui       ║
	# ║ arrose : à écartement nul, quatre traits épais collés au centre bouchent précisément l'endroit║
	# ║ qu'on vise. On dessine donc une croix FINE (traits d'1 px, longs, et un point central plus     ║
	# ║ petit) — la lecture « ce coup part exactement là » sans un pixel de plus. Le test porte sur la ║
	# ║ DISPERSION LUE, jamais sur l'id « condor » : le jour où le registre donne 0° à une autre arme, ║
	# ║ elle héritera de la croix de précision sans qu'on rouvre ce fichier.                           ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
	var precise := _reticle_is_precise()
	var arm: float = (RETICLE_ARM_PX * 1.7) if precise else RETICLE_ARM_PX
	var thickness: float = 1.0 if precise else 2.0
	var list: Array = []
	for axis: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var start := center + axis * spread
		list.append({PAINT_KIND: PAINT_LINE, PAINT_A: start, PAINT_B: start + axis * arm,
			PAINT_COLOR: color, PAINT_WIDTH: thickness})
	list.append({PAINT_KIND: PAINT_DOT, PAINT_A: center,
		PAINT_RADIUS: 1.0 if precise else 1.5, PAINT_COLOR: color})
	# HITMARKER — quatre traits en croix d'André, uniquement sur touche CONFIRMÉE par le serveur.
	# §8.151 (2ter, §4bis.2) : le KILL est ROUGE et plus long, et la longueur du trait suit les
	# dégâts RÉELS du coup (`_hitmarker_scale`, posée par l'événement). Rien ici ne s'allume tout
	# seul : `_hitmarker` n'est écrit que dans la branche `hit` de `_on_duel_event`, et il ne
	# s'éteint que par `_decay` — la sonde exige les deux, l'allumage ET l'extinction par le temps.
	if _hitmarker > 0.0:
		var marker := _hitmarker_color()
		var near: float = 5.0 * _hitmarker_scale
		var far: float = (16.0 if _hitmarker_kill else 12.0) * _hitmarker_scale
		var width: float = 3.0 if _hitmarker_kill else 2.0
		for diagonal: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			list.append({PAINT_KIND: PAINT_LINE, PAINT_A: center + diagonal * near,
				PAINT_B: center + diagonal * far, PAINT_COLOR: marker, PAINT_WIDTH: width})
	return list


# LE REJEU — il ne connaît ni les armes, ni la dispersion, ni le hitmarker : il repasse la liste.
func _draw_reticle() -> void:
	for cmd: Dictionary in _reticle_paint_list():
		_paint_command(_reticle, cmd)


# LE PINCEAU GÉNÉRIQUE — une commande, une primitive. TOUS ses arguments viennent de la commande :
# il n'a rien à inventer, et c'est cette propriété-là que la sonde audite sur la source.
func _paint_command(target: CanvasItem, cmd: Dictionary) -> void:
	if cmd[PAINT_KIND] == PAINT_LINE:
		target.draw_line(cmd[PAINT_A], cmd[PAINT_B], cmd[PAINT_COLOR], cmd[PAINT_WIDTH])
	else:
		target.draw_circle(cmd[PAINT_A], cmd[PAINT_RADIUS], cmd[PAINT_COLOR])


# LA COULEUR DU HITMARKER, en un seul endroit : ROUGE si le coup a été FATAL (`hp` de l'événement
# serveur tombé à 0), OR sinon — l'alpha porte le fondu. Elle part dans la LISTE DE PEINTURE, et
# c'est cette liste que la sonde lit : une garde qui recalculerait la couleur de son côté, ou qui
# lirait une fonction que la peinture n'est pas tenue d'appeler, ne garderait rien.
func _hitmarker_color() -> Color:
	var base := COL_DANGER if _hitmarker_kill else COL_GOLD
	return Color(base.r, base.g, base.b, clampf(_hitmarker / HITMARKER_TIME, 0.0, 1.0))


# ╔═ §8.151 (2ter, CORRECTIF) — « DISPERSION INCONNUE » N'EST PAS « DISPERSION NULLE » ══════════╗
# ║ 🩸 CE QUI N'ALLAIT PAS. `_dispersion_degrees()` rendait 0,0 quand l'arme courante n'était pas  ║
# ║ au registre — ce qui inclut le cas le PLUS FRÉQUENT au démarrage : `_rules` encore VIDE, avant ║
# ║ que `trench_init` n'arrive (jusqu'à 20 s en compétition, cf. le pavé de `_refresh_view`). Et   ║
# ║ `_reticle_is_precise()` testant `<= 0.0`, le doute était rendu par l'interprétation la PLUS    ║
# ║ FLATTEUSE : la croix de PRÉCISION, c'est-à-dire la promesse propre au CONDOR — « ce coup part  ║
# ║ exactement là » — peinte pour une VIPÈRE à 0,30°. C'est mot pour mot ce que la décision §1.9   ║
# ║ interdit : le HUD ne montre que des mécaniques RÉELLES.                                        ║
# ║ Le registre est donc la SEULE source d'un cône, et son silence a désormais sa propre valeur —  ║
# ║ un sentinelle NÉGATIF, qu'aucun `dispersion_deg` légal ne peut prendre. Le repli sur doute est ║
# ║ la croix ORDINAIRE, jamais celle de précision : on préfère promettre moins que la sim ne donne.║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const DISPERSION_UNKNOWN := -1.0


# LA CROIX DE PRÉCISION — dérivée de la DISPERSION LUE, jamais d'un id d'arme (le jour où le
# registre donne 0° à une autre arme, elle en hérite sans qu'on rouvre ce fichier).
func _reticle_is_precise() -> bool:
	var degrees := _dispersion_degrees()
	if degrees < 0.0:
		return false        # DISPERSION INCONNUE : croix ORDINAIRE, jamais la promesse du Condor
	return degrees <= 0.0


# L'ÉCARTEMENT RENDU, en un seul endroit — et il n'a plus qu'UN appelant, `_reticle_paint_list()`,
# c'est-à-dire la description de ce qui est peint. La sonde mesure cette liste, jamais cette
# fonction pour elle-même : mesurer ce que le pinceau n'est pas tenu d'utiliser était PRÉCISÉMENT
# le faux vert de la première livraison. Trois termes, tous justifiés : le trou de lisibilité, la
# DISPERSION RÉELLE de l'arme, et le claquement de refus. Le pulse de tir s'y ajoute, borné et POSÉ
# (§4bis.1) — il vaut zéro au repos, donc la sonde mesure bien la dispersion seule dès que le
# ressort est collé.
func _reticle_spread_px() -> float:
	return RETICLE_GAP_PX + _dispersion_pixels() \
		+ (RETICLE_REFUSE_PX if _fire_refuse > 0.0 else 0.0) \
		+ RETICLE_PULSE_PX * clampf(_reticle_pulse.value, 0.0, 1.0)


# ╔═ §8.151 (2ter) — LA DISPERSION SE PROJETTE PAR LA MÊME FONCTION QUE LA VISÉE ═════════════════╗
# ║ AVANT : `tan(d) / tan(fov/2) × (size.y/2)` — une SECONDE arithmétique de projection, écrite à   ║
# ║ côté de celle qui place réellement le réticule (`_world.project_aim` → `unproject_position`).   ║
# ║ Les deux coïncident au centre de l'écran et divergent partout ailleurs : elle ignorait le suivi ║
# ║ de caméra, le roulis et le punch de FOV, c'est-à-dire tout ce que la vague 2 a ajouté. Deux     ║
# ║ arithmétiques pour une même grandeur finissent TOUJOURS par se contredire — c'est mot pour mot  ║
# ║ la leçon de la table v1/v4 (§8.141.6), qui a coûté une partie entière.                          ║
# ║ On MESURE donc l'écart en projetant les DEUX BORDS du cône avec la fonction de la visée, et on  ║
# ║ prend la demi-distance : `dispersion_deg` est un DEMI-angle (registre serveur, §8.137), le      ║
# ║ segment [yaw−d, yaw+d] vaut donc le cône entier et sa moitié est le rayon cherché.              ║
# ║ ⚠️ AUCUNE ÉCRITURE DE VISÉE : `_aim_yaw`/`_aim_pitch` sont LUS, les deux sondes de visée le      ║
# ║ prouvent. Le repli (pas de monde, pas de caméra) est l'ancienne trigonométrie — un réticule      ║
# ║ dessiné vaut mieux qu'un réticule absent, et le repli ne sert qu'aux harnais sans scène 3D.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _dispersion_pixels() -> float:
	var degrees := _dispersion_degrees()
	# Cône NUL (Condor) et cône INCONNU (`DISPERSION_UNKNOWN`, registre muet) donnent tous deux
	# zéro pixel à ajouter : il n'y a rien à projeter dans les deux cas. Ce qui les sépare est la
	# FORME de la croix, et ça se décide dans `_reticle_is_precise()` — pas ici.
	if degrees <= 0.0:
		return 0.0
	if _world != null:
		var left: Vector2 = _world.project_aim(_aim_yaw - degrees, _aim_pitch)
		var right: Vector2 = _world.project_aim(_aim_yaw + degrees, _aim_pitch)
		var half := left.distance_to(right) * 0.5
		if half > 0.0:
			return half
	# Le champ de vision appartient à la CAMÉRA : on le demande au monde 3D plutôt que d'en
	# recopier la valeur ici (une seule source, comme partout ailleurs dans ce chantier).
	var half_fov := deg_to_rad(_world.camera_fov() if _world != null else 55.0) * 0.5
	return tan(deg_to_rad(degrees)) / maxf(0.001, tan(half_fov)) * (size.y * 0.5)


# LE CÔNE DE L'ARME COURANTE, LU AU REGISTRE — jamais un barème recopié (§8.137, §1.9). L'arme vient
# de l'ÉTAT serveur, la dispersion de `trench_init.rules.weapons` : aucune des deux n'est devinée.
func _dispersion_degrees() -> float:
	var me := _player_of(_latest(), _my_slot)
	var weapon_id := str(me.get("weapon", STARTING_WEAPON))
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			return float(weapon.get("dispersion_deg", 0.0))
	# ⚠️ PAS DE REGISTRE, PAS DE CÔNE — et surtout pas un cône NUL (cf. le pavé de
	# `_reticle_is_precise`). Le sentinelle négatif traverse `_dispersion_pixels()` par la même
	# porte que le zéro (« aucun pixel à ajouter ») et se distingue de lui là où ça compte : la
	# forme de la croix. Deux ignorances, un seul dessin — l'ORDINAIRE.
	return DISPERSION_UNKNOWN


# =================================================================================================
# LE GUIDE DES COMMANDES (F1) — §8.141.3
# =================================================================================================
# ╔═ POURQUOI IL EXISTE, ET POURQUOI IL S'OUVRE TOUT SEUL LA PREMIÈRE FOIS ═══════════════════════╗
# ║ Deux verdicts de partie réelle sur trois portaient sur des commandes que le joueur ne pouvait  ║
# ║ PAS deviner : « la touche pour se cacher ne fonctionne pas » (elle n'était liée à rien) et     ║
# ║ « comment utiliser les bandages ? ». Le duel a NEUF commandes, dont trois — le maintien de     ║
# ║ grenade, le bandage, le choix d'arme — n'existent nulle part ailleurs dans le jeu. Les          ║
# ║ annoncer une fois coûte un panneau ; ne pas les annoncer coûte une partie à chaque nouveau     ║
# ║ joueur, et ça s'est produit deux fois de suite.                                                 ║
# ║                                                                                                 ║
# ║ ⚠️ IL S'OUVRE PENDANT LE BANDEAU D'AVANT-MANCHE, pas en pleine action : c'est le seul moment    ║
# ║ où le jeu ne demande rien au joueur (`intermission`, 3 s). Et il se referme au coup d'envoi     ║
# ║ SANS que le joueur ait à s'en occuper — un panneau qu'il faut fermer pour jouer serait un       ║
# ║ obstacle, pas une aide.                                                                         ║
# ║ ⚠️ IL NE RELÂCHE PAS LA SOURIS et ne met rien en pause (même règle que le bandeau F3, et        ║
# ║ contrairement au panneau F10) : il ne peut donc rien offrir à personne, et n'a aucune raison    ║
# ║ d'être interdit en duel classé.                                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _build_help_panel() -> void:
	_help_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_ACCENT
	sb.set_border_width_all(1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	_help_panel.add_theme_stylebox_override("panel", sb)
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_panel.visible = false
	_hud.add_child(_help_panel)
	# ⚠️ Taille POSÉE et ancrage par offsets explicites : 8ᵉ récidive évitée de « un Control créé par
	# code garde size = (0,0) » — le panneau F10 avait atterri à x = −400 pour cette raison exacte.
	_anchored(_help_panel, Control.PRESET_CENTER, Vector2(-330, -250), Vector2(660, 500))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_panel.add_child(column)

	var title := _label(tr("TRENCH_HELP_TITLE"), 22, COL_ACCENT)
	column.add_child(title)
	column.add_child(HSeparator.new())

	# Chaque ligne : la TOUCHE en or, ce qu'elle fait en texte clair. L'ordre suit celui dans lequel
	# un joueur découvre le duel — bouger, se cacher, viser, tirer, puis les objets.
	for pair in [["TRENCH_HELP_MOVE", "TRENCH_HELP_MOVE_D"],
			["TRENCH_HELP_STANCE", "TRENCH_HELP_STANCE_D"],
			["TRENCH_HELP_AIM", "TRENCH_HELP_AIM_D"],
			["TRENCH_HELP_FIRE", "TRENCH_HELP_FIRE_D"],
			["TRENCH_HELP_GRENADE", "TRENCH_HELP_GRENADE_D"],
			["TRENCH_HELP_RELOAD", "TRENCH_HELP_RELOAD_D"],
			["TRENCH_HELP_BANDAGE", "TRENCH_HELP_BANDAGE_D"],
			["TRENCH_HELP_CHOICE", "TRENCH_HELP_CHOICE_D"],
			["TRENCH_HELP_ESCAPE", "TRENCH_HELP_ESCAPE_D"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var key := _label(tr(String(pair[0])), 15, COL_GOLD)
		key.custom_minimum_size = Vector2(230, 0)
		row.add_child(key)
		var what := _label(tr(String(pair[1])), 15, COL_TEXT)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(what)
		column.add_child(row)

	column.add_child(HSeparator.new())
	var tip := _label(tr("TRENCH_HELP_TIP"), 14, COL_ACCENT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(600, 0)
	column.add_child(tip)
	var close := _label(tr("TRENCH_HELP_CLOSE"), 13, COL_MUTED)
	close.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(close)

	# Le rappel discret, toujours à l'écran : un raccourci qu'on n'annonce pas n'existe pas.
	_help_hint = _label(tr("TRENCH_HELP_HOTKEY"), 13, COL_MUTED)
	_help_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_child(_help_hint)
	_anchored(_help_hint, Control.PRESET_TOP_RIGHT, Vector2(-320, 42), Vector2(296, 20))


# ╔═ LA JAUGE DE CHARGE A DISPARU (§8.141) ═══════════════════════════════════════════════════════╗
# ║ C'était une barre dorée au bas de l'écran, remplie par le maintien, dont la valeur choisissait  ║
# ║ une des cinq positions adverses. Elle demandait au joueur de lire une abstraction PENDANT qu'il ║
# ║ armait — c'est-à-dire de quitter des yeux le seul endroit qui compte. Le décalque au sol la     ║
# ║ remplace intégralement : il montre le point ET le rayon, LÀ où la grenade va tomber, et il se   ║
# ║ lit sans quitter la cible du regard. Il n'y a plus rien à afficher au bas de l'écran.           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝


func _refresh_hud(latest: Dictionary, me: Dictionary, they: Dictionary,
		render_tick: float) -> void:
	var hp_max := float(_rules.get("hp_max", 100))
	var my_hp := float(me.get("hp", 0))
	var their_hp := float(they.get("hp", 0))
	_my_hp_fill.size.x = 238.0 * clampf(my_hp / hp_max, 0.0, 1.0)
	_their_hp_fill.size.x = 178.0 * clampf(their_hp / hp_max, 0.0, 1.0)
	_my_hp_label.text = str(int(my_hp))

	# --- Munitions « 06/15 » ---
	var mag := _mag_size(str(me.get("weapon", "vipere")))
	_ammo_label.text = "%02d/%02d" % [int(me.get("ammo", 0)), mag]
	var reloading := int(me.get("reload_until_tick", 0)) > int(render_tick)
	_ammo_label.add_theme_color_override("font_color",
		COL_DANGER if (int(me.get("ammo", 0)) <= 0 or reloading) else COL_TEXT)
	_reload_label.text = tr("TRENCH_RELOADING") if reloading else ""
	# Le VIEWMODEL PEINT (§8.138) est une VUE : il ne relit pas l'état, on le lui pousse.
	# (§8.151 : plus de valeur de recul à pousser — le kick vit dans ses ressorts, `notify_fire`.)
	_viewmodel.set_reloading(reloading)
	# §8.152 — ce dont le rig 3D a besoin, et qui n'existe QUE dans l'état serveur.
	_rig_weapon = str(me.get("weapon", "vipere"))
	_rig_empty = int(me.get("ammo", 0)) <= 0
	_weapon_label.text = _weapon_name(str(me.get("weapon", "vipere")))
	_progress_label.text = _escalation_text(int(me.get("hits_total", 0)))

	# --- Cases d'objets ---
	_slot_grenade.text = "1  " + tr("TRENCH_GRENADES") % int(me.get("grenades", 0))
	# ╔═ LE REFUS SE VOIT ET S'ENTEND — IL N'EST JAMAIS SILENCIEUX (§B.1.3) ══════════════════════╗
	# ║ Tenter un lancer sans stock secoue la case et la passe au rouge, deux frames. C'est la      ║
	# ║ leçon directe de « la touche pour se cacher ne fonctionne pas » (§6.2 du rapport de pivot) :║
	# ║ ce n'était pas un bug, c'était une absence de réponse — et une absence de réponse EST un    ║
	# ║ bug du point de vue du joueur. Une case qui tremble dit « entendu, mais non ».              ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	if _grenade_refuse > 0.0:
		var wobble: float = 0.0 if _reduced_motion else sin(_grenade_refuse * 90.0) * 4.0
		_slot_grenade.offset_left = -190.0 + wobble
		_slot_grenade.offset_right = -10.0 + wobble
		_slot_grenade.add_theme_color_override("font_color", COL_DANGER)
	else:
		_slot_grenade.offset_left = -190.0
		_slot_grenade.offset_right = -10.0
		_slot_grenade.add_theme_color_override("font_color", COL_GOLD)
	var bandaging := int(me.get("bandage_until_tick", 0)) > int(render_tick)
	var bandages := int(me.get("bandages", 0))
	if bandaging:
		_slot_bandage.text = "2  " + tr("TRENCH_HEALING")
		_slot_bandage.add_theme_color_override("font_color", COL_ACCENT)
	else:
		_slot_bandage.text = "2  " + tr("TRENCH_ITEM_BANDAGE") + ("" if bandages > 0
			else "  " + tr("TRENCH_ITEM_USED"))
		_slot_bandage.add_theme_color_override("font_color",
			COL_GOLD if bandages > 0 else COL_MUTED)

	# --- Chrono / manche / score ---
	var phase := str(latest.get("phase", ""))
	# ⚠️ LE GUIDE S'OUVRE TOUT SEUL, UNE FOIS, PENDANT LE PREMIER BANDEAU D'AVANT-MANCHE. C'est le
	# seul instant où le jeu ne demande rien au joueur (3 s d'intermission), et c'est aussi le seul
	# où l'ignorer ne coûte rien. Deux verdicts de partie réelle sur trois portaient sur des
	# commandes indevinables — les annoncer une fois coûte moins cher que de les faire découvrir.
	if not _help_shown_once and phase == "intermission" and _help_panel != null:
		_help_shown_once = true
		_help_panel.visible = true
	if phase == "playing":
		var remaining := maxi(0, int(_rules.get("round_ticks", 900))
			- int(render_tick - float(latest.get("round_start_tick", 0))))
		var seconds := int(ceil(float(remaining) / _tick_rate))
		_timer_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	else:
		_timer_label.text = "—"
	_round_label.text = tr("TRENCH_ROUND") % int(latest.get("round_no", 1))
	var score: Array = latest.get("score", [0, 0])
	if score.size() >= 2:
		_score_label.text = tr("TRENCH_SCORE") % [int(score[_my_slot - 1]), int(score[2 - _my_slot])]

	# --- Dégâts subis : le pouls directionnel du flinch (overlay dédié §8.151, shader sans TIME) ---
	var flinch_mat := _hurt_overlay.material as ShaderMaterial
	if flinch_mat != null:
		# L'enveloppe 0,5 s de §5.5 devient l'uniform `intensity` (1 → 0) ; le CÔTÉ vient de la
		# position d'arène relative (`_hurt_dir` > 0 = adversaire côté +X monde = GAUCHE écran,
		# la mesure de SCREEN_TO_WORLD_X) et sature au-delà de 2 crans d'écart ⚙.
		flinch_mat.set_shader_parameter("intensity",
			clampf(_hurt_flash / 0.5 * _feel_flinch, 0.0, 1.0))
		flinch_mat.set_shader_parameter("side", clampf(-_hurt_dir * 0.5, -1.0, 1.0))
	_low_hp_vignette.color.a = 0.30 if my_hp <= hp_max * 0.25 and my_hp > 0.0 else 0.0

	if _choice_panel.visible:
		var deadline := int(_player_of(latest, _my_slot).get("choice_deadline_tick", 0))
		if deadline > 0:
			_choice_countdown.text = str(maxi(0, int(ceil((float(deadline) - render_tick)
				/ _tick_rate))))
		else:
			_choice_panel.visible = false
			_restore_mouse()


# Cadence d'une arme, en SECONDES. Lue dans `public_rules` : aucun barème en dur côté client.
func _cadence_seconds(weapon_id: String) -> float:
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			return float(weapon.get("cooldown_ticks", 0)) / _tick_rate
	return 0.0


# ╔═ §8.151 (2bis, correctif) — CE QUI RESTE DE LA CADENCE QUAND LE SERVEUR CONFIRME LE TIR ══════╗
# ║ La sim pose `fire_ready_tick = tick + cooldown_ticks` AU CLIC, AVANT même de brancher sur le    ║
# ║ laser (`trench_sim.step`). Pour une arme TÉLÉGRAPHIÉE (CONDOR), l'événement `fire` n'est émis   ║
# ║ qu'au tir échu, `laser_lead_ticks` plus tard : recaler la porte prédite sur la cadence ENTIÈRE  ║
# ║ à cet instant-là la repoussait de 0,5 s au-delà de la porte réelle. Tant que le décalage était  ║
# ║ muet, il rendait seulement la prédiction « prudente » ; depuis que `_arm_bolt` s'y branche, le  ║
# ║ clac de culasse — dont TOUT le rôle est de dire « prête » sans regarder le HUD — annonçait la   ║
# ║ disponibilité une demi-seconde APRÈS qu'elle soit acquise. Un repère de rythme qui ment sur une ║
# ║ mécanique réelle : le §1.9 l'interdit à l'œil, il n'y a pas de raison de le tolérer à l'oreille ║
# ║ (même argument que le recalage du bourdonnement du télégraphe sur la fenêtre de la SIM).        ║
# ║ ⚠️ LES DEUX BARÈMES SONT LUS AU REGISTRE, c'est leur ÉCART qui est la réponse : retoucher le ⚙   ║
# ║ `laser_lead_ticks` ou `cooldown_ticks` suit tout seul. Une arme ordinaire (`lead` 0) retrouve   ║
# ║ EXACTEMENT `_cadence_seconds` — le chemin nominal ne bouge pas d'un octet.                      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _cadence_remaining_seconds(weapon_id: String) -> float:
	var lead := 0.0
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			lead = float(weapon.get("laser_lead_ticks", 0))
			break
	# La cadence PLEINE passe par le helper existant : `cooldown_ticks` n'a qu'UN site de lecture.
	return maxf(0.0, _cadence_seconds(weapon_id) - lead / _tick_rate)


# ╔═ §8.152 (lot 3D-H, étage 0) — LA DURÉE DE RECHARGEMENT, LUE AU REGISTRE ════════════════════╗
# ║ Le viewmodel 3D anime le rechargement, et il lui faut une DURÉE. ⛔ Celle-ci est une valeur   ║
# ║ de RÈGLE : le serveur détient `reload_ticks` et c'est LUI qui remplit le chargeur, à          ║
# ║ `reload_until_tick`. Le client n'avait jamais eu à la lire — il ne connaissait du            ║
# ║ rechargement que l'échéance dans l'état.                                                     ║
# ║                                                                                               ║
# ║ 🩸 POURQUOI IL N'Y A PAS DE VALEUR PAR DÉFAUT. La référence portée écrit                      ║
# ║ `def.reloadTac ?? 2.15`. Recopié tel quel, ça donnerait 2,15 s d'animation pour une VIPÈRE    ║
# ║ que le serveur recharge en 1,50 s : la main reviendrait au garde-main **0,65 s après** que le ║
# ║ joueur a été autorisé à tirer. C'est le patron exact du §8.148 — une seconde source de vérité ║
# ║ qui diverge au premier rééquilibrage, en silence, et du seul côté que le joueur voit.         ║
# ║                                                                                               ║
# ║ ⚠️ Le repli est **0,0 et pas une durée plausible**, exactement comme `_cadence_seconds` : un   ║
# ║ zéro se remarque, un 2,15 se fond dans le décor. L'appelant doit traiter le registre muet     ║
# ║ comme « je ne sais pas encore », pas comme « recharge en deux secondes ».                     ║
# ║                                                                                               ║
# ║ ⚠️⚠️ PIÈGE D'ORDONNANCEMENT — À LIRE AVANT DE BRANCHER CET ACCESSEUR SUR LE RIG.             ║
# ║ `_apply_weapon()` est appelé depuis `_build_layers()`, donc dans `_ready()`, **bien avant**    ║
# ║ `_on_init`. À cet instant `_rules` est VIDE et `_tick_rate` vaut encore 10 alors que le        ║
# ║ contrat courant est à 20 Hz (§8.141.2) : un facteur DEUX, même si les règles étaient là. Le    ║
# ║ viewmodel 2D s'en moquait (il ne consommait aucune règle) ; le rig 3D, lui, **fige la durée   ║
# ║ dans ses clips à la construction**. Il faudra donc construire les armes APRÈS `_on_init`, ou   ║
# ║ reconstruire les clips à l'arrivée du registre.                                               ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _reload_seconds(weapon_id: String) -> float:
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			return float(weapon.get("reload_ticks", 0)) / _tick_rate
	return 0.0


func _mag_size(weapon_id: String) -> int:
	for weapon in _rules.get("weapons", []):
		if str(weapon.get("id", "")) == weapon_id:
			return int(weapon.get("mag_size", 0))
	return 0


func _weapon_name(weapon_id: String) -> String:
	return tr("WEAPON_" + weapon_id.to_upper())


func _escalation_text(hits: int) -> String:
	var esc: Dictionary = _rules.get("escalation", {})
	var frelon := int(esc.get("frelon_hits", 4))
	var choice := int(esc.get("choice_hits", 10))
	if hits < frelon:
		return tr("TRENCH_NEXT_WEAPON") % [hits, frelon]
	if hits < choice:
		return tr("TRENCH_NEXT_WEAPON") % [hits, choice]
	return tr("TRENCH_ARSENAL_MAX")


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(0.9)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


# =================================================================================================
# PANNEAUX (choix d'arme, abandon, résultat) — la souris est RELÂCHÉE dès qu'un clic est attendu
# =================================================================================================
func _build_choice_panel() -> void:
	_choice_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_GOLD
	sb.set_border_width_all(1)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	_choice_panel.add_theme_stylebox_override("panel", sb)
	_choice_panel.visible = false
	add_child(_choice_panel)
	_anchored(_choice_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-230, -240))
	var box := VBoxContainer.new()
	_choice_panel.add_child(box)
	_choice_title = _label("", 18, COL_GOLD)
	box.add_child(_choice_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_choice_buttons = []
	for i in range(2):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(190, 42)
		# ⚠️ PAS DE FOCUS SUR CES DEUX BOUTONS-LÀ, et c'est une décision de JEU : ce panneau s'ouvre
		# TOUT SEUL en pleine manche, pendant que le soldat marche aux FLÈCHES. Focusables, ils
		# capteraient cette navigation — et `ui_accept` choisirait une arme sur un geste de déplacement.
		# Ils gardent la souris et leurs touches à eux (`1`/`2`) ; ils ne prennent pas celles du soldat.
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_override("font", _make_font())
		btn.add_theme_font_size_override("font_size", 16)
		WarzoneUI.apply_ghost_button(btn)
		btn.pressed.connect(_queue_pick.bind(i))
		row.add_child(btn)
		_choice_buttons.append(btn)
	_choice_countdown = _label("", 22, COL_TEXT, true)
	_choice_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_choice_countdown)


func _open_choice(event: Dictionary) -> void:
	# ⚠️ RÉFÉRENCES DIRECTES, jamais get_node : les nœuds créés par code reçoivent des noms
	# auto-générés (« @VBoxContainer@N ») — un chemin littéral échouerait (défaut vu en CAPTURE).
	var options: Array = event.get("options", [])
	if options.size() < 2 or _choice_buttons.size() < 2:
		return
	var name_a := _weapon_name(str(options[0]))
	var name_b := _weapon_name(str(options[1]))
	_choice_title.text = tr("TRENCH_WEAPON_CHOICE") % [name_a, name_b]
	(_choice_buttons[0] as Button).text = "1 · " + name_a
	(_choice_buttons[1] as Button).text = "2 · " + name_b
	_choice_panel.visible = true
	_restore_mouse()


func _queue_pick(index: int) -> void:
	var esc: Dictionary = _rules.get("escalation", {})
	var options: Array = esc.get("choice_options", ["chacal", "condor"])
	if index >= 0 and index < options.size():
		_pick_queued = str(options[index])
	_choice_panel.visible = false
	_restore_mouse()


func _build_abandon_overlay() -> void:
	_abandon_overlay = _overlay_base()
	var panel := _overlay_panel(_abandon_overlay, Vector2(420, 170))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label(tr("TRENCH_ABANDON_TITLE"), 20, COL_DANGER))
	box.add_child(_label(tr("TRENCH_ABANDON_BODY"), 14, COL_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var confirm := Button.new()
	confirm.text = tr("TRENCH_ABANDON_CONFIRM")
	confirm.custom_minimum_size = Vector2(170, 40)
	confirm.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(confirm)
	confirm.pressed.connect(func():
		NetworkManager.send_trench_forfeit()
		_abandon_overlay.visible = false)
	row.add_child(confirm)
	var cancel := Button.new()
	cancel.text = tr("TRENCH_ABANDON_CANCEL")
	cancel.custom_minimum_size = Vector2(170, 40)
	cancel.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(cancel)
	cancel.pressed.connect(func():
		_abandon_overlay.visible = false
		_restore_mouse())
	row.add_child(cancel)


func _overlay_base() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	add_child(overlay)
	return overlay


func _overlay_panel(overlay: Control, panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = panel_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.border_color = COL_ACCENT
	sb.set_border_width_all(1)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)
	_anchored(panel, Control.PRESET_CENTER, -panel_size * 0.5)
	WarzoneUI.add_corner_notches(panel)
	return panel


# =================================================================================================
# ÉCRAN DE FIN — sobre : score, coins (avec plafond affiché), progression, REJOUER / RETOUR
# =================================================================================================
func _show_result(msg: Dictionary) -> void:
	if _result_overlay != null:
		return
	_capture_mouse(false)
	_abandon_overlay.visible = false
	_choice_panel.visible = false
	_result_overlay = _overlay_base()
	_result_overlay.visible = true
	var panel := _overlay_panel(_result_overlay, Vector2(520, 380))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var latest := _latest()
	var winner := int(msg.get("winner_slot", latest.get("winner_slot", 0)))
	var won := winner == _my_slot
	box.add_child(_label(tr("TRENCH_WIN") if won else tr("TRENCH_LOSE"), 30,
		COL_GOLD if won else COL_DANGER))
	var score: Array = msg.get("score", latest.get("score", [0, 0]))
	if score.size() >= 2:
		box.add_child(_label(tr("TRENCH_SCORE") % [int(score[_my_slot - 1]),
			int(score[2 - _my_slot])], 18, COL_TEXT, true))

	if bool(msg.get("training", _training)):
		box.add_child(_label(tr("TRENCH_VS_BOT_NOTE"), 14, COL_MUTED))
	else:
		var rewards = msg.get("rewards")
		if typeof(rewards) == TYPE_DICTIONARY:
			_fill_rewards(box, rewards, bool(msg.get("vs_bot", false)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var replay := Button.new()
	replay.text = tr("TRENCH_REPLAY")
	replay.custom_minimum_size = Vector2(190, 44)
	replay.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(replay)
	replay.pressed.connect(_back_to_hub.bind(true))
	row.add_child(replay)
	var back := Button.new()
	back.text = tr("TRENCH_BACK")
	back.custom_minimum_size = Vector2(190, 44)
	back.add_theme_font_override("font", _make_font())
	WarzoneUI.apply_ghost_button(back)
	back.pressed.connect(_back_to_hub.bind(false))
	row.add_child(back)

	var new_titles: Array = []
	var rewards2 = msg.get("rewards")
	if typeof(rewards2) == TYPE_DICTIONARY:
		new_titles = rewards2.get("new_titles", [])
	if not new_titles.is_empty():
		var celebration := Control.new()
		celebration.set_script(CelebrationScript)
		add_child(celebration)
		celebration.play({"name": tr("TITLE_TRENCH_" +
			str(new_titles[0].get("title_key", "")).to_upper()), "accent": COL_GOLD})


func _fill_rewards(box: VBoxContainer, rewards: Dictionary, vs_bot: bool) -> void:
	var part := int(rewards.get("participation_coins", 0))
	var part_line := tr("TRENCH_COINS_PARTICIPATION") % part
	if bool(rewards.get("participation_capped", false)):
		part_line = tr("TRENCH_DAILY_CAP")
	box.add_child(_label("❯ " + part_line, 14, COL_TEXT))
	var win_coins := int(rewards.get("win_coins", 0))
	if win_coins > 0:
		box.add_child(_label("❯ " + tr("TRENCH_COINS_WIN") % win_coins, 14, COL_GOLD))
	elif bool(rewards.get("win_capped", false)):
		box.add_child(_label("❯ " + tr("TRENCH_DAILY_CAP"), 14, COL_MUTED))
	elif vs_bot:
		box.add_child(_label("❯ " + tr("TRENCH_BOT_NO_WIN_REWARD"), 14, COL_MUTED))
	var progression = rewards.get("progression")
	if typeof(progression) == TYPE_DICTIONARY:
		var wins := int(progression.get("wins", 0))
		var level := int(progression.get("level", 0))
		var level_max := int(progression.get("level_max", 3))
		var next = progression.get("next_threshold")
		var line := tr("TRENCH_EVENT_LEVEL") % [level, level_max, wins]
		if next != null:
			line += "  ·  " + tr("TRENCH_NEXT_LEVEL") % int(next)
		box.add_child(_label(line, 14, COL_ACCENT))


func _back_to_hub(requeue := false) -> void:
	_capture_mouse(false)
	NetworkManager.leave_room()
	var events_script := load("res://scripts/ui/events_screen.gd")
	if events_script != null and requeue:
		events_script.pending_trench_requeue = true
	TransitionManager.change_scene("res://scenes/ui/events.tscn")
