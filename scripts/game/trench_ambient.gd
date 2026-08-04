extends Control

# =================================================================================================
# LA TRANCHÉE — HABILLAGE PROCÉDURAL (§8.139, LOT D)
#
# La couche qui SOUDE les autres. Décor peint, blockout 3D, sprites détourés et viewmodel sortent de
# quatre chaînes de production différentes ; ce nœud pose par-dessus ce qu'elles n'ont pas : de
# l'air. Trois éléments, tous procéduraux, aucun asset :
#
#   1. BRUME DE PROFONDEUR — deux nappes translucides à hauteur d'horizon, qui dérivent lentement.
#      C'est elle qui ASSIED le sprite du soldat : un billboard détouré posé sur un décor peint reste
#      un autocollant tant que rien ne passe devant ses pieds.
#   2. CENDRES — dérive lente plein cadre (le motif du splash de titre §8.63, repris de
#      `ambient_layer.gd` §8.122 : `local_coords = false`, rampe de fondu, point doux généré).
#   3. BRAISES — trois foyers discrets posés SUR la ligne d'horizon, côté ruines.
#
# ╔═ PLACEMENT DANS LA PILE — CE N'EST PAS UN DÉTAIL D'ORDRE ═════════════════════════════════════╗
# ║ Ce nœud vit AU-DESSUS du monde 3D et EN DESSOUS du viewmodel. Les deux bornes se justifient :  ║
# ║  • au-dessus du monde, parce que la brume doit voiler le soldat d'en face — il est à 35 m, et  ║
# ║    35 m d'air chargé, ça se voit ; une brume derrière lui ne l'assiérait pas, elle le          ║
# ║    découperait davantage ;                                                                     ║
# ║  • sous le viewmodel, parce que mon arme est à 0,60 m de mon œil : aucune cendre ni aucune     ║
# ║    nappe de brume ne peut passer DEVANT elle sans mentir sur la profondeur.                    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# VUE PURE (Règle d'Or §6.1) : ce script ne lit ni GameState ni le réseau. Il reçoit une posture et
# un drapeau de confort, rien d'autre. Aucune allocation par frame.

# ⚠️ BUDGET PARTICULES — critère de recette du bon de commande (≤ 200 pour cette scène). Vérifié par
# `tools/test_trench_ambient.tscn`, qui compare `particle_total()` au plafond.
const PARTICLE_BUDGET := 200

# --- Cendres (plein cadre) ------------------------------------------------------------------------
# 70 flocons sur un écran 1080p : ~1 % de couverture. Volontairement peu — la cendre doit se
# remarquer en vision périphérique et JAMAIS disputer la lecture de la cible, qui est le jeu.
const ASH_AMOUNT := 70
const ASH_LIFETIME := 8.0
const ASH_ALPHA := 0.15                        # PLAFOND : au-delà, l'écran se voile et la cible se perd
const ASH_COLOR := Color(0.66, 0.69, 0.72)

# --- Braises (sur l'horizon) ----------------------------------------------------------------------
const EMBER_SOURCES := 3
const EMBER_AMOUNT := 10
const EMBER_LIFETIME := 2.6
const EMBER_COLOR := Color(0.92, 0.55, 0.24, 0.42)
# Abscisses relatives des trois foyers : DÉLIBÉRÉMENT asymétriques et hors du centre. Un foyer au
# milieu de l'écran serait pile derrière le réticule, c'est-à-dire pile là où le joueur cherche sa
# cible — l'ambiance ne doit jamais disputer la lecture au jeu.
const EMBER_X := [0.17, 0.58, 0.86]

