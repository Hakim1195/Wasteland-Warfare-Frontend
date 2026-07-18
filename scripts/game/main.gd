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

# Cache des infos de faction (id -> {name, description}) lues des resources/factions/*.tres, pour le
# tooltip « Pouvoir de Faction » du HUD (chargé une fois par faction — elle ne change pas en partie).
const FACTIONS_DIR := "res://resources/factions/"
var _faction_info_cache: Dictionary = {}
# Cache enrichi (nom + description + pouvoir passif) pour le tiroir « INTEL : FACTIONS » (§2).
var _faction_full_cache: Dictionary = {}
# Cache des MODIFICATEURS de faction (id -> Dictionary), miroir du registre backend §4.3 lu des
# .tres — consommé par la Prévision de combat (G4 §8.63 : flags de dés passés à CombatOdds).
var _faction_mods_cache: Dictionary = {}
# Héros adverse actuellement inspecté (clic territoire) ; -1 = aucun. Sert au rafraîchissement temps
# réel de l'inspecteur (les PV/PP de la cible changent après un combat). Voir _refresh_enemy_inspector.
var _inspected_enemy_id: int = -1

# Bandeaux de tour/phase (E3 §8.75) : instance + mémoire de détection des changements.
var _phase_banner = null
var _banner_turn_key := ""
var _banner_phase := -1

# Ré-assaut en un clic (E7 §8.79) : dernière attaque {source, target} pour rejouer le MÊME assaut
# tant qu'il reste légal (source ≥ 2, cible toujours ennemie, Phase 3, notre tour, non conclusif).
var _last_attack: Dictionary = {}

# Rythme des combats (E8 §8.80) : paire (source→cible) du DERNIER combat animé → à partir du 2ᵉ
# assaut consécutif sur la MÊME paire, le VS passe en version condensée (~1,2 s), même en cinématique.
var _last_combat_pair: String = ""

# SFX zone_alarm (E9 §8.81) : signature du dernier télégraphe joué (évite le rejeu à chaque refresh).
var _last_zone_alarm_sig: String = ""

func _ready():
	button.pressed.connect(_on_debug_init)

	# Audio §8.66 : on bascule de la musique de menu vers la MUSIQUE DE COMBAT tendue de l'arène
	# (lecteur unique → transition propre, plus de silence en jeu).
	AudioManager.start_battle_ambient()

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
	# Inspecteur Tactique (§1) : un clic GAUCHE dans le vide referme le panneau (board_cleared).
	board.board_cleared.connect(hud.hide_territory_inspector)
	# Inspecteur Héros adverse (sprint RPG) : même geste de fermeture (clic dans le vide).
	board.board_cleared.connect(_on_board_cleared_inspector)
	hud.pass_pressed.connect(_on_pass_pressed)
	hud.card_played.connect(_on_card_played)
	hud.abandon_pressed.connect(_on_abandon_pressed)
	hud.deploy_confirmed.connect(_on_deploy_confirmed)
	# Roster de Guerre (E1 §8.73) : clic d'une ligne → inspecteur héros + focus caméra.
	hud.roster_player_clicked.connect(_on_roster_player_clicked)
	# Chrono SERVEUR (E3 §8.75) : messages légers timer_update → HUD (échéance + Time Bank).
	NetworkManager.timer_updated.connect(_on_timer_update)
	# Journal de Guerre 2.0 (E4 §8.76) : clic d'une entrée [url=<tid>] → focus caméra + flash.
	hud.log_territory_clicked.connect(_on_log_territory_clicked)
	# Commandement fluide (E7 §8.79) : ré-assaut + raccourcis de quantité.
	hud.reassault_pressed.connect(_on_reassault_pressed)
	hud.amount_quick.connect(_on_amount_quick)
	# Bandeau de tour/phase (E3) : stinger haut-centre, déclenché par _maybe_show_banner().
	_phase_banner = PhaseBannerScene.instantiate()
	add_child(_phase_banner)

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
	if event.is_action_pressed("ui_cancel") and _source != "":
		_clear_source()
		_update_instruction()
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
	# Inspecteur Tactique (§1) : informatif — s'affiche au clic de TOUT territoire (la logique de
	# jeu suit en dessous, inchangée). Refermé par board_cleared (clic vide) ou le bouton ✕.
	_push_inspector(tid)
	if GameState.winner_id != null:
		return
	# Jeu figé tant qu'une fenêtre modale (conquête §8.23, Éclipse/espionnage §8.3) est ouverte.
	if _input_blocked():
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
		# Adjacence (UX) : la destination doit être frontalière de la source. Le serveur re-valide.
		if not MapData.are_adjacent(_source, tid, GameState.map_id):
			hud.add_log(tr("GAME_DEST_NOT_ADJACENT"))
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
	# (adjacentes ennemies) d'un liseré cramoisi + on désature le reste. Aucun effet hors Phase 3.
	if GameState.stage == "playing" and int(GameState.current_phase) == 3:
		board.set_attack_context(tid, _valid_attack_targets(tid))

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
	NetworkManager.connected = false
	NetworkManager.set_process(false)
	NetworkManager.socket.close()
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
func _on_spy_result(target_player_id: int, description: String) -> void:
	var line := tr("GAME_SPY_RESULT_FMT") % [
		_bb_pseudo(target_player_id), str(description).replace("[", "[lb]")]
	hud.add_chat_message("prive", line)
	hud.add_log(line)

