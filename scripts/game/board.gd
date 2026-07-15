extends Node

# Vue du plateau (carte monde type Risk). Les 42 territoires sont placés MANUELLEMENT dans
# l'éditeur 2D ; ce script les RELIE aux données de MapData par le NOM du nœud (= id du
# territoire). AUCUNE logique de jeu ici (Règle d'Or §6.1) : c'est main.gd qui décide.
#
# Le développeur glisse le conteneur des 42 nœuds-territoires dans `territories_container`.
# Chaque nœud doit être nommé d'après un id de MapData.TERRITORIES (ex: "Alaska", "Brazil"…,
# la casse est ignorée). Cas nominal : des Area2D dessinés à la main → on câble leur signal
# `input_event` pour détecter le clic gauche. Fallback : un BaseButton (signal `pressed`).
# Dans les deux cas, un clic GAUCHE émet `territory_clicked(id)`.
signal territory_clicked(territory_id)
# Clic DROIT sur un territoire (Area2D uniquement) — utilisé par le tampon de déploiement
# (main.gd) pour RETIRER une troupe en attente (-1). Voir §8.26.
signal territory_right_clicked(territory_id)
# SURVOL d'un territoire (Area2D mouse_entered/mouse_exited) — consommé par la Prévision de
# combat (G4 §8.63) : en Phase 3, source sélectionnée + survol d'une cible ennemie adjacente →
# main.gd calcule et affiche les probabilités (CombatOdds). Vue pure : on ne fait qu'émettre.
signal territory_hovered(territory_id)
signal territory_unhovered(territory_id)
# Clic GAUCHE dans le VIDE (aucun territoire touché) — referme l'Inspecteur Tactique de Territoire
# (§1, charte Warzone Command). Émis par _unhandled_input avec une garde « même frame » contre le
# picking physique des Area2D (qui émet input_event AVANT _unhandled_input dans la même passe).
signal board_cleared

# Le développeur y glisse le nœud parent (Node2D) contenant ses 42 Area2D-territoires.
@export var territories_container: Node2D

# Palette par joueur (jusqu'à 6), teintes distinctes dans l'esprit wasteland. Sert de REPLI
# quand la faction du joueur n'a pas (encore) de ressource .tres avec accent_color.
const PALETTE := [
	Color("3fb7c9"),  # cyan tactique
	Color("c0654f"),  # rouille
	Color("5a8fd0"),  # acier bleu
	Color("e0b249"),  # or
	Color("9b6fd0"),  # améthyste
	Color("46b58a"),  # vert oxydé
]
# Palette DALTONIENNE (E10 §8.82) : Okabe-Ito, sûre pour deutan/protan/tritan. Quand le mode
# daltonien est actif, elle REMPLACE la palette de faction pour TOUS les joueurs — la bascule vit
# DANS get_player_color (source unique E1) → roster, VS, feed, badges suivent automatiquement.
const PALETTE_COLORBLIND := [
	Color("e69f00"),  # orange
	Color("56b4e9"),  # bleu ciel
	Color("009e73"),  # vert bleuté
	Color("f0e442"),  # jaune
	Color("cc79a7"),  # rose
	Color("0072b2"),  # bleu profond
]

# Visibilité Tactique (Partie 2) : badge de troupes + remplissage coloré des territoires.
const TerritoryBadgeScene := preload("res://scenes/game/territory_badge.tscn")
const FACTIONS_DIR := "res://resources/factions/"
# Opacité du remplissage du territoire (semi-transparent → on voit encore la carte de fond).
const FILL_ALPHA := 0.42
# Gris kaki pour un territoire neutre / sans propriétaire.
const NEUTRAL_COLOR := Color("8a97a5")

# Zone radioactive (§8.30) : shader de pulsation toxique appliqué en ShaderMaterial sur le
# remplissage d'un territoire contaminé, retiré dès qu'il sort de la zone.
const ToxicShader: Shader = preload("res://shaders/toxic_pulsation.gdshader")
const RAD_COLOR := Color("7fff00")    # vert nucléaire (miroir du défaut du shader)
const CONTAMINATED_ALPHA := 0.62      # opacité du remplissage contaminé (cf. fill_alpha shader)

# Hologramme Tactique (Concept A, Objectif 2) : contour néon + hachures diagonales défilantes
# appliqués sur les territoires POSSÉDÉS hors zone radioactive — on supprime ainsi le remplissage
# opaque uni qui rendait la carte illisible. Le shader écrase COLOR (cf. neon_hologram.gdshader) ;
# on lui passe l'accent du propriétaire ET les sommets du polygone (SDF du contour).
const HologramShader: Shader = preload("res://shaders/neon_hologram.gdshader")
const MAX_HOLO_POINTS := 64           # = MAX_POINTS du shader (au-delà, contour tronqué)
# Replis de remplissage STATIQUE (visibles seulement si un shader ne charge pas) : possédé = accent
# quasi transparent (plus de bloc uni), neutre = gris kaki très sombre (« vide »).
const HOLO_FALLBACK_ALPHA := 0.10
const NEUTRAL_FILL_COLOR := Color("0f1318")
const NEUTRAL_FILL_ALPHA := 0.22

