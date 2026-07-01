extends Control
##
## Splash Eroïque animé — NOUVELLE ouverture spectaculaire (R6 ; option C, choisie par l'utilisateur).
##
## Scène ONE-SHOT lancée par le bootloader (après le version-check) : fond hex-grid + radar (shader
## `title_hexgrid`), cendres cyan, le logo qui se RÉVÈLE entre deux chevrons qui glissent, un balayage
## lumineux, une ligne de statut tactique dactylographiée, puis l'invite « appuyez sur une touche » →
## transition vers l'auth. Règle d'Or §6.1 : Vue pure (aucun réseau ; le boot a déjà tout fait).
## 100% code + shader, charte « Warzone Command » §2 (gunmetal / cyan, angulaire, condensé MAJUSCULE).

const NEXT_SCENE := "res://scenes/ui/auth_screen.tscn"
const AUTO_ADVANCE_DELAY := 9.0   # garde-fou : on enchaîne seul si aucune entrée
const INPUT_GUARD := 0.35         # délai avant d'accepter une entrée (évite un skip accidentel)

const HEX_SHADER := preload("res://shaders/title_hexgrid.gdshader")
const LOGO_SCENE := preload("res://scenes/ui/ww_logo.tscn")  # wordmark typographique (police du jeu)
const MARK_TEX := preload("res://assets/images/logo_mark.svg")        # emblème biohazard — HÉROS du splash (§8.63)
const GLOW_TEX := preload("res://assets/images/logo_mark_glow.png")   # halo néon (révélé puis pulsé)

const GUNMETAL := Color(0.058824, 0.07451, 0.094118)
const ACCENT := Color(0.211765, 0.772549, 0.85098)   # cyan tactique
const MUTED := Color(0.541176, 0.592157, 0.647059)   # acier

var _font: SystemFont
var _can_advance := false
var _advancing := false
var _status_full := ""
var _status_label: Label
var _prompt_label: Label
var _emblem_glow: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	var vp := get_viewport_rect().size

	_build_background()
	_build_ash(vp)
	var emblem := _build_emblem(vp)
	var logo := _build_logo(vp)
	var sweep := _build_sweep(vp)
	_build_chevrons(vp)
	_build_status()
	_build_prompt()

	# Dévoilé d'entrée (overlay du TransitionManager) si l'autoload est présent.
	var tm := get_node_or_null("/root/TransitionManager")
	if tm and tm.has_method("fade_in_only"):
		tm.fade_in_only()

	_run_reveal(logo, emblem, sweep, vp)

	# Garde d'entrée + auto-enchaînement (Timers enfants : libérés avec la scène → aucun
	# callback tardif sur un nœud détruit, contrairement à un `await` de timer).
	_one_shot_timer(INPUT_GUARD, func() -> void: _can_advance = true)
	_one_shot_timer(AUTO_ADVANCE_DELAY, _advance)


# --- Construction de la scène (Vue) ------------------------------------------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = GUNMETAL
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var hex := ColorRect.new()
	hex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = HEX_SHADER
	hex.material = mat
	add_child(hex)


