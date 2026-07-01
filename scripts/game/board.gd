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
	_index_territory_nodes()
	_load_faction_accents()
	_setup_territory_overlay()

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

# Couleur d'un joueur telle qu'utilisée sur le plateau (accent de faction, sinon PALETTE par
# index, gris si inconnu). Exposé pour que le HUD colore le pseudo du joueur de façon COHÉRENTE
# avec ses territoires (CONTEXTE.md §8.23). Reconstruit la table si elle n'a pas encore été bâtie.
func get_player_color(pid: int) -> Color:
	if _owner_colors.is_empty():
		_build_owner_colors()
	return _owner_colors.get(pid, NEUTRAL_COLOR)

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

# Pousse le tampon de déploiement local (main.gd, §8.26) sur le plateau et redessine. Un dict
# vide efface tous les "+X". Appelé pendant les phases de placement / renforts.
func set_pending_deployments(pending: Dictionary) -> void:
	_pending = pending.duplicate() if pending != null else {}
	generate_board()

# Construit la table propriétaire -> couleur. Priorité à l'accent_color de la FACTION du
# joueur (via FactionData), sinon repli sur la PALETTE par index (ordre stable des ids).
func _build_owner_colors() -> void:
	var pids: Array = []
	for k in GameState.players.keys():
		pids.append(int(k))
	pids.sort()
	_owner_colors.clear()
	for i in range(pids.size()):
		var pid: int = pids[i]
		var col: Color = PALETTE[i % PALETTE.size()]
		var pdata = GameState.players.get(str(pid), {})
		if typeof(pdata) == TYPE_DICTIONARY:
			var fid := str(pdata.get("faction", ""))
			if _faction_accents.has(fid):
				col = _faction_accents[fid]
		_owner_colors[pid] = col

# Rafraîchit l'apparence de chaque nœud-territoire à partir de l'état courant (GameState) :
# remplissage semi-transparent à la couleur de faction du propriétaire (gris si neutre),
# badge de troupes au centre, surbrillance = sélection, ☢ = contamination.
func generate_board() -> void:
	_build_owner_colors()
	var contaminated := _contaminated_set()

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

	for tid in _nodes:
		var node = _nodes[tid]
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

		# Badge de troupes : bordure à l'accent du propriétaire, nombre d'unités au centre,
		# alerte ☢ si contaminé, et "+X" doré pour les troupes en attente de confirmation.
		_update_badge(tid, garrison, accent, is_contaminated, pending)

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
# `contaminated` (défaut false) pilote l'alerte ☢ ; repassé à chaque rafraîchissement → un
# territoire qui quitte la zone est automatiquement réinitialisé (☢ retiré).
func _update_badge(tid: String, troops: int, accent: Color, contaminated: bool = false, pending: int = 0) -> void:
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
	badge.global_position = pos
	badge.set_data(troops, accent, contaminated, pending)

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