# Mise en avant du JOUEUR LOCAL (perspective de CE client) : ses territoires doivent se distinguer
# d'un coup d'œil de ceux des adversaires. Deux leviers (couleur de faction CONSERVÉE, on ne joue
# que sur l'intensité) :
#   1) HOLOGRAMME renforcé — contour/halo/hachures plus marqués pour MOI, atténués pour les autres
#      (paramètres poussés au shader neon_hologram dans _apply_hologram_material) ;
#   2) RELIEF — une ombre portée (Polygon2D jumeau décalé, dessiné DERRIÈRE le remplissage) qui fait
#      « flotter » mes territoires au-dessus de la carte ; les territoires adverses restent à plat.
const OWN_FALLBACK_ALPHA := 0.18      # repli statique un peu plus dense pour MES territoires
# Décalage (px, espace local du board) + teinte de l'ombre portée des territoires possédés par MOI.
const OWN_RELIEF_OFFSET := Vector2(5, 8)
const OWN_RELIEF_COLOR := Color(0, 0, 0, 0.5)

var _selected_source: String = ""
var _owner_colors: Dictionary = {}
# Surlignage des cibles valides (E7 §8.79) : {tid: true} des cibles d'attaque légales, posé par
# main.gd à la sélection d'une source (Phase 3). Vide = aucun contexte d'attaque (rendu normal).
var _attack_targets: Dictionary = {}
# Flèche d'intention (E7) : Line2D pointillée animée source → territoire survolé (créée à la volée).
var _intent_arrow: Line2D = null
var _intent_target: String = ""
# id_territoire -> nœud visuel trouvé dans le conteneur.
var _nodes: Dictionary = {}
# faction_id (string) -> accent_color (Color), chargé une fois depuis resources/factions/*.tres.
var _faction_accents: Dictionary = {}
# id_territoire -> Polygon2D de remplissage (créé à la volée, enfant de l'Area2D).
var _fills: Dictionary = {}
# id_territoire -> Polygon2D d'ombre portée (relief) pour MES territoires (créé à la volée, dessiné
# DERRIÈRE le remplissage). Masqué dès que le territoire n'est plus à moi (cf. _apply/_clear_own_relief).
var _shadows: Dictionary = {}
# id_territoire -> instance de territory_badge.
var _badges: Dictionary = {}
# Calque (Node2D) accueillant les badges, dessiné par-dessus les territoires.
var _badge_layer: Node2D = null
# Déploiements EN ATTENTE (tampon local non confirmé piloté par main.gd, §8.26) : tid -> nb de
# troupes "+X". Affichés sur le badge/texte pour distinguer les troupes non encore validées.
var _pending: Dictionary = {}
# Frame du dernier clic ayant touché un territoire (picking Area2D) — garde anti-rebond pour
# distinguer un clic « dans le vide » (board_cleared) d'un clic sur un territoire (§1 Inspecteur).
var _pick_frame: int = -1

# --- Overlay « vraies frontieres » (§8.51) : colore/contoure les territoires d'apres la CARTE-ID
# (assets/images/territory_id_map.png, generee par tools/gen_territory_idmap.gd) AU LIEU des
# polygones-hitbox -> le rendu epouse les vraies cotes peintes. Voir territory_overlay.gdshader.
const ID_MAP_PATH := "res://assets/images/territory_id_map.png"
const ID_ORDER_PATH := "res://assets/images/territory_id_order.json"
const OverlayShader: Shader = preload("res://shaders/territory_overlay.gdshader")
const OVERLAY_CENTER := Vector2(1108, 757)   # centre du board_bg affiche en [8,2208]x[-8,1522]
var _overlay: Sprite2D = null
var _tid_index: Dictionary = {}              # tid -> index (1..N) dans la carte-ID

func _ready() -> void:
	# E1 §8.73 : le plateau s'enregistre pour les briques UI (player_chip) qui résolvent couleur
	# joueur / accent de faction via get_player_color / get_faction_accent — la palette reste
	# UNIQUE (piège n° 2 PLAN_EXPERIENCE : jamais de 2ᵉ table côté composants).
	add_to_group("game_board")
	_index_territory_nodes()
	_load_faction_accents()
	_setup_territory_overlay()
	# Mode daltonien (E10 §8.82) : au changement, on purge la table de couleurs (recalculée avec
	# la palette Okabe-Ito) et on redessine — toute l'UI suit via get_player_color.
	if not SettingsManager.comfort_changed.is_connected(_on_comfort_changed):
		SettingsManager.comfort_changed.connect(_on_comfort_changed)

func _on_comfort_changed(key: String, _value) -> void:
	# colorblind → palette + motifs ; reduced_motion → motion_scale du shader. Les deux exigent
	# un redraw (couleurs/motifs recalculés, uniformes repoussés).
	if key == "colorblind_mode" or key == "reduced_motion":
		_owner_colors.clear()
		generate_board()

# Construit l'overlay des territoires (§8.51) : un Sprite2D portant la CARTE-ID, recouvrant
# EXACTEMENT le board_bg, avec territory_overlay.gdshader. Texture chargee BRUTE (index exacts,
# filtre NEAREST) ; l'ordre des index vient du JSON jumeau. Ajoute au-dessus du fond et SOUS les
# badges (crees plus tard). Sans la carte-ID/JSON, l'overlay reste absent (repli : aucun coloriage).
func _setup_territory_overlay() -> void:
	var f := FileAccess.open(ID_ORDER_PATH, FileAccess.READ)
	if f == null:
		push_warning("board.gd : territory_id_order.json absent — overlay desactive.")
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("order"):
		return
	var order: Array = data["order"]
	for i in range(order.size()):
		_tid_index[str(order[i])] = i + 1
	var tex := load(ID_MAP_PATH) as Texture2D
	if tex == null:
		push_warning("board.gd : territory_id_map.png absent — overlay desactive.")
		return
	var idtex := ImageTexture.create_from_image(tex.get_image())
	_overlay = Sprite2D.new()
	_overlay.name = "TerritoryOverlay"
	_overlay.texture = idtex
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.position = OVERLAY_CENTER
	var mat := ShaderMaterial.new()
	mat.shader = OverlayShader
	mat.set_shader_parameter("id_map", idtex)
	_overlay.material = mat
	add_child(_overlay)