func _build_ash(vp: Vector2) -> void:
	var ash := GPUParticles2D.new()
	ash.amount = 70
	ash.lifetime = 6.0
	ash.preprocess = 3.0
	ash.texture = _make_dot(12)
	ash.position = vp * 0.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(vp.x * 0.5 + 40.0, vp.y * 0.5 + 40.0, 1.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 35.0
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 16.0
	pm.scale_min = 1.0
	pm.scale_max = 2.5
	pm.color = Color(ACCENT, 0.45)
	ash.process_material = pm
	add_child(ash)


func _build_emblem(vp: Vector2) -> TextureRect:
	# Emblème biohazard GÉANT — HÉROS du splash (§8.63) : reveal (fondu + dézoom élastique) puis
	# halo néon pulsé. Marque vectorielle nette (SVG) + halo flou derrière, animés indépendamment.
	var em := minf(340.0, vp.y * 0.36)
	var cx := vp.x * 0.5
	var ey := vp.y * 0.5 - 132.0

	var gside := em * 1.8
	_emblem_glow = TextureRect.new()
	_emblem_glow.texture = GLOW_TEX
	_emblem_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem_glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem_glow.size = Vector2(gside, gside)
	_emblem_glow.position = Vector2(cx - gside * 0.5, ey - gside * 0.5)
	_emblem_glow.pivot_offset = Vector2(gside * 0.5, gside * 0.5)
	_emblem_glow.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(_emblem_glow)

	var mk := TextureRect.new()
	mk.texture = MARK_TEX
	mk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mk.size = Vector2(em, em)
	mk.position = Vector2(cx - em * 0.5, ey - em * 0.5)
	mk.pivot_offset = Vector2(em * 0.5, em * 0.5)
	mk.scale = Vector2(0.55, 0.55)
	mk.modulate = Color(1.0, 1.0, 1.0, 0.0)
	add_child(mk)
	return mk


func _build_logo(vp: Vector2) -> Control:
	# Wordmark typographique SEUL (l'emblème biohazard ci-dessus est désormais le héros §8.63) :
	# on coupe la petite marque interne et on glisse le wordmark SOUS l'emblème.
	var w := minf(640.0, vp.x * 0.68)
	var h := 170.0
	var cy_off := 124.0

	var logo: Control = LOGO_SCENE.instantiate()
	logo.title_size = 54
	logo.eyebrow_size = 20
	logo.show_mark = false
	logo.show_glow = false
	logo.spacing = 8
	logo.show_brackets = false
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.anchor_left = 0.5
	logo.anchor_top = 0.5
	logo.anchor_right = 0.5
	logo.anchor_bottom = 0.5
	logo.offset_left = -w * 0.5
	logo.offset_top = -h * 0.5 + cy_off
	logo.offset_right = w * 0.5
	logo.offset_bottom = h * 0.5 + cy_off
	logo.pivot_offset = Vector2(w * 0.5, h * 0.5)
	logo.scale = Vector2(1.1, 1.1)
	logo.modulate = Color(1.0, 1.0, 1.0, 0.0)  # révélé par le Tween
	add_child(logo)
	return logo


func _build_sweep(vp: Vector2) -> ColorRect:
	var sweep := ColorRect.new()
	sweep.color = Color(ACCENT, 0.0)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.size = Vector2(vp.x, 3.0)
	sweep.position = Vector2(0.0, vp.y * 0.22)
	add_child(sweep)
	return sweep


func _build_chevrons(vp: Vector2) -> void:
	var cy := vp.y * 0.5 + 92.0   # encadrent le wordmark (sous l'emblème)
	var cx := vp.x * 0.5
	_animate_chevron("❯❯", -160.0, cx - 320.0, cy)
	_animate_chevron("❮❮", vp.x + 160.0, cx + 250.0, cy)


func _animate_chevron(glyph: String, start_x: float, end_x: float, y: float) -> void:
	var l := Label.new()
	l.text = glyph
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 56)
	l.add_theme_color_override("font_color", ACCENT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.modulate = Color(1.0, 1.0, 1.0, 0.0)
	l.position = Vector2(start_x, y)
	add_child(l)
	var t := create_tween()
	t.tween_interval(0.1)
	t.tween_property(l, "position:x", end_x, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.9, 0.45)


func _build_status() -> void:
	_status_full = tr("SPLASH_STATUS")
	_status_label = Label.new()
	_status_label.add_theme_font_override("font", _font)
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.add_theme_color_override("font_color", ACCENT)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_status_label.anchor_left = 0.0
	_status_label.anchor_right = 1.0
	_status_label.anchor_top = 0.5
	_status_label.anchor_bottom = 0.5
	# Sous le wordmark (slab « WARFARE » bas ≈ +199 du centre) : on dégage la ligne de statut
	# pour qu'elle ne se superpose plus au logo (cf. §correctif lisibilité splash).
	_status_label.offset_top = 250.0
	_status_label.offset_bottom = 290.0
	add_child(_status_label)


func _build_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.text = tr("SPLASH_PRESS_KEY")
	_prompt_label.add_theme_font_override("font", _font)
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_color_override("font_color", MUTED)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.0)  # masqué jusqu'à la fin du reveal
	_prompt_label.anchor_left = 0.0
	_prompt_label.anchor_right = 1.0
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_top = -72.0
	_prompt_label.offset_bottom = -40.0
	add_child(_prompt_label)


