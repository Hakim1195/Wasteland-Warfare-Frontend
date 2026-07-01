extends Control

# ÉCRAN MISSIONS (onglet « MISSIONS » de la barre) — défis QUOTIDIENS / HEBDOMADAIRES façon Warzone.
# Deux onglets internes basculent la liste des objectifs (barre de progression cyan + récompense XP
# en badge hexagonal or). View PURE (Règle d'Or §6.1). Construit par code (charte « Warzone Command »).
#
# ⚠️ Données MOCK : le backend n'expose pas encore d'objectifs (à spécifier dans CONTRAT_RESEAU §9,
# au même titre que R1/R2/R3). Quand l'endpoint existera, « seul le peuplement change » (les rangées
# sont déjà alimentées par une liste de dictionnaires { key, cur, goal, xp }).

const TopNav = preload("res://scripts/ui/top_nav.gd")
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

const ACCENT := Color("36c5d9")
const GOLD := Color("e0b249")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const BAR_H := 56.0

const _DAILY := [
	{"key": "MISSION_D1", "cur": 0, "goal": 5, "xp": 2500},
	{"key": "MISSION_D2", "cur": 3, "goal": 10, "xp": 2500},
	{"key": "MISSION_D3", "cur": 0, "goal": 3, "xp": 2500},
]
const _WEEKLY := [
	{"key": "MISSION_W1", "cur": 1, "goal": 3, "xp": 7500},
	{"key": "MISSION_W2", "cur": 40, "goal": 100, "xp": 7500},
	{"key": "MISSION_W3", "cur": 2, "goal": 5, "xp": 7500},
]

var _font: Font
var _list: VBoxContainer
var _tab_daily: Button
var _tab_weekly: Button
var _showing_daily := true

func _ready() -> void:
	_font = _make_font()
	var nav := TopNav.new()
	nav.active_tab = "missions"
	add_child(nav)
	AudioManager.start_menu_ambient()
	_build()
	_refresh_list()

func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = BAR_H
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = GUNMETAL
	st.set_corner_radius_all(0)
	st.set_border_width_all(3)
	st.border_color = ACCENT
	st.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)

	vb.add_child(_label("MISSIONS_EYEBROW", 14, ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
	vb.add_child(_label("MISSIONS_TITLE", 38, TEXT, HORIZONTAL_ALIGNMENT_LEFT))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	_tab_daily = _make_toggle("MISSIONS_TAB_DAILY", true)
	_tab_daily.pressed.connect(func() -> void: _switch(true))
	_tab_weekly = _make_toggle("MISSIONS_TAB_WEEKLY", false)
	_tab_weekly.pressed.connect(func() -> void: _switch(false))
	tabs.add_child(_tab_daily)
	tabs.add_child(_tab_weekly)
	vb.add_child(tabs)

	WarzoneUI.add_filet(vb)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	vb.add_child(_list)

	vb.add_child(_label("MISSIONS_STATUS", 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT))

func _switch(daily: bool) -> void:
	if daily == _showing_daily:
		return
	_showing_daily = daily
	AudioManager.play_sfx("click")
	_style_toggle(_tab_daily, daily)
	_style_toggle(_tab_weekly, not daily)
	_refresh_list()

func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var data: Array = _DAILY if _showing_daily else _WEEKLY
	for m in data:
		_list.add_child(_make_row(m))

# Rangée d'objectif : intitulé + barre de progression cyan + compteur + récompense XP (badge hexagone or).
func _make_row(m: Dictionary) -> Control:
	var cur := int(m.get("cur"))
	var goal := maxi(1, int(m.get("goal")))
	var done := cur >= goal

	var row := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.03)
	st.set_corner_radius_all(0)
	st.border_width_left = 3
	st.border_color = GOLD if done else ACCENT
	st.set_content_margin_all(12)
	row.add_theme_stylebox_override("panel", st)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	row.add_child(hb)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	var lbl := _label(str(m.get("key")), 16, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(lbl)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.min_value = 0.0
	bar.max_value = float(goal)
	bar.value = float(cur)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(0)
	var fg := StyleBoxFlat.new()
	fg.bg_color = GOLD if done else ACCENT
	fg.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	left.add_child(bar)
	hb.add_child(left)

	var counter := _label("%d/%d" % [cur, goal], 16, GOLD if done else ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	counter.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	counter.custom_minimum_size = Vector2(70, 0)
	counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(counter)

	var badge := WarzoneUI.make_hex_badge(str(int(m.get("xp"))), _font, 13, GOLD, GUNMETAL, 54.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(badge)
	return row

func _make_toggle(key: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = key
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 16)
	WarzoneUI.wire_button_sfx(btn)
	_style_toggle(btn, active)
	return btn

func _style_toggle(btn: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	if active:
		sb.bg_color = Color(ACCENT, 0.18)
		sb.border_width_bottom = 3
		sb.border_color = ACCENT
	else:
		sb.bg_color = Color(0, 0, 0, 0)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.16)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", TEXT if active else MUTED)
	btn.add_theme_color_override("font_hover_color", TEXT)

func _label(key_or_text: String, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = key_or_text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l