# --- Brume de profondeur --------------------------------------------------------------------------
const HAZE_SHADER := preload("res://shaders/trench_haze.gdshader")
# L'horizon est à 50 % de la hauteur : c'est LA cote du chantier (le blockout y place la ligne de
# tranchée adverse, cf. `trench_geometry.gd` projeté). Les décors sont produits sur cette cote.
const HORIZON_RATIO := 0.5
# ╔═ …MAIS L'HORIZON N'EST PLUS À UNE ORDONNÉE FIXE ══════════════════════════════════════════════╗
# ║ C'était vrai tant que la caméra ne bougeait pas : le décor était peint pour poser l'horizon à  ║
# ║ 50 % de la hauteur, et la brume s'y accrochait. Depuis le pivot « monde 3D + ciel peint », la  ║
# ║ caméra pique du nez et se redresse avec la visée — un horizon cloué à 50 % laisserait la brume ║
# ║ flotter au milieu du ciel et les braises brûler en l'air. `trench_fp.gd` pousse donc à chaque  ║
# ║ frame l'ordonnée RÉELLE, obtenue en projetant la direction de site nul par la caméra 3D.       ║
# ║ La constante ci-dessus reste la valeur de départ, avant le premier `set_horizon_ratio`.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Écart minimal (en fraction de hauteur) qui justifie de refaire la mise en page : sous ce seuil,
# rien ne se verrait bouger, et on relayouterait 60 fois par seconde pour rien.
const HORIZON_EPSILON := 0.004
# Deux nappes : hauteur de bande (en fraction d'écran), décalage vertical, échelle et vitesse.
# ⚠️ Les vitesses sont dans un rapport IRRATIONNEL (0,013 / 0,0071 ≈ 1,83) : deux vitesses en rapport
# simple se remettraient périodiquement en phase et la brume « battrait » à intervalle régulier.
const HAZE_BANDS := [
	{"height": 0.30, "offset": -0.02, "scale": 1.7, "speed": 0.0130, "strength": 0.20},
	{"height": 0.19, "offset": 0.05, "scale": 3.1, "speed": -0.0071, "strength": 0.14},
]

# --- Étalonnage -----------------------------------------------------------------------------------
const GRADE_SHADER := preload("res://shaders/trench_grade.gdshader")

var _reduced_motion := false
var _standing := true
var _horizon_ratio := HORIZON_RATIO
var _ash: GPUParticles2D = null
var _embers: Array = []
var _haze: Array = []                          # [{node: TextureRect, mat: ShaderMaterial, speed: float}]
var _scroll := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# ⚠️ Sans ça, la couche mangerait la souris et la visée cesserait de tourner. Vécu ailleurs
	# dans ce dépôt (§8.73, pièges `mouse_filter`) : un Control plein écran est un mur par défaut.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_haze()
	_build_ash()
	_build_embers()
	resized.connect(_layout)
	# ⚠️⚠️ PIÈGE DÉJÀ PAYÉ DEUX FOIS DANS CE DÉPÔT (§8.121, §8.138), ET REPAYÉ ICI : un `Control`
	# créé PAR CODE garde `size = (0,0)` malgré `set_anchors_preset(PRESET_FULL_RECT)`, et le signal
	# `resized` ne part JAMAIS — donc `_layout()` ne s'exécute qu'une fois, sur une taille nulle.
	# Mesuré : nappes de brume en 0x0, trois foyers de braises empilés en (0,0), cendres émises dans
	# une boîte de 1 px. La couche ne peignait RIEN, et rien ne le signalait : une nappe de taille
	# nulle et une nappe transparente rendent exactement la même image. On ne fait donc plus confiance
	# à `size` : c'est le VIEWPORT qui fait foi, et on se recale sur ses changements de taille.
	get_viewport().size_changed.connect(_layout)
	_layout()
	_apply_motion()


# La surface à couvrir. `size` est utilisée quand elle est crédible (cas d'un parent Control qui a
# vraiment posé la mise en page), le viewport sert de vérité de repli — jamais l'inverse.
func _canvas_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	return get_viewport_rect().size


# Appelé par `trench_fp.gd` avec le confort déjà lu (même patron que `_world`/`_viewmodel`).
func set_reduced_motion(value: bool) -> void:
	_reduced_motion = value
	_apply_motion()


# ╔═ ACCROUPI, IL N'Y A PLUS D'HORIZON — ET DONC PLUS RIEN À HABILLER AU LOIN ════════════════════╗
# ║ La géométrie du blockout est formelle (rapport §3.2, mesurée) : à 0,90 m de hauteur d'œil, le  ║
# ║ parapet à 1,25 m REMPLIT le champ. Le décor accroupi est un mur de sacs à 0,60 m, plein cadre. ║
# ║ Laisser tourner une brume de profondeur et trois foyers de braises au milieu de cet écran, ce  ║
# ║ serait peindre un lointain à travers un mur — et allumer trois feux à l'intérieur des sacs.    ║
# ║ Les CENDRES, elles, restent : elles tombent du ciel et tombent aussi dans la tranchée.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func set_horizon_ratio(ratio: float) -> void:
	if absf(ratio - _horizon_ratio) < HORIZON_EPSILON:
		return
	_horizon_ratio = ratio
	_layout()


