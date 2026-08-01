extends Control
##
## MANUEL DE GUERRE (TUTORIEL & FTUE §8.129, LOT E) — la référence CONSULTABLE À FROID.
##
## Troisième étage du dispositif, et le seul qui ne dépende d'aucun contexte : le briefing explique
## pendant qu'on joue, les bulles expliquent au moment où ça arrive, le Manuel répond quand on se
## pose la question deux semaines plus tard. Il est donc TOUJOURS accessible, jamais imposé.
##
## Trois chemins d'accès : PARAMÈTRES (onglet GÉNÉRAL) · « EN SAVOIR PLUS » d'une bulle (qui l'ouvre
## à LA bonne section) · menu ÉCHAP de l'arène.
##
## **Modal calqué sur le Classement** (référence maison actée §8.125) : voile plein écran + panneau
## gunmetal à liseré cyan, encoches de coin biseautées, filets sous les titres. **Aucun emoji.**
## Navigation LATÉRALE (une colonne de sections à gauche, le texte à droite) plutôt qu'un long
## défilement : huit sections lues d'affilée seraient un mur, alors qu'on vient toujours pour une.
##
## ⚠️ **Le contenu doit dire VRAI.** Chaque ligne des huit sections se vérifie dans
## `ARCHITECTURE_ET_REGLES.md` §4 (phases, dés, héros, factions, zone, objectifs, pactes) et §8.125
## (Battle Royale). Un tutoriel qui ment coûte plus cher que pas de tutoriel : si une règle change,
## c'est ICI qu'il faut repasser. Les textes eux-mêmes vivent dans `ui_strings.csv` (clés
## `MANUAL_SEC_*`), jamais en dur dans ce fichier.
##
## ⚠️ Une section est VOLONTAIREMENT incomplète : BATTLE ROYALE ne donne PAS les seuils exacts du
## Coup d'État (« la puissance décide » suffit). Le mystère est un ingrédient du mode, pas un oubli.

signal closed

const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")

const ACCENT := Color("36c5d9")
const GOLD := Color("e0b249")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.98)

const PANEL_SIZE := Vector2(1000, 620)
const NAV_WIDTH := 260.0

# Les HUIT sections, dans l'ordre de lecture d'un débutant : ce qu'on fait à chaque tour, puis ce
# qui se passe quand on frappe, puis qui l'on est, puis le décor, puis comment on gagne, puis les
# deux systèmes sociaux. `id` sert d'ancre à « EN SAVOIR PLUS » (registre `TutorialManager.HINTS`).
const SECTIONS := [
	{"id": "phases",        "title": "MANUAL_SEC_PHASES_TITLE",   "body": "MANUAL_SEC_PHASES_BODY"},
	{"id": "combat",        "title": "MANUAL_SEC_COMBAT_TITLE",   "body": "MANUAL_SEC_COMBAT_BODY"},
	{"id": "hero",          "title": "MANUAL_SEC_HERO_TITLE",     "body": "MANUAL_SEC_HERO_BODY"},
	{"id": "factions",      "title": "MANUAL_SEC_FACTIONS_TITLE", "body": "MANUAL_SEC_FACTIONS_BODY"},
	{"id": "zone",          "title": "MANUAL_SEC_ZONE_TITLE",     "body": "MANUAL_SEC_ZONE_BODY"},
	{"id": "objectives",    "title": "MANUAL_SEC_OBJ_TITLE",      "body": "MANUAL_SEC_OBJ_BODY"},
	{"id": "pacts",         "title": "MANUAL_SEC_PACTS_TITLE",    "body": "MANUAL_SEC_PACTS_BODY"},
	{"id": "battle_royale", "title": "MANUAL_SEC_BR_TITLE",       "body": "MANUAL_SEC_BR_BODY"},
]

var _nav_buttons := {}
var _title: Label
var _body: RichTextLabel
var _current := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	focus_section("")


