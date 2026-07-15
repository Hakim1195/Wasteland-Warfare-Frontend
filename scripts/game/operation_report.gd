extends Control

# RAPPORT POST-OPÉRATION (§4 Warzone Command) — débriefing after-action affiché en fin de partie.
# Fond = flou gaussien de l'arène gelée (report_blur.gdshader) + assombrissement gunmetal ; grand
# panneau central angulaire : titre massif, « Rapport d'Attrition » (depuis GameState.statistics,
# résolu par main.gd), et CTA « RETOURNER AU LOBBY ». View PURE (Règle d'Or §6.1) : aucune logique
# de jeu / réseau ici — main.gd pousse les données (populate) et gère la navigation (back_to_lobby).

signal back_to_lobby
# Re-queue en 1 clic (G3 §8.70) : « REJOUER » depuis le débriefing — bénéficie à TOUS les joueurs
# en fin de partie, pas qu'aux éliminés. main.gd relaie vers NetworkManager.requeue().
signal requeue_requested
# Inspection du champ de bataille (E11 §8.83) : masque le rapport ET le flou (le plateau final
# reste dessous) — main.gd libère/reprend la caméra. Zéro réseau : l'état final est déjà local.
signal battlefield_inspect(enabled: bool)

const ACCENT_CYAN := Color("36c5d9")
const ACCENT_GOLD := Color("e0b249")
const TEXT_MUTED := Color("8a97a5")
const DANGER := Color("d6453f")

# Jauge XP + Coins réutilisable (§8.47) — instanciée par code dans le bloc « Récompenses » (animé).
const XpCoinsBarScript = preload("res://scripts/ui/xp_coins_bar.gd")
# Brique identité (E1 §8.73) — podium et titres honorifiques (E11).
const PlayerChipScene := preload("res://scenes/components/player_chip.tscn")

# Garde anti double-construction : les récompenses peuvent arriver via populate(data.rewards) OU,
# en cas de course (game_over reçu APRÈS l'affichage du rapport), via populate_rewards() (main.gd).
var _rewards_built := false

# --- Refonte 2 colonnes (E11 §8.83) : gauche = LA PARTIE (publique), droite = MA PERFORMANCE. ---
var _left_col: VBoxContainer = null
var _my_perf_box: VBoxContainer = null
var _podium_list: VBoxContainer = null
var _timeline_wrap: VBoxContainer = null
var _timeline_chart: TimelineChart = null
var _my_stats_box: VBoxContainer = null
var _missions_lbl: Label = null
var _return_btn: Button = null
# Références DIRECTES aux nœuds du récap de zone migrés en colonne gauche (E11) : le reparentage
# invalide la résolution `%Nom` (unique_name_in_owner) → on garde des poignées explicites.
var _stagnation_ref: Label = null
var _attrition_ref: VBoxContainer = null

# =========================================================
# Timeline de domination (E11) — Control custom `_draw()`
# =========================================================
# Une polyligne par joueur (couleur plateau résolue par main.gd), X = rounds globaux,
# Y = territoires possédés, grille discrète charte.
class TimelineChart extends Control:
	var series: Array = []   # [{ "color": Color, "points": Array[int] }]
	var vmax := 1

	func setup(s: Array) -> void:
		series = s
		vmax = 1
		for entry in s:
			for v in entry.get("points", []):
				vmax = maxi(vmax, int(v))
		queue_redraw()

	func _draw() -> void:
		var r := size
		var grid := Color(0.211765, 0.772549, 0.85098, 0.12)
		for i in range(5):
			var y := r.y * float(i) / 4.0
			draw_line(Vector2(0, y), Vector2(r.x, y), grid, 1.0)
		var n := 0
		for entry in series:
			var pts_a: Array = entry.get("points", [])
			n = maxi(n, pts_a.size())
		if n < 2:
			return
		for entry in series:
			var pts_in: Array = entry.get("points", [])
			var poly := PackedVector2Array()
			for i in range(pts_in.size()):
				poly.append(Vector2(
					r.x * float(i) / float(n - 1),
					r.y * (1.0 - float(int(pts_in[i])) / float(vmax))))
			if poly.size() >= 2:
				draw_polyline(poly, entry.get("color", Color.WHITE), 2.0, true)

