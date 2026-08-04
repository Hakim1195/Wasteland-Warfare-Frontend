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

# Champ de vision VERTICAL de la caméra ⚙. À 75° horizontaux environ (16:9), la silhouette
# adverse de 0,955° occupe ~25 px sur 1920 : petite, mais franchement visable.
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
const AIM_FOLLOW := 1.0
# Borne de sécurité, au-delà du débattement client (±32°) : elle n'écrête jamais en jeu, elle
# empêche seulement une visée aberrante de faire pivoter la caméra à l'envers du monde.
const AIM_FOLLOW_MAX := 45.0
# Matière de MON parapet quand un décor est déposé : le mur de sacs peint de la pose accroupie.
const COVER_TEXTURE := "res://assets/images/trench/pose_2_down.png"

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
const GRENADE_POOL := 6
# Hauteur du PLANCHER DE TRANCHÉE (+ un rien pour éviter le z-fighting avec le sol). C'est là que
# tombent les grenades et que se posent leurs marqueurs — pas au niveau du no man's land.
const MARKER_Y := 0.04

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
var _markers: Array[MeshInstance3D] = []

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

# --- Machine à frames du soldat (§8.138) ----------------------------------------------------------
# `_enemy_painted` = TRUE quand `enemy_idle.png` existe. C'est un OU EXCLUSIF assumé : soit tout le
# soldat est peint, soit tout le soldat est en primitives. Jamais un panaché.
var _enemy_painted := false
var _enemy_frame := Sprites.ENEMY_IDLE
var _enemy_frame_left := 0.0
var _enemy_dying := false
var _enemy_aiming := false
var _enemy_dead := false
var _enemy_tint := COL_DANGER


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

	_build_enemy()
	_build_viewmodel()
	_build_pools()


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
	_enemy_painted = Sprites.enemy_available()
	_enemy_placeholder.visible = not _enemy_painted
	_enemy_sprite.visible = _enemy_painted
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
	_enemy_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# 2. ALPHA_CUT_DISABLED = fondu alpha classique, et NON `DISCARD`/`OPAQUE_PREPASS` :
	#    • les bords sont DOUX (sortie rembg antialiasée) — un seuil les redécouperait en escalier ;
	#    • c'est la SEULE option qui laisse vivre le fondu de redaction (`modulate.a`) : sous un
	#      seuil, l'adversaire ne s'effacerait pas, il DISPARAÎTRAIT d'un coup à mi-fondu.
	#    L'occultation par le parapet reste juste : un objet transparent est TESTÉ en profondeur même
	#    s'il n'y écrit pas, et le parapet est opaque. Le tri n'est pas un sujet : il y a UN sprite.
	_enemy_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	# 3. NON ÉCLAIRÉ, comme le placeholder et pour la MÊME raison (défaut n° 3 vu en CAPTURE) : à
	#    35 m la part exposée du soldat fait ~0,9°, soit une vingtaine de pixels. Éclairé, il tombe
	#    dans l'ombre du parapet et devient littéralement invisible. La lumière du personnage est
	#    DÉJÀ PEINTE dans la frame — la rééclairer serait de toute façon la peindre deux fois.
	_enemy_sprite.shaded = false
	_enemy_sprite.double_sided = true
	_enemy_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_enemy_sprite.pixel_size = Sprites.PIXEL_SIZE
	_enemy_sprite.centered = true
	_enemy.add_child(_enemy_sprite)


