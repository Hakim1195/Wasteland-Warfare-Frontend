extends RefCounted

# =========================================================================
# MODAL DE RÈGLES D'ÉVÉNEMENT (§8.132) — charte « Warzone Command » §2
# =========================================================================
# UN SEUL modal, DEUX points d'entrée : la carte ÉVÉNEMENT du QG et la carte principale de l'écran
# ÉVÉNEMENTS. Deux implémentations auraient été deux occasions d'afficher des règles différentes
# pour le même week-end — exactement le genre de divergence qu'un joueur repère en dix secondes.
#
# ⚠️⚠️ LE CLIENT NE POSSÈDE AUCUNE VALEUR D'ÉVÉNEMENT. Toutes les lignes affichées sont dérivées du
# bloc `rules` SERVI PAR LE SERVEUR (`events.snapshot_rules`, relayé par `GET /squad/playlists`) —
# patron `battle_royale.public_rules()` (§8.131). Rééquilibrer un événement au registre backend
# change ce que le joueur lit, sans redéployer le client. Ce fichier ne connaît que la FORME du
# bloc et la façon de la rendre en français, en anglais et en italien.
#
# Style calqué sur les modales maison (référence §8.125 : le modal du Classement, et le patron
# statique de `warzone_ui._open_info_modal`) — voile sombre cliquable, panneau gunmetal à liseré,
# encoches de coin, un bouton de fermeture.
#
# ⚠️⚠️ MODULE 100 % STATIQUE → `TranslationServer.translate`, JAMAIS `tr()`. `tr()` est une méthode
# d'`Object` : dans une fonction statique il n'y a pas d'instance, et l'appel échoue (piège maison
# §8.104, payé sur les modules d'identité de faction).

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)
const TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const MUTED := Color(0.541176, 0.592157, 0.647059, 1)

# Ordre d'affichage des effets — du plus STRUCTURANT (la carte change sous les pieds) au plus
# accessoire (les gains). Chaque entrée : [clé du snapshot, clé i18n, mode de rendu].
#   "flag"    : booléen → la ligne existe si vrai, sans valeur ;
#   "mult"    : entier  → la ligne existe si > 1, formatée avec ce multiplicateur ;
#   "percent" : nombre  → rendu en POURCENTAGE ENTIER du normal (0,5 → 50) ;
#   "bonus"   : nombre  → rendu en SURPLUS entier (1,5 → +50).
# ⚠️ Aucun float n'atteint jamais l'écran : tout est converti en entier avant formatage (« piège
# JSON float » §5 — `JSON.parse_string` rend des floats, et « ×2.0 » à l'écran fait amateur).
const RULE_ROWS := [
	["zone_teleport_per_player_turn", "EVENT_RULE_ZONE_TELEPORT", "flag"],
	["zone_growth_cap_multiplier", "EVENT_RULE_ZONE_GROWTH", "mult"],
	["phase_time_multiplier", "EVENT_RULE_PHASE_TIME", "percent"],
	["reinforcement_multiplier", "EVENT_RULE_REINFORCEMENTS", "bonus"],
	["card_value_multiplier", "EVENT_RULE_CARDS", "mult"],
	["xp_multiplier", "EVENT_RULE_XP", "mult"],
	["hero_coins_multiplier", "EVENT_RULE_HERO_COINS", "mult"],
]


# Traduction en contexte STATIQUE. `TranslationServer.translate` rend un StringName : la conversion
# explicite en String est indispensable avant tout `%` de formatage.
static func t(key: String) -> String:
	return String(TranslationServer.translate(key))