# =========================================================
# Helpers PURS (statiques, testés — pattern G4)
# =========================================================

static func _stat(statistics: Dictionary, key: String, pid: int) -> int:
	var d = statistics.get(key, {})
	if typeof(d) != TYPE_DICTIONARY:
		return 0
	return int(d.get(str(int(pid)), 0))

# Détenteur d'un titre : max (ou min) du compteur, DÉPARTAGE = pid croissant (itération triée →
# le premier à égalité gagne). -9999 si personne (need_positive et meilleur score ≤ 0).
static func _title_holder(statistics: Dictionary, key: String, pids: Array,
		need_positive: bool, take_min: bool) -> int:
	var sorted_pids: Array = []
	for p in pids:
		sorted_pids.append(int(p))
	sorted_pids.sort()
	var holder := -9999
	var best := 0
	for pid in sorted_pids:
		var v := _stat(statistics, key, pid)
		if holder == -9999 or (take_min and v < best) or (not take_min and v > best):
			holder = pid
			best = v
	if need_positive and best <= 0:
		return -9999
	return holder

# Titres honorifiques (E11 — formules EXACTES du plan, calcul CLIENT, cumul possible) :
#   💀 BOUCHER max kills · ⚔ CONQUÉRANT max conquêtes · 🎯 FOSSOYEUR max héros abattus (si > 0)
#   🛡 INDESTRUCTIBLE min pertes · ☢ IRRADIÉ max morts à la zone (si > 0).
# Retour : { pid: Array[clé i18n TITLE_*] }.
static func honor_titles(statistics: Dictionary, pids: Array) -> Dictionary:
	var out := {}
	for p in pids:
		out[int(p)] = []
	var defs := [
		["TITLE_BUTCHER", "combat_kills_by_player", false, false],
		["TITLE_CONQUEROR", "conquests_by_player", false, false],
		["TITLE_GRAVEDIGGER", "hero_kills_by_player", true, false],
		["TITLE_UNBREAKABLE", "losses_by_player", false, true],
		["TITLE_IRRADIATED", "zone_kills_by_player", true, false],
	]
	for d in defs:
		var holder := _title_holder(statistics, str(d[1]), pids, bool(d[2]), bool(d[3]))
		if holder != -9999 and out.has(holder):
			out[holder].append(str(d[0]))
	return out

# Médaille du podium : 🥇🥈🥉 puis « 4. », « 5. »…
static func medal_for(rank_index: int) -> String:
	match rank_index:
		0: return "🥇"
		1: return "🥈"
		2: return "🥉"
		_: return "%d." % (rank_index + 1)

func _ready() -> void:
	%BackToLobbyButton.pressed.connect(func(): back_to_lobby.emit())
	# SFX d'interface (survol/retour — R6).
	%BackToLobbyButton.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	%BackToLobbyButton.pressed.connect(func() -> void: AudioManager.play_sfx("back"))
	_build_requeue_button()
	_build_columns()
	_build_inspect_buttons()

# Bouton « ⟳ REJOUER » (G3 §8.70), construit par code À CÔTÉ du retour lobby (aucune retouche
# .tscn) : or (CTA de relance), anti double-clic, émet requeue_requested (main.gd décide).
func _build_requeue_button() -> void:
	var anchor: Button = %BackToLobbyButton
	var parent := anchor.get_parent()
	var btn := Button.new()
	btn.name = "RequeueButton"
	btn.text = tr("REPORT_REQUEUE")
	btn.custom_minimum_size = anchor.custom_minimum_size
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT_GOLD, 0.14)
	sb.set_border_width_all(2)
	sb.border_color = ACCENT_GOLD
	sb.set_content_margin_all(10)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT_GOLD, 0.30)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", ACCENT_GOLD)
	btn.add_theme_color_override("font_hover_color", Color("eef3f7"))
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	btn.pressed.connect(func() -> void:
		AudioManager.play_sfx("confirm")
		btn.disabled = true
		requeue_requested.emit())
	parent.add_child(btn)
	parent.move_child(btn, anchor.get_index())

