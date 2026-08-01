extends Node

# CONTRÔLEUR D'ARÈNE — le "cerveau" de la machine d'états côté client (Règle d'Or §6.2).
# Reçoit les clics du plateau et le bouton de phase, valide localement (UX), et envoie les
# actions au serveur via NetworkManager. Le serveur reste l'autorité (re-valide tout).
#
# Flux des phases d'un tour (moteur) : 1 Renforts (auto) -> 2 Déploiement -> 3 Attaque
# -> 4 Mouvement -> (5 Évènement / fin de tour). On avance avec "Fin de Phase" (pass_turn).

@export var test_room_id: String = "1"

# Scène de résolution visuelle des combats (Split-Screen VS, instanciée en surcouche).
const SplitScreenVSScene := preload("res://scenes/game/split_screen_vs.tscn")
# Flèche de guerre + explosion (lot D) : combats où je ne suis NI attaquant NI défenseur — animée
# DANS le plateau (SubViewport), aucun plein écran.
const AttackArrowScene := preload("res://scenes/game/attack_arrow.tscn")
# Cinématique de mise à mort (lot D) : permadeath §8.61, jouée pour TOUS, finisher du TUEUR.
const HeroDownCinematicScene := preload("res://scenes/game/hero_down_cinematic.tscn")
# Écran de Rapport Post-Opération (§4 Warzone Command), instancié en surcouche à la fin de partie.
const OperationReportScene := preload("res://scenes/game/operation_report.tscn")
# Script du rapport (E11 §8.83) : helpers statiques (titres honorifiques, médailles) appelés par
# le contrôleur pour résoudre les lignes du podium.
const OperationReportScript := preload("res://scripts/game/operation_report.gd")
# Bandeau de tour/phase (E3 §8.75) : stinger haut-centre non bloquant.
const PhaseBannerScene := preload("res://scenes/components/phase_banner.tscn")
# Journal de Guerre 2.0 (E4 §8.76) : module de parsing PUR des évènements → entrées structurées.
const WarFeed := preload("res://scripts/ui/war_feed.gd")
# War Room (E5 §8.77) : module de calcul PUR de l'Intel de guerre (8 compteurs + continents).
const WarRoom := preload("res://scripts/ui/war_room.gd")
# Tracker d'objectif vivant (E6 §8.78) : module de calcul PUR de la progression de l'objectif.
const ObjectiveTracker := preload("res://scripts/ui/objective_tracker.gd")
# Helpers de charte partagés (identité du meneur de faction — refonte 2026-07-18).
const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")
# Helpers purs du Roster de Guerre (E1 §8.73) : sorted_pids reste la SOURCE UNIQUE de l'ordre
# d'affichage des belligérants — réutilisé par la navigation ◀ ▶ de la fiche joueur (lot A).
const RosterHelpers := preload("res://scripts/ui/war_roster.gd")
# Jauge de tension UNIQUE (§8.122, LOT A) : module PUR (statique) — la formule vit là-bas, le
# contrôleur ne fait que l'ALIMENTER et la PROPAGER. Chargé par preload comme les autres modules
# du dossier (le `class_name` existe, mais on n'en dépend pas — prudence cache d'import, CLAUDE.md).
const WarIntensityCalc := preload("res://scripts/game/war_intensity.gd")

# --- PACTES DE NON-AGRESSION (§8.123) : MIROIR du registre serveur `pacts.PACT_RULES` -------------
# ⚠️ Ce sont des valeurs d'AFFICHAGE (libellé du bouton, grisages, calcul de trêve restant), jamais
# une règle : le serveur reste seul juge. Elles sont recopiées ici parce que le client ne reçoit pas
# le registre — si le serveur les change, le pire cas est un bouton grisé à tort (ou l'inverse),
# suivi d'un refus PROPRE et traduit. Toute modification du registre serveur doit être répercutée
# ici, comme `map_data.gd` l'est de `map_data.py`.
const PACT_DURATION_ROUNDS := 2
const PACT_MAX_ACTIVE := 2
const PACT_COOLDOWN_ROUNDS := 2

@onready var button = $Button
# Depuis la refonte HUD RTS (§8.29), le SubViewport du plateau est le 1ᵉʳ enfant de Main (plateau
# plein écran) et n'est PLUS sous le HUD : chemins mis à jour en conséquence. Le HUD reste $HUD.
@onready var board = $MapViewportContainer/MapContent/Board
@onready var camera = $MapViewportContainer/MapContent/TacticalCamera
@onready var hud = $HUD

# Territoire source sélectionné (attaque / mouvement). "" = aucun.
var _source: String = ""
# Évite d'afficher l'écran de victoire plusieurs fois.
var _victory_shown: bool = false
# Économie de fin de partie (§8.47) : détail des gains (game_over.match_rewards, clés str par
# player_id) + référence du Rapport Post-Op affiché, pour pousser les récompenses si le message
# game_over arrive APRÈS son ouverture (l'état winner_id et la clôture sont 2 messages distincts).
var _match_rewards: Dictionary = {}
var _report_node: Control = null
# Classement de la partie (E11 §8.83) : rankings du game_over (liste de pids, gagnant en tête) —
# consommé par le podium du Rapport Post-Op. [] tant que la clôture n'est pas reçue.
var _match_rankings: Array = []
# §8.99 — vrai dès que le message game_over (rankings + match_rewards) a été reçu au moins une fois
# pour cette partie. NE PAS confondre avec `_match_rankings.is_empty()` : sert de verrou pour ne
# JAMAIS déclarer une anomalie « aucune récompense » (cf. _has_played/populate_rewards) tant que le
# game_over n'est pas CONFIRMÉ arrivé — sinon la course réseau (état winner_id pouvant précéder le
# game_over, cf. commentaire _match_rewards ci-dessus) ferait passer un simple retard réseau pour
# une anomalie, et la garde _rewards_built de operation_report.gd figerait ce faux diagnostic AVANT
# même que les vraies récompenses (poussées juste après par _on_match_over) n'aient une chance de
# s'afficher.
var _match_over_received := false
# Pont missions (E11) : un seul fetch par fin de partie.
var _missions_fetched_for_report := false
# CARTE DE PARTAGE (§8.121, LOT D) — horodatage d'entrée dans l'arène, pour annoncer une DURÉE de
# partie sur la carte. Mesuré CÔTÉ CLIENT à dessein : le serveur n'expose que l'ÉCHÉANCE
# (`match_deadline_epoch`, §8.120), jamais l'instant de création de l'état ; on ne peut donc pas
# reconstituer le temps écoulé depuis le draft. Ce que la carte annonce est donc « la durée telle
# que CE joueur l'a vécue depuis son entrée dans l'arène » — l'écart avec la durée serveur est le
# draft (≤ 60 s) et le placement (≤ 90 s), et c'est assumé pour un objet marketing.
var _arena_entered_at := 0.0
# Vrai pendant l'animation Split-Screen VS : le rafraîchissement du plateau est alors différé
# (_refresh_pending) pour figer la mise à jour visuelle des troupes jusqu'à la fin du combat.
var _combat_animating: bool = false
var _refresh_pending: bool = false
# File d'attente des combats (correctif « PV qui disparaissent sans raison ») : un 2ᵉ attack_result reçu
# pendant qu'un Split-Screen VS s'anime est MIS EN FILE au lieu d'être jeté — chaque duel s'anime à son
# tour (sinon le HUD sautait à la valeur finale sans transition, typiquement pendant un tour de bot
# multi-attaques). Plafonnée : au-delà, on abrège (l'état diffusé reste correct, seule la narration résumée).
var _combat_queue: Array = []
const COMBAT_QUEUE_CAP := 6

# --- RYTHME DES TOURS ADVERSES (lot C) : file d'événements NON-combat d'un adversaire (bot ou
# humain), jouée SÉQUENTIELLEMENT à cadence lisible au lieu d'être absorbée d'un coup par le
# refresh d'état. Elle partage le MÊME verrou d'animation que les combats (_combat_animating) →
# les deux files s'enchaînent sans jamais se chevaucher, et le plateau ne se repeint qu'à la fin
# (pattern _refresh_pending existant). Aucune pause pendant MON tour : mes actions restent
# instantanées. ---
# event_type → clé i18n du toast d'action.
const PACE_EVENT_KEYS := {
	"units_deployed": "PACE_DEPLOY_FMT",
	"initial_units_placed": "PACE_DEPLOY_FMT",
	"units_moved": "PACE_MOVE_FMT",
	"card_played": "PACE_CARD_FMT",
	"card_kept": "PACE_CARD_FMT",
	"conquer_move_resolved": "PACE_CONQUER_MOVE_FMT",
}
# Cadence NOMINALE d'une action adverse (s) et cadence CONDENSÉE quand la file s'allonge
# (garde-fou anti-ennui : au-delà de PACE_QUEUE_RUSH entrées en attente, on accélère).
const PACE_STEP_TIME := 0.9
const PACE_STEP_TIME_FAST := 0.4
const PACE_QUEUE_RUSH := 8
# Plafond dur de la file (une salle de 5 bots peut produire beaucoup d'actions par tour) : au-delà,
# les plus anciennes sont abandonnées — l'état diffusé reste correct, seule la narration est
# résumée (même compromis que COMBAT_QUEUE_CAP).
const PACE_QUEUE_CAP := 24
var _pace_queue: Array = []
# tid -> owner_id tel qu'AFFICHÉ sur le plateau (snapshot du dernier _refresh). Indispensable
# pour retrouver le propriétaire PRÉ-combat du territoire défenseur : l'état reçu avec
# attack_result est déjà post-combat (en cas de conquête, l'owner a déjà basculé).
var _displayed_owners: Dictionary = {}
# tid -> garnison telle qu'AFFICHÉE (même snapshot) — E2 §8.74 : le VS affiche « avant ➜ après »
# par camp ; l'« avant » exact vient d'ici (l'état reçu est déjà post-combat, et le reconstruire
# par after+pertes serait FAUX en cas de conquête — troupes déplacées en plus des pertes).
var _displayed_garrisons: Dictionary = {}
# Déplacement post-conquête (CONTEXTE.md §8.23) : pendant l'attente du choix du joueur, le jeu
# local est FIGÉ (_awaiting_conquer_move) et le contexte de la conquête (from/to/min/max) mémorisé.
var _awaiting_conquer_move: bool = false
var _conquer_ctx: Dictionary = {}
# Mécaniques à états bloquants des factions (§8.3) : pendant qu'un de ces choix est affiché, le
# jeu local est FIGÉ (mêmes blocages que la fenêtre de conquête).
#  - Ordre de l'Éclipse : choisir laquelle des 2 cartes Événement conserver (action keep_card).
#  - Chasseurs d'Ombres : choisir un adversaire à espionner (action spy_objective).
var _awaiting_eclipse: bool = false
var _awaiting_spy: bool = false

# Tampon de déploiement LOCAL (§8.26) : tid -> nb de troupes en attente de confirmation. Rempli
# par clic gauche (+1) / droit (-1) pendant le placement initial ou la Phase 2 (renforts), puis
# envoyé en MASSE au serveur (action deploy_units) au clic sur « CONFIRMER LE DÉPLOIEMENT ».
var pending_deployments: Dictionary = {}

# Verrou « action en vol » (correctif §8.48) : empêche un 2ᵉ envoi de pass_turn tant que le serveur
# n'a pas répondu (un double-clic sur « Fin de Phase » avançait 2 phases d'un coup → saut d'étape).
# Levé à la réception de l'état (action acceptée) OU d'une erreur (action refusée).
var _pass_in_flight: bool = false
# Tampon de déploiement envoyé, conservé jusqu'à l'accusé serveur (correctif §8.48) : restauré tel
# quel si le serveur REFUSE le déploiement (plus de placement reperdu ni de soft-lock Phase 0).
var _deploy_snapshot: Dictionary = {}
var _deploy_in_flight: bool = false
# Verrou anti double-ATTAQUE (correctif « double déduction de PV ») : vrai dès l'ENVOI d'une attaque
# et jusqu'au retour du résultat serveur. Combiné à _combat_animating dans _input_blocked(), il garantit
# UN seul « attack_territory » par attaque VOULUE — sinon un 2ᵉ clic (pendant l'aller-retour réseau ou
# l'animation Split-Screen VS) déclencherait un 2ᵉ duel serveur (PV du héros déduits « une 2ᵉ fois »).
# Levé par _on_state_updated (résultat reçu) ou _on_game_error (attaque refusée) → jamais de soft-lock.
var _attack_in_flight: bool = false
# Filet de sécurité anti soft-lock du verrou d'attaque : la « génération » garantit qu'un ancien
# timeout ne lève PAS le verrou d'une attaque armée plus tard (cf. _arm_attack_in_flight).
var _attack_flight_gen: int = 0
const ATTACK_IN_FLIGHT_TIMEOUT := 8.0

# Phase 0 — DÉPLOIEMENT AVEUGLE & SIMULTANÉ (§8.31). Le serveur MASQUE pending_blind_deploy dans
# l'état diffusé : on suit donc LOCALEMENT le fait d'avoir soumis. Une fois vrai, le joueur ne peut
# plus modifier son tampon (clics ignorés) et l'UI passe en « attente des autres joueurs ». Remis à
# false dès qu'on quitte le placement. _blind_ready / _blind_expected = compteur X/Y lu de
# l'évènement blind_deploy_submitted (affichage « en attente (X/Y) »).
var _blind_submitted: bool = false
var _blind_ready: int = 0
var _blind_expected: int = 0

const FACTIONS_DIR := "res://resources/factions/"
# Cache des infos de faction (id -> {name, description, power, hero_path, leader}) lues des
# resources/factions/*.tres — SOURCE UNIQUE consommée par la zone JOUEUR, la fiche joueur et le
# Rapport Post-Op (chargée une fois par faction : elle ne change pas en cours de partie).
var _faction_full_cache: Dictionary = {}
# Cache des MODIFICATEURS de faction (id -> Dictionary), miroir du registre backend §4.3 lu des
# .tres — consommé par la Prévision de combat (G4 §8.63 : flags de dés passés à CombatOdds).
var _faction_mods_cache: Dictionary = {}
# FICHE JOUEUR (lot A) : joueur actuellement affiché dans le panneau gauche (-9999 = aucun) et
# territoire cliqué à détailler en bas de fiche ("" = aucun — navigation par flèches). Servent au
# rafraîchissement TEMPS RÉEL de la fiche (les PV/territoires changent après un combat).
var _sheet_pid: int = -9999
var _sheet_territory: String = ""

# Bandeaux de tour/phase (E3 §8.75) : instance + mémoire de détection des changements.
var _phase_banner = null
var _banner_turn_key := ""
var _banner_phase := -1

# Ré-assaut en un clic (E7 §8.79) : dernière attaque {source, target} pour rejouer le MÊME assaut
# tant qu'il reste légal (source ≥ 2, cible toujours ennemie, Phase 3, notre tour, non conclusif).
var _last_attack: Dictionary = {}

# Rythme des combats (E8 §8.80) : paire (source→cible) du DERNIER combat animé → à partir du 2ᵉ
# assaut consécutif sur la MÊME paire, le VS passe en version condensée (~1,2 s).
var _last_combat_pair: String = ""
# Facteur d'accélération du Split-Screen VS. Ex-valeur du mode « rapide » du réglage
# `combat_display` (E8 §8.80) : ce mode ayant été retenu comme le SEUL (décision Hakim
# 2026-07-27), le facteur devient une constante nommée du contrôleur.
const COMBAT_VS_SPEED := 2.5

# SFX zone_alarm (E9 §8.81) : signature du dernier télégraphe joué (évite le rejeu à chaque refresh).
var _last_zone_alarm_sig: String = ""

# --- INTENSITÉ DE GUERRE (§8.122, LOT A) : cible recalculée à CHAQUE refresh d'état, valeur lissée
#     en `_process`, propagée aux TROIS consommateurs par un chemin UNIQUE (aucun d'eux ne lit
#     GameState de son côté). `_war_intensity_pushed` mémorise la dernière valeur RÉELLEMENT
#     poussée : sous le seuil, on ne repousse rien → zéro travail inutile par frame. ---
var _war_intensity_target: float = 0.0
var _war_intensity: float = 0.0
var _war_intensity_pushed: float = -1.0
# En deçà de cet écart, la nouvelle valeur lissée ne change RIEN d'audible ni de visible : on
# économise un set_shader_parameter + un appel audio à chaque frame.
const WAR_INTENSITY_PUSH_EPSILON := 0.005

func _ready():
	button.pressed.connect(_on_debug_init)
	# §8.121 — début de la durée annoncée par la carte de partage (cf. _arena_entered_at).
	_arena_entered_at = Time.get_unix_time_from_system()

	# Audio §8.66 : on bascule de la musique de menu vers la MUSIQUE DE COMBAT tendue de l'arène
	# (lecteur unique → transition propre, plus de silence en jeu).
	AudioManager.start_battle_ambient()
	# §8.122 (LOT C) : ambiances DIÉGÉTIQUES de l'arène — vent du wasteland en continu + compteur
	# Geiger (muet tant que `set_zone_proximity` n'a pas annoncé de menace, cf. _refresh). Leur
	# extinction est prise en charge par AudioManager.start_menu_ambient (tous chemins de sortie).
	AudioManager.start_arena_ambience()

	NetworkManager.game_state_updated.connect(_on_state_updated)
	NetworkManager.game_event.connect(_on_game_event)
	NetworkManager.game_error.connect(_on_game_error)
	# Récompenses de fin de partie (points/XP/Coins, §8.47) → Rapport Post-Op animé.
	NetworkManager.match_over.connect(_on_match_over)
	NetworkManager.player_abandoned.connect(_on_player_abandoned)
	NetworkManager.spy_result.connect(_on_spy_result)
	# Chat de salle (§8.33) : envoi (HUD -> réseau) et réception (réseau -> HUD).
	NetworkManager.chat_message_received.connect(_on_chat_message)
	hud.chat_send_requested.connect(_on_chat_send)

	board.territory_clicked.connect(_on_territory_clicked)
	board.territory_right_clicked.connect(_on_territory_right_clicked)
	# Prévision de combat (G4 §8.63) : survol d'une cible en Phase 3 → probabilités affichées.
	board.territory_hovered.connect(_on_territory_hovered)
	board.territory_unhovered.connect(_on_territory_unhovered)
	hud.pass_pressed.connect(_on_pass_pressed)
	hud.card_played.connect(_on_card_played)
	hud.abandon_pressed.connect(_on_abandon_pressed)
	hud.deploy_confirmed.connect(_on_deploy_confirmed)
	# Fiche joueur (lot A) : flèches ◀ ▶ (et tout autre appelant historique du roster) → ouverture
	# de la fiche du joueur demandé + focus caméra sur son territoire le plus garni.
	hud.roster_player_clicked.connect(_on_roster_player_clicked)
	# Carte POUVOIR (lot E) : boutons contextuels (rouvrir Éclipse / Espionnage).
	hud.power_action_requested.connect(_on_power_action_requested)
	# PACTES (§8.123) : intentions du joueur (HUD → réseau) et messages PRIVÉS (réseau → HUD).
	# Les offres et les refus ne sont JAMAIS diffusés : ils n'arrivent que par ces deux signaux.
	hud.pact_offer_requested.connect(_on_pact_offer_requested)
	hud.pact_response_requested.connect(_on_pact_response_requested)
	NetworkManager.pact_offer_received.connect(_on_pact_offer_received)
	NetworkManager.pact_response_received.connect(_on_pact_response_received)
	# Chrono SERVEUR (E3 §8.75) : messages légers timer_update → HUD (échéance + Time Bank).
	NetworkManager.timer_updated.connect(_on_timer_update)
	# Journal de Guerre 2.0 (E4 §8.76) : clic d'une entrée [url=<tid>] → focus caméra + flash.
	hud.log_territory_clicked.connect(_on_log_territory_clicked)
	# Commandement fluide (E7 §8.79) : ré-assaut + raccourcis de quantité.
	hud.reassault_pressed.connect(_on_reassault_pressed)
	hud.amount_quick.connect(_on_amount_quick)
	# --- TUTORIEL / FTUE (§8.129) : ancres de surlignage + prise en main du coach. Purement
	# déclaratif — hors PREMIÈRE OPÉRATION, `bind_arena` est un no-op et rien ne s'affiche. Le HUD
	# lui-même est enregistré (`hud_root`) : le coach a besoin de lui appeler `open_objectives_tab`
	# avant de désigner le tracker, rangé dans une page d'onglet depuis le LOT 0. ---
	TutorialManager.register_anchor("hud_root", hud)
	TutorialManager.register_anchor("next_phase", hud.get_node_or_null("%NextPhaseButton"))
	TutorialManager.register_anchor("player_zone", hud.get_node_or_null("%PlayerZone"))
	TutorialManager.register_anchor("objective_tracker", hud.get_node_or_null("%InfoTabs"))
	TutorialManager.register_anchor("deploy_confirm", hud.get_deploy_confirm_button())
	TutorialManager.bind_arena(self, hud)

	# Bandeau de tour/phase (E3) : stinger haut-centre, déclenché par _maybe_show_banner().
	_phase_banner = PhaseBannerScene.instantiate()
	add_child(_phase_banner)

	# Coupure réseau VISIBLE (§8.118) : une fermeture WS non applicative laissait l'arène
	# silencieusement inerte — le joueur ne découvrait la panne qu'en cliquant. On la montre.
	NetworkManager.server_connection_lost.connect(_on_server_connection_lost)
	NetworkManager.server_connected.connect(_on_server_connection_restored)
	_build_net_overlay()

	# Fenêtre de déplacement post-conquête (déclarée dans main.tscn, masquée par défaut).
	%ConquerSlider.value_changed.connect(_on_conquer_slider_changed)
	%ConquerConfirm.pressed.connect(_on_conquer_confirmed)

	# Pop-ups des factions à états bloquants (§8.3, masquées par défaut).
	# Ordre de l'Éclipse : 2 gros boutons (clic = conserver cette carte).
	%EclipseCard0.pressed.connect(_on_eclipse_card_chosen.bind(0))
	%EclipseCard1.pressed.connect(_on_eclipse_card_chosen.bind(1))

	# Flux normal : on arrive avec un état déjà chargé -> on affiche et on masque le debug.
	if not GameState.territories.is_empty():
		button.hide()
		_refresh()
	else:
		button.text = tr("GAME_DEBUG_INIT")

	# Prévision de combat (G4 §8.63) : PRÉCHAUFFE la table DP au chargement de l'arène (~100 ms,
	# invisible ici) pour que le tout premier survol d'une grosse bataille soit instantané (< 1 ms,
	# tout est mémoïsé ensuite). Différé pour ne pas retarder le premier rendu de la scène.
	_warm_combat_odds.call_deferred()

# =========================================================
# Accès / helpers d'état
# =========================================================

# Annulation au clavier (E7 §8.79) : ESC (action ui_cancel, mappée par défaut) = désélection de
# la source d'attaque/mouvement — équivalent d'un clic dans le vide (réutilise _clear_source).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# §8.119 — ESC annule d'ABORD un ciblage de capacité en cours (le plus « modal » des deux
	# états), sinon la désélection d'attaque/mouvement historique.
	if _ability_target_mode != "":
		_cancel_ability_targeting(true)
		get_viewport().set_input_as_handled()
	elif _source != "":
		_clear_source()
		_update_instruction()
		get_viewport().set_input_as_handled()
	else:
		# §8.129 — TROISIÈME chemin d'accès au MANUEL DE GUERRE (les deux autres : PARAMÈTRES et
		# « EN SAVOIR PLUS » d'une bulle). L'arène n'a PAS de menu ÉCHAP — ESC n'y faisait
		# strictement rien quand aucune sélection n'était en cours. On occupe donc ce geste mort
		# plutôt que d'ajouter un bouton dans un HUD déjà dense, et ESC referme le Manuel : le
		# même geste ouvre et ferme, il n'y a rien à apprendre.
		TutorialManager.open_manual("")
		get_viewport().set_input_as_handled()

func _my_id() -> int:
	return AuthManager.user_id

func _terr(tid: String) -> Dictionary:
	return GameState.territories.get(tid, {})

func _owner(tid: String) -> int:
	var o = _terr(tid).get("owner_id")
	return int(o) if o != null else -1

func _garrison(tid: String) -> int:
	return int(_terr(tid).get("garrison", 0))

func _is_playing_my_turn() -> bool:
	return GameState.stage == "playing" and int(GameState.current_player_id) == _my_id()

# Phase 0 refondue (§8.31) : déploiement AVEUGLE & SIMULTANÉ — PLUS d'ordre setup_index. Le joueur
# local peut déployer tant qu'il est en placement, qu'il a encore un stock à poser, et qu'il n'a pas
# DÉJÀ soumis (verrou local _blind_submitted, le serveur masquant pending_blind_deploy dans l'état).
func _can_blind_deploy() -> bool:
	return GameState.stage == "placement" and not _blind_submitted and _deploy_quota() > 0

# État serveur du joueur LOCAL (les clés de GameState.players sont des STRINGS — JSON, §5).
func _my_state() -> Dictionary:
	var me = GameState.players.get(str(_my_id()), {})
	return me if typeof(me) == TYPE_DICTIONARY else {}

# Vrai si le joueur LOCAL est ÉLIMINÉ (mode observateur G3 §8.70) : il ne peut PLUS émettre
# d'action de jeu (le serveur refuse déjà, mais l'UI ne doit rien proposer). Défauts sûrs :
# jamais éliminé tant que l'état n'est pas synchronisé.
func _is_eliminated() -> bool:
	var me := _my_state()
	return str(me.get("status", "alive")) == "eliminated" or bool(me.get("is_dead", false))

# Vrai si une fenêtre modale bloquante est ouverte (conquête / Éclipse / espionnage) : le jeu
# local est alors figé, comme l'exige %ConquerDialog (§8.23) et les pop-ups de faction (§8.3).
# DURCI (G3 §8.70) : un ÉLIMINÉ ne peut JAMAIS émettre d'action de jeu (observateur pur).
func _input_blocked() -> bool:
	# Combat (correctif « double déduction de PV ») : tant qu'une attaque est EN VOL (envoyée, résultat
	# non revenu) OU que l'animation Split-Screen VS joue, on FIGE toute nouvelle action de jeu — un 2ᵉ
	# clic d'attaque partirait sinon sur un plateau figé (pré-combat) et le serveur résoudrait un 2ᵉ duel.
	return _awaiting_conquer_move or _awaiting_eclipse or _awaiting_spy or _is_eliminated() \
		or _combat_animating or _attack_in_flight

# =========================================================
# Clics sur le plateau
# =========================================================

func _on_territory_clicked(tid: String):
	# Fiche joueur (lot A) : informative — s'ouvre au clic de TOUT territoire possédé (la logique
	# de jeu suit en dessous, inchangée). Rétractable par son bouton-tiroir.
	_update_sheet_for_territory(tid)
	if GameState.winner_id != null:
		return
	# Jeu figé tant qu'une fenêtre modale (conquête §8.23, Éclipse/espionnage §8.3) est ouverte.
	if _input_blocked():
		return
	# §8.119 — CIBLAGE D'UNE CAPACITÉ armé : ce clic appartient au pouvoir, pas au jeu normal.
	# Une cible illégale annule proprement le ciblage (aucun envoi) au lieu d'être ignorée en
	# silence — le joueur comprend que son clic a été pris en compte et refusé.
	if _ability_target_mode != "":
		if _ability_targets(_ability_target_mode).has(tid):
			_send_ability(ABILITY_FACTION_POWER, tid)
		else:
			hud.add_log(tr("ABILITY_ERR_INVALID_TARGET"))
			_cancel_ability_targeting(true)
		return
	# Phases de déploiement (placement initial OU renforts Phase 2) : le clic gauche ALIMENTE le
	# tampon local (+1) au lieu d'envoyer au serveur — l'envoi se fait au clic « Confirmer » (§8.26).
	# Raccourcis quantité (E7 §8.79) : Shift = +5, Ctrl = MAX (tout le stock restant) sur le clic.
	if _in_deploy_mode():
		var step := 1
		if Input.is_key_pressed(KEY_CTRL):
			step = maxi(1, _deploy_quota() - _pending_total())
		elif Input.is_key_pressed(KEY_SHIFT):
			step = 5
		_buffer_add(tid, step)
		return
	if GameState.stage == "placement":
		hud.add_log(tr("GAME_NOT_YOUR_PLACEMENT"))
	elif GameState.stage == "playing":
		_handle_play_click(tid)

# Clic DROIT : retire une troupe en attente du tampon (-1), uniquement en mode déploiement (§8.26).
func _on_territory_right_clicked(tid: String):
	if GameState.winner_id != null or _input_blocked():
		return
	if _in_deploy_mode():
		_buffer_add(tid, -1)

func _handle_play_click(tid: String):
	if not _is_playing_my_turn():
		hud.add_log(tr("GAME_NOT_YOUR_TURN"))
		return
	match GameState.current_phase:
		3: _do_attack_click(tid)
		4: _do_move_click(tid)
		_:
			hud.add_log(tr("GAME_CLICK_NEXT_PHASE"))

# Arme le verrou « attaque en vol » + un filet de sécurité anti soft-lock : si le résultat ne revient
# jamais (message perdu / coupure-reconnexion), le verrou se lève après ATTACK_IN_FLIGHT_TIMEOUT. En
# temps normal, MON attack_result lève le verrou bien avant (via _on_game_event). La génération évite
# qu'un vieux timeout ne débloque une attaque ARMÉE ensuite (sinon on rouvrirait la fenêtre du bug).
func _arm_attack_in_flight() -> void:
	_attack_in_flight = true
	_attack_flight_gen += 1
	var gen := _attack_flight_gen
	get_tree().create_timer(ATTACK_IN_FLIGHT_TIMEOUT).timeout.connect(func() -> void:
		if _attack_flight_gen == gen:
			_attack_in_flight = false)

func _do_attack_click(tid: String):
	if _source == "":
		# Choix de la source : à moi, avec au moins 2 unités.
		if _owner(tid) == _my_id() and _garrison(tid) >= 2:
			_select_source(tid)
			hud.set_instruction(tr("GAME_ATTACK_PICK_TARGET"))
		else:
			hud.add_log(tr("GAME_INVALID_SOURCE"))
	else:
		if tid == _source:
			_clear_source()
			_update_instruction()
			return
		if _owner(tid) == _my_id():
			# On change de source si elle est valide, sinon on ignore.
			if _garrison(tid) >= 2:
				_select_source(tid)
			return
		# Adjacence (UX) : la cible doit être frontalière de la source. Le serveur re-valide.
		if not MapData.are_adjacent(_source, tid, GameState.map_id):
			hud.add_log(tr("GAME_TARGET_NOT_ADJACENT"))
			return
		# Combat VALIDÉ ici : source à moi (≥2 unités), cible ennemie adjacente (MapData).
		# La scène Split-Screen VS (affrontement des héros de factions) se joue à la
		# RÉCEPTION du résultat serveur (attack_result -> _play_combat_resolution), car
		# les jets de dés n'existent que dans la réponse du moteur.
		# Cible ennemie : on attaque avec le max de dés possibles (1-3).
		var dice = clampi(_garrison(_source) - 1, 1, 3)
		# Ré-assaut (E7 §8.79) : on mémorise ce couple pour rejouer l'assaut d'un clic.
		_last_attack = {"source": _source, "target": tid}
		NetworkManager.send_action("attack_territory", {
			"attacker_territory_id": _source,
			"defender_territory_id": tid,
			"attacker_dice": dice,
		})
		# Verrou immédiat : un seul « attack_territory » en vol par attaque VOULUE (anti double-clic).
		_arm_attack_in_flight()
		_clear_source()

