extends VBoxContainer
##
## Logo « Wasteland Warfare » — wordmark TYPOGRAPHIQUE (inspiration Cyberpunk, charte Warzone §2).
##
## Le wordmark est le HÉROS (plus d'emblème) : « WASTELAND » + « WARFARE » dans un slab cyan plein
## (texte en négatif gunmetal — l'« encadré » signature de Cyberpunk), eyebrow « // DOOMSDAY RISK »,
## petite marque BIOHAZARD tactique (+ halo néon cyan) et crochets tactiques aux coins. Le texte est posé
## en Label dans la police du jeu (Bahnschrift condensé 700) car l'importeur SVG de Godot (ThorVG)
## ne rend PAS les <text> ; seule la marque est un SVG (formes). Règle d'Or §6.1 : Vue pure.
##
## Instancié par les écrans (auth / bootloader / lobby / waiting_room) et par title_splash.gd.
## Les `@export` ajustent tailles / visibilité des ornements selon l'écran.

const MARK := preload("res://assets/images/logo_mark.svg")
const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")   # helper partagé (halo de marque §8.63)

const ACCENT := Color(0.211765, 0.772549, 0.85098)   # cyan tactique #36C5D9
const TEXT := Color(0.933333, 0.952941, 0.968627)     # blanc froid #EEF3F7
const GUNMETAL := Color(0.058824, 0.07451, 0.094118)  # #0F1318 (texte sur slab cyan)

@export var line_one: String = "WASTELAND"
@export var line_two: String = "WARFARE"
@export var eyebrow_text: String = "// DOOMSDAY RISK"
@export var title_size: int = 38
@export var eyebrow_size: int = 15
@export var mark_size: float = 42.0
@export var spacing: int = 4
@export var show_mark: bool = true
@export var show_glow: bool = true        ## halo néon cyan derrière la marque
@export var glow_strength: float = 1.0    ## opacité du halo (0 = éteint)
@export var show_eyebrow: bool = true
@export var show_brackets: bool = true

var _font: SystemFont


func _ready() -> void:
	_build()


func _build() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", spacing)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# Marque hex-nœuds (territoires / Risk).
	if show_mark:
		var mark := TextureRect.new()
		mark.texture = MARK
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(0.0, mark_size)
		mark.size_flags_horizontal = Control.SIZE_FILL
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(mark)

		# Halo néon cyan derrière la marque (mutualisé §8.63) : déborde sans peser sur le layout.
		if show_glow:
			WarzoneUI.attach_mark_glow(mark, mark_size, glow_strength)

	# Eyebrow « // DOOMSDAY RISK ».
	if show_eyebrow:
		add_child(_make_label(eyebrow_text, eyebrow_size, ACCENT))

	# Ligne 1 « WASTELAND » (blanc froid).
	add_child(_make_label(line_one, title_size, TEXT))

	# Ligne 2 « WARFARE » dans un slab cyan plein (texte en négatif gunmetal).
	var slab_row := HBoxContainer.new()
	slab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slab_row.size_flags_horizontal = Control.SIZE_FILL
	slab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var slab := PanelContainer.new()
	slab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ACCENT
	sb.set_corner_radius_all(0)
	var pad := int(round(float(title_size) * 0.26))
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = 1
	sb.content_margin_bottom = 3
	slab.add_theme_stylebox_override("panel", sb)

	var l2 := _make_label(line_two, title_size, GUNMETAL)
	l2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slab.add_child(l2)
	slab_row.add_child(slab)
	add_child(slab_row)

	# Crochets tactiques aux coins (dessinés dans _draw, repositionnés au resize).
	if show_brackets:
		resized.connect(queue_redraw)
		queue_redraw()


func _make_label(txt: String, fsize: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", fsize)
	lbl.add_theme_color_override("font_color", color)
	lbl.size_flags_horizontal = Control.SIZE_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Nom propre du jeu : hors système de traduction.
	lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	return lbl


func _draw() -> void:
	if not show_brackets:
		return
	var s := size
	var arm := 18.0
	var w := 2.0
	# 4 crochets en L (frame tactique).
	draw_polyline(PackedVector2Array([Vector2(0.0, arm), Vector2(0.0, 0.0), Vector2(arm, 0.0)]), ACCENT, w)
	draw_polyline(PackedVector2Array([Vector2(s.x - arm, 0.0), Vector2(s.x, 0.0), Vector2(s.x, arm)]), ACCENT, w)
	draw_polyline(PackedVector2Array([Vector2(0.0, s.y - arm), Vector2(0.0, s.y), Vector2(arm, s.y)]), ACCENT, w)
	draw_polyline(PackedVector2Array([Vector2(s.x - arm, s.y), Vector2(s.x, s.y), Vector2(s.x, s.y - arm)]), ACCENT, w)
