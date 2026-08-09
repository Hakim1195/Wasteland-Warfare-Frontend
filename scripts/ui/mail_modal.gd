extends Control
##
## COURRIER DU COMMANDEMENT (§8.144) — le modal de la boîte de réception.
##
## **Modal calqué sur le Classement** (référence maison actée §8.125, comme `war_manual.gd`) : voile
## plein écran + panneau gunmetal à liseré cyan, encoches de coin biseautées, filets sous les titres.
## **Aucun emoji.** Navigation LATÉRALE — la liste des plis à gauche, le pli ouvert à droite : on
## vient toujours lire UN courrier, pas les parcourir tous.
##
## Ce n'est PAS un écran de hub : le courrier est une NOTIFICATION DE COMPTE, pas une destination de
## jeu. Il s'ouvre par l'enveloppe de la barre de navigation, par-dessus n'importe quel écran.
##
## ⚠️ **LE CORPS D'UN PLI EST DU TEXTE, PAS DU BALISAGE.** `bbcode_enabled = false`, sans exception :
## c'est la contrepartie de la dérogation R4 du chantier (le serveur transporte ici du texte libre
## écrit par un opérateur, comme les messages du Chat §8.20). La dérogation porte sur le CONTENU,
## jamais sur le pouvoir de MISE EN FORME — un compte d'administration compromis ne doit pas pouvoir
## injecter du balisage dans le client. Tout le CHROME, lui, reste en clés i18n (FR/EN/IT).
##
## ⚠️ **L'IDEMPOTENCE DU CLAIM NE VIT PAS ICI.** Le verrou `_claim_in_flight` est du CONFORT (il
## empêche le double-clic de partir deux fois sur le réseau) ; la vérité est `player_mail.claimed_at`
## sous verrou de ligne, côté serveur. Les deux se testent séparément — et si celui-ci tombe, rien
## de grave n'arrive.

signal closed
## Émis après un claim réussi ET après une lecture : la nav rafraîchit sa pastille. On ne va pas la
## chercher dans l'arbre — vue PURE (Règle d'Or §6.1), c'est l'hôte qui branche.
signal badge_dirty

const WarzoneUI := preload("res://scripts/ui/warzone_ui.gd")
const CountdownLabel := preload("res://scripts/ui/countdown_label.gd")

const ACCENT := Color("36c5d9")
const GOLD := Color("e0b249")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
const DANGER := Color("d6453f")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.98)

const PANEL_SIZE := Vector2(1000, 620)
const LIST_WIDTH := 320.0

## Seuil d'affichage du compte à rebours dans la LISTE : 48 h. Au-delà, une échéance lointaine n'est
## pas une information utile et ferait du bruit sur chaque ligne. Le DÉTAIL, lui, l'affiche toujours.
const URGENT_WINDOW_S := 172800

