extends CanvasLayer

# BANDEAU DE TOUR/PHASE (E3 §8.75) — stinger ~1,1 s haut-centre, NON bloquant (mouse_filter
# IGNORE partout) : annonce chaque changement de tour/phase — « À VOUS DE JOUER, COMMANDANT »
# (or), « TOUR DE <PSEUDO> » (couleur joueur), « PHASE : ATTAQUE » (cyan). Piloté par main.gd
# (_maybe_show_banner) ; panneau angulaire charte §2 construit par code (pattern composants E1).

const STING_IN := 0.18
const STING_HOLD := 0.65
const STING_OUT := 0.27
# Position verticale du bandeau déployé (sous la TopBar du HUD).
const TOP_Y := 64.0

var _root: Control = null
var _panel: PanelContainer = null
var _label: Label = null
var _tween: Tween

func _ready() -> void:
	# Calque 2 : au-dessus du HUD (canvas racine, calque 0) — purement décoratif.
	layer = 2
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_root.add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_label)

# Lance le stinger : slide + fondu d'entrée, tenue, fondu de sortie. Un nouveau bandeau
# REMPLACE l'ancien immédiatement (kill du Tween en vol — jamais deux stingers superposés).
func show_banner(text: String, accent: Color) -> void:
	if _panel == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_label.text = text
	_label.add_theme_color_override("font_color", accent)
	# Panneau angulaire charte §2 : gunmetal quasi opaque, flancs à l'accent, coins droits.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.88)
	style.border_color = Color(accent, 0.8)
	style.set_border_width_all(0)
	style.border_width_left = 3
	style.border_width_right = 3
	style.set_corner_radius_all(0)
	style.content_margin_left = 26.0
	style.content_margin_right = 26.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = true
	_panel.reset_size()
	_panel.position = Vector2((_root.size.x - _panel.size.x) / 2.0, TOP_Y - 26.0)
	_panel.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_panel, "position:y", TOP_Y, STING_IN) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate:a", 1.0, STING_IN)
	_tween.set_parallel(false)
	_tween.tween_interval(STING_HOLD)
	_tween.tween_property(_panel, "modulate:a", 0.0, STING_OUT)
	_tween.tween_callback(func() -> void: _panel.visible = false)
