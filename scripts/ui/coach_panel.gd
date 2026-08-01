extends Control
##
## COACH « COMMANDEMENT » (TUTORIEL & FTUE §8.129) — **VUE PURE** (§6.1).
##
## Un seul panneau compact, en bas de l'écran, qui porte TOUT le didacticiel visible :
##   • les 13 étapes de la PREMIÈRE OPÉRATION (eyebrow « COMMANDEMENT ») ;
##   • les bulles d'AIDE CONTEXTUELLE hors briefing (eyebrow « AIDE »).
## Un seul composant pour les deux à dessein : la règle produit est « JAMAIS deux panneaux à
## l'écran » (§8.125), et deux scènes distinctes auraient été deux occasions de la violer. C'est le
## `TutorialManager` qui met les messages en FILE ; ici, on ne sait afficher qu'UN message.
##
## Cette vue ne décide RIEN : elle n'écoute aucun signal réseau, ne lit aucun état de partie et ne
## connaît aucune règle. Elle affiche ce qu'on lui donne et ré-émet trois intentions.
##
## Charte « Warzone Command » (§2) : gunmetal + liseré cyan, encoches de coin biseautées, eyebrow
## muette en petit → texte en grand, MAJUSCULES sur les libellés de boutons, **aucun emoji** (§8.125).
##
## Confort : `reduced_motion` (§8.82) remplace le liseré de surlignage PULSANT par un liseré FIXE —
## l'information (« c'est CE contrôle ») est préservée, seul le mouvement disparaît.

# Le joueur a lu et valide l'étape / la bulle courante.
signal acknowledged
# « PASSER LE BRIEFING » — visible à CHAQUE étape de la Première Opération (échappatoire permanente).
signal skip_requested
# « EN SAVOIR PLUS » — ouvre le MANUEL DE GUERRE à la section transmise avec le message.
signal more_requested(section_id: String)

const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")

const ACCENT := Color("36c5d9")
const GOLD := Color("e0b249")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
# ⚠️ Quasi-OPAQUE (0.97) et non translucide : vu en capture, à 0,94 le libellé OR d'une carte de
# mode traversait le panneau et se lisait par-dessus le texte du coach. Un panneau didactique doit
# être le seul objet lisible à son emplacement — c'est aussi le réglage du modal du Classement.
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.97)

const PANEL_WIDTH := 460.0
const NOTCH := 18.0
# Marges par défaut (écrans de menu : QG, draft, Rapport Post-Op). L'arène les remplace par
# `set_safe_margins()` — sa barre basse et son panneau COMMS occupent précisément ce coin.
const DEFAULT_MARGIN_RIGHT := 32.0
const DEFAULT_MARGIN_BOTTOM := 32.0

# Surlignage : marge autour du rectangle du contrôle cible, et épaisseur du liseré.
const HIGHLIGHT_PAD := 6.0
const HIGHLIGHT_WIDTH := 3.0

var _panel: PanelContainer
var _eyebrow: Label
var _body: Label
var _ack_btn: Button
var _more_btn: Button
var _skip_btn: Button
# Contrôle actuellement surligné (WeakRef : la cible peut disparaître avec son écran).
var _target: Control = null
var _more_section := ""
var _appear_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Le coach flotte AU-DESSUS du jeu sans jamais le bloquer : seuls ses boutons captent la souris.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	set_process(false)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CoachPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = GUNMETAL
	sb.set_border_width_all(1)
	sb.border_width_left = 3            # accent porteur à gauche (ADN angulaire de la charte)
	sb.border_color = ACCENT
	sb.set_content_margin_all(16)
	# Ombre portée : détache le panneau du fond quel que soit l'écran derrière (plateau, portrait
	# 3D du QG, rapport flouté) — même geste que le modal du Classement.
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	WarzoneUI.add_corner_notches(_panel, NOTCH)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)

	_eyebrow = Label.new()
	_eyebrow.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_eyebrow.add_theme_font_size_override("font_size", 13)
	_eyebrow.add_theme_color_override("font_color", ACCENT)
	col.add_child(_eyebrow)
	WarzoneUI.add_filet(col, 1)   # `add_filet` insère LUI-MÊME le séparateur dans `col`.

	_body = Label.new()
	_body.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_body.add_theme_font_size_override("font_size", 17)
	_body.add_theme_color_override("font_color", TEXT)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	_ack_btn = _make_button("", ACCENT)
	_ack_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ack_btn.pressed.connect(func() -> void: acknowledged.emit())
	row.add_child(_ack_btn)

	_more_btn = _make_button("", GOLD)
	_more_btn.pressed.connect(func() -> void: more_requested.emit(_more_section))
	row.add_child(_more_btn)

	# « PASSER LE BRIEFING » : DEUXIÈME rangée, en petit et en muet. C'est une échappatoire, pas une
	# option qu'on met au même niveau visuel que « COMPRIS » — mais elle est TOUJOURS là.
	_skip_btn = _make_button("", MUTED)
	_skip_btn.add_theme_font_size_override("font_size", 13)
	_skip_btn.pressed.connect(func() -> void: skip_requested.emit())
	col.add_child(_skip_btn)

	set_safe_margins(DEFAULT_MARGIN_RIGHT, DEFAULT_MARGIN_BOTTOM)


