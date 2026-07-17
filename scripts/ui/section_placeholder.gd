extends Control

# ÉCRAN « SECTION EN CONSTRUCTION » — placeholder RÉUTILISABLE de la charte « Warzone Command » (§2)
# pour les onglets dont le système de jeu n'existe pas encore (Armes, Skins, Battle Pass, Événements).
# Une seule logique, 4 scènes minces : chaque scène règle `tab_id` (onglet actif mis en surbrillance
# dans la barre) et `title_key` (grand titre traduit). View PURE : TopNav gère toute la navigation.

const TopNav = preload("res://scripts/ui/top_nav.gd")
const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

const ACCENT := Color("36c5d9")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
# Décalage du contenu sous la nav : ALIGNÉ sur la hauteur RÉELLE du composant (§8.94). Avant, la
# valeur locale (56) sous-estimait la bande (100) → le panneau passait dessous.
const BAR_H := TopNav.NAV_H

# `tab_id` : ces sections sont DÉBRANCHÉES de la nav (aucune entrée dans TABS) → leur id ne matche
# aucun onglet et AUCUN onglet n'est surligné. C'est le comportement nominal des écrans « hors
# onglets » (§8.94), identique à profil/réglages qui passent "".
@export var tab_id: String = "weapons"
@export var title_key: String = "NAV_WEAPONS"

var _font: Font

func _ready() -> void:
	_font = _make_font()
	var nav := TopNav.new()
	nav.active_tab = tab_id
	add_child(nav)
	AudioManager.start_menu_ambient()
	# Entrée d'écran UNIFORME (§8.96) : fondu + léger glissement, identique sur tous les écrans hub.
	WarzoneUI.animate_screen_enter(self)

	_build()

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
	var st := StyleBoxFlat.new()
	st.bg_color = GUNMETAL
	st.set_corner_radius_all(0)
	st.set_border_width_all(3)
	st.border_color = ACCENT
	st.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)

	vb.add_child(_label("SECTION_SOON_EYEBROW", 14, ACCENT))
	vb.add_child(_label(title_key, 48, TEXT))
	WarzoneUI.add_filet(vb)
	vb.add_child(_label("SECTION_SOON_TITLE", 24, ACCENT))
	var desc := _label("SECTION_SOON_DESC", 16, MUTED)
	desc.custom_minimum_size = Vector2(520, 0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc)

func _label(key: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = key
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