# =========================================================
# Chat de salle (§8.33) — Général / Privé (l'onglet « Alliés » est abandonné, chacun-pour-soi)
# =========================================================
# Le HUD est une VIEW pure : il émet chat_send_requested avec son canal INTERNE ("general"/"prive").
# Le contrat réseau, lui, parle "general"/"private" → on traduit ici (dans les deux sens).

# Envoi : le joueur a validé un message dans le HUD. On traduit le canal puis on relaie au réseau.
func _on_chat_send(channel: String, text: String, target_id: int) -> void:
	var net_tab := "private" if channel == "prive" else "general"
	NetworkManager.send_chat_message(net_tab, text, target_id)

# Réception : message ESTAMPILLÉ par le serveur (sender_id/sender_name réels, §8.33). On colore le
# pseudo à la couleur de faction de l'expéditeur et on ÉCHAPPE le texte ET le pseudo (anti-injection
# BBCode — le message d'un autre joueur ne doit jamais interpréter de balises). En privé, l'écho de
# NOS propres messages revient avec sender_id == nous : on affiche alors le DESTINATAIRE.
func _on_chat_message(tab: String, sender_id: int, sender_name: String, text: String, target_id: int) -> void:
	var channel := "prive" if tab == "private" else "general"
	var esc_text := text.replace("[", "[lb]")
	var line := ""
	if channel == "prive" and sender_id == _my_id():
		var to_color: Color = board.get_player_color(target_id)
		var to_name := _display_name(target_id).replace("[", "[lb]")
		line = "❯ [color=#%s]→ %s[/color] : %s" % [to_color.to_html(false), to_name, esc_text]
	else:
		var who: String = hud.color_pseudo(sender_name.replace("[", "[lb]"), board.get_player_color(sender_id))
		var prefix := "❯ " if channel == "prive" else ""
		line = "%s%s : %s" % [prefix, who, esc_text]
	hud.add_chat_message(channel, line)

# Liste des destinataires du chat PRIVÉ (§8.33) : tous les AUTRES joueurs de la partie, résolus en
# pseudo (le HUD reste une View pure). Poussée à chaque refresh (la compo de salle est stable).
func _push_chat_targets() -> void:
	var entries := []
	for key in GameState.players:
		var pid := int(key)
		if pid == _my_id():
			continue
		entries.append({"id": pid, "name": _display_name(pid)})
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
func _display_name(pid: int) -> String:
	# Bot de remplissage (G2 §8.72) : id NÉGATIF → préfixe « [IA] » (l'état public porte is_bot ET
	# l'indicatif dans username ; le préfixe est posé ICI, côté client, comme prévu au contrat).
	var p = GameState.players.get(str(pid), {})
	var is_bot: bool = pid < 0 or (typeof(p) == TYPE_DICTIONARY and bool(p.get("is_bot", false)))
	if typeof(p) == TYPE_DICTIONARY:
		var uname := str(p.get("username", ""))
		if uname != "":
			return (tr("COMMON_AI_PREFIX") + uname) if is_bot else uname
	if pid == _my_id() and AuthManager.username != "":
		return AuthManager.username
	if is_bot:
		return tr("COMMON_AI_PREFIX") + tr("CHIP_BOT_FALLBACK") % absi(pid)
	return tr("WR_PLAYER_FALLBACK") % GameState.player_number(pid)