# =========================================================
# Commandement fluide (E7 §8.79) — ré-assaut, raccourcis quantité, ESC
# =========================================================

# Ré-assaut d'un clic : rejoue le DERNIER assaut si toujours légal (re-testé à chaque état reçu
# par _refresh_reassault). Le serveur re-valide de toute façon.
func _on_reassault_pressed() -> void:
	if not _reassault_legal():
		return
	var src := str(_last_attack.get("source", ""))
	var tgt := str(_last_attack.get("target", ""))
	var dice = clampi(_garrison(src) - 1, 1, 3)
	NetworkManager.send_action("attack_territory", {
		"attacker_territory_id": src, "defender_territory_id": tgt, "attacker_dice": dice})
	_arm_attack_in_flight()  # même verrou anti double-envoi que l'attaque directe (ré-assaut E7 §8.79)
	hud.set_reassault(false)  # masque le bouton dès l'envoi (anti double-clic) — _refresh le ré-affiche si légal

# Le dernier assaut est-il encore rejouable ? Source à moi ≥ 2, cible toujours ennemie et
# adjacente, Phase 3, notre tour, aucune fenêtre bloquante.
func _reassault_legal() -> bool:
	if _last_attack.is_empty() or not _is_playing_my_turn() \
			or int(GameState.current_phase) != 3 or _input_blocked():
		return false
	var src := str(_last_attack.get("source", ""))
	var tgt := str(_last_attack.get("target", ""))
	if _owner(src) != _my_id() or _garrison(src) < 2:
		return false
	var to = _terr(tgt).get("owner_id")
	if to == null or int(to) == _my_id():
		return false
	return MapData.are_adjacent(src, tgt, GameState.map_id)

# Rafraîchit le bouton « RÉ-ASSAUT » selon la légalité courante (appelé depuis _refresh).
func _refresh_reassault() -> void:
	if _reassault_legal():
		hud.set_reassault(true, _territory_name(str(_last_attack.get("source", ""))),
			_territory_name(str(_last_attack.get("target", ""))))
	else:
		hud.set_reassault(false)

# Raccourci de quantité (E7 §8.79) : en Phase 4 (mouvement) ajuste %AmountSpin (+1/+5/MAX = tout
# le stock déplaçable de la source sélectionnée). Hors mouvement, sans effet ciblé (les
# déploiements passent par le clic-territoire Shift/Ctrl).
func _on_amount_quick(delta: int) -> void:
	if GameState.stage != "playing" or int(GameState.current_phase) != 4:
		return
	var spin: SpinBox = hud.get_node("%AmountSpin")
	if delta < 0:
		# MAX : garnison de la source − 1 (au moins 1 doit rester), sinon le plafond du spin.
		var maxv := int(spin.max_value)
		if _source != "":
			maxv = maxi(1, _garrison(_source) - 1)
		spin.value = maxv
	else:
		spin.value = min(spin.value + delta, spin.max_value)

func _do_move_click(tid: String):
	if _source == "":
		if _owner(tid) == _my_id() and _garrison(tid) >= 2:
			_select_source(tid)
			hud.set_instruction(tr("GAME_MOVE_PICK_TARGET"))
		else:
			hud.add_log(tr("GAME_INVALID_SOURCE"))
	else:
		if tid == _source:
			_clear_source()
			_update_instruction()
			return
		if _owner(tid) != _my_id():
			hud.add_log(tr("GAME_INVALID_DESTINATION"))
			return
		# Destination LÉGALE (UX ; le serveur reste juge, §4.2) : adjacente pour tout le monde —
		# ou, pour l'Éveil de la Ruche (`long_range_movement`), n'importe quel territoire allié
		# atteignable par une CHAÎNE alliée (miroir client de engine._has_friendly_path).
		# ⚠️ Correctif lot E : ce garde-fou refusait TOUTE destination non adjacente AVANT l'envoi,
		# ce qui rendait le pouvoir de la Ruche littéralement injouable alors que le serveur
		# l'acceptait déjà.
		if not _move_destination_legal(_source, tid):
			hud.add_log(tr("GAME_DEST_NO_CHAIN") if _has_long_range_movement()
				else tr("GAME_DEST_NOT_ADJACENT"))
			return
		NetworkManager.send_action("move_units", {
			"source_territory_id": _source,
			"target_territory_id": tid,
			"amount": maxi(1, hud.get_amount()),
		})
		_clear_source()

func _select_source(tid: String):
	_source = tid
	board.set_selected_source(tid)
	# Surlignage des cibles valides (E7 §8.79) : en Phase 3, on éclaire les cibles légales
	# (adjacentes ennemies) d'un liseré cramoisi + on désature le reste.
	# Lot E : MÊME surlignage en Phase 4 (mouvement) — indispensable pour la Ruche, dont les
	# destinations légales ne sont PAS visuellement évidentes (toute la chaîne alliée).
	if GameState.stage != "playing":
		return
	var phase := int(GameState.current_phase)
	if phase == 3:
		board.set_attack_context(tid, _valid_attack_targets(tid))
	elif phase == 4:
		board.set_attack_context(tid, _valid_move_targets(tid))

func _clear_source():
	_source = ""
	board.set_selected_source("")
	board.clear_attack_context()
	# Prévision de combat (G4 §8.63) : plus de source → plus de prévision affichable.
	hud.hide_forecast()

# Cibles d'attaque LÉGALES depuis une source (E7 §8.79) : territoires ADJACENTS (carte courante
# G5) appartenant à un AUTRE joueur. Mêmes règles que le serveur re-valide (§4.2). La garnison
# ≥ 2 est une contrainte de la SOURCE (vérifiée à sa sélection), pas des cibles.
func _valid_attack_targets(source_tid: String) -> Array:
	var out: Array = []
	for tid in MapData.neighbors_of(source_tid, GameState.map_id):
		var o = _terr(str(tid)).get("owner_id")
		if o != null and int(o) != _my_id():
			out.append(str(tid))
	return out

# =========================================================
# Mouvement stratégique (lot E) — chaîne alliée de l'Éveil de la Ruche
# =========================================================

# Ma faction possède-t-elle le mouvement longue distance (`long_range_movement`, §4.3) ?
func _has_long_range_movement() -> bool:
	var mods := _faction_modifiers(str(_my_state().get("faction", "")))
	return bool(mods.get("long_range_movement", false))

# Destinations LÉGALES d'un mouvement depuis `source_tid` : territoires À MOI, adjacents — ou
# TOUTE la chaîne alliée atteignable pour la Ruche. Miroir CLIENT de engine._has_friendly_path
# (BFS sur MapData.neighbors_of + owner_id) ; le serveur re-valide (§4.2), ceci n'est que de l'UX.
func _valid_move_targets(source_tid: String) -> Array:
	var out: Array = []
	if _has_long_range_movement():
		# BFS : on ne traverse QUE des territoires alliés (la source comprise), on collecte tous
		# ceux atteints sauf la source elle-même.
		var seen := {source_tid: true}
		var queue: Array = [source_tid]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			for n in MapData.neighbors_of(cur, GameState.map_id):
				var nid := str(n)
				if seen.has(nid):
					continue
				var o = _terr(nid).get("owner_id")
				if o == null or int(o) != _my_id():
					continue
				seen[nid] = true
				queue.append(nid)
				out.append(nid)
		return out
	for tid in MapData.neighbors_of(source_tid, GameState.map_id):
		var o2 = _terr(str(tid)).get("owner_id")
		if o2 != null and int(o2) == _my_id():
			out.append(str(tid))
	return out

# La destination est-elle légale pour un mouvement depuis `source_tid` ?
func _move_destination_legal(source_tid: String, target_tid: String) -> bool:
	if not _has_long_range_movement():
		return MapData.are_adjacent(source_tid, target_tid, GameState.map_id)
	return _valid_move_targets(source_tid).has(target_tid)

# =========================================================
# Prévision de combat (G4 §8.63) — survol d'une cible en Phase 3
# =========================================================

# Préchauffage de la DP (appelé une fois, différé, au chargement de l'arène) : calcule le pire
# cas SANS flags (60v60, la table couvre alors toutes les garnisons inférieures) + le couple de
# flags de MA faction contre chaque faction adverse présente (tables séparées par flags).
func _warm_combat_odds() -> void:
	var my_mods := _faction_modifiers(str(_my_state().get("faction", "")))
	CombatOdds.conquest_probability(CombatOdds.MAX_UNITS, CombatOdds.MAX_UNITS, {}, {})
	for k in GameState.players:
		var pdata: Dictionary = GameState.players.get(k, {})
		var fid := str(pdata.get("faction", ""))
		if fid != "":
			CombatOdds.conquest_probability(
				CombatOdds.MAX_UNITS, CombatOdds.MAX_UNITS, my_mods, _faction_modifiers(fid))

# Survol d'un territoire : si (mon tour, Phase 3, source sélectionnée, cible ENNEMIE adjacente),
# calcule la probabilité de conquête EXACTE côté client (CombatOdds, aucune requête réseau) et la
# pousse au HUD. Toute condition manquante → prévision masquée. Le calcul est mémoïsé (statique)
# → survol instantané (< 1 ms après le premier calcul d'un couple de garnisons).
func _on_territory_hovered(tid: String) -> void:
	if GameState.stage != "playing" or int(GameState.current_phase) != 3 \
			or not _is_playing_my_turn() or _input_blocked() or _source == "":
		hud.hide_forecast()
		return
	var owner = _owner(tid)
	if owner == null or int(owner) == _my_id():
		hud.hide_forecast()
		return
	if not MapData.are_adjacent(_source, tid, GameState.map_id):
		hud.hide_forecast()
		return
	var att_units := _garrison(_source)
	var def_units := _garrison(tid)
	if att_units < 2 or def_units < 1:
		hud.hide_forecast()
		return
	var atk_mods := _faction_modifiers(str(_my_state().get("faction", "")))
	var def_state: Dictionary = GameState.players.get(str(int(owner)), {})
	var def_mods := _faction_modifiers(str(def_state.get("faction", "")))
	var odds := CombatOdds.conquest_probability(att_units, def_units, atk_mods, def_mods)
	hud.show_forecast(float(odds.get("win_prob", 0.0)), float(odds.get("exp_att_losses", 0.0)))
	# Flèche d'intention (E7 §8.79) : source → cible survolée (complète la prévision G4).
	board.set_intent_arrow(tid)

func _on_territory_unhovered(_tid: String) -> void:
	hud.hide_forecast()
	board.clear_intent_arrow()

# Modificateurs de faction par id (miroir du registre backend §4.3), lus du .tres et mis en cache.
# Même scan robuste export-safe que _faction_info (.remap, duck-typing). {} si faction inconnue.
func _faction_modifiers(fid: String) -> Dictionary:
	if fid == "":
		return {}
	if _faction_mods_cache.has(fid):
		return _faction_mods_cache[fid]
	var mods: Dictionary = {}
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var fn := file_name
				if fn.ends_with(".remap"):
					fn = fn.trim_suffix(".remap")
				if fn.ends_with(".tres"):
					var full := FACTIONS_DIR + fn
					if ResourceLoader.exists(full):
						var res = load(full)
						if res != null and str(res.get("id")) == fid:
							var m = res.get("modifiers")
							if typeof(m) == TYPE_DICTIONARY:
								mods = m
							break
			file_name = dir.get_next()
		dir.list_dir_end()
	_faction_mods_cache[fid] = mods
	return mods

# =========================================================
# Tampon de déploiement local (§8.26) — placement initial & renforts Phase 2
# =========================================================

# Vrai si le joueur est en phase de DÉPLOIEMENT (clics = tampon local) : son tour de placement
# initial, OU sa Phase 2 (renforts) en cours de partie.
func _in_deploy_mode() -> bool:
	if GameState.winner_id != null or _input_blocked():
		return false
	# Placement (Phase 0) : tous les joueurs actifs remplissent leur tampon EN PARALLÈLE (§8.31).
	if GameState.stage == "placement":
		return _can_blind_deploy()
	# En partie : phase 2 (renforts), uniquement à mon tour.
	return _is_playing_my_turn() and int(GameState.current_phase) == 2

# Quota EXACT à placer = stock courant du joueur (tout le reste en placement, tous les renforts en
# Phase 2). Le bouton « Confirmer » ne s'active que lorsque la somme du tampon == ce quota.
func _deploy_quota() -> int:
	return int(_my_state().get("units_in_stock", 0))

func _pending_total() -> int:
	var s := 0
	for v in pending_deployments.values():
		s += int(v)
	return s

# Ajoute (delta>0 : +N, BORNÉ au stock restant — E7 §8.79 : Shift=+5, Ctrl=MAX) ou retire
# (delta<0 : −1) des troupes en attente sur un territoire ALLIÉ, sans dépasser le quota. Met à
# jour le plateau (badge "+X") et l'état du bouton « Confirmer ».
func _buffer_add(tid: String, delta: int) -> void:
	if _owner(tid) != _my_id():
		if delta > 0:
			hud.add_log(tr("GAME_DEPLOY_OWN_ONLY"))
		return
	var cur := int(pending_deployments.get(tid, 0))
	if delta > 0:
		var remaining := _deploy_quota() - _pending_total()
		if remaining <= 0:
			hud.add_log(tr("GAME_QUOTA_REACHED") % _deploy_quota())
			return
		cur += mini(delta, remaining)   # +1 / +5 / MAX (jamais au-delà du stock)
	else:
		cur -= 1
	if cur <= 0:
		pending_deployments.erase(tid)
	else:
		pending_deployments[tid] = cur
	board.set_pending_deployments(pending_deployments)
	_refresh_confirm_state()

# Met à jour l'état du bouton « Confirmer » (visible en mode déploiement avec quota > 0 ; activé
# uniquement quand la somme du tampon == quota).
func _refresh_confirm_state() -> void:
	var quota := _deploy_quota()
	if not _in_deploy_mode() or quota <= 0:
		hud.set_deploy_confirm(false)
		return
	hud.set_deploy_confirm(true, _pending_total(), quota)

func _clear_pending() -> void:
	pending_deployments.clear()
	board.set_pending_deployments({})
	_refresh_confirm_state()

# Clic sur « CONFIRMER LE DÉPLOIEMENT » : envoie le tampon complet en MASSE (action deploy_units),
# puis vide le tampon local. Le serveur revalide (somme == stock en placement, <= stock en Phase 2).
func _on_deploy_confirmed() -> void:
	if not _in_deploy_mode():
		return
	var quota := _deploy_quota()
	if _pending_total() != quota:
		hud.add_log(tr("GAME_DEPLOY_EXACT") % quota)
		return
	if pending_deployments.is_empty():
		return
	# Mémorise le tampon AVANT de le purger : restauré si le serveur refuse (correctif §8.48).
	_deploy_snapshot = pending_deployments.duplicate()
	_deploy_in_flight = true
	NetworkManager.send_action("deploy_units", {"deployments": pending_deployments.duplicate()})
	# Phase 0 (§8.31) : le déploiement est AVEUGLE — une fois soumis, on VERROUILLE localement le
	# choix (le serveur masque pending_blind_deploy ; le client fait foi de sa propre soumission) et
	# l'UI bascule en « attente des autres joueurs ». _clear_pending() masque alors « Confirmer »
	# (car _in_deploy_mode() devient faux) ; _update_instruction() affiche le message d'attente.
	if GameState.stage == "placement":
		_blind_submitted = true
	_clear_pending()
	_update_instruction()

# =========================================================
# Bouton "Fin de Phase"
# =========================================================

func _on_pass_pressed():
	if _pass_in_flight:
		hud.add_log(tr("GAME_ACTION_IN_PROGRESS"))
		return
	if _awaiting_conquer_move:
		hud.add_log(tr("GAME_CONQUER_FIRST"))
		return
	if _awaiting_eclipse:
		hud.add_log(tr("GAME_ECLIPSE_FIRST"))
		return
	if _awaiting_spy:
		hud.add_log(tr("GAME_SPY_FIRST"))
		return
	if GameState.stage != "playing":
		hud.add_log(tr("GAME_NOT_STARTED"))
		return
	if not _is_playing_my_turn():
		hud.add_log(tr("GAME_NOT_YOUR_TURN"))
		return
	_clear_source()
	# Verrou + désactivation immédiate du bouton : un seul pass_turn en vol par aller-retour serveur.
	_pass_in_flight = true
	hud.set_pass_enabled(false)
	# from_phase : le serveur rejette une 2ᵉ trame qui porterait l'ancienne phase (garde idempotente).
	NetworkManager.send_action("pass_turn", {"from_phase": GameState.current_phase})

# =========================================================
# Abandon (Fallen Empire)
# =========================================================

# Le joueur abandonne la partie : on transmet {"action": "abandon"} au serveur (enveloppe
# standard de send_action) ; le HUD a déjà demandé la confirmation (armement en 2 clics).
# Le serveur (§8.20) passe is_active=false, saute nos tours et laisse nos troupes en défense
# automatique, puis rediffuse "player_abandoned" (traité par _on_player_abandoned).
func _on_abandon_pressed():
	# On transmet l'abandon (le serveur fige nos troupes en défense auto, §8.20), on vide le
	# tampon d'envoi du socket (poll) pour garantir le départ du message, puis on coupe proprement
	# la connexion et on quitte l'arène vers le menu principal (directive UX — abandon = on sort).
	NetworkManager.send_action("abandon", {})
	NetworkManager.socket.poll()
	# Fermeture PROPRE via le manager (revue §8.116) : leave_room() recrée le WebSocketPeer (fix
	# STATE_CLOSING) — l'ancienne coupure à la main laissait un peer inutilisable et la recherche
	# suivante échouait en silence. (Si le message d'abandon n'était pas parti, le serveur traite de
	# toute façon la déconnexion dure comme un abandon, §8.31.)
	NetworkManager.leave_room()
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

# Vrai si le joueur LOCAL a abandonné (Fallen Empire) : lu dans l'état serveur diffusé.
# Les clés de GameState.players sont des STRINGS (JSON, cf. §5) ; défaut true = jamais
# considéré abandonné tant que l'état n'est pas synchronisé.
func _am_abandoned() -> bool:
	var me = GameState.players.get(str(_my_id()), {})
	return typeof(me) == TYPE_DICTIONARY and not bool(me.get("is_active", true))

# =========================================================
# Cartes
# =========================================================

func _on_card_played(card_index: int):
	if _input_blocked():
		return
	if not _is_playing_my_turn():
		hud.add_log(tr("GAME_CARD_TURN_ONLY"))
		return
	# Une carte = un nombre brut de troupes : on l'envoie directement par son index.
	# Le serveur retire la carte et crédite sa valeur au stock à déployer.
	NetworkManager.send_action("play_card", {"card_index": card_index})

# =========================================================
# Réactions aux messages serveur
# =========================================================

func _on_state_updated():
	# Le serveur a répondu : on lève les verrous « action en vol » (pass / déploiement acceptés).
	_pass_in_flight = false
	_deploy_in_flight = false
	# NOTE (correctif Bug C) : on NE lève PAS ici _attack_in_flight. _on_state_updated se déclenche pour
	# TOUT état diffusé — y compris un player_abandoned d'un AUTRE joueur pendant MON tour — ce qui
	# rouvrirait la fenêtre d'attaque AVANT le retour de MON résultat (2ᵉ attaque → 2ᵉ duel → double PV).
	# Le verrou est levé par _on_game_event à la réception de MON attack_result (puis _combat_animating
	# prend le relais pour l'animation), ou par _on_game_error si l'attaque est refusée.
	_clear_source()
	# Rafraîchissement DIFFÉRÉ d'une frame : le serveur émet game_state_updated PUIS
	# game_event dans le même message (network_manager.gd). Si l'évènement est un combat,
	# _on_game_event pose _combat_animating AVANT l'exécution différée -> le plateau reste
	# figé sur l'état pré-combat tant que le Split-Screen VS n'est pas terminé.
	_deferred_refresh.call_deferred()

func _deferred_refresh():
	if _combat_animating:
		_refresh_pending = true
		return
	_refresh()

func _on_game_event(event):
	# Journal de Guerre 2.0 (E4 §8.76) : parsing structuré (war_feed — catégories, [url=<tid>],
	# system_messages embarqués) + tics de zone DÉRIVÉS + kill feed (entrées majeures) + toast
	# défensif. Remplace l'ancien add_log(_format_event) — le texte legacy reste le repli (ctx).
	var entries: Array = WarFeed.parse(event, _feed_ctx(event))
	entries.append_array(WarFeed.zone_entries(_derive_zone_ticks(event)))
	hud.add_feed_entries(entries)
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and bool(e.get("major", false)):
			hud.push_kill_feed(str(e.get("rich_text", "")))
	_maybe_defense_toast(event)
	# Feedback sensoriel (E9 §8.81) : SFX + VFX ponctuels aux moments qui comptent.
	_play_event_feedback(event)
	# BATTLE ROYALE (§8.125) : mises en scène plein écran (caisse de ravitaillement, alarme de
	# trahison). Placées ICI, sur le flux d'évènements générique, pour qu'elles se jouent aussi
	# quand l'action vient d'un ADVERSAIRE ou d'un bot — une caisse qu'on ne verrait que quand on
	# l'ouvre soi-même ne serait plus un évènement d'équipe, et une alarme que la victime seule
	# entendrait raterait complètement son but.
	_play_battle_royale_feedback(event)
	# Phase 0 (§8.31) : suivi du compteur « X/Y joueurs ont validé » pour l'affichage d'attente
	# (le rafraîchissement d'état différé qui suit appellera _update_instruction avec ces valeurs).
	if typeof(event) == TYPE_DICTIONARY and str(event.get("event_type", "")) == "blind_deploy_submitted":
		_blind_ready = int(event.get("ready_count", _blind_ready))
		_blind_expected = int(event.get("expected_count", _blind_expected))
	if typeof(event) == TYPE_DICTIONARY and str(event.get("event_type", "")) == "attack_result":
		# Correctif Bug C : MON attack_result est revenu → on lève le verrou anti double-attaque (le
		# relais est assuré par _combat_animating que pose _play_combat_resolution juste après). Sans
		# effet pour un combat d'un AUTRE joueur/bot (mon verrou était déjà faux) — donc inoffensif.
		_attack_in_flight = false
		# Time Bank (§8.33) : le serveur a déjà repoussé l'échéance du tour courant (extend_deadline,
		# plafond 90 s). On répercute le MÊME bonus sur le rebours LOCAL du HUD AVANT de lancer le
		# Split-Screen VS — sinon, pendant l'animation, le compteur croit le temps écoulé alors que le
		# backend attend encore (désync §8.33). Appliqué sur TOUS les clients (le compteur affiché est
		# celui du tour courant, commun à tous), pas seulement l'attaquant local.
		var time_bonus := int(event.get("time_bank_bonus_seconds", 0))
		if time_bonus > 0:
			hud.add_time_to_timer(time_bonus)
		await _play_combat_resolution(event)
	# Rythme des tours adverses (lot C) : les actions NON-combat d'un adversaire sont mises en file
	# et racontées une par une (toast + flash du territoire) au lieu d'apparaître d'un bloc.
	_maybe_pace_event(event)
	_maybe_focus_combat(event)
	# Après l'animation de combat et le recadrage, on propose éventuellement la répartition
	# des troupes sur le territoire conquis (uniquement pour l'attaquant local, §8.23).
	_maybe_prompt_conquer(event)

# =========================================================
# Déplacement post-conquête (§8.23) — fenêtre de répartition des troupes
# =========================================================

# Affiche la fenêtre de répartition UNIQUEMENT pour le joueur LOCAL qui vient de conquérir un
# territoire ET qui a un vrai choix à faire (conquer_pending posé par le serveur).
func _maybe_prompt_conquer(event) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	if str(event.get("event_type", "")) != "attack_result":
		return
	if not bool(event.get("conquered", false)) or not bool(event.get("conquer_pending", false)):
		return
	# Partie gagnée par cette conquête : l'écran de victoire prime, pas de répartition.
	if GameState.winner_id != null:
		return
	# L'attaquant est toujours le joueur courant : on ne montre la fenêtre qu'à lui.
	if int(GameState.current_player_id) != _my_id():
		return
	_show_conquer_dialog({
		"from": str(event.get("conquer_from", "")),
		"to": str(event.get("conquer_to", "")),
		"min": int(event.get("conquer_min", 1)),
		"max": int(event.get("conquer_max", 1)),
	})

func _show_conquer_dialog(ctx: Dictionary) -> void:
	_awaiting_conquer_move = true
	_conquer_ctx = ctx
	%ConquerInfo.text = tr("GAME_CONQUER_INFO_FMT") % [
		_territory_name(ctx["to"]), _territory_name(ctx["from"])]
	%ConquerSlider.min_value = ctx["min"]
	%ConquerSlider.max_value = ctx["max"]
	%ConquerSlider.step = 1
	%ConquerSlider.value = ctx["max"]
	_update_conquer_value(int(ctx["max"]))
	%ConquerDialog.visible = true

func _on_conquer_slider_changed(value: float) -> void:
	_update_conquer_value(int(value))

func _update_conquer_value(v: int) -> void:
	# La source conserve (total - v) troupes ; total = max + 1 (car max = total - 1).
	var remaining: int = int(_conquer_ctx.get("max", 0)) + 1 - v
	%ConquerValue.text = tr("GAME_CONQUER_VALUE_FMT") % [v, remaining]

func _on_conquer_confirmed() -> void:
	if _conquer_ctx.is_empty():
		return
	var troops := int(%ConquerSlider.value)
	NetworkManager.send_action("conquer_move", {
		"from_tid": _conquer_ctx["from"],
		"to_tid": _conquer_ctx["to"],
		"troops": troops,
	})
	%ConquerDialog.visible = false
	_awaiting_conquer_move = false
	_conquer_ctx = {}

# =========================================================
# Pop-ups des factions à états bloquants (§8.3)
# =========================================================

# Ordre de l'Éclipse : si le serveur a posé 2 cartes Événement dans notre état
# (pending_eclipse_choice), on affiche la fenêtre de choix (2 gros boutons). Le clic envoie
# keep_card. Appelée à chaque rafraîchissement d'état (idempotente via _awaiting_eclipse).
func _maybe_prompt_eclipse() -> void:
	if GameState.winner_id != null:
		return
	var choices: Array = _my_state().get("pending_eclipse_choice", [])
	if choices.size() < 2:
		if _awaiting_eclipse:
			_awaiting_eclipse = false
			%EclipseDialog.visible = false
		return
	if _awaiting_eclipse:
		return  # déjà affichée
	_awaiting_eclipse = true
	%EclipseCard0.text = "+%d" % int(choices[0])
	%EclipseCard1.text = "+%d" % int(choices[1])
	%EclipseDialog.visible = true

func _on_eclipse_card_chosen(index: int) -> void:
	if not _awaiting_eclipse:
		return
	NetworkManager.send_action("keep_card", {"card_index": index})
	%EclipseDialog.visible = false
	_awaiting_eclipse = false

# Chasseurs d'Ombres : si le serveur a activé pending_spy_choice dans notre état, on affiche la
# fenêtre d'espionnage (un bouton par adversaire). Le clic envoie spy_objective.
func _maybe_prompt_spy() -> void:
	if GameState.winner_id != null:
		return
	if not bool(_my_state().get("pending_spy_choice", false)):
		if _awaiting_spy:
			_awaiting_spy = false
			%SpyDialog.visible = false
		return
	if _awaiting_spy:
		return  # déjà affichée
	_awaiting_spy = true
	_populate_spy_buttons()
	%SpyDialog.visible = true

func _populate_spy_buttons() -> void:
	var box: VBoxContainer = %SpyButtonsBox
	for child in box.get_children():
		child.queue_free()
	# Un bouton par adversaire (ids triés pour un ordre stable, cohérent avec player_number).
	var ids: Array = []
	for k in GameState.players.keys():
		ids.append(int(k))
	ids.sort()
	for pid in ids:
		if pid == _my_id():
			continue
		var btn := Button.new()
		btn.text = "◎ %s" % _display_name(pid)
		btn.custom_minimum_size = Vector2(380, 50)
		btn.add_theme_font_size_override("font_size", 18)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_spy_target_chosen.bind(pid))
		box.add_child(btn)

func _on_spy_target_chosen(target_id: int) -> void:
	if not _awaiting_spy:
		return
	NetworkManager.send_action("spy_objective", {"target_player_id": target_id})
	%SpyDialog.visible = false
	_awaiting_spy = false

# Réponse PRIVÉE du serveur à l'espionnage (reçue uniquement par l'espion, §8.3). Affichée dans
# le chat "Privé" ET le journal militaire — le secret n'est pas diffusé. Unification E1 : pseudo
# de la cible en couleur plateau (_bb_pseudo) ; la description est ÉCHAPPÉE (elle peut contenir
# le pseudo d'un joueur — objectif « éliminer X » — donc des « [ » hostiles, piège n° 1).
func _on_spy_result(target_player_id: int, description: String, objective: Dictionary) -> void:
	# i18n (§8.104) : libellé COMPOSÉ localement depuis la forme structurée {type, params} —
	# repli sur la description serveur (anglais invariant) si le serveur ne l'envoie pas encore.
	var txt := _objective_text(objective, description)
	# MODE STREAMER (§8.121, LOT E) : le renseignement est aussi sensible que MON objectif — il
	# passe donc par la MÊME plaque « maintenir pour révéler » (zone OBJECTIFS), et le chat/Journal
	# ne reçoivent qu'une ligne NEUTRE. Écrire l'objectif espionné en clair dans un journal
	# défilant aurait rouvert exactement la fuite que ce mode ferme (une ligne de journal ne peut
	# pas se « maintenir pour révéler »).
	if hud.is_intel_masked():
		hud.set_spy_intel("%s — %s" % [_display_name(target_player_id), txt])
		var masked := tr("GAME_SPY_RESULT_FMT") % [
			_bb_pseudo(target_player_id), tr("INTEL_CLASSIFIED_SHORT")]
		hud.add_chat_message("general", masked)
		hud.add_log(masked)
		return
	var line := tr("GAME_SPY_RESULT_FMT") % [
		_bb_pseudo(target_player_id), txt.replace("[", "[lb]")]
	# Lot B : le renseignement est un message SYSTÈME local (aucun envoi réseau) — il s'affiche
	# dans le canal général du chat, marqué « SYSTÈME », et dans le Journal de Guerre.
	hud.add_chat_message("general", line)
	hud.add_log(line)

# Libellé d'un objectif RÉVÉLÉ (espionnage / fin de partie) dans la langue courante : composé
# depuis `objective` ({type, params, volets} — §8.104), avec résolution du pseudo de la cible du
# volet « tuer ». Repli sur `fallback` (description serveur en anglais invariant) si la forme
# structurée est absente (serveur antérieur) ou d'un type inconnu.
func _objective_text(objective: Dictionary, fallback: String) -> String:
	if objective.is_empty():
		return fallback
	var params = objective.get("params", {})
	var target_name := ""
	if typeof(params) == TYPE_DICTIONARY and params.get("target_id") != null:
		var tid := int(params.get("target_id"))
		if GameState.players.has(str(tid)):
			target_name = _display_name(tid)
	var out := ObjectiveTracker.describe(objective, target_name)
	return out if out != "" else fallback

# =========================================================
# Chat de salle (§8.33) — Général / Privé (l'onglet « Alliés » est abandonné, chacun-pour-soi)
# =========================================================
# Le HUD est une VIEW pure : il émet chat_send_requested avec son canal INTERNE ("general"/"prive").
# Le contrat réseau, lui, parle "general"/"private" → on traduit ici (dans les deux sens).

