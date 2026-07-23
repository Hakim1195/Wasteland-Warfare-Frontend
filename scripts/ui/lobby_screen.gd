extends Control

@export var status_label: Label
@export var room_list_container: VBoxContainer
@export var refresh_button: Button

@export var join_id_input: LineEdit
@export var join_button: Button

@export var create_public_button: Button
@export var create_private_button: Button
@export var back_button: Button

# Effectif (3-6) HÉRITÉ du mode choisi au Menu Principal (autoload MatchConfig) — AFFICHAGE SEUL.
# Le sélecteur manuel (SpinBox « EFFECTIF 3-6 ») a été RETIRÉ (§8.57) : le lobby ne fait plus que
# REFLÉTER le mode décidé au menu, il ne le laisse plus rechoisir.
@export var headcount_value: Label

# Label "Centre de Commandement" affichant le pseudo de l'opérateur connecté (refonte UI §2.1).
@export var pseudo_label: Label

# --- Couche Vue 2.5D (parallaxe / VFX "Modern Warfare") ---
# Calques de profondeur pilotés par la souris, RÉPLIQUÉS À L'IDENTIQUE depuis auth_screen
# pour garantir une transition de fond "seamless" entre l'écran de connexion et le lobby.
@export var background: TextureRect
@export var hero_graphic: TextureRect
@export var ash_particles: GPUParticles2D

# Panneaux principaux : reçoivent les encoches de coin biseautées (charte « Warzone Command » §2).
@export var command_panel: Control
@export var browser_panel: Control

# Helpers UI partagés de la charte « Warzone Command » (§2).
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

# Amplitude du décalage parallaxe en pixels. Le héros (avant-plan) glisse plus
# vite que le fond → illusion de profondeur de champ. Valeurs alignées sur auth_screen.gd.
const BG_PARALLAX := 22.0
const HERO_PARALLAX := 48.0
# Vitesse de lissage du lerp (plus haut = plus réactif).
const PARALLAX_SMOOTH := 6.0
# Sur-cadrage (overscan) des calques : doit rester synchronisé avec offset_left/top des
# nœuds Background/HeroGraphic dans la scène (-60).
const OVERSCAN := 60.0

# Couleur d'accent "Cyan Tactique" de la charte Warzone Command.
const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
# Or « récompense » de la charte (#E0B249) — badge « CLASSÉE » (§8.88).
const ACCENT_GOLD := Color(0.878431, 0.698039, 0.286275, 1)

# Positions de repos des calques, recalculées analytiquement à chaque resize.
var _bg_rest := Vector2.ZERO
var _hero_rest := Vector2.ZERO

var selected_room_id: int = -1

# Effectif imposé par le mode du Menu Principal (autoload MatchConfig). Pilote À LA FOIS la création
# de salle ET le filtrage du Radar (on ne montre que les salles de même capacité). Borné 3-6 ;
# une absence de sélection (0, ex. accès direct au lobby en debug) est ramenée à 3 par clampi.
var _required_players: int = 3

# Mode « Classée » (§8.88) hérité du Menu Principal : la salle créée est marquée is_ranked et
# devient le SEUL mode à créditer le ladder. Le serveur fait autorité (il force l'effectif et
# refuse une carte incompatible) — les constantes ci-dessous ne sont qu'une garde d'UI, tenue
# en MIROIR de api/game/ranked.py (RANKED_PLAYER_COUNT) et du registre des cartes.
var _required_ranked: bool = false
# Effectif EXACT d'une partie classée — miroir de ranked.RANKED_PLAYER_COUNT.
const RANKED_PLAYER_COUNT := 5
# Seule carte supportant l'effectif classé aujourd'hui (skirmish_atlantic est bornée 3-4).
const RANKED_MAP_ID := "classic_42"