# Pseudo PRÊT pour le BBCode (journal militaire / chat) — unification E1 §8.73 : résolu
# (_display_name), échappé « [ » → « [lb] » (anti-injection §8.33 ; le préfixe [IA] des bots
# reste rendu tel quel) puis colorisé à la couleur PLATEAU du joueur (board.get_player_color,
# source unique). Généralisation du pattern historique de _on_chat_message : TOUT pseudo injecté
# dans un RichTextLabel passe par ici.
func _bb_pseudo(pid) -> String:
	var pseudo := _display_name(int(pid)).replace("[", "[lb]")
	return hud.color_pseudo(pseudo, board.get_player_color(int(pid)))

# Infos de faction du joueur LOCAL (nom + description du pouvoir) lues de son .tres, pour le tooltip
# du HUD. Scanne resources/factions/*.tres avec la même robustesse que board._load_faction_accents
# (gère le suffixe .remap des exports) et mémorise par id (la faction ne change pas en cours de
# partie). Renvoie {"name":"", "description":""} si la faction est inconnue / sans ressource.
func _local_faction_info() -> Dictionary:
	var fid := str(_my_state().get("faction", ""))
	if fid == "":
		return {"name": "", "description": ""}
	if _faction_info_cache.has(fid):
		return _faction_info_cache[fid]
	var info := {"name": "", "description": ""}
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
							# i18n (2026-07-18) : lore + pouvoir TRADUITS depuis les clés du .tres
							# (repli sur l'ancien champ description pour un .tres legacy).
							info = {
								"name": str(res.get("name")),
								"description": _faction_desc_text(res),
							}
							break
			file_name = dir.get_next()
		dir.list_dir_end()
	_faction_info_cache[fid] = info
	return info

# Texte lore + pouvoir d'une FactionData pour un affichage SANS BBCode (tooltip HUD) : lore
# traduit (desc_key) puis ligne « Pouvoir : … » traduite (power_key). Duck-typé, replis legacy.
func _faction_desc_text(res) -> String:
	var dk = res.get("desc_key")
	var pk = res.get("power_key")
	var lore := tr(str(dk)) if (dk != null and str(dk) != "") else str(res.get("description"))
	var power := tr(str(pk)) if (pk != null and str(pk) != "") else ""
	if power != "":
		return "%s\n\n%s %s" % [lore, tr("FACTION_POWER_LABEL"), power]
	return lore

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

# Inspecteur Tactique de Territoire (§1) : résout les données publiques du territoire cliqué et les
# pousse au HUD (View pure). Propriétaire neutre -> « NEUTRE » gris acier.
func _push_inspector(tid: String) -> void:
	# Propriétaire RÉEL du territoire : seul null = NEUTRE. owner_id peut être NÉGATIF (bot
	# G2 §8.72) — l'ancien test `>= 0` classait à tort les territoires de bots comme neutres.
	var raw_owner = _terr(tid).get("owner_id")
	var has_owner: bool = raw_owner != null
	var owner_id: int = int(raw_owner) if has_owner else -1
	var owner_name := tr("HUD_NEUTRAL")
	var owner_color := Color("8a97a5")
	if has_owner:
		owner_name = _display_name(owner_id)
		owner_color = board.get_player_color(owner_id)
	hud.set_territory_inspector({
		"name": _territory_name(tid),
		"owner_name": owner_name,
		"owner_color": owner_color,
		# E1 §8.73 : l'Inspecteur présente le propriétaire en player_chip (couleur plateau +
		# pseudo + faction) ; null = neutre → le HUD garde son label nu.
		"owner_id": owner_id if has_owner else null,
		"troops": _garrison(tid),
		"contaminated": board.is_contaminated(tid),
	})
	# Inspection adverse (sprint RPG, Objectif 5b) : si le territoire appartient à un AUTRE joueur
	# doté d'un héros, on pousse ses stats de héros (PUBLIQUES, aucune redaction). Sinon on masque
	# l'inspecteur adverse (territoire neutre, vide, ou à soi).
	if has_owner and owner_id != _my_id() and GameState.has_hero(owner_id):
		_inspected_enemy_id = owner_id  # mémorisé pour le rafraîchissement temps réel (_refresh)
		hud.set_player_inspector({
			"pseudo": owner_name,
			"color": owner_color,
			"hero": GameState.hero_of(owner_id),
		})
	else:
		_inspected_enemy_id = -1
		hud.hide_player_inspector()