# Envoi : le joueur a validé un message dans le HUD. On traduit le canal puis on relaie au réseau.
func _on_chat_send(channel: String, text: String, target_id: int) -> void:
	# « team » (MODE ÉQUIPES §8.124) traverse tel quel : c'est déjà le nom du canal côté contrat.
	var net_tab := "general"
	if channel == "prive":
		net_tab = "private"
	elif channel == "team":
		net_tab = "team"
	NetworkManager.send_chat_message(net_tab, text, target_id)

# Réception : message ESTAMPILLÉ par le serveur (sender_id/sender_name réels, §8.33). On colore le
# pseudo à la couleur de faction de l'expéditeur et on ÉCHAPPE le texte ET le pseudo (anti-injection
# BBCode — le message d'un autre joueur ne doit jamais interpréter de balises).
# Lot B — ROUTAGE PAR CONVERSATION : un privé va TOUJOURS dans le fil du CORRESPONDANT (l'autre
# joueur), que je sois l'expéditeur (écho de mon envoi : sender_id == moi → le correspondant est
# target_id) ou le destinataire (le correspondant est sender_id). L'expéditeur est TOUJOURS
# affiché, y compris pour mes propres messages (« MOI » traduit).
func _on_chat_message(tab: String, sender_id: int, sender_name: String, text: String, target_id: int) -> void:
	var esc_text := text.replace("[", "[lb]")
	var mine: bool = sender_id == _my_id()
	var who: String = hud.color_pseudo(tr("CHAT_ME"), board.get_player_color(_my_id())) if mine \
		else hud.color_pseudo(sender_name.replace("[", "[lb]"), board.get_player_color(sender_id))
	var conv_key := "general"
	if tab == "private":
		conv_key = str(target_id if mine else sender_id)
	elif tab == "team":
		# MODE ÉQUIPES (§8.124) : le canal d'équipe a SA propre conversation — le verser dans le
		# général mélangerait un message destiné à deux personnes avec ceux vus par toute la table,
		# et le joueur croirait avoir parlé en public (ou l'inverse).
		conv_key = "team"
	# Un message que J'ENVOIE ne doit jamais me notifier moi-même (badge/toast/son).
	hud.push_chat_message(conv_key, who, esc_text, not mine)

# Destinataires du chat (§8.33 — lot B) : uniquement les AUTRES joueurs HUMAINS (les bots ne
# parlent pas), résolus en pseudo + couleur plateau (le HUD reste une View pure §6.1). L'item
# « Tous » est ajouté par le HUD. Poussée à chaque refresh (la compo de salle est stable).
func _push_chat_targets() -> void:
	var entries := []
	var ids: Array = []
	for key in GameState.players.keys():
		ids.append(int(key))
	ids.sort()
	for pid in ids:
		if pid == _my_id():
			continue
		var p: Dictionary = GameState.players.get(str(pid), {})
		if pid < 0 or bool(p.get("is_bot", false)):
			continue
		entries.append({
			"id": pid,
			"name": _display_name(pid),
			"color": board.get_player_color(pid),
		})
	hud.set_chat_targets(entries)

func _territory_name(tid: String) -> String:
	# i18n (2026-07-18) : libellé TRADUIT via MapData (clé TERR_<ID>, repli nom FR historique).
	return MapData.t_name(tid)

# Nom AFFICHABLE d'une faction par id (EN invariant du .tres) — repli sur l'id brut. Consommé
# par le War Feed pour traduire les évènements système structurés (zone_protected).
func _faction_display_name(fid: String) -> String:
	var n := str(_faction_info(fid).get("name", ""))
	return n if n != "" else fid

# Nom à afficher pour un joueur : son VRAI pseudo, désormais diffusé par le serveur dans chaque
# PlayerState (§8.28). Replis successifs : notre pseudo local (AuthManager) si c'est nous, sinon
# "Joueur N" (numéro séquentiel 1..N) si l'identité n'a pas pu être résolue côté serveur.
# §8.126 — le TAG DE COMPAGNIE préfixe le pseudo, et il le fait ICI : ce résolveur alimente le
# journal, les toasts, le kill feed, le Split-Screen VS et le Rapport Post-Op. Le poser une fois à la
# source, c'est le voir apparaître dans les six d'un coup ; le poser à chaque appelant, c'est en
# oublier un. `GameState.tagged_name` est la SOURCE UNIQUE de sa forme, et rend le pseudo INCHANGÉ
# quand le joueur n'a pas de compagnie (bots compris) — aucune garde à écrire ailleurs.
func _display_name(pid: int) -> String:
	# Bot de remplissage (G2 §8.72) : id NÉGATIF → préfixe « [IA] » (l'état public porte is_bot ET
	# l'indicatif dans username ; le préfixe est posé ICI, côté client, comme prévu au contrat).
	var p = GameState.players.get(str(pid), {})
	var is_bot: bool = pid < 0 or (typeof(p) == TYPE_DICTIONARY and bool(p.get("is_bot", false)))
	if typeof(p) == TYPE_DICTIONARY:
		var uname := str(p.get("username", ""))
		if uname != "":
			return GameState.tagged_name(pid,
				(tr("COMMON_AI_PREFIX") + uname) if is_bot else uname)
	if pid == _my_id() and AuthManager.username != "":
		return GameState.tagged_name(pid, AuthManager.username)
	if is_bot:
		return tr("COMMON_AI_PREFIX") + tr("CHIP_BOT_FALLBACK") % absi(pid)
	return GameState.tagged_name(pid, tr("WR_PLAYER_FALLBACK") % GameState.player_number(pid))

# Pseudo PRÊT pour le BBCode (journal militaire / chat) — unification E1 §8.73 : résolu
# (_display_name), échappé « [ » → « [lb] » (anti-injection §8.33 ; le préfixe [IA] des bots
# reste rendu tel quel) puis colorisé à la couleur PLATEAU du joueur (board.get_player_color,
# source unique). Généralisation du pattern historique de _on_chat_message : TOUT pseudo injecté
# dans un RichTextLabel passe par ici.
func _bb_pseudo(pid) -> String:
	var pseudo := _display_name(int(pid)).replace("[", "[lb]")
	return hud.color_pseudo(pseudo, board.get_player_color(int(pid)))

# NB (lot A) : l'ancien tooltip « Pouvoir de Faction » de la TopBar (et son cache dédié
# _local_faction_info / _faction_desc_text) est SUPPRIMÉ — le pouvoir de MA faction s'affiche
# désormais en clair dans la zone JOUEUR de la barre basse, et celui de chaque adversaire dans
# la fiche joueur. Tout passe par _faction_info(fid), source unique déjà en cache.

# Infos de faction par id (nom + description + résumé du pouvoir passif), lues du .tres et mises en
# cache. Sert au tiroir « INTEL : FACTIONS » (§2). Scan robuste export-safe (.remap), duck-typing.
func _faction_info(fid: String) -> Dictionary:
	if fid == "":
		return {"name": "", "description": "", "power": ""}
	if _faction_full_cache.has(fid):
		return _faction_full_cache[fid]
	var info := {"name": "", "description": "", "power": "", "hero_path": ""}
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var fn := file_name
				if fn.ends_with(".remap"):
					fn = fn.trim_suffix(".remap")
				if fn.ends_with(".tres"):
					var full := FACTIONS_DIR + fn
					if ResourceLoader.exists(full):
						var res = load(full)
						if res != null and str(res.get("id")) == fid:
							var desc := str(res.get("description"))
							# §8.100 — hero_path AUSSI mis en cache (portrait du panneau héros du
							# Rapport Post-Op). Duck-typing défensif : null si champ absent → "".
							var hp = res.get("hero_path")
							# i18n (2026-07-18) : pouvoir passif via power_key traduite (repli
							# legacy : parsing de l'ancienne description). « leader » = identité du
							# meneur (rang traduit + nom invariant) pour le rapport/les tiroirs.
							var pk = res.get("power_key")
							var power_txt := tr(str(pk)) if (pk != null and str(pk) != "") \
								else _extract_power(desc)
							info = {"name": str(res.get("name")), "description": desc,
								"power": power_txt,
								"hero_path": str(hp) if hp != null else "",
								"leader": WarzoneUI.faction_leader_title(res)}
							break
			file_name = dir.get_next()
		dir.list_dir_end()
	_faction_full_cache[fid] = info
	return info

# Résumé du pouvoir passif : portion après « Pouvoir » de la description (BBCode strippé), repli sur
# la description nettoyée complète si le motif est absent.
func _extract_power(desc: String) -> String:
	var clean := desc.replace("[b]", "").replace("[/b]", "").replace("[i]", "").replace("[/i]", "")
	var idx := clean.findn("Pouvoir")
	if idx >= 0:
		var tail := clean.substr(idx)
		var colon := tail.find(":")
		if colon >= 0:
			tail = tail.substr(colon + 1)
		return tail.strip_edges()
	return clean.strip_edges()

# FICHE JOUEUR (lot A) — un clic sur N'IMPORTE QUEL territoire ouvre la fiche de son PROPRIÉTAIRE,
# avec en bas le bloc TERRITOIRE cliqué. Territoire NEUTRE (owner_id null) : aucun joueur à
# afficher → on garde la fiche courante et on n'ouvre rien (le badge du plateau porte déjà l'info).
# Remplace les 3 anciens panneaux (Inspecteur de Territoire, inspecteur héros adverse, panneau
# héros local) — une seule fiche, un seul endroit où lire « qui possède quoi ».
# ⚠️ RENOMMÉE de `_open_player_sheet_for_territory` (§8.125) : elle n'OUVRE plus le tiroir, elle
# ne fait que le REMPLIR. Garder le mot « open » dans le nom aurait conduit le prochain lecteur
# à y rebrancher une ouverture — c'est exactement le défaut qu'on vient de corriger deux fois.
func _update_sheet_for_territory(tid: String) -> void:
	# Propriétaire RÉEL du territoire : seul null = NEUTRE. owner_id peut être NÉGATIF (bot
	# G2 §8.72) — l'ancien test `>= 0` classait à tort les territoires de bots comme neutres.
	var raw_owner = _terr(tid).get("owner_id")
	if raw_owner == null:
		return
	_sheet_territory = tid
	_push_player_sheet(int(raw_owner))

# Compose et pousse la fiche d'un joueur (View pure §6.1 : TOUT est résolu ici). `pid` = joueur
# affiché ; `_sheet_territory` = territoire cliqué à détailler en bas de fiche ("" = aucun).
# ⚠️ NE DÉPLOIE JAMAIS le tiroir de gauche (§8.125) : elle ne fait que composer son CONTENU. Le
# panneau n'obéit qu'à son propre bouton ◀/▶ — cliquer un territoire met donc la fiche à jour
# SANS rien ouvrir, et le joueur la trouvera prête quand il décidera de regarder.
func _push_player_sheet(pid: int) -> void:
	if not GameState.players.has(str(pid)):
		return
	_sheet_pid = pid
	var p: Dictionary = GameState.players.get(str(pid), {})
	var fid := str(p.get("faction", ""))
	var finfo := _faction_info(fid)
	var fname := str(finfo.get("name", ""))
	if fname == "":
		fname = fid.capitalize() if fid != "" else tr("GAME_FACTION_UNKNOWN")
	# Statut public : éliminé > abandon (Fallen Empire §8.20) > vivant.
	var status_key := "HUD_SHEET_STATUS_ALIVE"
	if str(p.get("status", "alive")) == "eliminated" or bool(p.get("is_dead", false)):
		status_key = "HUD_SHEET_STATUS_DEAD"
	elif not bool(p.get("is_active", true)):
		status_key = "HUD_SHEET_STATUS_ABANDONED"
	# Troupes totales + territoires possédés (comptage direct de l'état public).
	var terr_count := 0
	var troops := 0
	for t_id in GameState.territories:
		var t: Dictionary = GameState.territories.get(t_id, {})
		var o = t.get("owner_id")
		if o != null and int(o) == pid:
			terr_count += 1
			troops += int(t.get("garrison", 0))
	var cards_n := 0
	var hand = p.get("cards_in_hand", [])
	if typeof(hand) == TYPE_ARRAY:
		cards_n = (hand as Array).size()
	var data := {
		"pid": pid,
		"pseudo": _display_name(pid),
		"color": board.get_player_color(pid),
		"faction_name": fname,
		"leader": str(finfo.get("leader", "")),
		"power_text": str(finfo.get("power", "")),
		"status_key": status_key,
		"hero": GameState.hero_of(pid),
		"territories": terr_count,
		"troops": troops,
		"cards": cards_n,
		# PACTES (§8.123) — bloc résolu ICI (View pure §6.1) ; {} sur ma propre fiche.
		"pact": _pact_sheet_block(pid),
	}
	if _sheet_territory != "" and GameState.territories.has(_sheet_territory):
		data["territory"] = {
			"name": _territory_name(_sheet_territory),
			"garrison": _garrison(_sheet_territory),
			"contaminated": board.is_contaminated(_sheet_territory),
		}
	hud.set_player_sheet(data)

# Clic d'une flèche ◀ ▶ de la fiche (ou de tout appelant historique du roster E1 §8.73) : la fiche
# bascule sur ce joueur (SANS bloc territoire — on change de belligérant, pas de zone) et la caméra
# se focalise sur son territoire le plus garni.
func _on_roster_player_clicked(pid: int) -> void:
	_sheet_territory = ""
	_push_player_sheet(pid)
	# Territoire le plus garni du joueur — aucun territoire (éliminé rasé) → pas de focus.
	var best_tid := ""
	var best_garrison := -1
	for tid in GameState.territories:
		var t: Dictionary = GameState.territories.get(tid, {})
		var o = t.get("owner_id")
		if o != null and int(o) == pid and int(t.get("garrison", 0)) > best_garrison:
			best_garrison = int(t.get("garrison", 0))
			best_tid = str(tid)
	if best_tid == "":
		return
	var pos: Vector2 = board.get_territory_position(best_tid)
	if pos == Vector2.INF:
		return
	camera.focus_on_combat(pos, pos)
	get_tree().create_timer(2.5).timeout.connect(camera.reset_view)

# Rafraîchit en TEMPS RÉEL la fiche joueur ouverte (PV/PP/territoires changent après un combat) :
# re-pousse les données publiques du joueur affiché à chaque mise à jour d'état (appelé par _refresh).
func _refresh_player_sheet() -> void:
	if _sheet_pid == -9999:
		return
	if not GameState.players.has(str(_sheet_pid)):
		_sheet_pid = -9999
		return
	_push_player_sheet(_sheet_pid)

# Ordre de navigation de la fiche (flèches ◀ ▶) : rotation d'Initiative (turn_order), VIVANTS
# d'abord puis éliminés — même tri stable que l'ancien Roster de Guerre (helper partagé).
func _push_sheet_players() -> void:
	var order: Array = RosterHelpers.sorted_pids(GameState.players, GameState.turn_order)
	var alive: Array = []
	var down: Array = []
	for pid in order:
		var p: Dictionary = GameState.players.get(str(int(pid)), {})
		if str(p.get("status", "alive")) == "eliminated" or bool(p.get("is_dead", false)):
			down.append(int(pid))
		else:
			alive.append(int(pid))
	hud.set_sheet_players(alive + down)

# Zone JOUEUR de la barre basse (lot A) : MOI — identité, pouvoir de faction (libellé + ligne
# d'état vivante résolue au lot E) et 4 barres PV/PA/PB/PP. View pure §6.1.
func _push_player_panel() -> void:
	var fid := str(_my_state().get("faction", ""))
	var finfo := _faction_info(fid)
	var fname := str(finfo.get("name", ""))
	if fname == "":
		fname = fid.capitalize() if fid != "" else tr("GAME_FACTION_UNKNOWN")
	hud.set_player_panel({
		"pid": _my_id(),
		"pseudo": _display_name(_my_id()),
		"color": board.get_player_color(_my_id()),
		"faction_name": fname,
		"leader": str(finfo.get("leader", "")),
		"power_label": str(finfo.get("power", "")),
		"power_state": _power_state_line(),
		"hero": GameState.hero_of(_my_id()),
		# PACTES (§8.123) : « ↔ NOM (R5) · ↔ NOM (R6) » — "" si je n'ai aucun engagement.
		"pacts_line": _my_pacts_line(),
	})

# =========================================================
# PACTES DE NON-AGRESSION (§8.123) — proposer, répondre, voir, trahir
# =========================================================
# Le CLIENT ne décide RIEN : le serveur est seul juge de la légalité d'une offre (§6.1). Tout ce
# qui suit est de la LISIBILITÉ — griser un bouton en disant pourquoi, marquer les chips, raconter
# une trahison. Un désaccord entre ce grisage et le serveur ne produit qu'un refus propre.

# Id du pacte dont le toast d'offre est affiché, pour ne pas le rejouer à chaque rediffusion d'état.
var _pact_toast_shown: int = -1
# DERNIÈRE famille d'action susceptible d'être refusée avec un CODE ("pact" | "ability" | "").
# POURQUOI : les deux jeux de codes se CHEVAUCHENT (`not_your_turn`, `invalid_target`,
# `ranked_disabled`) et le message `{"type":"error"}` ne dit pas quelle action il refuse. On mémorise
# donc l'émetteur au moment de l'envoi, et `_on_game_error` le CONSOMME (remis à "") — un marqueur
# périmé est impossible à conserver, le prochain envoi l'écrase de toute façon.
var _last_coded_action: String = ""

# Codes de refus du serveur → clés i18n (§8.123). Jeu FERMÉ, miroir exact de `pacts.REASON_*` : un
# code inconnu (client plus ancien que le serveur) retombe sur le message serveur, jamais sur du
# vide. Même patron que `ABILITY_ERROR_KEYS` (§8.119).
const PACT_ERROR_KEYS := {
	"not_your_turn": "PACT_ERR_NOT_YOUR_TURN",
	"invalid_target": "PACT_ERR_INVALID_TARGET",
	"pair_busy": "PACT_ERR_PAIR_BUSY",
	"cap_reached": "PACT_ERR_CAP_REACHED",
	"cooldown": "PACT_ERR_COOLDOWN",
	"final_protocol": "PACT_ERR_FINAL_PROTOCOL",
	"not_pending": "PACT_ERR_NOT_PENDING",
	"ranked_disabled": "PACT_ERR_RANKED_DISABLED",
}

# Bloc PACTE de la fiche d'un joueur ({} = rien à afficher : moi-même, ou joueur inconnu).
func _pact_sheet_block(pid: int) -> Dictionary:
	if pid == _my_id() or pid == -9999:
		return {}
	var pacts: Array = GameState.pacts
	var me := _my_id()
	var active := PactState.find_active_between(pacts, me, pid)
	if not active.is_empty():
		return {"pid": pid, "state": "active",
			"expires_at_round": int(active.get("expires_at_round", 0))}

	var d := {"pid": pid, "state": "none", "enabled": false, "reason_key": "", "reason_arg": 0,
		"duration_rounds": PACT_DURATION_ROUNDS}
	# Offre déjà en vol entre nous : le bouton devient un accusé de réception (dans un sens) ou
	# reste grisé (dans l'autre — c'est le toast qui porte alors la décision).
	var outgoing := PactState.outgoing_offer(pacts, me)
	if not outgoing.is_empty() and PactState.partner_of(outgoing, me) == pid:
		d["state"] = "sent"
		return d
	if PactState.has_pending_between(pacts, me, pid):
		d["reason_key"] = "PACT_ERR_PAIR_BUSY"
		return d

	# --- Raisons de grisage, dans le MÊME ordre que le serveur (`pacts.can_offer`) : le joueur
	# lit donc toujours la raison que le serveur lui opposerait s'il forçait le clic.
	var target: Dictionary = GameState.players.get(str(pid), {})
	if str(target.get("status", "alive")) == "eliminated" or not bool(target.get("is_active", true)):
		d["reason_key"] = "PACT_ERR_INVALID_TARGET"
		return d
	if not _is_playing_my_turn() or int(GameState.current_phase) < 1 \
			or int(GameState.current_phase) > 4:
		d["reason_key"] = "PACT_ERR_NOT_YOUR_TURN"
		return d
	if GameState.final_protocol_active:
		d["reason_key"] = "PACT_ERR_FINAL_PROTOCOL"
		return d
	if PactState.active_partners(pacts, me).size() >= PACT_MAX_ACTIVE \
			or PactState.active_partners(pacts, pid).size() >= PACT_MAX_ACTIVE:
		d["reason_key"] = "PACT_ERR_CAP_REACHED"
		return d
	if not outgoing.is_empty():
		d["reason_key"] = "PACT_ERR_CAP_REACHED"
		return d
	var cd := _pact_cooldown_remaining(pid)
	if cd > 0:
		d["reason_key"] = "PACT_ERR_COOLDOWN"
		d["reason_arg"] = cd
		return d
	d["enabled"] = true
	return d

# Rounds de TRÊVE restants avec ce joueur (0 = libre). Miroir de `pacts.cooldown_remaining` : on
# prend la fin la PLUS RÉCENTE d'un pacte nous liant. Le round courant se dérive comme côté serveur
# (nombre de snapshots de domination + 1) — MÊME échelle que le Rapport Post-Op.
func _pact_cooldown_remaining(other: int) -> int:
	var current_round := _current_global_round()
	var remaining := 0
	for e in GameState.pacts:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		if PactState.partner_of(e, _my_id()) != int(other):
			continue
		var ended := int(e.get("ended_round", 0))
		if ended <= 0:
			continue
		remaining = maxi(remaining, ended + PACT_COOLDOWN_ROUNDS - current_round)
	return maxi(0, remaining)

# Round GLOBAL courant, DÉRIVÉ exactement comme le serveur (`engine.current_global_round`) : le
# nombre de tours par round DIMINUE avec les éliminations, `current_turn / effectif` dériverait.
func _current_global_round() -> int:
	var stats: Dictionary = GameState.statistics if typeof(GameState.statistics) == TYPE_DICTIONARY else {}
	var history = stats.get("territory_history", [])
	return (history.size() if typeof(history) == TYPE_ARRAY else 0) + 1

# Ligne compacte de MES pactes pour la zone joueur ("" = aucun).
func _my_pacts_line() -> String:
	var parts: PackedStringArray = []
	for e in PactState.my_active(GameState.pacts, _my_id()):
		parts.append(tr("PACT_PLAYER_ENTRY_FMT") % [
			_display_name(PactState.partner_of(e, _my_id())).to_upper(),
			int(e.get("expires_at_round", 0))])
	return " · ".join(parts)

# --- Intentions du joueur (relayées par le HUD) --------------------------------------------------
func _on_pact_offer_requested(target_pid: int) -> void:
	_last_coded_action = "pact"
	NetworkManager.send_pact_offer(int(target_pid))
	# Retour IMMÉDIAT : le bouton passe en « OFFRE ENVOYÉE… » sans attendre l'aller-retour. Si le
	# serveur refuse, `_on_game_error` le dira et le prochain état remettra le bouton en place.
	_refresh_player_sheet()

func _on_pact_response_requested(pact_id: int, accept: bool) -> void:
	_last_coded_action = "pact"
	NetworkManager.send_pact_respond(int(pact_id), accept)

# --- Messages PRIVÉS du serveur ------------------------------------------------------------------
# Offre reçue : toast persistant si elle M'EST adressée ; simple ligne de journal si c'est la mienne
# (accusé de réception — la confirmation que le message est bien parti).
func _on_pact_offer_received(pact_id: int, proposer_id: int, target_id: int, _duration: int) -> void:
	if int(target_id) != _my_id():
		hud.add_feed_entries([{"category": "system", "icon": "↔", "major": false,
			"rich_text": tr("PACT_OFFER_SENT_LOG") % _bb_pseudo(int(target_id))}])
		return
	_pact_toast_shown = int(pact_id)
	hud.show_pact_offer(int(pact_id), _display_name(int(proposer_id)),
		board.get_player_color(int(proposer_id)))
	AudioManager.play_sfx("chat_ping")
	hud.add_feed_entries([{"category": "system", "icon": "↔", "major": true,
		"rich_text": tr("PACT_OFFER_LOG") % _bb_pseudo(int(proposer_id))}])
	# §8.129 — première offre de pacte REÇUE de toute la carrière : on explique en deux lignes ce
	# qu'un pacte fait (et surtout ce qu'il NE fait PAS). Une seule fois, jamais répétée.
	TutorialManager.hint_once("first_pact_received")

# Refus reçu (message PRIVÉ, jamais diffusé) : une ligne de journal sobre pour les deux concernés.
# Volontairement DISCRET — un refus n'est pas un évènement de partie, et l'ébruiter en ferait une
# humiliation. Le toast éventuel est retiré ici (cas du refus d'un BOT, immédiat).
func _on_pact_response_received(pact_id: int, accept: bool, proposer_id: int, target_id: int) -> void:
	hud.hide_pact_offer(int(pact_id))
	if _pact_toast_shown == int(pact_id):
		_pact_toast_shown = -1
	if accept:
		return  # une ACCEPTATION est publique : elle arrive par l'évènement `pact_active`.
	var other := int(target_id) if int(proposer_id) == _my_id() else int(proposer_id)
	hud.add_feed_entries([{"category": "system", "icon": "↔", "major": false,
		"rich_text": tr("PACT_DECLINED_LOG") % _bb_pseudo(other)}])

# --- Évènements PUBLICS --------------------------------------------------------------------------
# Pacte entré en vigueur : tout le monde le voit, c'est le principe. Toast + journal + SFX ; les
# chips se marquent d'elles-mêmes au prochain rafraîchissement d'état (player_chip lit GameState).
func _on_pact_active(event: Dictionary) -> void:
	var a := int(event.get("a_id", -9999))
	var b := int(event.get("b_id", -9999))
	var expires := int(event.get("expires_at_round", 0))
	hud.hide_pact_offer(int(event.get("pact_id", -1)))
	_pact_toast_shown = -1
	hud.show_power_toast(tr("PACT_ACTIVE_TOAST") % [
		_display_name(a).to_upper(), _display_name(b).to_upper()], Color("36c5d9"))
	AudioManager.play_sfx("pact_sealed")
	hud.add_feed_entries([{"category": "system", "icon": "↔", "major": true,
		"rich_text": tr("PACT_ACTIVE_LOG") % [_bb_pseudo(a), _bb_pseudo(b), expires]}])

# LA TRAHISON — le moment que toute la mécanique existe pour produire. Bandeau pleine largeur,
# sting dissonant, musique baissée, kill feed et Journal. La marque ⚡ sur la chip du traître, elle,
# est posée par `player_chip` à partir de l'état (elle reste jusqu'à la fin de la partie).
func _on_pact_broken(betrayer_id: int, victim_id: int) -> void:
	var line := tr("PACT_BROKEN_BANNER") % [
		_display_name(betrayer_id).to_upper(), _display_name(victim_id).to_upper()]
	if _phase_banner != null:
		_phase_banner.show_banner(line, Color("d6453f"))
	AudioManager.play_sfx("betrayal")
	# §8.122 : le sting passe DEVANT la musique. Appel DÉFENSIF — le ducking est arrivé avec le
	# chantier sensoriel, un AudioManager antérieur n'a pas la méthode.
	if AudioManager.has_method("duck_music"):
		AudioManager.duck_music()
	var feed_line := tr("PACT_BROKEN_LOG") % [_bb_pseudo(betrayer_id), _bb_pseudo(victim_id)]
	hud.add_feed_entries([{"category": "combat", "icon": "⚡", "major": true,
		"rich_text": feed_line}])
	hud.push_kill_feed(feed_line)

# Expiration : DISCRÈTE à dessein (aucun bandeau, aucun son). Un pacte qui s'éteint n'est pas un
# évènement dramatique — mais il ne doit pas non plus disparaître en silence total, sinon les deux
# signataires continueraient de se croire couverts.
func _on_pact_expired(a_id: int, b_id: int) -> void:
	hud.add_feed_entries([{"category": "system", "icon": "↔", "major": false,
		"rich_text": tr("PACT_EXPIRED_LOG") % [_bb_pseudo(a_id), _bb_pseudo(b_id)]}])

# Synchronisation du toast d'offre avec l'ÉTAT (appelé à chaque rafraîchissement) : c'est ce qui le
# fait survivre à une RECONNEXION (l'offre vit dans l'état, pas seulement dans un message fugace) et
# disparaître quand elle cesse d'exister (proposant éliminé, offre soldée, course perdue).
func _sync_pact_toast() -> void:
	var incoming := PactState.incoming_offer(GameState.pacts, _my_id())
	if incoming.is_empty():
		hud.hide_pact_offer()
		_pact_toast_shown = -1
		return
	var pact_id := int(incoming.get("id", -1))
	if pact_id == _pact_toast_shown and hud.current_pact_offer_id() == pact_id:
		return
	_pact_toast_shown = pact_id
	var proposer := int(incoming.get("proposed_by", -9999))
	hud.show_pact_offer(pact_id, _display_name(proposer), board.get_player_color(proposer))

# =========================================================
# Carte POUVOIR vivante (lot E) — zone JOUEUR + onglet ACTIONS
# =========================================================
# POURQUOI : les 10 pouvoirs sont appliqués côté serveur depuis longtemps, mais RIEN ne les rendait
# perceptibles en jeu (aucun compteur, aucun état, aucune relance de fenêtre). Ici, chaque faction
# expose une ligne d'ÉTAT lue de son propre état serveur — jamais une valeur en dur.

# Ligne d'état COURTE du pouvoir de MA faction (zone JOUEUR).
func _power_state_line() -> String:
	var mods := _faction_modifiers(str(_my_state().get("faction", "")))
	var me := _my_state()
	if mods.get("bonus_strategic_moves", 0):
		# Pillards : `strategic_moves_left` est DÉJÀ diffusé dans l'état — il n'était juste
		# affiché nulle part. Le total = 1 mouvement de base + le bonus de faction.
		var total := 1 + int(mods.get("bonus_strategic_moves", 0))
		return tr("POWER_STATE_MOVES_FMT") % [int(me.get("strategic_moves_left", total)), total]
	if mods.get("long_range_movement", false):
		return tr("POWER_STATE_CHAIN")
	if mods.get("free_contamination_immunity", 0):
		return tr("POWER_STATE_ZONE_IMMUNE")
	if mods.get("event_draw_pick_count", 0):
		var pending: Array = me.get("pending_eclipse_choice", [])
		return tr("POWER_STATE_ECLIPSE_PENDING") if pending.size() >= 2 else tr("POWER_STATE_ECLIPSE")
	if mods.get("peek_objective", 0):
		return tr("POWER_STATE_SPY_PENDING") if bool(me.get("pending_spy_choice", false)) \
			else tr("POWER_STATE_SPY_DONE")
	if mods.get("bonus_reinforcement_flat", 0):
		return tr("POWER_STATE_NEXT_REINFORCE_FMT") % int(mods.get("bonus_reinforcement_flat", 0))
	if mods.get("continent_bonus_plus", 0):
		return tr("POWER_STATE_NEXT_REINFORCE_FMT") % (
			int(mods.get("continent_bonus_plus", 0)) * _continents_owned(_my_id()))
	return tr("POWER_STATE_PASSIVE")

