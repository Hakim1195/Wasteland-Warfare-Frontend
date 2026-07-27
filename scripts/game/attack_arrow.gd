extends Node2D

# FLÈCHE DE GUERRE + MINI-EXPLOSION (REFONTE UI ARÈNE, lot D).
#
# POURQUOI : jusqu'ici, TOUS les combats — y compris ceux entre deux adversaires — ouvraient le
# Split-Screen VS plein écran (ou un bandeau compact peu lisible). Contre 5 bots, l'écran passait
# son temps en plein écran pour des duels qui ne concernent pas le joueur. Désormais :
#   • MES combats (attaquant OU défenseur)  → Split-Screen VS plein écran (inchangé, moment fort) ;
#   • les combats des AUTRES                → cette flèche IN-BOARD + explosion + chiffres.
#
# Vit dans le SubViewport du plateau (coordonnées MONDE, PAS dans le HUD) : instanciée par main.gd
# en enfant de `Board`, elle se supprime toute seule à la fin (queue_free garanti même si la partie
# se termine pendant l'animation). Vue PURE (Règle d'Or §6.1) : aucune logique de jeu, on ne fait
# que raconter un `attack_result` déjà résolu par le serveur.

# Émis quand l'animation complète est terminée (tracé + impact + retombées) : main.gd enchaîne.
signal finished

# --- Géométrie du tracé (aucune valeur en dur ailleurs) ---
const BODY_WIDTH := 14.0          # épaisseur du corps de la flèche (px monde)
const OUTLINE_EXTRA := 6.0        # sur-épaisseur du liseré sombre (lisibilité sur toute carte)
const ARC_RATIO := 0.18           # hauteur de l'arc, en fraction de la distance source→cible
const CURVE_SAMPLES := 28         # points échantillonnés sur la Bézier quadratique
const HEAD_LENGTH := 46.0         # longueur de la tête triangulaire
const HEAD_WIDTH := 34.0          # demi-largeur de la tête
const CHEVRON_COUNT := 4          # chevrons ❯ qui défilent le long du tracé (ADN de la charte)
const CHEVRON_SIZE := 11.0

# --- Cadence (constantes nommées — le mode « condensé » divise tout par CONDENSED_FACTOR) ---
const DRAW_TIME := 0.45           # tracé progressif de la flèche
const IMPACT_TIME := 0.6          # flash + anneaux + particules
const HOLD_TIME := 0.25           # temps de lecture des chiffres avant disparition
const FADE_TIME := 0.25
const CONDENSED_FACTOR := 2.0     # mode rapide / chaîne de ré-assaut → ~0,7 s au total

# --- Charte « Warzone Command » (§2) ---
const DANGER := Color("d6453f")
const GOLD := Color("e0b249")
const OUTLINE := Color(0.02, 0.03, 0.04, 0.85)
const HERO_VIOLET := Color("8c6bd9")

# Amplitude (px monde) et durée du micro-screen-shake de la caméra tactique à l'impact.
const SHAKE_AMPLITUDE := 7.0
const SHAKE_TIME := 0.15

var _curve: PackedVector2Array = PackedVector2Array()
var _outline: Line2D = null
var _core: Line2D = null
var _head: Polygon2D = null
var _chevrons: Array = []
var _speed := 1.0

func _ready() -> void:
	# Le plateau reste cliquable pendant l'animation (la flèche n'est qu'un calque narratif).
	z_index = 40
	top_level = true   # coordonnées MONDE, indépendantes du parent (le Board peut être décalé)

# Point d'entrée. `from`/`to` = positions MONDE des centroïdes (board.get_territory_position).
# `color` = couleur PLATEAU de l'ATTAQUANT. `info` = retombées déjà résolues par main.gd :
#   { atk_losses:int, def_losses:int, hero_damage:int, conquered:bool, marks:Array[String] }
# `condensed` = version accélérée (réglage « rapide » ou chaîne de ré-assaut).
func play(from: Vector2, to: Vector2, color: Color, info: Dictionary, condensed: bool = false) -> void:
	_speed = CONDENSED_FACTOR if condensed else 1.0
	_build_curve(from, to)
	_build_arrow(color)
	# reduced_motion (E10 §8.82) : on garde le TRACÉ (l'information reste lisible) mais on coupe
	# les effets cinétiques (chevrons animés, particules, secousse).
	var still: bool = bool(SettingsManager.get_comfort("reduced_motion"))

	var draw_time := DRAW_TIME / _speed
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_progress, 0.0, 1.0, draw_time)
	if not still:
		_animate_chevrons(draw_time)
	await tw.finished

	_show_head(color)
	_impact(to, color, still)
	_spawn_numbers(from, to, info)
	await get_tree().create_timer(IMPACT_TIME / _speed).timeout
	await get_tree().create_timer(HOLD_TIME / _speed).timeout

	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, FADE_TIME / _speed)
	await fade.finished
	finished.emit()
	queue_free()