func set_stance(stance: String) -> void:
	var standing := stance != "down"
	if standing == _standing:
		return
	_standing = standing
	for band in _haze:
		band["node"].visible = standing
	for p in _embers:
		if is_instance_valid(p):
			p.visible = standing
			# `visible = false` seul laisserait les particules tourner — invisibles mais payées
			# (leçon `ambient_layer.set_enabled`, §8.122).
			p.emitting = standing


# ╔═ « FIGÉ » N'EST PAS « ÉTEINT » ═══════════════════════════════════════════════════════════════╗
# ║ Le confort demandé est `reduced_motion`, pas `no_atmosphere` : ce qui gêne, c'est le MOUVEMENT ║
# ║ périphérique, pas la matière. On coupe donc la simulation (`speed_scale = 0`) et le défilement ║
# ║ des nappes, en laissant l'image en place — le joueur garde son décor habillé, il perd juste ce ║
# ║ qui bouge. Éteindre les nœuds serait plus simple à écrire et changerait la composition de       ║
# ║ l'écran entre deux joueurs, ce que ce réglage n'a jamais promis.                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _apply_motion() -> void:
	var scale := 0.0 if _reduced_motion else 1.0
	if _ash != null and is_instance_valid(_ash):
		_ash.speed_scale = scale
	for p in _embers:
		if is_instance_valid(p):
			p.speed_scale = scale


func _process(delta: float) -> void:
	if _reduced_motion or _haze.is_empty():
		return
	_scroll += delta
	for band in _haze:
		var mat: ShaderMaterial = band["mat"]
		var spec: Dictionary = band["spec"]
		mat.set_shader_parameter("scroll", _scroll * float(spec["speed"]))


# =================================================================================================
# 1) BRUME DE PROFONDEUR
# =================================================================================================
func _build_haze() -> void:
	for spec in HAZE_BANDS:
		var mat := ShaderMaterial.new()
		mat.shader = HAZE_SHADER
		mat.set_shader_parameter("noise_tex", _make_noise())
		mat.set_shader_parameter("scale_x", float(spec["scale"]))
		mat.set_shader_parameter("strength", float(spec["strength"]))
		var rect := ColorRect.new()
		rect.name = "Haze%d" % _haze.size()
		rect.color = Color.WHITE                # ignorée par le shader, mais un alpha 0 le sauterait
		rect.material = mat
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		_haze.append({"node": rect, "mat": mat, "spec": spec})


# Bruit SANS COUTURE : la nappe défile en boucle sur l'axe X, une texture non bouclée y montrerait
# une jointure qui repasse à intervalle fixe — le défaut le plus visible d'un scrolling procédural.
func _make_noise() -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 128
	tex.seamless = true
	tex.noise = noise
	return tex


# =================================================================================================
# 2) CENDRES  &  3) BRAISES
# =================================================================================================
func _build_ash() -> void:
	_ash = _make_emitter("Ash", ASH_AMOUNT, ASH_LIFETIME)
	# La moitié d'une durée de vie en préchauffage : l'écran est déjà « habité » à l'ouverture du
	# duel, au lieu de se remplir sous les yeux du joueur pendant les premières secondes.
	_ash.preprocess = ASH_LIFETIME * 0.5
	var pm := _ash.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.direction = Vector3(-0.35, 1.0, 0.0)     # la cendre TOMBE, poussée par un vent de travers
	pm.spread = 24.0
	pm.gravity = Vector3(0.0, 6.0, 0.0)
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 26.0
	pm.scale_min = 1.0
	pm.scale_max = 2.6
	pm.color = Color(ASH_COLOR.r, ASH_COLOR.g, ASH_COLOR.b, ASH_ALPHA)
	add_child(_ash)


func _build_embers() -> void:
	for i in EMBER_SOURCES:
		var p := _make_emitter("Ember%d" % i, EMBER_AMOUNT, EMBER_LIFETIME)
		p.preprocess = EMBER_LIFETIME
		var pm := p.process_material as ParticleProcessMaterial
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(26.0, 4.0, 1.0)
		pm.direction = Vector3(0.15, -1.0, 0.0)
		pm.spread = 14.0
		pm.gravity = Vector3(0.0, -14.0, 0.0)
		pm.initial_velocity_min = 6.0
		pm.initial_velocity_max = 20.0
		pm.scale_min = 0.6
		pm.scale_max = 1.6
		pm.color = EMBER_COLOR
		add_child(p)
		_embers.append(p)