# Carte POUVOIR de l'onglet ACTIONS : lignes d'état + boutons contextuels (rouvrir une fenêtre de
# choix EN ATTENTE). Poussée à chaque refresh (View pure §6.1).
func _push_power_card() -> void:
	var lines: Array = []
	var buttons: Array = []
	var mods := _faction_modifiers(str(_my_state().get("faction", "")))
	var me := _my_state()
	# Compteur de mouvements (phase 4) : affiché pour TOUT LE MONDE (1 mouvement de base), la
	# mention « Razzia » ne s'ajoutant que pour les Pillards — le pouvoir devient perceptible.
	if _is_playing_my_turn() and int(GameState.current_phase) == 4:
		var total := 1 + int(mods.get("bonus_strategic_moves", 0))
		lines.append(tr("POWER_MOVES_LEFT_FMT") % [int(me.get("strategic_moves_left", total)), total])
		if mods.get("bonus_strategic_moves", 0):
			lines.append(tr("POWER_RAZZIA_HINT_FMT") % total)
		if mods.get("long_range_movement", false):
			lines.append(tr("POWER_CHAIN_HINT"))
	# Fenêtres de choix EN ATTENTE : le joueur peut les rouvrir s'il les a fermées.
	var pending_eclipse: Array = me.get("pending_eclipse_choice", [])
	if pending_eclipse.size() >= 2:
		lines.append(tr("POWER_STATE_ECLIPSE_PENDING"))
		buttons.append({"label": tr("POWER_BTN_ECLIPSE"), "action": "eclipse"})
	if bool(me.get("pending_spy_choice", false)):
		lines.append(tr("POWER_STATE_SPY_PENDING"))
		buttons.append({"label": tr("POWER_BTN_SPY"), "action": "spy"})
	# --- CAPACITÉS DE HÉROS (§8.119) : les PP deviennent dépensables. ---
	# RATIONNER : proposé aux 10 héros dès que le joueur a un héros initialisé. Toujours AFFICHÉ
	# pendant son tour (grisé + raison en infobulle si indisponible) — un bouton qui disparaît
	# n'enseigne rien, un bouton grisé qui explique pourquoi enseigne la règle.
	if GameState.has_hero(_my_id()) and _is_playing_my_turn():
		var preview: Array = _ration_preview()
		var ration_block := _ability_block_reason(ABILITY_RATION)
		buttons.append({
			"label": tr("ABILITY_RATION"),
			"subtitle": tr("ABILITY_RATION_PREVIEW") % [int(preview[0]), int(preview[1])],
			"action": "ability_ration",
			"disabled": ration_block != "",
			"tooltip": tr(ration_block) if ration_block != "" else tr("ABILITY_RATION_DESC"),
		})
		# Pouvoir de faction : UNIQUEMENT les 3 pilotes, et JAMAIS en Classée (les 7 autres
		# factions n'ont pas encore le leur → l'afficher serait un avantage arbitraire).
		var spec := _my_power()
		if not spec.is_empty() and not bool(GameState.is_ranked):
			var power_block := _ability_block_reason(ABILITY_FACTION_POWER)
			buttons.append({
				"label": tr(str(spec.get("name_key", ""))),
				"subtitle": tr("ABILITY_COST_FMT") % int(spec.get("pp_cost", 0)),
				"action": "ability_power",
				"disabled": power_block != "",
				"tooltip": tr(power_block) if power_block != "" else tr(str(spec.get("desc_key", ""))),
			})
	# --- BATTLE ROYALE (§8.125) : réanimation, reddition, coup d'État. ---
	_append_battle_royale_actions(lines, buttons)
	hud.set_power_card(lines, buttons)
	# --- AIDES CONTEXTUELLES (§8.129) : première fois qu'une capacité est réellement ACTIVABLE.
	# On teste `disabled == false` et non la simple présence : un bouton grisé n'apprend rien à
	# expliquer, il porte déjà sa raison en infobulle. Chaque bulle ne sort qu'UNE fois à vie. ---
	for b in buttons:
		if typeof(b) != TYPE_DICTIONARY or bool(b.get("disabled", false)):
			continue
		match str(b.get("action", "")):
			"ability_ration": TutorialManager.hint_once("first_pp_spend")
			"ability_power": TutorialManager.hint_once("first_power_ready")

# =========================================================
# BATTLE ROYALE (§8.125) — actions d'équipe dans la carte POUVOIR
# =========================================================
# Elles vivent dans la MÊME carte que les capacités de héros plutôt que dans un panneau à part :
# du point de vue du joueur, « rationner », « réanimer mon coéquipier » et « lancer le coup d'État »
# sont la même question — *qu'est-ce que je peux faire d'autre que déplacer des troupes ?*. Les
# séparer aurait obligé à chercher à deux endroits.
#
# Discipline VUE PURE (§6.1) : les gardes ci-dessous ne servent QU'À AFFICHER (griser, expliquer).
# Le client n'applique AUCUNE règle — il envoie, le serveur décide. Un bouton grisé qui dit POURQUOI
# enseigne la règle ; un bouton qui disparaît n'enseigne rien. D'où le choix systématique de
# l'afficher désactivé avec sa raison en infobulle.

# Round global courant, DÉRIVÉ comme côté serveur (`engine.current_global_round` : nombre de
# snapshots de domination + 1). Recopié plutôt qu'importé — le client n'a pas le moteur.
func _current_round() -> int:
	var stats: Dictionary = GameState.statistics if typeof(GameState.statistics) == TYPE_DICTIONARY else {}
	var history = stats.get("territory_history", [])
	return (history.size() if typeof(history) == TYPE_ARRAY else 0) + 1


# Bloc `battle_royale` de l'état (compteurs publics), {} si absent (serveur antérieur / FFA).
func _br_state() -> Dictionary:
	var data = GameState.battle_royale
	return data if typeof(data) == TYPE_DICTIONARY else {}


# SUIVI DES PRIMES (2026-08-01) — kills cumulés de MON équipe et caisses déjà ouvertes.
# ⚠️ MÊME agrégat que le serveur (`engine._open_pending_crates`) : la somme porte sur TOUS les
# membres de l'équipe, MORTS COMPRIS. Exclure les morts ferait CHUTER le compteur au moment précis
# où l'équipe vient de perdre quelqu'un — et le joueur croirait avoir reculé vers sa caisse.
func _push_bounty_progress() -> void:
	if GameState.team_mode == "":
		return
	var stats: Dictionary = GameState.statistics if 		typeof(GameState.statistics) == TYPE_DICTIONARY else {}
	var ck = stats.get("combat_kills_by_player", {})
	if typeof(ck) != TYPE_DICTIONARY:
		ck = {}
	var me := _my_id()
	var total := 0
	for pid in ([me] + GameState.teammates_of(me)):
		total += int(ck.get(str(int(pid)), ck.get(int(pid), 0)))
	var crates = _br_state().get("crates", {})
	var opened := 0
	if typeof(crates) == TYPE_DICTIONARY:
		var team := GameState.team_of(me)
		opened = int(crates.get(str(team), crates.get(team, 0)))
	hud.set_bounty_progress(total, opened, BR_CRATE_KILL_STEP, BR_CRATE_MAX)