# Refonte 2 COLONNES (E11 §8.83) PAR CODE : une rangée de colonnes s'insère dans ReportVBox et
# les blocs EXISTANTS du récap de zone (eyebrow + stagnation + attrition) MIGRENT dans la colonne
# gauche — aucune retouche .tscn (piège n° 6). Gauche = LA PARTIE (podium + objectifs révélés +
# timeline + zone) ; droite = MA PERFORMANCE (récompenses animées + stats personnelles + missions).
func _build_columns() -> void:
	# Poignées directes AVANT tout reparentage (le déplacement casse la résolution `%Nom`).
	_stagnation_ref = %StagnationReport
	_attrition_ref = %AttritionList
	var vbox: VBoxContainer = _attrition_ref.get_parent()
	vbox.custom_minimum_size = Vector2(1040, 0)
	var eyebrow := vbox.get_node("AttritionEyebrow")
	var insert_at := eyebrow.get_index()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 28)
	vbox.add_child(columns)
	vbox.move_child(columns, insert_at)

	_left_col = VBoxContainer.new()
	_left_col.add_theme_constant_override("separation", 8)
	_left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_col.custom_minimum_size = Vector2(560, 0)
	columns.add_child(_left_col)
	_my_perf_box = VBoxContainer.new()
	_my_perf_box.add_theme_constant_override("separation", 8)
	_my_perf_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_my_perf_box.custom_minimum_size = Vector2(400, 0)
	columns.add_child(_my_perf_box)

	# Colonne GAUCHE — podium & objectifs révélés (peuplés par populate_podium).
	var pod_eyebrow := Label.new()
	pod_eyebrow.text = tr("REPORT_PODIUM_EYEBROW")
	pod_eyebrow.add_theme_color_override("font_color", ACCENT_CYAN)
	pod_eyebrow.add_theme_font_size_override("font_size", 14)
	_left_col.add_child(pod_eyebrow)
	_podium_list = VBoxContainer.new()
	_podium_list.add_theme_constant_override("separation", 6)
	_left_col.add_child(_podium_list)
	var waiting := Label.new()
	waiting.name = "PodiumWaiting"
	waiting.text = tr("REPORT_PODIUM_WAITING")
	waiting.add_theme_color_override("font_color", TEXT_MUTED)
	waiting.add_theme_font_size_override("font_size", 14)
	_podium_list.add_child(waiting)

	# Timeline de domination — MASQUÉE par défaut (serveur antérieur / historique vide, §9.2).
	_timeline_wrap = VBoxContainer.new()
	_timeline_wrap.visible = false
	_timeline_wrap.add_theme_constant_override("separation", 4)
	var tl_eyebrow := Label.new()
	tl_eyebrow.text = tr("REPORT_TIMELINE_EYEBROW")
	tl_eyebrow.add_theme_color_override("font_color", ACCENT_CYAN)
	tl_eyebrow.add_theme_font_size_override("font_size", 14)
	_timeline_wrap.add_child(tl_eyebrow)
	_timeline_chart = TimelineChart.new()
	_timeline_chart.custom_minimum_size = Vector2(0, 110)
	_timeline_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_wrap.add_child(_timeline_chart)
	_left_col.add_child(_timeline_wrap)

	# Migration du récap de zone EXISTANT (plan E11 : ces lignes vivent en colonne gauche).
	# reparent() préserve l'owner (contrairement à remove/add) → pas d'invalidation de `%`, mais
	# on utilise de toute façon les poignées directes _stagnation_ref/_attrition_ref ensuite.
	for node in [eyebrow, _stagnation_ref, _attrition_ref]:
		node.reparent(_left_col)

	# Colonne DROITE — en-tête « MA PERFORMANCE » ; les récompenses animées (populate_rewards)
	# et les stats personnelles s'y insèrent.
	var my_eyebrow := Label.new()
	my_eyebrow.text = tr("REPORT_MYPERF_EYEBROW")
	my_eyebrow.add_theme_color_override("font_color", ACCENT_CYAN)
	my_eyebrow.add_theme_font_size_override("font_size", 14)
	_my_perf_box.add_child(my_eyebrow)
	_my_stats_box = VBoxContainer.new()
	_my_stats_box.add_theme_constant_override("separation", 3)
	_my_perf_box.add_child(_my_stats_box)

