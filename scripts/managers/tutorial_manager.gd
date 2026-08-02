extends CanvasLayer
##
## TUTORIAL MANAGER (autoload) — TUTORIEL & FTUE, §8.129.
##
## Trois étages DÉCOUPLÉS, chacun fonctionnel si les deux autres n'existaient pas :
##   1. **PREMIÈRE OPÉRATION** — une VRAIE partie (salon privé + bots) accompagnée par un coach
##      « COMMANDEMENT » de 13 étapes, jouée UNE fois par compte.
##   2. **AIDES CONTEXTUELLES** — une bulle à la PREMIÈRE rencontre de chaque système avancé,
##      jamais répétée (mémoire LOCALE `user://tutorial_hints.json`).
##   3. **MANUEL DE GUERRE** — la référence à froid (`scripts/ui/war_manual.gd`), ouverte depuis
##      les Paramètres, depuis « EN SAVOIR PLUS » d'une bulle, ou depuis le menu ÉCHAP de l'arène.
##
## ⛔ **AUCUNE MODIFICATION DU MOTEUR.** La Première Opération est une partie NORMALE : mêmes règles,
## mêmes bots, XP et missions crédités comme d'habitude. Ce manager **observe** (il écoute les mêmes
## signaux que le HUD) et **affiche** ; il ne truque rien, ne bloque rien, ne désactive rien. Les
## seuls verrous sont des SUGGESTIONS visuelles, et « PASSER LE BRIEFING » est accessible à CHAQUE
## étape (la partie, elle, continue normalement).
##
## Règle d'Or §6.1 : ce manager ne contient AUCUNE règle de jeu — il lit `GameState` et les
## évènements, il n'en dérive jamais une décision de partie. Le composant visuel (`coach_panel.gd`)
## est une **Vue PURE** hébergée ici, sur le modèle de `TransitionManager` (autoload CanvasLayer) :
## le coach doit SURVIVRE aux changements de scène (draft → arène → Rapport Post-Op), sans quoi
## chaque écran devrait le remonter et se rappeler où en était le briefing.
##
## Préférences produit (§8.125) : aucun emoji, un seul panneau à l'écran à la fois, et chaque
## interaction se vérifie par une contre-épreuve COMPORTEMENTALE (cf. §8.129 des docs).

# Prime de briefing effectivement créditée par le serveur (le Rapport Post-Op affiche « +N ¢ »).
# Émis UNIQUEMENT sur un crédit RÉEL : jamais sur un `already` (rien n'a bougé), jamais sur un
# serveur ancien (404) — un toast de récompense qui mentirait sur le solde serait pire que rien.
signal tutorial_reward_granted(coins_awarded: int, balance: int)

const CoachPanelScript := preload("res://scripts/ui/coach_panel.gd")

# Au-dessus du HUD et des écrans, SOUS le fondu de TransitionManager (128) : une bascule de scène
# doit couvrir le coach comme le reste, sinon il « flotterait » pendant le fondu.
const COACH_LAYER := 120

# --- PREMIÈRE OPÉRATION : le véhicule (§8.116, API inchangée) ---------------------------------
# `skirmish_atlantic` (≈ 20 territoires, 3 joueurs) : une première partie complète en moins de dix
# minutes. Sur `classic_42` le briefing aurait duré une demi-heure avant le premier enseignement.
const GUIDED_MAP := "skirmish_atlantic"
const GUIDED_PLAYERS := 3
# Faction RECOMMANDÉE au draft (jamais imposée) : le pouvoir le plus lisible du jeu — « +1 renfort
# fixe à chaque phase de renforts » se constate au premier tour, sans rien connaître des règles.
const GUIDED_FACTION := "barons_ferraille"

# --- Fichier de mémoire LOCALE ----------------------------------------------------------------
# LOCALE et non serveur, à dessein : revoir une bulle sur une nouvelle machine est un comportement
# acceptable, et un aller-retour réseau PAR BULLE ne l'était pas. Le drapeau du BRIEFING, lui, est
# bien serveur (`users.tutorial_done`) — c'est une récompense, pas un confort d'affichage.
const HINTS_PATH := "user://tutorial_hints.json"