# Fermeture de l'inspecteur héros adverse (clic dans le vide) : masque + oublie la cible suivie.
func _on_board_cleared_inspector() -> void:
	_inspected_enemy_id = -1
	hud.hide_player_inspector()

# Clic d'une ligne du Roster de Guerre (E1 §8.73) : ouvre l'inspecteur héros du joueur (existant,
# réutilisé tel quel — suivi temps réel via _inspected_enemy_id) et focalise la caméra tactique
# sur son territoire le plus garni (même cinétique + retour que le focus de combat).
func _on_roster_player_clicked(pid: int) -> void:
	if pid != _my_id() and GameState.has_hero(pid):
		_inspected_enemy_id = pid
		hud.set_player_inspector({
			"pseudo": _display_name(pid),
			"color": board.get_player_color(pid),
			"hero": GameState.hero_of(pid),
		})
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

# Rafraîchit en TEMPS RÉEL l'inspecteur héros adverse ouvert (PV/PP changent après un combat) : re-pousse
# les stats publiques de la cible suivie à chaque mise à jour d'état. Appelé depuis _refresh.
func _refresh_enemy_inspector() -> void:
	if _inspected_enemy_id < 0:
		return
	if not GameState.has_hero(_inspected_enemy_id):
		_inspected_enemy_id = -1
		hud.hide_player_inspector()
		return
	hud.set_player_inspector({
		"pseudo": _display_name(_inspected_enemy_id),
		"color": board.get_player_color(_inspected_enemy_id),
		"hero": GameState.hero_of(_inspected_enemy_id),
	})