var _font: Font
var _list_box: VBoxContainer
var _list_scroll: ScrollContainer
var _detail_scroll: ScrollContainer
var _empty_box: CenterContainer
var _detail_box: VBoxContainer
## Dernier payload `GET /mail` reçu — re-peint au changement de langue SANS aller-retour réseau
## (dette relevée sur `missions_panel.gd`, qui ne le faisait pas à l'origine).
var _mails: Array = []
var _selected_id: int = 0
## Anti double-clic : id du pli dont le claim est EN VOL (0 = aucun).
var _claim_in_flight: int = 0
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = _make_font()
	_build()

	NetworkManager.mail_list_loaded.connect(_on_mail_loaded)
	NetworkManager.mail_claimed.connect(_on_claimed)
	NetworkManager.mail_claim_failed.connect(_on_claim_failed)
	LocaleManager.locale_changed.connect(_on_locale_changed)

	_set_status(tr("MAIL_LOADING"), MUTED)
	NetworkManager.fetch_mail()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(
		["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


# =========================================================
# CONSTRUCTION (100 % code — patron war_manual.gd)
# =========================================================
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
	pan.name = "MailPanel"
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

	# --- En-tête : eyebrow + titre + FERMER ---
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)

	var head_col := VBoxContainer.new()
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_col.add_theme_constant_override("separation", 2)
	head.add_child(head_col)

	var eyebrow := Label.new()
	eyebrow.text = "MAIL_EYEBROW"
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", MUTED)
	head_col.add_child(eyebrow)

	var big := Label.new()
	big.text = "MAIL_TITLE"
	big.add_theme_font_override("font", _font)
	big.add_theme_font_size_override("font_size", 26)
	big.add_theme_color_override("font_color", ACCENT)
	head_col.add_child(big)

	var close_btn := Button.new()
	close_btn.text = "MAIL_CLOSE"
	close_btn.add_theme_font_override("font", _font)
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	WarzoneUI.apply_ghost_button(close_btn)
	WarzoneUI.wire_button_sfx(close_btn)
	close_btn.pressed.connect(_close)
	head.add_child(close_btn)

	WarzoneUI.add_filet(col)

	# --- Corps : liste | détail ---
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 20)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(list_scroll)
	_list_scroll = list_scroll

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_list_box)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(detail_scroll)

	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(_detail_box)
	_detail_scroll = detail_scroll

	# --- ÉTAT VIDE : son PROPRE bloc, centré sur TOUTE la surface du corps -----------------------
	# Une boîte vide n'a pas de liste : elle n'a qu'un message. Les deux colonnes sont donc
	# MASQUÉES et celui-ci prend leur place — plutôt qu'un « AUCUN COURRIER » tassé en haut à gauche
	# d'un panneau de 1000×620 vide (défaut de la première version, vu SUR CAPTURE).
	_empty_box = CenterContainer.new()
	_empty_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_box.visible = false
	split.add_child(_empty_box)

	var empty_col := VBoxContainer.new()
	empty_col.add_theme_constant_override("separation", 8)
	_empty_box.add_child(empty_col)

	var empty := Label.new()
	empty.text = "MAIL_EMPTY"
	empty.add_theme_font_override("font", _font)
	empty.add_theme_font_size_override("font_size", 20)
	empty.add_theme_color_override("font_color", MUTED)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_col.add_child(empty)

	var hint := Label.new()
	hint.text = "MAIL_EMPTY_HINT"
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(MUTED, 0.7))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_col.add_child(hint)

	_status = Label.new()
	_status.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_status.add_theme_font_override("font", _font)
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)