func _build() -> void:
	# Voile : cliquer À CÔTÉ referme, comme le panneau de règles du Classement.
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.62)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_close())
	add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var pan := PanelContainer.new()
	pan.name = "ManualPanel"
	pan.custom_minimum_size = PANEL_SIZE
	pan.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = GUNMETAL
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = ACCENT
	st.set_content_margin_all(24.0)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 10
	pan.add_theme_stylebox_override("panel", st)
	center.add_child(pan)
	WarzoneUI.add_corner_notches(pan)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pan.add_child(col)

	# --- En-tête : eyebrow + titre + bouton FERMER ---
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)

	var head_col := VBoxContainer.new()
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_col.add_theme_constant_override("separation", 2)
	head.add_child(head_col)

	var eyebrow := Label.new()
	eyebrow.text = "MANUAL_EYEBROW"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", MUTED)
	head_col.add_child(eyebrow)

	var big := Label.new()
	big.text = "MANUAL_TITLE"
	big.add_theme_font_size_override("font_size", 26)
	big.add_theme_color_override("font_color", ACCENT)
	head_col.add_child(big)

	var close_btn := Button.new()
	close_btn.text = "MANUAL_CLOSE"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	WarzoneUI.apply_ghost_button(close_btn)
	WarzoneUI.wire_button_sfx(close_btn)
	close_btn.pressed.connect(_close)
	head.add_child(close_btn)

	WarzoneUI.add_filet(col)

	# --- Corps : navigation latérale | texte ---
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)

	var nav := VBoxContainer.new()
	nav.custom_minimum_size = Vector2(NAV_WIDTH, 0)
	nav.add_theme_constant_override("separation", 4)
	split.add_child(nav)
	for s in SECTIONS:
		var b := Button.new()
		b.text = str(s.get("title", ""))       # clé brute → auto-traduction
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		WarzoneUI.apply_ghost_button(b)
		WarzoneUI.wire_button_sfx(b)
		var sid := str(s.get("id", ""))
		b.pressed.connect(func() -> void: focus_section(sid))
		nav.add_child(b)
		_nav_buttons[sid] = b

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)

	_title = Label.new()
	_title.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", GOLD)
	right.add_child(_title)
	WarzoneUI.add_filet(right, 1)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)

	_body = RichTextLabel.new()
	_body.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 16)
	_body.add_theme_constant_override("line_separation", 5)
	_body.add_theme_color_override("default_color", TEXT)
	scroll.add_child(_body)


# Affiche une section. `section_id` vide ou inconnu → la première (LES PHASES D'UN TOUR) : « EN
# SAVOIR PLUS » d'une bulle future dont la section n'existerait pas ouvre un manuel utile, jamais
# un panneau vide.
func focus_section(section_id: String) -> void:
	var target := section_id
	var spec := _section(target)
	if spec.is_empty():
		spec = SECTIONS[0]
		target = str(spec.get("id", ""))
	_current = target
	_title.text = tr(str(spec.get("title", "")))
	# Puces « ❯ » (charte §2) posées à la LECTURE et non écrites dans le CSV : le traducteur n'a
	# ainsi qu'un texte à écrire, une ligne par idée.
	# Les corps de section sont stockés sur UNE ligne de CSV, les paragraphes séparés par la séquence
	# littérale « \n » : le CSV du dépôt n'a jamais contenu de champ multi-ligne, et en introduire
	# aurait fait dépendre l'i18n du parseur CSV de Godot sur un point qu'aucun autre écran n'exerce.
	var lines := tr(str(spec.get("body", ""))).replace("\\n", "\n").split("\n", false)
	var out := PackedStringArray()
	for l in lines:
		var t := str(l).strip_edges()
		if t == "":
			continue
		out.append("[color=#36c5d9]❯[/color]  " + t)
	_body.text = "\n".join(out)
	for id in _nav_buttons.keys():
		var b: Button = _nav_buttons[id]
		b.add_theme_color_override("font_color", ACCENT if id == target else MUTED)


func _section(section_id: String) -> Dictionary:
	for s in SECTIONS:
		if str(s.get("id", "")) == section_id:
			return s
	return {}


func _close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	# ÉCHAP referme le Manuel — et SEULEMENT lui : `set_input_as_handled` empêche l'arène d'ouvrir
	# son propre menu ÉCHAP dans la foulée (c'est souvent par là qu'on est arrivé).
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