# Rafraîchissement automatique de la liste (en secondes).
# Le lobby est purement REST : le backend n'émet AUCUN push WebSocket quand une salle
# est créée/rejointe, et un joueur qui parcourt le lobby n'est connecté à aucun WebSocket
# (la connexion WS n'a lieu qu'APRÈS avoir rejoint une salle, dans waiting_room).
# Sans backend modifiable, le seul moyen d'avoir une liste "temps réel" est de repoller
# périodiquement GET /lobby/rooms tant que cet écran est affiché.
const AUTO_REFRESH_INTERVAL := 5.0   # 5 s (option §8.2 : réduit le volume vu par l'edge ; radar un peu moins réactif)
var _auto_refresh_timer: Timer

func _ready():
	# Encoches biseautées sur les panneaux (charte « Warzone Command » §2).
	WarzoneUI.add_corner_notches(command_panel)
	WarzoneUI.add_corner_notches(browser_panel)

	# Clics UI
	if refresh_button: refresh_button.pressed.connect(_on_refresh_pressed)
	if join_button: join_button.pressed.connect(_on_join_manual_pressed)
	if create_public_button: create_public_button.pressed.connect(_on_create_public_pressed)
	if create_private_button: create_private_button.pressed.connect(_on_create_private_pressed)
	# Sélecteur de CARTE (G5 §8.71) : « GUERRE MONDIALE — 42 » / « THÉÂTRE ATLANTIQUE — 20, rapide ».
	_build_map_selector()
	if back_button: back_button.pressed.connect(_on_back_pressed)

	# SFX d'interface (survol/clic — R6) + nappe d'ambiance des menus (idempotente, R6).
	WarzoneUI.wire_buttons_sfx([refresh_button, join_button, create_public_button, create_private_button, back_button])
	AudioManager.start_menu_ambient()

	# Connexion aux signaux du NetworkManager
	NetworkManager.rooms_loaded.connect(_on_rooms_loaded)
	NetworkManager.lobby_error.connect(_on_lobby_error)
	# AC.7 — échec d'un FETCH de salles : coupe le polling auto (distinct des erreurs de join/create).
	NetworkManager.rooms_fetch_failed.connect(_on_rooms_fetch_failed)
	# AC.5 — expiration de session (le lobby n'a pas de top_nav) : retour à l'auth.
	NetworkManager.session_expired.connect(_on_session_expired)
	NetworkManager.lobby_action_success.connect(_on_lobby_success)

	# Identité du joueur dans le Centre de Commandement (pseudo posé au login, cf. AuthManager).
	# Repli NEUTRE « Joueur » (COMMON_PLAYER) — COMMON_OPERATOR est un libellé, pas un nom (§8.102).
	if pseudo_label:
		var pseudo: String = AuthManager.username if AuthManager.username != "" else tr("COMMON_PLAYER")
		pseudo_label.text = "// " + pseudo.to_upper()

	# Effectif HÉRITÉ du mode choisi au Menu Principal (autoload MatchConfig — refonte « Warzone
	# Command » §8.54). Le sélecteur manuel a disparu (§8.57) : cette valeur pilote À LA FOIS la
	# création de salle ET le filtrage du Radar. L'effectif (3-6) passe nativement par max_players.
	# Mode « Classée » (§8.88) : l'intention est LUE ici et câblée jusqu'au serveur (create_room).
	var match_cfg := get_node_or_null("/root/MatchConfig")
	if match_cfg != null:
		# clampi ramène une absence de sélection (0) à 3 → le lobby reflète toujours un mode cohérent.
		_required_players = clampi(int(match_cfg.selected_player_count), 3, 6)
		_required_ranked = bool(match_cfg.selected_ranked)
	if _required_ranked:
		# Garde DÉFENSIVE (le serveur re-valide et fait autorité) : une partie classée se joue à
		# RANKED_PLAYER_COUNT joueurs sur une carte qui les supporte. Aujourd'hui seule classic_42
		# accepte 5 (skirmish_atlantic est bornée 3-4) → on verrouille les deux pour ne jamais
		# soumettre une création vouée au 400.
		_required_players = RANKED_PLAYER_COUNT
		_selected_map_id = RANKED_MAP_ID
		_lock_map_selector_for_ranked()
		_show_ranked_badge()
	else:
		# Casual (§8.103) : une carte trop petite pour l'effectif du mode (Théâtre Atlantique
		# borné 3-4 face à FIVE 5 / EXA 6) laissait la création CLAMPER en silence — un joueur
		# en mode EXA(6) démarrait à 4. Le mode fait foi : ces cartes sont désactivées.
		_restrict_map_selector_to_mode()
	_refresh_headcount_display()

	# Mise en place de la couche 2.5D (repos des calques + dimensionnement des cendres).
	_setup_view_layer()
	get_viewport().size_changed.connect(_setup_view_layer)

	# Timer de rafraîchissement auto : repolle la liste en silence à intervalle régulier.
	# Détruit automatiquement avec cet écran (changement de scène) → le polling s'arrête seul.
	_auto_refresh_timer = Timer.new()
	_auto_refresh_timer.wait_time = AUTO_REFRESH_INTERVAL
	_auto_refresh_timer.autostart = true
	_auto_refresh_timer.timeout.connect(_on_auto_refresh)
	add_child(_auto_refresh_timer)

	# On charge la liste immédiatement à l'ouverture (le timer prend le relais ensuite).
	_on_refresh_pressed()

