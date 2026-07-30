extends Node

# =============================================================================
# CARTE VIVANTE (§8.122, LOT D) — orchestrateur des deux calques d'ambiance du plateau
# =============================================================================
# Le plateau cesse d'être une carte d'état-major inerte : des cendres dérivent, les territoires
# récemment conquis FUMENT, chaque belligérant entretient un feu de camp sur sa plus grosse
# garnison, l'orage claque dans la zone radioactive et des oiseaux traversent la carte.
#
# CE SCRIPT EST UNE VUE PURE (Règle d'Or §6.1) : il ne lit JAMAIS GameState. Tout lui arrive par
# `refresh(ctx)` — c'est board.gd qui résout propriétaires, garnisons et couleurs (source unique
# get_player_color), dans la MÊME passe que ses shaders. Aucun `_process` par territoire, aucune
# allocation par frame : tout est piloté par le refresh d'état et par trois Timers.
#
# ⚠️ BUDGET PARTICULES (critère de recette) : ASH + POOL×FUMÉE + CAMPS×BRAISES doit rester
# strictement sous PARTICLE_BUDGET. Le harnais `tools/test_ambient_layer.tscn` le vérifie.

# --- Cendres globales (calque ARRIÈRE) : réglages repris du splash de titre (§8.63). ---
const ASH_AMOUNT := 40
const ASH_LIFETIME := 9.0
const ASH_ALPHA := 0.15                       # PLAFOND : au-delà, la carte se voile
const ASH_COLOR := Color(0.62, 0.72, 0.78)    # gris-cyan (charte §2)

# --- Fumées de guerre (calque AVANT) : un émetteur par conquête RÉCENTE. ---
const SMOKE_POOL_MAX := 10
const SMOKE_AMOUNT_FRESH := 24                # conquête du round COURANT
const SMOKE_AMOUNT_AGED := 12                 # round - 1
const SMOKE_MAX_AGE := 2                      # round - 2 : extinction (retour au pool)
const SMOKE_LIFETIME := 3.2
const SMOKE_COLOR := Color(0.16, 0.17, 0.18, 0.55)

# --- Feux de camp de faction (calque AVANT) : la « capitale » de chaque joueur vivant. ---
const CAMP_MAX := 6                           # 6 joueurs maximum par partie
const CAMP_AMOUNT := 8
const CAMP_LIFETIME := 1.8
const CAMP_ALPHA := 0.5

# --- Éclairs de zone (calque AVANT). ---
const LIGHTNING_MIN_S := 8.0
const LIGHTNING_MAX_S := 15.0
const LIGHTNING_FLASH_S := 0.25               # aller-retour complet
const LIGHTNING_COLOR := Color(0.72, 1.0, 0.5, 0.30)   # blanc-vert, alpha PLAFONNÉ à 0,30

# --- Nuée d'oiseaux (calque AVANT) : pure décoration, la première chose qu'on sacrifie. ---
const BIRDS_MIN_S := 60.0
const BIRDS_MAX_S := 90.0
const BIRDS_COUNT := 5
const BIRDS_CROSS_MIN_S := 6.0
const BIRDS_CROSS_MAX_S := 8.0
const BIRD_SIZE := 8.0
const BIRD_COLOR := Color(0.10, 0.12, 0.14, 0.75)
const BIRD_WAVE_AMPLITUDE := 14.0             # oscillation verticale (px)
const BIRD_WAVE_CYCLES := 3.0                 # nombre d'ondulations sur la traversée

# Garde-fou de performance : total de particules GPU simultanées, toutes sources confondues.
const PARTICLE_BUDGET := 500

var _back: Node2D = null
var _front: Node2D = null
var _board: Node = null                       # pour flash_territory_color (éclairs) — jamais l'état
var _board_rect := Rect2()

var _enabled := true
# Vrai pendant qu'un combat s'anime : on ne lance PAS d'oiseaux par-dessus le spectacle principal.
var _busy := false

var _ash: GPUParticles2D = null
# Pool de fumées : émetteurs recyclés, jamais réalloués. tid -> index dans _smoke_pool.
var _smoke_pool: Array = []
var _smoke_by_tid: Dictionary = {}
# tid -> round de la conquête (purgé au refresh, cf. SMOKE_MAX_AGE).
var _smoke_rounds: Dictionary = {}
# File d'usage du pool (le plus ancien en tête) — recyclage quand le pool est plein.
var _smoke_order: Array = []