# Charge la couleur d'accent de chaque faction depuis ses ressources data-driven (.tres).
# Même pattern robuste que faction_selection.gd : scan du dossier, export-safe (.remap),
# duck-typing (on n'exige pas le type global FactionData). 7/10 factions n'ont pas encore de
# .tres → ces joueurs retombent sur la PALETTE par index (voir _build_owner_colors).
func _load_faction_accents() -> void:
	_faction_accents.clear()
	var dir := DirAccess.open(FACTIONS_DIR)
	if dir == null:
		return
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
					if res != null and res.get("id") != null:
						var accent = res.get("accent_color")
						if accent is Color:
							_faction_accents[str(res.get("id"))] = accent
		file_name = dir.get_next()
	dir.list_dir_end()

# Parcourt les enfants du conteneur, valide le nom contre MapData et câble les clics.
func _index_territory_nodes() -> void:
	_nodes.clear()
	if territories_container == null:
		push_warning("board.gd : 'territories_container' non assigné — placez vos 42 territoires dans l'éditeur et glissez le conteneur.")
		return
	for territory_node in territories_container.get_children():
		var t_id := String(territory_node.name).to_lower()
		if not MapData.TERRITORIES.has(t_id):
			push_warning("board.gd : nœud '%s' sans correspondance dans MapData.TERRITORIES (ignoré)." % territory_node.name)
			continue
		_nodes[t_id] = territory_node
		_wire_click(territory_node, t_id)

# Câble le clic d'un nœud-territoire vers `territory_clicked`, selon son type.
# Area2D (cas nominal) : signal `input_event` — on filtrera le clic gauche dans le handler.
# BaseButton (fallback) : signal `pressed`, déjà filtré par le moteur.
func _wire_click(node: Node, t_id: String) -> void:
	if node.has_signal("input_event"):
		_warn_if_area_not_clickable(node)
		var cb := _on_area_input_event.bind(t_id)
		if not node.input_event.is_connected(cb):
			node.input_event.connect(cb)
		# Survol (G4 §8.63) : relaie l'entrée/sortie de souris (prévision de combat).
		var cb_in := _on_area_mouse_entered.bind(t_id)
		if not node.mouse_entered.is_connected(cb_in):
			node.mouse_entered.connect(cb_in)
		var cb_out := _on_area_mouse_exited.bind(t_id)
		if not node.mouse_exited.is_connected(cb_out):
			node.mouse_exited.connect(cb_out)
	elif node.has_signal("pressed"):
		var cb_btn := _on_pressed.bind(t_id)
		if not node.pressed.is_connected(cb_btn):
			node.pressed.connect(cb_btn)
	else:
		push_warning("board.gd : nœud '%s' ni Area2D ni BaseButton — clic non câblé." % node.name)

# Diagnostic (level design manuel) : un Area2D ne reçoit `input_event` QUE s'il est
# `input_pickable` ET possède au moins une forme de collision. Oublier l'un ou l'autre rend le
# territoire silencieusement non cliquable (aucune erreur) — on prévient plutôt que de laisser
# deviner. N'altère rien : se contente de logguer un avertissement en build debug.
func _warn_if_area_not_clickable(node: Node) -> void:
	if "input_pickable" in node and not node.input_pickable:
		push_warning("board.gd : Area2D '%s' a input_pickable=false → clics ignorés." % node.name)
	for child in node.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			return
	push_warning("board.gd : Area2D '%s' sans CollisionShape2D/CollisionPolygon2D → clics ignorés." % node.name)

func set_selected_source(tid: String) -> void:
	_selected_source = tid
	generate_board()

# Contexte d'attaque (E7 §8.79) : main.gd calcule les cibles légales à la sélection d'une source
# (Phase 3) → liseré cramoisi pulsant sur les cibles + désaturation des autres (via l'overlay).
func set_attack_context(source_tid: String, valid_targets: Array) -> void:
	_attack_targets = {}
	for tid in valid_targets:
		_attack_targets[str(tid)] = true
	generate_board()

func clear_attack_context() -> void:
	if _attack_targets.is_empty() and _intent_target == "":
		return
	_attack_targets = {}
	clear_intent_arrow()
	generate_board()

# Flèche d'intention pointillée (E7) : source → territoire survolé. Recréée si la cible change.
func set_intent_arrow(target_tid: String) -> void:
	if _selected_source == "" or target_tid == _selected_source:
		clear_intent_arrow()
		return
	var from := get_territory_position(_selected_source)
	var to := get_territory_position(target_tid)
	if from == Vector2.INF or to == Vector2.INF:
		clear_intent_arrow()
		return
	_intent_target = target_tid
	if _intent_arrow == null or not is_instance_valid(_intent_arrow):
		_intent_arrow = Line2D.new()
		_intent_arrow.width = 5.0
		_intent_arrow.default_color = Color(0.85, 0.15, 0.15, 0.85)
		_intent_arrow.z_index = 50
		_intent_arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_intent_arrow.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(_intent_arrow)
	_intent_arrow.visible = true
	# Trait principal + tête de flèche (deux segments obliques) — pointillé simulé par segments.
	var dir := (to - from).normalized()
	var head := to - dir * 46.0
	var perp := dir.orthogonal()
	_intent_arrow.points = PackedVector2Array([from, head])
	if _intent_head == null or not is_instance_valid(_intent_head):
		_intent_head = Line2D.new()
		_intent_head.width = 5.0
		_intent_head.default_color = Color(0.85, 0.15, 0.15, 0.95)
		_intent_head.z_index = 50
		add_child(_intent_head)
	_intent_head.visible = true
	_intent_head.points = PackedVector2Array([
		head + perp * 22.0 - dir * 4.0, to, head - perp * 22.0 - dir * 4.0])