# Tiroir « INTEL : FACTIONS » (§2) : liste les joueurs avec faction + pouvoir passif, résolus (pseudo,
# couleur de faction, pouvoir lu du .tres) et triés par id (View pure, Règle d'Or §6.1).
func _push_factions_intel() -> void:
	var entries: Array = []
	var ids: Array = []
	for k in GameState.players.keys():
		ids.append(int(k))
	ids.sort()
	for pid in ids:
		var p = GameState.players.get(str(pid), {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var fid := str(p.get("faction", ""))
		var finfo := _faction_info(fid)
		var fname := str(finfo.get("name", ""))
		if fname == "":
			fname = fid.capitalize() if fid != "" else tr("GAME_FACTION_UNKNOWN")
		entries.append({
			"pseudo": _display_name(pid),
			"faction_name": fname,
			"color": board.get_player_color(pid),
			"power": str(finfo.get("power", "")),
		})
		# Barre d'info du tour (i18n 2026-07-18) : le HUD affiche le nom EN invariant, plus l'id brut.
		hud.faction_name_by_pid[str(pid)] = fname
	hud.set_factions_intel(entries)

# « Mémoire Tactique » (§8.35/§8.36) : extrait les statistiques GLOBALES PUBLIQUES de l'état réseau
# (GameState.statistics) et pousse une liste prête à afficher au tiroir Intel du HUD. Suit le contrat
# serveur tel quel : statistics.zone_stagnation_turns (int) + statistics.zone_kills_by_player
# ({"<pid>": kills}). Pièges JSON (§5) : clés player_id en STR, valeurs en float -> int(). Résout
# pseudo (_display_name) + couleur de faction (board.get_player_color) AVANT de pousser, pour que le
# HUD reste une View pure (Règle d'Or §6.1).
func _push_intel() -> void:
	var stats: Dictionary = GameState.statistics
	var stagnation := int(stats.get("zone_stagnation_turns", 0))
	var kills_by_player: Dictionary = stats.get("zone_kills_by_player", {})
	var entries: Array = []
	# Tri par id croissant (ordre stable, cohérent avec player_number et la palette du plateau).
	var keys: Array = kills_by_player.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for k in keys:
		var kills := int(kills_by_player[k])
		if kills <= 0:
			continue
		var pid := int(k)
		entries.append({
			"pseudo": _display_name(pid),
			"color": board.get_player_color(pid),
			"kills": kills,
		})
	hud.set_intel(stagnation, entries)

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

# War Room (E5 §8.77) : agrège les 8 compteurs publics de GameState.statistics + territoires
# (module pur WarRoom) et la synthèse des continents DE LA CARTE COURANTE (G5 :
# MapData.get_map(map_id).continent_territories), puis pousse au HUD (View pure §6.1).
func _push_war_intel() -> void:
	var rows: Array = WarRoom.player_rows(
		GameState.players, GameState.territories, GameState.statistics)
	var cont_terrs: Dictionary = MapData.get_map(GameState.map_id).get("continent_territories", {})
	var continents: Dictionary = {}
	for cid in cont_terrs.keys():
		continents[cid] = {
			"name": MapData.c_name(cid),
			"tids": cont_terrs[cid],
		}
	hud.set_war_intel(rows, WarRoom.continent_rows(GameState.territories, continents))

# Tracker d'objectif vivant (E6 §8.78) : résout le CONTEXTE public (mes territoires, mes
# continents entièrement possédés, statut de la cible d'élimination) et pousse la progression
# au HUD (module pur ObjectiveTracker). Notre propre objectif porte type/params/description
# (§4.4) — aucune fuite : le nom de la cible est déjà dans notre description.
func _push_objective_tracker() -> void:
	var obj: Dictionary = GameState.objectives.get(str(_my_id()), {})
	if typeof(obj) != TYPE_DICTIONARY or obj.is_empty():
		hud.set_objective_progress({})
		return
	# Mes continents ENTIÈREMENT possédés (réutilise la synthèse E5, carte courante G5).
	var cont_terrs: Dictionary = MapData.get_map(GameState.map_id).get("continent_territories", {})
	var my_continents := 0
	for cid in cont_terrs.keys():
		var tids: Array = cont_terrs[cid]
		if tids.is_empty():
			continue
		var all_mine := true
		for tid in tids:
			var t: Dictionary = GameState.territories.get(str(tid), {})
			var o = t.get("owner_id")
			if o == null or int(o) != _my_id():
				all_mine = false
				break
		if all_mine:
			my_continents += 1
	# Cible d'élimination (volet kill de l'objectif double) : id au 1er niveau des params (§8.61).
	var target_id := int(obj.get("params", {}).get("target_id", -9999))
	var target_alive := true
	if GameState.players.has(str(target_id)):
		var tp: Dictionary = GameState.players.get(str(target_id), {})
		target_alive = str(tp.get("status", "alive")) != "eliminated" and not bool(tp.get("is_dead", false))
	var ctx := {
		"owned_count": WarRoom.territory_count(GameState.territories, _my_id()),
		"continents_owned": my_continents,
		"target_alive": target_alive,
		"target_name": _display_name(target_id) if target_id != -9999 else tr("GAME_TARGET_FALLBACK"),
	}
	var data := ObjectiveTracker.progress(obj, ctx)
	# i18n (2026-07-18) : description composée LOCALEMENT (type/params) en langue courante,
	# repli sur la description serveur (anglais invariant) pour un type inconnu.
	var obj_txt := ObjectiveTracker.describe(obj,
		_display_name(target_id) if target_id != -9999 else "")
	if obj_txt == "":
		obj_txt = str(obj.get("description", ""))
	var tooltip := obj_txt + "\n" + tr("OBJ_LAST_SURVIVOR_HINT")
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

	# Rythme des combats (E8 §8.80). Mode par implication (réglage combat_display) :
	#   cinematique = plein écran pour TOUS ; rapide = plein écran pré-accéléré ×2,5 ;
	#   bandeau = pour les combats où JE ne suis NI attaquant NI défenseur → bandeau compact
	#             (pas de plein écran) ; mes propres combats restent plein écran.
	var am_participant: bool = int(atk_owner) == _my_id() or int(def_owner) == _my_id()
	var mode := str(SettingsManager.get_comfort("combat_display"))
	# Chaîne de ré-assaut (E7) : 2ᵉ+ assaut consécutif sur la MÊME paire → version condensée.
	var pair := "%s>%s" % [atk_tid, def_tid]
	var condensed := pair == _last_combat_pair
	_last_combat_pair = pair

	if mode == "bandeau" and not am_participant:
		# Bandeau compact (E8) : passe dans la MÊME file _combat_animating (durée plus courte) —
		# AUCUN état ne se peint pendant une résolution (piège n° 4). HUD non masqué.
		await _play_combat_banner(event, atk_owner, def_owner)
		_combat_finished()
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
			# Rythme (E8 §8.80) : "rapide" démarre pré-accéléré ; chaîne de ré-assaut = condensé.
			"speed": 2.5 if mode == "rapide" else 1.0,
			"condensed": condensed,
		})
	await vs_screen.animation_finished

	# Combat lu : on rétablit le HUD flottant (fondu inverse 0,5 s, §8.29).
	hud.fade_ui_for_combat(false)
	_combat_finished()

