extends Control

# =============================================================================
# SÉQUENCE D'UNLOCK (§8.122, LOT F) — « vous venez d'acquérir X »
# =============================================================================
# Surcouche GÉNÉRIQUE et réutilisable (100 % code, charte « Warzone Command » §2) : assombrissement
# → SILHOUETTE noire de l'article → révélation (lumière + dézoom élastique) + sting + gerbe dorée.
#
# Elle existe parce qu'un achat validé ne produisait jusqu'ici qu'une ligne de statut : le moment
# où l'on obtient enfin un personnage — le seul achat coûteux du jeu — ne se voyait nulle part.
#
# Règle d'Or §6.1 : VUE pure. Elle ne connaît ni la boutique, ni l'économie, ni le réseau. On lui
# passe un nom, une texture et une couleur ; elle émet `finished` quand le joueur a fermé.
#
# CONTRATS DU CHANTIER :
#   • durée de la séquence ANIMÉE ≤ 2,5 s (ici ≈ 1,5 s) ;
#   • un clic n'importe où SKIPPE et pose l'état final ;
#   • `reduced_motion` → affichage DIRECT (aucune animation, aucune particule).

signal finished

const DIM_TIME := 0.25          # fondu du voile
const SILHOUETTE_TIME := 0.40   # temps où l'article reste une ombre (on retient son souffle)
const REVEAL_TIME := 0.50       # révélation : noir → blanc + dézoom élastique
const REVEAL_SCALE_FROM := 1.15
const PARTICLE_AMOUNT := 30
const PARTICLE_LIFETIME := 1.1
const ART_SIZE := Vector2(300, 300)

const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1)

const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")

var _dim: ColorRect = null
var _art: TextureRect = null
var _panel: PanelContainer = null
var _burst: GPUParticles2D = null
var _tween: Tween = null
var _revealed := false
var _accent: Color = GOLD


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP : la surcouche avale tous les clics — on ne veut pas d'un achat déclenché « à travers ».
	mouse_filter = Control.MOUSE_FILTER_STOP


# data = { "name": String (déjà traduit), "texture": Texture2D|null, "accent": Color }
func play(data: Dictionary) -> void:
	var item_name := str(data.get("name", ""))
	var tex = data.get("texture")
	_accent = data.get("accent", GOLD) if data.get("accent") is Color else GOLD

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.78)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GUNMETAL, 0.96)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(2)
	sb.border_color = GOLD
	sb.set_content_margin_all(30.0)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(col)

	# Eyebrow « DÉBLOQUÉ » (rythme eyebrow → valeur, charte §2).
	var eyebrow := Label.new()
	eyebrow.text = tr("UNLOCK_EYEBROW")
	eyebrow.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	eyebrow.add_theme_font_override("font", _make_font())
	eyebrow.add_theme_font_size_override("font_size", 15)
	eyebrow.add_theme_color_override("font_color", GOLD)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(eyebrow)

	# Visuel de l'article. Sans texture (finisher, Pass…), un carré d'accent tient le rôle : la
	# SILHOUETTE puis la révélation fonctionnent de la même façon, il n'y a pas de « cas sans image ».
	_art = TextureRect.new()
	_art.custom_minimum_size = ART_SIZE
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex is Texture2D:
		_art.texture = tex
	else:
		_art.texture = _make_accent_plate(_accent)
	# État de départ : SILHOUETTE (modulate noir) — on voit la forme, pas encore l'article.
	_art.modulate = Color(0, 0, 0, 1)
	col.add_child(_art)

	var name_lbl := Label.new()
	name_lbl.text = item_name
	name_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	name_lbl.add_theme_font_override("font", _make_font())
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)

	var cta := Button.new()
	cta.text = tr("UNLOCK_CONTINUE")
	cta.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	cta.add_theme_font_override("font", _make_font())
	cta.add_theme_font_size_override("font_size", 17)
	cta.custom_minimum_size = Vector2(220, 46)
	WarzoneUI.apply_ghost_button(cta)
	cta.pressed.connect(_close)
	cta.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	col.add_child(cta)

	WarzoneUI.add_corner_notches(_panel, 18.0, GOLD)

	# `reduced_motion` (E10) : AFFICHAGE DIRECT. Pas de voile qui monte, pas de silhouette, pas de
	# gerbe — le résultat est là, tout de suite. Le sting reste (c'est du son, pas du mouvement).
	if bool(SettingsManager.get_comfort("reduced_motion")):
		_dim.modulate.a = 1.0
		_reveal_now()
		return

	_tween = create_tween()
	_tween.tween_property(_dim, "modulate:a", 1.0, DIM_TIME)
	_tween.tween_interval(SILHOUETTE_TIME)
	_tween.tween_callback(_reveal_now)