var _intent_head: Line2D = null

func clear_intent_arrow() -> void:
	_intent_target = ""
	if _intent_arrow != null and is_instance_valid(_intent_arrow):
		_intent_arrow.visible = false
	if _intent_head != null and is_instance_valid(_intent_head):
		_intent_head.visible = false

# Couleur d'un joueur telle qu'utilisée sur le plateau (accent de faction, sinon PALETTE par
# index, gris si inconnu). Exposé pour que le HUD colore le pseudo du joueur de façon COHÉRENTE
# avec ses territoires (CONTEXTE.md §8.23). Reconstruit la table si elle n'a pas encore été bâtie.
func get_player_color(pid: int) -> Color:
	if _owner_colors.is_empty():
		_build_owner_colors()
	return _owner_colors.get(pid, NEUTRAL_COLOR)

# Accent d'une faction (accent_color de son .tres) — NEUTRAL_COLOR si inconnue / sans ressource.
# Exposé pour la brique identité player_chip (E1 §8.73) : la table des accents chargée ici reste
# la SEULE source (aucun doublon de scan côté UI).
func get_faction_accent(faction_id: String) -> Color:
	return _faction_accents.get(faction_id, NEUTRAL_COLOR)

# Id du joueur LOCAL (la perspective de CE client) — ses territoires sont mis en avant (hologramme
# vif + relief) pour les distinguer des adversaires. Même source que main._my_id() / le HUD :
# AuthManager.user_id. board reste une Vue, il ne fait que REFLÉTER cette perspective (pas de logique
# de jeu). Vaut -1 tant que l'id n'est pas chargé → aucun territoire « à moi » (repli sûr).
func _local_pid() -> int:
	return AuthManager.user_id

# Ensemble des territoires contaminés (modèle CLUSTER §8.27 : clé "territories" = liste). Renvoie
# un Dictionary {tid: true} pour un test d'appartenance O(1) dans generate_board. Rétro-compatible
# avec l'ancien modèle « position unique ».
func _contaminated_set() -> Dictionary:
	var out: Dictionary = {}
	var zone = GameState.contamination_zone
	if typeof(zone) != TYPE_DICTIONARY:
		return out
	if zone.has("territories") and typeof(zone["territories"]) == TYPE_ARRAY:
		for tid in zone["territories"]:
			out[str(tid)] = true
	elif zone.has("position"):  # rétro-compatibilité ancien modèle
		out[str(zone["position"])] = true
	return out

# TÉLÉGRAPHE (G1 §8.62) : ensemble {tid: true} des territoires ANNONCÉS pour la PROCHAINE zone
# (contamination_zone.next_territories, pré-tiré par le serveur un round à l'avance). Même contrat
# que _contaminated_set ; clé absente (serveur antérieur / état legacy) → ensemble vide, aucun crash.
func _forecast_set() -> Dictionary:
	var out: Dictionary = {}
	var zone = GameState.contamination_zone
	if typeof(zone) != TYPE_DICTIONARY:
		return out
	if zone.has("next_territories") and typeof(zone["next_territories"]) == TYPE_ARRAY:
		for tid in zone["next_territories"]:
			out[str(tid)] = true
	return out

# Pousse le tampon de déploiement local (main.gd, §8.26) sur le plateau et redessine. Un dict
# vide efface tous les "+X". Appelé pendant les phases de placement / renforts.
func set_pending_deployments(pending: Dictionary) -> void:
	_pending = pending.duplicate() if pending != null else {}
	generate_board()

# Construit la table propriétaire -> couleur. Priorité à l'accent_color de la FACTION du
# joueur (via FactionData), sinon repli sur la PALETTE par index (ordre stable des ids).
# Mode DALTONIEN (E10 §8.82) : la palette Okabe-Ito par INDEX remplace TOUT (y compris les accents
# de faction) → distinction garantie des 6 factions ; les motifs (shader) renforcent la couleur.
func _build_owner_colors() -> void:
	var pids: Array = []
	for k in GameState.players.keys():
		pids.append(int(k))
	pids.sort()
	_owner_colors.clear()
	var colorblind: bool = bool(SettingsManager.get_comfort("colorblind_mode"))
	for i in range(pids.size()):
		var pid: int = pids[i]
		var col: Color
		if colorblind:
			col = PALETTE_COLORBLIND[i % PALETTE_COLORBLIND.size()]
		else:
			col = PALETTE[i % PALETTE.size()]
			var pdata = GameState.players.get(str(pid), {})
			if typeof(pdata) == TYPE_DICTIONARY:
				var fid := str(pdata.get("faction", ""))
				if _faction_accents.has(fid):
					col = _faction_accents[fid]
		_owner_colors[pid] = col

# Index de PALETTE d'un joueur (0..5, ordre stable des ids) — sert au motif daltonien (pattern_id
# par index de joueur, E10 §8.82).
func _player_palette_index(pid: int) -> int:
	var pids: Array = []
	for k in GameState.players.keys():
		pids.append(int(k))
	pids.sort()
	var idx := pids.find(pid)
	return idx if idx >= 0 else 0

