extends Node3D
# =================================================================================================
# LA TRANCHÉE (§8.141) — L'EXPLOSION DE GRENADE : une séquence, pas un flash.
#
# ╔═ CE QUE CETTE SCÈNE DOIT DIRE, ET DANS QUEL ORDRE ════════════════════════════════════════════╗
# ║ Verdict de Hakim : l'explosion « n'a pas de rayon d'action visible et pas d'animation ». Deux   ║
# ║ manques distincts, et le second n'est pas du décor :                                            ║
# ║   • SANS RAYON, le joueur ne peut pas apprendre la portée de son arme anti-camping. Il lance    ║
# ║     au jugé, il encaisse au jugé, et il ne construit jamais l'intuition qui fait le duel.       ║
# ║   • SANS DURÉE, une grenade est un clignotement : rien ne relie le lancer à ses conséquences.   ║
# ║ La séquence ci-dessous répond aux deux, et son élément CENTRAL n'est pas le feu — c'est         ║
# ║ l'ANNEAU DE CHOC, qui s'étend de 0 au rayon EXACT. La zone de dégâts se LIT dans l'animation,   ║
# ║ à chaque explosion, sans texte et sans tutoriel.                                                ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️ L'INVARIANT D'HONNÊTETÉ (§C.1) — LE VISUEL N'A PAS SA PROPRE VALEUR ════════════════════╗
# ║ Le rayon dessiné n'est PAS une constante de ce fichier : il est POSÉ par l'appelant, qui le     ║
# ║ tient de `trench_init.rules.grenade.radius_m` — c'est-à-dire du REGISTRE SERVEUR qui décide des ║
# ║ dégâts. Il n'y a donc pas deux rayons à garder d'accord : il n'y en a qu'un, et le cercle ne    ║
# ║ PEUT pas mentir. Si le rééquilibrage passe un jour le rayon à 3 m, l'anneau suit sans qu'une    ║
# ║ ligne ne soit touchée ici.                                                                      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# POOLÉE : l'appelant (`trench_fp_world.gd`) en garde un petit nombre et les réarme par `play()`.
# Rien n'est instancié en cours de duel — la première explosion coûterait sinon sa compilation de
# shader au pire moment (celui où quelque chose d'important se passe).

# --- La séquence, en secondes ⚙ (le tableau du bon de commande, une ligne par élément) -----------
const FLASH_END := 0.033          # 2 frames à 60 Hz
const CORE_END := 0.12
const RING_END := 0.35
const FOUNTAIN_START := 0.03
const FOUNTAIN_END := 0.60
const SMOKE_START := 0.12
const SMOKE_END := 2.50
const CRATER_END := 8.00
const TOTAL := CRATER_END

const FLASH_RADIUS := 0.6

# Couleurs ⚙ — accordées au ciel couvert et à la boue du blockout, pas choisies au hasard : une
# explosion orange vif dans ce monde-là se lirait comme un effet collé par-dessus l'image.
const COL_FLASH := Color(1.0, 0.94, 0.72)
const COL_FIRE := Color(1.0, 0.62, 0.24)
const COL_MUD := Color(0.38, 0.31, 0.24)
const COL_SMOKE := Color(0.34, 0.33, 0.31)
const COL_RING := Color(1.0, 0.78, 0.42)

# ╔═ ⚠️⚠️ L'ANNEAU EST GARANTI EN FRAMES, PAS SEULEMENT EN SECONDES — VU PAR LA SONDE ═══════════╗
# ║ `probe_trench_grenade` a rendu « aucun pixel ne change » sur l'anneau de choc, alors que son    ║
# ║ échelle et son alpha étaient justes. Cause : les deux frames de la capture ont pris 150 ms à    ║
# ║ elles deux, et `_time` avait déjà dépassé `RING_END` (350 ms) — l'anneau était né et mort entre ║
# ║ deux images. Ce n'est pas un artefact de harnais : la PREMIÈRE explosion d'un duel est celle    ║
# ║ qui compile les shaders de particules, donc celle qui produit la frame la plus longue — et      ║
# ║ c'est exactement celle où le joueur a le plus besoin d'apprendre le rayon de son arme.          ║
# ║ Une animation dont la lisibilité dépend de la cadence n'est pas une animation lisible. On       ║
# ║ garantit donc un nombre MINIMAL DE FRAMES affichées, quoi qu'il arrive à l'horloge.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const RING_MIN_FRAMES := 3