# Marges de sécurité du coach dans l'ARÈNE : la barre basse (bouton de repli 26 + corps 272) et le
# panneau COMMS (382) occupent exactement le coin bas-droit. Sans ces marges, le coach s'assiérait
# sur les contrôles qu'il explique.
const ARENA_MARGIN_RIGHT := 400.0
const ARENA_MARGIN_BOTTOM := 316.0
# Marges des écrans de MENU (QG, draft, Rapport Post-Op) : rien n'occupe le coin bas-droit.
const MENU_MARGIN_RIGHT := 32.0
const MENU_MARGIN_BOTTOM := 32.0

# =========================================================
# REGISTRE DES ÉTAPES DE LA PREMIÈRE OPÉRATION (§8.129, LOT C)
# =========================================================
# `id`      : identifiant STABLE (mémoire de progression, tests).
# `text`    : clé i18n du texte du coach.
# `anchor`  : id d'ancre à surligner ("" = aucun surlignage).
# `ack`     : clé i18n du bouton principal.
# L'ORDRE de ce tableau n'impose RIEN : chaque étape est armée par son propre déclencheur RÉEL.
# Un joueur plus rapide que le coach (il a déjà attaqué quand l'étape ATTAQUER s'arme) voit
# l'étape SAUTÉE en silence — `_already_satisfied()` porte cette lecture.
const STEPS := [
	{"id": "welcome",   "text": "TUTO_STEP_WELCOME",   "anchor": ""},
	{"id": "draft",     "text": "TUTO_STEP_DRAFT",     "anchor": "draft_recommended"},
	{"id": "blind",     "text": "TUTO_STEP_BLIND",     "anchor": "deploy_confirm"},
	{"id": "reinforce", "text": "TUTO_STEP_REINFORCE", "anchor": "player_zone"},
	{"id": "deploy",    "text": "TUTO_STEP_DEPLOY",    "anchor": "deploy_confirm"},
	{"id": "attack",    "text": "TUTO_STEP_ATTACK",    "anchor": ""},
	{"id": "combat",    "text": "TUTO_STEP_COMBAT",    "anchor": ""},
	{"id": "conquer",   "text": "TUTO_STEP_CONQUER",   "anchor": ""},
	{"id": "hero",      "text": "TUTO_STEP_HERO",      "anchor": "player_zone"},
	{"id": "objective", "text": "TUTO_STEP_OBJECTIVE", "anchor": "objective_tracker"},
	{"id": "zone",      "text": "TUTO_STEP_ZONE",      "anchor": ""},
	{"id": "movecard",  "text": "TUTO_STEP_MOVECARD",  "anchor": "next_phase"},
	{"id": "debrief",   "text": "TUTO_STEP_DEBRIEF",   "anchor": ""},
]

# =========================================================
# REGISTRE DES AIDES CONTEXTUELLES (§8.129, LOT D)
# =========================================================
# id → { text: clé i18n (2 lignes max), section: section du MANUEL ouverte par « EN SAVOIR PLUS » }.
# Une bulle par PREMIÈRE rencontre, jamais deux fois — c'est la promesse du dispositif.
const HINTS := {
	"first_pact_received": {"text": "TUTO_HINT_PACT_RECEIVED", "section": "pacts"},
	"first_pact_button":   {"text": "TUTO_HINT_PACT_BUTTON",   "section": "pacts"},
	"first_pp_spend":      {"text": "TUTO_HINT_PP_SPEND",      "section": "hero"},
	"first_power_ready":   {"text": "TUTO_HINT_POWER_READY",   "section": "factions"},
	"first_card":          {"text": "TUTO_HINT_CARD",          "section": "phases"},
	"first_final_protocol": {"text": "TUTO_HINT_FINAL_PROTOCOL", "section": "phases"},
	"first_spectator":     {"text": "TUTO_HINT_SPECTATOR",     "section": "phases"},
	"first_br_queue":      {"text": "TUTO_HINT_BR_QUEUE",      "section": "battle_royale"},
	"first_coup_order":    {"text": "TUTO_HINT_COUP_ORDER",    "section": "battle_royale"},
	"first_company_tab":   {"text": "TUTO_HINT_COMPANY",       "section": "factions"},
	"first_ranked_queue":  {"text": "TUTO_HINT_RANKED",        "section": "phases"},
	"first_shop_visit":    {"text": "TUTO_HINT_SHOP",          "section": "factions"},
	# Les deux ancres `# TUTO:` posées par PLAN_EXPERIENCE dans `war_roster.gd` : l'auteur y avait
	# jugé la lecture confuse. Elles deviennent deux bulles à part entière (LOT D : « une ancre sans
	# bulle = ajoute la bulle »), déclenchées à la première ouverture du Roster de Guerre.
	"first_roster_order":  {"text": "TUTO_HINT_ROSTER_ORDER",  "section": "phases"},
	"first_roster_enemy":  {"text": "TUTO_HINT_ROSTER_ENEMY",  "section": "hero"},
	# §8.132 — première partie jouée sous un ÉVÉNEMENT MUTATEUR. Renvoie vers la section PHASES du
	# Manuel : ce que l'événement modifie (zone, temps, cartes, renforts) y est déjà décrit dans sa
	# version de base — la bulle explique seulement que ces règles-là ont bougé pour ce week-end.
	"first_event":         {"text": "TUTO_HINT_EVENT",         "section": "phases"},
}