# Boutons d'inspection (E11) : « 🔍 INSPECTER LE CHAMP DE BATAILLE » dans la rangée de CTA +
# bouton flottant « ◀ RAPPORT » pour revenir. Masque le rapport ET le flou — le plateau final
# reste dessous, main.gd libère la caméra (signal battlefield_inspect).
func _build_inspect_buttons() -> void:
	var anchor: Button = %BackToLobbyButton
	var parent := anchor.get_parent()
	var btn := Button.new()
	btn.name = "InspectButton"
	btn.text = tr("REPORT_INSPECT")
	btn.custom_minimum_size = anchor.custom_minimum_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT_CYAN, 0.10)
	sb.set_border_width_all(1)
	sb.border_color = Color(ACCENT_CYAN, 0.55)
	sb.set_content_margin_all(10)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT_CYAN, 0.25)
	hover.border_color = ACCENT_CYAN
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color("eef3f7"))
	btn.add_theme_color_override("font_hover_color", ACCENT_CYAN)
	btn.mouse_entered.connect(func() -> void: AudioManager.play_sfx("hover"))
	btn.pressed.connect(_set_inspecting.bind(true))
	parent.add_child(btn)
	parent.move_child(btn, anchor.get_index())

	_return_btn = Button.new()
	_return_btn.text = tr("REPORT_BACK_TO_REPORT")
	_return_btn.visible = false
	_return_btn.position = Vector2(18, 18)
	_return_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_return_btn.add_theme_stylebox_override("normal", sb)
	_return_btn.add_theme_stylebox_override("hover", hover)
	_return_btn.add_theme_stylebox_override("pressed", hover)
	_return_btn.add_theme_color_override("font_color", Color("eef3f7"))
	_return_btn.add_theme_color_override("font_hover_color", ACCENT_CYAN)
	_return_btn.pressed.connect(_set_inspecting.bind(false))
	add_child(_return_btn)

func _set_inspecting(on: bool) -> void:
	AudioManager.play_sfx("click")
	$Center.visible = not on
	$BlurRect.visible = not on
	_return_btn.visible = on
	battlefield_inspect.emit(on)

# Podium & classement (E11) : consomme ENFIN `rankings`. rows résolues par main.gd :
# { pid, medal, titles: Array[clé TITLE_*], objective, completed, has_reveal, kills, conquests,
#   eliminations, points (−1 = masqué — seuls MES points sont connus, redaction serveur) }.
func populate_podium(rows: Array) -> void:
	if _podium_list == null:
		return
	# Retrait IMMÉDIAT (remove_child avant queue_free) : le placeholder « en attente » et un
	# éventuel podium précédent (populate au victory PUIS re-push au game_over) disparaissent
	# tout de suite — pas de double-rendu transitoire ni de comptage faussé.
	for c in _podium_list.get_children():
		_podium_list.remove_child(c)
		c.queue_free()
	for i in range(rows.size()):
		_podium_list.add_child(_make_podium_row(rows[i]))