# =========================================================
# DONNÉES
# =========================================================
func _on_mail_loaded(data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant une fermeture.
	_claim_in_flight = 0
	var rows = data.get("mails", [])
	_mails = rows if typeof(rows) == TYPE_ARRAY else []
	# Sélection PRÉSERVÉE d'un rafraîchissement à l'autre quand c'est possible : après un claim on
	# re-fetche, et le joueur doit rester sur le pli qu'il vient d'ouvrir.
	if _selected_id != 0 and _find(_selected_id).is_empty():
		_selected_id = 0
	if _selected_id == 0 and not _mails.is_empty():
		_selected_id = int(_mails[0].get("id", 0))
	_render_list()
	_render_detail()
	_set_status("", MUTED)


func _on_locale_changed(_code: String) -> void:
	# Les libellés composés (« PIÈCE JOINTE : 200 COINS ») sont posés par `tr()` en code → ils ne se
	# re-traduisent pas seuls. On repeint depuis le cache, sans aller-retour réseau.
	if not is_inside_tree():
		return
	_render_list()
	_render_detail()


func _find(mail_id: int) -> Dictionary:
	for m in _mails:
		if typeof(m) == TYPE_DICTIONARY and int(m.get("id", 0)) == int(mail_id):
			return m
	return {}


# =========================================================
# LISTE (gauche)
# =========================================================
func _render_list() -> void:
	if _list_box == null:
		return
	_clear(_list_box)
	# 🩸 ÉTAT VIDE : la colonne de gauche est MASQUÉE, et le message occupe toute la largeur du
	# panneau, CENTRÉ. La première version le laissait dans la colonne étroite : un « AUCUN
	# COURRIER » tassé en haut à gauche d'un panneau de 1000×620 vide — défaut invisible en test
	# (le Label existait, avec le bon texte) et trouvé UNIQUEMENT en relisant la capture.
	# Une liste vide n'a pas de liste : elle n'a qu'un message.
	var empty := _mails.is_empty()
	if _list_scroll != null and is_instance_valid(_list_scroll):
		_list_scroll.visible = not empty
	if _detail_scroll != null and is_instance_valid(_detail_scroll):
		_detail_scroll.visible = not empty
	if _empty_box != null and is_instance_valid(_empty_box):
		_empty_box.visible = empty
	if empty:
		return
	for m in _mails:
		if typeof(m) == TYPE_DICTIONARY:
			_list_box.add_child(_make_list_row(m))


func _make_list_row(m: Dictionary) -> Control:
	# Piège JSON float §5 : tout ce qui vient du réseau passe par int()/bool().
	var mail_id := int(m.get("id", 0))
	var is_read := bool(m.get("read", false))
	var claimed := bool(m.get("claimed", false))
	var coins := int(m.get("coins_attached", 0))
	var expires := int(m.get("expires_at_epoch", 0))
	var selected := mail_id == _selected_id

	var row := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(ACCENT, 0.10) if selected else Color(1, 1, 1, 0.03)
	st.set_corner_radius_all(0)
	st.border_width_left = 3
	# Non lu → OR (il y a quelque chose à faire) ; lu → cyan si sélectionné, muet sinon.
	st.border_color = GOLD if not is_read else (ACCENT if selected else Color(MUTED, 0.5))
	st.set_content_margin_all(10)
	row.add_theme_stylebox_override("panel", st)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	row.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)

	# Point OR devant un pli non lu — même glyphe que les pastilles de la nav (`●`, ASCII-safe :
	# aucun emoji, aucun tofu avec la police condensée de la charte, constat §8.117/§8.123).
	if not is_read:
		var dot := Label.new()
		dot.text = "●"
		dot.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		dot.add_theme_font_override("font", _font)
		dot.add_theme_font_size_override("font_size", 13)
		dot.add_theme_color_override("font_color", GOLD)
		top.add_child(dot)

	var title := Label.new()
	# ⚠️ TEXTE LIBRE DE L'OPÉRATEUR (dérogation R4 de CONTENU) : jamais une clé, donc jamais
	# auto-traduit — sans quoi Godot chercherait « Compensation incident » dans le catalogue.
	title.text = str(m.get("title", ""))
	title.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", TEXT if not is_read else MUTED)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	# Trombone : pièce jointe NON ENCORE réclamée. Dessiné, pas un emoji (cf. `PaperclipGlyph`).
	if coins > 0 and not claimed:
		var clip := PaperclipGlyph.new()
		# 20 px et non 16 : à 16, les trois rails du trombone se touchent et la silhouette redevient
		# une tache. Mesuré SUR CAPTURE, pas supposé.
		clip.custom_minimum_size = Vector2(20, 20)
		clip.color = GOLD
		clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(clip)

	# Compte à rebours COMPACT sous 48 h — le composant maison, jamais un format réécrit (§8.134).
	var remaining := expires - int(Time.get_unix_time_from_system())
	if expires > 0 and remaining < URGENT_WINDOW_S:
		var cd = CountdownLabel.make(11, MUTED)
		cd.custom_minimum_size.x = 0.0     # compact : la largeur réservée du composant est pour le détail
		cd.set_target(expires, "MAIL_EXPIRES_IN")
		# Un pli qui meurt SOUS LES YEUX du joueur : on recharge, il disparaît de la liste.
		cd.expired.connect(_on_mail_expired)
		v.add_child(cd)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(_on_row_pressed.bind(mail_id))
	row.add_child(btn)
	return row