# --- État ---------------------------------------------------------------------------------------
var _coach: Control = null
# Partie guidée EN COURS. Persisté localement : le briefing doit survivre à une reconnexion, et
# même à un redémarrage du client en cours de partie (on ne stocke RIEN côté serveur pour ça).
var guided := false
# Étapes déjà soldées (id → true). Reconstruit à la volée depuis l'état à la reconnexion.
var _steps_done := {}
# Bulles déjà vues (id → true), persistées.
var _hints_seen := {}
# File d'attente : {kind: "step"|"hint", id, text, anchor, section}. UN SEUL panneau à l'écran.
var _queue: Array = []
var _current: Dictionary = {}
# Ancres enregistrées par les écrans : id → Control. Nettoyées paresseusement (les Controls meurent
# avec leur scène).
var _anchors := {}
# Le briefing a-t-il été lancé depuis le QG dans CETTE session ? Sert à ne pas relancer un salon si
# le joueur revient au QG pendant la création.
var _launching := false
# Manuel de Guerre ouvert (une seule instance à la fois).
var _manual: Control = null


func _ready() -> void:
	layer = COACH_LAYER
	_load_hints()
	_coach = CoachPanelScript.new()
	_coach.name = "CoachPanel"
	add_child(_coach)
	_coach.acknowledged.connect(_on_acknowledged)
	_coach.skip_requested.connect(_on_skip_requested)
	_coach.more_requested.connect(open_manual)
	# Le manager écoute les MÊMES signaux que le HUD (§6.1 : il n'en dérive aucune décision de jeu).
	NetworkManager.game_event.connect(_on_game_event)
	NetworkManager.game_state_updated.connect(_on_state_updated)
	NetworkManager.game_started_signal.connect(_on_game_started)
	NetworkManager.private_created.connect(_on_private_created)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.tutorial_settled.connect(_on_tutorial_settled)


# =========================================================
# 1. ÉTAT SERVEUR DU BRIEFING
# =========================================================

# Le QG doit-il mettre la PREMIÈRE OPÉRATION en avant ? NON tant que le serveur n'a pas RÉELLEMENT
# renvoyé le drapeau (`tutorial_done_known`) : sur un serveur pas encore redéployé, supposer
# « false » proposerait le briefing à toute la population, vétérans compris.
func should_offer_first_operation() -> bool:
	return AuthManager.tutorial_done_known and not AuthManager.tutorial_done