# ===========================================================================
# COUCHE VUE 2.5D — parallaxe identique à auth_screen.gd (transition "seamless").
# ===========================================================================
# Recalcule les positions de repos (overscan) et étale l'émetteur de cendres
# sur tout l'écran. Appelé au démarrage puis à chaque changement de résolution.
func _setup_view_layer():
	var vp := get_viewport_rect().size
	_bg_rest = Vector2(-OVERSCAN, -OVERSCAN)
	_hero_rest = Vector2(vp.x * 0.5 - OVERSCAN, -OVERSCAN)
	if ash_particles:
		ash_particles.position = vp * 0.5
		var mat := ash_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.emission_box_extents = Vector3(vp.x * 0.5 + 64.0, vp.y * 0.5 + 64.0, 1.0)
		ash_particles.restart()

func _process(delta):
	if background == null and hero_graphic == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	# Décalage normalisé de la souris par rapport au centre de l'écran : ~[-0.5, 0.5].
	var ratio := (get_viewport().get_mouse_position() / vp) - Vector2(0.5, 0.5)
	var weight := clampf(delta * PARALLAX_SMOOTH, 0.0, 1.0)
	# Les calques glissent à l'inverse de la souris → effet de profondeur réactif.
	if background:
		background.position = background.position.lerp(_bg_rest - ratio * BG_PARALLAX, weight)
	if hero_graphic:
		hero_graphic.position = hero_graphic.position.lerp(_hero_rest - ratio * HERO_PARALLAX, weight)

# Affiche (LECTURE SEULE) l'effectif imposé par le mode du Menu Principal dans le Centre de
# Commandement. Réutilise la clé i18n DÉJÀ existante du menu (MENU_MODE_PLAYERS, « %d JOUEURS ») →
# aucune nouvelle clé de traduction requise.
func _refresh_headcount_display() -> void:
	if headcount_value == null:
		return
	headcount_value.text = tr("MENU_MODE_PLAYERS") % _required_players

# --- ACTIONS UI ---
func _on_refresh_pressed():
	status_label.text = tr("LOBBY_SEARCHING")
	NetworkManager.fetch_rooms()

# Rafraîchissement automatique périodique : on repolle SANS écraser le status_label
# (pas de "Recherche..." clignotant toutes les 3 s). _on_rooms_loaded mettra à jour
# le compteur de salles, ce qui suffit à refléter l'état réel du serveur en continu.
func _on_auto_refresh():
	NetworkManager.fetch_rooms()

func _on_join_manual_pressed():
	var r_id = join_id_input.text.strip_edges()
	if r_id.is_valid_int():
		status_label.text = tr("LOBBY_JOIN_TRYING") % r_id
		NetworkManager.join_room(r_id.to_int())
	else:
		status_label.text = tr("LOBBY_INVALID_ID")