var _radius := 2.5
var _time := 0.0
var _ring_frames := 0
var _running := false
var _reduced := false

var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _crater: MeshInstance3D
var _crater_mat: StandardMaterial3D
var _core: GPUParticles3D
var _fountain: GPUParticles3D
var _smoke: GPUParticles3D


func _ready() -> void:
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	# --- LE FLASH : deux frames, et c'est tout. Plus long, ça devient un lampadaire. -------------
	var ball := SphereMesh.new()
	ball.radius = FLASH_RADIUS
	ball.height = FLASH_RADIUS * 2.0
	ball.radial_segments = 12
	ball.rings = 6
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.mesh = ball
	_flash.material_override = _emissive(COL_FLASH, 4.0)
	_flash.position = Vector3(0.0, 0.5, 0.0)
	add_child(_flash)

	# --- L'ANNEAU DE CHOC : LA pièce du lot ------------------------------------------------------
	# ⚠️ Un TORE PLAT posé au sol, et non un disque : un disque plein masquerait la boue et les
	# pieds de la cible pendant 0,35 s — c'est-à-dire pile pendant qu'on cherche à voir si on a
	# touché. Un anneau montre sa FRONTIÈRE, ce qui est exactement l'information à transmettre.
	# ⚠️ Son rayon EXTÉRIEUR à l'instant final vaut `_radius` au mètre près : c'est l'invariant §C.1.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 32
	ring.ring_segments = 8
	_ring = MeshInstance3D.new()
	_ring.name = "ShockRing"
	_ring.mesh = ring
	_ring_mat = _emissive(COL_RING, 2.2)
	# ╔═ ⚠️⚠️ L'ANNEAU SE VOIT À TRAVERS LES SACS — MESURÉ, ET C'EST LA MOITIÉ DU LOT ════════════╗
	# ║ La sonde `probe_trench_grenade` a rendu « aucun pixel ne change » sur une explosion posée   ║
	# ║ dans la tranchée adverse : la ligne de vue qui rase l'arête du parapet d'en face coupe à    ║
	# ║ **1,194 m** au plan des soldats, donc TOUT ce qui se passe au sol de cette tranchée est     ║
	# ║ occulté depuis un œil debout. L'anneau de choc — la pièce qui porte le rayon d'action, la   ║
	# ║ raison d'être du lot — n'était vu par personne.                                             ║
	# ║ ⚠️ Le FEU, la TERRE et la FUMÉE gardent leur test de profondeur : eux sont physiques, et     ║
	# ║ voir des flammes À TRAVERS un mur de sacs se lirait comme un défaut d'affichage. La fumée    ║
	# ║ monte de toute façon au-dessus du parapet — c'est elle qui raconte « ça a explosé là-bas ». ║
	# ║ Seul l'anneau, qui est une INFORMATION et non une matière, s'affranchit de l'occultation.    ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	_ring_mat.no_depth_test = true
	_ring_mat.render_priority = 8
	_ring.material_override = _ring_mat
	_ring.position = Vector3(0.0, 0.05, 0.0)
	add_child(_ring)

	# --- LE CRATÈRE : un disque assombri, fondu lent. Il fait DURER la trace du lancer. ----------
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 24
	_crater = MeshInstance3D.new()
	_crater.name = "Crater"
	_crater.mesh = disc
	_crater_mat = StandardMaterial3D.new()
	_crater_mat.albedo_color = Color(0.10, 0.08, 0.06, 0.75)
	_crater_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crater_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crater_mat.disable_fog = true
	_crater.material_override = _crater_mat
	_crater.position = Vector3(0.0, 0.03, 0.0)
	add_child(_crater)

	# --- LE CŒUR : la boule de feu, additive et très brève ---------------------------------------
	_core = _emitter("Core", 14, CORE_END, 0.22, COL_FIRE, true)
	var core_process := ParticleProcessMaterial.new()
	core_process.direction = Vector3(0.0, 1.0, 0.0)
	core_process.spread = 180.0
	core_process.initial_velocity_min = 1.5
	core_process.initial_velocity_max = 4.5
	core_process.gravity = Vector3.ZERO
	core_process.scale_min = 1.0
	core_process.scale_max = 2.4
	core_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	core_process.emission_sphere_radius = 0.25
	_core.process_material = core_process

	# --- LA FONTAINE DE TERRE : gravité RÉELLE, retombée VISIBLE ---------------------------------
	# ⚠️ La gravité n'est pas un réglage esthétique ici : c'est elle qui donne l'échelle. Des mottes
	# qui montent et retombent en 0,6 s disent « une explosion de cette taille-là » sans un chiffre.
	_fountain = _emitter("Fountain", 36, FOUNTAIN_END - FOUNTAIN_START, 0.10, COL_MUD, false)
	var mud_process := ParticleProcessMaterial.new()
	mud_process.direction = Vector3(0.0, 1.0, 0.0)
	mud_process.spread = 42.0
	mud_process.initial_velocity_min = 3.0
	mud_process.initial_velocity_max = 7.0
	mud_process.gravity = Vector3(0.0, -9.8, 0.0)
	mud_process.scale_min = 0.5
	mud_process.scale_max = 1.6
	mud_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mud_process.emission_sphere_radius = 0.35
	_fountain.process_material = mud_process

	# --- LA FUMÉE : lente, large, accordée à la dérive de la brume --------------------------------
	_smoke = _emitter("Smoke", 10, SMOKE_END - SMOKE_START, 0.9, COL_SMOKE, false)
	var smoke_process := ParticleProcessMaterial.new()
	smoke_process.direction = Vector3(0.25, 1.0, 0.0)
	smoke_process.spread = 26.0
	smoke_process.initial_velocity_min = 0.5
	smoke_process.initial_velocity_max = 1.3
	smoke_process.gravity = Vector3(0.15, 0.25, 0.0)   # elle MONTE et dérive, elle ne retombe pas
	smoke_process.scale_min = 1.0
	smoke_process.scale_max = 2.8
	smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_process.emission_sphere_radius = 0.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.55))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	smoke_process.color_ramp = ramp
	_smoke.process_material = smoke_process


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# La leçon du ciel (§8.140) : tout ce qui doit garder sa couleur s'exempte de la brume.
	m.disable_fog = true
	return m