func _make_emitter(node_name: String, amount: int, lifetime: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	# `local_coords = false` : les particules déjà émises restent où elles sont quand l'émetteur se
	# déplace (redimensionnement de fenêtre) — sinon toute la cendre « téléporte » d'un bloc.
	p.local_coords = false
	p.texture = _make_dot(10)
	var pm := ParticleProcessMaterial.new()
	# Fondu de sortie : sans rampe, les particules disparaissent NET en fin de vie (effet « clic »).
	# Testé défensivement, comme dans `ambient_layer.gd` : si la propriété disparaissait d'une
	# version future on perdrait le fondu, jamais le rendu.
	if "color_ramp" in pm:
		pm.color_ramp = _make_fade_ramp()
	p.process_material = pm
	return p


func _make_fade_ramp() -> GradientTexture1D:
	# Une cendre APPARAÎT et DISPARAÎT en fondu : la rampe monte vite puis redescend lentement.
	# ⚠️ Écrite en POSANT les deux tableaux, et non par `set_color`/`add_point` enchaînés : insérer un
	# point RENUMÉROTE les suivants, et l'ordre des appels devient un piège silencieux.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


# Point doux généré (même recette que `ambient_layer.gd`) — aucune dépendance à un fichier image,
# donc rien qui puisse manquer dans un export.
func _make_dot(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := float(d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)


# =================================================================================================
# MISE EN PAGE — tout se recalcule sur la taille RÉELLE, jamais sur une constante de résolution
# =================================================================================================
func _layout() -> void:
	var canvas := _canvas_size()
	var w := canvas.x
	var h := canvas.y
	if w <= 0.0 or h <= 0.0:
		return
	var horizon := h * _horizon_ratio

	for band in _haze:
		var rect: ColorRect = band["node"]
		var spec: Dictionary = band["spec"]
		var band_h := h * float(spec["height"])
		rect.position = Vector2(0.0, horizon + h * float(spec["offset"]) - band_h * 0.5)
		rect.size = Vector2(w, band_h)

	if _ash != null and is_instance_valid(_ash):
		_ash.position = Vector2(w * 0.5, h * 0.5)
		var pm := _ash.process_material as ParticleProcessMaterial
		# ╔═ ÉMISSION SUR TOUT LE CADRE, PAS EN HAUT D'ÉCRAN ════════════════════════════════════════╗
		# ║ Première version : émission dans une bande au-dessus du cadre, en comptant sur la chute   ║
		# ║ pour peupler l'écran. MESURÉ sur capture : la cendre ne descendait que de ~200 px en 8 s   ║
		# ║ (8-26 px/s), et les 800 px du bas restaient rigoureusement VIDES — 0,00 % de pixels        ║
		# ║ touchés. Accélérer la chute donnerait de la pluie, pas de la cendre. On émet donc PARTOUT  ║
		# ║ et on laisse la dérive faire le reste : c'est aussi ce que fait `ambient_layer.gd` (§8.122)║
		# ║ pour les cendres du plateau, et pour la même raison.                                       ║
		# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
		pm.emission_box_extents = Vector3(w * 0.55, h * 0.55, 1.0)

	for i in _embers.size():
		var p: GPUParticles2D = _embers[i]
		if is_instance_valid(p):
			p.position = Vector2(w * float(EMBER_X[i % EMBER_X.size()]), horizon)


# Total de particules GPU alloué par cette couche — exposé pour le harnais de recette.
static func particle_total() -> int:
	return ASH_AMOUNT + EMBER_SOURCES * EMBER_AMOUNT


# L'étalonnage est monté par `trench_fp.gd` (il doit être AU-DESSUS du viewmodel, donc hors de ce
# nœud) mais sa fabrique vit ici, avec le reste de l'habillage : un seul fichier à rouvrir le jour
# où la direction artistique bouge.
static func make_grade_layer() -> ColorRect:
	var rect := ColorRect.new()
	rect.name = "Grade"
	rect.color = Color.WHITE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = GRADE_SHADER
	rect.material = mat
	return rect
