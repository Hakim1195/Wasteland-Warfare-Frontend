extends Control

# OVERLAY OBSERVATEUR (lot G3 — §8.70) : bandeau haut « ★ K.I.A. — MODE OBSERVATEUR » affiché au
# joueur ÉLIMINÉ (permadeath héros §8.61). NON bloquant : le plateau reste visible/navigable
# (caméra tactique libre) et le chat reste accessible — l'overlay n'occupe que le bandeau.
# View PURE (Règle d'Or §6.1) : 2 boutons → signaux ; main.gd décide (requeue réseau / sortie).
# Construit par code (charte « Warzone Command » §2 : gunmetal, titre or, boutons angulaires).

signal requeue_pressed
signal quit_pressed
# PARIS D'OBSERVATEUR (chantier « Tension & fin de partie », LOT E/F) : la vue ne connaît NI le
# réseau NI les règles — elle émet le choix, main.gd l'envoie et lui renvoie le verdict serveur
# (Règle d'Or §6.1). `value` = player_id (winner / next_hero_down) ou "objective"|"elimination"|
# "timeout" (end_reason).
signal bet_placed(bet_type: String, value)

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

	# MODE ÉQUIPES (§8.124) : quand mon équipe SE BAT ENCORE, « K.I.A. » ne dit pas la vérité — la
	# partie n'est pas finie POUR MOI, elle continue sans moi. Le bandeau le dit explicitement et
	# nomme le survivant : c'est ce qui transforme une élimination en attente intéressée plutôt
	# qu'en sortie. Absent en FFA, et absent si toute l'équipe est tombée (là, K.I.A. est exact).
	var alive_mate := _first_alive_teammate()
	if alive_mate != "":
		var team_line := Label.new()
		team_line.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		team_line.text = tr("TEAM_ALIVE_SPECTATOR") % alive_mate
		team_line.add_theme_font_override("font", _font)
		team_line.add_theme_font_size_override("font_size", 13)
		team_line.add_theme_color_override("font_color", ACCENT)
		title_box.add_child(team_line)

	# §8.116 : après une partie PRIVÉE, pas de re-file (salons éphémères) → le bouton devient un
	# retour au QG (émet quit_pressed, que main.gd route vers le QG). Sinon, re-file publique.
	var _is_private := bool(GameState.is_private)
	var requeue := _make_button(tr("MM_BACK_TO_HQ") if _is_private else tr("SPECT_REQUEUE"), GOLD)
	requeue.pressed.connect(func():
		requeue.disabled = true  # anti double-clic pendant la re-queue réseau.
		if _is_private:
			quit_pressed.emit()
		else:
			requeue_pressed.emit())
	h.add_child(requeue)

	var quit := _make_button(tr("SPECT_QUIT"), DANGER)
	quit.pressed.connect(func(): quit_pressed.emit())
	h.add_child(quit)

	_build_bets_panel()


# =========================================================
# PANNEAU « PARIS » (chantier « Tension & fin de partie », LOT E/F)
# =========================================================
# SEUL ajout à cet overlay : un panneau COMPACT sous le bandeau, 3 lignes (une par type de pari).
# Il reste NON BLOQUANT (le plateau demeure navigable) et n'occupe qu'un coin.
# POURQUOI ce panneau existe : un joueur éliminé n'avait plus rien à faire et quittait ; les primes
# sont dérisoires à dessein (35 XP / 20 ¢ au mieux), c'est l'ATTENTION qui est le gain.

var _bets_panel: PanelContainer = null
var _bet_rows: Dictionary = {}   # bet_type -> { "select": OptionButton, "btn": Button, "state": Label }
var _bets_open := true