func _make_podium_row(r: Dictionary) -> Control:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 1)
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 6)
	var medal := Label.new()
	medal.text = str(r.get("medal", "—"))
	medal.custom_minimum_size = Vector2(30, 0)
	medal.add_theme_font_size_override("font_size", 18)
	line1.add_child(medal)
	var chip := PlayerChipScene.instantiate()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line1.add_child(chip)
	chip.setup(int(r.get("pid", 0)), false)
	for t in r.get("titles", []):
		var badge := Label.new()
		badge.text = tr(str(t))
		badge.add_theme_font_size_override("font_size", 11)
		badge.add_theme_color_override("font_color", ACCENT_GOLD)
		badge.tooltip_text = tr("REPORT_TITLE_TOOLTIP")
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		line1.add_child(badge)
	var pts := int(r.get("points", -1))
	if pts >= 0:
		var pts_lbl := Label.new()
		pts_lbl.text = "+%d PTS" % pts
		pts_lbl.add_theme_font_size_override("font_size", 15)
		pts_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
		line1.add_child(pts_lbl)
	card.add_child(line1)

	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 8)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(30, 0)
	line2.add_child(indent)
	# Objectif révélé (bloc PUBLIC objectives_reveal) — ✔ vert / ✘ gris ; masqué si serveur
	# antérieur (has_reveal false → mention neutre).
	var obj := Label.new()
	if bool(r.get("has_reveal", false)):
		var done := bool(r.get("completed", false))
		obj.text = ("✔ " if done else "✘ ") + str(r.get("objective", ""))
		obj.add_theme_color_override("font_color", Color("46b58a") if done else TEXT_MUTED)
	else:
		obj.text = tr("REPORT_OBJ_UNKNOWN")
		obj.add_theme_color_override("font_color", TEXT_MUTED)
	obj.add_theme_font_size_override("font_size", 13)
	obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obj.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	obj.tooltip_text = str(r.get("objective", ""))
	obj.mouse_filter = Control.MOUSE_FILTER_PASS
	line2.add_child(obj)
	var stats := Label.new()
	stats.text = "⚔%d 🚩%d 🎯%d" % [int(r.get("kills", 0)), int(r.get("conquests", 0)),
		int(r.get("eliminations", 0))]
	stats.add_theme_font_size_override("font_size", 12)
	stats.add_theme_color_override("font_color", Color("c8cdd6"))
	stats.tooltip_text = tr("REPORT_STATS_LEGEND")
	stats.mouse_filter = Control.MOUSE_FILTER_PASS
	line2.add_child(stats)
	card.add_child(line2)
	return card

# Timeline de domination (E11) : series résolues par main.gd (couleur plateau + points par round).
# Vide / absente (serveur antérieur) → section MASQUÉE, aucune erreur (§9.2).
func set_timeline(series: Array) -> void:
	if _timeline_wrap == null:
		return
	if series.is_empty():
		_timeline_wrap.visible = false
		return
	_timeline_wrap.visible = true
	_timeline_chart.setup(series)

# Stats personnelles de la partie (E11, colonne droite) : dict résolu par main.gd.
func set_my_stats(ms: Dictionary) -> void:
	if _my_stats_box == null:
		return
	for c in _my_stats_box.get_children():
		c.queue_free()
	if ms.is_empty():
		return
	var lines := [
		tr("REPORT_MS_COMBAT") % [int(ms.get("kills", 0)), int(ms.get("losses", 0))],
		tr("REPORT_MS_CONQ") % [int(ms.get("conquests", 0)), int(ms.get("eliminations", 0))],
		tr("REPORT_MS_CARDS") % int(ms.get("cards_played", 0)),
		tr("REPORT_MS_HERO") % [int(ms.get("hero_damage", 0)), int(ms.get("hero_kills", 0))],
		tr("REPORT_MS_ZONE") % int(ms.get("zone_deaths", 0)),
	]
	for l in lines:
		var lbl := Label.new()
		lbl.text = str(l)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color("c8cdd6"))
		_my_stats_box.add_child(lbl)
	var hero_line := str(ms.get("hero_line", ""))
	if hero_line != "":
		var hero_lbl := Label.new()
		hero_lbl.text = tr("REPORT_MY_HERO") + "  " + hero_line
		hero_lbl.add_theme_font_size_override("font_size", 14)
		hero_lbl.add_theme_color_override("font_color",
			DANGER if hero_line.begins_with("💀") else ACCENT_CYAN)
		_my_stats_box.add_child(hero_lbl)