# Fin d'UN combat : draine la FILE (chaque duel s'anime) AVANT tout rafraîchissement. _combat_animating
# reste vrai pendant tout le drainage → aucun état ne se peint, input figé, ordre des combats préservé.
func _combat_finished() -> void:
	if not _combat_queue.is_empty():
		var next_event: Dictionary = _combat_queue.pop_front()
		call_deferred("_do_play_combat", next_event)
		return
	_combat_animating = false
	if _refresh_pending:
		_refresh_pending = false
		_refresh()

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

# Caméra tactique : sur un résultat d'attaque, travelling vers les deux belligérants
# (zoom 1.5x), puis retour à la vue d'ensemble une fois le combat "lu".
func _maybe_focus_combat(event) -> void:
	if typeof(event) != TYPE_DICTIONARY or str(event.get("event_type", "")) != "attack_result":
		return
	var pos_a: Vector2 = board.get_territory_position(str(event.get("attacker_territory_id", "")))
	var pos_b: Vector2 = board.get_territory_position(str(event.get("defender_territory_id", "")))
	if pos_a == Vector2.INF or pos_b == Vector2.INF:
		return
	camera.focus_on_combat(pos_a, pos_b)
	get_tree().create_timer(2.5).timeout.connect(camera.reset_view)

func _on_game_error(message: String):
	# L'action a été refusée par le serveur → on déverrouille pour réessayer.
	_pass_in_flight = false
	_attack_in_flight = false  # attaque refusée (doublon, non adjacent…) : on lève le verrou (jamais de soft-lock)
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
	# Identité locale (pseudo + couleur de faction) poussée au HUD — couleur cohérente avec le
	# plateau (board.get_player_color), pour colorer le pseudo dans la TopBar (§8.23).
	hud.set_local_identity(_display_name(_my_id()), board.get_player_color(_my_id()))
	# Tooltip « Pouvoir de Faction » (§3) : nom + description lus du .tres de la faction locale.
	var finfo := _local_faction_info()
	hud.set_faction_info(str(finfo.get("name", "")), str(finfo.get("description", "")))
	hud.update_display()
	# Panneau Héros du joueur local (sprint RPG, Objectif 5a) : PV/PA/PB/PP/Niveau résolus depuis
	# l'état (GameState.hero_of). Le HUD se masque seul si le héros n'est pas initialisé (pré-RPG).
	hud.set_hero_panel(GameState.hero_of(_my_id()))
	# Inspecteur héros adverse (sprint RPG) : si un est ouvert, on rafraîchit ses PV/PP en temps réel
	# (la cible vient peut-être de subir un duel) au lieu de garder un instantané figé au clic.
	_refresh_enemy_inspector()
	# Tiroir « INTEL : ZONE » (§8.36) : pousse la Mémoire Tactique (stats globales §8.35) résolue en
	# pseudo + couleur de faction (le HUD reste une View pure, Règle d'Or §6.1).
	_push_intel()
	# Tiroir « INTEL : FACTIONS » (§2) : pouvoirs passifs des factions en jeu (résolus, View pure).
	_push_factions_intel()
	# Tiroir « INTEL : GUERRE » (E5 §8.77) : rapports de force complets (War Room).
	_push_war_intel()
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
			var atk_tid := str(event.get("attacker_territory_id", ""))
			var def_tid := str(event.get("defender_territory_id", ""))
			# Douleur du héros (VFX) : NOTRE héros défenseur encaisse des dégâts. Identités = champs
			# serveur en priorité (§8.85) — le snapshot est périmé sur une chaîne d'attaques de bot.
			var duel = event.get("hero_duel")
			if typeof(duel) == TYPE_DICTIONARY and int(duel.get("damage", 0)) > 0 \
					and _event_pid(event, "defender_player_id",
						int(_displayed_owners.get(def_tid, -9999))) == _my_id():
				if _vfx_enabled():
					hud.pulse_hero_pain()
			# Conquête : fanfare + flash radial à l'accent du conquérant.
			if bool(event.get("conquered", false)):
				AudioManager.play_sfx("conquest")
				if _vfx_enabled():
					var conqueror := _event_pid(event, "attacker_player_id",
						int(_displayed_owners.get(atk_tid, _owner(atk_tid))))
					board.conquest_flash(def_tid, board.get_player_color(conqueror))
		"card_played", "card_kept":
			AudioManager.play_sfx("card_draw")
	# Tics de zone (VFX) : flotteur -1 vert sur CHAQUE territoire touché (mêmes ticks dérivés
	# que le journal E4). SFX zone_alarm distinct = télégraphe (voir _push_intel).
	if _vfx_enabled():
		for t in _derive_zone_ticks(event):
			if typeof(t) == TYPE_DICTIONARY:
				board.spawn_zone_tick(str(t.get("tid", "")))

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
	# Caméra tactique LIBRE (pan drag droit/molette + zoom molette) : l'observateur explore.
	camera.set_free_navigation(true)
	# Échec de re-queue → retour au lobby (le socket est déjà fermé par requeue()).
	if not NetworkManager.requeue_failed.is_connected(_on_requeue_failed):
		NetworkManager.requeue_failed.connect(_on_requeue_failed)
	hud.add_log(tr("GAME_KIA_SPECTATOR"))

