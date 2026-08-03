extends VBoxContainer

# =========================================================================
# PANNEAU DÉFIS — missions quotidiennes / hebdomadaires (§8.134)
# =========================================================================
# CE FICHIER EST UN DÉMÉNAGEMENT, PAS UNE RÉÉCRITURE. Tout ce qui suit vient de `missions.gd`
# (lot M2 §8.65, renommé DÉFIS en §8.92) : mêmes boîtes quotidien/hebdo, mêmes décomptes de reset,
# même claim avec verrou `_claim_in_flight`, mêmes signaux, mêmes clés i18n. Seul l'EMBALLAGE
# change — le contenu n'est plus un écran, c'est un panneau HÉBERGEABLE, que l'onglet DÉFIS du hub
# ÉVÉNEMENTS monte tel quel.
#
# ⚠️ AUCUNE LOGIQUE DE MISSION N'A ÉTÉ TOUCHÉE. La progression reste 100 % serveur (`GET /missions`,
# `POST /missions/claim`) : ce panneau affiche et relaie, comme avant. Les routes n'ont pas bougé.
#
# View PURE (Règle d'Or §6.1). L'écran hôte n'a rien à faire d'autre que l'`add_child()` : le
# panneau s'abonne, déclenche son propre fetch et se rafraîchit seul.

const WarzoneUI = preload("res://scripts/ui/warzone_ui.gd")

const ACCENT := Color("36c5d9")
const GOLD := Color("e0b249")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
const DANGER := Color("d6453f")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)

var _font: Font
var _daily_box: VBoxContainer
var _weekly_box: VBoxContainer
var _daily_countdown: Label
var _weekly_countdown: Label
var _status: Label
# Échéances de reset (epoch UTC, dérivées des ISO serveur) — pilotent les comptes à rebours.
var _daily_reset_epoch: int = 0
var _weekly_reset_epoch: int = 0
# Anti double-clic : id de la mission dont le claim est EN VOL ("" = aucun).
var _claim_in_flight: String = ""
# Dernier payload `GET /missions` reçu — re-peint au changement de langue SANS aller-retour réseau.
# (L'écran d'origine ne gérait PAS la bascule de langue à chaud : c'est le seul ajout de ce
# déménagement, demandé par les contre-épreuves du chantier.)
var _last_data: Dictionary = {}


func _ready() -> void:
	_font = _make_font()
	add_theme_constant_override("separation", 12)
	_build()

	NetworkManager.missions_loaded.connect(_on_missions_loaded)
	NetworkManager.mission_claimed.connect(_on_mission_claimed)
	NetworkManager.mission_claim_failed.connect(_on_claim_failed)
	LocaleManager.locale_changed.connect(_on_locale_changed)

	_set_status(tr("MISSIONS_STATUS_LOADING"), MUTED)
	# La nav lance déjà `fetch_missions()` sur tous les écrans hub ; on re-demande quand même car le
	# panneau peut être monté APRÈS la réponse (ouverture directe sur l'onglet DÉFIS). Le serveur
	# assigne de façon lazy et DÉTERMINISTE : un appel de plus ne re-tire aucune mission.
	NetworkManager.fetch_missions()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	f.font_weight = 700
	return f