# Pose la texture de la frame courante ET RECALCULE L'ANCRAGE AU SOL.
# ⚠️ Le quad est CENTRÉ sur son origine : pour que les PIEDS tombent sur l'ancrage du blockout, on
# remonte le sprite d'une demi-hauteur. Cette demi-hauteur se recalcule à chaque frame parce que
# `pixel_size` est CONSTANT (cf. `trench_sprites.PIXEL_SIZE`) : une frame de mort livrée moins haute
# qu'une frame debout rend un corps AU SOL, et non un cadavre étiré sur 1,80 m.
func _apply_enemy_frame() -> void:
	if not _enemy_painted or _enemy_sprite == null:
		return
	var frame := Sprites.enemy_texture(_enemy_frame)
	if frame == null:
		return
	_enemy_sprite.texture = frame
	_enemy_sprite.position = Vector3(0.0, float(frame.get_height()) * Sprites.PIXEL_SIZE * 0.5, 0.0)


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

		# Le MARQUEUR D'IMPACT AU SOL : un disque pulsant, visible DÈS LE LANCER (règle d'or).
		var disc := CylinderMesh.new()
		disc.top_radius = 1.6
		disc.bottom_radius = 1.6
		disc.height = 0.05
		var marker := MeshInstance3D.new()
		marker.mesh = disc
		marker.material_override = _material(Color(COL_DANGER.r, COL_DANGER.g, COL_DANGER.b, 0.55),
			true)
		marker.visible = false
		_root.add_child(marker)
		_markers.append(marker)

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


# Le champ de vision de la caméra, exposé à l'hôte : c'est lui qui convertit la dispersion d'une
# arme (en degrés) en écartement de réticule (en pixels). Une seule source pour le FOV.
func camera_fov() -> float:
	return _camera.fov if _camera != null else CAMERA_FOV


# Bascule greybox / décor pré-rendu. Sans décor déposé, le blockout EST le fond (aligné par
# définition) ; avec un décor, on masque les volumes pour ne pas doubler les sacs de sable.
# ⚠️ NE MASQUE QUE LE MONDE LOINTAIN. Ma propre tranchée (`cover_root`) reste rendue quoi qu'il
# arrive : un décor peint remplace le no man's land, jamais le volume derrière lequel on s'abrite
# (§8.139.1 — défaut « il n'y a pas de tranchée », vu en partie réelle). Quand un décor existe, ce
# volume est HABILLÉ de la matière du mur de sacs plutôt que laissé en gris de blockout.
func show_blockout_geometry(show_geometry: bool) -> void:
	if _blockout == null:
		return
	if _blockout.has_method("set_geometry_visible"):
		_blockout.set_geometry_visible(show_geometry)
	if _blockout.has_method("set_cover_texture"):
		_blockout.set_cover_texture(null if show_geometry else Sprites.texture_at(COVER_TEXTURE))


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
	_cam_yaw = clampf(_aim_yaw * AIM_FOLLOW, -AIM_FOLLOW_MAX, AIM_FOLLOW_MAX)
	_cam_pitch = clampf(_aim_pitch * AIM_FOLLOW, -AIM_FOLLOW_MAX, AIM_FOLLOW_MAX)
	_camera.position = _cam_current
	_camera.look_at(_cam_current + _direction(_cam_yaw, _cam_pitch), Vector3.UP)


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
	var x := _lerp_position_x(_enemy_last_pos)
	# En s'effaçant, il s'enfonce derrière le parapet : la disparition RACONTE quelque chose.
	var sink := (1.0 - _enemy_alpha) * 0.55
	_enemy.position = Vector3(x, -sink, Geo.far_soldier_z())
	var flash: float = clampf(float(enemy.get("hit", 0.0)), 0.0, 1.0)
	if _enemy_painted:
		# TEINTE DE FACTION + fondu de redaction + éclair de touche, en une seule couleur : sur un
		# `Sprite3D`, `modulate` est le point d'entrée unique (il n'y a pas de matériau à repeindre).
		var tint := Color.WHITE.lerp(_enemy_tint, ENEMY_TINT_MIX)
		if flash > 0.0:
			tint = tint.lerp(Color.WHITE, flash * ENEMY_HIT_WHITEN)
		tint.a = _enemy_alpha
		_enemy_sprite.modulate = tint
		return
	for mesh in [_enemy_mesh, _enemy_helmet]:
		if mesh != null and mesh.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = mesh.material_override
			mat.albedo_color.a = _enemy_alpha
			mat.emission_enabled = flash > 0.0
			mat.emission = Color(1, 1, 1)
			mat.emission_energy_multiplier = flash * 3.0


func _lerp_position_x(pos: float) -> float:
	var low := int(floor(pos))
	var high: int = mini(low + 1, Geo.POSITIONS - 1)
	return lerpf(Geo.position_x(low), Geo.position_x(high), pos - float(low))