# =========================================================
# 2. LANCEMENT DE LA PREMIÈRE OPÉRATION
# =========================================================
# Salon privé auto-créé + LANCER AVEC BOTS immédiat, SANS montrer l'écran salon : le joueur n'a
# rien à comprendre d'un salon pour sa première partie. On réutilise les DEUX routes existantes
# (§8.116) telles quelles — aucune route de tutoriel côté matchmaking.
func start_first_operation() -> void:
	if _launching:
		return
	_launching = true
	guided = true
	_steps_done.clear()
	_queue.clear()
	_current = {}
	_save_hints()          # persiste `guided` : survit à un redémarrage en cours de partie
	MatchConfig.set_mode("tutorial", GUIDED_PLAYERS, false)
	MatchConfig.set_map(GUIDED_MAP)
	NetworkManager.private_create(GUIDED_MAP, GUIDED_PLAYERS)


func _on_private_created(ok: bool, data: Dictionary) -> void:
	if not _launching:
		return
	if not ok or not bool(data.get("created", false)):
		# Échec (déjà en salle, sanction, serveur injoignable) : on ABANDONNE le briefing sans rien
		# solder — le joueur le retrouvera au QG. Silence assumé : `search_screen` reste le seul
		# écran qui explique un refus de matchmaking, et il n'est pas ouvert ici.
		_launching = false
		guided = false
		_save_hints()
		return
	NetworkManager.current_room_id = str(int(data.get("room_id", -1)))
	NetworkManager.current_salon_code = str(data.get("code", ""))
	# `salon_screen` ouvrait le tunnel WS à son `_ready` ; on ne passe pas par lui, donc on l'ouvre.
	NetworkManager.connect_to_server(NetworkManager.current_room_id)


func _on_server_connected() -> void:
	if not _launching:
		return
	# LANCER AVEC BOTS : le serveur remplit la salle et diffuse `game_started`.
	NetworkManager.private_start_bots()


func _on_game_started() -> void:
	if not _launching:
		return
	_launching = false
	TransitionManager.change_scene("res://scenes/faction_selection/faction_selection.tscn")


# Appelé par le QG à chaque arrivée. Purge un lancement RESTÉ EN L'AIR : si `private_create` a
# réussi mais que `game_started` n'est jamais venu (serveur muet, salle fermée), `_launching`
# resterait vrai et le bouton « LANCER LE BRIEFING » serait mort en silence. Revenir au QG signifie
# précisément que ce lancement-là n'aboutira pas.
func notify_hub_entered() -> void:
	_launching = false


# « JE CONNAIS LA GUERRE » au QG : drapeau posé, AUCUNE prime (la prime paie l'effort, pas le clic).
func decline_first_operation() -> void:
	guided = false
	_save_hints()
	NetworkManager.tutorial_skip()


# =========================================================
# 3. MACHINE À ÉTAPES — pilotée par les ÉVÈNEMENTS RÉELS
# =========================================================
# Aucune minuterie nulle part : chaque étape attend le fait de jeu qui la rend pertinente. Une
# étape dont la condition de sortie est DÉJÀ remplie est marquée soldée sans jamais s'afficher.

# Appelé par `faction_selection.gd` à son `_ready`.
func bind_draft(screen: Control) -> void:
	if not guided or screen == null:
		return
	_coach.set_safe_margins(MENU_MARGIN_RIGHT, MENU_MARGIN_BOTTOM)
	_arm("welcome")
	_arm("draft")


# Appelé par `main.gd` à son `_ready` (l'arène est prête, le HUD existe).
func bind_arena(_controller: Node, _hud: Control) -> void:
	# ⚠️ La référence d'arène est gardée MÊME quand `guided` est faux : `notify_game_over()` et les
	# nettoyages doivent pouvoir éteindre un surlignage laissé derrière par un briefing interrompu.
	# Typée `Node` — `main.gd` étend `Node`, pas `Control` (piège §7.3 : une signature `Control`
	# passe l'`--import` sans broncher et casse au BOOT).
	_arena = _controller
	if not guided:
		return
	_coach.set_safe_margins(ARENA_MARGIN_RIGHT, ARENA_MARGIN_BOTTOM)
	# Le draft est derrière nous quoi qu'il arrive.
	_steps_done["welcome"] = true
	_steps_done["draft"] = true
	# RECONNEXION / redémarrage en cours de partie : on déduit de l'état courant les étapes déjà
	# dépassées, puis on arme celle qui correspond au moment présent.
	_sync_from_state()