# Rafraîchit l'apparence de chaque nœud-territoire à partir de l'état courant (GameState) :
# remplissage semi-transparent à la couleur de faction du propriétaire (gris si neutre),
# badge de troupes au centre, surbrillance = sélection, ☢ = contamination.
func generate_board() -> void:
	_build_owner_colors()
	var contaminated := _contaminated_set()
	var forecast := _forecast_set()
	# Carte réduite (G5 §8.71) : territoires de LA CARTE JOUÉE — les nœuds hors carte sont
	# masqués/désactivés plus bas ; le rect englobant des actifs recadre la caméra tactique.
	var map_terrs: Dictionary = MapData.map_territories(GameState.map_id)
	var partial_map: bool = map_terrs.size() < _nodes.size()
	var active_rect := Rect2()
	var have_rect := false

	# Tableaux pousses a l'overlay (§8.51), indexes par la carte-ID : couleur+alpha de remplissage
	# et alpha de contour. Initialises transparents -> les territoires neutres restent invisibles.
	var ov_colors := PackedColorArray()
	ov_colors.resize(42)
	for i in range(42):
		ov_colors[i] = Color(0, 0, 0, 0)
	var ov_edges := PackedFloat32Array()
	ov_edges.resize(42)
	# 1 = territoire du JOUEUR LOCAL -> porte une ombre de relief (§8.52, via l'overlay).
	var ov_mine := PackedFloat32Array()
	ov_mine.resize(42)
	# 1 = territoire ANNONCÉ pour la prochaine zone -> liseré or pulsant (télégraphe G1 §8.62).
	var ov_forecast := PackedFloat32Array()
	ov_forecast.resize(42)
	# 1 = cible d'attaque valide -> liseré cramoisi pulsant (E7 §8.79).
	var ov_attack := PackedFloat32Array()
	ov_attack.resize(42)
	# Motif daltonien par index de joueur (E10 §8.82) : 0 = aucun (mode normal), 1..6 sinon.
	var ov_pattern := PackedFloat32Array()
	ov_pattern.resize(42)
	var colorblind: bool = bool(SettingsManager.get_comfort("colorblind_mode"))

	for tid in _nodes:
		var node = _nodes[tid]
		# Hors carte (G5) : nœud invisible + non cliquable + badge masqué, rien d'autre à faire
		# (l'overlay reste transparent : le territoire n'existe pas dans GameState.territories).
		var in_map: bool = map_terrs.has(tid)
		if "visible" in node:
			node.visible = in_map
		if "input_pickable" in node:
			node.input_pickable = in_map
		if not in_map:
			var stale = _badges.get(tid)
			if stale != null and is_instance_valid(stale):
				stale.visible = false
			continue
		# Rect englobant des territoires ACTIFS (recadrage caméra, seulement en carte partielle).
		if partial_map:
			var node_rect := _node_world_rect(node)
			if node_rect.size != Vector2.ZERO:
				active_rect = node_rect if not have_rect else active_rect.merge(node_rect)
				have_rect = true
		var t: Dictionary = GameState.territories.get(tid, {})
		var territory_owner = t.get("owner_id")
		var garrison := int(t.get("garrison", 0))
		# Troupes en attente de confirmation sur ce territoire (tampon local, §8.26).
		var pending := int(_pending.get(tid, 0))

		# Couleur d'accent du propriétaire (gris kaki si le territoire est neutre / vide).
		var accent: Color = NEUTRAL_COLOR
		if territory_owner != null and _owner_colors.has(int(territory_owner)):
			accent = _owner_colors[int(territory_owner)]

		# Territoire du JOUEUR LOCAL ? Ses possessions sont mises en avant (hologramme renforcé +
		# relief) pour se distinguer d'un coup d'œil de celles des adversaires (atténuées, à plat).
		var is_mine: bool = territory_owner != null and int(territory_owner) == _local_pid()

		# Couleur de remplissage du polygone (avec surbrillance de sélection et teinte de zone).
		# Type explicite : `tid` (clé de Dictionary) est un Variant → l'inférence `:=` échoue.
		var is_contaminated: bool = contaminated.has(tid)
		# Territoire annoncé pour la PROCHAINE zone (télégraphe G1 §8.62 — liseré or + badge ⚠).
		var is_forecast: bool = forecast.has(tid)
		var fill_col: Color
		var fill_alpha: float
		if territory_owner != null:
			fill_col = accent
			if tid == _selected_source:
				fill_col = fill_col.lightened(0.35)
			fill_alpha = OWN_FALLBACK_ALPHA if is_mine else HOLO_FALLBACK_ALPHA
		else:
			# Territoire NEUTRE : pas d'hologramme → gris kaki très sombre (« vide »).
			fill_col = NEUTRAL_FILL_COLOR
			fill_alpha = NEUTRAL_FILL_ALPHA
		if is_contaminated:
			# Zone radioactive : superposition vert fluo nettement plus marquée ET plus opaque
			# que le remplissage normal → le territoire contaminé saute aux yeux (bug playtest).
			fill_col = fill_col.lerp(Color("7fff00"), 0.7)
			fill_alpha = 0.62

		# Overlay « vraies frontieres » (§8.51) : on POUSSE la couleur+alpha de remplissage calcules
		# ci-dessus dans la carte-ID (territory_overlay.gdshader), plus un alpha de CONTOUR neon (mes
		# territoires vifs, adverses attenues, contamines marques). Remplace les fills/hologramme/relief
		# qui suivaient le POLYGONE -> desormais le rendu epouse les VRAIES cotes peintes.
		var edge_a := 0.0
		if is_contaminated:
			edge_a = 0.9
		elif territory_owner != null:
			edge_a = 0.95 if is_mine else 0.55
			if tid == _selected_source:
				edge_a = 1.0
		if _tid_index.has(tid):
			var oi: int = int(_tid_index[tid]) - 1
			if oi >= 0 and oi < ov_colors.size():
				ov_colors[oi] = Color(fill_col.r, fill_col.g, fill_col.b, fill_alpha)
				ov_edges[oi] = edge_a
				ov_mine[oi] = 1.0 if is_mine else 0.0
				ov_forecast[oi] = 1.0 if is_forecast else 0.0
				ov_attack[oi] = 1.0 if _attack_targets.has(tid) else 0.0
				# Motif daltonien (E10) : index de joueur +1 (1..6) sur les territoires possédés.
				if colorblind and territory_owner != null:
					ov_pattern[oi] = float(_player_palette_index(int(territory_owner)) % 6 + 1)

		# Badge de troupes : bordure à l'accent du propriétaire, nombre d'unités au centre,
		# alerte ☢ si contaminé, "+X" doré pour les troupes en attente, ⚠ or si le territoire
		# est annoncé pour la prochaine zone (télégraphe G1 §8.62). Mode daltonien (E10) :
		# initiale du pseudo du propriétaire en redondance texte.
		var initial := ""
		if colorblind and territory_owner != null:
			initial = _owner_initial(int(territory_owner))
		_update_badge(tid, garrison, accent, is_contaminated, pending, is_forecast, initial)

		# Libellé/garnison : on n'écrase un texte que si le nœud expose la propriété `text`
		# (cas fallback BaseButton ; les Area2D dessinés à la main n'ont pas de `text`).
		if "text" in node:
			var prefix := ""
			if tid == _selected_source:
				prefix = "▶ "
			if is_contaminated:
				prefix = "☢ " + prefix
			var troop_str := str(garrison)
			if pending > 0:
				troop_str = "%d+%d" % [garrison, pending]
			node.text = "%s%s\n%s" % [prefix, MapData.TERRITORIES[tid]["name"], troop_str]

	# Pousse couleurs + contours a l'overlay (un seul set par rafraichissement).
	if _overlay != null and _overlay.material is ShaderMaterial:
		var m := _overlay.material as ShaderMaterial
		m.set_shader_parameter("territory_colors", ov_colors)
		m.set_shader_parameter("territory_edge", ov_edges)
		m.set_shader_parameter("territory_mine", ov_mine)
		m.set_shader_parameter("territory_forecast", ov_forecast)
		m.set_shader_parameter("territory_attack", ov_attack)
		# attack_dim > 0 dès qu'une source a des cibles surlignées → désaturation des autres (E7).
		m.set_shader_parameter("attack_dim", 1.0 if not _attack_targets.is_empty() else 0.0)
		m.set_shader_parameter("territory_pattern", ov_pattern)  # motifs daltoniens (E10)
		# reduced_motion (E10) : fige les pulsations du plateau (télégraphe/attaque).
		m.set_shader_parameter("motion_scale",
			0.0 if bool(SettingsManager.get_comfort("reduced_motion")) else 1.0)

	# Cadre actif (G5) : mémorisé pour la caméra — Rect2() vide sur la carte COMPLÈTE (le
	# cadrage historique plein plateau est alors conservé, non-régression classic).
	_active_rect = active_rect if (partial_map and have_rect) else Rect2()