# Origine d'un tir : l'œil du tireur, dans SA tranchée.
func _muzzle_origin(from_pos: int, mine: bool) -> Vector3:
	var z: float = Geo.near_soldier_z() if mine else Geo.far_soldier_z()
	return Vector3(Geo.position_x(from_pos), Geo.EYE_UP, z)


# Direction d'un tir dans MON repère.
# ⚠️ MIROIR : le tireur d'en face vise dans SON repère, dont le +Z pointe vers moi. Le passage
# d'un repère à l'autre est la réflexion (x, y, z) → (x, y, 35 - z) : elle laisse le lacet
# inchangé et RETOURNE la composante en Z. D'où le signe ci-dessous — c'est la même convention de
# miroir que la table angulaire, qui sert aux deux camps sans inversion d'index.
func _shot_direction(yaw_deg: float, pitch_deg: float, mine: bool) -> Vector3:
	var dir := _direction(yaw_deg, pitch_deg)
	return dir if mine else Vector3(dir.x, dir.y, -dir.z)


func _render_tracers(tracers: Array) -> void:
	for i in range(_tracers.size()):
		var node := _tracers[i]
		if i >= tracers.size():
			node.visible = false
			continue
		var shot: Dictionary = tracers[i]
		var mine := bool(shot.get("mine", false))
		var origin := _muzzle_origin(int(shot.get("from_pos", 2)), mine)
		var dir := _shot_direction(float(shot.get("yaw", 0.0)), float(shot.get("pitch", 0.0)), mine)
		var travelled: float = clampf(float(shot.get("t", 0.0)), 0.0, 1.0) * Geo.NO_MANS_LAND
		var head := origin + dir * travelled
		# La traçante est un SEGMENT (la balle a une longueur apparente), pas un point.
		var tail := origin + dir * maxf(0.0, travelled - 3.0)
		node.visible = true
		node.position = (head + tail) * 0.5
		node.look_at(head, Vector3.UP)
		node.scale = Vector3(1.0, 1.0, maxf(0.4, head.distance_to(tail)))


func _render_grenades(grenades: Array, markers: Array) -> void:
	for i in range(_grenades.size()):
		var node := _grenades[i]
		if i >= grenades.size():
			node.visible = false
			continue
		var g: Dictionary = grenades[i]
		var mine := bool(g.get("mine", false))
		var origin := _muzzle_origin(int(g.get("from_pos", 2)), mine)
		var land_z: float = Geo.far_soldier_z() if mine else Geo.near_soldier_z()
		# ⚠️ LA GRENADE TOMBE AU FOND DE LA TRANCHÉE (y ≈ 0), PAS au niveau du no man's land :
		# les positions du duel sont DANS les tranchées. Défaut vu en CAPTURE seulement — posé à
		# `GROUND_Y` (1,0 m), le marqueur passait AU-DESSUS des yeux d'un accroupi (0,90 m) et
		# noyait tout l'écran de rouge. Un boot headless ne l'aurait jamais montré.
		var target := Vector3(Geo.position_x(int(g.get("target_pos", 2))), MARKER_Y, land_z)
		var t: float = clampf(float(g.get("t", 0.0)), 0.0, 1.0)
		# CLOCHE : une parabole franche — c'est elle qui rend le temps de vol lisible à l'œil.
		var flat := origin.lerp(target, t)
		flat.y += sin(t * PI) * 6.0
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
		node.position = Vector3(Geo.position_x(int(m.get("target_pos", 2))), MARKER_Y, z)
		# Le disque PULSE d'autant plus vite que l'impact approche : la menace se lit sans lire.
		var eta: float = clampf(float(m.get("eta", 1.0)), 0.0, 1.0)
		var pulse: float = 1.0 if _reduced_motion else (0.75 + 0.25 * sin((1.0 - eta) * 26.0))
		node.scale = Vector3(pulse, 1.0, pulse)
		if node.material_override is StandardMaterial3D:
			(node.material_override as StandardMaterial3D).albedo_color.a = 0.30 + 0.45 * (1.0 - eta)


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
