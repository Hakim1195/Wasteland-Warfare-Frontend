extends Control

# CINÉMATIQUE DE MISE À MORT (REFONTE UI ARÈNE, lot D) — permadeath §8.61.
#
# Jouée pour TOUS les joueurs, sans exception ni réglage, quand un héros tombe :
# c'est le moment le plus fort d'une partie, personne ne doit le rater. La variante jouée est le
# FINISHER DU TUEUR (`equipped_finisher` de son PlayerState public — miroir des skins M5 §8.69) ;
# le basique gratuit ("" ) est le défaut de tout le monde.
#
# 100 % PROCÉDURAL (Tween + Polygon2D + GPUParticles2D) — aucune vidéo embarquée (hors périmètre,
# §16 du prompt) : la scène reste légère et se décline par simple changement de paramètres
# (registre `finishers.gd`, Règle d'Or §6.3).
#
# Vue PURE (§6.1) : main.gd résout tueur/victime/portrait/couleurs et appelle `play()`.

signal finished

const Finishers := preload("res://scripts/game/finishers.gd")

# Durées (constantes nommées) — total ≈ 3 s.
const IN_TIME := 0.35
const HOLD_TIME := 2.1
const OUT_TIME := 0.5

var _params: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # aucun clic ne traverse vers le plateau
	modulate.a = 0.0

# data = {
#   killer_name, killer_color: Color, killer_portrait: Texture2D|null,
#   victim_name, victim_color: Color, finisher_id: String }
func play(data: Dictionary) -> void:
	_params = Finishers.params_for(data.get("finisher_id", ""))
	var accent: Color = _params["accent"]
	var secondary: Color = _params["secondary"]

	# --- Fond assombri + traits diagonaux à la palette du finisher (ADN angulaire §2) ---
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_build_streaks(accent, secondary)

	# --- Bloc central : bandeau « HÉROS ABATTU » + portrait du tueur + ligne tueur ▸ victime ---
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = tr("CINE_HERO_DOWN_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", accent)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	col.add_child(title)

	var portrait = data.get("killer_portrait")
	if portrait is Texture2D:
		var tex := TextureRect.new()
		tex.texture = portrait
		tex.custom_minimum_size = Vector2(260, 260)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tex.modulate = Color(1, 1, 1, 0.92)
		col.add_child(tex)

	# « {tueur} ▸ {victime} ☠ » — pseudos aux couleurs PLATEAU (repère instantané).
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.custom_minimum_size = Vector2(760, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("normal_font_size", 30)
	var killer_col: Color = data.get("killer_color", Color("eef3f7"))
	var victim_col: Color = data.get("victim_color", Color("d6453f"))
	line.append_text("[center]" + (tr("CINE_HERO_DOWN_FMT") % [
		"[color=#%s]%s[/color]" % [killer_col.to_html(false), str(data.get("killer_name", "?")).to_upper()],
		"[color=#%s]%s[/color]" % [victim_col.to_html(false), str(data.get("victim_name", "?")).to_upper()],
	]) + "[/center]")
	col.add_child(line)

	var variant := Label.new()
	variant.text = tr(str(_params.get("name_key", "FINISHER_BASIC_NAME")))
	variant.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	variant.add_theme_font_size_override("font_size", 14)
	variant.add_theme_color_override("font_color", secondary)
	col.add_child(variant)

	# --- Particules + onde de choc + sting audio ---
	if not bool(SettingsManager.get_comfort("reduced_motion")):
		add_child(_make_particles(accent, secondary))
		if bool(_params.get("shockwave", true)):
			_shockwave(secondary)
	AudioManager.play_sfx(str(_params.get("sting", "hero_down")))
	# §8.122 (LOT B) : la musique s'efface sous le sting du finisher — sans ce ducking, la couche
	# « high » d'une fin de partie tendue mange l'impact du seul moment vraiment irréversible du jeu.
	AudioManager.duck_music()

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, IN_TIME)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(self, "modulate:a", 0.0, OUT_TIME)
	await tw.finished
	finished.emit()
	queue_free()

# Traits diagonaux de fond (nombre piloté par le finisher — 1 pour la frappe orbitale, 9 pour le
# barrage d'acier) : le décor change de personnalité sans changer de code.
func _build_streaks(accent: Color, secondary: Color) -> void:
	var n := maxi(int(_params.get("streaks", 4)), 0)
	var vp := get_viewport_rect().size
	for i in range(n):
		var bar := ColorRect.new()
		bar.color = (accent if i % 2 == 0 else secondary)
		bar.color.a = 0.16
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(maxf(vp.x, 1920.0) * 1.6, 10.0 + 6.0 * float(i % 3))
		bar.position = Vector2(-vp.x * 0.3, vp.y * (0.12 + 0.09 * float(i)))
		bar.rotation = deg_to_rad(-9.0)
		bar.pivot_offset = Vector2.ZERO
		add_child(bar)
		var tw := bar.create_tween()
		tw.tween_property(bar, "position:x", bar.position.x + 140.0, IN_TIME + HOLD_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _make_particles(accent: Color, secondary: Color) -> GPUParticles2D:
	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 90.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = float(_params.get("particle_spread", 180.0))
	mat.initial_velocity_min = 90.0
	mat.initial_velocity_max = 380.0
	mat.gravity = Vector3(0, float(_params.get("particle_gravity", 240.0)), 0)
	mat.scale_min = 1.5
	mat.scale_max = 6.0
	mat.color = accent.lerp(secondary, 0.4)
	var p := GPUParticles2D.new()
	p.process_material = mat
	p.amount = maxi(int(_params.get("particle_amount", 40)), 1)
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 0.65
	p.position = get_viewport_rect().size * 0.5
	p.emitting = true
	return p

# Onde de choc : deux anneaux qui s'ouvrent depuis le centre de l'écran.
func _shockwave(col: Color) -> void:
	var center := get_viewport_rect().size * 0.5
	for i in range(2):
		var ring := Line2D.new()
		var pts := PackedVector2Array()
		for k in range(40):
			var a := TAU * float(k) / 40.0
			pts.append(Vector2(cos(a), sin(a)) * 80.0)
		ring.points = pts
		ring.closed = true
		ring.width = 5.0
		ring.default_color = col
		ring.position = center
		add_child(ring)
		var tw := ring.create_tween().set_parallel(true)
		tw.tween_property(ring, "scale", Vector2(7.0, 7.0), 1.1).set_delay(0.12 * float(i))
		tw.tween_property(ring, "modulate:a", 0.0, 1.1).set_delay(0.12 * float(i))
