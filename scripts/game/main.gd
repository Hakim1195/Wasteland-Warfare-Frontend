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
# Vrai pendant l'animation Split-Screen VS : le rafraîchissement du plateau est alors différé
# (_refresh_pending) pour figer la mise à jour visuelle des troupes jusqu'à la fin du combat.
var _combat_animating: bool = false
var _refresh_pending: bool = false
# tid -> owner_id tel qu'AFFICHÉ sur le plateau (snapshot du dernier _refresh). Indispensable
# pour retrouver le propriétaire PRÉ-combat du territoire défenseur : l'état reçu avec
# attack_result est déjà post-combat (en cas de conquête, l'owner a déjà basculé).
var _displayed_owners: Dictionary = {}
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
# Héros adverse actuellement inspecté (clic territoire) ; -1 = aucun. Sert au rafraîchissement temps
# réel de l'inspecteur (les PV/PP de la cible changent après un combat). Voir _refresh_enemy_inspector.
var _inspected_enemy_id: int = -1

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
	# Inspecteur Tactique (§1) : un clic GAUCHE dans le vide referme le panneau (board_cleared).
	board.board_cleared.connect(hud.hide_territory_inspector)
	# Inspecteur Héros adverse (sprint RPG) : même geste de fermeture (clic dans le vide).
	board.board_cleared.connect(_on_board_cleared_inspector)
	hud.pass_pressed.connect(_on_pass_pressed)
	hud.card_played.connect(_on_card_played)
	hud.abandon_pressed.connect(_on_abandon_pressed)
	hud.deploy_confirmed.connect(_on_deploy_confirmed)

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
		button.text = "Initialiser une partie (debug)"

# =========================================================
# Accès / helpers d'état
# =========================================================

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

# Vrai si une fenêtre modale bloquante est ouverte (conquête / Éclipse / espionnage) : le jeu
# local est alors figé, comme l'exige %ConquerDialog (§8.23) et les pop-ups de faction (§8.3).
func _input_blocked() -> bool:
	return _awaiting_conquer_move or _awaiting_eclipse or _awaiting_spy

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
	if _in_deploy_mode():
		_buffer_add(tid, 1)
		return
	if GameState.stage == "placement":
		hud.add_log("⏳ Pas votre tour de placement.")
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
		hud.add_log("⏳ Ce n'est pas votre tour.")
		return
	match GameState.current_phase:
		3: _do_attack_click(tid)
		4: _do_move_click(tid)
		_:
			hud.add_log("Cliquez « Fin de Phase » pour avancer.")

func _do_attack_click(tid: String):
	if _source == "":
		# Choix de la source : à moi, avec au moins 2 unités.
		if _owner(tid) == _my_id() and _garrison(tid) >= 2:
			_select_source(tid)
			hud.set_instruction("ATTAQUE : cliquez un territoire ENNEMI adjacent (ou la source pour annuler).")
		else:
			hud.add_log("⛔ Source invalide (à vous, ≥ 2 unités).")
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
		if not MapData.are_adjacent(_source, tid):
			hud.add_log("⛔ Cible non adjacente à la source.")
			return
		# Combat VALIDÉ ici : source à moi (≥2 unités), cible ennemie adjacente (MapData).
		# La scène Split-Screen VS (affrontement des héros de factions) se joue à la
		# RÉCEPTION du résultat serveur (attack_result -> _play_combat_resolution), car
		# les jets de dés n'existent que dans la réponse du moteur.
		# Cible ennemie : on attaque avec le max de dés possibles (1-3).
		var dice = clampi(_garrison(_source) - 1, 1, 3)
		NetworkManager.send_action("attack_territory", {
			"attacker_territory_id": _source,
			"defender_territory_id": tid,
			"attacker_dice": dice,
		})
		_clear_source()