# =========================================================
# Sélecteur de CARTE (G5 §8.71) — construit par code au-dessus des boutons de création
# =========================================================
var _selected_map_id := "classic_42"
var _map_option: OptionButton = null
# Ordre des items du sélecteur → map_id (index 0 = classique, 1 = Atlantique).
const _MAP_CHOICES := ["classic_42", "skirmish_atlantic"]

func _build_map_selector() -> void:
	if create_public_button == null:
		return
	var parent := create_public_button.get_parent()
	var eyebrow := Label.new()
	eyebrow.text = tr("LOBBY_MAP_EYEBROW")
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color(0.211765, 0.772549, 0.85098, 1))
	_map_option = OptionButton.new()
	_map_option.add_item(tr("LOBBY_MAP_CLASSIC"))
	_map_option.add_item(tr("LOBBY_MAP_ATLANTIC"))
	_map_option.custom_minimum_size = Vector2(0, 40)
	_map_option.focus_mode = Control.FOCUS_NONE
	_map_option.item_selected.connect(func(idx: int) -> void:
		_selected_map_id = _MAP_CHOICES[clampi(idx, 0, _MAP_CHOICES.size() - 1)])
	# Insérés juste AU-DESSUS du bouton « CRÉER UNE OPÉRATION » (aucune retouche .tscn).
	parent.add_child(eyebrow)
	parent.add_child(_map_option)
	parent.move_child(eyebrow, create_public_button.get_index())
	parent.move_child(_map_option, create_public_button.get_index())

# Badge « CLASSÉE » (§8.88) — or « récompense » de la charte Warzone Command (#E0B249). Purement
# LOCAL (dérivé de MatchConfig) : aucun champ réseau requis. Inséré au-dessus de l'effectif affiché,
# donc aucune retouche .tscn.
func _show_ranked_badge() -> void:
	if headcount_value == null:
		return
	var badge := Label.new()
	badge.text = tr("LOBBY_RANKED_BADGE")
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", ACCENT_GOLD)
	var parent := headcount_value.get_parent()
	if parent == null:
		return
	parent.add_child(badge)
	parent.move_child(badge, headcount_value.get_index())

# Mode « Classée » (§8.88) : la carte est IMPOSÉE (seule classic_42 supporte 5 joueurs) — on cale
# le sélecteur dessus et on le désactive, plutôt que de laisser le joueur soumettre une création
# que le serveur refuserait en 400. Garde d'UI : le serveur reste seul juge.
func _lock_map_selector_for_ranked() -> void:
	if _map_option == null:
		return
	var idx := _MAP_CHOICES.find(RANKED_MAP_ID)
	if idx >= 0:
		_map_option.select(idx)
	_map_option.disabled = true
	_map_option.tooltip_text = tr("LOBBY_RANKED_MAP_LOCKED")

# Casual (§8.103) — miroir du principe classé ci-dessus : le MODE choisi au menu fait foi, la
# carte doit le supporter. Toute carte dont les bornes ne couvrent pas l'effectif du mode est
# DÉSACTIVÉE dans le sélecteur, avec une INFOBULLE « MAX N JOUEURS » — surtout PAS un suffixe de
# libellé : l'OptionButton se dimensionne sur l'item le plus long (fit_to_longest_item) et un
# libellé rallongé élargissait tout le Centre de Commandement en FIVE/HEXA (retour Hakim). La
# taille du panneau doit rester IDENTIQUE dans tous les modes. Garde d'avenir : si la carte
# déjà retenue devenait incompatible, on retombe sur la carte par défaut (couvre 3-6).
func _restrict_map_selector_to_mode() -> void:
	if _map_option == null:
		return
	for i in range(_MAP_CHOICES.size()):
		var def: Dictionary = MapData.MAP_DEFS.get(_MAP_CHOICES[i], {})
		var max_p := int(def.get("max_players", 6))
		var min_p := int(def.get("min_players", 3))
		if _required_players > max_p or _required_players < min_p:
			_map_option.set_item_disabled(i, true)
			if _required_players > max_p:
				_map_option.get_popup().set_item_tooltip(i, tr("LOBBY_MAP_MAX_PLAYERS") % max_p)
	var kept: Dictionary = MapData.MAP_DEFS.get(_selected_map_id, {})
	if _required_players > int(kept.get("max_players", 6)) \
			or _required_players < int(kept.get("min_players", 3)):
		_selected_map_id = MapData.DEFAULT_MAP_ID
		var idx := _MAP_CHOICES.find(_selected_map_id)
		if idx >= 0:
			_map_option.select(idx)