var _camps: Array = []                        # CAMP_MAX émetteurs pré-alloués, masqués par défaut
var _contaminated: Array = []                 # copie locale de la zone (pour l'éclair)

var _lightning_timer: Timer = null
var _birds_timer: Timer = null
var _rng := RandomNumberGenerator.new()

# Nuée en vol : nœuds + géométrie de la trajectoire, mémorisés pour que `_move_flock` n'alloue rien.
var _flock: Array = []
var _flock_p0 := Vector2.ZERO
var _flock_p1 := Vector2.ZERO
var _flock_p2 := Vector2.ZERO


# Monté par board.gd (_setup_ambient_layer) : les deux calques déclarés dans board.tscn + une
# référence au plateau (pour le flash d'éclair) + le rect à couvrir par les cendres.
func setup(back: Node2D, front: Node2D, board_ref: Node, board_rect: Rect2) -> void:
	_back = back
	_front = front
	_board = board_ref
	_board_rect = board_rect
	_rng.randomize()
	_build_ash()
	_build_smoke_pool()
	_build_camps()
	_build_timers()
	if not SettingsManager.comfort_changed.is_connected(_on_comfort_changed):
		SettingsManager.comfort_changed.connect(_on_comfort_changed)
	_apply_settings()


# Réglage `living_map` (défaut ON) ET `reduced_motion` (qui le FORCE à OFF : la carte vivante n'est
# que du mouvement, il n'y a rien à en figer). On lit les deux ici plutôt que d'écrire le forçage
# dans SettingsManager — le joueur retrouve son choix intact s'il coupe `reduced_motion`.
func _apply_settings() -> void:
	set_enabled(bool(SettingsManager.get_comfort("living_map"))
		and not bool(SettingsManager.get_comfort("reduced_motion")))

func _on_comfort_changed(key: String, _value) -> void:
	if key == "living_map" or key == "reduced_motion":
		_apply_settings()


# Coupe TOUT : nœuds invisibles, émetteurs à l'arrêt (un `visible=false` seul laisserait les
# particules tourner — invisibles mais payées), timers stoppés, nuée en vol libérée.
func set_enabled(on: bool) -> void:
	_enabled = on
	if _back != null and is_instance_valid(_back):
		_back.visible = on
	if _front != null and is_instance_valid(_front):
		_front.visible = on
	if _ash != null and is_instance_valid(_ash):
		_ash.emitting = on
	for p in _smoke_pool:
		if is_instance_valid(p) and not on:
			p.emitting = false
	for p in _camps:
		if is_instance_valid(p) and not on:
			p.emitting = false
	if not on:
		_clear_flock()
	_set_timer(_lightning_timer, on)
	_set_timer(_birds_timer, on)
	if on:
		# Ré-activation à chaud (le joueur décoche reduced_motion en pleine partie) : on repeint
		# l'ambiance depuis le dernier contexte connu au lieu d'attendre le prochain état.
		_refresh_smoke()
		_refresh_camps_visibility()


# Verrou d'animation de combat, poussé par main.gd via board.set_ambient_busy(). Sert UNIQUEMENT
# aux oiseaux : on ne vole jamais une frame (ni un regard) au spectacle principal.
func set_busy(v: bool) -> void:
	_busy = v


# =========================================================
# Refresh d'ambiance — appel UNIQUE depuis board.generate_board()
# =========================================================
# ctx = {
#   "round": int,
#   "contaminated": Array[String],
#   "capitals": Array[{ "tid": String, "color": Color }],   # une par joueur vivant
# }
func refresh(ctx: Dictionary) -> void:
	_contaminated = ctx.get("contaminated", []) if typeof(ctx.get("contaminated")) == TYPE_ARRAY else []
	_purge_smoke(int(ctx.get("round", 0)))
	_refresh_smoke()
	_refresh_camps(ctx.get("capitals", []) if typeof(ctx.get("capitals")) == TYPE_ARRAY else [])