# Pont missions (M2 §8.65 — E11) : rappel de la boucle de rétention au pied de MA colonne.
func set_missions_summary(progressed: int, claimable: int) -> void:
	if _my_perf_box == null:
		return
	if _missions_lbl == null or not is_instance_valid(_missions_lbl):
		_missions_lbl = Label.new()
		_missions_lbl.add_theme_font_size_override("font_size", 14)
		_my_perf_box.add_child(_missions_lbl)
	_missions_lbl.text = tr("REPORT_MISSIONS") % [progressed, claimable] \
		+ (" ✦" if claimable > 0 else "")
	_missions_lbl.add_theme_color_override("font_color",
		ACCENT_GOLD if claimable > 0 else TEXT_MUTED)

# Remplit le rapport. data = {
#   title: String, title_color: Color, stagnation: int,
#   attrition: Array[{ pseudo: String, color: Color, losses: int }] (triée desc.),
#   worst_pseudo: String,
#   rewards: Dictionary (FACULTATIF) — gains du joueur local (game_over.match_rewards[my_id], §8.47),
#   podium: Array (FACULTATIF, E11) — lignes résolues (populate_podium),
#   timeline: Array (FACULTATIF, E11) — séries de domination (set_timeline),
#   my_stats: Dictionary (FACULTATIF, E11) — stats personnelles (set_my_stats) }
func populate(data: Dictionary) -> void:
	%ReportTitle.text = str(data.get("title", "OPÉRATION TERMINÉE")).to_upper()
	%ReportTitle.add_theme_color_override("font_color", data.get("title_color", ACCENT_GOLD))

	var stag := int(data.get("stagnation", 0))
	if stag > 0:
		_stagnation_ref.text = "☢ La zone radioactive a stagné %d round(s) sans se déplacer." % stag
	else:
		_stagnation_ref.text = "☢ Zone radioactive instable jusqu'au bout (déplacements fréquents)."

	var list: VBoxContainer = _attrition_ref
	for child in list.get_children():
		child.queue_free()
	var attrition: Array = data.get("attrition", [])
	var worst := str(data.get("worst_pseudo", ""))
	if attrition.is_empty():
		var none := Label.new()
		none.text = "— Aucune perte enregistrée dans la zone —"
		none.add_theme_color_override("font_color", TEXT_MUTED)
		none.add_theme_font_size_override("font_size", 15)
		list.add_child(none)
	else:
		for e in attrition:
			var pseudo := str(e.get("pseudo", "?"))
			var is_worst: bool = pseudo == worst
			var row := Label.new()
			var prefix := "🥇 PLUS LOURD TRIBUT : " if is_worst else "❯ "
			row.text = "%s%s — %d unité(s) perdues dans la zone" % [prefix, pseudo, int(e.get("losses", 0))]
			row.add_theme_color_override("font_color", ACCENT_GOLD if is_worst else e.get("color", Color.WHITE))
			row.add_theme_font_size_override("font_size", 17 if is_worst else 15)
			list.add_child(row)

	# Blocs E11 (clés FACULTATIVES — payload legacy → sections masquées, aucune erreur §9.2).
	if data.has("podium"):
		populate_podium(data.get("podium", []))
	set_timeline(data.get("timeline", []))
	set_my_stats(data.get("my_stats", {}))

	# Bloc « Récompenses » animé (si les gains du joueur local sont déjà connus à l'affichage).
	var rewards: Dictionary = data.get("rewards", {})
	if not rewards.is_empty():
		populate_rewards(rewards)