# Effectif de création CLAMPÉ aux bornes de la carte choisie (G5) : le serveur re-clampe de
# toute façon, mais on évite de créer une salle qui ne matcherait pas le mode du joueur.
func _create_headcount() -> int:
	var max_p := int(MapData.MAP_DEFS.get(_selected_map_id, {}).get("max_players", 6))
	return clampi(_required_players, 3, max_p)

func _on_create_public_pressed():
	# Effectif AUTOMATIQUE hérité du mode (MatchConfig, §8.57), CLAMPÉ aux bornes de la carte
	# choisie (G5 §8.71 : Théâtre Atlantique = 3-4). Le serveur re-clampe de toute façon.
	# is_ranked (§8.88) : marque la salle → seul mode à créditer le ladder.
	status_label.text = tr("LOBBY_CREATING_PUBLIC") % _create_headcount()
	NetworkManager.create_room(false, "", _create_headcount(), _selected_map_id, _required_ranked)

func _on_create_private_pressed():
	# Idem : la salle privée naît avec l'effectif du mode sélectionné au Menu Principal.
	status_label.text = tr("LOBBY_CREATING_PRIVATE") % _create_headcount()
	NetworkManager.create_room(true, "SECRET123", _create_headcount(), _selected_map_id,
		_required_ranked) # Le code secret sera configurable plus tard

# RETOUR (refonte navigation) : simple retour au menu principal, avec le fondu gunmetal
# entrant/sortant du TransitionManager (cohérent avec leaderboard / shop / profile / settings).
# La DÉCONNEXION a MIGRÉ dans l'écran Paramètres (settings.gd) ; le lobby étant purement REST
# (aucun WebSocket ouvert ici, cf. note AUTO_REFRESH_INTERVAL), revenir en arrière ne requiert
# AUCUN nettoyage réseau ni purge de session.
func _on_back_pressed():
	TransitionManager.change_scene("res://scenes/ui/main_menu.tscn")

# --- RÉPONSES DU SERVEUR ---
func _on_rooms_loaded(rooms: Array):
	# AC.7 — un fetch RÉUSSI alors que le polling était coupé (⇒ rafraîchissement MANUEL, l'auto étant
	# à l'arrêt) : on RELANCE le polling (retour en ligne).
	if _auto_refresh_timer and _auto_refresh_timer.is_stopped():
		_auto_refresh_timer.start()
	# On ne compte QUE les salles publiques affichées (les privées sont masquées de la liste).
	var shown := 0

	# 1. On vide l'ancienne liste.
	# queue_free() est différé (fin de frame) : les anciens nœuds coexisteraient avec les
	# nouveaux dessinés juste après → doublons/affichage figé. On les retire donc TOUT DE SUITE
	# de l'arbre avant de redessiner, puis on planifie leur libération mémoire.
	for child in room_list_container.get_children():
		room_list_container.remove_child(child)
		child.queue_free()

	# 2. On génère dynamiquement une ligne stylisée (Modern Warfare) par salle publique DONT LA
	#    CAPACITÉ CORRESPOND au mode choisi au Menu Principal (§8.57). Le filtrage est CÔTÉ CLIENT :
	#    GET /lobby/rooms n'expose AUCUN paramètre de capacité (CONTRAT_RESEAU §5) et la règle
	#    « interdiction de deviner » du contrat proscrit d'inventer une query string spéculative.
	#    Piège JSON float §5 : on force int() sur max_players avant la comparaison.
	for room in rooms:
		if room.get("is_private", false) == true:
			continue # On ne montre pas les salles privées dans la liste publique
		if int(room.get("max_players", 0)) != _required_players:
			continue # Capacité ≠ effectif du mode sélectionné → masquée du Radar
		# Étanchéité CLASSÉE ↔ casual (§8.103) : à capacité égale (5), le Radar du mode FIVE
		# listait aussi les salles CLASSÉE (et réciproquement, faussant l'attente de ladder).
		# room.get DÉFENSIF : un backend antérieur à §8.88 n'envoie pas is_ranked (→ casual).
		if bool(room.get("is_ranked", false)) != _required_ranked:
			continue # Intention classée ≠ intention du mode → masquée du Radar
		room_list_container.add_child(_build_room_row(room))
		shown += 1

	# Message d'état (le compteur reflète l'état réel du serveur à chaque repoll).
	if shown == 0:
		status_label.text = tr("LOBBY_NO_ROOMS")
	else:
		status_label.text = tr("LOBBY_ROOMS_FOUND") % shown

