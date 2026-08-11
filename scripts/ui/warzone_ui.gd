extends RefCounted

# =========================================================
# Helpers UI partagés — charte « Warzone Command » (§2)
# =========================================================
# Centralise les ornements angulaires de la charte pour éviter de dupliquer le code dans
# chaque écran. Chargé par preload (PAS via class_name) côté écrans : robuste au cache d'import
# (même prudence que faction_selection.gd / board.gd vis-à-vis de l'enregistrement des classes).

const NOTCH_SIZE := 18.0
const NOTCH_COLOR := Color("36c5d9")

# Couleurs canoniques de la charte (§2) — exposées ici pour mutualiser les ornements.
const ACCENT := Color("36c5d9")   # cyan tactique (interactif)
const GOLD := Color("e0b249")     # or (récompense / prix)
const GUNMETAL := Color("0f1318") # fond gunmetal (texte sur badge clair)
const TEXT := Color("eef3f7")     # texte primaire (blanc froid)
const MUTED := Color("8a97a5")    # texte muet (acier)

# Halo néon cyan (silhouette du biohazard floutée) posé derrière la marque du logo (§8.63).
const MARK_GLOW := preload("res://assets/images/logo_mark_glow.png")
const MARK_GLOW_SCALE := 1.7

# Ajoute deux encoches de coin biseautées (petits triangles cyan, haut-gauche / bas-droite) qui
# « mordent » les angles d'un panneau → rappel de l'ADN angulaire Warzone sans texture 9-patch.
# Les triangles sont repositionnés à chaque resize (un panneau dimensionné par un conteneur n'a
# sa taille réelle qu'APRÈS la passe de layout). Idempotent (garde par méta).
static func add_corner_notches(panel: Control, notch_size: float = NOTCH_SIZE, color: Color = NOTCH_COLOR) -> void:
	if panel == null or panel.has_meta("ww_notched"):
		return
	panel.set_meta("ww_notched", true)

	var tl := Polygon2D.new()
	tl.name = "Notch_tl"
	tl.color = color
	panel.add_child(tl)

	var br := Polygon2D.new()
	br.name = "Notch_br"
	br.color = color
	panel.add_child(br)

	var relayout := func() -> void:
		tl.position = Vector2.ZERO
		tl.polygon = PackedVector2Array([Vector2.ZERO, Vector2(notch_size, 0.0), Vector2(0.0, notch_size)])
		br.position = panel.size
		br.polygon = PackedVector2Array([Vector2.ZERO, Vector2(-notch_size, 0.0), Vector2(0.0, -notch_size)])

	panel.resized.connect(relayout)
	relayout.call()

# Construit un badge « hexagone » (ADN angulaire Warzone §2) : un Polygon2D hexagonal plein
# surmonté d'un libellé centré. Utilisé pour les compteurs/prix (ex. prix en or de la Boutique R1,
# quantité d'un objet d'inventaire). Taille fixe → pas de relayout nécessaire (le Polygon2D dessine
# dans l'espace local [0, diameter] du Control hôte, dimensionné par son conteneur via custom_minimum_size).
static func make_hex_badge(text: String, font: Font, font_size: int, fill: Color, text_color: Color, diameter: float = 52.0) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(diameter, diameter)
	root.size = Vector2(diameter, diameter)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hex := Polygon2D.new()
	hex.name = "Hex"
	hex.color = fill
	var c := diameter * 0.5
	var r := diameter * 0.5
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0 * float(i) - 90.0) # pointe en haut
		pts.append(Vector2(c + r * cos(a), c + r * sin(a)))
	hex.polygon = pts
	root.add_child(hex)

	var lbl := Label.new()
	lbl.name = "Value"
	lbl.text = text
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", text_color)
	root.add_child(lbl)

	return root