# =========================================================
# Construction
# =========================================================

# Bézier quadratique : point de contrôle décalé perpendiculairement au segment → léger arc.
func _build_curve(from: Vector2, to: Vector2) -> void:
	var dir := to - from
	var dist := dir.length()
	var perp := Vector2(-dir.y, dir.x).normalized() if dist > 0.001 else Vector2.UP
	var ctrl := (from + to) * 0.5 + perp * dist * ARC_RATIO
	# On s'arrête AVANT la cible : la tête triangulaire occupe les derniers pixels.
	var shortened := to - dir.normalized() * minf(HEAD_LENGTH * 0.8, dist * 0.25) if dist > 0.001 else to
	_curve = PackedVector2Array()
	for i in range(CURVE_SAMPLES + 1):
		var t := float(i) / float(CURVE_SAMPLES)
		var a := from.lerp(ctrl, t)
		var b := ctrl.lerp(shortened, t)
		_curve.append(a.lerp(b, t))

func _build_arrow(color: Color) -> void:
	_outline = Line2D.new()
	_outline.width = BODY_WIDTH + OUTLINE_EXTRA
	_outline.default_color = OUTLINE
	_outline.joint_mode = Line2D.LINE_JOINT_ROUND
	_outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_outline)

	_core = Line2D.new()
	_core.width = BODY_WIDTH
	_core.default_color = color
	_core.joint_mode = Line2D.LINE_JOINT_ROUND
	_core.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_core.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_core)

	for i in range(CHEVRON_COUNT):
		var ch := Polygon2D.new()
		ch.polygon = PackedVector2Array([
			Vector2(-CHEVRON_SIZE, -CHEVRON_SIZE), Vector2(CHEVRON_SIZE * 0.5, 0.0),
			Vector2(-CHEVRON_SIZE, CHEVRON_SIZE), Vector2(-CHEVRON_SIZE * 0.4, 0.0)])
		ch.color = Color(1, 1, 1, 0.75)
		ch.visible = false
		add_child(ch)
		_chevrons.append(ch)

# Tracé progressif : on ne conserve que les points jusqu'à `p` (0..1), le dernier interpolé.
func _set_progress(p: float) -> void:
	var total := _curve.size()
	if total < 2:
		return
	var exact := clampf(p, 0.0, 1.0) * float(total - 1)
	var last := int(floor(exact))
	var pts := PackedVector2Array()
	for i in range(last + 1):
		pts.append(_curve[i])
	if last < total - 1:
		pts.append(_curve[last].lerp(_curve[last + 1], exact - float(last)))
	_outline.points = pts
	_core.points = pts

# Chevrons qui remontent le tracé pendant le dessin (ADN angulaire de la charte §2).
func _animate_chevrons(duration: float) -> void:
	for i in range(_chevrons.size()):
		var ch: Polygon2D = _chevrons[i]
		ch.visible = true
		var offset := float(i) / float(maxi(_chevrons.size(), 1)) * 0.35
		var tw := create_tween().set_loops(2)
		tw.tween_method(func(t: float) -> void:
			_place_on_curve(ch, clampf(t - offset, 0.0, 1.0)), 0.0, 1.0, duration * 0.6)

func _place_on_curve(node: Node2D, t: float) -> void:
	if _curve.size() < 2:
		return
	var exact := clampf(t, 0.0, 1.0) * float(_curve.size() - 1)
	var idx := clampi(int(floor(exact)), 0, _curve.size() - 2)
	var pos := _curve[idx].lerp(_curve[idx + 1], exact - float(idx))
	node.position = pos
	node.rotation = (_curve[idx + 1] - _curve[idx]).angle()

# Tête triangulaire pleine, orientée sur la dernière tangente du tracé.
func _show_head(color: Color) -> void:
	if _curve.size() < 2:
		return
	_head = Polygon2D.new()
	_head.polygon = PackedVector2Array([
		Vector2(HEAD_LENGTH, 0.0), Vector2(-HEAD_LENGTH * 0.35, -HEAD_WIDTH),
		Vector2(-HEAD_LENGTH * 0.35, HEAD_WIDTH)])
	_head.color = color
	var tip := _curve[_curve.size() - 1]
	_head.position = tip
	_head.rotation = (tip - _curve[_curve.size() - 2]).angle()
	add_child(_head)
	for ch in _chevrons:
		if is_instance_valid(ch):
			ch.visible = false