# Rect englobant MONDE d'un territoire actif (rect caméra G5) — Rect2() vide si aucun polygone.
func _node_world_rect(node: Node) -> Rect2:
	for child in node.get_children():
		if child is CollisionPolygon2D and child.polygon.size() > 0:
			var xform: Transform2D = child.global_transform
			var rect := Rect2(xform * child.polygon[0], Vector2.ZERO)
			for p in child.polygon:
				rect = rect.expand(xform * p)
			return rect
	if node is Node2D:
		return Rect2(node.global_position, Vector2.ZERO)
	return Rect2()

# Rect englobant des territoires de la carte ACTIVE (G5 §8.71) — vide = carte complète (le
# consommateur, la caméra tactique, garde alors sa vue plein plateau historique).
var _active_rect := Rect2()

func get_active_map_rect() -> Rect2:
	return _active_rect

# Crée (une fois) puis renvoie le Polygon2D de remplissage d'un territoire, construit à partir
# de son CollisionPolygon2D (mêmes points, transformés dans l'espace local de l'Area2D).
# Renvoie null si le nœud n'a pas de polygone exploitable (cas fallback BaseButton).
func _ensure_fill(tid: String, node: Node) -> Polygon2D:
	if _fills.has(tid) and is_instance_valid(_fills[tid]):
		return _fills[tid]
	var cpoly: CollisionPolygon2D = null
	for child in node.get_children():
		if child is CollisionPolygon2D and child.polygon.size() >= 3:
			cpoly = child
			break
	if cpoly == null:
		return null
	var pts := PackedVector2Array()
	for p in cpoly.polygon:
		pts.append(cpoly.transform * p)
	var fill := Polygon2D.new()
	fill.polygon = pts
	# Enfant de l'Area2D (dans TerritoriesContainer, rendu APRÈS le BoardBackground → par-dessus
	# la carte). Polygon2D n'a pas de picking → n'intercepte pas les clics (picking sur l'Area2D).
	node.add_child(fill)
	_fills[tid] = fill
	return fill