# Applique le style « ghost » de la charte (§2) à un bouton : fond quasi transparent + fin liseré
# cyan, fond cyan léger au survol, texte qui s'illumine en cyan. Angulaire (corner_radius 0).
# Mutualise le style construit en code répété dans le HUD / les écrans (R6).
# Pastille « i » qui OUVRE UN PANNEAU MODAL d'explication.
#
# ⚠️ MODAL, PAS une infobulle au survol (correction §8.125) : la 1ʳᵉ version posait un
# `tooltip_text`, qui ne se déclenchait pas de façon fiable et — surtout — ne ressemblait EN RIEN au
# détail des points du Classement, la référence maison. Le projet a déjà SON vocabulaire pour « je
# t'explique une règle » : un voile sombre + un panneau bordé cyan qu'on referme en cliquant
# n'importe où (`leaderboard._build_rules_overlay`). On le reproduit ici plutôt que d'inventer un
# second dialecte.
#
# `parent_screen` reçoit le voile (il doit couvrir TOUT l'écran, pas seulement la ligne du titre).
# ⚠️ La lettre « i » et non un glyphe « ⓘ » : les symboles hors ASCII rendent en TOFU dès que la
# police de repli change. Le cercle est dessiné par StyleBox, pas par le texte.
static func make_info_badge(parent_screen: Control, title: String, body: String,
							font: Font = null, diameter: float = 22.0) -> Control:
	var badge := Button.new()
	badge.text = "i"
	badge.focus_mode = Control.FOCUS_NONE
	badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	badge.custom_minimum_size = Vector2(diameter, diameter)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if font != null:
		badge.add_theme_font_override("font", font)
	badge.add_theme_font_size_override("font_size", int(diameter * 0.62))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.30 if state == "hover" else 0.12)
		sb.set_corner_radius_all(int(diameter / 2.0))
		sb.set_border_width_all(1)
		sb.border_color = Color(ACCENT, 0.95 if state == "hover" else 0.6)
		sb.set_content_margin_all(0.0)
		badge.add_theme_stylebox_override(state, sb)
	badge.add_theme_color_override("font_color", ACCENT)
	badge.add_theme_color_override("font_hover_color", Color.WHITE)
	badge.pressed.connect(func() -> void:
		_open_info_modal(parent_screen, title, body, font))
	return badge


# Voile + panneau d'explication — MÊME construction que `leaderboard._build_rules_overlay` : fond
# noir à 60 %, panneau gunmetal bordé cyan, fermeture au clic N'IMPORTE OÙ (aucun bouton « fermer »
# à chercher). Créé à la volée puis libéré : rien ne reste en mémoire une fois lu.
static func _open_info_modal(screen: Control, title: String, body: String, font: Font) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	var veil := ColorRect.new()
	veil.name = "InfoOverlay"
	veil.color = Color(0, 0, 0, 0.6)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			veil.queue_free())
	screen.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(center)

	var pan := PanelContainer.new()
	pan.custom_minimum_size = Vector2(730, 0)   # +30 %, même respiration que les écrans hôtes.
	pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = ACCENT
	st.set_content_margin_all(32.0)
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 10
	pan.add_theme_stylebox_override("panel", st)
	center.add_child(pan)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pan.add_child(col)

	var head := Label.new()
	head.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	head.text = title
	if font != null:
		head.add_theme_font_override("font", font)
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	add_filet(col)

	var text := Label.new()
	text.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	text.text = body
	if font != null:
		text.add_theme_font_override("font", font)
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", Color("eef3f7"))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)

	var hint := Label.new()
	hint.text = "COMMON_CLICK_TO_CLOSE"  # clé brute -> auto-traduction
	if font != null:
		hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color("8a97a5"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)


static func apply_ghost_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := StyleBoxFlat.new()
	normal.set_corner_radius_all(0)
	normal.content_margin_left = 16.0
	normal.content_margin_top = 10.0
	normal.content_margin_right = 16.0
	normal.content_margin_bottom = 10.0
	normal.bg_color = Color(1, 1, 1, 0.03)
	normal.set_border_width_all(1)
	normal.border_color = Color(ACCENT, 0.6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT, 0.16)
	hover.border_color = ACCENT
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", ACCENT)


# Câble les SFX d'interface (survol/clic — AudioManager R6, placeholders procéduraux) sur un
# bouton. No-op si null. AudioManager est un autoload (accessible par son nom global) et la lecture
# est neutralisée sous headless → sans danger en validation CLI.
static func wire_button_sfx(btn: Button) -> void:
	if btn == null:
		return
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	btn.pressed.connect(func() -> void: AudioManager.play_sfx("click"))