# Appelé par le contrôleur d'arène à l'ouverture du Rapport Post-Op : le débrief et le solde du
# briefing. Typé `Node` et non `Control` — `main.gd` étend `Node` (l'arène n'est pas un Control).
func bind_report(_screen: Node) -> void:
	if not guided:
		return
	_coach.set_safe_margins(MENU_MARGIN_RIGHT, MENU_MARGIN_BOTTOM)
	_arm("debrief")


# Le joueur a verrouillé sa faction (relayé par `faction_selection.gd`).
func notify_faction_locked() -> void:
	_close_step("draft")


func _on_state_updated() -> void:
	if not guided:
		return
	_sync_from_state()
	var stage := str(GameState.stage)
	var phase := int(GameState.current_phase)
	var mine: bool = int(GameState.current_player_id) == int(AuthManager.user_id)
	if stage == "placement":
		_arm("blind")
		return
	if stage != "playing" or not mine:
		return
	match phase:
		1: _arm("reinforce")
		2: _arm("deploy")
		3: _arm("attack")
		4, 5: _arm("movecard")


func _on_game_event(event) -> void:
	if not guided or typeof(event) != TYPE_DICTIONARY:
		return
	var me := int(AuthManager.user_id)
	var etype := str(event.get("event_type", ""))
	# --- Faits PORTÉS par le type d'évènement ---
	match etype:
		"units_deployed":
			if int(event.get("player_id", -9999)) == me:
				_close_step("blind")
				_close_step("deploy")
		"attack_result":
			if int(event.get("attacker_id", -9999)) == me:
				_close_step("attack")
				_arm("combat")
				if bool(event.get("conquered", false)):
					_arm("conquer")
			# Le duel de héros se joue dans les DEUX sens : subir compte autant qu'infliger.
			if int(event.get("attacker_id", -9999)) == me or int(event.get("defender_id", -9999)) == me:
				_arm("hero")
		"conquer_move_resolved":
			if int(event.get("player_id", -9999)) == me:
				_close_step("conquer")
				_arm("objective")
		"turn_passed", "turn_timeout":
			if int(event.get("player_id", -9999)) == me:
				_close_step("movecard")
	# --- Faits portés par les ÉVÈNEMENTS SYSTÈME (codes imbriqués) ---
	var sys = event.get("system_events", [])
	if typeof(sys) != TYPE_ARRAY:
		return
	for sev in sys:
		if typeof(sev) != TYPE_DICTIONARY:
			continue
		match str(sev.get("code", "")):
			"reinforcements_granted":
				if int(sev.get("player_id", -9999)) == me:
					_arm("reinforce")
			"zone_forecast", "zone_grew":
				_arm("zone")


# La partie est finie : le débrief attend le Rapport Post-Op (`bind_report`).
func notify_game_over() -> void:
	# Nettoyage n°4 AVANT la garde `guided` : un briefing passé en cours de partie a pu laisser un
	# liseré allumé, et le Rapport Post-Op s'ouvre par-dessus un plateau encore visible.
	_clear_board_highlight()
	if not guided:
		return
	for id in ["blind", "deploy", "attack", "combat", "conquer", "movecard", "objective", "zone",
			"reinforce", "hero"]:
		_steps_done[id] = true
	_dismiss_current()


# Déduit de l'ÉTAT COURANT les étapes déjà dépassées. C'est ce qui rend la machine tolérante à la
# reconnexion (et au joueur plus rapide que le coach) SANS rien persister côté serveur : l'état
# suffit à dire ce qui a forcément déjà eu lieu.
func _sync_from_state() -> void:
	var stage := str(GameState.stage)
	var turn := int(GameState.current_turn)
	var phase := int(GameState.current_phase)
	if stage != "placement":
		_steps_done["blind"] = true        # la partie a démarré : le déploiement aveugle est passé
	if stage == "playing" and turn >= 2:
		# Au 2ᵉ round, tout ce qui appartient au premier tour a déjà été vécu (ou raté) : insister
		# reviendrait à expliquer une phase qu'on ne reverra pas avant longtemps.
		for id in ["reinforce", "deploy"]:
			_steps_done[id] = true
	if stage == "playing" and turn >= 3:
		for id in ["attack", "movecard"]:
			_steps_done[id] = true
	if stage == "finished":
		notify_game_over()
	# Une phase 4/5 en cours signifie que les phases 1-3 du tour sont derrière nous.
	if stage == "playing" and phase >= 4 \
			and int(GameState.current_player_id) == int(AuthManager.user_id):
		for id in ["reinforce", "deploy", "attack"]:
			_steps_done[id] = true