## Trombone DESSINÉ par code — même doctrine que le `PowerGlyph` de `top_nav.gd` (§8.102) : les
## caractères « trombone » n'existent que dans les polices emoji et rendent en TOFU avec la police
## condensée de la charte.
##
## 🩸 **Une première version fermait la silhouette en haut ET en bas** : deux arcs opposés plus deux
## verticales donnent une CAPSULE, pas un trombone — à 16 px, le rendu se lisait « 0 ». Défaut
## invisible en test (le nœud existait, il était de la bonne taille, il était de la bonne couleur) et
## trouvé UNIQUEMENT en relisant la capture. Un trombone, c'est un tracé **OUVERT** : un grand U,
## une remontée, un demi-tour serré, et une redescente plus courte À L'INTÉRIEUR. Ce sont les DEUX
## niveaux d'imbrication qui le font reconnaître, pas la boucle.
class PaperclipGlyph extends Control:
	var color: Color = Color.WHITE:
		set(v):
			color = v
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var width := maxf(1.5, w * 0.10)
		# Trois « rails » verticaux : extérieur gauche, extérieur droit, intérieur. L'écart entre
		# eux est ce qui reste lisible quand le glyphe tombe à 16 px.
		var x_left := w * 0.30
		var x_right := w * 0.70
		var x_inner := w * 0.50
		var y_top := h * 0.20
		var y_bottom := h * 0.72
		var r_big := (x_right - x_left) * 0.5
		var r_small := (x_right - x_inner) * 0.5

		# 1. Grand U : descente à gauche, demi-tour en bas, remontée à droite.
		draw_line(Vector2(x_left, y_top), Vector2(x_left, y_bottom - r_big), color, width, true)
		draw_arc(Vector2((x_left + x_right) * 0.5, y_bottom - r_big), r_big, PI, 0.0, 16,
				color, width, true)
		draw_line(Vector2(x_right, y_bottom - r_big), Vector2(x_right, y_top + r_small),
				color, width, true)
		# 2. Demi-tour SERRÉ en haut à droite, puis redescente INTÉRIEURE — plus courte, pour que
		#    l'œil voie qu'elle est « dedans » et non un troisième trait parallèle.
		draw_arc(Vector2((x_inner + x_right) * 0.5, y_top + r_small), r_small, 0.0, -PI, 16,
				color, width, true)
		draw_line(Vector2(x_inner, y_top + r_small), Vector2(x_inner, y_bottom - r_big * 0.55),
				color, width, true)


# =========================================================
# DÉTAIL (droite)
# =========================================================
func _render_detail() -> void:
	if _detail_box == null:
		return
	_clear(_detail_box)
	# L'état vide vit dans son PROPRE bloc centré (cf. `_build`) — pas ici : un `SIZE_EXPAND_FILL`
	# ne s'étire pas dans un `ScrollContainer`, dont l'enfant prend sa taille MINIMALE sur l'axe qui
	# défile. Des spacers y auraient produit un centrage strictement décoratif.
	if _mails.is_empty():
		return
	var m := _find(_selected_id)
	if m.is_empty():
		return

	var title := Label.new()
	title.text = str(m.get("title", ""))     # texte libre — jamais auto-traduit (cf. la liste)
	title.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", GOLD)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(title)
	WarzoneUI.add_filet(_detail_box, 1)

	# Méta : l'échéance, toujours — c'est elle qui dit qu'il y a urgence ou pas.
	var expires := int(m.get("expires_at_epoch", 0))
	if expires > 0:
		var cd = CountdownLabel.make(13, MUTED)
		cd.set_target(expires, "MAIL_EXPIRES_IN")
		cd.expired.connect(_on_mail_expired)
		_detail_box.add_child(cd)

	# ⚠️⚠️ LE CORPS : `bbcode_enabled = false`. C'est LA garde de la dérogation R4 (cf. en-tête).
	var body := RichTextLabel.new()
	body.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	body.bbcode_enabled = false
	body.fit_content = true
	body.text = str(m.get("body", ""))
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_override("normal_font", _font)
	body.add_theme_font_size_override("normal_font_size", 16)
	body.add_theme_constant_override("line_separation", 5)
	body.add_theme_color_override("default_color", TEXT)
	_detail_box.add_child(body)

	var coins := int(m.get("coins_attached", 0))
	if coins <= 0:
		return   # message simple : pas de bloc pièce jointe, pas de bouton.

	WarzoneUI.add_filet(_detail_box, 1)

	var attach := HBoxContainer.new()
	attach.add_theme_constant_override("separation", 16)
	_detail_box.add_child(attach)

	var label := Label.new()
	label.text = tr("MAIL_ATTACHMENT") % coins
	label.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", GOLD)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	attach.add_child(label)

	var claimed := bool(m.get("claimed", false))
	var mail_id := int(m.get("id", 0))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(180, 46)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 15)
	btn.focus_mode = Control.FOCUS_NONE
	if claimed:
		btn.text = tr("MAIL_CLAIMED")
		btn.disabled = true
		btn.add_theme_color_override("font_color", MUTED)
		btn.add_theme_color_override("font_disabled_color", MUTED)
	else:
		btn.text = tr("MAIL_CLAIM_CTA")
		btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		_style_claim_button(btn)
		WarzoneUI.wire_button_sfx(btn)
		# ⚠️ Un claim DÉJÀ en vol laisse le bouton désactivé : le verrou survit au re-rendu.
		btn.disabled = _claim_in_flight != 0
		btn.pressed.connect(_on_claim_pressed.bind(mail_id, btn))
	attach.add_child(btn)