# Coéquipiers MORTS, réanimables (ni déjà réanimés, ni hors partie).
func _revivable_teammates() -> Array:
	var out: Array = []
	var revived: Array = _br_state().get("revived", [])
	for mate in GameState.teammates_of(_my_id()):
		var p: Dictionary = GameState.players.get(str(int(mate)), {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if str(p.get("status", "alive")) != "eliminated":
			continue
		if int(mate) in revived.map(func(v): return int(v)):
			continue
		out.append(int(mate))
	return out


func _append_battle_royale_actions(lines: Array, buttons: Array) -> void:
	if GameState.team_mode == "" or GameState.winner_id != null:
		return
	var me := _my_id()
	var my_state: Dictionary = _my_state()
	var alive := str(my_state.get("status", "alive")) == "alive"
	var round_now := _current_round()

	# --- ORDRE SECRET DU TRAÎTRE ---------------------------------------------------------------
	# `GameState.traitors` est REDACTÉ à la source : s'il contient une entrée, elle est FORCÉMENT
	# la nôtre (le serveur ne nous envoie jamais celle d'autrui). Aucun filtrage à faire ici.
	var my_victim := -1
	for k in GameState.traitors.keys():
		my_victim = int(GameState.traitors[k])
	if my_victim >= 0:
		# EN ROUGE, pas en cyan comme les lignes d'état : c'est l'information la plus lourde que le
		# jeu confie à un joueur, et elle ne doit surtout pas se lire comme un compteur de renforts.
		lines.append({"text": "⚠ " + tr("BR_COUP_ORDER") % _display_name(my_victim),
			"color": Color("d6453f")})
		# §8.129 — bulle DISCRÈTE : elle dit seulement où lire son ordre et que personne d'autre ne
		# le voit. Elle ne nomme JAMAIS la victime (une bulle est un panneau, et un panneau se lit
		# par-dessus l'épaule) et ne dit rien du nombre de traîtres à la table.
		TutorialManager.hint_once("first_coup_order")

	# --- RÉANIMER ------------------------------------------------------------------------------
	# UN BOUTON PAR MORT plutôt qu'un sélecteur : en 3v3 il y a au plus deux coéquipiers, et deux
	# boutons nommés se lisent plus vite qu'une liste déroulante à ouvrir. Le coût en PV est dans le
	# sous-titre — c'est la seule chose que le joueur doit peser avant de cliquer.
	if alive and _is_playing_my_turn() and int(GameState.current_phase) in [1, 2, 3, 4]:
		var my_hp := int(my_state.get("hero_pv_current", 0))
		var already_revived := int(_br_state().get("revives_done", {}).get(str(me), 0)) > 0
		for mate in _revivable_teammates():
			var blocked := ""
			if already_revived:
				blocked = "BR_ERR_ALREADY_USED"
			elif my_hp - BR_REVIVE_COST < 1:
				blocked = "BR_ERR_NOT_ENOUGH_HP"
			buttons.append({
				"label": tr("BR_REVIVE") + " — " + _display_name(mate),
				"subtitle": tr("BR_REVIVE_COST_FMT") % BR_REVIVE_COST,
				"action": "br_revive_%d" % int(mate),
				"disabled": blocked != "",
				"tooltip": tr(blocked) if blocked != "" else tr("BR_REVIVE_DESC"),
			})

	# --- COUP D'ÉTAT ---------------------------------------------------------------------------
	# Visible du SEUL traître, et seulement pendant sa phase d'attaque. ⚠️ CONFIRMATION EN DEUX
	# TEMPS (cf. `_coup_armed`) : c'est le seul geste du jeu qui peut tuer son auteur et clore la
	# partie sur un clic. Un mécanisme d'idempotence serveur protège du double-envoi, pas du
	# clic MALHEUREUX — et ici le clic malheureux est irrattrapable.
	if my_victim >= 0 and alive:
		var coup_used: Array = _br_state().get("coup_used", [])
		var coup_block := ""
		if me in coup_used.map(func(v): return int(v)):
			coup_block = "BR_ERR_ALREADY_USED"
		elif round_now < BR_COUP_MIN_ROUND:
			coup_block = "BR_ERR_NO_SURRENDER_YET"
		elif not (_is_playing_my_turn() and int(GameState.current_phase) == 3):
			coup_block = "BR_ERR_NOT_YOUR_TURN"
		elif str(GameState.players.get(str(my_victim), {}).get("status", "")) != "alive":
			coup_block = "BR_ERR_INVALID_TARGET"
		buttons.append({
			"label": tr("BR_COUP_CONFIRM") if _coup_armed else tr("BR_COUP_BUTTON"),
			"subtitle": tr("BR_COUP_SUBTITLE") % _display_name(my_victim),
			"action": "br_coup",
			"disabled": coup_block != "",
			"tooltip": tr(coup_block) if coup_block != "" else tr("BR_COUP_DESC"),
			# ROUGE DANGER, et pas la couleur des autres actions : ce bouton n'est pas une capacité
			# de plus dans une liste, c'est le seul du jeu qui peut tuer son auteur. Il doit se
			# distinguer AVANT d'être lu.
			"accent": Color("d6453f"),
		})

	# --- SE RENDRE -----------------------------------------------------------------------------
	# HORS TOUR (le serveur l'accepte hors tour, cf. §8.125) : on se rend en REGARDANT l'autre camp
	# écraser le sien. Le compteur de voix est dans le libellé — sans lui, un joueur qui a voté ne
	# saurait pas s'il attend un coéquipier ou si son vote s'est perdu.
	if alive:
		var team_id := GameState.team_of(me)
		var votes: Array = _br_state().get("surrender", {}).get(str(team_id), [])
		var voted := me in votes.map(func(v): return int(v))
		var quorum := 0
		for mate in (GameState.teammates_of(me) + [me]):
			var p2: Dictionary = GameState.players.get(str(int(mate)), {})
			if str(p2.get("status", "alive")) == "alive" and bool(p2.get("is_active", true)):
				quorum += 1
		var surr_block := ""
		if voted:
			surr_block = "BR_ERR_ALREADY_USED"
		elif round_now < BR_SURRENDER_MIN_ROUND:
			surr_block = "BR_ERR_NO_SURRENDER_YET"
		buttons.append({
			"label": tr("BR_SURRENDER"),
			"subtitle": tr("BR_SURRENDER_VOTE") % [votes.size(), quorum],
			"action": "br_surrender",
			"disabled": surr_block != "",
			"tooltip": tr(surr_block) if surr_block != "" else tr("BR_SURRENDER_DESC"),
		})


# Marqueurs des pouvoirs déclenchés pendant CE combat (flags posés par engine._handle_attack) :
# étiquettes flottantes de la flèche de guerre + toasts d'activation. Table unique → aucun risque
# d'oublier un flag comme cela s'était produit pour razzia_reroll / first_strike.
# Chaque entrée : [flag serveur, clé du TOAST (phrase complète), clé du MARQUEUR court].
# Le marqueur court est celui du Journal (FEED_MARK_*) : c'est lui qui flotte au-dessus du
# territoire pendant la flèche — la phrase entière y serait illisible et ferait doublon avec le
# toast (constaté en capture).
const COMBAT_POWER_FLAGS := [
	["phalanges_reroll", "POWER_TOAST_PHALANX", "FEED_MARK_PHALANX"],
	["aegis_kill", "POWER_TOAST_AEGIS", "FEED_MARK_AEGIS"],
	["terror_kill", "POWER_TOAST_TERROR", "FEED_MARK_TERROR"],
	["razzia_reroll", "POWER_TOAST_RAZZIA", "FEED_MARK_RAZZIA"],
	["first_strike", "POWER_TOAST_AMBUSH", "FEED_MARK_AMBUSH"],
]

func _combat_power_marks(event: Dictionary) -> Array:
	var out: Array = []
	for f in COMBAT_POWER_FLAGS:
		if event.get(str(f[0])):
			out.append(tr(str(f[2])))
	return out

# Toasts d'ACTIVATION des pouvoirs de combat, joués APRÈS l'animation (sinon ils précéderaient le
# combat qu'ils commentent). Le liseré prend la couleur du camp CONCERNÉ : attaquant pour les
# pouvoirs offensifs (Phalanges/Razzia/Embuscade/Terreur), défenseur pour Aegis.
func _push_combat_power_toasts(event: Dictionary, atk_owner, def_owner) -> void:
	for f in COMBAT_POWER_FLAGS:
		if not event.get(str(f[0])):
			continue
		var owner: int = int(def_owner) if str(f[0]) == "aegis_kill" else int(atk_owner)
		hud.show_power_toast(tr(str(f[1])), board.get_player_color(owner))

# Bouton contextuel de la carte POUVOIR (onglet ACTIONS) : rouvre la fenêtre correspondante quand
# un choix de faction est EN ATTENTE côté serveur (l'état fait foi, jamais le client).
func _on_power_action_requested(action: String) -> void:
	match action:
		"eclipse":
			if _my_state().get("pending_eclipse_choice", []).size() >= 2:
				_awaiting_eclipse = false   # force la ré-ouverture par _maybe_prompt_eclipse
				_maybe_prompt_eclipse()
		"spy":
			if bool(_my_state().get("pending_spy_choice", false)):
				_awaiting_spy = false
				_maybe_prompt_spy()
		"ability_ration":
			_send_ability(ABILITY_RATION)
		"ability_power":
			_start_power_activation()
		"br_surrender":
			_last_coded_action = "br"
			NetworkManager.send_action("team_surrender", {})
		"br_coup":
			# CONFIRMATION EN DEUX TEMPS : le 1er clic ARME (le bouton devient rouge et change de
			# libellé), le 2e envoie. Ce geste peut tuer son auteur et clore la partie — le protéger
			# d'un clic malheureux vaut la seconde de friction. `_push_power_card` re-rend la carte,
			# donc le nouveau libellé apparaît immédiatement.
			if not _coup_armed:
				_coup_armed = true
				hud.add_log("⚠ " + tr("BR_COUP_ARMED"))
				_push_power_card()
				return
			_coup_armed = false
			_last_coded_action = "br"
			NetworkManager.send_action("coup_detat", {})
		_:
			# RÉANIMER : l'id de la cible est encodé dans l'action (`br_revive_<pid>`) — un bouton
			# par mort, cf. `_append_battle_royale_actions`.
			if action.begins_with("br_revive_"):
				_last_coded_action = "br"
				NetworkManager.send_action("team_revive",
					{"target_player_id": int(action.trim_prefix("br_revive_"))})

# =========================================================
# CAPACITÉS DE HÉROS (§8.119) — RATIONNER + pouvoir de faction du trio pilote
# =========================================================
# ⚠️ VUE PURE (§6.1) : les constantes ci-dessous ne servent QU'À AFFICHER (libellé, coût, phases
# autorisées, mode de ciblage). Le client n'applique AUCUNE règle — il envoie l'action, le serveur
# décide, l'état redescend. Le grisage d'un bouton est un CONFORT (ne rien proposer d'impossible),
# jamais une autorité : un état limite passé au travers est de toute façon refusé par le serveur.
#
# ⚠️ MIROIR de `backend/api/game/hero_abilities.py` — même discipline que `map_data.gd` face à
# `map_data.py`. Si un coût change côté serveur, le mettre à jour ICI aussi (le serveur reste la
# source de vérité : au pire l'affichage est périmé, jamais la règle).

const ABILITY_RATION := "ration"
const ABILITY_FACTION_POWER := "faction_power"

# Phases où RATIONNER est proposé (miroir de HERO_ABILITIES["ration"]["phases"]).
const RATION_PHASES := [2, 3, 4]
const RATION_PP_MAX := 5
const RATION_PV_PER_PP := 6

# Modes de ciblage (miroir de hero_abilities.TARGET_*).
const TARGET_NONE := "none"
const TARGET_OWN_UNSHIELDED := "own_unshielded"
const TARGET_CONTAMINATED := "contaminated"

# Pouvoirs des 3 factions PILOTES. Les 7 autres factions n'ont AUCUNE entrée → aucun bouton, et
# surtout PAS de mention « bientôt » (décision produit).
const FACTION_POWERS := {
	"phalanges_acier": {
		"power_id": "bastion_acier", "name_key": "ABILITY_BASTION",
		"desc_key": "ABILITY_BASTION_DESC", "pp_cost": 6, "phases": [2, 3, 4],
		"target": TARGET_OWN_UNSHIELDED, "pick_key": "ABILITY_PICK_TARGET_OWN",
	},
	"chasseurs_ombres": {
		"power_id": "frappe_fantome", "name_key": "ABILITY_FANTOME",
		"desc_key": "ABILITY_FANTOME_DESC", "pp_cost": 8, "phases": [3],
		"target": TARGET_NONE, "pick_key": "",
	},
	"culte_isotope": {
		"power_id": "absolution", "name_key": "ABILITY_ABSOLUTION",
		"desc_key": "ABILITY_ABSOLUTION_DESC", "pp_cost": 5, "phases": [2, 3, 4],
		"target": TARGET_CONTAMINATED, "pick_key": "ABILITY_PICK_TARGET_ZONE",
	},
}

# Traduction des codes de refus serveur (`NetworkManager.last_error_reason`) → clé i18n. Un code
# inconnu (serveur plus récent que le client) retombe sur le `message` serveur : jamais d'écran vide.
const ABILITY_ERROR_KEYS := {
	"already_used": "ABILITY_ERR_ALREADY_USED",
	"insufficient_pp": "ABILITY_ERR_INSUFFICIENT_PP",
	"ranked_disabled": "ABILITY_ERR_RANKED",
	"invalid_target": "ABILITY_ERR_INVALID_TARGET",
	"wrong_phase": "ABILITY_ERR_WRONG_PHASE",
	"not_your_turn": "ABILITY_ERR_NOT_YOUR_TURN",
	"blocked_state": "ABILITY_ERR_BLOCKED_STATE",
	"no_power": "ABILITY_ERR_NO_POWER",
}

# --- BATTLE ROYALE (§8.125) ------------------------------------------------------------------
# Réglages RECOPIÉS du registre serveur (`battle_royale.BR_RULES`) — ils ne servent QU'À AFFICHER
# (coût annoncé, grisage anticipé). Le serveur reste l'autorité : une valeur qui divergerait ici
# ferait au pire promettre un coût inexact, jamais appliquer une règle fausse.
const BR_REVIVE_COST := 100
const BR_SURRENDER_MIN_ROUND := 3
const BR_COUP_MIN_ROUND := 4
# Caisses de ravitaillement : palier de kills d'ÉQUIPE et plafond par partie
# (`BR_RULES["crate_kill_step"]` / `["crate_max_per_team"]`). Recopiés au même titre que les
# précédents : ils n'alimentent QUE l'affichage du suivi des primes, jamais une décision.
const BR_CRATE_KILL_STEP := 50
const BR_CRATE_MAX := 4

# Refus CODÉS des actions Battle Royale. Jeu de codes DISTINCT de celui des capacités et des
# pactes bien que plusieurs noms coïncident (`already_used`, `invalid_target`, `not_your_turn`) :
# seul le contexte les distingue, d'où le préfixe `BR_ERR_*` et l'aiguillage par
# `_last_coded_action == "br"` (même mécanique que `PACT_ERROR_KEYS`).
const BR_ERROR_KEYS := {
	"not_team_mode": "BR_ERR_NOT_TEAM_MODE",
	"not_your_turn": "BR_ERR_NOT_YOUR_TURN",
	"invalid_target": "BR_ERR_INVALID_TARGET",
	"already_used": "BR_ERR_ALREADY_USED",
	"not_enough_hp": "BR_ERR_NOT_ENOUGH_HP",
	"not_traitor": "BR_ERR_NOT_TRAITOR",
	"no_surrender_yet": "BR_ERR_NO_SURRENDER_YET",
}

# COUP D'ÉTAT armé (1er clic) → le 2e envoie. Remis à false à l'envoi, au refus, et à chaque
# changement de tour (ci-dessous) : une confirmation qui SURVIVRAIT au tour suivant serait un
# piège — le joueur cliquerait « attaquer » et déclencherait son coup d'État.
var _coup_armed := false

# Mode de ciblage EN COURS pour une capacité ("" = aucun). Quand il est armé, le prochain clic de
# territoire est CONSOMMÉ par la capacité au lieu du jeu normal (attaque / mouvement).
var _ability_target_mode: String = ""

# Spécification du pouvoir de MA faction, ou {} si ma faction n'en a pas (7 factions sur 10).
func _my_power() -> Dictionary:
	var spec = FACTION_POWERS.get(str(_my_state().get("faction", "")), {})
	return spec if typeof(spec) == TYPE_DICTIONARY else {}

# PP disponibles AU-DESSUS du plancher (le serveur refuse tout paiement qui le franchirait).
func _pp_available() -> int:
	var hero := GameState.hero_of(_my_id())
	return int(hero.get("pp_current", 0)) - int(hero.get("pp_min", 0))

# Aperçu EXACT du rationnement : (PP dépensés, PV rendus) — miroir de `hero_abilities.ration_plan`.
# Affiché en sous-titre du bouton, pour que le joueur voie la vraie affaire AVANT de cliquer (le
# plafond de PV peut rogner la conversion : « −5 PP → +2 PV » doit se lire, pas se découvrir).
func _ration_preview() -> Array:
	var hero := GameState.hero_of(_my_id())
	var pp_spent: int = clampi(_pp_available(), 0, RATION_PP_MAX)
	var missing: int = maxi(int(hero.get("pv_max", 0)) - int(hero.get("pv_current", 0)), 0)
	return [pp_spent, mini(pp_spent * RATION_PV_PER_PP, missing)]

# Raison de GRISAGE d'une capacité (clé i18n), "" si elle est activable. Ordre calqué sur celui de
# `hero_abilities.can_use` pour que l'infobulle annonce la MÊME raison que le refus serveur.
func _ability_block_reason(ability: String) -> String:
	if not _is_playing_my_turn() or _is_eliminated():
		return "ABILITY_ERR_NOT_YOUR_TURN"
	if _input_blocked():
		return "ABILITY_ERR_BLOCKED_STATE"
	var me := _my_state()
	var phase := int(GameState.current_phase)
	if ability == ABILITY_RATION:
		if not RATION_PHASES.has(phase):
			return "ABILITY_ERR_WRONG_PHASE"
		if bool(me.get("ability_ration_used", false)):
			return "ABILITY_ERR_ALREADY_USED"
		if _pp_available() <= 0:
			return "ABILITY_ERR_INSUFFICIENT_PP"
		if int(_ration_preview()[1]) <= 0:
			return "ABILITY_ERR_FULL_PV"
		return ""
	var spec := _my_power()
	if spec.is_empty():
		return "ABILITY_ERR_NO_POWER"
	if bool(GameState.is_ranked):
		return "ABILITY_ERR_RANKED"
	if not (spec.get("phases", []) as Array).has(phase):
		return "ABILITY_ERR_WRONG_PHASE"
	if bool(me.get("ability_power_used", false)):
		return "ABILITY_ERR_ALREADY_USED"
	if _pp_available() < int(spec.get("pp_cost", 0)):
		return "ABILITY_ERR_INSUFFICIENT_PP"
	# Pouvoir SANS cible (Frappe Fantôme) : rien à vérifier ici. On ne teste la disponibilité de
	# cibles que pour les pouvoirs qui en demandent une — sinon `_ability_targets(TARGET_NONE)`,
	# qui renvoie [] par contrat, griserait le bouton en permanence.
	var mode := str(spec.get("target", TARGET_NONE))
	if mode != TARGET_NONE and _ability_targets(mode).is_empty():
		return "ABILITY_ERR_INVALID_TARGET"
	return ""

# Territoires légaux pour un mode de ciblage — MIROIR de `hero_abilities.target_is_valid` (le
# surlignage affiché est donc exactement ce que le serveur acceptera).
func _ability_targets(mode: String) -> Array:
	var out: Array = []
	if mode == TARGET_NONE:
		return out
	for tid in GameState.territories.keys():
		var t: Dictionary = _terr(str(tid))
		if mode == TARGET_OWN_UNSHIELDED:
			if _owner(str(tid)) == _my_id() and int(t.get("shield_turns_left", 0)) <= 0:
				out.append(str(tid))
		elif mode == TARGET_CONTAMINATED and _contaminated_tids().has(str(tid)):
			out.append(str(tid))
	return out

# Territoires de la zone COURANTE (jamais `next_territories` — le télégraphe n'est pas purgeable).
func _contaminated_tids() -> Array:
	var zone: Dictionary = GameState.contamination_zone \
		if typeof(GameState.contamination_zone) == TYPE_DICTIONARY else {}
	var tids = zone.get("territories", [])
	var out: Array = []
	if typeof(tids) == TYPE_ARRAY:
		for t in tids:
			out.append(str(t))
	return out

# Clic sur le bouton de pouvoir : envoi DIRECT si le pouvoir n'a pas de cible (Frappe Fantôme),
# sinon armement du mode de ciblage sur le plateau.
func _start_power_activation() -> void:
	var spec := _my_power()
	if spec.is_empty():
		return
	var mode := str(spec.get("target", TARGET_NONE))
	if mode == TARGET_NONE:
		_send_ability(ABILITY_FACTION_POWER)
		return
	# Un ciblage de capacité et une sélection d'attaque ne peuvent pas cohabiter : on repart propre.
	_clear_source()
	_ability_target_mode = mode
	board.set_ability_targets(_ability_targets(mode))
	hud.set_instruction(tr(str(spec.get("pick_key", "ABILITY_PICK_TARGET_OWN"))))

# Sort du mode ciblage (ESC, clic sur une cible illégale, activation réussie, changement de phase).
func _cancel_ability_targeting(notify: bool = false) -> void:
	if _ability_target_mode == "":
		return
	_ability_target_mode = ""
	board.clear_attack_context()
	if notify:
		hud.add_log(tr("ABILITY_TARGETING_CANCELLED"))
	_update_instruction()

# Toast PUBLIC d'activation d'une capacité, composé depuis l'évènement système `ability_used`
# (un SEUL code paramétré côté serveur → la phrase est choisie ici, dans la langue du joueur).
# `power_id` inconnu (serveur plus récent que le client) → phrase générique, jamais d'écran muet.
func _push_ability_toast(sev: Dictionary) -> void:
	var pid := int(sev.get("player_id", -9999))
	var who := _display_name(pid)
	var accent: Color = board.get_player_color(pid)
	var text := ""
	if str(sev.get("ability", "")) == ABILITY_RATION:
		text = tr("SYSEV_ABILITY_RATION") % [who, int(sev.get("pp_spent", 0)),
			int(sev.get("pv_healed", 0))]
		# Flotteur vert « +N PV » sur MA jauge de héros (le soin doit se voir autant que les dégâts).
		if pid == _my_id():
			hud.float_hero_heal(int(sev.get("pv_healed", 0)))
	else:
		var tname := _territory_name(str(sev.get("territory_id", "")))
		match str(sev.get("power_id", "")):
			"bastion_acier": text = tr("SYSEV_ABILITY_BASTION") % [who, tname]
			"frappe_fantome": text = tr("SYSEV_ABILITY_FANTOME") % who
			"absolution": text = tr("SYSEV_ABILITY_ABSOLUTION") % [who, tname]
			_: text = tr("SYSEV_ABILITY_GENERIC") % who
	hud.show_power_toast(text, accent)
	hud.add_log(text)

func _send_ability(ability: String, target_tid: String = "") -> void:
	var payload := {"ability": ability}
	if target_tid != "":
		payload["target_territory_id"] = target_tid
	# `send_action` injecte lui-même un `action_id` unique → l'idempotence serveur protège d'un
	# double-clic ou d'une retransmission WS (jamais de double dépense de PP).
	_last_coded_action = "ability"
	NetworkManager.send_action("hero_ability", payload)
	_cancel_ability_targeting()

# Résout les NOMS de faction affichables par joueur (le bandeau de tour et la fiche n'affichent
# jamais l'id snake_case brut). Remplace l'ancien tiroir « INTEL : FACTIONS » (supprimé lot A —
# l'information vit désormais dans la fiche joueur, complète et par joueur).
func _push_faction_names() -> void:
	for k in GameState.players.keys():
		var p = GameState.players.get(k, {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var fid := str(p.get("faction", ""))
		var fname := str(_faction_info(fid).get("name", ""))
		if fname == "":
			fname = fid.capitalize() if fid != "" else tr("GAME_FACTION_UNKNOWN")
		hud.faction_name_by_pid[str(int(k))] = fname

# Télégraphe de la zone (G1 §8.62) — devenu un CHIP discret sous le bandeau haut (lot A : les 3
# tiroirs INTEL sont supprimés, leurs infos vivent dans la fiche joueur et le Journal). Résout les
# NOMS lisibles des territoires annoncés et les pousse au HUD (View pure §6.1).
func _push_zone_forecast() -> void:
	# Télégraphe de la zone (G1 §8.62) : résout les NOMS lisibles des territoires annoncés
	# (contamination_zone.next_territories, pré-tirés serveur) et pousse la ligne permanente au HUD.
	# Clé absente (serveur antérieur / état legacy) → liste vide, mention neutre côté HUD.
	var zone: Dictionary = GameState.contamination_zone if typeof(GameState.contamination_zone) == TYPE_DICTIONARY else {}
	var forecast_names: Array = []
	var next_tids = zone.get("next_territories", [])
	var mine_targeted := false
	if typeof(next_tids) == TYPE_ARRAY:
		for tid in next_tids:
			forecast_names.append(MapData.t_name(str(tid)))
			if _owner(str(tid)) == _my_id():
				mine_targeted = true
	hud.set_zone_forecast(forecast_names)
	# SFX zone_alarm (E9 §8.81) : le télégraphe annonce la PROCHAINE zone sur AU MOINS un de MES
	# territoires. Joué une seule fois par nouveau télégraphe (signature) — pas à chaque refresh.
	var sig := ",".join(PackedStringArray(forecast_names))
	if mine_targeted and sig != _last_zone_alarm_sig:
		AudioManager.play_sfx("zone_alarm")
	_last_zone_alarm_sig = sig

# =========================================================
# INTENSITÉ DE GUERRE (§8.122, LOT A) — cible, lissage, propagation
# =========================================================
# Le contrôleur est le SEUL point où l'état devient « tension » : il construit le snapshot,
# délègue le CALCUL au module pur, lisse, et pousse la valeur aux consommateurs. Ni AudioManager
# ni board ne lisent GameState — c'est ce qui garantit qu'ils entendent tous la même guerre.

func _process(delta: float) -> void:
	var next := WarIntensityCalc.smooth(_war_intensity, _war_intensity_target, delta)
	if is_equal_approx(next, _war_intensity) and _war_intensity_pushed >= 0.0:
		return
	_war_intensity = next
	if absf(_war_intensity - _war_intensity_pushed) < WAR_INTENSITY_PUSH_EPSILON:
		return
	_war_intensity_pushed = _war_intensity
	# LOT B/C : musique à couches + volume du Geiger d'ambiance.
	AudioManager.set_war_intensity(_war_intensity)
	# LOT E : désaturation / vignette / virage chromatique du fond de carte.
	if is_instance_valid(board):
		board.set_war_intensity(_war_intensity)

# Recalcule la CIBLE depuis l'état public courant. Appelé par _refresh() (donc à chaque état reçu) :
# jamais en `_process`, le snapshot ne change qu'avec l'état.
func _update_war_intensity_target() -> void:
	_war_intensity_target = WarIntensityCalc.compute(_war_intensity_snapshot())

# Extrait de l'état public consommé par la formule. Tout vient de GameState — AUCUN champ neuf.
func _war_intensity_snapshot() -> Dictionary:
	# Moyenne des PV% des héros encore EN JEU (les éliminés/morts sortent du calcul : leur 0 % tirerait
	# la tension au plafond alors qu'ils ne pèsent plus sur la partie).
	var sum_ratio := 0.0
	var counted := 0
	for key in GameState.players.keys():
		var p = GameState.players.get(str(key), null)
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if str(p.get("status", "alive")) == "eliminated" or bool(p.get("is_dead", false)):
			continue
		var pv_max := int(p.get("hero_pv_max", 0))
		if pv_max <= 0:
			continue   # état pré-RPG : pas de héros, rien à moyenner.
		sum_ratio += clampf(float(p.get("hero_pv_current", 0)) / float(pv_max), 0.0, 1.0)
		counted += 1
	# Aucun héros mesurable → 1.0 (« tous intacts »), le repli SÛR du module pur.
	var heroes_ratio := (sum_ratio / float(counted)) if counted > 0 else 1.0
	var mine: Dictionary = GameState.hero_of(_my_id())
	var my_ratio := 1.0
	if int(mine.get("pv_max", 0)) > 0:
		my_ratio = clampf(float(mine.get("pv_current", 0)) / float(mine.get("pv_max", 1)), 0.0, 1.0)
	# Zone : modèle CLUSTER §8.27 (liste "territories"), même lecture défensive que board.gd.
	var zone_count := 0
	var zone = GameState.contamination_zone
	if typeof(zone) == TYPE_DICTIONARY and typeof(zone.get("territories")) == TYPE_ARRAY:
		zone_count = (zone["territories"] as Array).size()
	return {
		"round": int(GameState.current_turn),
		"alive_heroes_pv_ratio": heroes_ratio,
		"my_hero_pv_ratio": my_ratio,
		"zone_count": zone_count,
		"final_protocol": bool(GameState.final_protocol_active),
	}


# GEIGER (§8.122, LOT C) — distance MINIMALE, en sauts d'adjacence, entre la zone contaminée et le
# territoire à MOI le plus proche. 0 = un de mes territoires EST dans la zone. -1 = hors de portée
# (ou je n'ai plus rien / la zone est vide) → AudioManager coupe le compteur.
#
# BFS MULTI-SOURCE depuis la zone, borné à la profondeur du dernier palier audible : sur 42 nœuds
# c'est quelques dizaines d'itérations, et ça ne tourne qu'à la réception d'un état — jamais par
# frame. On part de la ZONE (souvent 1 à 8 nœuds) plutôt que de mes territoires (jusqu'à 42) :
# c'est le plus petit des deux fronts dans l'immense majorité des cas.
func _zone_distance_to_me() -> int:
	var zone = GameState.contamination_zone
	if typeof(zone) != TYPE_DICTIONARY or typeof(zone.get("territories")) != TYPE_ARRAY:
		return -1
	var mine: Dictionary = {}
	for tid in GameState.territories:
		var o = GameState.territories[tid].get("owner_id")
		if o != null and int(o) == _my_id():
			mine[str(tid)] = true
	if mine.is_empty():
		return -1
	var seen: Dictionary = {}
	var frontier: Array = []
	for tid in zone["territories"]:
		var t := str(tid)
		if not seen.has(t):
			seen[t] = true
			frontier.append(t)
	if frontier.is_empty():
		return -1
	# Borne = index du dernier palier de la table de volumes (source unique côté AudioManager) :
	# chercher plus loin ne servirait à rien, tout ce qui dépasse est « coupé ».
	var max_hops: int = AudioManager.AMB_GEIGER_DB_BY_DISTANCE.size() - 1
	for depth in range(max_hops + 1):
		for t in frontier:
			if mine.has(t):
				return depth
		if depth == max_hops:
			break
		var next_front: Array = []
		for t in frontier:
			for nb in MapData.neighbors_of(t, GameState.map_id):
				var n := str(nb)
				if seen.has(n):
					continue
				seen[n] = true
				next_front.append(n)
		frontier = next_front
		if frontier.is_empty():
			break
	return -1


# =========================================================
# REBOURS GLOBAL DE PARTIE & PROTOCOLE FINAL (chantier « Tension & fin de partie », LOT F)
# =========================================================

# Vrai quand le PROTOCOLE FINAL a déjà été annoncé — évite de rejouer le bandeau à chaque refresh.
var _final_protocol_announced := false

# Pousse l'échéance GLOBALE au HUD et, pendant le PROTOCOLE FINAL, le mini-classement de départage.
#
# ⚠️ POURQUOI LE CLASSEMENT EST CALCULÉ ICI et non lu du serveur : le bloc `final_scores` n'arrive
# qu'au `game_over` — trop tard pour une course. Les DEUX derniers critères (PV de héros, kills de
# combat) sont des données PUBLIQUES de l'état, donc calculables en direct. Le PREMIER (% d'objectif)
# est SECRET pour autrui : on affiche « ??? » pour les autres et notre VRAIE valeur pour nous. C'est
# un choix assumé — la tension vient justement de ne pas savoir où en sont les adversaires.
func _push_match_countdown() -> void:
	hud.set_match_deadline(float(GameState.match_deadline_epoch), float(GameState.server_time))
	var active: bool = bool(GameState.final_protocol_active) \
		and GameState.stage == "playing" and GameState.winner_id == null
	if active and not _final_protocol_announced:
		_final_protocol_announced = true
		if _phase_banner != null:
			_phase_banner.show_banner(tr("FINAL_PROTOCOL_BANNER"), Color("d6453f"))
		AudioManager.play_sfx("zone_alarm")
		# §8.122 (LOT B) : l'annonce du PROTOCOLE FINAL passe DEVANT la musique. C'est aussi le
		# moment où l'intensité saute à ≥ 0,85 (plancher WarIntensity) : sans ducking, le fondu
		# d'entrée de la couche « high » et l'alarme se disputeraient les mêmes 2 secondes.
		AudioManager.duck_music()
		hud.add_feed_entries([{"category": "zone", "icon": "☢", "major": true, "tid": "",
			"rich_text": tr("FINAL_PROTOCOL_LOG")}])
		# §8.129 — premier PROTOCOLE FINAL de la carrière : le bandeau dit QU'IL se passe quelque
		# chose, la bulle dit QUOI (zone doublée, diplomatie fermée, victoire au score).
		TutorialManager.hint_once("first_final_protocol")
	if not active:
		hud.set_tiebreak_board([])
		return
	hud.set_tiebreak_board(_tiebreak_rows())


# Lignes du mini-classement, TRIÉES comme le barème serveur (`final_scoring`) sur ce que le client
# peut voir : PV de héros % puis kills de combat. On NE trie PAS sur le % d'objectif — il nous est
# inconnu pour les autres, et un tri partiel serait plus trompeur qu'utile (l'ordre affiché ne
# prétend donc PAS être le classement final, il montre les critères).
func _tiebreak_rows() -> Array:
	var stats: Dictionary = GameState.statistics if typeof(GameState.statistics) == TYPE_DICTIONARY else {}
	var kills_by: Dictionary = stats.get("combat_kills_by_player", {}) \
		if typeof(stats.get("combat_kills_by_player")) == TYPE_DICTIONARY else {}
	var rows: Array = []
	for key in GameState.players.keys():
		var pid := int(key)
		var p: Dictionary = GameState.players.get(str(key), {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		# Les éliminés ne peuvent plus gagner au temps (mêmes « contenders » que le serveur).
		if str(p.get("status", "alive")) == "eliminated":
			continue
		var pv_max := int(p.get("hero_pv_max", 0))
		var pv_pct := 0 if pv_max <= 0 else int(floor(100.0 * float(p.get("hero_pv_current", 0)) / float(pv_max)))
		# % d'objectif : le nôtre est réel (le tracker le calcule déjà), celui des autres est SECRET.
		var objective_txt := tr("SCOREBOARD_UNKNOWN")
		if pid == _my_id():
			objective_txt = "%d%%" % int(floor(100.0 * _my_objective_ratio()))
		rows.append({
			"name": _display_name(pid).to_upper(),
			"color": board.get_player_color(pid),
			"objective": objective_txt,
			"hero_pv": pv_pct,
			"kills": int(kills_by.get(str(pid), kills_by.get(pid, 0))),
		})
	rows.sort_custom(func(a, b):
		if int(a.get("hero_pv", 0)) != int(b.get("hero_pv", 0)):
			return int(a.get("hero_pv", 0)) > int(b.get("hero_pv", 0))
		return int(a.get("kills", 0)) > int(b.get("kills", 0)))
	return rows


# Notre PROPRE progression d'objectif (0..1) : réutilise le module PUR du tracker et le MÊME
# contexte — une 2ᵉ formule locale finirait par diverger de la jauge affichée juste à côté.
func _my_objective_ratio() -> float:
	var obj: Dictionary = GameState.objectives.get(str(_my_id()), {})
	if typeof(obj) != TYPE_DICTIONARY or obj.is_empty():
		return 0.0
	return float(ObjectiveTracker.progress(obj, _objective_ctx()).get("best_ratio", 0.0))


# NB (lot A) : l'ancien tiroir « INTEL : GUERRE » (E5 §8.77) est SUPPRIMÉ de l'arène — le module
# PUR `WarRoom` reste la source unique des compteurs, désormais consommée par le Rapport Post-Op
# (podium + BILAN) et par la fiche joueur ; aucune donnée n'est perdue.

# Tracker d'objectif vivant (E6 §8.78) : résout le CONTEXTE public (mes territoires, mes
# continents entièrement possédés, statut de la cible d'élimination) et pousse la progression
# au HUD (module pur ObjectiveTracker). Notre propre objectif porte type/params/description
# (§4.4) — aucune fuite : le nom de la cible est déjà dans notre description.
# Contexte PUBLIC de progression d'objectif — MIROIR de `api/game/objectives.build_context`.
# EXTRAIT de `_push_objective_tracker` (chantier « Tension », LOT F) parce qu'il a désormais DEUX
# consommateurs : la jauge du HUD et le mini-classement de départage (`_my_objective_ratio`). Une
# 2ᵉ construction locale aurait fini par afficher deux pourcentages différents du même objectif.
func _objective_ctx() -> Dictionary:
	var me := _my_id()
	# Mes continents ENTIÈREMENT possédés + ma possession PAR continent (carte courante G5).
	var cont_terrs: Dictionary = MapData.get_map(GameState.map_id).get("continent_territories", {})
	var my_continents := 0
	var owned_by_continent := {}
	var continent_sizes := {}
	for cid in cont_terrs.keys():
		var tids: Array = cont_terrs[cid]
		continent_sizes[str(cid)] = tids.size()
		var mine := 0
		for tid in tids:
			var t: Dictionary = GameState.territories.get(str(tid), {})
			var o = t.get("owner_id")
			if o != null and int(o) == me:
				mine += 1
		owned_by_continent[str(cid)] = mine
		if not tids.is_empty() and mine == tids.size():
			my_continents += 1
	# Garnisons de MES territoires (fortified_hold) — une seule passe sur la carte.
	var owned_garrisons: Array = []
	for tid in GameState.territories.keys():
		var t2: Dictionary = GameState.territories.get(str(tid), {})
		var o2 = t2.get("owner_id")
		if o2 != null and int(o2) == me:
			owned_garrisons.append(int(t2.get("garrison", 0)))
	# MES kills AU COMBAT (destroy_units) — jamais les kills de ZONE (la zone tue sans mérite).
	var stats: Dictionary = GameState.statistics if typeof(GameState.statistics) == TYPE_DICTIONARY else {}
	var ck: Dictionary = stats.get("combat_kills_by_player", {}) \
		if typeof(stats.get("combat_kills_by_player")) == TYPE_DICTIONARY else {}
	# Cible d'élimination (volet kill de l'objectif double) : id au 1er niveau des params (§8.61).
	var obj0: Dictionary = GameState.objectives.get(str(me), {})
	var target_id := -9999
	if typeof(obj0) == TYPE_DICTIONARY:
		target_id = int(obj0.get("params", {}).get("target_id", -9999))
	var target_alive := true
	if GameState.players.has(str(target_id)):
		var tp: Dictionary = GameState.players.get(str(target_id), {})
		target_alive = str(tp.get("status", "alive")) != "eliminated" and not bool(tp.get("is_dead", false))
	return {
		"owned_count": WarRoom.territory_count(GameState.territories, me),
		"continents_owned": my_continents,
		"target_alive": target_alive,
		"target_name": _display_name(target_id) if target_id != -9999 else tr("GAME_TARGET_FALLBACK"),
		"owned_by_continent": owned_by_continent,
		"continent_sizes": continent_sizes,
		"combat_kills": int(ck.get(str(me), ck.get(me, 0))),
		"owned_garrisons": owned_garrisons,
	}

# =========================================================
# BATTLE ROYALE (§8.125) — mises en scène plein écran
# =========================================================
const CoupAlarmScript := preload("res://scripts/game/coup_alarm.gd")
const CrateRevealScript := preload("res://scripts/game/crate_reveal.gd")

# Une seule surcouche à la fois : deux caisses coup sur coup (ou une caisse pendant une alarme) se
# superposeraient en un magma illisible. La seconde est simplement SAUTÉE — son effet mécanique,
# lui, est déjà appliqué côté serveur, on ne perd donc que l'animation.
var _br_overlay: Control = null


func _play_battle_royale_feedback(event) -> void:
	if typeof(event) != TYPE_DICTIONARY or GameState.team_mode == "":
		return

	# --- CAISSES : attachées à l'attaque qui a franchi le palier (clé `crates`). ---
	var crates = event.get("crates", [])
	if typeof(crates) == TYPE_ARRAY and not crates.is_empty():
		var crate = crates[0]
		if typeof(crate) == TYPE_DICTIONARY:
			# Une caisse ne concerne QUE l'équipe qui l'a méritée : la montrer à l'adversaire
			# serait lui annoncer que l'autre camp vient de se renforcer.
			if int(crate.get("team_id", 0)) == GameState.team_of(_my_id()):
				var shares: Dictionary = crate.get("shares", {}) if 					typeof(crate.get("shares")) == TYPE_DICTIONARY else {}
				var named := {}
				for pid in shares:
					named[_display_name(int(pid))] = int(shares[pid])
				# SUIVI DES PRIMES (2026-08-01) : on ARCHIVE la caisse avant de l'animer. Le
				# détail (`shares`) ne vit QUE dans cet évènement — l'état de partie, lui, ne
				# transporte que le compteur de caisses ouvertes. Sans cette capture, la part
				# revenue au joueur serait définitivement perdue au bout de trois secondes.
				hud.push_crate_record(str(crate.get("reward_id", "")),
					int(crate.get("total", 0)),
					int(shares.get(str(_my_id()), shares.get(_my_id(), 0))),
					int(crate.get("team_kills", 0)))
				_show_br_overlay(CrateRevealScript, func(node):
					node.play(str(crate.get("reward_id", "")), int(crate.get("total", 0)), named,
						int(crate.get("team_kills", 0))))

	# --- COUP D'ÉTAT : vu par TOUS, c'est tout son intérêt. ---
	if str(event.get("event_type", "")) == "coup_detat":
		var traitor := _display_name(int(event.get("traitor_id", 0)))
		var victim := _display_name(int(event.get("victim_id", 0)))
		var success := bool(event.get("success", false))
		_show_br_overlay(CoupAlarmScript, func(node): node.play(success, traitor, victim))


func _show_br_overlay(script_res, starter: Callable) -> void:
	if _br_overlay != null and is_instance_valid(_br_overlay):
		return   # une seule surcouche à la fois (cf. `_br_overlay`).
	var node := Control.new()
	node.set_script(script_res)
	add_child(node)   # dernier enfant de Main → dessiné au-dessus de tout.
	_br_overlay = node
	node.finished.connect(func() -> void: _br_overlay = null)
	starter.call(node)


# Contexte COMBINÉ de l'objectif d'ÉQUIPE (MODE ÉQUIPES §8.124) — MIROIR d'
# `api/game/objectives.build_team_context`. MÊMES CLÉS que `_objective_ctx` : les formules du
# tracker sont donc les mêmes des deux côtés, seul le PÉRIMÈTRE change (mon camp au lieu de moi).
#
# ⚠️ « Combiné » = UNION là où ça compte : un continent est acquis à l'ÉQUIPE si chacun de ses
# territoires appartient à l'un OU l'AUTRE de ses membres — un continent partagé à deux compte donc
# UNE fois, alors qu'il ne comptait pour personne en lecture individuelle. C'est la seule règle du
# mode où « partager » RAPPORTE, et la jauge doit le montrer, sinon les coéquipiers ne comprendront
# jamais pourquoi ils devraient se répartir un continent.
#
# Membres MORTS inclus : leurs territoires restent sur la carte, exactement comme côté serveur —
# sans quoi la jauge partagée chuterait au moment où l'équipe vient de perdre quelqu'un.
func _team_objective_ctx() -> Dictionary:
	var members := GameState.teammates_of(_my_id())
	members.append(_my_id())
	var owned := {}
	for m in members:
		owned[int(m)] = true

	var cont_terrs: Dictionary = MapData.get_map(GameState.map_id).get("continent_territories", {})
	var team_continents := 0
	var owned_by_continent := {}
	var continent_sizes := {}
	for cid in cont_terrs.keys():
		var tids: Array = cont_terrs[cid]
		continent_sizes[str(cid)] = tids.size()
		var ours := 0
		for tid in tids:
			var t: Dictionary = GameState.territories.get(str(tid), {})
			var o = t.get("owner_id")
			if o != null and owned.has(int(o)):
				ours += 1
		owned_by_continent[str(cid)] = ours
		if not tids.is_empty() and ours == tids.size():
			team_continents += 1

	var owned_count := 0
	var owned_garrisons: Array = []
	for tid in GameState.territories.keys():
		var t2: Dictionary = GameState.territories.get(str(tid), {})
		var o2 = t2.get("owner_id")
		if o2 != null and owned.has(int(o2)):
			owned_count += 1
			owned_garrisons.append(int(t2.get("garrison", 0)))

	var stats: Dictionary = GameState.statistics if typeof(GameState.statistics) == TYPE_DICTIONARY else {}
	var ck: Dictionary = stats.get("combat_kills_by_player", {}) \
		if typeof(stats.get("combat_kills_by_player")) == TYPE_DICTIONARY else {}
	var kills := 0
	for m in members:
		kills += int(ck.get(str(int(m)), ck.get(int(m), 0)))

	return {
		"owned_count": owned_count,
		"continents_owned": team_continents,
		"owned_by_continent": owned_by_continent,
		"continent_sizes": continent_sizes,
		"combat_kills": kills,
		"owned_garrisons": owned_garrisons,
	}


# Objectif d'ÉQUIPE du joueur local, DÉJÀ REDACTÉ par le serveur (§3.4 — on ne reçoit que le nôtre).
# {} en FFA, ou si l'entrée est le marqueur « hidden » (ce qui ne devrait jamais arriver pour NOTRE
# équipe, mais un état corrompu ne doit pas afficher « type: hidden » dans la jauge).
func _my_team_objective() -> Dictionary:
	if GameState.team_mode == "":
		return {}
	var tid := GameState.team_of(_my_id())
	if tid == 0:
		return {}
	var obj = GameState.team_objectives.get(str(tid), GameState.team_objectives.get(tid, {}))
	if typeof(obj) != TYPE_DICTIONARY or str(obj.get("type", "")) in ["", "hidden"]:
		return {}
	return obj


func _push_objective_tracker() -> void:
	# MODE ÉQUIPES (§8.124) : c'est l'objectif d'ÉQUIPE qui pilote la jauge — le seul qui fasse
	# GAGNER (l'objectif individuel ne décide plus rien en équipe, cf. `engine._check_team_victory`).
	# Afficher l'individuel aurait envoyé les joueurs courir après une victoire impossible.
	var team_obj := _my_team_objective()
	if not team_obj.is_empty():
		var tctx := _team_objective_ctx()
		var tdata := ObjectiveTracker.progress(team_obj, tctx)
		var ttxt := ObjectiveTracker.describe(team_obj)
		if ttxt == "":
			ttxt = str(team_obj.get("description", ""))
		hud.set_objective_progress(tdata, "%s\n%s" % [tr("TEAM_OBJECTIVE_TITLE"), ttxt])
		return

	var obj: Dictionary = GameState.objectives.get(str(_my_id()), {})
	if typeof(obj) != TYPE_DICTIONARY or obj.is_empty():
		hud.set_objective_progress({})
		return
	var ctx := _objective_ctx()
	var target_id := int(obj.get("params", {}).get("target_id", -9999))
	var data := ObjectiveTracker.progress(obj, ctx)
	# i18n (2026-07-18) : description composée LOCALEMENT (type/params) en langue courante,
	# repli sur la description serveur (anglais invariant) pour un type inconnu.
	var obj_txt := ObjectiveTracker.describe(obj,
		_display_name(target_id) if target_id != -9999 else "")
	if obj_txt == "":
		obj_txt = str(obj.get("description", ""))
	# Lot A : le rappel « dernier survivant » est désormais rendu EN CLAIR sous la jauge (zone
	# OBJECTIFS) — le tooltip ne porte plus que la description complète de l'objectif.
	var tooltip := obj_txt
	hud.set_objective_progress(data, tooltip)

# =========================================================
# Résolution visuelle des combats (Split-Screen VS)
# =========================================================

# Superpose la scène d'affrontement des héros de factions (dés façon machine à sous) et
# FIGE la mise à jour visuelle du plateau jusqu'à la fin de l'animation. Le refresh mis en
# attente pendant l'animation (_refresh_pending) est rejoué à la sortie.
func _play_combat_resolution(event: Dictionary) -> void:
	# ENTRÉE : si un combat s'anime déjà, on met celui-ci en FILE au lieu de le JETER — sa perte de PV
	# s'animera à son tour, au lieu de « sauter » à la valeur finale sans transition (perçu comme des
	# « PV disparus sans raison », typiquement pendant un tour de bot enchaînant plusieurs attaques).
	if _combat_animating:
		if _combat_queue.size() < COMBAT_QUEUE_CAP:
			_combat_queue.append(event.duplicate(true))
		return
	_combat_animating = true
	# §8.122 (LOT D) : la carte vivante se met en retrait pendant le spectacle (aucune nuée
	# d'oiseaux lancée par-dessus un duel). Levé par _combat_finished, à la fin des DEUX files.
	board.set_ambient_busy(true)
	await _do_play_combat(event)

# Identité d'un camp d'un attack_result — le SERVEUR fait AUTORITÉ (§8.85).
#
# Pourquoi : le snapshot d'affichage (_displayed_owners) ne suffit PAS. Pendant un tour de bot les
# attaques s'enchaînent toutes les ~1 s alors qu'une animation VS dure plusieurs secondes → les
# combats s'empilent dans _combat_queue et _refresh() (qui met à jour _displayed_owners) est différé
# jusqu'au drainage complet. Or un bot attaque très souvent DEPUIS le territoire qu'il vient de
# conquérir : au moment où ce combat s'anime, le snapshot porte encore l'ANCIEN propriétaire (souvent
# l'humain) → pseudo/faction/héros/couleur d'un joueur non impliqué, jusqu'au « mon personnage attaque
# mon personnage » quand la cible est aussi à lui.
#
# `fallback` = la valeur historique propre à CHAQUE site d'appel (leurs sentinelles diffèrent :
# -1 « neutre » via _owner(), -9999 « inconnu ») : elle est conservée telle quelle si le champ est
# absent → repli SILENCIEUX sur le comportement actuel quand le VPS n'est pas encore redéployé (§9.2).
# `defender_player_id` vaut null pour un territoire NEUTRE → -1, sentinelle « sans propriétaire »
# déjà rendue par _owner() (aucune régression sur les attaques de neutres).
func _event_pid(event: Dictionary, key: String, fallback: int) -> int:
	if event.has(key):
		var v = event.get(key)
		return int(v) if v != null else -1
	return fallback

# Animation d'UN combat (déjà sous verrou _combat_animating). À la fin, draine la file via _combat_finished().
func _do_play_combat(event: Dictionary) -> void:
	var atk_tid := str(event.get("attacker_territory_id", ""))
	var def_tid := str(event.get("defender_territory_id", ""))
	# Identités des deux camps : champs serveur en PRIORITÉ (§8.85), repli sur les propriétaires tels
	# qu'AFFICHÉS avant le combat (snapshot de _refresh) — l'état courant est déjà post-combat (le
	# territoire conquis appartient déjà à l'attaquant).
	var atk_owner := _event_pid(event, "attacker_player_id",
		int(_displayed_owners.get(atk_tid, _owner(atk_tid))))
	var def_owner := _event_pid(event, "defender_player_id",
		int(_displayed_owners.get(def_tid, _owner(def_tid))))

	# ROUTAGE DES ANIMATIONS (lot D — REFONTE UI ARÈNE, simplifié le 2026-07-27) :
	#   je suis attaquant OU défenseur  → Split-Screen VS plein écran (vitrine skins M5, Time Bank,
	#                                     duel de héros) ;
	#   combat entre les AUTRES         → flèche de guerre + explosion IN-BOARD (aucun plein écran,
	#                                     aucun recadrage caméra — cf. _maybe_focus_combat) ;
	#   héros abattu (n'importe qui)    → animation normale PUIS cinématique de mise à mort plein
	#                                     écran pour TOUS.
	# ⚠️ Le réglage `combat_display` (ex-E8 §8.80 : cinematique/rapide/bandeau puis standard/rapide/
	# minimal) est SUPPRIMÉ — décision Hakim : le rythme RAPIDE est le seul retenu, il devient le
	# comportement unique et non négociable (VS pré-accéléré ×COMBAT_VS_SPEED, flèche condensée).
	# Plus rien ne lit SettingsManager.get_comfort("combat_display").
	var am_participant: bool = int(atk_owner) == _my_id() or int(def_owner) == _my_id()
	# Chaîne de ré-assaut (E7) : 2ᵉ+ assaut consécutif sur la MÊME paire → version condensée du VS.
	# INDÉPENDANT de la vitesse : c'est un raccourci de NARRATION (on ne rejoue pas la mise en place
	# des héros pour le 3ᵉ assaut d'affilée sur la même cible).
	var pair := "%s>%s" % [atk_tid, def_tid]
	var condensed := pair == _last_combat_pair
	_last_combat_pair = pair
	var duel = event.get("hero_duel")
	var hero_died: bool = typeof(duel) == TYPE_DICTIONARY and bool(duel.get("hero_died", false))

	if not am_participant:
		# Flèche de guerre : passe dans la MÊME file _combat_animating — AUCUN état ne se peint
		# pendant une résolution (piège n° 4). Le HUD n'est PAS masqué (pas de plein écran).
		# TOUJOURS condensée (~0,7 s) : c'est le rythme rapide, désormais unique.
		await _play_attack_arrow(event, atk_owner, def_owner, true)
		_after_combat_animation(event, atk_owner, def_owner, duel, hero_died)
		return

	# Le Split-Screen VS sacralise l'affrontement des héros : on efface le HUD flottant pendant
	# le duel (fondu 0,5 s, §8.29). La scène VS est enfant de Main (hors HUD) → elle reste visible.
	hud.fade_ui_for_combat(true)

	var vs_screen := SplitScreenVSScene.instantiate()
	add_child(vs_screen) # dernier enfant de Main -> dessiné au-dessus du HUD (surcouche)
	# §3 Warzone : on transmet les pertes + le Time Bank. local_is_attacker se base sur l'ATTAQUANT
	# DE CE COMBAT (§8.85) et non sur GameState.current_player_id : un combat DÉFILÉ depuis la file
	# s'anime alors que le tour courant a pu changer → « TIME BANK +10s » s'affichait au mauvais camp.
	# Garnisons « avant ➜ après » (E2 §8.74) : avant = snapshot AFFICHÉ pré-combat (exact même
	# en cas de conquête) ; après = état courant (déjà post-combat). Repli avant = après + pertes
	# (1er combat avant tout _refresh — jamais le cas en pratique, garde-fou).
	var atk_g_after := _garrison(atk_tid)
	var def_g_after := _garrison(def_tid)
	var atk_g_before := int(_displayed_garrisons.get(atk_tid,
		atk_g_after + int(event.get("attacker_losses", 0))))
	var def_g_before := int(_displayed_garrisons.get(def_tid,
		def_g_after + int(event.get("defender_losses", 0))))
	vs_screen.start_combat_resolution(
		_faction_of_player(atk_owner), _faction_of_player(def_owner),
		event.get("attacker_rolls", []), event.get("defender_rolls", []),
		{
			"attacker_losses": int(event.get("attacker_losses", 0)),
			"defender_losses": int(event.get("defender_losses", 0)),
			"time_bank_bonus": int(event.get("time_bank_bonus_seconds", 0)),
			"local_is_attacker": int(atk_owner) == _my_id(),
			# Skins équipés (M5 §8.69) : lus du PlayerState PUBLIC de chaque camp — les DEUX
			# joueurs voient le skin de l'autre dans le Split-Screen VS (moment vitrine).
			"attacker_skin": _equipped_skin_of(atk_owner),
			"defender_skin": _equipped_skin_of(def_owner),
			# --- E2 §8.74 : le combat raconte les HÉROS (Dictionary rétro-compatible). ---
			"attacker_pid": int(atk_owner), "defender_pid": int(def_owner),
			# Pseudo transmis SEULEMENT si le joueur existe (un owner -1 « neutre » afficherait
			# sinon « [IA] Bot 1 ») ; pseudo vide → le VS garde ses rôles legacy (rétro-compat).
			"attacker_name": _display_name(int(atk_owner)) \
				if GameState.players.has(str(int(atk_owner))) else "",
			"defender_name": _display_name(int(def_owner)) \
				if GameState.players.has(str(int(def_owner))) else "",
			"attacker_color": board.get_player_color(int(atk_owner)),
			"defender_color": board.get_player_color(int(def_owner)),
			# ⚠️ hero_of reflète l'état POST-combat : les PV pré-duel du défenseur se
			# reconstituent par defender_pv + damage (champs du duel) — jamais d'état antérieur.
			"attacker_hero": GameState.hero_of(int(atk_owner)),
			"defender_hero": GameState.hero_of(int(def_owner)),
			"hero_duel": event.get("hero_duel"),  # null si héros non initialisés (§8.61)
			"attacker_garrison_before": atk_g_before, "attacker_garrison_after": atk_g_after,
			"defender_garrison_before": def_g_before, "defender_garrison_after": def_g_after,
			# Rythme (ex-E8 §8.80) : le Split-Screen VS démarre TOUJOURS pré-accéléré — le mode
			# « rapide » est devenu le comportement unique (le réglage a été supprimé).
			"speed": COMBAT_VS_SPEED,
			"condensed": condensed,
		})
	await vs_screen.animation_finished

	# Combat lu : on rétablit le HUD flottant (fondu inverse 0,5 s, §8.29).
	hud.fade_ui_for_combat(false)
	_after_combat_animation(event, atk_owner, def_owner, duel, hero_died)

# Épilogue COMMUN aux deux animations (VS plein écran ET flèche in-board) :
#   1. flash de conquête + fanfare — joués APRÈS la narration du combat (avant le lot D, le flash
#      partait à la réception de l'évènement, donc AVANT l'animation : la conquête était « spoilée ») ;
#   2. cinématique de mise à mort si un héros est tombé — pour TOUS les joueurs ;
#   3. drainage de la file (combats en attente, puis actions adverses du lot C).
func _after_combat_animation(event: Dictionary, atk_owner, def_owner, duel, hero_died: bool) -> void:
	# Lot E : toasts d'ACTIVATION des pouvoirs déclenchés par ce combat (Phalanges, Aegis, Terreur,
	# Razzia, Embuscade) — jusqu'ici, deux d'entre eux n'apparaissaient nulle part.
	_push_combat_power_toasts(event, atk_owner, def_owner)
	if bool(event.get("conquered", false)):
		AudioManager.play_sfx("conquest")
		if _vfx_enabled():
			board.conquest_flash(str(event.get("defender_territory_id", "")),
				board.get_player_color(int(atk_owner)))
	if hero_died:
		await _play_hero_down(duel, atk_owner, def_owner)
	_combat_finished()

# =========================================================
# Flèche de guerre + explosion (lot D) — combats qui ne me concernent pas
# =========================================================
# Instanciée DANS le plateau (enfant de Board → coordonnées monde). Repli SILENCIEUX sur le bandeau
# compact (E8 §8.80) si une position de territoire est introuvable (carte réduite G5, état partiel)
# — jamais de crash, jamais de combat muet.
func _play_attack_arrow(event: Dictionary, atk_owner, def_owner, condensed: bool) -> void:
	var atk_tid := str(event.get("attacker_territory_id", ""))
	var def_tid := str(event.get("defender_territory_id", ""))
	var from: Vector2 = board.get_territory_position(atk_tid)
	var to: Vector2 = board.get_territory_position(def_tid)
	if from == Vector2.INF or to == Vector2.INF:
		await _play_combat_banner(event, atk_owner, def_owner)
		return
	var arrow = AttackArrowScene.instantiate()
	board.add_child(arrow)
	var dmg := 0
	var duel = event.get("hero_duel")
	if typeof(duel) == TYPE_DICTIONARY:
		dmg = int(duel.get("damage", 0))
	arrow.play(from, to, board.get_player_color(int(atk_owner)), {
		"atk_losses": int(event.get("attacker_losses", 0)),
		"def_losses": int(event.get("defender_losses", 0)),
		"hero_damage": dmg,
		"conquered": bool(event.get("conquered", false)),
		"marks": _combat_power_marks(event),
	}, condensed)
	await arrow.finished

# =========================================================
# Cinématique de mise à mort (lot D) — permadeath §8.61, visible par TOUS
# =========================================================
# Le finisher joué est celui du TUEUR (champ PUBLIC `equipped_finisher`, lot G) ; id vide/inconnu
# → basique gratuit (repli silencieux du registre finishers.gd). Garde IDEMPOTENTE par victime :
# une reconnexion qui rejouerait l'évènement ne rejoue pas la cinématique.
var _hero_down_played: Dictionary = {}

func _play_hero_down(duel, atk_owner, def_owner) -> void:
	var victim := int(duel.get("defender_id", def_owner)) if typeof(duel) == TYPE_DICTIONARY else int(def_owner)
	if _hero_down_played.has(victim):
		return
	_hero_down_played[victim] = true
	var killer := int(duel.get("attacker_id", atk_owner)) if typeof(duel) == TYPE_DICTIONARY else int(atk_owner)
	var cine = HeroDownCinematicScene.instantiate()
	add_child(cine)   # dernier enfant de Main → dessiné AU-DESSUS du HUD
	cine.play({
		"killer_name": _display_name(killer),
		"killer_color": board.get_player_color(killer),
		"killer_portrait": _hero_portrait_of(killer),
		"victim_name": _display_name(victim),
		"victim_color": board.get_player_color(victim),
		"finisher_id": _equipped_finisher_of(killer),
	})
	await cine.finished

# Portrait du héros d'un joueur (hero_path du .tres de sa faction, déjà mis en cache) — null si
# la ressource manque : la cinématique s'affiche alors sans portrait (repli silencieux).
func _hero_portrait_of(pid: int) -> Texture2D:
	var fid := _faction_of_player(pid)
	var hp := str(_faction_info(fid).get("hero_path", ""))
	if hp == "" or not ResourceLoader.exists(hp):
		return null
	var res = load(hp)
	return res if res is Texture2D else null

# Finisher équipé d'un joueur (lot G) — champ PUBLIC de son PlayerState ("" = basique gratuit).
# Absent d'un serveur non redéployé → "" → basique : le client fonctionne SANS le champ (§9.2).
func _equipped_finisher_of(pid) -> String:
	if pid == null:
		return ""
	var p = GameState.players.get(str(int(pid)), {})
	if typeof(p) == TYPE_DICTIONARY:
		return str(p.get("equipped_finisher", ""))
	return ""

# Fin d'UN combat : draine la FILE (chaque duel s'anime) AVANT tout rafraîchissement. _combat_animating
# reste vrai pendant tout le drainage → aucun état ne se peint, input figé, ordre des combats préservé.
# Lot C : la file des actions adverses NON-combat s'enchaîne ensuite sur le MÊME verrou (aucun
# chevauchement possible entre une flèche/un VS et un toast d'action).
func _combat_finished() -> void:
	if not _combat_queue.is_empty():
		var next_event: Dictionary = _combat_queue.pop_front()
		call_deferred("_do_play_combat", next_event)
		return
	if not _pace_queue.is_empty():
		call_deferred("_play_pace_queue")
		return
	_combat_animating = false
	board.set_ambient_busy(false)   # §8.122 (LOT D) : les deux files sont vides, la carte revit.
	if _refresh_pending:
		_refresh_pending = false
		_refresh()

# =========================================================
# Rythme des tours adverses (lot C) — file d'actions NON-combat
# =========================================================

# Doit-on mettre cet évènement en file ? Uniquement en partie EN COURS, pour un acteur qui n'est
# PAS moi (mes propres actions restent instantanées) et pour un type d'action « racontable ».
func _maybe_pace_event(event) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	var etype := str(event.get("event_type", ""))
	if not PACE_EVENT_KEYS.has(etype) or GameState.stage != "playing":
		return
	# Acteur : champ explicite du payload quand il existe (card_played/card_kept), sinon le joueur
	# courant — pour ces actions le tour ne change pas, l'acteur EST le joueur courant.
	var actor := int(event.get("player_id", GameState.current_player_id))
	if actor == _my_id():
		return
	_pace_queue.append(event.duplicate(true))
	while _pace_queue.size() > PACE_QUEUE_CAP:
		_pace_queue.pop_front()
	# Si une animation (combat ou action) est déjà en cours, _combat_finished prendra le relais.
	if not _combat_animating:
		_combat_animating = true
		board.set_ambient_busy(true)   # §8.122 (LOT D) — cf. _play_combat_resolution.
		_play_pace_queue()

# Draine la file : un toast + un flash de territoire par action, puis rend la main à
# _combat_finished (qui enchaîne sur un combat en attente, ou libère le verrou et rejoue le
# rafraîchissement différé).
func _play_pace_queue() -> void:
	while not _pace_queue.is_empty():
		var e: Dictionary = _pace_queue.pop_front()
		var step := PACE_STEP_TIME_FAST if _pace_queue.size() > PACE_QUEUE_RUSH else PACE_STEP_TIME
		var actor := int(e.get("player_id", GameState.current_player_id))
		var line := _pace_line(e, actor)
		if line != "":
			hud.show_action_toast(line, board.get_player_color(actor), step)
		var tid := _pace_territory(e)
		if tid != "" and _vfx_enabled():
			board.flash_territory(tid)
		await get_tree().create_timer(step).timeout
	_combat_finished()

# Libellé TRADUIT d'une action adverse (« [IA] RAIDER-2 ❯ déploie 4 unités sur Oural »).
func _pace_line(e: Dictionary, actor: int) -> String:
	var who := _bb_pseudo(actor)
	match str(e.get("event_type", "")):
		"units_deployed", "initial_units_placed":
			var n := _deployments_count(e)
			var amount := int(e.get("amount", 0))
			if n > 1:
				return tr("PACE_DEPLOY_MULTI_FMT") % [who, amount, n]
			var tid := _pace_territory(e)
			return tr("PACE_DEPLOY_FMT") % [who, amount, _territory_name(tid)]
		"units_moved":
			return tr("PACE_MOVE_FMT") % [who, int(e.get("amount", 0)),
				_territory_name(str(e.get("source_territory_id", ""))),
				_territory_name(str(e.get("target_territory_id", "")))]
		"card_played", "card_kept":
			return tr("PACE_CARD_FMT") % [who, int(e.get("card_value", 0))]
		"conquer_move_resolved":
			return tr("PACE_CONQUER_MOVE_FMT") % [who, int(e.get("troops", 0)),
				_territory_name(str(e.get("to_tid", "")))]
	return ""

# Territoire à faire FLASHER pour une action adverse ("" si l'action n'en cible pas un seul).
func _pace_territory(e: Dictionary) -> String:
	match str(e.get("event_type", "")):
		"units_deployed", "initial_units_placed":
			if e.has("territory_id"):
				return str(e.get("territory_id"))
			var d = e.get("deployments", {})
			if typeof(d) == TYPE_DICTIONARY and not (d as Dictionary).is_empty():
				return str((d as Dictionary).keys()[0])
		"units_moved":
			return str(e.get("target_territory_id", ""))
		"conquer_move_resolved":
			return str(e.get("to_tid", ""))
	return ""

# Bandeau compact d'un combat où JE ne suis pas impliqué (E8 §8.80, mode "bandeau") : ~2,2 s
# haut-centre — chips E1 des deux camps, dés figés, pertes, -PV héros. Le kill feed E4 complète.
# Passe dans la MÊME file _combat_animating (durée courte) — aucun état ne se peint pendant.
func _play_combat_banner(event: Dictionary, atk_owner, def_owner) -> void:
	var duel = event.get("hero_duel")
	hud.show_combat_banner({
		"atk_pid": int(atk_owner), "def_pid": int(def_owner),
		"atk_rolls": event.get("attacker_rolls", []),
		"def_rolls": event.get("defender_rolls", []),
		"atk_losses": int(event.get("attacker_losses", 0)),
		"def_losses": int(event.get("defender_losses", 0)),
		"hero_damage": int(duel.get("damage", 0)) if typeof(duel) == TYPE_DICTIONARY else 0,
		"hero_died": bool(duel.get("hero_died", false)) if typeof(duel) == TYPE_DICTIONARY else false,
		"conquered": bool(event.get("conquered", false)),
	})
	await get_tree().create_timer(2.2).timeout

# Id de faction d'un joueur (clé "faction" du PlayerState diffusé par le serveur).
# Les clés de GameState.players sont des STRINGS (JSON) et pid peut être un float : on
# normalise via int() (piège Godot des ids JSON, cf. CONTEXTE.md §5).
func _faction_of_player(pid) -> String:
	var p = GameState.players.get(str(int(pid)), {})
	if typeof(p) == TYPE_DICTIONARY:
		return str(p.get("faction", ""))
	return ""

# Skin équipé d'un joueur (M5 §8.69) — champ PUBLIC de son PlayerState ("" si aucun / inconnu).
func _equipped_skin_of(pid) -> String:
	if pid == null:
		return ""
	var p = GameState.players.get(str(int(pid)), {})
	if typeof(p) == TYPE_DICTIONARY:
		return str(p.get("equipped_skin", ""))
	return ""

# Caméra tactique : sur un résultat d'attaque, travelling vers les deux belligérants (zoom 1,5×)
# puis retour à la vue d'ensemble — UNIQUEMENT pour MES combats (ceux qui ouvrent le Split-Screen
# VS). Retour Hakim (2026-07-27) : sur les combats des AUTRES, désormais racontés par la flèche de
# guerre (~0,7 s), le travelling durait à lui seul 0,8 s + 0,8 s de retour — la caméra passait son
# temps en allers-retours pendant les tours de bots, pour une animation déjà terminée. La flèche se
# lit très bien en vue d'ensemble : plus AUCUN recadrage pour ces combats-là.
# (La micro-secousse de l'explosion est conservée : elle joue sur `offset`, ne déplace pas la vue
# et ne coûte rien — c'est le feedback d'impact, pas un recadrage.)
func _maybe_focus_combat(event) -> void:
	if typeof(event) != TYPE_DICTIONARY or str(event.get("event_type", "")) != "attack_result":
		return
	var atk_tid := str(event.get("attacker_territory_id", ""))
	var def_tid := str(event.get("defender_territory_id", ""))
	# Identités = champs serveur en PRIORITÉ (§8.85), repli sur le snapshot pré-combat — mêmes
	# résolutions que _do_play_combat, pour que les deux prennent EXACTEMENT la même décision.
	var atk_owner := _event_pid(event, "attacker_player_id",
		int(_displayed_owners.get(atk_tid, _owner(atk_tid))))
	var def_owner := _event_pid(event, "defender_player_id",
		int(_displayed_owners.get(def_tid, _owner(def_tid))))
	if int(atk_owner) != _my_id() and int(def_owner) != _my_id():
		return
	var pos_a: Vector2 = board.get_territory_position(atk_tid)
	var pos_b: Vector2 = board.get_territory_position(def_tid)
	if pos_a == Vector2.INF or pos_b == Vector2.INF:
		return
	camera.focus_on_combat(pos_a, pos_b)
	get_tree().create_timer(2.5).timeout.connect(camera.reset_view)

func _on_game_error(message: String):
	# L'action a été refusée par le serveur → on déverrouille pour réessayer.
	_pass_in_flight = false
	_attack_in_flight = false  # attaque refusée (doublon, non adjacent…) : on lève le verrou (jamais de soft-lock)
	# §8.119 — refus CODÉ (`reason`) : on journalise la phrase TRADUITE au lieu du message serveur
	# non localisé. Lu immédiatement (la propriété est écrasée au refus suivant). Code inconnu →
	# on retombe sur le `message` serveur ci-dessous, jamais sur du vide.
	var reason := str(NetworkManager.last_error_reason)
	# §8.123 — refus de PACTE : mêmes codes machine, même traitement, mais le seul refus CHIFFRÉ du
	# jeu (`cooldown`) doit dire COMBIEN de rounds il reste, sinon « trop tôt » n'apprend rien.
	# Testé AVANT les capacités : les deux jeux de codes partagent des noms (`invalid_target`,
	# `not_your_turn`) et seul le contexte les distingue — d'où le préfixe `PACT_ERR_*` distinct.
	var coded_family := _last_coded_action
	_last_coded_action = ""
	if reason != "" and PACT_ERROR_KEYS.has(reason) and coded_family == "pact":
		var key := str(PACT_ERROR_KEYS[reason])
		var text := (tr(key) % int(NetworkManager.last_error_remaining_rounds)) \
			if key == "PACT_ERR_COOLDOWN" else tr(key)
		hud.add_log("⚠ " + text)
		_refresh_player_sheet()
		return
	# §8.125 — refus d'une action BATTLE ROYALE. Testé AVANT les capacités, pour la même raison que
	# les pactes : les jeux de codes partagent des noms et seul le contexte les distingue.
	if reason != "" and BR_ERROR_KEYS.has(reason) and coded_family == "br":
		_coup_armed = false   # un refus DÉSARME le coup d'État (on ne laisse jamais un piège armé).
		hud.add_log("⚠ " + tr(str(BR_ERROR_KEYS[reason])))
		_push_power_card()
		return
	if reason != "" and ABILITY_ERROR_KEYS.has(reason):
		_cancel_ability_targeting()
		hud.add_log("⚠ " + tr(str(ABILITY_ERROR_KEYS[reason])))
		return
	if _deploy_in_flight:
		_deploy_in_flight = false
		# Refus du déploiement : on RESTAURE le tampon (et on lève le verrou aveugle de Phase 0) pour
		# que le joueur recompose / re-confirme sans tout reperdre, au lieu d'un soft-lock.
		pending_deployments = _deploy_snapshot.duplicate()
		if GameState.stage == "placement":
			_blind_submitted = false
		board.set_pending_deployments(pending_deployments)
		_refresh_confirm_state()
		_update_instruction()
	hud.add_log("⚠ " + message)

# Un joueur a abandonné (Fallen Empire §8.20). L'état est déjà appliqué et le refresh déjà
# déclenché par network_manager (game_state_updated émis dans le même message) : ici on
# journalise, et si c'est NOUS on verrouille le bouton d'abandon (anti double-envoi).
func _on_player_abandoned(player_id: int) -> void:
	# Unification E1 : pseudo en couleur plateau (échappé), reste de la ligne en rouge charte.
	hud.add_log(tr("GAME_PLAYER_ABANDONED_FMT") % _bb_pseudo(player_id))
	if player_id == _my_id():
		hud.lock_abandon_button()

func _refresh():
	# Réarme le bouton « Fin de Phase » à chaque état reçu (le verrou _pass_in_flight a été levé par
	# _on_state_updated) : il se réactive donc exactement une fois par transition acceptée (§8.48).
	hud.set_pass_enabled(true)
	# Sortie de la Phase 0 (§8.31) : on lève le verrou local de soumission aveugle et on remet le
	# compteur d'attente à zéro (réutilisable si une nouvelle partie démarre). À faire AVANT les
	# tests _in_deploy_mode() ci-dessous, qui en dépendent.
	if GameState.stage != "placement":
		_blind_submitted = false
		_blind_ready = 0
		_blind_expected = 0
	# Tampon de déploiement (§8.26) : on le PURGE hors mode déploiement (changement de tour/phase),
	# sinon on ré-affiche les "+X" sur les badges. set_pending_deployments redessine le plateau.
	if not _in_deploy_mode() and not pending_deployments.is_empty():
		pending_deployments.clear()
	board.set_pending_deployments(pending_deployments if _in_deploy_mode() else {})
	# Carte réduite (G5 §8.71) : recadre la vue « plein plateau » sur les territoires ACTIFS
	# (rect vide sur la carte complète → cadrage historique conservé, non-régression classic).
	camera.set_board_rect(board.get_active_map_rect())
	# Bandeau haut MINIMAL (lot A) : identité du joueur DONT C'EST LE TOUR (pseudo + couleur
	# plateau) — plus d'identité locale redondante ni de barre d'infos.
	var cur_pid := int(GameState.current_player_id)
	hud.set_turn_identity(_display_name(cur_pid), board.get_player_color(cur_pid))
	# Noms de faction affichables (le HUD n'affiche jamais l'id snake_case brut).
	_push_faction_names()
	hud.update_display()
	# Zone JOUEUR de la barre basse (lot A) : moi — identité, pouvoir, PV/PA/PB/PP en barres.
	_push_player_panel()
	# Carte POUVOIR de l'onglet ACTIONS (lot E) : compteur de mouvements + fenêtres en attente
	# + capacités de héros (§8.119 : RATIONNER et pouvoir de faction, grisés avec raison).
	_push_power_card()
	# §8.119 — bandeau « PROCHAINE ATTAQUE : PORTÉE ILLIMITÉE » tant que la Frappe Fantôme est
	# armée. Piloté par l'ÉTAT SERVEUR (`airborne_attacks_left`) et non par une mémoire locale :
	# il disparaît tout seul dès que l'attaque a consommé le crédit ou que le tour se termine.
	hud.set_ability_banner(tr("ABILITY_AIRBORNE_ARMED") \
		if int(_my_state().get("airborne_attacks_left", 0)) > 0 else "")
	# Un ciblage de capacité ne doit JAMAIS survivre à un changement de tour/phase (le serveur
	# refuserait l'envoi, mais le plateau resterait surligné et le joueur bloqué en mode ciblage).
	if _ability_target_mode != "" and _ability_block_reason(ABILITY_FACTION_POWER) != "":
		_cancel_ability_targeting()
	# Fiche joueur (lot A) : ordre de navigation ◀ ▶ + rafraîchissement TEMPS RÉEL de la fiche
	# ouverte (la cible vient peut-être de subir un duel / de perdre un territoire).
	_push_sheet_players()
	_refresh_player_sheet()
	# PACTES (§8.123) : le toast d'offre est piloté par l'ÉTAT et non par le message qui l'a
	# annoncé — il survit donc à une reconnexion (l'offre vit dans l'état, pas dans un message
	# fugace) et s'efface dès que l'offre cesse d'exister côté serveur.
	_sync_pact_toast()
	# Télégraphe de zone (G1 §8.62) : chip discret sous le bandeau haut.
	_push_zone_forecast()
	# Rebours GLOBAL de partie + mini-classement de départage (chantier « Tension », LOT F).
	_push_match_countdown()
	# SUIVI DES PRIMES (2026-08-01) : kills cumulés de MON équipe + caisses déjà ouvertes.
	_push_bounty_progress()
	# INTENSITÉ DE GUERRE (§8.122, LOT A) : nouvelle CIBLE. Le lissage et la propagation (musique,
	# ambiance, shader) se font en `_process` — ici on ne fait que recalculer la destination.
	_update_war_intensity_target()
	# GEIGER (§8.122, LOT C) : proximité de la zone radioactive, en sauts d'adjacence. Recalculé
	# ICI (à l'état reçu) et JAMAIS en `_process` : la zone ne bouge qu'entre deux états.
	AudioManager.set_zone_proximity(_zone_distance_to_me())
	# Tracker d'objectif vivant (E6 §8.78) : jauge de progression sous l'objectif secret.
	_push_objective_tracker()
	# Destinataires du chat privé (§8.33) : autres joueurs résolus en pseudo.
	_push_chat_targets()
	_update_instruction()
	# Bandeaux de tour/phase (E3 §8.75) : stinger sur chaque changement détecté.
	_maybe_show_banner()
	# Bouton « CONFIRMER LE DÉPLOIEMENT » : visible/activé selon le mode déploiement et le quota.
	_refresh_confirm_state()
	# Commandement fluide (E7 §8.79) : légalité du ré-assaut re-testée + coup de pouce de phase.
	_refresh_reassault()
	hud.pulse_next_phase(_no_action_possible())
	# Snapshot des propriétaires ET garnisons tels qu'affichés à l'écran : lu par
	# _play_combat_resolution pour identifier le défenseur et les garnisons PRÉ-combat
	# (l'état réseau, lui, est déjà post-combat). Garnisons : E2 §8.74 (« avant ➜ après »).
	_displayed_owners.clear()
	_displayed_garrisons.clear()
	for tid in GameState.territories:
		_displayed_owners[tid] = _owner(tid)
		_displayed_garrisons[tid] = _garrison(tid)
	# Pop-ups des factions à états bloquants (§8.3) : affichées/masquées selon NOTRE état serveur
	# (pending_eclipse_choice / pending_spy_choice). Idempotent — sans effet pour les autres tours.
	_maybe_prompt_eclipse()
	_maybe_prompt_spy()
	# Mode OBSERVATEUR (G3 §8.70) : si NOUS venons d'être éliminés, bandeau K.I.A. + caméra libre.
	_maybe_show_spectator()
	# Paris d'observateur (LOT E/F) : cibles vivantes + ouverture du guichet re-testées à chaque état
	# (le PROTOCOLE FINAL ferme les paris, et une cible peut être tombée entre-temps).
	_refresh_bet_panel()
	if GameState.winner_id != null:
		_show_victory()

# =========================================================
# Journal de Guerre 2.0 (E4 §8.76) — contexte de parsing, zone dérivée, toast, caméra
# =========================================================

# Feedback sensoriel (E9 §8.81) : SFX aux moments clés + VFX ponctuels (flash de conquête, tics
# de zone, douleur du héros). Les VFX obéissent au réglage reduced_motion (E10) ; les SFX non
# (ils passent par le bus SFX, coupé via le volume). Appelé pour CHAQUE game_event.
func _vfx_enabled() -> bool:
	return not bool(SettingsManager.get_comfort("reduced_motion"))

func _play_event_feedback(event) -> void:
	if typeof(event) != TYPE_DICTIONARY:
		return
	match str(event.get("event_type", "")):
		"attack_result":
			var def_tid := str(event.get("defender_territory_id", ""))
			# Douleur du héros (VFX) : NOTRE héros défenseur encaisse des dégâts. Identités = champs
			# serveur en priorité (§8.85) — le snapshot est périmé sur une chaîne d'attaques de bot.
			var duel = event.get("hero_duel")
			if typeof(duel) == TYPE_DICTIONARY and int(duel.get("damage", 0)) > 0 \
					and _event_pid(event, "defender_player_id",
						int(_displayed_owners.get(def_tid, -9999))) == _my_id():
				if _vfx_enabled():
					hud.pulse_hero_pain()
			# NB (lot D) : la fanfare + le flash radial de CONQUÊTE ont migré dans
			# `_after_combat_animation` — joués APRÈS la narration du combat. Déclenchés ici (à la
			# réception de l'évènement), ils « spoilaient » l'issue avant même l'animation.
		"card_played", "card_kept":
			AudioManager.play_sfx("card_draw")
		"pact_active":
			# §8.123 — un pacte vient d'entrer en vigueur. Évènement PUBLIC, avec identités : c'est
			# TOUTE la raison d'être du dispositif (un engagement que la table entière voit).
			_on_pact_active(event)
	# Lot E : le Culte de l'Isotope protège ses territoires de la zone — l'évènement système
	# `zone_protected` produit désormais AUSSI un toast de pouvoir (en plus de sa ligne verte au
	# Journal, conservée). Le pouvoir devient perceptible sans lire le journal.
	var sys_events = event.get("system_events", [])
	if typeof(sys_events) == TYPE_ARRAY:
		var isotope_shown := false
		for sev in sys_events:
			if typeof(sev) != TYPE_DICTIONARY:
				continue
			var code := str(sev.get("code", ""))
			if code == "zone_protected" and not isotope_shown:
				hud.show_power_toast(tr("POWER_TOAST_ISOTOPE"), Color("7fff00"))
				isotope_shown = true
			elif code == "ability_used":
				# §8.119 — toast PUBLIC : TOUT LE MONDE voit qu'une capacité a été activée (sinon
				# un territoire devenu inattaquable ou une frappe venue de nulle part serait
				# incompréhensible pour les adversaires).
				_push_ability_toast(sev)
			elif code == "zone_grew":
				# ZONE CROISSANTE (chantier « Tension », LOT A/F) : le territoire vient de basculer
				# dans le rendu contaminé (`toxic_pulsation`, posé par board.gd au refresh d'état).
				# On y ajoute un FLASH court + une entrée ☢ au Journal — sans quoi l'extension
				# passerait inaperçue au milieu d'un tour chargé.
				_on_zone_grew(str(sev.get("territory_id", "")))
			elif code == "pact_broken":
				# §8.123 — LA TRAHISON. Portée par les `system_events` de l'`attack_result` qui l'a
				# provoquée : le bandeau part donc AVEC le combat, pas plusieurs actions plus tard.
				_on_pact_broken(int(sev.get("betrayer_id", -9999)),
					int(sev.get("victim_id", -9999)))
			elif code == "pact_expired":
				# §8.123 — fin de pacte, DISCRÈTE (journal seul, aucun bandeau ni son) : ce n'est
				# pas un drame, mais les signataires doivent cesser de se croire couverts.
				_on_pact_expired(int(sev.get("a_id", -9999)), int(sev.get("b_id", -9999)))
	# Tics de zone (VFX) : flotteur -1 vert sur CHAQUE territoire touché (mêmes ticks dérivés
	# que le journal E4). SFX zone_alarm distinct = télégraphe (voir _push_zone_forecast).
	if _vfx_enabled():
		for t in _derive_zone_ticks(event):
			if typeof(t) == TYPE_DICTIONARY:
				board.spawn_zone_tick(str(t.get("tid", "")))

# ZONE CROISSANTE (chantier « Tension & fin de partie », LOT F) : rendu de l'extension. Le passage
# au shader `toxic_pulsation` est déjà fait par board.gd (le territoire est entré dans
# `contamination_zone.territories`) — on ajoute ici ce que l'état seul ne dit pas : QUAND, et OÙ.
# Flash bref + entrée ☢ cliquable au Journal (le clic recentre la caméra, E4 §8.76).
func _on_zone_grew(tid: String) -> void:
	if tid == "":
		return
	if _vfx_enabled():
		board.flash_territory(tid)
	hud.add_feed_entries([{"category": "zone", "icon": "☢", "tid": tid, "major": false,
		"rich_text": tr("ZONE_GREW_LOG") % _territory_name(tid).to_upper()}])
	AudioManager.play_sfx("zone_alarm")


# Contexte de résolution injecté à war_feed.parse : pseudos BBCode (E1), noms de territoires,
# texte legacy en repli, et propriétaires PRÉ-combat pour attack_result (l'état reçu est déjà
# post-combat — même source que le VS, _displayed_owners).
func _feed_ctx(event) -> Dictionary:
	var ctx := {
		"bb": Callable(self, "_bb_pseudo"),
		"tname": Callable(self, "_territory_name"),
		# i18n (2026-07-18) : résolution id de faction → nom EN invariant (system_events).
		"fname": Callable(self, "_faction_display_name"),
		"fallback": _format_event(event),
	}
	if typeof(event) == TYPE_DICTIONARY and str(event.get("event_type", "")) == "attack_result":
		var atk_tid := str(event.get("attacker_territory_id", ""))
		var def_tid := str(event.get("defender_territory_id", ""))
		# Identités = champs serveur en priorité (§8.85), repli sur le snapshot pré-combat.
		var atk_pid := _event_pid(event, "attacker_player_id",
			int(_displayed_owners.get(atk_tid, _owner(atk_tid))))
		var def_pid := _event_pid(event, "defender_player_id",
			int(_displayed_owners.get(def_tid, _owner(def_tid))))
		ctx["atk_pid"] = atk_pid if GameState.players.has(str(atk_pid)) else -9999
		ctx["def_pid"] = def_pid if GameState.players.has(str(def_pid)) else -9999
	return ctx

# Dégâts de zone DÉRIVÉS (E4 §8.76) : le serveur n'itemise pas les « −1 » de contamination — on
# les déduit en comparant la garnison AFFICHÉE (snapshot pré-évènement, même mécanique que
# _displayed_owners) à l'état reçu, pour les seuls territoires de la zone COURANTE, sur les
# évènements de TOUR (les dégâts s'appliquent à l'entame du tour, engine._end_turn). Les combats
# passent par attack_result (exclu) → aucune confusion possible.
func _derive_zone_ticks(event) -> Array:
	if typeof(event) != TYPE_DICTIONARY:
		return []
	var etype := str(event.get("event_type", ""))
	if etype != "turn_passed" and etype != "turn_timeout" and etype != "blind_deploy_resolved":
		return []
	var zone: Dictionary = GameState.contamination_zone \
		if typeof(GameState.contamination_zone) == TYPE_DICTIONARY else {}
	var tids = zone.get("territories", [])
	if typeof(tids) != TYPE_ARRAY:
		return []
	var ticks: Array = []
	for tid in tids:
		var key := str(tid)
		if not _displayed_garrisons.has(key):
			continue
		var before := int(_displayed_garrisons.get(key, 0))
		if _garrison(key) < before:
			ticks.append({"tid": key, "name": _territory_name(key),
				"ravaged": _garrison(key) <= 0 and _terr(key).get("owner_id") == null})
	return ticks

# Toast défensif (E4 §8.76) : un attack_result frappe un territoire à NOUS pendant le tour d'un
# AUTRE → toast + SFX (les données sont déjà diffusées à tous — pure mise en scène locale).
func _maybe_defense_toast(event) -> void:
	if typeof(event) != TYPE_DICTIONARY or str(event.get("event_type", "")) != "attack_result":
		return
	if int(GameState.current_player_id) == _my_id():
		return
	var def_tid := str(event.get("defender_territory_id", ""))
	# Identités = champs serveur en priorité (§8.85), repli sur le snapshot pré-combat.
	if _event_pid(event, "defender_player_id",
			int(_displayed_owners.get(def_tid, -9999))) != _my_id():
		return
	var atk_tid := str(event.get("attacker_territory_id", ""))
	var atk_owner := _event_pid(event, "attacker_player_id",
		int(_displayed_owners.get(atk_tid, _owner(atk_tid))))
	var line: String
	if bool(event.get("conquered", false)):
		line = tr("TOAST_TERRITORY_LOST") % [_territory_name(def_tid).to_upper(), _bb_pseudo(atk_owner)]
	else:
		line = tr("TOAST_UNDER_ATTACK") % [_territory_name(def_tid).to_upper(), _bb_pseudo(atk_owner),
			int(event.get("defender_losses", 0))]
	hud.show_defense_toast(line)
	AudioManager.play_sfx("under_attack")

# Clic d'une entrée [url=<tid>] du journal (E4) : focus caméra + flash bref du territoire —
# le journal devient un outil de NAVIGATION.
func _on_log_territory_clicked(tid: String) -> void:
	var pos: Vector2 = board.get_territory_position(tid)
	if pos == Vector2.INF:
		return
	board.flash_territory(tid)
	camera.focus_on_combat(pos, pos)
	get_tree().create_timer(2.5).timeout.connect(camera.reset_view)

# =========================================================
# Chrono SERVEUR & bandeaux de tour/phase (E3 §8.75)
# =========================================================

# Message léger timer_update : pousse l'échéance serveur au HUD (le flotteur « +N s » du gain de
# Time Bank est géré par hud.apply_timer_update, qui connaît l'échéance précédente).
func _on_timer_update(deadline_epoch: float, _budget_seconds: int, reason: String,
		server_time: float) -> void:
	hud.apply_timer_update(deadline_epoch, reason, server_time)

# Stinger de tour/phase — détection de changement sur l'état reçu (appelé par _refresh, donc
# JAMAIS pendant une résolution de combat : le refresh y est différé, piège n° 4). Priorité :
# nouveau tour (« À VOUS DE JOUER » / « TOUR DE X ») > nouvelle phase (« PHASE : X »).
func _maybe_show_banner() -> void:
	if _phase_banner == null:
		return
	if GameState.stage != "playing" or GameState.winner_id != null:
		_banner_turn_key = ""
		_banner_phase = -1
		return
	var cur_pid := int(GameState.current_player_id)
	var turn_key := "%s|%s" % [str(GameState.current_turn), str(cur_pid)]
	var phase := int(GameState.current_phase)
	if turn_key != _banner_turn_key:
		_banner_turn_key = turn_key
		_banner_phase = phase
		# §8.125 — le COUP D'ÉTAT armé ne SURVIT PAS au changement de tour. Sans ce désarmement, un
		# joueur qui a armé puis laissé passer son tour retrouverait le bouton en position
		# « CONFIRMER » et déclencherait son coup d'un clic qu'il croyait anodin. Une confirmation
		# ne doit jamais survivre au contexte qui l'a demandée.
		_coup_armed = false
		if cur_pid == _my_id():
			_phase_banner.show_banner(tr("BANNER_YOUR_TURN"), Color("e0b249"))
			AudioManager.play_sfx("your_turn")
			# Fenêtre en arrière-plan → attire l'attention (barre des tâches) : on ne rate
			# plus jamais le début de son tour.
			if not get_window().has_focus():
				DisplayServer.window_request_attention()
		else:
			_phase_banner.show_banner(tr("BANNER_TURN_OF") % _display_name(cur_pid).to_upper(),
				board.get_player_color(cur_pid))
		return
	if phase != _banner_phase:
		_banner_phase = phase
		_phase_banner.show_banner(tr("BANNER_PHASE") % hud.phase_name(phase).to_upper(),
			Color("36c5d9"))

# =========================================================
# Mode OBSERVATEUR (G3 §8.70) — bandeau K.I.A. + caméra libre + re-queue
# =========================================================
const SpectatorOverlayScene := preload("res://scenes/ui/spectator_overlay.tscn")
var _spectator_shown := false
# Overlay vivant (chantier « Tension », LOT F) : conservé pour lui pousser les options de paris, la
# fermeture du guichet au PROTOCOLE FINAL et le verdict de fin. null tant qu'on n'est pas éliminé.
var _spectator_overlay: Node = null

func _maybe_show_spectator() -> void:
	if _spectator_shown or GameState.winner_id != null:
		return
	if not _is_eliminated():
		return
	_spectator_shown = true
	var overlay := SpectatorOverlayScene.instantiate()
	add_child(overlay)  # au-dessus du HUD (dernier enfant de Main), non bloquant (bandeau seul)
	overlay.requeue_pressed.connect(_on_spectator_requeue)
	overlay.quit_pressed.connect(_on_spectator_quit)
	# PARIS D'OBSERVATEUR (chantier « Tension », LOT E/F) : la vue émet, le contrôleur envoie.
	_spectator_overlay = overlay
	overlay.bet_placed.connect(_on_spectator_bet)
	# §8.129 — première élimination de la carrière : on explique que la partie n'est pas finie pour
	# autant (paris d'observateur). La bulle passe APRÈS le bandeau K.I.A., jamais à sa place.
	TutorialManager.hint_once("first_spectator")
	if not NetworkManager.observer_bet_accepted.is_connected(_on_observer_bet_accepted):
		NetworkManager.observer_bet_accepted.connect(_on_observer_bet_accepted)
	_refresh_bet_panel()
	# Caméra tactique LIBRE (pan drag droit/molette + zoom molette) : l'observateur explore.
	camera.set_free_navigation(true)
	# Échec de re-queue → retour au lobby (le socket est déjà fermé par requeue()).
	if not NetworkManager.requeue_failed.is_connected(_on_requeue_failed):
		NetworkManager.requeue_failed.connect(_on_requeue_failed)
	# Partie PRIVÉE (§8.116) : requeue() refuse la re-file (salons éphémères) → retour au QG.
	if not NetworkManager.requeue_unavailable.is_connected(_on_requeue_unavailable):
		NetworkManager.requeue_unavailable.connect(_on_requeue_unavailable)
	hud.add_log(tr("GAME_KIA_SPECTATOR"))

# --- PARIS D'OBSERVATEUR (chantier « Tension & fin de partie », LOT E/F) ------------------------

# Rafraîchit le panneau PARIS : options (joueurs encore EN LICE) + ouverture du guichet. Appelé à
# l'apparition de l'overlay et à chaque refresh d'état (les cibles vivantes changent, et le
# PROTOCOLE FINAL ferme les paris en cours de route).
func _refresh_bet_panel() -> void:
	if _spectator_overlay == null or not is_instance_valid(_spectator_overlay):
		return
	var options: Array = []
	for key in GameState.players.keys():
		var p: Dictionary = GameState.players.get(str(key), {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		# On ne parie que sur des joueurs encore EN LICE : ni un éliminé (il ne gagnera pas, et son
		# héros est déjà tombé), ni nous-mêmes.
		if str(p.get("status", "alive")) == "eliminated" or int(key) == _my_id():
			continue
		options.append({"id": int(key), "name": _display_name(int(key)).to_upper()})
	_spectator_overlay.set_bet_options(options)
	# MÊME règle que le serveur (`observer_bets.open_for`) : fermé dès le PROTOCOLE FINAL.
	_spectator_overlay.set_bets_open(not bool(GameState.final_protocol_active)
		and GameState.winner_id == null)


# La vue a émis un choix → on l'envoie. Le serveur répond EN PRIVÉ : `observer_bet_ack` (accepté)
# ou `{"type":"error","reason":<code>}` — ce dernier est déjà routé vers le journal par
# _on_game_error, qui traduit le code (clés BET_ERR_*).
func _on_spectator_bet(bet_type: String, value) -> void:
	NetworkManager.send_observer_bet(bet_type, value)


# Pari ACCEPTÉ : on verrouille la ligne avec un libellé LISIBLE de la mise (pseudo pour un pari de
# joueur, libellé traduit pour un mode de fin) et la prime potentielle annoncée par le serveur.
func _on_observer_bet_accepted(bet_type: String, value, reward: Dictionary) -> void:
	if _spectator_overlay == null or not is_instance_valid(_spectator_overlay):
		return
	var label := ""
	if bet_type == "end_reason":
		label = tr("BET_END_" + str(value).to_upper())
	else:
		label = _display_name(int(value)).to_upper()
	_spectator_overlay.lock_bet(bet_type, label, reward)
	hud.add_log(tr("BET_ACCEPTED_LOG") % label)


func _on_spectator_requeue() -> void:
	# Le helper réseau ferme le WS, re-file la même modalité et rejoint l'écran de recherche (§8.116).
	# Après une partie PRIVÉE, il émet requeue_unavailable → retour au QG (cf. _on_requeue_unavailable).
	NetworkManager.requeue()

func _on_spectator_quit() -> void:
	# Sortie propre du spectateur (le serveur nous sait déjà éliminé — aucune action à envoyer) :
	# leave_room() (revue §8.116) recrée le WebSocketPeer (fix STATE_CLOSING), puis retour menu.
	NetworkManager.leave_room()
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

func _on_requeue_failed(_message: String) -> void:
	# B.5 : si le rapport est ENCORE affiché, on RÉACTIVE son bouton REJOUER (stoppe la pulsation,
	# restaure le libellé + `disabled=false`) avant de basculer — défensif via has_method. Le bouton
	# n'est réactivé que si le rapport reste vivant (sinon reset_requeue_button est un no-op interne).
	if _report_node != null and is_instance_valid(_report_node) and _report_node.has_method("reset_requeue_button"):
		_report_node.reset_requeue_button()
	# Repli : retour au QG (le message est déjà explicite ; plus de lobby, §8.116).
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

# Partie PRIVÉE (§8.116) : la re-file est impossible (salons éphémères) → retour au QG. On réactive
# d'abord le bouton du rapport s'il est encore affiché (défensif via has_method).
func _on_requeue_unavailable() -> void:
	if _report_node != null and is_instance_valid(_report_node) and _report_node.has_method("reset_requeue_button"):
		_report_node.reset_requeue_button()
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

func _show_victory():
	if _victory_shown:
		return
	_victory_shown = true
	_show_operation_report()

# §4 Warzone Command — Rapport Post-Opération : débriefing after-action (flou de l'arène gelée +
# grand panneau central). Remplace l'ancien overlay « VICTOIRE/DÉFAITE » minimal.
func _show_operation_report() -> void:
	# Efface le HUD flottant (comme le combat) pour que le flou ne porte que sur le plateau gelé.
	hud.fade_ui_for_combat(true)
	# §8.129 — DÉBRIEF du briefing : la partie guidée est finie (victoire OU défaite, finir suffit).
	# Le coach solde le briefing et la prime au clic sur COMPRIS. No-op hors Première Opération.
	TutorialManager.notify_game_over()
	TutorialManager.bind_report(self)
	var win := int(GameState.winner_id)
	var title := ""
	var title_color := Color("e0b249")  # or (victoire)
	# MODE ÉQUIPES (§8.124) : la victoire est COMMUNE — le titre nomme l'ÉQUIPE, pas le
	# porte-drapeau. Sans ça, le coéquipier du `winner_id` lirait « DÉFAITE » alors qu'il vient de
	# gagner (le `winner_id` n'est qu'un membre désigné, cf. `engine._award_team_victory`), et
	# c'est exactement le genre de contresens qui tue la confiance dans un mode.
	var win_team := int(GameState.winning_team_id)
	if GameState.team_mode != "" and win_team > 0:
		title = tr("TEAM_VICTORY_BANNER") % win_team
		if GameState.team_of(_my_id()) != win_team:
			title_color = Color("d6453f")
	elif win == _my_id():
		title = tr("GAME_VICTORY_TITLE_FMT") % _display_name(win)
	else:
		title = tr("GAME_DEFEAT_TITLE_FMT") % _display_name(win)
		title_color = Color("d6453f")  # rouge danger (défaite)
	# VICTOIRE AU TEMPS (chantier « Tension », LOT B/F) : `victory_reason == "timeout"` est une
	# valeur ADDITIVE du champ PUBLIC de l'état. Le titre garde le VAINQUEUR (l'information la
	# plus attendue) et gagne un sur-titre explicite : sans lui, un joueur qui menait aux
	# territoires ne comprendrait pas pourquoi la partie s'est arrêtée.
	if str(GameState.victory_reason) == "timeout":
		title = "%s — %s" % [tr("VERDICT_TIMEOUT"), title]
	# Rapport d'Attrition depuis la Mémoire Tactique (§8.35) : pertes infligées par la zone, triées
	# décroissant ; on met en avant le « plus lourd tribut » (médaille dorée).
	var stats: Dictionary = GameState.statistics
	var stagnation := int(stats.get("zone_stagnation_turns", 0))
	var kills: Dictionary = stats.get("zone_kills_by_player", {})
	var attrition: Array = []
	var worst_pseudo := ""
	var worst_n := 0
	var keys: Array = kills.keys()
	keys.sort_custom(func(a, b): return int(kills[a]) > int(kills[b]))
	for k in keys:
		var n := int(kills[k])
		if n <= 0:
			continue
		var pid := int(k)
		var pseudo := _display_name(pid)
		attrition.append({"pseudo": pseudo, "color": board.get_player_color(pid), "losses": n})
		if n > worst_n:
			worst_n = n
			worst_pseudo = pseudo
	var report := OperationReportScene.instantiate()
	add_child(report)  # dernier enfant de Main -> dessiné au-dessus de tout
	_report_node = report
	report.back_to_lobby.connect(_on_back_to_lobby)
	# « ⟳ REJOUER » du débriefing (G3 §8.70) : re-queue en 1 clic pour TOUS les joueurs.
	report.requeue_requested.connect(_on_spectator_requeue)
	# Inspection du champ de bataille (E11 §8.83) : rapport/flou masqués → caméra LIBRE sur
	# l'état final (zéro réseau) ; retour → caméra pilotée à nouveau.
	report.battlefield_inspect.connect(func(on: bool) -> void: camera.set_free_navigation(on))
	# CARTE DE PARTAGE (§8.121, LOT D) : le rapport DEMANDE, le contrôleur RÉSOUT le payload (View
	# pure §6.1 — c'est ici que vivent GameState, le board et les .tres de faction).
	report.share_card_requested.connect(_on_share_card_requested)
	if not NetworkManager.requeue_failed.is_connected(_on_requeue_failed):
		NetworkManager.requeue_failed.connect(_on_requeue_failed)
	# Récompenses du joueur LOCAL (Économie §8.47) : déjà reçues via match_over → animées d'emblée ;
	# sinon vides ici, et poussées plus tard par _on_match_over (course réseau état/clôture).
	# E11 : + podium (si le classement est déjà connu), timeline de domination et stats perso.
	# §8.99 : + tableau BILAN (debrief), TOUJOURS résolu (cf. commentaire de _debrief_rows).
	# §8.100 — classement EFFECTIF résolu AVANT le bloc data : rankings serveur si reçus, sinon
	# repli LOCAL (même tri que rewards.rank_players). Sert au podium ET au tableau BILAN (rangs).
	var eff_rankings := _effective_rankings()
	var data := {
		"title": title,
		"title_color": title_color,
		"stagnation": stagnation,
		"attrition": attrition,
		"worst_pseudo": worst_pseudo,
		"rewards": _local_rewards(),
		"timeline": _timeline_series(),
		# §8.99 — tableau BILAN (onglet 4) : TOUJOURS résolu. §8.100 : ordonné par le classement
		# EFFECTIF (serveur, sinon repli local) — mêmes rangs que le podium, aucune divergence.
		"debrief": _debrief_rows(eff_rankings),
		"my_stats": _my_match_stats(),
		"xp_detail": _xp_detail(),
		# §8.88 — mode classé (bloc PUBLIC du game_over, relayé en propriété par NetworkManager) :
		# pilote l'affichage des points de match. Résolu ICI (main.gd) : le rapport reste une
		# Vue pure (§6.1) et ne lit aucun manager.
		"is_ranked": _match_is_ranked(),
		# §8.99 — n'affirme « le joueur a disputé la partie » (→ bloc récompenses à 0 + anomalie si
		# `rewards` est vide) QUE si le game_over est déjà CONFIRMÉ reçu (_match_over_received) :
		# sinon, quand l'état winner_id arrive avant le game_over (course réseau, cf. _match_rewards
		# plus haut), un simple retard réseau serait affiché comme une anomalie — et la garde
		# _rewards_built bloquerait ensuite silencieusement les VRAIES récompenses poussées par
		# _on_match_over l'instant d'après. Dans ce cas, `has_played` reste false ICI : le bloc
		# n'est pas construit maintenant, _on_match_over le fera dès son arrivée (avec le bon verdict).
		"has_played": _has_played() and _match_over_received,
		# §8.100 — identité du héros LOCAL (faction, portrait, niveau, état) : données 100 % locales
		# (GameState + .tres), donc TOUJOURS résolues — l'onglet XP HÉROS n'est plus jamais vide,
		# même si le game_over (porteur des récompenses) tarde ou se perd.
		"hero_panel": _hero_panel_data(),
	}
	# §8.100 — CLASSEMENT TOUJOURS AFFICHÉ : rankings serveur si reçus, sinon repli LOCAL (même tri
	# que rewards.rank_players : vainqueur, puis territoires > continents > kills). L'écran ne reste
	# plus jamais sur « en attente du classement » alors que la partie est terminée ; le repli est
	# marqué PROVISOIRE et remplacé dès l'arrivée du game_over (_on_match_over → populate_podium).
	if not eff_rankings.is_empty():
		data["podium"] = _podium_rows(eff_rankings)
		data["podium_provisional"] = _match_rankings.is_empty()
	report.populate(data)
	if not _match_rankings.is_empty():
		_fetch_missions_for_report()

# Fin de partie (Économie §8.47) : on mémorise les gains diffusés et, si le Rapport Post-Op est DÉJÀ
# affiché (game_over reçu après l'état winner_id), on lui pousse les récompenses du joueur local.
# E11 §8.83 : rankings ENFIN consommé (podium + objectifs révélés) + pont missions.
func _on_match_over(_winner_id: int, _match_type: String, rankings: Array, match_rewards: Dictionary) -> void:
	# §8.99 — le game_over EST la confirmation autoritaire (cf. commentaire de la variable) : à partir
	# d'ici, `_local_rewards()` vide pour un joueur ayant disputé la partie est une VRAIE anomalie,
	# plus un simple retard réseau.
	_match_over_received = true
	_match_rewards = match_rewards
	_match_rankings = rankings if typeof(rankings) == TYPE_ARRAY else []
	if _report_node != null and is_instance_valid(_report_node):
		# §8.100 — ORDRE DÉFENSIF : le classement (verdict serveur, ce que le joueur attend le plus)
		# est poussé AVANT le bloc récompenses. Si une erreur runtime imprévue interrompait la chaîne
		# des récompenses (animations, breakdown), le podium et le BILAN seraient déjà rendus — c'est
		# l'inverse qui laissait l'écran figé sur « en attente du classement » (bug constaté).
		if not _match_rankings.is_empty():
			_report_node.populate_podium(_podium_rows(_match_rankings), false)
			_fetch_missions_for_report()
		# §8.99 — BILAN rafraîchi INCONDITIONNELLEMENT avec les tout derniers rankings/statistics.
		_report_node.populate_debrief(_debrief_rows(_effective_rankings()))
		# §8.100 — le détail du barème est re-résolu AVEC le rang serveur définitif : l'ancien
		# _xp_detail (capturé à l'ouverture du rapport, rang deviné) sous-estimait/surestimait les
		# postes d'un non-vainqueur tant que rankings n'était pas connu.
		_report_node.set_xp_detail(_xp_detail())
		_report_node.populate_rewards(_local_rewards(), _match_is_ranked(), _has_played())
		# Chantier « Tension & fin de partie » : DÉPARTAGE public (LOT B) + résultats PRIVÉS des
		# paris (LOT E). Blocs ADDITIFS — vides sur un serveur antérieur, le rapport n'affiche alors
		# simplement pas ces sections.
		_report_node.populate_final_scores(NetworkManager.last_final_scores,
			_scoreboard_colors(), _my_id())
		_report_node.populate_bet_results(NetworkManager.last_bet_results)
		# §8.121 — RAPPORT DE TRAHISON (LOT B) : le journal d'attaques n'arrive QU'AVEC le game_over,
		# donc c'est ici (et nulle part ailleurs) que le 5ᵉ onglet est peuplé. Serveur non redéployé
		# → journal vide → l'onglet reste masqué (§9.2).
		_report_node.populate_betrayals(_betrayal_data())
	# L'overlay spectateur, s'il est encore vivant sous le rapport, affiche aussi le verdict de ses
	# paris : le parieur n'a pas à chercher où est passé son résultat.
	var bets: Dictionary = NetworkManager.last_bet_results
	if _spectator_overlay != null and is_instance_valid(_spectator_overlay) and not bets.is_empty():
		var results = bets.get("results", [])
		_spectator_overlay.show_bet_results(results if typeof(results) == TYPE_ARRAY else [])

# Couleurs de plateau par player_id (str) pour le tableau de DÉPARTAGE du Rapport Post-Op : le
# rapport est une View pure (§6.1), c'est le contrôleur qui résout la palette (source unique
# board.get_player_color, même que le HUD et les pastilles).
func _scoreboard_colors() -> Dictionary:
	var out := {}
	for key in GameState.players.keys():
		out[str(int(key))] = board.get_player_color(int(key))
	return out

# Partie CLASSÉE ? (§8.88) — bloc PUBLIC du game_over, relayé en propriété par le NetworkManager
# (même pattern que last_objectives_reveal). Défaut `true` côté manager = comportement legacy d'un
# serveur non redéployé, qui crédite encore le ladder sur TOUTES les parties.
func _match_is_ranked() -> bool:
	return bool(NetworkManager.last_match_is_ranked)

# =========================================================
# Débriefing 2.0 (E11 §8.83) — résolveurs du Rapport Post-Op (View pure §6.1)
# =========================================================

# §8.100 — classement EFFECTIF : rankings du game_over si reçus, sinon repli LOCAL calculé sur
# l'état final (le rapport ne doit JAMAIS rester « en attente » une partie terminée). Le repli
# reproduit le tri serveur de rewards.rank_players : vainqueur en tête, puis territoires >
# continents > kills (décroissants ; à égalité pid croissant — départage stable).
func _effective_rankings() -> Array:
	if not _match_rankings.is_empty():
		return _match_rankings
	return _local_rankings_fallback()

func _local_rankings_fallback() -> Array:
	if GameState.winner_id == null:
		return []
	var winner := int(GameState.winner_id)
	var others: Array = []
	for k in GameState.players:
		var pid := int(k)
		if pid != winner:
			others.append(pid)
	others.sort_custom(func(a, b) -> bool:
		var ta := WarRoom.territory_count(GameState.territories, int(a))
		var tb := WarRoom.territory_count(GameState.territories, int(b))
		if ta != tb:
			return ta > tb
		var ca := _continents_owned(int(a))
		var cb := _continents_owned(int(b))
		if ca != cb:
			return ca > cb
		var ka := WarRoom.stat_of(GameState.statistics, "combat_kills_by_player", int(a))
		var kb := WarRoom.stat_of(GameState.statistics, "combat_kills_by_player", int(b))
		if ka != kb:
			return ka > kb
		return int(a) < int(b))
	return [winner] + others

# Continents ENTIÈREMENT possédés par `pid` en fin de partie (même synthèse que le tracker E6).
# Factorisé §8.100 : servait déjà à _xp_detail, requis aussi par le repli local de classement.
func _continents_owned(pid: int) -> int:
	var cont_terrs: Dictionary = MapData.get_map(GameState.map_id).get("continent_territories", {})
	var owned := 0
	for cid in cont_terrs.keys():
		var tids: Array = cont_terrs[cid]
		if tids.is_empty():
			continue
		var all_mine := true
		for tid in tids:
			var t: Dictionary = GameState.territories.get(str(tid), {})
			var o = t.get("owner_id")
			if o == null or int(o) != pid:
				all_mine = false
				break
		if all_mine:
			owned += 1
	return owned

# Lignes du podium : classement (rankings EFFECTIFS passés par l'appelant §8.100), objectifs
# révélés (bloc PUBLIC objectives_reveal), titres honorifiques (formules statiques du rapport,
# départage pid croissant), stats publiques — et MES points de match seuls (redaction serveur).
func _podium_rows(rankings: Array) -> Array:
	var reveal_by_pid := {}
	for r in NetworkManager.last_objectives_reveal:
		if typeof(r) == TYPE_DICTIONARY:
			reveal_by_pid[int(r.get("player_id", -9999))] = r
	var pids: Array = []
	for p in rankings:
		pids.append(int(p))
	var titles: Dictionary = OperationReportScript.honor_titles(GameState.statistics, pids)
	var rows: Array = []
	for i in range(pids.size()):
		var pid := int(pids[i])
		var rev: Dictionary = reveal_by_pid.get(pid, {})
		# i18n (§8.104) : objectif révélé COMPOSÉ dans la langue courante depuis sa forme
		# structurée ; repli sur la description serveur (anglais invariant) si absente.
		var rev_obj = rev.get("objective", {})
		rows.append({
			"pid": pid,
			"medal": OperationReportScript.medal_for(i),
			"titles": titles.get(pid, []),
			"objective": _objective_text(
				rev_obj if typeof(rev_obj) == TYPE_DICTIONARY else {},
				str(rev.get("description", ""))),
			"completed": bool(rev.get("completed", false)),
			"has_reveal": not rev.is_empty(),
			"kills": WarRoom.stat_of(GameState.statistics, "combat_kills_by_player", pid),
			"conquests": WarRoom.stat_of(GameState.statistics, "conquests_by_player", pid),
			"eliminations": WarRoom.stat_of(GameState.statistics, "eliminations_by_player", pid),
		})
	return rows

# Lignes du tableau BILAN (§8.99, onglet 4) — calcul délégué au module PUR WarRoom (source unique
# des compteurs, partagée avec le HUD in-game et le podium : aucune divergence possible entre les
# écrans). GameState.winner_id est déjà un int SÛR ici : les 2 points d'appel de cette fonction
# (_show_operation_report, _on_match_over) sont tous deux postérieurs au garde-fou de _show_victory
# (`if GameState.winner_id != null: _show_victory()`, :1557) — cf. aussi le fallback défensif
# ci-dessous si jamais cette fonction était un jour appelée plus tôt.
# ⚠️ Pas de propriété `NetworkManager.last_winner_id` (vérifié) : GameState.winner_id est la SOURCE
# DÉJÀ UTILISÉE par le titre du rapport juste au-dessus (_show_operation_report) — la réutiliser ici
# évite d'introduire une 2ᵉ variable qui pourrait diverger (ex. mémoriser le _winner_id du signal
# match_over serait redondant avec un état déjà fiable et déjà consommé pour la même question).
func _debrief_rows(rankings: Array = []) -> Array:
	var winner := int(GameState.winner_id) if GameState.winner_id != null else -1
	var eff: Array = rankings if not rankings.is_empty() else _match_rankings
	var rows: Array = WarRoom.debrief_rows(GameState.players, GameState.territories,
		GameState.statistics, eff, _my_id(), winner)
	# §8.100 — enrichissement VUE : couleur plateau de chaque belligérant (pastille de la ligne
	# BILAN, cf. maquette). Résolu ICI (le module WarRoom reste PUR, sans dépendance au board).
	for r in rows:
		r["color"] = board.get_player_color(int(r.get("pid", -9999)))
	return rows

# Séries de la timeline de domination (statistics.territory_history, diffusé AVANT le game_over).
# Historique absent/trop court (serveur antérieur, partie éclair) → [] (section masquée §9.2).
func _timeline_series() -> Array:
	var history = GameState.statistics.get("territory_history", [])
	if typeof(history) != TYPE_ARRAY or history.size() < 2:
		return []
	var series: Array = []
	for k in GameState.players:
		var pid := int(k)
		var pts: Array = []
		for snap in history:
			if typeof(snap) == TYPE_DICTIONARY:
				pts.append(int(snap.get(str(pid), 0)))
		series.append({"color": board.get_player_color(pid), "points": pts})
	return series

# =========================================================
# STREAMABILITÉ & PARTAGE (§8.121) — résolveurs du Rapport de Trahison et de la carte
# =========================================================

# RAPPORT DE TRAHISON (LOT B) — tout est calculé par le module PUR `BetrayalReport` ; ce résolveur
# ne fait que lui fournir ses entrées (journal du game_over + timeline + statistics) et habiller le
# résultat de ce qui appartient à la VUE : les pseudos affichables (préfixe [IA] compris) et les
# couleurs PLATEAU (source unique `board.get_player_color`, partagée avec le podium et le BILAN).
# {} si le serveur n'a pas envoyé de journal (non redéployé) → l'onglet reste masqué (§9.2).
func _betrayal_data() -> Dictionary:
	var log_ = NetworkManager.last_attack_log
	if typeof(log_) != TYPE_ARRAY:
		log_ = []
	# §8.123 : l'historique COMPLET des pactes (redaction levée au game_over). L'onglet a désormais
	# DEUX sources possibles — une partie sans le moindre combat mais avec des pactes proposés a
	# tout de même une histoire à raconter.
	var pact_log = NetworkManager.last_match_pacts
	if typeof(pact_log) != TYPE_ARRAY:
		pact_log = []
	if (log_ as Array).is_empty() and (pact_log as Array).is_empty():
		return {}
	# Ordre des lignes/colonnes de la matrice = le CLASSEMENT (le vainqueur en haut à gauche) ;
	# on complète avec les belligérants absents du classement (défensif — un joueur déconnecté
	# avant le game_over garderait sa ligne dans le récit).
	var pids: Array = []
	for p in _effective_rankings():
		if not pids.has(int(p)):
			pids.append(int(p))
	for k in GameState.players:
		if not pids.has(int(k)):
			pids.append(int(k))
	var history = GameState.statistics.get("territory_history", [])
	var tp: Dictionary = BetrayalReport.find_turning_point(
		history if typeof(history) == TYPE_ARRAY else [])
	var names := {}
	var colors := {}
	for pid in pids:
		names[str(int(pid))] = _display_name(int(pid))
		colors[str(int(pid))] = board.get_player_color(int(pid))
	var window: Array = []
	if not tp.is_empty():
		# La mini-vue est une TRANCHE de la courbe déjà affichée dans l'onglet BILAN : deux séries
		# construites séparément auraient pu raconter deux histoires différentes.
		window = BetrayalReport.timeline_window(_timeline_series(),
			int(tp.get("from_index", 0)), int(tp.get("to_index", 0)))
	return {
		"backstab": BetrayalReport.find_backstab(log_),
		"turning_point": tp,
		"turning_series": window,
		"matrix": BetrayalReport.aggression_matrix(log_, pids),
		"chain": BetrayalReport.elimination_chain(GameState.statistics, log_),
		# §8.123 — chronologie des pactes (tenus, rompus, expirés, refusés).
		"pacts": BetrayalReport.pact_timeline(pact_log),
		"names": names,
		"colors": colors,
	}

# CARTE DE PARTAGE (LOT D) — le rapport a demandé la carte : on résout le payload puis on lui rend
# la main (c'est LUI qui héberge le SubViewport et affiche le résultat de l'export).
func _on_share_card_requested() -> void:
	if _report_node == null or not is_instance_valid(_report_node):
		return
	_report_node.run_share_export(_share_card_payload())

# Payload de la carte : verdict, podium des 3 premiers, MON héros, palmarès, courbe de domination,
# ligne de trahison, chiffres clés. 100 % de données DÉJÀ résolues ailleurs dans ce fichier (aucun
# nouveau calcul) — la carte n'est qu'une seconde mise en page du même débriefing.
func _share_card_payload() -> Dictionary:
	var me := _my_id()
	var win := int(GameState.winner_id) if GameState.winner_id != null else -1
	var is_victory := win == me
	var rankings := _effective_rankings()
	var podium: Array = []
	for i in range(mini(3, rankings.size())):
		var pid := int(rankings[i])
		podium.append({
			"name": _display_name(pid),
			"color": board.get_player_color(pid),
			"medal": OperationReportScript.medal_for(i),
		})
	# Titres honorifiques que J'AI gagnés (mêmes formules que le podium — source unique).
	var pids: Array = []
	for p in rankings:
		pids.append(int(p))
	var titles: Array = []
	for key in OperationReportScript.honor_titles(GameState.statistics, pids).get(me, []):
		titles.append(tr(str(key)))

	var hero: Dictionary = GameState.hero_of(me)
	var fid := str(hero.get("faction", ""))
	var finfo := _faction_info(fid)
	var portrait: Texture2D = null
	var hp := str(finfo.get("hero_path", ""))
	if hp != "" and ResourceLoader.exists(hp):
		var res = load(hp)
		if res is Texture2D:
			portrait = res

	# Raison du verdict : la MÊME valeur PUBLIQUE que le sur-titre du rapport (§8.120), pour que la
	# carte et le rapport ne puissent pas annoncer deux fins différentes.
	var reason_key := ""
	match str(GameState.victory_reason):
		"timeout": reason_key = "VERDICT_TIMEOUT"
		"objective": reason_key = "SHARE_REASON_OBJECTIVE"
		"elimination": reason_key = "SHARE_REASON_ELIMINATION"
		"abandon": reason_key = "SHARE_REASON_ABANDON"

	var stab: Dictionary = _betrayal_data().get("backstab", {})
	var betrayal_line := ""
	if not stab.is_empty() and bool(stab.get("confirmed", false)):
		betrayal_line = tr("BETRAYAL_BACKSTAB") % [
			_display_name(int(stab.get("attacker", 0))),
			_display_name(int(stab.get("defender", 0))),
			int(stab.get("round", 0))]
		# §8.123 : si ce coup de poignard a rompu un PACTE, la carte le dit. C'est l'information qui
		# transforme une bonne attaque en histoire — et c'est précisément ce qu'on partage.
		if bool(stab.get("pact_broken", false)):
			betrayal_line += " · " + tr("SHARE_PACT_BROKEN")

	var kills := WarRoom.stat_of(GameState.statistics, "combat_kills_by_player", me)
	var conquests := WarRoom.stat_of(GameState.statistics, "conquests_by_player", me)
	var duration := _match_duration_text()
	return {
		"verdict": tr("SHARE_VERDICT_WIN") if is_victory else tr("SHARE_VERDICT_LOSS"),
		"verdict_reason": tr(reason_key) if reason_key != "" else "",
		"is_victory": is_victory,
		"podium": podium,
		"faction_name": str(finfo.get("name", "")),
		"leader": str(finfo.get("leader", "")),
		"portrait": portrait,
		"accent": board.get_player_color(me),
		"titles": titles,
		"timeline": _timeline_series(),
		"betrayal_line": betrayal_line,
		"stats": [
			[tr("SHARE_STAT_KILLS"), str(kills)],
			[tr("SHARE_STAT_CONQUESTS"), str(conquests)],
			[tr("SHARE_STAT_DURATION"), duration],
		],
		# Champs du résumé TEXTE copié dans le presse-papiers (share_card.clipboard_summary).
		"duration": duration,
		"kills": kills,
		"conquests": conquests,
		"betrayals": 1 if betrayal_line != "" else 0,
	}

# Durée « MM:SS » écoulée depuis l'entrée dans l'arène (cf. _arena_entered_at pour l'écart assumé
# avec la durée serveur). Horodatage non initialisé → « — » plutôt qu'un 00:00 trompeur.
func _match_duration_text() -> String:
	if _arena_entered_at <= 0.0:
		return "—"
	var secs := maxi(0, int(Time.get_unix_time_from_system() - _arena_entered_at))
	return "%d:%02d" % [secs / 60, secs % 60]

# Stats personnelles de la partie (colonne MA PERFORMANCE) + état final de MON héros.
func _my_match_stats() -> Dictionary:
	var pid := _my_id()
	var s: Dictionary = GameState.statistics
	var hero: Dictionary = GameState.hero_of(pid)
	var hero_line := ""
	if int(hero.get("pv_max", 0)) > 0:
		if bool(hero.get("is_dead", false)):
			hero_line = tr("REPORT_HERO_DOWN")
		else:
			hero_line = "PV %d/%d · PP %+d · NIV %d" % [
				int(hero.get("pv_current", 0)), int(hero.get("pv_max", 0)),
				int(hero.get("pp_current", 0)), int(hero.get("level", 1))]
	return {
		"kills": WarRoom.stat_of(s, "combat_kills_by_player", pid),
		"losses": WarRoom.stat_of(s, "losses_by_player", pid),
		"conquests": WarRoom.stat_of(s, "conquests_by_player", pid),
		"eliminations": WarRoom.stat_of(s, "eliminations_by_player", pid),
		"cards_played": WarRoom.stat_of(s, "cards_played_by_player", pid),
		"hero_damage": WarRoom.stat_of(s, "hero_damage_by_player", pid),
		"hero_kills": WarRoom.stat_of(s, "hero_kills_by_player", pid),
		"zone_deaths": WarRoom.stat_of(s, "zone_kills_by_player", pid),
		"hero_line": hero_line,
		# §8.100 — flag EXPLICITE pour la couleur danger de la ligne héros : l'ancien test client
		# `begins_with("💀")` (emoji retiré de la charte) était un couplage fragile au libellé i18n.
		"hero_dead": bool(hero.get("is_dead", false)) and int(hero.get("pv_max", 0)) > 0,
	}

# §8.100 — identité du héros LOCAL pour l'en-tête de l'onglet XP HÉROS du Rapport Post-Op.
# 100 % local (GameState.hero_of + .tres de faction) : résolu SANS attendre le game_over — c'est ce
# qui garantit un onglet jamais vide. {} si pré-RPG (pv_max 0 → pas de panneau, comportement §9.2).
func _hero_panel_data() -> Dictionary:
	var pid := _my_id()
	var hero: Dictionary = GameState.hero_of(pid)
	if int(hero.get("pv_max", 0)) <= 0:
		return {}
	var fid := str(hero.get("faction", ""))
	var info := _faction_info(fid)
	var portrait: Texture2D = null
	var hp := str(info.get("hero_path", ""))
	if hp != "" and ResourceLoader.exists(hp):
		var res = load(hp)
		if res is Texture2D:
			portrait = res
	return {
		"faction_name": str(info.get("name", "")),
		# Identité du meneur (refonte 2026-07-18) : rang traduit + nom propre invariant.
		"leader": str(info.get("leader", "")),
		"portrait": portrait,
		"color": board.get_player_color(pid),
		"level": int(hero.get("level", 1)),
		"pv_current": int(hero.get("pv_current", 0)),
		"pv_max": int(hero.get("pv_max", 0)),
		"pa": int(hero.get("pa", 0)),
		"pp": int(hero.get("pp_current", 0)),
		"is_dead": bool(hero.get("is_dead", false)),
	}

# Entrées BRUTES du détail du barème (E-visuel) pour le Rapport Post-Op : tout est PUBLIC/local
# (statistiques, territoires, continents de la carte courante, objectif révélé). Le rapport
# reconstitue le barème (rewards.py répliqué) et RÉCONCILIE aux totaux serveur — AUCUNE requête.
func _xp_detail() -> Dictionary:
	var pid := _my_id()
	var s: Dictionary = GameState.statistics
	# Rang final (0 = 1er) : classement EFFECTIF (§8.100 — serveur si connu, sinon repli local, le
	# même que le podium) ; à défaut vainqueur → 0, sinon 2e (réconcilié ensuite au total serveur).
	var eff := _effective_rankings()
	var rank := -1
	for i in range(eff.size()):
		if int(eff[i]) == pid:
			rank = i
			break
	if rank < 0:
		rank = 0 if int(GameState.winner_id) == pid else 1
	# Continents ENTIÈREMENT possédés en fin de partie (helper partagé §8.100).
	var continents_final := _continents_owned(pid)
	# Objectif rempli (bloc PUBLIC objectives_reveal — même source que le podium).
	var objective_done := false
	for r in NetworkManager.last_objectives_reveal:
		if typeof(r) == TYPE_DICTIONARY and int(r.get("player_id", -9999)) == pid:
			objective_done = bool(r.get("completed", false))
			break
	return {
		"rank": rank,
		"territories_final": WarRoom.territory_count(GameState.territories, pid),
		"continents_final": continents_final,
		"conquests": WarRoom.stat_of(s, "conquests_by_player", pid),
		"kills": WarRoom.stat_of(s, "combat_kills_by_player", pid),
		"eliminations": WarRoom.stat_of(s, "eliminations_by_player", pid),
		"hero_kills": WarRoom.stat_of(s, "hero_kills_by_player", pid),
		"hero_damage": WarRoom.stat_of(s, "hero_damage_by_player", pid),
		"objective_done": objective_done,
	}

# Pont missions (M2 §8.65 — E11) : un fetch UNIQUE après le game_over, résumé poussé au rapport
# au moment exact où le joueur est réceptif (boucle de rétention).
func _fetch_missions_for_report() -> void:
	if _missions_fetched_for_report:
		return
	_missions_fetched_for_report = true
	if not NetworkManager.missions_loaded.is_connected(_on_report_missions):
		NetworkManager.missions_loaded.connect(_on_report_missions)
	NetworkManager.fetch_missions()

func _on_report_missions(data: Dictionary) -> void:
	if _report_node == null or not is_instance_valid(_report_node):
		return
	var all_missions: Array = []
	var daily = data.get("daily", [])
	var weekly = data.get("weekly", [])
	if typeof(daily) == TYPE_ARRAY:
		all_missions.append_array(daily)
	if typeof(weekly) == TYPE_ARRAY:
		all_missions.append_array(weekly)
	var progressed := 0
	for m in all_missions:
		if typeof(m) == TYPE_DICTIONARY and int(m.get("progress", 0)) > 0 \
				and not bool(m.get("claimed", false)):
			progressed += 1
	_report_node.set_missions_summary(progressed, int(data.get("claimable_count", 0)))

# Récompenses du joueur LOCAL depuis le cache (repli sur le dernier reçu par NetworkManager). {} si
# absentes (le rapport s'affiche alors sans bloc Récompenses, sans bloquer le débriefing).
func _local_rewards() -> Dictionary:
	var src: Dictionary = _match_rewards if not _match_rewards.is_empty() else NetworkManager.last_match_rewards
	return src.get(str(_my_id()), {})

# §8.99 — ai-je DISPUTÉ cette partie ? Discriminant joueur / spectateur pour le bloc récompenses :
# présence dans `rankings` (source d'autorité du game_over), repli sur l'état public `players`
# (rankings absent = serveur antérieur / game_over pas encore arrivé). Clés de players en STRING
# après JSON (piège §5). Répond uniquement « ai-je joué », PAS « peut-on déjà se fier à une
# récompense vide » — voir `_match_over_received` pour cette 2ᵉ question (évite de crier à
# l'anomalie pendant que le game_over est simplement en vol).
func _has_played() -> bool:
	for p in _match_rankings:
		if int(p) == _my_id():
			return true
	return GameState.players.has(str(_my_id()))

# CTA de fin de partie : fermeture PROPRE du WS (leave_room recrée le socket — fix STATE_CLOSING)
# puis retour au QG (§8.116 : plus de lobby ; le JWT reste valide pour l'écran de recherche).
func _on_back_to_lobby():
	NetworkManager.leave_room()
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

func _update_instruction():
	if GameState.winner_id != null:
		hud.set_instruction(tr("GAME_INSTR_VICTORY_FMT") % _display_name(int(GameState.winner_id)))
		return

	# Conquête en attente de répartition : la fenêtre fait foi (jeu figé, §8.23).
	if _awaiting_conquer_move:
		hud.set_instruction(tr("GAME_INSTR_CONQUER"))
		return

	# Choix de carte Événement / espionnage en attente (factions à états bloquants, §8.3).
	if _awaiting_eclipse:
		hud.set_instruction(tr("GAME_INSTR_ECLIPSE"))
		return
	if _awaiting_spy:
		hud.set_instruction(tr("GAME_INSTR_SPY"))
		return

	# Empire déchu local : plus rien à jouer (le serveur saute nos tours), on observe.
	if _am_abandoned():
		hud.set_instruction(tr("GAME_INSTR_ABANDONED"))
		return

	match GameState.stage:
		"placement":
			# Phase 0 AVEUGLE & SIMULTANÉE (§8.31) : plus d'ordre de tour. Soit on dépose, soit on a
			# validé et on ATTEND la résolution simultanée (message persistant « en attente »).
			if _blind_submitted:
				var suffix := ""
				if _blind_expected > 0:
					suffix = " (%d/%d)" % [_blind_ready, _blind_expected]
				hud.set_instruction(tr("GAME_INSTR_BLIND_WAIT") % suffix)
			else:
				hud.set_instruction(tr("GAME_INSTR_BLIND_DEPLOY") % _deploy_quota())
		"playing":
			if not _is_playing_my_turn():
				# Lot A : pendant le tour d'un adversaire, l'onglet ACTIONS affiche un état
				# SPECTATEUR explicite (« TOUR DE X — observez le champ de bataille ») au lieu
				# d'une simple attente devant des contrôles grisés.
				hud.set_instruction(tr("HUD_SPECTATE_TURN_FMT")
					% _display_name(int(GameState.current_player_id)).to_upper())
			else:
				match GameState.current_phase:
					1: hud.set_instruction(tr("GAME_INSTR_REINFORCEMENTS"))
					2: hud.set_instruction(tr("GAME_INSTR_DEPLOY") % _deploy_quota())
					3: hud.set_instruction(tr("GAME_INSTR_ATTACK"))
					4: hud.set_instruction(tr("GAME_INSTR_MOVE"))
					_: hud.set_instruction(tr("GAME_INSTR_TRANSITION"))
		_:
			hud.set_instruction("")

# Coup de pouce de phase (E7 §8.79) : AUCUNE action possible dans la phase courante ? (Phase 3 :
# pas une seule attaque légale ; Phase 4 : pas un seul mouvement légal.) Calcul LOCAL, indicatif —
# le serveur reste seul juge (§8.48). Faux hors de notre tour / hors phases 3-4 (rien à signaler).
func _no_action_possible() -> bool:
	if not _is_playing_my_turn() or _input_blocked() or GameState.winner_id != null:
		return false
	var phase := int(GameState.current_phase)
	if phase != 3 and phase != 4:
		return false
	# Lot E — Ruche (`long_range_movement`) : le test de la phase 4 reste VALABLE tel quel. Une
	# chaîne alliée commence forcément par un VOISIN allié : « au moins un voisin à moi » est donc
	# exactement la condition d'existence d'un mouvement, chaîne comprise. Aucun cas où la Ruche
	# aurait un mouvement possible sans voisin allié → pas de faux « aucune action possible ».
	for tid in GameState.territories:
		if _owner(str(tid)) != _my_id() or _garrison(str(tid)) < 2:
			continue
		for n in MapData.neighbors_of(str(tid), GameState.map_id):
			var o = _terr(str(n)).get("owner_id")
			if phase == 3 and o != null and int(o) != _my_id():
				return false  # au moins une attaque possible
			if phase == 4 and o != null and int(o) == _my_id():
				return false  # au moins un mouvement allié possible
	return true

# Nombre de territoires ciblés par un évènement de déploiement en masse (§8.26).
func _deployments_count(e: Dictionary) -> int:
	var d = e.get("deployments", {})
	return d.size() if typeof(d) == TYPE_DICTIONARY else 0

func _format_event(e) -> String:
	if typeof(e) != TYPE_DICTIONARY:
		return str(e)
	match str(e.get("event_type", "")):
		"attack_result":
			var s = tr("EVT_ATTACK_FMT") % [
				e.get("attacker_territory_id"), e.get("defender_territory_id"),
				e.get("attacker_rolls"), e.get("defender_rolls"),
				e.get("attacker_losses"), e.get("defender_losses")]
			# Effets de faction déclenchés ce combat (§8.3) — noms EN invariants, pouvoirs traduits.
			if e.get("phalanges_reroll"):
				s += " " + tr("EVT_MARK_PHALANX")
			if e.get("aegis_kill"):
				s += " " + tr("EVT_MARK_AEGIS")
			if e.get("terror_kill"):
				s += " " + tr("EVT_MARK_TERROR")
			# Lot E : marqueurs manquants — Razzia (Pillards) et Embuscade (Chasseurs d'Ombres).
			if e.get("razzia_reroll"):
				s += " " + tr("EVT_MARK_RAZZIA")
			if e.get("first_strike"):
				s += " " + tr("EVT_MARK_AMBUSH")
			if e.get("conquered"):
				s += " " + tr("EVT_CONQUERED_SUFFIX")
			return s
		"blind_deploy_submitted":
			# Phase 0 (§8.31) : un joueur a validé son déploiement aveugle (compteur X/Y).
			var line := tr("EVT_BLIND_SUBMITTED_FMT") % [
				str(int(e.get("ready_count", 0))), str(int(e.get("expected_count", 0)))]
			if e.get("setup_complete"):
				line += tr("EVT_ALL_READY_SUFFIX")
			return line
		"blind_deploy_resolved":
			# Résolution simultanée de la Phase 0 (tous soumis OU délai de 90 s écoulé, §8.31).
			return tr("EVT_BLIND_RESOLVED_FMT") % (
				tr("EVT_TIMEOUT_SUFFIX") if e.get("forced") else "")
		"turn_timeout":
			# Minuterie de tour expirée (60 s) : le serveur a passé le tour d'office (§8.31).
			return tr("EVT_TURN_TIMEOUT_FMT") % _bb_pseudo(int(e.get("player_id", -1)))
		"initial_units_placed":
			# Déploiement en masse (§8.26) : `deployments` = dict {tid: nb} ; l'ancien format
			# unitaire (territory_id/amount) reste affichable proprement.
			var msg = ""
			if e.has("territory_id"):
				msg = tr("EVT_DEPLOY_ONE_FMT") % [e.get("amount"), e.get("territory_id")]
			else:
				msg = tr("EVT_PLACED_FMT") % [
					str(e.get("amount", 0)), _deployments_count(e)]
			if e.get("setup_complete"):
				msg += tr("EVT_PLACEMENT_DONE_SUFFIX")
			return msg
		"units_deployed":
			if e.has("territory_id"):
				return tr("EVT_DEPLOY_ONE_FMT") % [e.get("amount"), e.get("territory_id")]
			return tr("EVT_REINFORCED_FMT") % [
				str(e.get("amount", 0)), _deployments_count(e)]
		"units_moved":
			return tr("EVT_MOVED_FMT") % [e.get("amount"), e.get("source_territory_id"), e.get("target_territory_id")]
		"conquer_move_resolved":
			return tr("EVT_CONQUER_MOVE_FMT") % [
				str(e.get("troops")), e.get("from_tid"), e.get("to_tid")]
		"turn_passed":
			return tr("EVT_NEXT_PHASE")
		"card_played":
			return tr("EVT_CARD_PLAYED_FMT") % str(int(e.get("card_value", 0)))
		"card_kept":
			return tr("EVT_CARD_KEPT_FMT") % str(int(e.get("card_value", 0)))
		"spy_done":
			return tr("EVT_SPY_DONE")
		"game_initialized":
			return "❯ " + str(e.get("message", tr("EVT_GAME_INITIALIZED")))
		"game_over":
			return tr("EVT_GAME_OVER_FMT") % [
				_bb_pseudo(int(e.get("winner_id", -1))), str(e.get("match_type"))]
		_:
			return str(e.get("event_type", e))

# =========================================================
# COUPURE RÉSEAU VISIBLE EN PARTIE (§8.118)
# =========================================================
# Constat : une fermeture WS NON applicative (1006 crash serveur / coupure réseau / VPN, 1001…)
# ne produisait AUCUN signal — l'arène restait affichée, figée, et le joueur ne comprenait la
# panne qu'en cliquant (« NET_NOT_CONNECTED »). On rend donc la coupure VISIBLE, avec UNE
# tentative de reconnexion automatique, puis une sortie honnête si elle échoue.
#
# ⚠️ PÉRIMÈTRE : on ne change RIEN à la règle serveur. Une déconnexion en partie reste traitée
# côté backend comme un abandon (`_maybe_abandon_on_disconnect`) — chantier séparé du backlog
# (fenêtre de grâce / bot de remplacement). Le dialogue final le DIT au lieu de promettre une
# reprise qui n'existe pas.

# Délai avant la tentative UNIQUE de reconnexion (laisse passer un micro-hoquet réseau).
const NET_RETRY_DELAY := 2.0
# Filet de sécurité : si la tentative n'aboutit ni n'échoue franchement (connect_to_url en erreur,
# socket bloqué en CONNECTING → aucun STATE_CLOSED, donc aucun 2ᵉ server_connection_lost), on
# tranche au bout de ce délai plutôt que de laisser le bandeau rouge tourner indéfiniment.
const NET_GIVEUP_DELAY := 8.0
# Tenue du bandeau vert « CONNEXION RÉTABLIE » avant effacement.
const NET_RESTORED_HOLD := 2.0
# Ordonnée du bandeau — MÊME ligne d'ancrage que le stinger de tour (phase_banner.gd TOP_Y),
# documentée « sous la TopBar du HUD ». ⚠️ Défaut vu en CAPTURE seulement : collé à y = 0, le
# bandeau MASQUE la pastille tour/phase/chrono et le bouton ABANDONNER — précisément ce qu'on ne
# doit pas voler au joueur pendant une panne. La collision avec le stinger de tour est théorique :
# aucun changement de tour/phase ne peut arriver pendant que le socket est mort.
const NET_BANNER_TOP := 64.0

# Vert de SANTÉ déjà employé par le Roster de Guerre (war_roster.gd PV_GREEN) : la charte §2 n'a
# pas de « vert de succès », et son seul vert nommé (#7FFF00) veut dire CONTAMINATION — l'employer
# ici enverrait exactement le message inverse.
const NET_GREEN := Color("46b58a")

var _net_layer: CanvasLayer = null
var _net_banner: PanelContainer = null
var _net_banner_label: Label = null
var _net_modal: Control = null
# "" = lien sain · "lost" = coupé, reconnexion en cours · "final" = abandonné, dialogue affiché.
var _net_state: String = ""
# Jeton d'invalidation des minuteries en vol (pattern _requeue_cycle de network_manager) : chaque
# changement d'état l'incrémente, une minuterie périmée se sait périmée et ne fait rien.
var _net_cycle: int = 0

func _build_net_overlay() -> void:
	# Calque 3 : AU-DESSUS du HUD (calque 0) et du bandeau de tour (calque 2) — une panne de lien
	# prime sur tout le reste de l'affichage.
	_net_layer = CanvasLayer.new()
	_net_layer.layer = 3
	add_child(_net_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_layer.add_child(root)

	# --- Bandeau plein-largeur haut (non bloquant : le joueur peut continuer à regarder le plateau).
	_net_banner = PanelContainer.new()
	_net_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Hauteur laissée au minimum du contenu (offsets haut/bas égaux → croissance vers le bas).
	_net_banner.offset_top = NET_BANNER_TOP
	_net_banner.offset_bottom = NET_BANNER_TOP
	_net_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_banner.visible = false
	root.add_child(_net_banner)

	_net_banner_label = Label.new()
	_net_banner_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_net_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_banner_label.add_theme_font_override("font", _net_font())
	_net_banner_label.add_theme_font_size_override("font_size", 20)
	_net_banner_label.add_theme_constant_override("outline_size", 5)
	_net_banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_net_banner.add_child(_net_banner_label)

	# --- Dialogue final (modal, MOUSE_FILTER_STOP : plus rien à faire sur le plateau).
	_net_modal = Control.new()
	_net_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_net_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_net_modal.visible = false
	root.add_child(_net_modal)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_modal.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_modal.add_child(center)

	# Panneau angulaire charte §2 : gunmetal, coins droits, liseré rouge danger, encoches cyan.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.96)
	style.set_corner_radius_all(0)
	style.set_border_width_all(2)
	style.border_color = Color("d6453f")
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	panel.add_child(box)

	var msg := Label.new()
	msg.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	msg.text = tr("NET_CONNECTION_LOST_FINAL")
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_override("font", _net_font())
	msg.add_theme_font_size_override("font_size", 18)
	msg.add_theme_color_override("font_color", Color("eef3f7"))
	box.add_child(msg)

	# Clé i18n RÉUTILISÉE (MM_BACK_TO_HQ, §8.116) plutôt qu'une deuxième « RETOUR AU QG ».
	var quit_btn := Button.new()
	quit_btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	quit_btn.text = "❯ " + tr("MM_BACK_TO_HQ")
	quit_btn.custom_minimum_size = Vector2(0, 56)
	quit_btn.add_theme_font_override("font", _net_font())
	quit_btn.add_theme_font_size_override("font_size", 18)
	quit_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	WarzoneUI.apply_ghost_button(quit_btn)
	WarzoneUI.wire_button_sfx(quit_btn)
	quit_btn.pressed.connect(_on_net_back_to_hq)
	box.add_child(quit_btn)

# Police de la charte §2 (condensée, graisse 700) — l'arène n'en instancie aucune par ailleurs.
func _net_font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f

# Coupure annoncée par NetworkManager (codes 4000/4001/4003 EXCLUS en amont : ils ont déjà leur
# message via game_error). 1re émission = on prévient et on tente ; 2ᵉ = la tentative a échoué.
func _on_server_connection_lost(code: int) -> void:
	# Partie terminée : le Rapport Post-Op est à l'écran et le lien n'a plus d'objet (le serveur
	# ferme d'ailleurs souvent la salle). Un bandeau d'alarme par-dessus le débriefing serait du
	# bruit pur.
	if _victory_shown or _net_state == "final":
		return
	if _net_state == "lost":
		_net_connection_final()
		return
	print("MAIN: connexion perdue (code %d) — tentative de reconnexion unique." % code)
	_net_state = "lost"
	_net_cycle += 1
	var cycle := _net_cycle
	_show_net_banner(tr("NET_CONNECTION_LOST"), Color("d6453f"))
	get_tree().create_timer(NET_RETRY_DELAY).timeout.connect(_on_net_retry.bind(cycle))
	get_tree().create_timer(NET_GIVEUP_DELAY).timeout.connect(_on_net_giveup.bind(cycle))

# Tentative UNIQUE (aucune boucle) : NetworkManager rejoue le chemin de connexion existant avec les
# identifiants déjà en mémoire. Si elle réussit, le serveur nous renvoie un `game_started` PERSONNEL
# qui resynchronise GameState tout seul — RIEN à recharger ici.
func _on_net_retry(cycle: int) -> void:
	if cycle != _net_cycle or _net_state != "lost":
		return  # minuterie périmée (lien rétabli entre-temps, ou abandon déjà acté).
	NetworkManager.retry_connection()

func _on_net_giveup(cycle: int) -> void:
	if cycle != _net_cycle or _net_state != "lost":
		return
	_net_connection_final()

# `server_connected` est aussi émis à la connexion INITIALE : on n'agit que si l'on se savait coupé.
func _on_server_connection_restored() -> void:
	if _net_state != "lost":
		return
	_net_state = ""
	_net_cycle += 1  # invalide la tentative et l'abandon encore en vol.
	var cycle := _net_cycle
	_show_net_banner(tr("NET_CONNECTION_RESTORED"), NET_GREEN)
	get_tree().create_timer(NET_RESTORED_HOLD).timeout.connect(func() -> void:
		# Une NOUVELLE coupure pendant la tenue du bandeau vert a déjà repris la main : on ne lui
		# efface pas son bandeau rouge sous les pieds.
		if cycle == _net_cycle:
			_hide_net_banner())

func _net_connection_final() -> void:
	_net_state = "final"
	_net_cycle += 1
	_hide_net_banner()
	if _net_modal != null:
		_net_modal.visible = true

func _on_net_back_to_hq() -> void:
	# leave_room() recrée le WebSocketPeer (fix STATE_CLOSING, revue §8.116) : sans lui, la
	# recherche de partie suivante échouerait en silence.
	NetworkManager.leave_room()
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

func _show_net_banner(text: String, accent: Color) -> void:
	if _net_banner == null:
		return
	# Même grammaire que les bandeaux existants (hud.gd show_combat_banner / phase_banner.gd) :
	# gunmetal translucide, coins droits, filet d'accent en bord bas.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.92)
	style.set_corner_radius_all(0)
	style.set_border_width_all(0)
	style.border_width_bottom = 2
	style.border_color = accent
	style.set_content_margin_all(10)
	_net_banner.add_theme_stylebox_override("panel", style)
	_net_banner_label.text = text.to_upper()  # charte §2 : bandeaux en MAJUSCULES.
	_net_banner_label.add_theme_color_override("font_color", accent)
	_net_banner.visible = true

func _hide_net_banner() -> void:
	if _net_banner != null:
		_net_banner.visible = false


# =========================================================
# Mode debug solo (lancement direct de main.tscn)
# =========================================================

func _on_debug_init():
	button.disabled = true
	button.text = tr("GAME_DEBUG_CONNECTING")
	if not NetworkManager.connected:
		NetworkManager.connect_to_server(test_room_id)
		await NetworkManager.server_connected
	# §8.116 : l'init de partie en solo (backdoor WS init_game) est SUPPRIMÉE — une partie ne démarre
	# plus que via le matchmaker ou un salon privé (launch_room, sous verrou). Ce bouton de debug ne
	# peut donc plus initialiser une partie ; il se limite à la connexion WS ci-dessus.
	button.disabled = false
	button.hide()