# Câble les SFX sur une liste de boutons (entrées nulles ignorées).
static func wire_buttons_sfx(buttons: Array) -> void:
	for b in buttons:
		wire_button_sfx(b)


# =========================================================
# POLISH TRANSVERSE DES ÉCRANS HUB (§8.96)
# =========================================================
# Feedback interactif UNIFORME : SFX de survol/clic (wire_button_sfx) + LUEUR cyan légère au survol.
# ⚠️ N'ÉCRASE AUCUN StyleBox : la lueur passe par `modulate` (multiplicatif), donc les styles propres
# à chaque écran (ghost, CTA, or…) sont préservés — on n'ajoute que les signaux manquants.
# Idempotent (garde par méta) → sans danger sur un bouton déjà câblé par son écran.
static func wire_button_feedback(btn: Button) -> void:
	if btn == null or btn.has_meta("ww_feedback"):
		return
	btn.set_meta("ww_feedback", true)
	wire_button_sfx(btn)
	btn.mouse_entered.connect(func() -> void:
		if is_instance_valid(btn):
			btn.modulate = HOVER_GLOW)
	btn.mouse_exited.connect(func() -> void:
		if is_instance_valid(btn):
			btn.modulate = Color(1, 1, 1, 1))

# Teinte de survol : blanc légèrement sur-exposé → « allume » n'importe quel style sans le redéfinir.
const HOVER_GLOW := Color(1.18, 1.18, 1.18, 1.0)

static func wire_buttons_feedback(buttons: Array) -> void:
	for b in buttons:
		wire_button_feedback(b)


# Animation d'ENTRÉE d'écran commune (§8.96) : fondu alpha 0→1 + léger glissement vertical, appelée
# au `_ready()` de chaque écran hub APRÈS construction. Volontairement DISCRÈTE et identique partout.
# ⚠️ Jamais `Engine.time_scale` (qui affecterait tout le jeu) : un Tween local, borné à ce Control.
# Les transitions ENTRE scènes restent gérées par TransitionManager (fondu) — on ne les touche pas.
# No-op headless (le pilote « Dummy » ne rend rien, mais le tween reste inoffensif) et robuste si le
# nœud sort de l'arbre pendant l'animation (le Tween est lié au nœud → tué avec lui).
const SCREEN_ENTER_TIME := 0.18
const SCREEN_ENTER_OFFSET := 12.0

static func animate_screen_enter(root: Control) -> void:
	if root == null or not is_instance_valid(root):
		return
	var start := root.position
	root.modulate = Color(1, 1, 1, 0)
	root.position = start + Vector2(0, SCREEN_ENTER_OFFSET)
	# `create_tween()` sur le nœud : automatiquement libéré avec lui (aucune fuite au changement de scène).
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_QUAD)
	tw.tween_property(root, "modulate:a", 1.0, SCREEN_ENTER_TIME)
	tw.tween_property(root, "position", start, SCREEN_ENTER_TIME)


# Ajoute un filet fin cyan (HSeparator stylé) comme enfant de `parent`. Renvoie le séparateur
# (utile pour le repositionner / régler son `size_flags`). Mutualise l'ornement de charte (§2).
static func add_filet(parent: Node, thickness: int = 2, color: Color = ACCENT) -> HSeparator:
	var sep := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(color, 0.5)
	line.thickness = thickness
	sep.add_theme_stylebox_override("separator", line)
	if parent:
		parent.add_child(sep)
	return sep


# Pose un halo néon cyan DERRIÈRE une marque (TextureRect du logo biohazard §8.63) : un enfant
# `show_behind_parent` ancré au centre, boîte fixe `mark_px * scale` → il DÉBORDE visuellement
# SANS toucher au layout (la marque garde sa taille ; aucune régression de mise en page). Idempotent
# (garde par méta). `strength` = opacité (modulate) ; <= 0 → pas de halo. `mark_px` = côté de la
# marque (ex. mark_size de ww_logo, ou 54 pour la petite icône de la top-bar).
static func attach_mark_glow(mark: TextureRect, mark_px: float, strength: float = 1.0, scale: float = MARK_GLOW_SCALE) -> void:
	if mark == null or strength <= 0.0 or mark.has_meta("ww_glow"):
		return
	mark.set_meta("ww_glow", true)
	var glow := TextureRect.new()
	glow.name = "MarkGlow"
	glow.texture = MARK_GLOW
	glow.show_behind_parent = true
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(1.0, 1.0, 1.0, strength)
	var gside := mark_px * scale
	glow.anchor_left = 0.5
	glow.anchor_top = 0.5
	glow.anchor_right = 0.5
	glow.anchor_bottom = 0.5
	glow.offset_left = -gside * 0.5
	glow.offset_top = -gside * 0.5
	glow.offset_right = gside * 0.5
	glow.offset_bottom = gside * 0.5
	mark.add_child(glow)