# =========================================================
# Bloc « Récompenses » (§8.47) — décompte des points + barre d'XP qui se remplit + lueur Coins
# =========================================================
# Appelable séparément par main.gd quand le message game_over (porteur de match_rewards) arrive APRÈS
# la construction du rapport (course réseau : l'état winner_id et le game_over sont 2 messages). La
# garde _rewards_built évite tout doublon. `rewards` = match_rewards[player_id_local].
func populate_rewards(rewards: Dictionary) -> void:
	if _rewards_built or rewards.is_empty():
		return
	_rewards_built = true
	_build_and_animate_rewards(rewards)

func _build_and_animate_rewards(rewards: Dictionary) -> void:
	# E11 : le bloc Récompenses vit désormais dans MA colonne (droite), plus dans l'attrition.
	var list: VBoxContainer = _my_perf_box if _my_perf_box != null else _attrition_ref

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "▌ RÉCOMPENSES DE FIN D'OPÉRATION"
	header.add_theme_color_override("font_color", ACCENT_CYAN)
	header.add_theme_font_size_override("font_size", 18)
	block.add_child(header)

	# Ligne « Points de Match » (décompte animé depuis 0).
	var points_lbl := Label.new()
	points_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	points_lbl.add_theme_font_size_override("font_size", 22)
	points_lbl.text = "POINTS DE MATCH : +0"
	block.add_child(points_lbl)

	# Pass Spécial (M4 §8.67) : le serveur a appliqué +25 % d'XP (et coins héros ×4) — simple
	# RELAIS du flag, suffixe discret or sur la ligne d'XP (aucun calcul client).
	if bool(rewards.get("pass_bonus_applied", false)):
		var pass_lbl := Label.new()
		pass_lbl.text = "★ +25 % XP — PASS SPÉCIAL ACTIF"
		pass_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
		pass_lbl.add_theme_font_size_override("font_size", 13)
		block.add_child(pass_lbl)

	# Jauge XP + Coins réutilisable (remplissage cyan + lueur dorée aux paliers de 10 niveaux).
	var bar = XpCoinsBarScript.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(bar)

	if rewards.get("level_up_triggered", false):
		var lvl_lbl := Label.new()
		var gained := int(rewards.get("levels_gained", 0))
		lvl_lbl.text = "⬆ %d NIVEAU(X) GAGNÉ(S) — NIVEAU %d" % [gained, int(rewards.get("new_level", 1))]
		lvl_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
		lvl_lbl.add_theme_font_size_override("font_size", 14)
		block.add_child(lvl_lbl)

	# --- PROGRESSION DU HÉROS (sprint RPG, Objectif 5c) : XP héros distincte du profil, barre
	#     logarithmique (fraction dans le niveau fournie par le serveur), pop-up de paliers franchis. ---
	block.add_child(HSeparator.new())
	var hero_header := Label.new()
	hero_header.text = "▌ PROGRESSION DU HÉROS"
	hero_header.add_theme_color_override("font_color", ACCENT_CYAN)
	hero_header.add_theme_font_size_override("font_size", 18)
	block.add_child(hero_header)

	var hero_xp_lbl := Label.new()
	hero_xp_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	hero_xp_lbl.add_theme_font_size_override("font_size", 20)
	hero_xp_lbl.text = "XP HÉROS : +0"
	block.add_child(hero_xp_lbl)

	var hero_level_lbl := Label.new()
	var h_old := int(rewards.get("hero_level", 1))
	var h_new := int(rewards.get("hero_new_level", h_old))
	hero_level_lbl.text = ("NIVEAU HÉROS %d ❯ %d" % [h_old, h_new]) if h_new > h_old else ("NIVEAU HÉROS %d" % h_new)
	hero_level_lbl.add_theme_color_override("font_color", ACCENT_CYAN if h_new > h_old else TEXT_MUTED)
	hero_level_lbl.add_theme_font_size_override("font_size", 14)
	block.add_child(hero_level_lbl)

	# Barre log : remplie à la fraction xp_in_level / xp_for_level (0..1) calculée serveur-side.
	var hero_bar := ProgressBar.new()
	hero_bar.min_value = 0.0
	hero_bar.max_value = 1.0
	hero_bar.value = 0.0
	hero_bar.show_percentage = false
	hero_bar.custom_minimum_size = Vector2(0, 14)
	hero_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(hero_bar)

	# Pop-up « Statistiques Améliorées » : un palier franchi → bonus de stats (ex. +50 PV, +1 PA).
	for ms in rewards.get("hero_milestones", []):
		var ms_lbl := Label.new()
		ms_lbl.text = "⬆ STATISTIQUES AMÉLIORÉES (Niv %d) : %s" % [
			int(ms.get("level", 0)), _format_milestone_bonus(ms.get("bonus", {}))]
		ms_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
		ms_lbl.add_theme_font_size_override("font_size", 14)
		block.add_child(ms_lbl)

	block.add_child(HSeparator.new())

	# E11 : le bloc s'insère juste SOUS l'en-tête « MA PERFORMANCE » (index 1) — repli legacy :
	# tête de liste (comportement historique).
	list.add_child(block)
	list.move_child(block, 1 if list == _my_perf_box else 0)

	await _run_reward_animation(points_lbl, bar, rewards)
	await _animate_hero(hero_xp_lbl, hero_bar, rewards)