func _do_move_click(tid: String):
	if _source == "":
		if _owner(tid) == _my_id() and _garrison(tid) >= 2:
			_select_source(tid)
			hud.set_instruction("MOUVEMENT : cliquez un territoire ALLIÉ adjacent (ou la source pour annuler).")
		else:
			hud.add_log("⛔ Source invalide (à vous, ≥ 2 unités).")
	else:
		if tid == _source:
			_clear_source()
			_update_instruction()
			return
		if _owner(tid) != _my_id():
			hud.add_log("⛔ Destination invalide (territoire allié requis).")
			return
		# Adjacence (UX) : la destination doit être frontalière de la source. Le serveur re-valide.
		if not MapData.are_adjacent(_source, tid):
			hud.add_log("⛔ Destination non adjacente à la source.")
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

func _clear_source():
	_source = ""
	board.set_selected_source("")

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

# Ajoute (delta=+1) ou retire (delta=-1) une troupe en attente sur un territoire ALLIÉ, sans
# dépasser le quota. Met à jour le plateau (badge "+X") et l'état du bouton « Confirmer ».
func _buffer_add(tid: String, delta: int) -> void:
	if _owner(tid) != _my_id():
		if delta > 0:
			hud.add_log("⛔ Déployez sur VOS territoires.")
		return
	var cur := int(pending_deployments.get(tid, 0))
	if delta > 0:
		if _pending_total() >= _deploy_quota():
			hud.add_log("⛔ Quota atteint (%d troupe(s))." % _deploy_quota())
			return
		cur += 1
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
		hud.add_log("⛔ Placez EXACTEMENT %d troupe(s) avant de confirmer." % quota)
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
		hud.add_log("⏳ Action en cours…")
		return
	if _awaiting_conquer_move:
		hud.add_log("⏳ Répartissez d'abord vos troupes sur le territoire conquis.")
		return
	if _awaiting_eclipse:
		hud.add_log("⏳ Choisissez d'abord votre carte Événement (Ordre de l'Éclipse).")
		return
	if _awaiting_spy:
		hud.add_log("⏳ Choisissez d'abord une cible à espionner (Chasseurs d'Ombres).")
		return
	if GameState.stage != "playing":
		hud.add_log("La partie n'a pas encore commencé.")
		return
	if not _is_playing_my_turn():
		hud.add_log("⏳ Ce n'est pas votre tour.")
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
		hud.add_log("⏳ Vous ne pouvez jouer une carte que pendant votre tour.")
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
	hud.add_log(_format_event(event))
	# Messages système DIFFUSÉS attachés à l'évènement (ex. immunité du Culte de l'Isotope, §8.3) :
	# journalisés tels quels (BBCode autorisé, le journal est un RichTextLabel).
	if typeof(event) == TYPE_DICTIONARY:
		for m in event.get("system_messages", []):
			hud.add_log(str(m))
	# Phase 0 (§8.31) : suivi du compteur « X/Y joueurs ont validé » pour l'affichage d'attente
	# (le rafraîchissement d'état différé qui suit appellera _update_instruction avec ces valeurs).
	if typeof(event) == TYPE_DICTIONARY and str(event.get("event_type", "")) == "blind_deploy_submitted":
		_blind_ready = int(event.get("ready_count", _blind_ready))
		_blind_expected = int(event.get("expected_count", _blind_expected))
	if typeof(event) == TYPE_DICTIONARY and str(event.get("event_type", "")) == "attack_result":
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
	%ConquerInfo.text = "Vous avez conquis %s !\nCombien de troupes y déplacer depuis %s ?" % [
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
	%ConquerValue.text = "Déplacer %d troupe(s)  —  reste %d en défense sur la source" % [v, remaining]

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
		btn.text = "🎯 %s" % _display_name(pid)
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

# Réponse PRIVÉE du serveur à l'espionnage (reçue uniquement par l'espion, §8.3). On l'affiche
# en VIOLET dans le chat "Privé" (et dans le journal militaire) — le secret n'est pas diffusé.
func _on_spy_result(target_player_id: int, description: String) -> void:
	var line := "[color=purple]L'objectif de %s est : %s[/color]" % [
		_display_name(target_player_id), description]
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
		line = "🔒 [color=#%s]→ %s[/color] : %s" % [to_color.to_html(false), to_name, esc_text]
	else:
		var who: String = hud.color_pseudo(sender_name.replace("[", "[lb]"), board.get_player_color(sender_id))
		var prefix := "🔒 " if channel == "prive" else ""
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
	if MapData.TERRITORIES.has(tid):
		return str(MapData.TERRITORIES[tid].get("name", tid))
	return tid

# Nom à afficher pour un joueur : son VRAI pseudo, désormais diffusé par le serveur dans chaque
# PlayerState (§8.28). Replis successifs : notre pseudo local (AuthManager) si c'est nous, sinon
# "Joueur N" (numéro séquentiel 1..N) si l'identité n'a pas pu être résolue côté serveur.
func _display_name(pid: int) -> String:
	var p = GameState.players.get(str(pid), {})
	if typeof(p) == TYPE_DICTIONARY:
		var uname := str(p.get("username", ""))
		if uname != "":
			return uname
	if pid == _my_id() and AuthManager.username != "":
		return AuthManager.username
	return "Joueur %d" % GameState.player_number(pid)

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
							info = {
								"name": str(res.get("name")),
								"description": str(res.get("description")),
							}
							break
			file_name = dir.get_next()
		dir.list_dir_end()
	_faction_info_cache[fid] = info
	return info

# Infos de faction par id (nom + description + résumé du pouvoir passif), lues du .tres et mises en
# cache. Sert au tiroir « INTEL : FACTIONS » (§2). Scan robuste export-safe (.remap), duck-typing.
func _faction_info(fid: String) -> Dictionary:
	if fid == "":
		return {"name": "", "description": "", "power": ""}
	if _faction_full_cache.has(fid):
		return _faction_full_cache[fid]
	var info := {"name": "", "description": "", "power": ""}
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
							info = {"name": str(res.get("name")), "description": desc, "power": _extract_power(desc)}
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
	var owner_id := _owner(tid)
	var owner_name := "NEUTRE"
	var owner_color := Color("8a97a5")
	if owner_id >= 0:
		owner_name = _display_name(owner_id)
		owner_color = board.get_player_color(owner_id)
	hud.set_territory_inspector({
		"name": _territory_name(tid),
		"owner_name": owner_name,
		"owner_color": owner_color,
		"troops": _garrison(tid),
		"contaminated": board.is_contaminated(tid),
	})
	# Inspection adverse (sprint RPG, Objectif 5b) : si le territoire appartient à un AUTRE joueur
	# doté d'un héros, on pousse ses stats de héros (PUBLIQUES, aucune redaction). Sinon on masque
	# l'inspecteur adverse (territoire neutre, vide, ou à soi).
	if owner_id >= 0 and owner_id != _my_id() and GameState.has_hero(owner_id):
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
			fname = fid.capitalize() if fid != "" else "Faction inconnue"
		entries.append({
			"pseudo": _display_name(pid),
			"faction_name": fname,
			"color": board.get_player_color(pid),
			"power": str(finfo.get("power", "")),
		})
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

# =========================================================
# Résolution visuelle des combats (Split-Screen VS)
# =========================================================

# Superpose la scène d'affrontement des héros de factions (dés façon machine à sous) et
# FIGE la mise à jour visuelle du plateau jusqu'à la fin de l'animation. Le refresh mis en
# attente pendant l'animation (_refresh_pending) est rejoué à la sortie.
func _play_combat_resolution(event: Dictionary) -> void:
	if _combat_animating:
		return # garde anti-empilement (un seul duel à l'écran)
	_combat_animating = true
	# Le Split-Screen VS sacralise l'affrontement des héros : on efface le HUD flottant pendant
	# le duel (fondu 0,5 s, §8.29). La scène VS est enfant de Main (hors HUD) → elle reste visible.
	hud.fade_ui_for_combat(true)

	var atk_tid := str(event.get("attacker_territory_id", ""))
	var def_tid := str(event.get("defender_territory_id", ""))
	# Propriétaires tels qu'AFFICHÉS avant le combat (snapshot de _refresh) : l'état courant
	# est déjà post-combat (le territoire conquis appartient déjà à l'attaquant).
	var atk_owner = _displayed_owners.get(atk_tid, _owner(atk_tid))
	var def_owner = _displayed_owners.get(def_tid, _owner(def_tid))

	var vs_screen := SplitScreenVSScene.instantiate()
	add_child(vs_screen) # dernier enfant de Main -> dessiné au-dessus du HUD (surcouche)
	# §3 Warzone : on transmet les pertes + le Time Bank. local_is_attacker = c'est NOTRE tour
	# (l'attaquant est toujours le joueur courant) → seul l'attaquant local voit « TIME BANK +10s ».
	vs_screen.start_combat_resolution(
		_faction_of_player(atk_owner), _faction_of_player(def_owner),
		event.get("attacker_rolls", []), event.get("defender_rolls", []),
		{
			"attacker_losses": int(event.get("attacker_losses", 0)),
			"defender_losses": int(event.get("defender_losses", 0)),
			"time_bank_bonus": int(event.get("time_bank_bonus_seconds", 0)),
			"local_is_attacker": int(GameState.current_player_id) == _my_id(),
		})
	await vs_screen.animation_finished

	# Combat lu : on rétablit le HUD flottant (fondu inverse 0,5 s, §8.29).
	hud.fade_ui_for_combat(false)
	_combat_animating = false
	if _refresh_pending:
		_refresh_pending = false
		_refresh()

# Id de faction d'un joueur (clé "faction" du PlayerState diffusé par le serveur).
# Les clés de GameState.players sont des STRINGS (JSON) et pid peut être un float : on
# normalise via int() (piège Godot des ids JSON, cf. CONTEXTE.md §5).
func _faction_of_player(pid) -> String:
	var p = GameState.players.get(str(int(pid)), {})
	if typeof(p) == TYPE_DICTIONARY:
		return str(p.get("faction", ""))
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
	hud.add_log("🚫 " + message)

# Un joueur a abandonné (Fallen Empire §8.20). L'état est déjà appliqué et le refresh déjà
# déclenché par network_manager (game_state_updated émis dans le même message) : ici on
# journalise, et si c'est NOUS on verrouille le bouton d'abandon (anti double-envoi).
func _on_player_abandoned(player_id: int) -> void:
	hud.add_log("[color=red]%s a abandonné ! Défense automatique activée.[/color]" % _display_name(player_id))
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
	# Destinataires du chat privé (§8.33) : autres joueurs résolus en pseudo.
	_push_chat_targets()
	_update_instruction()
	# Bouton « CONFIRMER LE DÉPLOIEMENT » : visible/activé selon le mode déploiement et le quota.
	_refresh_confirm_state()
	# Snapshot des propriétaires tels qu'affichés à l'écran : lu par _play_combat_resolution
	# pour identifier le défenseur PRÉ-combat (l'état réseau, lui, est déjà post-combat).
	_displayed_owners.clear()
	for tid in GameState.territories:
		_displayed_owners[tid] = _owner(tid)
	# Pop-ups des factions à états bloquants (§8.3) : affichées/masquées selon NOTRE état serveur
	# (pending_eclipse_choice / pending_spy_choice). Idempotent — sans effet pour les autres tours.
	_maybe_prompt_eclipse()
	_maybe_prompt_spy()
	if GameState.winner_id != null:
		_show_victory()

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
		title = "VICTOIRE DE %s" % _display_name(win)
	else:
		title = "OPÉRATION TERMINÉE — %s L'EMPORTE" % _display_name(win)
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
	# Récompenses du joueur LOCAL (Économie §8.47) : déjà reçues via match_over → animées d'emblée ;
	# sinon vides ici, et poussées plus tard par _on_match_over (course réseau état/clôture).
	report.populate({
		"title": title,
		"title_color": title_color,
		"stagnation": stagnation,
		"attrition": attrition,
		"worst_pseudo": worst_pseudo,
		"rewards": _local_rewards(),
	})

# Fin de partie (Économie §8.47) : on mémorise les gains diffusés et, si le Rapport Post-Op est DÉJÀ
# affiché (game_over reçu après l'état winner_id), on lui pousse les récompenses du joueur local.
func _on_match_over(_winner_id: int, _match_type: String, _rankings: Array, match_rewards: Dictionary) -> void:
	_match_rewards = match_rewards
	if _report_node != null and is_instance_valid(_report_node):
		_report_node.populate_rewards(_local_rewards())

# Récompenses du joueur LOCAL depuis le cache (repli sur le dernier reçu par NetworkManager). {} si
# absentes (le rapport s'affiche alors sans bloc Récompenses, sans bloquer le débriefing).
func _local_rewards() -> Dictionary:
	var src: Dictionary = _match_rewards if not _match_rewards.is_empty() else NetworkManager.last_match_rewards
	return src.get(str(_my_id()), {})

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
		hud.set_instruction("🏆 VICTOIRE de %s !" % _display_name(int(GameState.winner_id)))
		return

	# Conquête en attente de répartition : la fenêtre fait foi (jeu figé, §8.23).
	if _awaiting_conquer_move:
		hud.set_instruction("🏴 Conquête ! Répartissez vos troupes dans la fenêtre.")
		return

	# Choix de carte Événement / espionnage en attente (factions à états bloquants, §8.3).
	if _awaiting_eclipse:
		hud.set_instruction("🌑 Ordre de l'Éclipse : choisissez la carte à conserver.")
		return
	if _awaiting_spy:
		hud.set_instruction("🕵 Chasseurs d'Ombres : choisissez une cible à espionner.")
		return

	# Empire déchu local : plus rien à jouer (le serveur saute nos tours), on observe.
	if _am_abandoned():
		hud.set_instruction("🏳️ Vous avez abandonné — vos territoires se défendent automatiquement.")
		return

	match GameState.stage:
		"placement":
			# Phase 0 AVEUGLE & SIMULTANÉE (§8.31) : plus d'ordre de tour. Soit on dépose, soit on a
			# validé et on ATTEND la résolution simultanée (message persistant « en attente »).
			if _blind_submitted:
				var suffix := ""
				if _blind_expected > 0:
					suffix = " (%d/%d)" % [_blind_ready, _blind_expected]
				hud.set_instruction("⏳ Déploiement validé — en attente des autres joueurs…%s" % suffix)
			else:
				hud.set_instruction("PLACEMENT AVEUGLE : clic GAUCHE +1 / clic DROIT -1 sur VOS territoires. Posez vos %d troupes, puis CONFIRMER." % _deploy_quota())
		"playing":
			if not _is_playing_my_turn():
				hud.set_instruction("Tour de %s — patientez." % _display_name(int(GameState.current_player_id)))
			else:
				match GameState.current_phase:
					1: hud.set_instruction("RENFORTS reçus. Déployez en cliquant « Fin de Phase ».")
					2: hud.set_instruction("DÉPLOIEMENT : clic GAUCHE +1 / clic DROIT -1 sur vos territoires, puis CONFIRMER (%d à placer)." % _deploy_quota())
					3: hud.set_instruction("ATTAQUE : cliquez votre territoire (≥2), puis un ennemi adjacent.")
					4: hud.set_instruction("MOUVEMENT : cliquez une source, puis un territoire allié adjacent.")
					_: hud.set_instruction("Transition… cliquez « Fin de Phase ».")
		_:
			hud.set_instruction("")

# Nombre de territoires ciblés par un évènement de déploiement en masse (§8.26).
func _deployments_count(e: Dictionary) -> int:
	var d = e.get("deployments", {})
	return d.size() if typeof(d) == TYPE_DICTIONARY else 0

func _format_event(e) -> String:
	if typeof(e) != TYPE_DICTIONARY:
		return str(e)
	match str(e.get("event_type", "")):
		"attack_result":
			var s = "⚔️ T%s→T%s | dés A:%s D:%s | pertes A:%s D:%s" % [
				e.get("attacker_territory_id"), e.get("defender_territory_id"),
				e.get("attacker_rolls"), e.get("defender_rolls"),
				e.get("attacker_losses"), e.get("defender_losses")]
			# Effets de faction déclenchés ce combat (§8.3).
			if e.get("phalanges_reroll"):
				s += " ⚙️ Phalanges (relance)"
			if e.get("aegis_kill"):
				s += " 🛡️ Aegis (double)"
			if e.get("terror_kill"):
				s += " 💀 Terreur (3e)"
			if e.get("conquered"):
				s += " 🏴 conquis !"
			return s
		"blind_deploy_submitted":
			# Phase 0 (§8.31) : un joueur a validé son déploiement aveugle (compteur X/Y).
			var line := "📦 Déploiement aveugle validé (%s/%s)." % [
				str(int(e.get("ready_count", 0))), str(int(e.get("expected_count", 0)))]
			if e.get("setup_complete"):
				line += " Tous prêts — la partie commence !"
			return line
		"blind_deploy_resolved":
			# Résolution simultanée de la Phase 0 (tous soumis OU délai de 90 s écoulé, §8.31).
			return "📦 Déploiements simultanés résolus%s — la partie commence !" % (
				" (délai écoulé)" if e.get("forced") else "")
		"turn_timeout":
			# Minuterie de tour expirée (60 s) : le serveur a passé le tour d'office (§8.31).
			return "⏰ Temps écoulé — tour de %s passé d'office." % _display_name(int(e.get("player_id", -1)))
		"initial_units_placed":
			# Déploiement en masse (§8.26) : `deployments` = dict {tid: nb} ; l'ancien format
			# unitaire (territory_id/amount) reste affichable proprement.
			var msg = ""
			if e.has("territory_id"):
				msg = "📍 +%s sur T%s" % [e.get("amount"), e.get("territory_id")]
			else:
				msg = "📍 %s troupe(s) placée(s) sur %d territoire(s)" % [
					str(e.get("amount", 0)), _deployments_count(e)]
			if e.get("setup_complete"):
				msg += " — placement terminé, la partie commence !"
			return msg
		"units_deployed":
			if e.has("territory_id"):
				return "🪖 +%s sur T%s" % [e.get("amount"), e.get("territory_id")]
			return "🪖 %s renfort(s) déployé(s) sur %d territoire(s)" % [
				str(e.get("amount", 0)), _deployments_count(e)]
		"units_moved":
			return "➡️ %s de T%s à T%s" % [e.get("amount"), e.get("source_territory_id"), e.get("target_territory_id")]
		"conquer_move_resolved":
			return "🚚 %s troupe(s) déplacée(s) de T%s vers T%s (conquête)." % [
				str(e.get("troops")), e.get("from_tid"), e.get("to_tid")]
		"turn_passed":
			return "⏭️ Phase suivante."
		"card_played":
			return "🃏 Carte +%s jouée — troupes à déployer." % str(int(e.get("card_value", 0)))
		"card_kept":
			return "🌑 Carte +%s conservée (Ordre de l'Éclipse)." % str(int(e.get("card_value", 0)))
		"spy_done":
			return "🕵 Un Chasseur d'Ombres a espionné un objectif secret."
		"game_initialized":
			return "🌍 " + str(e.get("message", "Partie initialisée."))
		"game_over":
			return "🏁 Partie terminée — vainqueur : %s (%s)" % [
				_display_name(int(e.get("winner_id", -1))), str(e.get("match_type"))]
		_:
			return str(e.get("event_type", e))

# =========================================================
# Mode debug solo (lancement direct de main.tscn)
# =========================================================

func _on_debug_init():
	button.disabled = true
	button.text = "Connexion..."
	if not NetworkManager.connected:
		NetworkManager.connect_to_server(test_room_id)
		await NetworkManager.server_connected
	button.text = "Initialisation..."
	NetworkManager.send_init_game()
	button.disabled = false
	button.hide()