func _make_button(label: String, accent: Color) -> Button:
	var b := Button.new()
	b.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	b.text = label
	b.add_theme_font_size_override("font_size", 15)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	WarzoneUI.apply_ghost_button(b)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", TEXT)
	WarzoneUI.wire_button_sfx(b)
	return b


# Repositionne le panneau pour ne recouvrir AUCUN élément vital de l'écran courant. L'arène a une
# barre basse pleine largeur et un panneau COMMS à droite : sans ces marges, le coach s'assiérait
# précisément sur les contrôles qu'il est en train d'expliquer.
func set_safe_margins(margin_right: float, margin_bottom: float) -> void:
	if _panel == null:
		return
	_panel.offset_right = -margin_right
	_panel.offset_left = _panel.offset_right - PANEL_WIDTH
	_panel.offset_bottom = -margin_bottom


# =========================================================
# AFFICHAGE D'UN MESSAGE
# =========================================================
# `ack_label` : libellé du bouton principal (« COMPRIS », « CONTINUER »…).
# `skip_label` : "" → bouton masqué (les bulles contextuelles ne se « passent » pas, elles se ferment).
# `more_section` : "" → pas de bouton « EN SAVOIR PLUS ».
func show_message(eyebrow: String, body: String, ack_label: String,
		skip_label: String = "", more_label: String = "", more_section: String = "") -> void:
	_eyebrow.text = eyebrow
	_body.text = body
	_ack_btn.text = ack_label
	_more_section = more_section
	_more_btn.text = more_label
	_more_btn.visible = more_section != "" and more_label != ""
	_skip_btn.text = skip_label
	_skip_btn.visible = skip_label != ""
	visible = true
	# Apparition : léger fondu + montée. `reduced_motion` → apparition SÈCHE (l'information arrive
	# au même instant, sans mouvement).
	if _appear_tween != null and _appear_tween.is_valid():
		_appear_tween.kill()
	if bool(SettingsManager.get_comfort("reduced_motion")):
		_panel.modulate.a = 1.0
		return
	_panel.modulate.a = 0.0
	_appear_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_appear_tween.tween_property(_panel, "modulate:a", 1.0, 0.18)


func hide_message() -> void:
	visible = false
	clear_highlight()


# =========================================================
# SURLIGNAGE D'UN CONTRÔLE CIBLE
# =========================================================
# Liseré cyan tracé AUTOUR du contrôle (jamais par-dessus : on encadre, on ne masque pas). Le rect
# est relu à chaque frame — un contrôle de la barre basse bouge quand elle se rétracte, et un
# rectangle figé pointerait alors le vide.
func highlight(control: Control) -> void:
	_target = control
	set_process(control != null)
	queue_redraw()


func clear_highlight() -> void:
	_target = null
	set_process(false)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		return
	var r: Rect2 = _target.get_global_rect().grow(HIGHLIGHT_PAD)
	# Le coach est plein écran ancré à l'origine : ses coordonnées locales SONT les globales. On
	# soustrait néanmoins sa position, pour rester juste si un parent venait à le décaler.
	r.position -= global_position
	var alpha := 1.0
	if not bool(SettingsManager.get_comfort("reduced_motion")):
		alpha = 0.55 + 0.45 * absf(sin(float(Time.get_ticks_msec()) / 320.0))
	draw_rect(r, Color(ACCENT, alpha), false, HIGHLIGHT_WIDTH)
	# Coins renforcés (ADN angulaire §2) : quatre équerres pleines qui « accrochent » le rectangle.
	var c := 14.0
	var col := Color(ACCENT, alpha)
	for corner in [
			[r.position, Vector2(1, 0), Vector2(0, 1)],
			[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)],
			[r.end, Vector2(-1, 0), Vector2(0, -1)]]:
		var p: Vector2 = corner[0]
		draw_line(p, p + (corner[1] as Vector2) * c, col, HIGHLIGHT_WIDTH)
		draw_line(p, p + (corner[2] as Vector2) * c, col, HIGHLIGHT_WIDTH)