# Applique (ou met à jour) le ShaderMaterial de pulsation toxique (§8.30) sur le remplissage
# d'un territoire contaminé. Réutilise le matériau déjà présent pour ne pas en recréer un à
# chaque rafraîchissement ; lui passe l'accent du propriétaire (le shader pulse vers le vert
# nucléaire). Voir toxic_pulsation.gdshader.
func _apply_toxic_material(fill: Polygon2D, base_accent: Color) -> void:
	var mat := fill.material as ShaderMaterial
	# Recrée le matériau si absent OU s'il portait un AUTRE shader (ex. l'hologramme d'un territoire
	# qui vient d'ENTRER dans la zone) — sinon on pousserait des paramètres toxiques sur l'hologramme.
	if mat == null or mat.shader != ToxicShader:
		mat = ShaderMaterial.new()
		mat.shader = ToxicShader
		fill.material = mat
	mat.set_shader_parameter("base_color", base_accent)
	mat.set_shader_parameter("rad_color", RAD_COLOR)
	mat.set_shader_parameter("fill_alpha", CONTAMINATED_ALPHA)

# Applique (ou met à jour) le ShaderMaterial « Hologramme Tactique » (Concept A) sur le remplissage
# d'un territoire POSSÉDÉ hors zone : contour néon + hachures diagonales défilantes, intérieur quasi
# transparent. Réutilise le matériau s'il porte déjà ce shader (sinon le recrée — le territoire
# sortait peut-être de la zone radioactive). On lui transmet l'accent du propriétaire ET les sommets
# du polygone (espace local du Polygon2D) pour le SDF du contour. Voir neon_hologram.gdshader.
#
# `emphasized` (territoire du JOUEUR LOCAL) renforce contour + halo + hachures pour faire RESSORTIR
# mes possessions ; à false (adversaire) on atténue ces mêmes paramètres → la carte se lit « les
# miens brillent, les leurs sont en sourdine ». La couleur de faction reste INCHANGÉE dans les deux
# cas (on ne joue que sur l'intensité, pour préserver l'identité visuelle des factions).
func _apply_hologram_material(fill: Polygon2D, accent: Color, emphasized: bool = false) -> void:
	var mat := fill.material as ShaderMaterial
	if mat == null or mat.shader != HologramShader:
		mat = ShaderMaterial.new()
		mat.shader = HologramShader
		fill.material = mat
	mat.set_shader_parameter("accent_color", accent)
	# Intensité de l'hologramme selon l'appartenance (mes territoires = vifs, adverses = atténués).
	mat.set_shader_parameter("neon_width", 10.0 if emphasized else 5.0)
	mat.set_shader_parameter("glow_width", 52.0 if emphasized else 26.0)
	mat.set_shader_parameter("glow_strength", 0.5 if emphasized else 0.16)
	mat.set_shader_parameter("neon_boost", 2.4 if emphasized else 1.5)
	mat.set_shader_parameter("hatch_alpha", 0.24 if emphasized else 0.09)
	var pts := fill.polygon
	if pts.size() > MAX_HOLO_POINTS:
		push_warning("board.gd : territoire à %d sommets > %d — contour néon tronqué." % [pts.size(), MAX_HOLO_POINTS])
		pts = pts.slice(0, MAX_HOLO_POINTS)
	mat.set_shader_parameter("edge_points", pts)
	mat.set_shader_parameter("point_count", pts.size())

# Crée (ou réactive) l'ombre portée de relief d'un territoire possédé par le JOUEUR LOCAL : un
# Polygon2D jumeau du remplissage, décalé de OWN_RELIEF_OFFSET et dessiné DERRIÈRE lui (déplacé en
# 1er enfant de l'Area2D) → le territoire paraît soulevé au-dessus de la carte. Réutilisé d'un
# rafraîchissement à l'autre (on ne le recrée pas), simplement masqué quand il n'est plus à moi.
func _apply_own_relief(tid: String, node: Node, fill: Polygon2D) -> void:
	var shadow = _shadows.get(tid)
	if shadow == null or not is_instance_valid(shadow):
		shadow = Polygon2D.new()
		shadow.name = "OwnRelief"
		node.add_child(shadow)
		node.move_child(shadow, 0)  # dessiné AVANT le remplissage → derrière lui
		_shadows[tid] = shadow
	shadow.polygon = fill.polygon
	shadow.position = OWN_RELIEF_OFFSET
	shadow.color = OWN_RELIEF_COLOR
	shadow.visible = true

# Masque l'ombre de relief d'un territoire qui n'appartient plus au JOUEUR LOCAL (adverse / neutre /
# perdu). On la conserve masquée plutôt que de la libérer : elle resservira si le territoire revient.
func _clear_own_relief(tid: String) -> void:
	var shadow = _shadows.get(tid)
	if shadow != null and is_instance_valid(shadow):
		shadow.visible = false

# Crée ou met à jour le badge de troupes d'un territoire, positionné en son centre.
# `contaminated` (défaut false) pilote l'alerte ☢ ; `forecast` (défaut false) le ⚠ or du
# télégraphe (G1 §8.62) ; repassés à chaque rafraîchissement → un territoire qui quitte la zone
# (ou n'est plus annoncé) est automatiquement réinitialisé (☢/⚠ retirés).
# Initiale (majuscule) du pseudo d'un joueur pour la redondance texte du badge daltonien (E10).
func _owner_initial(pid: int) -> String:
	var p = GameState.players.get(str(pid), {})
	if typeof(p) == TYPE_DICTIONARY:
		var uname := str(p.get("username", ""))
		if uname != "":
			return uname.substr(0, 1).to_upper()
	return str(pid) if pid >= 0 else "IA"

func _update_badge(tid: String, troops: int, accent: Color, contaminated: bool = false,
		pending: int = 0, forecast: bool = false, initial: String = "") -> void:
	var pos := get_territory_position(tid)
	if pos == Vector2.INF:
		return
	if _badge_layer == null or not is_instance_valid(_badge_layer):
		_badge_layer = Node2D.new()
		_badge_layer.name = "BadgeLayer"
		add_child(_badge_layer)
	var badge = _badges.get(tid)
	if badge == null or not is_instance_valid(badge):
		badge = TerritoryBadgeScene.instantiate()
		_badge_layer.add_child(badge)
		_badges[tid] = badge
	# Ré-affiche un badge masqué par un passage hors-carte (changement de carte, G5 §8.71).
	badge.visible = true
	badge.global_position = pos
	badge.set_data(troops, accent, contaminated, pending, forecast, initial)