# Construit une ligne de salle épurée : nom à gauche, jauge "joueurs/max" centrée,
# bouton "REJOINDRE" (style ghost) à droite. Seul le PEUPLEMENT de l'UI change ici ;
# l'action de jonction reste NetworkManager.join_room (logique réseau inchangée).
func _build_room_row(room: Dictionary) -> PanelContainer:
	# JSON → float : on force des entiers pour l'affichage ET pour l'URL de jonction (piège §5).
	var room_id_int := int(room.get("id", -1))
	var max_p := int(room.get("max_players", 6))
	# Occupation courante : GameRoomResponse expose DÉSORMAIS `current_players: int` (§8.34, une fois
	# le backend redéployé §1). On la lit malgré tout DÉFENSIVEMENT (repli "—" si le champ manque, ex.
	# VPS pas encore à jour) ; les autres clés ne sont que des alias de tolérance. Jamais "0/x" faux.
	var current := -1
	for key in ["current_players", "player_count", "players_count", "nb_players"]:
		if room.has(key):
			current = int(room[key])
			break
	if current < 0 and typeof(room.get("players")) == TYPE_ARRAY:
		current = (room["players"] as Array).size()

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _make_row_style())
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	row.add_child(hbox)

	# Nom de la salle (aligné à gauche, occupe l'espace disponible).
	var name_label := Label.new()
	name_label.text = tr("LOBBY_ROOM_NAME") % str(room_id_int)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.933333, 0.952941, 0.968627, 1))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(name_label)

	# Label de CARTE (G5 §8.71) : renvoyé par le serveur (map_label) ; repli sur le miroir local
	# via map_id ; muet si aucun des deux (backend antérieur — aucune régression d'affichage).
	var map_txt := str(room.get("map_label", ""))
	if map_txt == "" and room.has("map_id"):
		map_txt = MapData.map_label(str(room.get("map_id", "")))
	if map_txt != "":
		var map_lbl := Label.new()
		map_lbl.text = map_txt.to_upper()
		map_lbl.add_theme_font_size_override("font_size", 13)
		map_lbl.add_theme_color_override("font_color", Color(0.541176, 0.592157, 0.647059, 1))
		map_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hbox.add_child(map_lbl)

	# Jauge d'effectif "joueurs/max" (centrée).
	var count_label := Label.new()
	count_label.text = (str(current) if current >= 0 else "—") + " / " + str(max_p)
	count_label.add_theme_font_size_override("font_size", 18)
	count_label.add_theme_color_override("font_color", Color(0.211765, 0.772549, 0.85098, 1))
	count_label.custom_minimum_size = Vector2(80, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(count_label)

	# Bouton "REJOINDRE" (style ghost épuré, aligné à droite).
	var btn := Button.new()
	btn.text = tr("LOBBY_JOIN")
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(130, 44)
	_style_ghost_button(btn)
	WarzoneUI.wire_button_sfx(btn)
	# On attache l'ID (entier) de la salle au bouton → jonction via la logique réseau intacte.
	btn.pressed.connect(func(): NetworkManager.join_room(room_id_int))
	hbox.add_child(btn)

	return row

# StyleBoxFlat d'une ligne de salle : fond translucide + liseré cyan à gauche (charte §2.1).
func _make_row_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.border_width_left = 3
	sb.border_color = ACCENT
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_right = 0
	sb.corner_radius_bottom_left = 0
	sb.content_margin_left = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 12.0
	return sb

# Applique le style "ghost" (fond quasi nul + liseré cyan translucide) à un bouton généré.
func _style_ghost_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.03)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.211765, 0.772549, 0.85098, 0.55)
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 12.0
	normal.content_margin_top = 8.0
	normal.content_margin_right = 12.0
	normal.content_margin_bottom = 8.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.211765, 0.772549, 0.85098, 0.16)
	hover.border_color = ACCENT

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", Color(0.541176, 0.592157, 0.647059, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_focus_color", Color(0.541176, 0.592157, 0.647059, 1))