# =========================================================
# FRAIS D'INSCRIPTION — LA PHRASE QUI EXPLIQUE LE PRIX (chantier CORRECTIFS ÉCONOMIQUES)
# =========================================================
# UNE SEULE RÈGLE D'AFFICHAGE, ICI, pour les TROIS surfaces qui montrent un péage (recherche
# Battle Royale, adhésion à une compagnie, entrée d'événement). Elles la dupliquaient chacune à sa
# façon, et les trois se sont trompées de la même manière.
#
# 🩸 LE DÉFAUT QU'ELLE FERME. Chaque écran testait `fee_with_pass < fee` pour décider s'il devait
# parler du Pass. Cette condition est FAUSSE pour un DÉTENTEUR : le serveur lui sert déjà son tarif
# remisé, donc `fee == fee_with_pass` et l'écran se taisait. Résultat rapporté en jeu : « 50 réglé
# au panel, 25 affiché » — un prix moitié moindre que l'annonce, sans un mot d'explication. Ce
# n'était pas un bug de calcul (25 est exact) : c'était un bug de LISIBILITÉ, et il fallait le
# `fee_base` du serveur pour le réparer.
#
# Renvoie `{ "text": String, "owned": bool }` — `text` vide = il n'y a RIEN à dire (ne rien
# afficher). `owned` distingue les deux tons : l'avantage que le lecteur EXERCE (or, il en profite
# maintenant) de l'argument de vente adressé à qui n'a pas le Pass (muet, on propose sans insister).
# ⛔ Un frais à 0 ne dit JAMAIS rien : écrire la gratuité en prix la transforme en tarif.
static func fee_pass_hint(fee: int, fee_base: int, fee_with_pass: int) -> Dictionary:
	var mute := {"text": "", "owned": false}
	if fee_base <= 0:
		return mute                                     # activité gratuite : silence total.
	if fee <= 0:
		# Le lecteur est EXONÉRÉ alors qu'un prix existe : c'est l'avantage le plus fort du Pass,
		# et sans cette ligne il était rigoureusement invisible (le prix disparaissait, point).
		return {"text": _tr("FEE_OFFERED_PASS"), "owned": true}
	if fee_base > fee:
		return {"text": _tr("FEE_PASS_APPLIED") % fee_base, "owned": true}
	# À partir d'ici le lecteur paie le plein tarif : on lui dit ce que le Pass changerait.
	if fee_with_pass <= 0:
		return {"text": _tr("FEE_FREE_WITH_PASS"), "owned": false}
	if fee_with_pass < fee:
		return {"text": _tr("FEE_HALF_WITH_PASS"), "owned": false}
	return mute


# Traduction depuis un contexte STATIQUE. ⛔ `tr()` est une méthode d'INSTANCE : dans une
# `static func` elle ne résout pas (le piège exact du §8.104, war_feed / identités de factions).
static func _tr(key: String) -> String:
	return String(TranslationServer.translate(key))