# =========================================================
# 4. FILE D'ATTENTE — un seul panneau à l'écran
# =========================================================

func _arm(step_id: String) -> void:
	if not guided or _steps_done.get(step_id, false):
		return
	var spec := _step_spec(step_id)
	if spec.is_empty():
		return
	# Déjà en file / déjà affiché : on n'empile pas deux fois la même étape.
	if str(_current.get("id", "")) == step_id:
		return
	for q in _queue:
		if str(q.get("id", "")) == step_id:
			return
	_queue.append({
		"kind": "step", "id": step_id,
		"text": tr(str(spec.get("text", ""))),
		"anchor": str(spec.get("anchor", "")),
		"section": "",
	})
	_pump()


# Ferme l'étape parce que sa CONDITION DE SORTIE est remplie (le joueur a agi). Si elle n'avait pas
# encore été montrée, elle est simplement soldée : c'est le « saut silencieux » du §8.129.
func _close_step(step_id: String) -> void:
	if not guided:
		return
	_steps_done[step_id] = true
	_queue = _queue.filter(func(q): return str(q.get("id", "")) != step_id)
	# Chemin de nettoyage n°1 : la PREMIÈRE ATTAQUE éteint le liseré. Explicite, et non délégué à
	# `_pump()` : quand plus rien n'attend dans la file, `_pump` sort immédiatement et ne rappelle
	# donc PAS `_apply_board_highlight`. Le liseré or serait resté allumé sur un territoire déjà
	# attaqué — et un liseré or, dans ce jeu, veut dire « zone radioactive annoncée ».
	if step_id == "attack":
		_clear_board_highlight()
	if str(_current.get("id", "")) == step_id:
		_dismiss_current()


func _step_spec(step_id: String) -> Dictionary:
	for s in STEPS:
		if str(s.get("id", "")) == step_id:
			return s
	return {}


func _pump() -> void:
	if not _current.is_empty() or _queue.is_empty():
		return
	_current = _queue.pop_front()
	var is_step: bool = str(_current.get("kind", "")) == "step"
	# Surlignage PLATEAU : calculé AVANT l'affichage, car il enrichit le texte de l'étape (« vise X
	# — n % »). Appelé pour CHAQUE panneau, y compris les bulles : c'est ce passage systématique qui
	# éteint le liseré de l'étape précédente (chemin de nettoyage n°2).
	var board_suffix := _apply_board_highlight(str(_current.get("id", "")) if is_step else "")
	_coach.show_message(
		tr("TUTO_EYEBROW_COACH") if is_step else tr("TUTO_EYEBROW_HINT"),
		str(_current.get("text", "")) + board_suffix,
		tr("TUTO_BTN_OK"),
		# « PASSER LE BRIEFING » n'a de sens QUE pendant la Première Opération : une bulle
		# contextuelle ne se « passe » pas, elle se referme.
		tr("TUTO_BTN_SKIP") if is_step else "",
		tr("TUTO_BTN_MORE"),
		str(_current.get("section", "")))
	_apply_highlight(str(_current.get("anchor", "")))


func _dismiss_current() -> void:
	_current = {}
	_coach.hide_message()
	_pump()


func _on_acknowledged() -> void:
	if _current.is_empty():
		return
	if str(_current.get("kind", "")) == "step":
		_steps_done[str(_current.get("id", ""))] = true
		# Le débrief est la DERNIÈRE étape : le valider solde le briefing (et paie la prime).
		if str(_current.get("id", "")) == "debrief":
			_complete_briefing()
	_dismiss_current()