func _on_lobby_success(action: String, data: Dictionary):
	var r_id = ""

	# IMPORTANT : JSON.parse_string transforme les nombres en float. str(11.0) donnerait "11.0",
	# ce qui ouvrirait une salle WebSocket "11.0" DISTINCTE de "11" (créateur isolé des autres).
	# On force donc systématiquement un identifiant entier propre.
	var raw_id = data.get("id", null)
	if raw_id != null:
		r_id = str(int(raw_id))

	if action == "create":
		status_label.text = tr("LOBBY_ROOM_CREATED")
	elif action == "join":
		# L'ID nous est renvoyé par le NetworkManager (liste ou saisie manuelle).
		status_label.text = tr("LOBBY_ACCESS_GRANTED")

	if r_id == "":
		status_label.text = tr("LOBBY_ROOM_NOT_FOUND")
		return

	# On s'assure d'avoir notre player_id (requis pour l'URL WebSocket) avant de connecter.
	if AuthManager.user_id < 0:
		status_label.text = tr("LOBBY_PREPARING")
		await AuthManager.ensure_user_id()
		if AuthManager.user_id < 0:
			status_label.text = tr("LOBBY_NO_IDENTITY")
			return

	# On mémorise la salle courante (utile à la salle d'attente / l'arène).
	NetworkManager.current_room_id = r_id

	# 1. On ouvre le fameux tunnel WebSocket vers cette salle précise !
	NetworkManager.connect_to_server(r_id)

	# 2. On téléporte le joueur dans la salle d'attente
	TransitionManager.change_scene("res://scenes/ui/waiting_room.tscn")

# AC.7 — le FETCH de salles a échoué : on COUPE le polling auto (pas de rafale toutes les 3 s vers un
# serveur injoignable) et on affiche le statut hors-ligne. Reprise SEULEMENT au prochain
# rafraîchissement MANUEL réussi (_on_rooms_loaded relance alors le timer).
func _on_rooms_fetch_failed(_msg: String) -> void:
	if _auto_refresh_timer:
		_auto_refresh_timer.stop()
	status_label.text = tr("LOBBY_OFFLINE")

# AC.5 — session expirée : purge le token, laisse un message et renvoie à l'auth (aucun retry).
func _on_session_expired() -> void:
	AuthManager.session_notice = tr("AUTH_SESSION_EXPIRED")
	AuthManager.clear_session()
	TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")

func _on_lobby_error(msg: String):
	status_label.text = tr("LOBBY_ERROR_PREFIX") % msg
	# AC.9 — échec BÉNIN (join d'une salle pleine/disparue, création…) : UN seul rafraîchissement de
	# la liste pour refléter l'état réel, JAMAIS de nouvelle tentative automatique de l'action.
	NetworkManager.fetch_rooms()