func _emitter(node_name: String, amount: int, lifetime: float, quad: float, color: Color,
		additive: bool) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.name = node_name
	node.amount = maxi(1, amount)
	node.lifetime = maxf(0.05, lifetime)
	node.one_shot = true
	node.emitting = false
	node.explosiveness = 1.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(quad, quad)
	node.draw_pass_1 = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.surface_set_material(0, mat)
	add_child(node)
	return node


# =================================================================================================
# API — l'appelant pose le point, le rayon RÉEL, et le confort
# =================================================================================================
func set_reduced_motion(reduced: bool) -> void:
	_reduced = reduced


func is_busy() -> bool:
	return _running


# ⚠️ `radius` VIENT DU REGISTRE SERVEUR (`rules.grenade.radius_m`) et de nulle part ailleurs.
# C'est CE paramètre qui rend le §C.1 mécanique plutôt que déclaratif.
func play(at: Vector3, radius: float) -> void:
	_radius = maxf(0.1, radius)
	global_position = at
	_time = 0.0
	_ring_frames = 0
	_running = true
	visible = true
	set_process(true)
	# `reduced_motion` : on coupe le SPECTACLE, jamais l'INFORMATION. L'anneau reste — posé
	# directement au rayon final, immobile — parce qu'il porte la zone de dégâts. Le reste s'éteint.
	if _reduced:
		_core.emitting = false
		_fountain.emitting = false
		_smoke.emitting = false
		_ring.scale = Vector3(_radius, 1.0, _radius)
		return
	_core.restart()
	_fountain.restart()
	_smoke.restart()