func _style_claim_button(btn: Button) -> void:
	# Copie conforme du bouton RÉCLAMER des DÉFIS (`missions_panel._style_claim_button`) : réclamer
	# est le MÊME geste, il doit avoir la même apparence partout dans le jeu.
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(GOLD, 0.14)
	sb.set_border_width_all(2)
	sb.border_color = GOLD
	sb.set_content_margin_all(8)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(GOLD, 0.30)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", GOLD)
	btn.add_theme_color_override("font_hover_color", TEXT)


# =========================================================
# INTERACTIONS
# =========================================================
func _on_row_pressed(mail_id: int) -> void:
	AudioManager.play_sfx("click")
	_selected_id = int(mail_id)
	var m := _find(_selected_id)
	# ACCUSÉ DE LECTURE — fire-and-forget : l'échec réseau ne doit pas empêcher de LIRE.
	if not m.is_empty() and not bool(m.get("read", false)):
		m["read"] = true                     # décrément LOCAL immédiat (patron missions)…
		NetworkManager.mail_mark_read(_selected_id)
		badge_dirty.emit()                   # …et la nav se réconcilie au prochain fetch.
	_render_list()
	_render_detail()


func _on_claim_pressed(mail_id: int, btn: Button) -> void:
	if _claim_in_flight != 0:
		return   # un claim est déjà en vol : on ignore (anti double-appel côté UI).
	_claim_in_flight = int(mail_id)
	btn.disabled = true
	NetworkManager.claim_mail(int(mail_id))


func _on_claimed(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	_claim_in_flight = 0
	AudioManager.play_sfx("confirm")
	_set_status(tr("MAIL_CLAIM_OK") % int(data.get("coins", 0)), GOLD)
	# La nav écoute le MÊME signal `mail_claimed` et met sa jauge à jour depuis `balance_after` —
	# aucun appel réseau de plus, et ce modal reste une vue PURE (il ne connaît pas la nav).
	badge_dirty.emit()
	NetworkManager.fetch_mail()   # source de vérité serveur : l'état `claimed` vient de lui.


func _on_claim_failed(reason: String) -> void:
	if not is_inside_tree():
		return
	_claim_in_flight = 0
	# `already_claimed` : l'autre onglet a gagné, et c'est une BONNE nouvelle — l'argent est chez le
	# joueur. On se réconcilie SANS erreur visible plutôt que d'inquiéter pour un succès.
	if reason == "already_claimed":
		_set_status("", MUTED)
	else:
		_set_status(_refusal_text(reason), DANGER if reason != "expired" else GOLD)
	NetworkManager.fetch_mail()


## Raison canonique → texte i18n. Une raison INCONNUE (serveur plus récent que ce build) retombe sur
## le message générique — plus jamais un écran muet, c'est la leçon du LOT 4 de ce même chantier.
func _refusal_text(reason: String) -> String:
	match reason:
		"expired":
			return tr("MAIL_EXPIRED")
		"no_attachment":
			return tr("MAIL_NO_ATTACHMENT")
		"unavailable":
			return tr("MAIL_CLAIM_FAILED")
		_:
			return tr("MAIL_CLAIM_FAILED")


## Un pli est mort pendant que le modal était ouvert : le rebours a atteint zéro. On RECHARGE — le
## serveur ne sert plus les expirés, le pli disparaît de la liste et son bouton avec lui. C'est le
## composant `countdown_label` qui prévient (signal `expired`), on ne surveille rien nous-mêmes.
func _on_mail_expired() -> void:
	if not is_inside_tree():
		return
	badge_dirty.emit()
	NetworkManager.fetch_mail()


func _set_status(text: String, color: Color) -> void:
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	# ÉCHAP referme le COURRIER — et SEULEMENT lui : `set_input_as_handled` empêche la nav de
	# ramener au QG dans la foulée (patron `war_manual.gd`).
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