func _on_skip_requested() -> void:
	# ÉCHAPPATOIRE PERMANENTE : le coach disparaît, la partie CONTINUE normalement (aucun appel
	# moteur, aucun abandon). Le drapeau est posé sans prime.
	guided = false
	_queue.clear()
	_current = {}
	_coach.hide_message()
	_clear_board_highlight()   # chemin de nettoyage n°3 : le briefing est abandonné, le plateau redevient neutre
	_save_hints()
	NetworkManager.tutorial_skip()


func _complete_briefing() -> void:
	guided = false
	_save_hints()
	NetworkManager.tutorial_complete()


func _on_tutorial_settled(ok: bool, data: Dictionary) -> void:
	if not ok:
		# Serveur antérieur (404) ou incident : on ne ment JAMAIS sur un solde. Le coach se tait,
		# le QG reproposera le briefing au prochain lancement — pas de prime fantôme.
		return
	AuthManager.mark_tutorial_done()
	var awarded := int(data.get("coins_awarded", 0))
	if awarded <= 0:
		return
	tutorial_reward_granted.emit(awarded, int(data.get("coins", 0)))
	# Dernier mot du coach : la prime, ANNONCÉE APRÈS confirmation du serveur. On réutilise le même
	# panneau (jamais deux composants à l'écran) et on n'annonce QUE ce qui a réellement été crédité.
	_queue.append({
		"kind": "reward", "id": "reward",
		"text": tr("TUTO_REWARD_TOAST") % awarded,
		"anchor": "", "section": "",
	})
	_pump()


# =========================================================
# 5. ANCRES DE SURLIGNAGE
# =========================================================
# Chaque écran déclare les contrôles que le coach peut désigner. Un id inconnu ou un contrôle mort
# ne surligne RIEN — jamais d'erreur, jamais de rectangle orphelin.
func register_anchor(id: String, control: Control) -> void:
	if id == "":
		return
	if control == null:
		_anchors.erase(id)
		return
	_anchors[id] = control


func anchor(id: String) -> Control:
	var c = _anchors.get(id, null)
	if c == null or not is_instance_valid(c):
		_anchors.erase(id)
		return null
	return c


# =========================================================
# SURLIGNAGE PLATEAU DE L'ÉTAPE « ATTAQUER » (finitions pré-playtest)
# =========================================================
# Le reste-à-faire n°2 du §8.129 : l'étape ATTAQUER expliquait quoi faire sans montrer OÙ. On
# désigne désormais la MEILLEURE cible du tour, calculée par l'arène (`tutorial_attack_hint`) avec
# la prévision de combat qui sert déjà au survol — le coach ne calcule RIEN lui-même (⛔ aucune
# règle de jeu ici : il écoute et il affiche).
#
# ⚠️ NETTOYAGE : quatre chemins mènent à l'extinction du liseré, et ils sont tous couverts —
#   1. la première attaque lancée  → `_close_step("attack")` (évènement `attack_result`) ;
#   2. tout changement d'étape     → `_pump()` rappelle `_apply_board_highlight` pour la suivante ;
#   3. « PASSER LE BRIEFING »      → `_on_skip_requested` ;
#   4. la fin de partie            → `notify_game_over`.
# Un liseré or orphelin serait pris pour un télégraphe de zone — c'est-à-dire pour une MENACE.
var _arena: Node = null

func _board() -> Node:
	if _arena == null or not is_instance_valid(_arena):
		return null
	var b = _arena.get("board")
	return b if (b != null and is_instance_valid(b) and b.has_method("tutorial_highlight")) else null


func _clear_board_highlight() -> void:
	var b := _board()
	if b != null:
		b.tutorial_highlight_clear()


# Rend le complément de texte (« vise X — n % de victoire ») et allume le liseré, ou "" si l'étape
# n'est pas ATTAQUER / si aucune cible n'est jouable.
func _apply_board_highlight(step_id: String) -> String:
	_clear_board_highlight()
	if step_id != "attack" or _arena == null or not is_instance_valid(_arena):
		return ""
	if not _arena.has_method("tutorial_attack_hint"):
		return ""
	var hint: Dictionary = _arena.tutorial_attack_hint()
	if hint.is_empty():
		return ""
	var b := _board()
	if b != null:
		b.tutorial_highlight(str(hint.get("tid", "")))
	return "\n" + tr("TUTO_STEP_ATTACK_TARGET") % [
		str(hint.get("name", "")), int(round(float(hint.get("prob", 0.0)) * 100.0))]