# --- Orchestration de l'animation --------------------------------------------

func _run_reveal(logo: Control, emblem: TextureRect, sweep: ColorRect, vp: Vector2) -> void:
	# Emblème biohazard (HÉROS) : « sting » + fondu + dézoom élastique, halo qui monte puis PULSE.
	var te := create_tween()
	te.tween_interval(0.2)
	te.tween_callback(_play_sting)
	te.parallel().tween_property(emblem, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)
	te.parallel().tween_property(emblem, "scale", Vector2.ONE, 0.85).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	te.parallel().tween_property(_emblem_glow, "modulate:a", 0.95, 0.7).set_trans(Tween.TRANS_SINE)
	te.tween_callback(_start_emblem_pulse)

	# Wordmark : fondu + dézoom élastique, juste après l'emblème (pivot centré).
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_property(logo, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(logo, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Balayage lumineux qui descend une fois sur le logo.
	var ts := create_tween()
	ts.tween_interval(0.3)
	ts.tween_property(sweep, "color:a", 0.7, 0.15)
	ts.parallel().tween_property(sweep, "position:y", vp.y * 0.78, 0.6).set_trans(Tween.TRANS_SINE)
	ts.chain().tween_property(sweep, "color:a", 0.0, 0.25)

	# Ligne de statut dactylographiée, puis invite clignotante.
	var tt := create_tween()
	tt.tween_interval(1.1)
	tt.tween_method(_set_status_chars, 0.0, float(_status_full.length()), maxf(0.4, _status_full.length() * 0.035))
	tt.tween_callback(_reveal_prompt)


func _set_status_chars(n: float) -> void:
	_status_label.text = _status_full.substr(0, int(n))


func _reveal_prompt() -> void:
	# Apparition + clignotement en boucle (Tween auto-tué à la libération de la scène).
	var blink := create_tween().set_loops()
	blink.tween_property(_prompt_label, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	blink.tween_property(_prompt_label, "modulate:a", 0.25, 0.7).set_trans(Tween.TRANS_SINE)


func _start_emblem_pulse() -> void:
	# Le halo de l'emblème « respire » en boucle (alpha + léger souffle d'échelle).
	# Tweens auto-tués à la libération de la scène (one-shot scene).
	var p := create_tween().set_loops()
	p.tween_property(_emblem_glow, "modulate:a", 0.5, 1.3).set_trans(Tween.TRANS_SINE)
	p.tween_property(_emblem_glow, "modulate:a", 1.0, 1.3).set_trans(Tween.TRANS_SINE)
	var s := create_tween().set_loops()
	s.tween_property(_emblem_glow, "scale", Vector2(1.07, 1.07), 1.3).set_trans(Tween.TRANS_SINE)
	s.tween_property(_emblem_glow, "scale", Vector2.ONE, 1.3).set_trans(Tween.TRANS_SINE)


func _play_sting() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx"):
		am.play_sfx("sting")


# --- Entrée & enchaînement ---------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _can_advance or _advancing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_advance()
	elif event is InputEventMouseButton and event.pressed:
		_advance()
	elif event is InputEventScreenTouch and event.pressed:
		_advance()


func _advance() -> void:
	if _advancing:
		return
	_advancing = true
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play_sfx"):
		am.play_sfx("confirm")
	var tm := get_node_or_null("/root/TransitionManager")
	if tm and tm.has_method("change_scene"):
		tm.change_scene(NEXT_SCENE)
	else:
		get_tree().change_scene_to_file(NEXT_SCENE)


# --- Helpers -----------------------------------------------------------------

func _one_shot_timer(delay: float, cb: Callable) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = delay
	add_child(timer)
	timer.timeout.connect(cb)
	timer.timeout.connect(timer.queue_free)
	timer.start()


# Petite texture « point doux » pour les particules de cendre (évite de dépendre d'un asset).
func _make_dot(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := float(d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)
