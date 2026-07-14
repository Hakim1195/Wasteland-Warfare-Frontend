extends Control

# OVERLAY OBSERVATEUR (lot G3 — §8.70) : bandeau haut « ★ K.I.A. — MODE OBSERVATEUR » affiché au
# joueur ÉLIMINÉ (permadeath héros §8.61). NON bloquant : le plateau reste visible/navigable
# (caméra tactique libre) et le chat reste accessible — l'overlay n'occupe que le bandeau.
# View PURE (Règle d'Or §6.1) : 2 boutons → signaux ; main.gd décide (requeue réseau / sortie).
# Construit par code (charte « Warzone Command » §2 : gunmetal, titre or, boutons angulaires).

signal requeue_pressed
signal quit_pressed

const ACCENT := Color("36c5d9")
const GOLD := Color("e0b249")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
const DANGER := Color("d6453f")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.92)

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

var _font: SystemFont


func _ready() -> void:
	# Plein écran mais TRANSPARENT aux clics (seul le bandeau est interactif).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	var panel := PanelContainer.new()
	panel.name = "SpectatorBanner"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = GUNMETAL
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = GOLD
	st.content_margin_left = 24.0
	st.content_margin_right = 24.0
	st.content_margin_top = 10.0
	st.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", st)
	# Ancré en HAUT-CENTRE (ne recouvre ni le plateau ni les panneaux latéraux du HUD).
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 8.0
	add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	panel.add_child(h)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	h.add_child(title_box)
	var eyebrow := Label.new()
	eyebrow.text = tr("SPECT_EYEBROW")
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", MUTED)
	title_box.add_child(eyebrow)
	var title := Label.new()
	title.text = tr("SPECT_TITLE")
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", GOLD)
	title_box.add_child(title)

	var requeue := _make_button(tr("SPECT_REQUEUE"), GOLD)
	requeue.pressed.connect(func():
		requeue.disabled = true  # anti double-clic pendant la re-queue réseau.
		requeue_pressed.emit())
	h.add_child(requeue)

	var quit := _make_button(tr("SPECT_QUIT"), DANGER)
	quit.pressed.connect(func(): quit_pressed.emit())
	h.add_child(quit)


func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 42)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(accent, 0.14)
	sb.set_border_width_all(2)
	sb.border_color = accent
	sb.set_content_margin_all(8)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(accent, 0.30)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", TEXT)
	WarzoneUI.wire_button_sfx(btn)
	return btn