# Ouvre le modal AU-DESSUS de `host`. `event` = une entrée de `NetworkManager.events_config`
# (`{id, name_key, desc_key, starts_at_epoch, ends_at_epoch, rules}`). `is_active` colore le liseré
# (or = en cours, cyan = à venir), exactement comme la carte qui a servi de point d'entrée.
static func open(host: Control, event: Dictionary, is_active: bool, font: Font) -> void:
	if host == null or not is_instance_valid(host) or event.is_empty():
		return
	var veil := ColorRect.new()
	veil.name = "EventRulesOverlay"
	veil.color = Color(0, 0, 0, 0.6)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			veil.queue_free())
	host.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.058824, 0.07451, 0.094118, 0.98)
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = GOLD if is_active else ACCENT
	st.set_content_margin_all(30.0)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	WarzoneUI.add_corner_notches(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	col.add_child(_label(t("EVENT_RULES_TITLE"), 13, GOLD if is_active else ACCENT, font,
		HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_label(t(str(event.get("name_key", ""))).to_upper(), 30, TEXT, font,
		HORIZONTAL_ALIGNMENT_CENTER))
	WarzoneUI.add_filet(col)

	var desc := _label(t(str(event.get("desc_key", ""))), 16, MUTED, font,
		HORIZONTAL_ALIGNMENT_CENTER)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)

	# --- Effets EXACTS, depuis le bloc servi par le serveur ---
	var rules = event.get("rules", {})
	var lines := rule_lines(rules if typeof(rules) == TYPE_DICTIONARY else {})
	if lines.is_empty():
		# Snapshot indisponible (serveur antérieur au chantier) : on ne fabrique RIEN. Une liste
		# vide se dit ; une liste inventée se paie.
		col.add_child(_label(t("EVENT_RULE_NONE"), 15, MUTED, font, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		for line in lines:
			col.add_child(_label("❯  " + line, 16, TEXT, font))

	WarzoneUI.add_filet(col)
	var scope := _label(t("EVENT_SCOPE_NOTE"), 13, MUTED, font, HORIZONTAL_ALIGNMENT_CENTER)
	scope.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(scope)

	var close := Button.new()
	close.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	# `MANUAL_CLOSE` (« FERMER ») : libellé de fermeture DÉJÀ traduit du Manuel de Guerre — on
	# réutilise plutôt que d'ajouter une clé de plus pour le même mot.
	close.text = t("MANUAL_CLOSE")
	close.custom_minimum_size = Vector2(200, 44)
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.add_theme_font_override("font", font)
	close.add_theme_font_size_override("font_size", 16)
	WarzoneUI.apply_ghost_button(close)
	WarzoneUI.wire_button_sfx(close)
	close.pressed.connect(func() -> void: veil.queue_free())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(close)
	col.add_child(row)


# Lignes d'effets LISIBLES dérivées d'un snapshot serveur. FONCTION PURE (aucun nœud) — c'est elle
# que le rappel de règles de l'arène réutilise (LOT D), pour que le joueur lise EXACTEMENT les
# mêmes phrases au QG et en partie. Snapshot vide / neutre → liste VIDE (jamais une ligne « rien
# ne change », qui serait du bruit).
static func rule_lines(rules: Dictionary) -> Array:
	var out: Array = []
	for row in RULE_ROWS:
		var key: String = row[0]
		var i18n: String = row[1]
		var mode: String = row[2]
		if not rules.has(key):
			continue
		match mode:
			"flag":
				if bool(rules[key]):
					out.append(t(i18n))
			"mult":
				var m := int(rules[key])
				if m > 1:
					out.append(t(i18n) % m)
			"percent":
				var p := int(round(float(rules[key]) * 100.0))
				if p != 100:
					out.append(t(i18n) % p)
			"bonus":
				var b := int(round((float(rules[key]) - 1.0) * 100.0))
				if b != 0:
					out.append(t(i18n) % b)
	return out


static func _label(text: String, font_size: int, color: Color, font: Font,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	# Textes DÉJÀ traduits (ou composés) : l'auto-traduction de Godot les re-chercherait comme des
	# clés et rendrait la chaîne brute. Piège maison, cf. company_screen._label.
	l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l