# Pose l'état FINAL (article éclairé, taille nominale) et lance sting + particules. Idempotent :
# c'est aussi le point d'arrivée du skip.
func _reveal_now() -> void:
	if _revealed:
		return
	_revealed = true
	AudioManager.play_sfx("confirm")
	if _art == null or not is_instance_valid(_art):
		return
	if bool(SettingsManager.get_comfort("reduced_motion")):
		_art.modulate = Color.WHITE
		return
	_art.pivot_offset = _art.size * 0.5
	_art.scale = Vector2(REVEAL_SCALE_FROM, REVEAL_SCALE_FROM)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_art, "modulate", Color.WHITE, REVEAL_TIME)
	tw.tween_property(_art, "scale", Vector2.ONE, REVEAL_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_burst()


# Gerbe dorée one-shot centrée sur l'article (≈ 30 particules — sans commune mesure avec le budget
# du plateau : c'est un écran de menu, rien d'autre ne tourne).
func _spawn_burst() -> void:
	if _art == null or not is_instance_valid(_art):
		return
	_burst = GPUParticles2D.new()
	_burst.amount = PARTICLE_AMOUNT
	_burst.lifetime = PARTICLE_LIFETIME
	_burst.one_shot = true
	_burst.explosiveness = 0.9
	_burst.local_coords = false
	_burst.texture = _make_dot(10)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 40.0
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 180.0
	pm.gravity = Vector3(0.0, 220.0, 0.0)
	pm.initial_velocity_min = 90.0
	pm.initial_velocity_max = 300.0
	pm.scale_min = 1.0
	pm.scale_max = 3.0
	pm.color = GOLD
	if "color_ramp" in pm:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = g
		pm.color_ramp = ramp
	_burst.process_material = pm
	add_child(_burst)
	_burst.position = _art.global_position + _art.size * 0.5
	_burst.emitting = true


# Clic n'importe où = SKIP tant que la révélation n'a pas eu lieu ; une fois révélé, il ferme.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	accept_event()
	if not _revealed:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		if _dim != null and is_instance_valid(_dim):
			_dim.modulate.a = 1.0
		_reveal_now()
		return
	_close()


func _close() -> void:
	AudioManager.play_sfx("back")
	finished.emit()
	queue_free()


# --- Fabriques ---------------------------------------------------------------
func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f

# Plaque d'accent servant de visuel de repli (article sans portrait) : dégradé sobre + liseré.
func _make_accent_plate(accent: Color) -> ImageTexture:
	var d := 64
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	for y in d:
		for x in d:
			var edge: bool = x < 2 or y < 2 or x >= d - 2 or y >= d - 2
			var t := float(y) / float(d - 1)
			var c := Color(accent.r, accent.g, accent.b, lerpf(0.45, 0.12, t))
			img.set_pixel(x, y, accent if edge else c)
	return ImageTexture.create_from_image(img)

func _make_dot(d: int) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := float(d) * 0.5
	for y in d:
		for x in d:
			var dist := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			var a := clampf(1.0 - dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)
