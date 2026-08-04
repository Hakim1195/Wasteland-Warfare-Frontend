extends Node3D
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — LE BLOCKOUT : l'arène 3D en volumes gris, SOURCE DE VÉRITÉ géométrique.
#
# Une scène à DEUX MÉTIERS (§4.1), et c'est délibéré :
#   1. OUTIL DE CALIBRATION — `tools/gen_trench_angles.gd` l'instancie pour projeter la table
#      angulaire, `tools/gen_trench_renders.gd` la photographie pour l'img2img du LOT E ;
#   2. SCÈNE DE PRODUCTION — le `SubViewport` 3D de `trench_fp.gd` l'instancie pour ses REPÈRES
#      (poses de caméra, plans de soldats), et l'affiche telle quelle tant qu'aucun décor
#      pré-rendu n'est déposé (le greybox est le placeholder jouable, doctrine du dépôt).
#
# ⚠️ AUCUNE COORDONNÉE EN DUR ICI NI DANS LE .tscn : tout est bâti au `_ready()` depuis
# `trench_geometry.gd`. C'est la garantie mécanique que le blockout, la table angulaire, les rendus
# et le serveur parlent de la MÊME arène — la désynchronisation géométrique est LE bug fatal de ce
# chantier, on la rend impossible plutôt que de la surveiller.
#
# PERF (critère de recette §5.7) : `MeshInstance3D` + `BoxMesh` plutôt que CSG — les CSG
# recalculent leur maillage et pèsent inutilement sous GL Compatibility. Une douzaine de boîtes,
# un `DirectionalLight3D`, aucune ombre dynamique coûteuse : le budget tient largement.
# =================================================================================================

const Geo := preload("res://scripts/game/trench_geometry.gd")

# Longueur de front bâtie (au-delà des positions, pour que le décor ne s'arrête pas net à l'écran).
const FRONT_OVERSHOOT := 10.0
# Teintes du greybox — neutres et DIFFÉRENCIÉES : un greybox illisible ne se recette pas.
const COL_GROUND := Color(0.30, 0.29, 0.27)
const COL_PARAPET := Color(0.46, 0.44, 0.40)
const COL_TRENCH := Color(0.20, 0.19, 0.18)
const COL_WALL := Color(0.26, 0.25, 0.23)

# Racines nommées : `trench_fp.gd` et les outils s'y accrochent (jamais par index d'enfant).
var poses_root: Node3D          # les 10 Marker3D de MON camp
var enemy_root: Node3D          # les 5 Marker3D des positions ADVERSES (ancrage du soldat)
var geometry_root: Node3D       # le monde LOINTAIN (masquable : un décor peint le remplace)
# ╔═ MA PROPRE TRANCHÉE VIT À PART, ET ELLE NE SE MASQUE PAS AVEC LE RESTE ═══════════════════════╗
# ║ ⚠️⚠️ DÉFAUT VÉCU EN PARTIE RÉELLE (§8.139.1). `set_geometry_visible(false)` masquait TOUT dès   ║
# ║ qu'un décor peint était déposé — y compris `NearParapet`, que le commentaire de ce fichier      ║
# ║ appelle lui-même « le parapet de sacs qui décide de tout le jeu ». Le joueur se retrouvait      ║
# ║ DEBOUT EN TERRAIN DÉCOUVERT, avec pour seule couverture une bande peinte de 77 px au bas du     ║
# ║ décor : elle n'occulte rien, ne tourne pas avec la caméra, ne se décale pas quand on fait un    ║
# ║ pas. Verdict du testeur, littéral : « il n'y a pas de tranchée ».                               ║
# ║ Un décor remplace le LOINTAIN (le no man's land, la tranchée d'en face). Il ne remplace JAMAIS  ║
# ║ le volume derrière lequel le joueur s'abrite : celui-là doit rester de la vraie géométrie, pour ║
# ║ occulter juste et bouger juste.                                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
var cover_root: Node3D          # MA tranchée : plancher, mur arrière, parapet — TOUJOURS rendue


func _ready() -> void:
	_build()


# Reconstruction complète — idempotente, appelable par un outil après un changement de cote.
func _build() -> void:
	for child in get_children():
		child.queue_free()
	geometry_root = _named_child("Geometry")
	cover_root = _named_child("Cover")
	poses_root = _named_child("Poses")
	enemy_root = _named_child("EnemyAnchors")
	_build_terrain()
	_build_poses()
	_build_light()