func _build() -> void:
	# --- Section QUOTIDIENNES : eyebrow + compte à rebours + liste ---
	var d_header := HBoxContainer.new()
	add_child(d_header)
	d_header.add_child(_label(tr("MISSIONS_DAILY"), 16, ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
	var d_spacer := Control.new()
	d_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_header.add_child(d_spacer)
	_daily_countdown = _label("--:--:--", 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	d_header.add_child(_daily_countdown)

	_daily_box = VBoxContainer.new()
	_daily_box.add_theme_constant_override("separation", 8)
	add_child(_daily_box)

	WarzoneUI.add_filet(self)

	# --- Section HEBDOMADAIRES ---
	var w_header := HBoxContainer.new()
	add_child(w_header)
	w_header.add_child(_label(tr("MISSIONS_WEEKLY"), 16, ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
	var w_spacer := Control.new()
	w_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w_header.add_child(w_spacer)
	_weekly_countdown = _label("--:--:--", 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	w_header.add_child(_weekly_countdown)

	_weekly_box = VBoxContainer.new()
	_weekly_box.add_theme_constant_override("separation", 8)
	add_child(_weekly_box)

	WarzoneUI.add_filet(self)

	_status = _label("", 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_status.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_status)


# =========================================================
# Peuplement depuis le serveur (missions_loaded)
# =========================================================
func _on_missions_loaded(data: Dictionary) -> void:
	if not is_inside_tree():
		return  # garde défensive : signal global reçu pendant un changement d'onglet/écran.
	_last_data = data
	_claim_in_flight = ""
	_fill(_daily_box, data.get("daily", []))
	_fill(_weekly_box, data.get("weekly", []))
	_daily_reset_epoch = _epoch_from_iso(str(data.get("daily_resets_at", "")))
	_weekly_reset_epoch = _epoch_from_iso(str(data.get("weekly_resets_at", "")))
	var claimable := int(data.get("claimable_count", 0))
	if claimable > 0:
		_set_status(tr("MISSIONS_STATUS_CLAIMABLE").format({"n": claimable}), GOLD)
	else:
		_set_status(tr("MISSIONS_STATUS_UP_TO_DATE"), MUTED)


# Changement de langue à chaud : les libellés de ce panneau sont posés par `tr()` en code (comme
# dans l'écran d'origine) → ils ne se re-traduisent pas seuls. On repeint depuis le cache, sans
# aller-retour réseau.
func _on_locale_changed(_code: String) -> void:
	if not is_inside_tree() or _last_data.is_empty():
		return
	_on_missions_loaded(_last_data)


func _fill(box: VBoxContainer, entries: Array) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if entries.is_empty():
		box.add_child(_label(tr("MISSIONS_STATUS_EMPTY"), 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT))
		return
	for m in entries:
		if typeof(m) == TYPE_DICTIONARY:
			box.add_child(_make_row(m))


# Rangée : intitulé + description | barre de progression cyan (or si complétée) + compteur |
# badge récompense Coins | bouton RÉCLAMER (or) / RÉCLAMÉE ✓ (muet).
func _make_row(m: Dictionary) -> Control:
	# Piège JSON §5 : nombres en float après parse → int() systématique.
	var cur := int(m.get("progress", 0))
	var goal := maxi(1, int(m.get("target", 1)))
	var completed := bool(m.get("completed", false))
	var claimed := bool(m.get("claimed", false))
	var reward := int(m.get("reward_coins", 0))
	var mission_id := str(m.get("mission_id", ""))

	var row := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.03)
	st.set_corner_radius_all(0)
	st.border_width_left = 3
	st.border_color = GOLD if (completed and not claimed) else (MUTED if claimed else ACCENT)
	st.set_content_margin_all(12)
	row.add_theme_stylebox_override("panel", st)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	row.add_child(hb)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	var name_lbl := _label(tr(str(m.get("name_key", ""))), 16, MUTED if claimed else TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(name_lbl)
	var desc_lbl := _label(tr(str(m.get("desc_key", ""))), 12, MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(desc_lbl)
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
	fg.bg_color = GOLD if completed else ACCENT
	fg.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	left.add_child(bar)
	hb.add_child(left)

	var counter := _label("%d/%d" % [cur, goal], 16,
		GOLD if completed else ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	counter.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	counter.custom_minimum_size = Vector2(76, 0)
	counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(counter)

	# Récompense en COINS (badge hexagonal or, valeur brute serveur — le ×1.5 Pass est appliqué
	# au claim par le serveur et affiché dans le statut).
	var badge := WarzoneUI.make_hex_badge(str(reward), _font, 13, GOLD, GUNMETAL, 52.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.tooltip_text = tr("MISSIONS_REWARD_TOOLTIP")
	hb.add_child(badge)

	# Bouton d'action : RÉCLAMER (or, actif) / RÉCLAMÉE ✓ (désactivé) / EN COURS (désactivé muet).
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 44)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.focus_mode = Control.FOCUS_NONE
	if claimed:
		btn.text = tr("MISSIONS_CLAIMED")
		btn.disabled = true
		btn.add_theme_color_override("font_color", MUTED)
		btn.add_theme_color_override("font_disabled_color", MUTED)
	elif completed:
		btn.text = tr("MISSIONS_CLAIM")
		_style_claim_button(btn)
		WarzoneUI.wire_button_sfx(btn)
		btn.pressed.connect(_on_claim_pressed.bind(mission_id, btn))
	else:
		btn.text = tr("MISSIONS_IN_PROGRESS")
		btn.disabled = true
		btn.add_theme_color_override("font_disabled_color", Color(MUTED, 0.6))
	hb.add_child(btn)
	return row


func _style_claim_button(btn: Button) -> void:
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
# Claim (POST /missions/claim) — anti double-clic + re-fetch
# =========================================================
func _on_claim_pressed(mission_id: String, btn: Button) -> void:
	if _claim_in_flight != "":
		return  # un claim est déjà en vol : on ignore (anti double-dépense côté UI).
	_claim_in_flight = mission_id
	btn.disabled = true
	NetworkManager.claim_mission(mission_id)


func _on_mission_claimed(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	AudioManager.play_sfx("confirm")
	var paid := int(data.get("reward_paid", 0))
	var msg := tr("MISSIONS_STATUS_CLAIMED").format({"n": paid})
	if bool(data.get("pass_bonus_applied", false)):
		msg += "  " + tr("MISSIONS_PASS_BONUS")
	_set_status(msg, GOLD)
	# Source de vérité serveur : on RE-FETCHE la liste (progress/claimed/pastille à jour).
	# NOTE (constat, hors périmètre de ce chantier) : la jauge de Coins de la nav n'est PAS
	# rafraîchie après un claim — elle ne bouge qu'au prochain `/auth/me`. Comportement HÉRITÉ de
	# l'écran d'origine, reconduit tel quel : ce lot est un déménagement, pas une correction.
	NetworkManager.fetch_missions()


func _on_claim_failed(message: String) -> void:
	if not is_inside_tree():
		return
	_claim_in_flight = ""
	_set_status(message, DANGER)
	NetworkManager.fetch_missions()


# =========================================================
# Comptes à rebours de reset (04:00 UTC / lundi 04:00 UTC)
# =========================================================
func _process(_delta: float) -> void:
	var now := int(Time.get_unix_time_from_system())
	if _daily_countdown != null and _daily_reset_epoch > 0:
		_daily_countdown.text = tr("MISSIONS_RESET_IN") + " " + _fmt_delta(_daily_reset_epoch - now)
	if _weekly_countdown != null and _weekly_reset_epoch > 0:
		_weekly_countdown.text = tr("MISSIONS_RESET_IN") + " " + _fmt_delta(_weekly_reset_epoch - now)


func _fmt_delta(seconds: int) -> String:
	if seconds <= 0:
		return "00:00:00"
	@warning_ignore("integer_division")
	var d := seconds / 86400
	@warning_ignore("integer_division")
	var h := (seconds % 86400) / 3600
	@warning_ignore("integer_division")
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	if d > 0:
		# §8.118 : le suffixe de jours était en dur en FRANÇAIS — seule chaîne visible de l'écran à
		# échapper à l'i18n. Le format reste composé ICI (et non porté par une clé « %dj %02d… ») :
		# une clé à 4 substitutions ordonnées est un piège à traduction.
		return "%d%s %02d:%02d:%02d" % [d, tr("TIME_DAYS_SHORT"), h, m, s]
	return "%02d:%02d:%02d" % [h, m, s]


# ISO "2026-07-15T04:00:00Z" (UTC) → epoch. Godot ne gère pas le suffixe Z → retiré avant parse.
func _epoch_from_iso(iso: String) -> int:
	if iso == "":
		return 0
	return int(Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z")))


# =========================================================
# Divers
# =========================================================
func _set_status(text: String, color: Color) -> void:
	if _status != null:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func _label(text: String, size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l