# =========================================================
# Impact — flash radial, anneaux, particules, secousse
# =========================================================

func _impact(at: Vector2, color: Color, still: bool) -> void:
	AudioManager.play_sfx("explosion")
	var dur := IMPACT_TIME / _speed
	# Flash radial : disque plein qui gonfle et s'efface.
	var flash := Polygon2D.new()
	flash.polygon = _circle_points(30.0, 20)
	flash.color = Color(1.0, 0.92, 0.72, 0.9)
	flash.position = at
	add_child(flash)
	var ft := create_tween().set_parallel(true)
	ft.tween_property(flash, "scale", Vector2(2.6, 2.6), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ft.tween_property(flash, "modulate:a", 0.0, dur)
	# 2-3 anneaux d'onde de choc, décalés dans le temps.
	for i in range(3):
		var ring := Line2D.new()
		ring.points = _circle_points(26.0, 26)
		ring.closed = true
		ring.width = 4.0
		ring.default_color = DANGER if i % 2 == 0 else GOLD
		ring.position = at
		add_child(ring)
		var rt := create_tween().set_parallel(true)
		rt.tween_property(ring, "scale", Vector2(1.0 + 1.1 * float(i + 1), 1.0 + 1.1 * float(i + 1)),
			dur).set_delay(0.06 * float(i))
		rt.tween_property(ring, "modulate:a", 0.0, dur).set_delay(0.06 * float(i))
	if still:
		return
	add_child(_make_sparks(at, color))
	_shake_camera()

# Particules d'étincelles/fumée one-shot, teintées danger/or (charte §2).
func _make_sparks(at: Vector2, color: Color) -> GPUParticles2D:
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 12.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 120.0
	mat.initial_velocity_max = 420.0
	mat.gravity = Vector3(0, 260, 0)
	mat.damping_min = 40.0
	mat.damping_max = 120.0
	mat.scale_min = 1.5
	mat.scale_max = 5.0
	mat.color = DANGER.lerp(GOLD, 0.45)
	var p := GPUParticles2D.new()
	p.process_material = mat
	p.amount = 46
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 1.0
	p.position = at
	p.modulate = color.lerp(Color.WHITE, 0.4)
	p.emitting = true
	return p

# Micro-secousse de la caméra tactique — via `offset`, jamais `position` (le travelling de combat
# tween `position` : y toucher créerait un conflit de Tween et un saut de cadrage).
func _shake_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var tw := cam.create_tween()
	var steps := 5
	for i in range(steps):
		var amp := SHAKE_AMPLITUDE * (1.0 - float(i) / float(steps))
		tw.tween_property(cam, "offset",
			Vector2(randf_range(-amp, amp), randf_range(-amp, amp)), SHAKE_TIME / float(steps))
	tw.tween_property(cam, "offset", Vector2.ZERO, SHAKE_TIME / float(steps))

func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

# =========================================================
# Retombées lisibles — chiffres flottants au-dessus des deux territoires
# =========================================================

func _spawn_numbers(from: Vector2, to: Vector2, info: Dictionary) -> void:
	# Réglage damage_numbers (E10 §8.82) : les flotteurs de dégâts sont masquables.
	if not bool(SettingsManager.get_comfort("damage_numbers")):
		return
	var atk_losses := int(info.get("atk_losses", 0))
	var def_losses := int(info.get("def_losses", 0))
	if atk_losses > 0:
		_float_label(from, "-%d" % atk_losses, DANGER)
	if def_losses > 0:
		_float_label(to, "-%d" % def_losses, DANGER)
	var hero_dmg := int(info.get("hero_damage", 0))
	if hero_dmg > 0:
		# SOUS la cible (et non à droite) : à droite, le flotteur chevauchait le « -N » des pertes.
		_float_label(to + Vector2(0, 74), tr("ARROW_HERO_DAMAGE_FMT") % hero_dmg, HERO_VIOLET, 28)
	# Marqueurs de pouvoirs déclenchés (lot E) : étiquettes COURTES (mêmes libellés que le Journal)
	# empilées au-dessus de la cible — la phrase complète vit dans le toast de pouvoir du HUD.
	var marks = info.get("marks", [])
	if typeof(marks) == TYPE_ARRAY:
		var k := 0
		for m in marks:
			_float_label(to + Vector2(0, -52.0 - 30.0 * float(k)), str(m), GOLD, 24)
			k += 1

func _float_label(at: Vector2, text: String, col: Color, font_size: int = 34) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	lbl.position = at + Vector2(-16, -74)
	var tw := lbl.create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 58.0, 1.0 / _speed)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0 / _speed)