# =========================================================
# 1) CENDRES GLOBALES (calque ARRIÈRE)
# =========================================================
func _build_ash() -> void:
	if _back == null or not is_instance_valid(_back):
		return
	_ash = GPUParticles2D.new()
	_ash.name = "Ash"
	_ash.amount = ASH_AMOUNT
	_ash.lifetime = ASH_LIFETIME
	_ash.preprocess = ASH_LIFETIME * 0.5     # la carte est déjà « habitée » à l'ouverture
	_ash.local_coords = false
	_ash.texture = _make_dot(12)
	_ash.position = _board_rect.get_center()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(_board_rect.size.x * 0.5, _board_rect.size.y * 0.5, 1.0)
	# Dérive DIAGONALE lente : un vent d'ouest qui pousse la cendre vers le haut-droite.
	pm.direction = Vector3(0.6, -0.8, 0.0)
	pm.spread = 22.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 22.0
	pm.scale_min = 1.0
	pm.scale_max = 3.0
	pm.color = Color(ASH_COLOR, ASH_ALPHA)
	_ash.process_material = pm
	_back.add_child(_ash)


# =========================================================
# 2) FUMÉES DE GUERRE (calque AVANT) — pool recyclé
# =========================================================
func _build_smoke_pool() -> void:
	if _front == null or not is_instance_valid(_front):
		return
	for i in SMOKE_POOL_MAX:
		var p := _make_emitter("Smoke%d" % i, SMOKE_AMOUNT_FRESH, SMOKE_LIFETIME)
		var pm := p.process_material as ParticleProcessMaterial
		pm.direction = Vector3(0.0, -1.0, 0.0)
		pm.spread = 18.0
		pm.gravity = Vector3(0.0, -18.0, 0.0)
		pm.initial_velocity_min = 10.0
		pm.initial_velocity_max = 34.0
		pm.scale_min = 3.0
		pm.scale_max = 8.0
		pm.color = SMOKE_COLOR
		p.emitting = false
		p.visible = false
		_front.add_child(p)
		_smoke_pool.append(p)


# Signalé par board.gd depuis le flux d'évènements (là où part `conquest_flash`) : un territoire
# vient de changer de main, il fume. Ré-annoncer le MÊME territoire rafraîchit simplement son âge.
func on_conquest(tid: String, round_no: int) -> void:
	if tid == "":
		return
	_smoke_rounds[tid] = round_no
	if not _enabled:
		return
	_assign_smoke(tid)
	_refresh_smoke()


# Purge par ANCIENNETÉ : au-delà de SMOKE_MAX_AGE rounds, le territoire ne fume plus.
func _purge_smoke(current_round: int) -> void:
	for tid in _smoke_rounds.keys():
		if current_round - int(_smoke_rounds[tid]) >= SMOKE_MAX_AGE:
			_smoke_rounds.erase(tid)
			_release_smoke(tid)


# Attribue (ou recycle) un émetteur du pool à un territoire. Pool plein → on reprend le PLUS ANCIEN
# (file `_smoke_order`) : la fumée la plus récente est toujours celle qu'on voit.
func _assign_smoke(tid: String) -> void:
	if _smoke_by_tid.has(tid):
		_smoke_order.erase(tid)
		_smoke_order.append(tid)
		return
	if _smoke_by_tid.size() >= _smoke_pool.size():
		if _smoke_order.is_empty():
			return
		_release_smoke(str(_smoke_order[0]))
	# Premier émetteur libre.
	var used := {}
	for k in _smoke_by_tid:
		used[int(_smoke_by_tid[k])] = true
	for i in _smoke_pool.size():
		if not used.has(i):
			_smoke_by_tid[tid] = i
			_smoke_order.append(tid)
			return


func _release_smoke(tid: String) -> void:
	if not _smoke_by_tid.has(tid):
		return
	var idx := int(_smoke_by_tid[tid])
	_smoke_by_tid.erase(tid)
	_smoke_order.erase(tid)
	if idx >= 0 and idx < _smoke_pool.size() and is_instance_valid(_smoke_pool[idx]):
		_smoke_pool[idx].emitting = false
		_smoke_pool[idx].visible = false


# Repositionne / redimensionne les panaches actifs. Le nombre de particules DÉCROÎT avec l'âge :
# une conquête du round courant fume fort, celle du round précédent s'éteint doucement.
func _refresh_smoke() -> void:
	if not _enabled or _board == null or not is_instance_valid(_board):
		return
	var newest := 0
	for tid in _smoke_rounds:
		newest = maxi(newest, int(_smoke_rounds[tid]))
	for tid in _smoke_by_tid:
		var idx := int(_smoke_by_tid[tid])
		if idx < 0 or idx >= _smoke_pool.size() or not is_instance_valid(_smoke_pool[idx]):
			continue
		var p: GPUParticles2D = _smoke_pool[idx]
		var pos: Vector2 = _board.get_territory_position(str(tid))
		if pos == Vector2.INF:
			p.emitting = false
			p.visible = false
			continue
		p.position = pos
		var age: int = newest - int(_smoke_rounds.get(tid, newest))
		p.amount = SMOKE_AMOUNT_FRESH if age <= 0 else SMOKE_AMOUNT_AGED
		p.visible = true
		p.emitting = true