# =========================================================
# SÉLECTEUR DE LANGUE (Feuille de route R4) — FR / EN / IT
# =========================================================
# Construit un sélecteur de langue autonome (HBox de 3 boutons angulaires), câblé
# DIRECTEMENT sur l'autoload LocaleManager (Règle d'Or §6.1 : la logique de langue vit
# dans le manager, ce widget n'est qu'une Vue). Le bouton de la langue active est mis en
# surbrillance ; le widget se resynchronise sur le signal LocaleManager.locale_changed et
# se désabonne proprement à sa sortie de l'arbre (évite tout rappel sur des nœuds libérés).
# Réutilisable tel quel par n'importe quel écran (ex. main_menu, auth_screen, futur R5 Options).
static func build_language_selector() -> Control:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	font.font_weight = 700

	var root := HBoxContainer.new()
	root.name = "LanguageSelector"
	root.add_theme_constant_override("separation", 6)

	var globe := Label.new()
	globe.text = "❯"
	globe.add_theme_font_size_override("font_size", 18)
	globe.add_theme_color_override("font_color", MUTED)
	globe.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	globe.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	root.add_child(globe)

	# code de langue -> bouton (pour resynchroniser la surbrillance).
	var buttons := {}
	for code in LocaleManager.SUPPORTED:
		var btn := Button.new()
		btn.text = str(code).to_upper()
		btn.custom_minimum_size = Vector2(46, 34)
		btn.focus_mode = Control.FOCUS_NONE
		btn.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 16)
		# Capture de la valeur de boucle (sinon toutes les lambdas verraient le dernier code).
		var this_code: String = code
		btn.pressed.connect(func() -> void: LocaleManager.set_locale(this_code))
		root.add_child(btn)
		buttons[code] = btn

	_refresh_language_selector(buttons, LocaleManager.current_locale())

	# Resynchronisation vive + désabonnement à la destruction du widget.
	var on_changed := func(active: String) -> void: _refresh_language_selector(buttons, active)
	LocaleManager.locale_changed.connect(on_changed)
	root.tree_exiting.connect(func() -> void:
		if LocaleManager.locale_changed.is_connected(on_changed):
			LocaleManager.locale_changed.disconnect(on_changed))

	return root

# Restyle les boutons du sélecteur : actif = rempli cyan + texte blanc, inactif = ghost acier.
static func _refresh_language_selector(buttons: Dictionary, active_code: String) -> void:
	for code in buttons:
		var btn: Button = buttons[code]
		if not is_instance_valid(btn):
			continue
		var active := str(code) == active_code
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(0)
		sb.content_margin_left = 10.0
		sb.content_margin_top = 6.0
		sb.content_margin_right = 10.0
		sb.content_margin_bottom = 6.0
		if active:
			sb.bg_color = Color(ACCENT, 0.22)
			sb.set_border_width_all(2)
			sb.border_color = ACCENT
		else:
			sb.bg_color = Color(1, 1, 1, 0.03)
			sb.set_border_width_all(1)
			sb.border_color = Color(ACCENT, 0.45)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = Color(ACCENT, 0.32) if active else Color(ACCENT, 0.14)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", hover)
		btn.add_theme_stylebox_override("focus", sb)
		btn.add_theme_color_override("font_color", TEXT if active else MUTED)
		btn.add_theme_color_override("font_hover_color", TEXT)

# =========================================================================
# Identité du meneur de faction (refonte 2026-07-18)
# =========================================================================
# « GÉNÉRAL VIKTOR "IRONLINE" STAHL » : rang TRADUIT (clés RANK_GENERAL / RANK_CAPTAIN, via
# TranslationServer — utilisable depuis un helper static) + nom propre et callsign INVARIANTS
# (anglais, identiques dans toutes les langues). `f` = FactionData duck-typé (.get()) : un
# .tres legacy sans champs héros renvoie "" et l'appelant masque la ligne.
static func faction_leader_title(f) -> String:
	if f == null:
		return ""
	var raw_name = f.get("hero_name")
	var hero_name := str(raw_name) if raw_name != null else ""
	if hero_name == "":
		return ""
	var raw_rank = f.get("hero_rank")
	var rank_key := "RANK_GENERAL" if str(raw_rank) == "general" else "RANK_CAPTAIN"
	var rank := TranslationServer.translate(rank_key)
	var raw_callsign = f.get("hero_callsign")
	var callsign := str(raw_callsign) if raw_callsign != null else ""
	var full := hero_name
	if callsign != "":
		var parts := hero_name.split(" ", false, 1)
		if parts.size() == 2:
			full = "%s \"%s\" %s" % [parts[0], callsign, parts[1]]
		else:
			full = "%s \"%s\"" % [hero_name, callsign]
	return "%s %s" % [rank, full]