func _named_child(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	return node


# --- Volumes ---------------------------------------------------------------------------------
func _box(parent: Node3D, node_name: String, size: Vector3, center: Vector3,
		color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.metallic = 0.0
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = center
	parent.add_child(instance)
	return instance


func _build_terrain() -> void:
	var front: float = float(Geo.POSITIONS - 1) * Geo.POSITION_SPACING + FRONT_OVERSHOOT * 2.0
	var no_mans_land: float = Geo.NO_MANS_LAND

	# Sol du no man's land : entre les deux parapets, à `GROUND_Y` au-dessus des plancher de
	# tranchée. C'est la surface que les grenades frappent et sur laquelle courent les ombres.
	var land_depth: float = no_mans_land - Geo.PARAPET_THICKNESS * 2.0
	_box(geometry_root, "NoMansLand", Vector3(front, 0.2, land_depth),
		Vector3(0.0, Geo.GROUND_Y - 0.1, Geo.PARAPET_THICKNESS + land_depth * 0.5), COL_GROUND)

	# MA tranchée : plancher, mur arrière, et le parapet de sacs qui décide de tout le jeu.
	# ⚠️ Sous `cover_root`, PAS sous `geometry_root` : un décor peint ne doit jamais l'effacer.
	_box(cover_root, "NearFloor", Vector3(front, 0.2, Geo.TRENCH_WIDTH),
		Vector3(0.0, -0.1, -Geo.TRENCH_WIDTH * 0.5), COL_TRENCH)
	_box(cover_root, "NearBackWall", Vector3(front, Geo.GROUND_Y + 0.4, 0.4),
		Vector3(0.0, (Geo.GROUND_Y + 0.4) * 0.5, -Geo.TRENCH_WIDTH - 0.2), COL_WALL)
	_box(cover_root, "NearParapet", Vector3(front, Geo.PARAPET_Y, Geo.PARAPET_THICKNESS),
		Vector3(0.0, Geo.PARAPET_Y * 0.5, Geo.PARAPET_THICKNESS * 0.5), COL_PARAPET)

	# La tranchée ADVERSE, en miroir : son parapet a son arête PROCHE à `far_parapet_near_edge_z`
	# — c'est CETTE arête qui coupe le bas de la silhouette (cf. `occlusion_floor_at_target`).
	var far_parapet_center: float = Geo.far_parapet_near_edge_z() + Geo.PARAPET_THICKNESS * 0.5
	_box(geometry_root, "FarParapet", Vector3(front, Geo.PARAPET_Y, Geo.PARAPET_THICKNESS),
		Vector3(0.0, Geo.PARAPET_Y * 0.5, far_parapet_center), COL_PARAPET)
	_box(geometry_root, "FarFloor", Vector3(front, 0.2, Geo.TRENCH_WIDTH),
		Vector3(0.0, -0.1, no_mans_land + Geo.TRENCH_WIDTH * 0.5), COL_TRENCH)
	_box(geometry_root, "FarBackWall", Vector3(front, Geo.GROUND_Y + 0.4, 0.4),
		Vector3(0.0, (Geo.GROUND_Y + 0.4) * 0.5, no_mans_land + Geo.TRENCH_WIDTH + 0.2), COL_WALL)


# --- Repères ---------------------------------------------------------------------------------
func _build_poses() -> void:
	# Les 10 poses de MON camp (5 positions × 2 postures) — nommées `cam_p{i}_{up|down}`.
	for pose in Geo.all_poses():
		var marker := Marker3D.new()
		marker.name = String(pose["name"])
		marker.transform = Geo.pose_transform(int(pose["pos"]), String(pose["stance"]))
		poses_root.add_child(marker)
	# Les 5 ancrages ADVERSES : le soldat placeholder (et demain le .glb) s'y accroche, au SOL de
	# sa tranchée — la posture est jouée par l'animation, pas par le repère.
	for i in range(Geo.POSITIONS):
		var anchor := Marker3D.new()
		anchor.name = "enemy_p%d" % i
		anchor.position = Vector3(Geo.position_x(i), 0.0, Geo.far_soldier_z())
		# Il fait FACE à moi (demi-tour par rapport à mes caméras).
		anchor.rotation = Vector3.ZERO
		enemy_root.add_child(anchor)


func _build_light() -> void:
	# Lumière rasante unique : elle sculpte les sacs de sable pour que le greybox se lise en
	# capture (§6.4) sans coûter d'ombre dynamique.
	# ⚠️ LE SOLEIL VIENT DE DERRIÈRE LE JOUEUR (lacet ~200°) : c'est la seule orientation qui
	# éclaire les faces TOURNÉES VERS LA CAMÉRA — parapet proche, mur de sacs, silhouette adverse.
	# Un soleil de face laissait tout le champ visible dans son ombre et rendait le greybox
	# quasiment noir (défaut vu en CAPTURE, invisible au boot headless).
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-34.0, 200.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = false
	add_child(sun)


# --- API pour les outils et pour `trench_fp.gd` ---------------------------------------------
# Transform d'une pose de caméra, LU sur le blockout (et non recalculé) : c'est ainsi que la vue
# de production et la table angulaire ne peuvent pas diverger.
func pose_transform(pos_index: int, stance: String) -> Transform3D:
	if poses_root == null:
		return Geo.pose_transform(pos_index, stance)
	var marker := poses_root.get_node_or_null(Geo.pose_name(pos_index, stance))
	if marker is Marker3D:
		return (marker as Marker3D).transform
	return Geo.pose_transform(pos_index, stance)


# Point d'ancrage au sol d'une position adverse (pose du soldat ennemi).
func enemy_anchor(pos_index: int) -> Vector3:
	if enemy_root != null:
		var marker := enemy_root.get_node_or_null("enemy_p%d" % clampi(pos_index, 0, Geo.POSITIONS - 1))
		if marker is Marker3D:
			return (marker as Marker3D).position
	return Vector3(Geo.position_x(pos_index), 0.0, Geo.far_soldier_z())


# Masque les volumes : le rendu « décor pré-rendu déposé » n'affiche QUE les acteurs (soldat,
# projectiles) par-dessus l'image — les boîtes grises deviendraient un doublon disgracieux.
func set_geometry_visible(visible_geometry: bool) -> void:
	if geometry_root != null:
		geometry_root.visible = visible_geometry


# Habille MA tranchée avec la matière du décor accroupi — le mur de sacs de jute déjà peint.
# `null` remet le gris du greybox.
#
# ╔═ POURQUOI TEXTURER PLUTÔT QUE LAISSER LE VOLUME GRIS ════════════════════════════════════════╗
# ║ Avec un décor photoréaliste derrière lui, un parapet gris uni ne se lit pas comme « mon abri » ║
# ║ mais comme un défaut d'affichage — un rectangle mat posé sur une photo. Or on tient déjà LA    ║
# ║ bonne matière : `pose_2_down.png` EST un mur de sacs de jute plein cadre, peint dans la même   ║
# ║ passe et sous la même lumière que le paysage. On la réutilise, coût nul, cohérence garantie.   ║
# ║ ⚠️ Le pavage est calculé en MÈTRES (`uv1_scale`), pas en fraction de face : sans ça, la même   ║
# ║ image s'étirerait sur 26 m de front et les sacs feraient trois mètres de large.                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const COVER_SANDBAG_METRES := 2.4     # largeur réelle représentée par une tuile de texture ⚙
# ⚠️ Le parapet est À CONTRE-JOUR (le soleil vient de derrière le joueur, cf. `_build_light`) : sa
# face tournée vers l'œil ne reçoit presque rien. Teinté à 0,62 il sortait en BANDEAU NOIR — la
# matière de jute ne se lisait pas, et l'abri se lisait donc comme un défaut d'affichage plutôt que
# comme un mur de sacs. On compense par l'albédo plutôt qu'en tordant l'éclairage, qui sert aussi à
# sculpter le soldat d'en face.
const COVER_TINT := Color(1.30, 1.28, 1.24)


func set_cover_texture(tex: Texture2D) -> void:
	if cover_root == null:
		return
	for child in cover_root.get_children():
		var instance := child as MeshInstance3D
		if instance == null or not (instance.mesh is BoxMesh):
			continue
		var box := instance.mesh as BoxMesh
		var material := box.material as StandardMaterial3D
		if material == null:
			continue
		material.albedo_texture = tex
		if tex == null:
			material.uv1_scale = Vector3.ONE
			material.albedo_color = COL_PARAPET if instance.name == "NearParapet" else COL_TRENCH
			continue
		material.uv1_scale = Vector3(box.size.x / COVER_SANDBAG_METRES,
			maxf(box.size.y, box.size.z) / COVER_SANDBAG_METRES, 1.0)
		material.albedo_color = COVER_TINT