func _apply_highlight(anchor_id: String) -> void:
	var target := anchor(anchor_id) if anchor_id != "" else null
	if target != null and anchor_id == "objective_tracker":
		# Le tracker vit dans une PAGE D'ONGLET depuis le LOT 0 : surligner un contrôle rangé
		# derrière un onglet fermé ne montrerait rien. On ouvre l'onglet AVANT de désigner.
		var hud := anchor("hud_root")
		if hud != null and hud.has_method("open_objectives_tab"):
			hud.call("open_objectives_tab")
	_coach.highlight(target)


# =========================================================
# 6. AIDES CONTEXTUELLES (LOT D)
# =========================================================
# `hint_once(id)` est un NO-OP si : la bulle a déjà été vue, les aides sont coupées, ou une partie
# guidée est en cours (le coach a la parole — deux voix simultanées seraient illisibles).
# `target` accepte indifféremment un ID d'ancre (String) ou le Control lui-même : les écrans qui
# ont déjà le contrôle sous la main n'ont ainsi rien à enregistrer, et ceux qui le construisent
# ailleurs passent par le registre. "" / null = aucune désignation.
func hint_once(id: String, target = "") -> void:
	if guided or not hints_enabled():
		return
	if not HINTS.has(id) or _hints_seen.get(id, false):
		return
	var anchor_id := ""
	if typeof(target) == TYPE_STRING:
		anchor_id = str(target)
	elif target is Control:
		anchor_id = "_hint_" + id
		register_anchor(anchor_id, target)
	# Marquée vue À L'ARMEMENT et non à la fermeture : si le joueur change d'écran avant de lire,
	# la bulle a tout de même été proposée — la promesse est « une fois », pas « une lecture ».
	_hints_seen[id] = true
	_save_hints()
	var spec: Dictionary = HINTS[id]
	_queue.append({
		"kind": "hint", "id": id,
		"text": tr(str(spec.get("text", ""))),
		"anchor": anchor_id,
		"section": str(spec.get("section", "")),
	})
	_pump()


func hints_enabled() -> bool:
	return bool(SettingsManager.get_comfort("context_hints"))


# « REVOIR LES AIDES » (Paramètres) : remet la mémoire des bulles à zéro. Distinct de la case
# AIDES CONTEXTUELLES — se taire n'est pas la même chose que tout recommencer.
func reset_hints() -> void:
	_hints_seen.clear()
	_save_hints()


func hints_seen_count() -> int:
	return _hints_seen.size()


# =========================================================
# 7. MANUEL DE GUERRE
# =========================================================
func open_manual(section_id: String = "") -> void:
	if _manual != null and is_instance_valid(_manual):
		if _manual.has_method("focus_section"):
			_manual.call("focus_section", section_id)
		return
	var script: Script = load("res://scripts/ui/war_manual.gd")
	if script == null:
		return
	_manual = script.new()
	add_child(_manual)
	if _manual.has_method("focus_section"):
		_manual.call("focus_section", section_id)
	if _manual.has_signal("closed"):
		_manual.connect("closed", func() -> void:
			if _manual != null and is_instance_valid(_manual):
				_manual.queue_free()
			_manual = null)


# =========================================================
# 8. PERSISTANCE LOCALE
# =========================================================
func _load_hints() -> void:
	if not FileAccess.file_exists(HINTS_PATH):
		return
	var f := FileAccess.open(HINTS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var seen = data.get("seen", [])
	if typeof(seen) == TYPE_ARRAY:
		for id in seen:
			_hints_seen[str(id)] = true
	# Reprise d'un briefing interrompu par une fermeture du client (§8.129 : la machine survit à
	# une reconnexion). L'état de partie fera le reste — aucune étape n'est mémorisée, elles sont
	# DÉDUITES (`_sync_from_state`).
	guided = bool(data.get("guided", false))


func _save_hints() -> void:
	var f := FileAccess.open(HINTS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"seen": _hints_seen.keys(),
		"guided": guided,
	}))
	f.close()