# =========================================================
# 3) FEUX DE CAMP DE FACTION (calque AVANT)
# =========================================================
func _build_camps() -> void:
	if _front == null or not is_instance_valid(_front):
		return
	for i in CAMP_MAX:
		var p := _make_emitter("Camp%d" % i, CAMP_AMOUNT, CAMP_LIFETIME)
		var pm := p.process_material as ParticleProcessMaterial
		pm.direction = Vector3(0.0, -1.0, 0.0)
		pm.spread = 30.0
		pm.gravity = Vector3(0.0, -30.0, 0.0)
		pm.initial_velocity_min = 8.0
		pm.initial_velocity_max = 26.0
		pm.scale_min = 1.5
		pm.scale_max = 3.5
		p.emitting = false
		p.visible = false
		_front.add_child(p)
		_camps.append(p)


# `capitals` = [{tid, color}] résolu par board.gd (garnison la plus grosse, égalité tranchée par
# l'ordre alphabétique du tid → stable d'un refresh à l'autre). Les capitales BOUGENT avec la
# partie : c'est voulu, le front se raconte tout seul.
func _refresh_camps(capitals: Array) -> void:
	for i in _camps.size():
		var p: GPUParticles2D = _camps[i]
		if not is_instance_valid(p):
			continue
		if not _enabled or i >= capitals.size() or _board == null or not is_instance_valid(_board):
			p.emitting = false
			p.visible = false
			continue
		var entry = capitals[i]
		var pos: Vector2 = _board.get_territory_position(str(entry.get("tid", "")))
		if pos == Vector2.INF:
			p.emitting = false
			p.visible = false
			continue
		var col: Color = entry.get("color", Color.WHITE)
		p.position = pos
		var pm := p.process_material as ParticleProcessMaterial
		pm.color = Color(col.r, col.g, col.b, CAMP_ALPHA)
		p.visible = true
		p.emitting = true

# Ré-allumage après un set_enabled(true) : on ne connaît plus les capitales (elles viennent du ctx),
# on se contente de rendre visibles celles qui tournaient déjà — le prochain état les repositionne.
func _refresh_camps_visibility() -> void:
	for p in _camps:
		if is_instance_valid(p) and p.emitting:
			p.visible = true


# =========================================================
# 4) ÉCLAIRS DE ZONE + 5) NUÉE D'OISEAUX (calque AVANT)
# =========================================================
func _build_timers() -> void:
	_lightning_timer = Timer.new()
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_on_lightning_tick)
	add_child(_lightning_timer)
	_birds_timer = Timer.new()
	_birds_timer.one_shot = true
	_birds_timer.timeout.connect(_on_birds_tick)
	add_child(_birds_timer)

func _set_timer(t: Timer, on: bool) -> void:
	if t == null or not is_instance_valid(t):
		return
	if on:
		if t == _lightning_timer:
			t.start(_rng.randf_range(LIGHTNING_MIN_S, LIGHTNING_MAX_S))
		else:
			t.start(_rng.randf_range(BIRDS_MIN_S, BIRDS_MAX_S))
	else:
		t.stop()


# ORAGE DANS LA ZONE : un territoire contaminé au hasard s'illumine d'un blanc-vert bref, doublé
# d'une détonation LOINTAINE. Le flash passe par board.flash_territory_color (le même Polygon2D
# de remplissage que `flash_territory`) : depuis l'overlay « vraies frontières » §8.51, il n'y a
# plus de matériau `toxic_pulsation` par territoire à faire pulser — c'est le repli prévu au
# cahier des charges, et il a l'avantage d'épouser la vraie côte peinte.
func _on_lightning_tick() -> void:
	if _enabled and not _contaminated.is_empty() and _board != null and is_instance_valid(_board):
		var tid := str(_contaminated[_rng.randi_range(0, _contaminated.size() - 1)])
		_board.flash_territory_color(tid, LIGHTNING_COLOR, LIGHTNING_FLASH_S)
		AudioManager.play_sfx("thunder_far")
	_set_timer(_lightning_timer, _enabled)