# Formate un bonus de palier ({pv_max:50, pa:1, pb:0.01}) en libellé lisible (« +50 PV, +1 PA »).
func _format_milestone_bonus(bonus: Dictionary) -> String:
	var parts: Array[String] = []
	if int(bonus.get("pv_max", 0)) != 0:
		parts.append("+%d PV" % int(bonus.get("pv_max", 0)))
	if int(bonus.get("pa", 0)) != 0:
		parts.append("+%d PA" % int(bonus.get("pa", 0)))
	if float(bonus.get("pb", 0.0)) != 0.0:
		parts.append("+%d%% PB" % int(round(float(bonus.get("pb", 0.0)) * 100.0)))
	return ", ".join(parts) if not parts.is_empty() else "amélioration"


# Animation du bloc héros : décompte de l'XP gagnée puis remplissage de la barre log.
func _animate_hero(hero_xp_lbl: Label, hero_bar: ProgressBar, rewards: Dictionary) -> void:
	var earned := int(rewards.get("hero_xp_earned", 0))
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(
		func(v: float): hero_xp_lbl.text = "XP HÉROS : +%d" % int(round(v)),
		0.0, float(earned), 0.8)
	await t.finished

	var span := int(rewards.get("hero_xp_for_level", 0))
	var frac := 0.0 if span <= 0 else clampf(float(rewards.get("hero_xp_in_level", 0)) / float(span), 0.0, 1.0)
	var tb := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tb.tween_property(hero_bar, "value", frac, 0.7)
	await tb.finished

func _run_reward_animation(points_lbl: Label, bar, rewards: Dictionary) -> void:
	# Laisse le layout se résoudre (tailles des nœuds) avant les Tweens d'échelle/pivot.
	await get_tree().process_frame

	# 1) Décompte des Points de Match (0 → match_points).
	var pts := int(rewards.get("match_points", 0))
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_method(
		func(v: float): points_lbl.text = "POINTS DE MATCH : +%d" % int(round(v)),
		0.0, float(pts), 0.9)
	await t.finished

	# 2) La barre d'XP se remplit (avec montées de niveau + lueur Coins aux paliers de 10, §4).
	await bar.play_match_result(rewards)