func _on_spectator_requeue() -> void:
	# Le helper réseau enchaîne quitter → radar → rejoindre/créer → waiting_room (G3 §8.70).
	NetworkManager.requeue()

func _on_spectator_quit() -> void:
	# Sortie propre du spectateur : même chemin que l'abandon (le serveur nous sait déjà éliminé —
	# aucune action à envoyer), socket coupé puis retour menu.
	NetworkManager.connected = false
	NetworkManager.set_process(false)
	NetworkManager.socket.close()
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

func _on_requeue_failed(_message: String) -> void:
	# Repli : retour au lobby (l'écran lobby réaffiche le radar ; le message est déjà explicite).
	TransitionManager.change_scene("res://scenes/ui/lobby_screen.tscn")

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
	var win := int(GameState.winner_id)
	var title := ""
	var title_color := Color("e0b249")  # or (victoire)
	if win == _my_id():
		title = tr("GAME_VICTORY_TITLE_FMT") % _display_name(win)
	else:
		title = tr("GAME_DEFEAT_TITLE_FMT") % _display_name(win)
		title_color = Color("d6453f")  # rouge danger (défaite)
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
	var my_rewards := _local_rewards()
	var rows: Array = []
	for i in range(pids.size()):
		var pid := int(pids[i])
		var rev: Dictionary = reveal_by_pid.get(pid, {})
		rows.append({
			"pid": pid,
			"medal": OperationReportScript.medal_for(i),
			"titles": titles.get(pid, []),
			"objective": str(rev.get("description", "")),
			"completed": bool(rev.get("completed", false)),
			"has_reveal": not rev.is_empty(),
			"kills": WarRoom.stat_of(GameState.statistics, "combat_kills_by_player", pid),
			"conquests": WarRoom.stat_of(GameState.statistics, "conquests_by_player", pid),
			"eliminations": WarRoom.stat_of(GameState.statistics, "eliminations_by_player", pid),
			# -1 = « aucun point à afficher » (convention du podium) : les points des AUTRES sont
			# inconnus (redaction serveur) et, en partie NON classée (§8.88), les miens non plus
			# n'ont pas à s'afficher — le serveur renvoie 0, aucun ladder n'est crédité.
			"points": int(my_rewards.get("match_points", -1)) \
				if (pid == _my_id() and _match_is_ranked()) else -1,
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

# CTA « RETOURNER AU LOBBY » : nettoyage de session puis retour au lobby (≠ ancien retour au
# main_menu). lobby_screen re-fetch les salles en REST (le JWT reste valide).
func _on_back_to_lobby():
	if NetworkManager.socket:
		NetworkManager.socket.close()
	NetworkManager.connected = false
	NetworkManager.set_process(false)
	NetworkManager.current_room_id = ""
	TransitionManager.change_scene("res://scenes/ui/lobby_screen.tscn")

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
				hud.set_instruction(tr("GAME_INSTR_WAIT_TURN") % _display_name(int(GameState.current_player_id)))
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
# Mode debug solo (lancement direct de main.tscn)
# =========================================================

func _on_debug_init():
	button.disabled = true
	button.text = tr("GAME_DEBUG_CONNECTING")
	if not NetworkManager.connected:
		NetworkManager.connect_to_server(test_room_id)
		await NetworkManager.server_connected
	button.text = tr("GAME_DEBUG_INITIALIZING")
	NetworkManager.send_init_game()
	button.disabled = false
	button.hide()