# Position monde (espace du SubViewport) du centre d'un territoire — utilisée par la
# caméra tactique pour cadrer les combats. Centre = centroïde du CollisionPolygon2D si
# présent, sinon position du nœud. Vector2.INF si le territoire est inconnu.
func get_territory_position(tid: String) -> Vector2:
	var node = _nodes.get(tid)
	if node == null:
		return Vector2.INF
	for child in node.get_children():
		if child is CollisionPolygon2D and child.polygon.size() > 0:
			var centroid := Vector2.ZERO
			for p in child.polygon:
				centroid += p
			return child.global_transform * (centroid / child.polygon.size())
	if node is Node2D:
		return node.global_position
	return Vector2.INF

func _on_pressed(tid: String) -> void:
	territory_clicked.emit(tid)

# Survol d'un territoire (G4 §8.63) : simple relais de signal (aucune logique de jeu, §6.1).
func _on_area_mouse_entered(tid: String) -> void:
	territory_hovered.emit(tid)

func _on_area_mouse_exited(tid: String) -> void:
	territory_unhovered.emit(tid)

# Handler des Area2D : clic GAUCHE enfoncé → territory_clicked ; clic DROIT enfoncé →
# territory_right_clicked (retrait d'une troupe en attente, §8.26). Les autres évènements
# input_event (survol, relâche) sont ignorés.
func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int, tid: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		_pick_frame = Engine.get_process_frames()
		if event.button_index == MOUSE_BUTTON_LEFT:
			territory_clicked.emit(tid)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			territory_right_clicked.emit(tid)

# Clic GAUCHE « dans le vide » : si aucun Area2D n'a capté ce clic CETTE frame, on referme
# l'Inspecteur Tactique (§1). Le picking physique stampe _pick_frame juste avant ; si la frame
# courante diffère, c'est que le clic n'a touché aucun territoire. (Le bouton ✕ de l'Inspecteur
# reste le repli garanti si l'ordre picking/_unhandled_input variait.)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Engine.get_process_frames() != _pick_frame:
			board_cleared.emit()

# Vrai si le territoire est dans la zone de contamination courante (§1 Inspecteur Tactique).
# Wrapper public sur _contaminated_set (modèle cluster §8.27).
func is_contaminated(tid: String) -> bool:
	return _contaminated_set().has(tid)

# Flash radial de CONQUÊTE (E9 §8.81) : halo 0,5 s à la teinte accent du conquérant sur le
# territoire pris (shader conquest_flash confiné au Polygon2D de remplissage — pattern §8.30).
const ConquestFlashShader: Shader = preload("res://shaders/conquest_flash.gdshader")

func conquest_flash(tid: String, accent: Color) -> void:
	var node = _nodes.get(tid)
	if node == null:
		return
	var fill := _ensure_fill(tid, node)
	if fill == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = ConquestFlashShader
	mat.set_shader_parameter("flash_color", Color(accent.r, accent.g, accent.b, 0.85))
	mat.set_shader_parameter("progress", 0.0)
	fill.material = mat
	fill.color = Color(accent.r, accent.g, accent.b, 0.0)
	fill.visible = true
	var tw := fill.create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.5)
	tw.tween_callback(func() -> void:
		fill.material = null
		fill.visible = false)

# Flotteur « tic de zone » (E9 §8.81) : « -1 » vert toxique sur un territoire touché par la
# contamination. Réutilise le calque de badges (BadgeLayer) posé sur le plateau.
func spawn_zone_tick(tid: String) -> void:
	# Réglage damage_numbers (E10 §8.82) : les flotteurs de dégâts (zone comprise) sont masquables.
	if not bool(SettingsManager.get_comfort("damage_numbers")):
		return
	var pos := get_territory_position(tid)
	if pos == Vector2.INF:
		return
	if _badge_layer == null or not is_instance_valid(_badge_layer):
		_badge_layer = Node2D.new()
		_badge_layer.name = "BadgeLayer"
		add_child(_badge_layer)
	var lbl := Label.new()
	lbl.text = "-1"
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color("7fff00"))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_badge_layer.add_child(lbl)
	lbl.global_position = pos + Vector2(-14, -60)
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 60.0, 1.1)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(lbl.queue_free)

# Flash bref d'un territoire (E4 §8.76 — clic d'une entrée du Journal de Guerre) : teinte accent
# du propriétaire, 0,4 s. Réutilise le Polygon2D de remplissage legacy (_ensure_fill — inutilisé
# depuis l'overlay « vraies frontières » §8.51) comme calque de flash ponctuel.
func flash_territory(tid: String) -> void:
	var node = _nodes.get(tid)
	if node == null:
		return
	var fill := _ensure_fill(tid, node)
	if fill == null:
		return
	var accent: Color = NEUTRAL_COLOR
	var t: Dictionary = GameState.territories.get(tid, {})
	var o = t.get("owner_id")
	if o != null:
		accent = get_player_color(int(o))
	fill.material = null
	fill.color = Color(accent.r, accent.g, accent.b, 0.55)
	fill.visible = true
	var tw := fill.create_tween()
	tw.tween_property(fill, "color:a", 0.0, 0.4)
	tw.tween_callback(func() -> void: fill.visible = false)