# NUÉE D'OISEAUX : 5 triangles suivant une Bézier quadratique aléatoire, animés par UN SEUL Tween
# (aucun `_process`). Sautée si un combat s'anime — la carte doit se taire pendant le duel.
func _on_birds_tick() -> void:
	if _enabled and not _busy and _front != null and is_instance_valid(_front) and _flock.is_empty():
		_launch_flock()
	_set_timer(_birds_timer, _enabled)


func _launch_flock() -> void:
	var r := _board_rect
	# Traversée d'un bord vertical à l'autre, à une hauteur aléatoire, avec un point de contrôle
	# décalé → jamais deux passages identiques.
	var left_to_right := _rng.randf() < 0.5
	var y0 := r.position.y + r.size.y * _rng.randf_range(0.15, 0.75)
	var y1 := r.position.y + r.size.y * _rng.randf_range(0.15, 0.75)
	_flock_p0 = Vector2(r.position.x - 60.0 if left_to_right else r.end.x + 60.0, y0)
	_flock_p2 = Vector2(r.end.x + 60.0 if left_to_right else r.position.x - 60.0, y1)
	_flock_p1 = Vector2(r.get_center().x, r.position.y + r.size.y * _rng.randf_range(0.05, 0.85))
	for i in BIRDS_COUNT:
		var bird := Polygon2D.new()
		bird.polygon = PackedVector2Array([
			Vector2(-BIRD_SIZE, -BIRD_SIZE * 0.5),
			Vector2(BIRD_SIZE, 0.0),
			Vector2(-BIRD_SIZE, BIRD_SIZE * 0.5)])
		bird.color = BIRD_COLOR
		if not left_to_right:
			bird.scale = Vector2(-1.0, 1.0)
		_front.add_child(bird)
		_flock.append(bird)
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(_move_flock, 0.0, 1.0,
		_rng.randf_range(BIRDS_CROSS_MIN_S, BIRDS_CROSS_MAX_S))
	tw.tween_callback(_clear_flock)


# Positionne la nuée le long de la Bézier. Chaque oiseau porte un décalage de phase (traînée en V
# décalée) et une ondulation verticale propre. Aucune allocation : Vector2 est un type VALEUR.
func _move_flock(t: float) -> void:
	for i in _flock.size():
		var bird = _flock[i]
		if not is_instance_valid(bird):
			continue
		var lag := clampf(t - float(i) * 0.035, 0.0, 1.0)
		var u := 1.0 - lag
		var pos: Vector2 = _flock_p0 * (u * u) + _flock_p1 * (2.0 * u * lag) + _flock_p2 * (lag * lag)
		pos.y += sin((lag * BIRD_WAVE_CYCLES + float(i) * 0.4) * TAU) * BIRD_WAVE_AMPLITUDE
		bird.position = pos


func _clear_flock() -> void:
	for bird in _flock:
		if is_instance_valid(bird):
			bird.queue_free()
	_flock.clear()


# =========================================================
# Fabriques
# =========================================================
# Émetteur GPU commun. `local_coords = false` sur TOUS (exigence du cahier des charges) : les
# particules déjà émises restent dans le monde quand l'émetteur se déplace — sinon un panache
# « téléporterait » avec sa capitale au refresh suivant.
func _make_emitter(node_name: String, amount: int, lifetime: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.texture = _make_dot(10)
	var pm := ParticleProcessMaterial.new()
	# Fondu de sortie : sans rampe, les particules DISPARAISSENT net en fin de vie (effet « clic »).
	# Testé défensivement — si la propriété change de nom dans une version future, on perd le fondu,
	# jamais le rendu.
	if "color_ramp" in pm:
		pm.color_ramp = _make_fade_ramp()
	p.process_material = pm
	return p


# Rampe alpha 1 → 0 (GradientTexture1D) appliquée sur la durée de vie des particules.
func _make_fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return tex


# Point doux (même recette que le splash de titre) — évite de dépendre d'un asset image.
func _make_dot(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := float(d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)


# Total de particules GPU alloué par ce calque — exposé pour le harnais de recette (budget ≤ 500).
static func particle_total() -> int:
	return ASH_AMOUNT + SMOKE_POOL_MAX * SMOKE_AMOUNT_FRESH + CAMP_MAX * CAMP_AMOUNT