func _process(delta: float) -> void:
	if not _running:
		return
	_time += delta
	if _time >= TOTAL:
		_running = false
		visible = false
		set_process(false)
		return

	# --- FLASH : allumé deux frames, puis plus jamais de la séquence -----------------------------
	_flash.visible = _time <= FLASH_END

	# --- ANNEAU : de 0 au RAYON EXACT, PUIS extinction SUR PLACE ---------------------------------
	# ⚠️ La progression est en RACINE du temps : un anneau linéaire part trop lentement pour se lire
	# comme un souffle. La racine donne le départ brusque qu'a une onde de choc.
	# ╔═ ⚠️⚠️ LA CROISSANCE FINIT AVANT LE FONDU, ET CE N'EST PAS UN DÉTAIL DE COURBE ═══════════╗
	# ║ Premier montage : l'anneau grandissait pendant toute la durée ET s'effaçait sur le dernier ║
	# ║ tiers. Il atteignait donc son rayon exact au moment précis où son alpha valait ZÉRO : la    ║
	# ║ seule image qui porte l'information — le cercle à la taille de la zone — n'était JAMAIS     ║
	# ║ montrée. Pire, une frame longue (30 ms de hoquet) pouvait faire sauter l'anneau directement ║
	# ║ de 80 % à l'extinction, et le harnais l'a attrapé : il mesurait 1,00 m pour 2,50 attendus.  ║
	# ║ La croissance s'achève donc à 70 % de la durée, et les 30 % restants sont un fondu SUR      ║
	# ║ PLACE, au rayon plein. Le joueur voit le cercle à sa vraie taille pendant ~105 ms — c'est    ║
	# ║ court, et c'est très au-dessus du seuil de lecture.                                         ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	if _reduced:
		_ring.visible = _time <= SMOKE_END
		_ring_mat.albedo_color.a = 0.85
	elif _time <= RING_END or _ring_frames < RING_MIN_FRAMES:
		var grow_end: float = RING_END * 0.7
		var t: float = clampf(_time / grow_end, 0.0, 1.0)
		var grown: float = _radius * sqrt(t)
		_ring.visible = true
		_ring_frames += 1
		_ring.scale = Vector3(maxf(0.01, grown), 1.0, maxf(0.01, grown))
		# ⚠️⚠️ LE RATTRAPAGE TIENT AUSSI L'ALPHA À 1, ET C'EST LA MOITIÉ QUI MANQUAIT. Premier
		# correctif : on gardait l'anneau VISIBLE quelques frames de plus, mais son fondu, lui,
		# continuait de suivre l'horloge — la sonde a alors rendu « anneau visible = true, alpha =
		# 0,00 ». Un objet transparent et un objet caché produisent exactement la même image : on
		# avait déplacé le défaut, pas corrigé. Tant que l'anneau n'a pas été MONTRÉ le nombre de
		# frames voulu, il reste franc ; le fondu ne commence qu'après.
		if _ring_frames <= RING_MIN_FRAMES:
			_ring_mat.albedo_color.a = 1.0
		elif _time <= grow_end:
			_ring_mat.albedo_color.a = 1.0
		else:
			_ring_mat.albedo_color.a = lerpf(1.0, 0.0, clampf(
				(minf(_time, RING_END) - grow_end) / maxf(0.001, RING_END - grow_end), 0.0, 1.0))
	else:
		# ⚠️ On laisse l'échelle AU RAYON PLEIN en éteignant : c'est le dernier état connu, et c'est
		# celui qu'une lecture de recette doit trouver. Un anneau caché à 1,0 m dirait que la zone
		# faisait 1 m — exactement le genre de « vérité résiduelle » qui trompe un futur relecteur.
		_ring.scale = Vector3(_radius, 1.0, _radius)
		_ring.visible = false

	# --- CRATÈRE : posé au rayon dès la première frame, fondu très lent ---------------------------
	# Il porte le rayon LUI AUSSI : après l'anneau, c'est lui qui continue de dire « la zone était
	# là ». Un joueur qui arrive en retard sur le champ lit encore la portée de l'arme.
	_crater.visible = true
	_crater.scale = Vector3(_radius, 1.0, _radius)
	_crater_mat.albedo_color.a = 0.75 * clampf(1.0 - _time / CRATER_END, 0.0, 1.0)


# LECTURES — réservées au harnais de recette (l'invariant §C.1 se VÉRIFIE, il ne se déclare pas).
func ring_world_radius() -> float:
	return _ring.scale.x if _ring != null else 0.0


func crater_world_radius() -> float:
	return _crater.scale.x if _crater != null else 0.0


func elapsed() -> float:
	return _time