# Ordre d'affichage = ordre canonique serveur (observer_bets.BET_TYPES).
const BET_TYPES := ["winner", "next_hero_down", "end_reason"]
const BET_TITLE_KEYS := {
	"winner": "BET_WINNER",
	"next_hero_down": "BET_NEXT_HERO",
	"end_reason": "BET_END_REASON",
}
# Valeurs du pari « mode de fin » : miroir de observer_bets.END_REASONS (« abandon » n'est PAS
# pariable — ce n'est pas une façon de gagner qu'on peut lire sur le plateau).
const END_REASONS := ["objective", "elimination", "timeout"]
const END_REASON_KEYS := {
	"objective": "BET_END_OBJECTIVE",
	"elimination": "BET_END_ELIMINATION",
	"timeout": "BET_END_TIMEOUT",
}


func _build_bets_panel() -> void:
	_bets_panel = PanelContainer.new()
	_bets_panel.name = "BetsPanel"
	_bets_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = GUNMETAL
	st.set_corner_radius_all(0)
	st.set_border_width_all(2)
	st.border_color = ACCENT
	st.set_content_margin_all(12.0)
	_bets_panel.add_theme_stylebox_override("panel", st)
	# HAUT-DROITE, sous le bandeau : la gauche est prise par le mini-classement de départage du HUD
	# pendant le PROTOCOLE FINAL, le centre par le bandeau de tour.
	_bets_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_bets_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bets_panel.offset_right = -16.0
	_bets_panel.offset_top = 96.0
	add_child(_bets_panel)
	WarzoneUI.add_corner_notches(_bets_panel, 14.0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_bets_panel.add_child(box)

	var title := Label.new()
	title.text = tr("BETS_TITLE")
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)

	var hint := Label.new()
	hint.text = tr("BETS_HINT")
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", MUTED)
	box.add_child(hint)

	for bet_type in BET_TYPES:
		box.add_child(_build_bet_row(bet_type))


func _build_bet_row(bet_type: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = tr(BET_TITLE_KEYS.get(bet_type, bet_type))
	label.custom_minimum_size = Vector2(180, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT)
	row.add_child(label)

	var select := OptionButton.new()
	select.custom_minimum_size = Vector2(150, 30)
	select.focus_mode = Control.FOCUS_NONE
	select.add_theme_font_size_override("font_size", 12)
	row.add_child(select)

	var btn := _make_button(tr("BET_PLACE"), ACCENT)
	btn.custom_minimum_size = Vector2(96, 30)
	btn.add_theme_font_size_override("font_size", 12)
	btn.disabled = true   # activé par set_bet_options (rien à parier sans options)
	btn.pressed.connect(func() -> void:
		var idx := select.get_selected_id()
		if idx < 0:
			return
		bet_placed.emit(bet_type, select.get_item_metadata(select.get_selected())))
	row.add_child(btn)

	var state := Label.new()
	state.custom_minimum_size = Vector2(120, 0)
	state.add_theme_font_size_override("font_size", 12)
	state.add_theme_color_override("font_color", MUTED)
	row.add_child(state)

	_bet_rows[bet_type] = {"select": select, "btn": btn, "state": state}
	return row


# Alimente les listes déroulantes. `players` (résolus par main.gd — la vue ne lit pas l'état) :
# liste de { id: int, name: String }. Les valeurs du pari « mode de fin » sont, elles, statiques.
func set_bet_options(players: Array) -> void:
	# MODE ÉQUIPES (§8.124) : MON CAMP est retiré du domaine du pari « vainqueur » — le serveur le
	# refuse (`own_team`), autant ne pas le proposer. Raison : ce pari serait gratuit et
	# systématique (tout mort le poserait sans réfléchir), or l'intérêt du dispositif est de faire
	# LIRE la table. « Prochain héros abattu », lui, garde TOUT le monde : parier sur la chute d'un
	# coéquipier n'a rien d'automatique, c'est même un pari de lecture froide.
	var own_camp := {}
	if GameState.team_mode != "":
		for mate in GameState.teammates_of(AuthManager.user_id):
			own_camp[int(mate)] = true
		own_camp[int(AuthManager.user_id)] = true

	for bet_type in ["winner", "next_hero_down"]:
		var row: Dictionary = _bet_rows.get(bet_type, {})
		if row.is_empty():
			continue
		var select: OptionButton = row["select"]
		select.clear()
		for p in players:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			if bet_type == "winner" and own_camp.has(int(p.get("id", -1))):
				continue
			select.add_item(str(p.get("name", "")))
			select.set_item_metadata(select.item_count - 1, int(p.get("id", -1)))
		row["btn"].disabled = select.item_count == 0 or not _bets_open
	var er: Dictionary = _bet_rows.get("end_reason", {})
	if not er.is_empty():
		var sel: OptionButton = er["select"]
		if sel.item_count == 0:
			for reason in END_REASONS:
				sel.add_item(tr(END_REASON_KEYS.get(reason, reason)))
				sel.set_item_metadata(sel.item_count - 1, reason)
		er["btn"].disabled = not _bets_open


# Guichet ouvert/fermé — MÊME règle que le serveur (`observer_bets.open_for`) : fermé dès le
# PROTOCOLE FINAL, sinon le pari « mode de fin » deviendrait trivial. Un pari DÉJÀ posé garde son
# libellé verrouillé (on ne le réactive jamais).
func set_bets_open(opened: bool) -> void:
	_bets_open = opened
	for bet_type in _bet_rows.keys():
		var row: Dictionary = _bet_rows[bet_type]
		if str(row["state"].text) != "":
			continue   # ligne déjà verrouillée par un pari
		row["btn"].disabled = not opened or (row["select"] as OptionButton).item_count == 0
		if not opened:
			row["state"].text = tr("BET_LOCKED")
			row["state"].add_theme_color_override("font_color", MUTED)


# Pari ACCEPTÉ par le serveur : la ligne se verrouille et affiche la mise + la prime potentielle.
func lock_bet(bet_type: String, value_label: String, reward: Dictionary) -> void:
	var row: Dictionary = _bet_rows.get(bet_type, {})
	if row.is_empty():
		return
	(row["select"] as OptionButton).disabled = true
	(row["btn"] as Button).disabled = true
	row["state"].text = tr("BET_PLACED_FMT") % [value_label,
		int(reward.get("xp", 0)), int(reward.get("coins", 0))]
	row["state"].add_theme_color_override("font_color", GOLD)


# Verdict de fin de partie (bloc PRIVÉ `bet_results`) : chaque ligne pariée passe en GAGNÉ / PERDU.
# L'overlay peut encore être visible sous le Rapport Post-Op — les deux disent la même chose, ce
# qui est voulu : le parieur voit son résultat sans avoir à chercher.
func show_bet_results(results: Array) -> void:
	for r in results:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = _bet_rows.get(str(r.get("bet_type", "")), {})
		if row.is_empty():
			continue
		var won := bool(r.get("won", false))
		row["state"].text = tr("BET_WON") % int(r.get("xp", 0)) if won else tr("BET_LOST")
		row["state"].add_theme_color_override("font_color", GOLD if won else DANGER)
		(row["btn"] as Button).disabled = true
		(row["select"] as OptionButton).disabled = true


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


# Pseudo du PREMIER coéquipier encore en vie, ou "" (MODE ÉQUIPES §8.124).
# "" couvre les trois cas où « K.I.A. » reste le bon mot : partie FFA, joueur sans équipe, ou
# équipe entièrement tombée. Aucun appelant n'a donc de garde à écrire.
func _first_alive_teammate() -> String:
	if GameState.team_mode == "":
		return ""
	for mate in GameState.teammates_of(AuthManager.user_id):
		var p: Dictionary = GameState.players.get(str(int(mate)), {})
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if str(p.get("status", "alive")) == "eliminated" or bool(p.get("is_dead", false)):
			continue
		var who := str(p.get("username", ""))
		# §8.126 — même identité qu'ailleurs : le tag de compagnie accompagne le pseudo.
		return GameState.tagged_name(int(mate), who if who != "" else "#%d" % int(mate))
	return ""
