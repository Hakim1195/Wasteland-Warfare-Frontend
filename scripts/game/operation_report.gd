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
# Texte primaire (blanc froid, charte §2) — jusqu'ici toujours écrit en dur (Color("eef3f7")) dans
# ce fichier ; nommé ICI (§8.99) car le tableau BILAN en a besoin à plusieurs endroits (ligne d'un
# belligérant vivant, non vainqueur, non « moi »).
const TEXT_PRIMARY := Color("eef3f7")

# Jauge XP + Coins réutilisable (§8.47) — instanciée par code dans le bloc « Récompenses » (animé).
const XpCoinsBarScript = preload("res://scripts/ui/xp_coins_bar.gd")
# Brique identité (E1 §8.73) — podium et titres honorifiques (E11).
const PlayerChipScene := preload("res://scenes/components/player_chip.tscn")
# Helpers partagés (police mono du détail chiffré) — war_roster.gd expose ses statiques (§8.73).
const RosterHelpers := preload("res://scripts/ui/war_roster.gd")

# Garde anti double-construction : les récompenses peuvent arriver via populate(data.rewards) OU,
# en cas de course (game_over reçu APRÈS l'affichage du rapport), via populate_rewards() (main.gd).
var _rewards_built := false

# --- Refonte EN ONGLETS (E-visuel) : XP JOUEUR / XP HÉROS / CLASSEMENT. Chaque onglet = un
#     ScrollContainer > VBox (contenu long → défilement, jamais de débordement). Les conteneurs
#     peuplés par populate*/set_* sont RE-CIBLÉS ici — le contrat main.gd reste inchangé. ---
var _tabs: TabContainer = null
var _player_tab: VBoxContainer = null           # onglet 1 : récompenses + détail + stats + missions
var _player_rewards_box: VBoxContainer = null   # bloc récompenses animé + détail des points/XP
var _hero_tab: VBoxContainer = null             # onglet 2 : progression héros + détail
var _hero_progress_box: VBoxContainer = null    # bloc progression héros animé + détail
var _ranking_tab: VBoxContainer = null          # onglet 3 : podium + récap de zone
var _podium_list: VBoxContainer = null
var _timeline_wrap: VBoxContainer = null
var _timeline_chart: TimelineChart = null
var _my_stats_box: VBoxContainer = null
# Onglet 4 : BILAN (§8.99) — tableau comparatif de TOUS les belligérants (gains/pertes/échange)
# + timeline de domination, MIGRÉE ici depuis l'onglet CLASSEMENT (cf. _build_tabs).
# Colonnes : JOUEUR · TERR · CONQ · KILLS · ÉLIM · HÉROS · UNITÉS · ZONE · ÉCHANGE. Écartés à
# dessein (lisibilité à 700 px — chaque colonne de plus dégrade toutes les autres) : cards_played,
# détail des continents. Données disponibles dans les lignes si besoin plus tard.
const DEBRIEF_COLUMNS := 9
var _debrief_tab: VBoxContainer = null
var _debrief_grid: GridContainer = null
var _missions_lbl: Label = null
var _return_btn: Button = null
# Références DIRECTES aux nœuds du récap de zone migrés dans l'onglet CLASSEMENT (E11) : le
# reparentage invalide la résolution `%Nom` (unique_name_in_owner) → on garde des poignées explicites.
var _stagnation_ref: Label = null
var _attrition_ref: VBoxContainer = null
# Entrées BRUTES du détail (xp_detail poussé par main.gd) : rank, territoires/continents en fin,
# conquêtes, kills, éliminations, hero_kills, hero_damage, objectif rempli — pour reconstituer le
# barème localement (réconcilié aux totaux serveur). {} = payload legacy → aucune section détail.
var _detail_inputs: Dictionary = {}

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
	_build_tabs()
	_build_inspect_buttons()
	if OS.is_debug_build() and not _self_checked:
		_self_check()

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

# Refonte EN ONGLETS (E-visuel) PAR CODE : un TabContainer s'insère dans ReportVBox à l'emplacement
# de l'eyebrow d'attrition ; 4 pages (ScrollContainer > VBox) — XP JOUEUR / XP HÉROS / CLASSEMENT /
# BILAN (§8.99, tableau comparatif + timeline). Les blocs EXISTANTS du récap de zone (eyebrow +
# stagnation + attrition) MIGRENT dans l'onglet CLASSEMENT — aucune retouche .tscn (piège n° 6).
# Les conteneurs peuplés par populate*/set_* sont simplement RE-CIBLÉS (contrat main.gd inchangé).
func _build_tabs() -> void:
	# Poignées directes AVANT tout reparentage (le déplacement casse la résolution `%Nom`).
	_stagnation_ref = %StagnationReport
	_attrition_ref = %AttritionList
	var vbox: VBoxContainer = _attrition_ref.get_parent()
	vbox.custom_minimum_size = Vector2(720, 0)
	var eyebrow := vbox.get_node("AttritionEyebrow")
	var insert_at := eyebrow.get_index()

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(700, 452)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tabs(_tabs)
	vbox.add_child(_tabs)
	vbox.move_child(_tabs, insert_at)
	# SFX au changement d'onglet (cohérence avec les autres boutons — R6).
	_tabs.tab_changed.connect(func(_i: int) -> void: AudioManager.play_sfx("click"))

	# --- Onglet 1 : XP JOUEUR (récompenses animées + détail + stats perso + missions) ---
	_player_tab = _add_tab_page("TabPlayer")
	_player_rewards_box = VBoxContainer.new()
	_player_rewards_box.add_theme_constant_override("separation", 6)
	_player_tab.add_child(_player_rewards_box)
	_player_tab.add_child(_eyebrow(tr("REPORT_MYPERF_EYEBROW")))
	_my_stats_box = VBoxContainer.new()
	_my_stats_box.add_theme_constant_override("separation", 3)
	_player_tab.add_child(_my_stats_box)

	# --- Onglet 2 : XP HÉROS (progression animée + détail du barème héros) ---
	_hero_tab = _add_tab_page("TabHero")
	_hero_progress_box = VBoxContainer.new()
	_hero_progress_box.add_theme_constant_override("separation", 6)
	_hero_tab.add_child(_hero_progress_box)

	# --- Onglet 3 : CLASSEMENT (podium + objectifs révélés + récap de zone migré) ---
	_ranking_tab = _add_tab_page("TabRanking")
	_ranking_tab.add_child(_eyebrow(tr("REPORT_PODIUM_EYEBROW")))
	_podium_list = VBoxContainer.new()
	_podium_list.add_theme_constant_override("separation", 6)
	_ranking_tab.add_child(_podium_list)
	var waiting := Label.new()
	waiting.name = "PodiumWaiting"
	waiting.text = tr("REPORT_PODIUM_WAITING")
	waiting.add_theme_color_override("font_color", TEXT_MUTED)
	waiting.add_theme_font_size_override("font_size", 14)
	_podium_list.add_child(waiting)

	# Migration du récap de zone EXISTANT vers l'onglet CLASSEMENT (reparent préserve l'owner ; on
	# garde de toute façon les poignées directes _stagnation_ref/_attrition_ref pour populate()).
	for node in [eyebrow, _stagnation_ref, _attrition_ref]:
		node.reparent(_ranking_tab)

	# --- Onglet 4 : BILAN (§8.99) — tableau comparatif de TOUS les belligérants + timeline ---
	# La timeline de domination MIGRE ici depuis l'onglet CLASSEMENT : c'est une STATISTIQUE
	# (comment chacun a performé), pas un verdict (qui a gagné et pourquoi, laissé à l'onglet 3).
	_debrief_tab = _add_tab_page("TabDebrief")
	_debrief_tab.add_child(_eyebrow(tr("REPORT_DEBRIEF_EYEBROW")))
	_debrief_grid = GridContainer.new()
	_debrief_grid.columns = DEBRIEF_COLUMNS
	_debrief_grid.add_theme_constant_override("h_separation", 8)
	_debrief_grid.add_theme_constant_override("v_separation", 4)
	_debrief_tab.add_child(_debrief_grid)
	var legend := Label.new()
	legend.text = tr("REPORT_DEBRIEF_LEGEND")
	legend.add_theme_color_override("font_color", TEXT_MUTED)
	legend.add_theme_font_size_override("font_size", 10)
	_debrief_tab.add_child(legend)

	# Timeline de domination (DÉPLACÉE depuis l'onglet CLASSEMENT) — MASQUÉE par défaut (serveur
	# antérieur / historique vide, §9.2).
	_timeline_wrap = VBoxContainer.new()
	_timeline_wrap.visible = false
	_timeline_wrap.add_theme_constant_override("separation", 4)
	_timeline_wrap.add_child(_eyebrow(tr("REPORT_TIMELINE_EYEBROW")))
	_timeline_chart = TimelineChart.new()
	_timeline_chart.custom_minimum_size = Vector2(0, 110)
	_timeline_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline_wrap.add_child(_timeline_chart)
	_debrief_tab.add_child(_timeline_wrap)

	# Titres d'onglets (à icônes — charte §2 ; traduits, posés APRÈS l'ajout des pages).
	_tabs.set_tab_title(0, tr("REPORT_TAB_PLAYER"))
	_tabs.set_tab_title(1, tr("REPORT_TAB_HERO"))
	_tabs.set_tab_title(2, tr("REPORT_TAB_RANKING"))
	_tabs.set_tab_title(3, tr("REPORT_TAB_DEBRIEF"))
	_tabs.remove_child(_tabs.get_child(3))  # CONTRE-EPREUVE TEMPORAIRE - A RETIRER

# Une page d'onglet : ScrollContainer (contenu long → défilement vertical, jamais de débordement) >
# VBoxContainer de contenu. `id` = nom ASCII du nœud (le titre visible est posé par set_tab_title).
func _add_tab_page(id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = id
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(scroll)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	return page

# Petit eyebrow de section « ❯/▸ … » (cyan, charte §2) — brique unique des en-têtes de bloc.
func _eyebrow(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT_CYAN)
	l.add_theme_font_size_override("font_size", 14)
	return l

# Thème du TabContainer : angles DROITS, liseré cyan sur l'onglet actif, gunmetal translucide (§2).
func _style_tabs(tc: TabContainer) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.058824, 0.07451, 0.094118, 0.55)
	panel.border_color = Color(ACCENT_CYAN, 0.35)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(0)
	panel.set_content_margin_all(12)
	tc.add_theme_stylebox_override("panel", panel)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(ACCENT_CYAN, 0.16)
	sel.set_corner_radius_all(0)
	sel.border_width_top = 2
	sel.border_color = ACCENT_CYAN
	sel.content_margin_left = 14
	sel.content_margin_right = 14
	sel.content_margin_top = 7
	sel.content_margin_bottom = 7
	var unsel := StyleBoxFlat.new()
	unsel.bg_color = Color(0.101961, 0.12549, 0.156863, 0.5)
	unsel.set_corner_radius_all(0)
	unsel.content_margin_left = 14
	unsel.content_margin_right = 14
	unsel.content_margin_top = 7
	unsel.content_margin_bottom = 7
	var hover := unsel.duplicate() as StyleBoxFlat
	hover.bg_color = Color(ACCENT_CYAN, 0.08)
	tc.add_theme_stylebox_override("tab_selected", sel)
	tc.add_theme_stylebox_override("tab_unselected", unsel)
	tc.add_theme_stylebox_override("tab_hovered", hover)
	tc.add_theme_color_override("font_selected_color", ACCENT_CYAN)
	tc.add_theme_color_override("font_unselected_color", TEXT_MUTED)
	tc.add_theme_color_override("font_hovered_color", Color("eef3f7"))

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
	# Points de match : +N PTS pour MOI (connu) ; « — » (masqué) pour les autres (redaction serveur
	# — seuls MES points sont diffusés). On ne masque plus la colonne : on affiche l'inconnu honnête.
	var pts := int(r.get("points", -1))
	var pts_lbl := Label.new()
	pts_lbl.add_theme_font_size_override("font_size", 15)
	if pts >= 0:
		pts_lbl.text = "+%d PTS" % pts
		pts_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	else:
		pts_lbl.text = tr("REPORT_POINTS_HIDDEN")
		pts_lbl.add_theme_color_override("font_color", TEXT_MUTED)
		pts_lbl.tooltip_text = tr("REPORT_POINTS_HIDDEN_TIP")
		pts_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
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

# Tableau BILAN (§8.99) — `rows` résolues par main.gd via WarRoom.debrief_rows (module PUR) :
# { pid, username, is_bot, is_alive, is_me, is_winner, rank, territories, conquests, kills,
#   eliminations, hero_damage, hero_kills, losses, zone_deaths, ratio, threat }.
# Vue PURE (Règle d'Or §6.1) : aucun calcul ici, uniquement du rendu. Clé `data["debrief"]`
# FACULTATIVE côté populate() (§9.2) : payload legacy → cette fonction n'est jamais appelée, le
# tableau reste vide (juste les en-têtes ne sont pas non plus posés), aucune erreur.
func populate_debrief(rows: Array) -> void:
	if _debrief_grid == null:
		return
	for c in _debrief_grid.get_children():
		_debrief_grid.remove_child(c)
		c.queue_free()
	for h in ["JOUEUR", "TERR", "CONQ", "KILLS", "ÉLIM", "HÉROS", "UNITÉS", "ZONE", "ÉCHANGE"]:
		var lbl := Label.new()
		lbl.text = h
		# Les 2 colonnes de PERTES en rouge : « gains vs pertes » lisible sans légende.
		lbl.add_theme_color_override("font_color",
			DANGER if h in ["UNITÉS", "ZONE"] else TEXT_MUTED)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if h == "JOUEUR" \
			else HORIZONTAL_ALIGNMENT_RIGHT
		_debrief_grid.add_child(lbl)
	for r in rows:
		_add_debrief_row(r)

# Une ligne du tableau BILAN. Vainqueur → or ; moi → cyan ; éliminé → muet + ✖ ; sinon texte
# primaire. Les colonnes UNITÉS/ZONE (pertes) restent en rouge quel que soit le tint de la ligne —
# même logique de lecture que l'en-tête.
func _add_debrief_row(r: Dictionary) -> void:
	var alive := bool(r.get("is_alive", true))
	var tint: Color = ACCENT_GOLD if bool(r.get("is_winner", false)) \
		else (ACCENT_CYAN if bool(r.get("is_me", false)) else (TEXT_PRIMARY if alive else TEXT_MUTED))
	var name_lbl := Label.new()
	var tag := "[IA] " if bool(r.get("is_bot", false)) else ""
	name_lbl.text = "%s%s%s" % [tag, str(r.get("username", "?")), "" if alive else "  ✖"]
	name_lbl.add_theme_color_override("font_color", tint)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_debrief_grid.add_child(name_lbl)
	for key in ["territories", "conquests", "kills", "eliminations", "hero_kills",
			"losses", "zone_deaths"]:
		var v := Label.new()
		v.text = str(int(r.get(key, 0)))
		v.add_theme_color_override("font_color",
			DANGER if key in ["losses", "zone_deaths"] else tint)
		v.add_theme_font_override("font", RosterHelpers._mono_font())
		v.add_theme_font_size_override("font_size", 12)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_debrief_grid.add_child(v)
	# ÉCHANGE : ratio kills/(kills+pertes) — barre CYAN (gains) sur fond ROUGE (pertes) : lecture
	# instantanée, sans avoir à comparer les 2 colonnes chiffrées d'à côté (cf. REPORT_DEBRIEF_LEGEND).
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = float(r.get("ratio", 0.5))
	bar.custom_minimum_size = Vector2(76, 6)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(DANGER, 0.55)
	bar_bg.set_corner_radius_all(0)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT_CYAN
	bar_fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	_debrief_grid.add_child(bar)

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
	if _player_tab == null:
		return
	if _missions_lbl == null or not is_instance_valid(_missions_lbl):
		_missions_lbl = Label.new()
		_missions_lbl.add_theme_font_size_override("font_size", 14)
		_player_tab.add_child(_missions_lbl)
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
#   my_stats: Dictionary (FACULTATIF, E11) — stats personnelles (set_my_stats),
#   debrief: Array (FACULTATIF, §8.99) — tableau BILAN, une ligne/belligérant (populate_debrief) }
func populate(data: Dictionary) -> void:
	%ReportTitle.text = str(data.get("title", "OPÉRATION TERMINÉE")).to_upper()
	%ReportTitle.add_theme_color_override("font_color", data.get("title_color", ACCENT_GOLD))
	# Entrées brutes du détail du barème (FACULTATIF, E-visuel) — stockées AVANT populate_rewards,
	# qui peut arriver plus tard (course réseau) et en aura besoin pour reconstruire les postes.
	_detail_inputs = data.get("xp_detail", {})

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
	# Tableau BILAN (§8.99, FACULTATIF) — même garde que le podium : absente → onglet 4 vide,
	# aucune erreur (§9.2).
	if data.has("debrief"):
		populate_debrief(data.get("debrief", []))

	# Bloc « Récompenses » animé (si les gains du joueur local sont déjà connus à l'affichage).
	# is_ranked (§8.88, FACULTATIF) : défaut `true` = comportement legacy (points affichés).
	# has_played (§8.99, FACULTATIF, défaut false = comportement historique) : discrimine JOUEUR
	# (bloc à 0 + anomalie si `rewards` est vide) de SPECTATEUR (rien affiché) — cf. populate_rewards.
	var rewards: Dictionary = data.get("rewards", {})
	var has_played := bool(data.get("has_played", false))
	if not rewards.is_empty() or has_played:
		populate_rewards(rewards, bool(data.get("is_ranked", true)), has_played)

# =========================================================
# Bloc « Récompenses » (§8.47) — décompte des points + barre d'XP qui se remplit + lueur Coins
# =========================================================
# Appelable séparément par main.gd quand le message game_over (porteur de match_rewards) arrive APRÈS
# la construction du rapport (course réseau : l'état winner_id et le game_over sont 2 messages). La
# garde _rewards_built évite tout doublon. `rewards` = match_rewards[player_id_local].
# `is_ranked` (§8.88) : en partie NON classée, le compteur « POINTS DE MATCH » cède la place à une
# mention « PARTIE NON CLASSÉE » (le serveur renvoie match_points = 0 : afficher « +0 » serait
# trompeur). Défaut `true` = comportement LEGACY — un serveur antérieur ne diffuse pas le champ
# mais crédite encore le ladder sur toutes les parties.
# `has_played` (§8.99, ADDITIF, défaut `false` = comportement historique) distingue les DEUX cas
# qu'un simple `rewards.is_empty()` confondait :
#   - SPECTATEUR (n'a pas joué) → on n'affiche rien : « XP : +0 » pour une partie non disputée
#     serait un contresens. Comportement actuel CONSERVÉ ;
#   - JOUEUR sans récompense reçue → ANOMALIE (0 XP ne devrait jamais arriver) : on affiche le
#     bloc à 0 + une mention explicite. Une anomalie muette est indétectable côté joueur.
# ⚠️ L'appelant (main.gd) est responsable de ne passer `has_played=true` qu'une fois le game_over
# CONFIRMÉ reçu (pas seulement « le joueur est en jeu ») : sinon un simple retard réseau (rewards
# pas encore arrivées) serait pris pour une anomalie, construirait ce bloc à 0, et la garde
# `_rewards_built` ci-dessous bloquerait silencieusement les VRAIES récompenses reçues juste après.
func populate_rewards(rewards: Dictionary, is_ranked: bool = true, has_played: bool = false) -> void:
	if _rewards_built:
		return
	if rewards.is_empty() and not has_played:
		return
	_rewards_built = true
	# Onglet 1 (joueur) et onglet 2 (héros) construits + animés SÉPARÉMENT (coroutines détachées :
	# la partie synchrone — blocs + détail — est posée immédiatement, les animations suivent).
	_build_player_rewards(rewards, is_ranked)
	_build_hero_progress(rewards)

# Bloc LADDER RP (§8.95) : ligne « +25 RP — OR II » (or si positif, rouge danger si négatif), suivie
# d'une bannière PROMOTION / RÉTROGRADATION et d'une mention discrète si le plancher de division a
# amorti la perte. Tout vient des champs PRIVÉS de match_rewards — aucun barème en dur ici.
func _build_rp_block(block: VBoxContainer, rewards: Dictionary) -> void:
	var delta := int(rewards.get("rp_delta", 0))
	var label := str(rewards.get("rp_label", ""))

	var eyebrow := Label.new()
	eyebrow.text = tr("REPORT_RP_EYEBROW")
	eyebrow.add_theme_color_override("font_color", TEXT_MUTED)
	eyebrow.add_theme_font_size_override("font_size", 12)
	block.add_child(eyebrow)

	var rp_lbl := Label.new()
	# Le signe + n'est pas posé par %d sur les positifs → composé à la main.
	var signed := ("+%d" % delta) if delta > 0 else str(delta)
	rp_lbl.text = tr("REPORT_RP_LINE").format({"delta": signed, "label": label})
	rp_lbl.add_theme_color_override("font_color", ACCENT_GOLD if delta >= 0 else Color("d6453f"))
	rp_lbl.add_theme_font_size_override("font_size", 20)
	block.add_child(rp_lbl)

	if bool(rewards.get("rp_promoted", false)):
		var promo := Label.new()
		promo.text = tr("REPORT_PROMOTED").format({"label": label})
		promo.add_theme_color_override("font_color", ACCENT_GOLD)
		promo.add_theme_font_size_override("font_size", 16)
		block.add_child(promo)
	elif bool(rewards.get("rp_demoted", false)):
		var demo := Label.new()
		demo.text = tr("REPORT_DEMOTED").format({"label": label})
		demo.add_theme_color_override("font_color", TEXT_MUTED)
		demo.add_theme_font_size_override("font_size", 14)
		block.add_child(demo)

	# Plancher de division appliqué : mention DISCRÈTE (le joueur a « perdu » moins que le barème).
	if bool(rewards.get("rp_floor_protected", false)):
		var prot := Label.new()
		prot.text = tr("REPORT_RP_PROTECTED")
		prot.add_theme_color_override("font_color", TEXT_MUTED)
		prot.add_theme_font_size_override("font_size", 12)
		block.add_child(prot)

# Onglet 1 — bloc RÉCOMPENSES animé (points de match + jauge XP/Coins + Pass + montées de niveau)
# SUIVI du détail du barème (points & XP réconciliés aux totaux serveur). Coroutine (await l'anim).
func _build_player_rewards(rewards: Dictionary, is_ranked: bool = true) -> void:
	var box: VBoxContainer = _player_rewards_box if _player_rewards_box != null else _attrition_ref
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = "▌ RÉCOMPENSES DE FIN D'OPÉRATION"
	header.add_theme_color_override("font_color", ACCENT_CYAN)
	header.add_theme_font_size_override("font_size", 18)
	block.add_child(header)

	# §8.99 — le serveur n'a envoyé AUCUNE récompense alors que le joueur a bien disputé la partie
	# (populate_rewards ne nous fait atteindre ce point avec `rewards` vide QUE si `has_played`
	# était vrai) : 0 XP ne devrait JAMAIS arriver. On rend l'anomalie VISIBLE plutôt que d'afficher
	# un bloc de zéros silencieux qui passerait pour un résultat normal.
	if rewards.is_empty():
		var anomaly := Label.new()
		anomaly.text = "AUCUNE RÉCOMPENSE REÇUE DU SERVEUR"
		anomaly.add_theme_color_override("font_color", DANGER)
		anomaly.add_theme_font_size_override("font_size", 13)
		block.add_child(anomaly)

	# Ligne « Points de Match » (décompte animé depuis 0) — EN CLASSÉE UNIQUEMENT (§8.88). Hors
	# classée le serveur renvoie match_points = 0 : on affiche une mention muette explicite plutôt
	# qu'un « +0 » qui laisserait croire à une contre-performance. `points_lbl` reste null dans ce
	# cas → _run_reward_animation saute le décompte.
	var points_lbl: Label = null
	if is_ranked:
		points_lbl = Label.new()
		points_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
		points_lbl.add_theme_font_size_override("font_size", 22)
		points_lbl.text = "POINTS DE MATCH : +0"
		block.add_child(points_lbl)
	else:
		var unranked_lbl := Label.new()
		unranked_lbl.text = "PARTIE NON CLASSÉE — AUCUN POINT DE LADDER"
		unranked_lbl.add_theme_color_override("font_color", TEXT_MUTED)
		unranked_lbl.add_theme_font_size_override("font_size", 15)
		block.add_child(unranked_lbl)

	# --- Ladder RP (§8.95) — EN CLASSÉE UNIQUEMENT (en non classée, rien : cohérent §8.88) ---
	# Champs PRIVÉS de match_rewards (redactés par destinataire, E11 §8.83). Lecture DÉFENSIVE : un
	# serveur antérieur au ladder RP n'envoie pas `rp_label` → aucun bloc affiché (pas de « +0 RP »).
	if is_ranked and str(rewards.get("rp_label", "")) != "":
		_build_rp_block(block, rewards)

	# XP JOUEUR gagnée (§8.89) — compteur animé, miroir de « XP HÉROS : +N » de l'onglet héros.
	# L'XP est créditée dans TOUS les modes (seuls les points de ladder sont conditionnels).
	var xp_lbl := Label.new()
	xp_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
	xp_lbl.add_theme_font_size_override("font_size", 20)
	xp_lbl.text = "XP JOUEUR : +0"
	block.add_child(xp_lbl)

	# Pass Spécial (M4 §8.67) : RELAIS du flag serveur (+25 % XP déjà appliqué côté serveur).
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

	# COINS GAGNÉS (§8.89/§8.99) — TOTAL réel = coins de PROFIL (paliers de 10 niveaux) + coins de
	# MONTÉE DE NIVEAU DU HÉROS (même porte-monnaie). §8.99 : TOUJOURS affiché, même à 0 — un
	# compteur masqué à 0 est indiscernable d'un compteur ABSENT (le joueur ne peut pas savoir s'il
	# a gagné 0 ou si l'affichage a échoué).
	var coins_profile := int(rewards.get("coins_earned", 0))
	var coins_hero := int(rewards.get("hero_coins_earned", 0))
	var coins_total := coins_profile + coins_hero
	var coins_lbl := Label.new()
	coins_lbl.text = "◈ COINS GAGNÉS : +%d" % coins_total
	coins_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	coins_lbl.add_theme_font_size_override("font_size", 18)
	block.add_child(coins_lbl)
	# Détail muet : uniquement quand les DEUX sources ont contribué (sinon le total se suffit — ce
	# n'est pas un compteur masqué mais une RÉPARTITION, et la part héros reste lisible onglet 2).
	if coins_profile > 0 and coins_hero > 0:
		var coins_sub := Label.new()
		coins_sub.text = "profil +%d · héros +%d" % [coins_profile, coins_hero]
		coins_sub.add_theme_color_override("font_color", TEXT_MUTED)
		coins_sub.add_theme_font_override("font", RosterHelpers._mono_font())
		coins_sub.add_theme_font_size_override("font_size", 13)
		block.add_child(coins_sub)

	box.add_child(block)
	# NOUVEAU — détail ligne-à-ligne du barème (points de match + XP de profil), réconcilié aux
	# totaux OFFICIELS serveur (match_points / xp_earned) pour ne jamais mentir sur le chiffre.
	# §8.99 — SAUF en cas d'anomalie (`rewards` vide) : le détail se réconcilie aux totaux serveur
	# avec REPLI sur le total reconstruit côté client (cf. _render_detail), il afficherait donc un
	# « TOTAL : +N » non nul JUSTE SOUS la bannière « AUCUNE RÉCOMPENSE REÇUE DU SERVEUR » — un
	# contresens qui saperait le signal d'anomalie lui-même. Soit le serveur a envoyé les chiffres
	# (on détaille), soit il n'a rien envoyé (on ne détaille rien) : pas d'entre-deux inventé.
	if not rewards.is_empty():
		_build_player_detail(box, rewards)

	await _run_reward_animation(points_lbl, xp_lbl, bar, rewards)

# Onglet 2 — bloc PROGRESSION DU HÉROS animé (XP héros + niveau + barre log + paliers de stats)
# SUIVI du détail du barème héros (réconcilié à hero_xp_earned). Coroutine (await l'animation).
func _build_hero_progress(rewards: Dictionary) -> void:
	var box: VBoxContainer = _hero_progress_box if _hero_progress_box != null else _attrition_ref
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

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

	# COINS HÉROS (§8.89/§8.99) : les montées de niveau du héros créditent des coins sur le MÊME
	# porte-monnaie que le profil. §8.99 : TOUJOURS construit, même à 0 → `hero_coins_lbl` n'est
	# plus jamais null, l'animation de queue d'_animate_hero s'exécute donc toujours (cf. plus bas,
	# le test `!= null` y reste une garde défensive inoffensive, pas une condition d'affichage).
	var hero_coins_lbl := Label.new()
	hero_coins_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	hero_coins_lbl.add_theme_font_size_override("font_size", 16)
	hero_coins_lbl.text = "◈ COINS HÉROS : +0"
	block.add_child(hero_coins_lbl)

	var hero_level_lbl := Label.new()
	var h_old := int(rewards.get("hero_level", 1))
	var h_new := int(rewards.get("hero_new_level", h_old))
	hero_level_lbl.text = ("NIVEAU HÉROS %d ❯ %d" % [h_old, h_new]) if h_new > h_old else ("NIVEAU HÉROS %d" % h_new)
	hero_level_lbl.add_theme_color_override("font_color", ACCENT_CYAN if h_new > h_old else TEXT_MUTED)
	hero_level_lbl.add_theme_font_size_override("font_size", 14)
	block.add_child(hero_level_lbl)

	# Niveaux héros gagnés (§8.89) — ligne MIROIR du bloc joueur (« ⬆ N NIVEAU(X) GAGNÉ(S) »),
	# pilotée par le flag SERVEUR hero_level_up plutôt que par la déduction h_new > h_old.
	if bool(rewards.get("hero_level_up", false)):
		var hero_gain_lbl := Label.new()
		hero_gain_lbl.text = "⬆ %d NIVEAU(X) HÉROS GAGNÉ(S)" % int(rewards.get("hero_levels_gained", 0))
		hero_gain_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
		hero_gain_lbl.add_theme_font_size_override("font_size", 14)
		block.add_child(hero_gain_lbl)

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

	box.add_child(block)
	# NOUVEAU — détail du barème héros (réconcilié à hero_xp_earned).
	# §8.99 — même garde que l'onglet 1 : en anomalie (`rewards` vide), le détail retomberait sur le
	# total RECONSTRUIT côté client et contredirait la bannière « aucune récompense reçue ».
	if not rewards.is_empty():
		_build_hero_detail(box, rewards)

	await _animate_hero(hero_xp_lbl, hero_bar, rewards, hero_coins_lbl)

# =========================================================
# DÉTAIL DU BARÈME (E-visuel) — helpers PURS (miroir EXACT de api/game/rewards.py) + rendu.
# Chaque poste = { "key": <clé i18n libellé>, "value": <points/xp entiers> }. Le total affiché est
# TOUJOURS le total OFFICIEL serveur : une ligne « Ajustement serveur » absorbe tout écart de
# reconstruction (continents conquis pendant la partie, unités héros… non tracés côté client), pour
# ne JAMAIS mentir sur le chiffre. Helpers testés par _self_check (pattern G4).
# =========================================================

# Points de classement (rewards.compute_match_points) : rank 0 = 1er, 1 = 2e, 2+ = 3e et suivants.
static func player_points_breakdown(rank: int, territories: int, continents: int,
		eliminations: int, enemy_kills: int) -> Array:
	var items: Array = []
	if rank == 0:
		items.append({"key": "REPORT_PT_WIN_BASE", "value": 20})
		items.append({"key": "REPORT_PT_TERR", "value": territories})
		items.append({"key": "REPORT_PT_CONT", "value": 2 * continents})
		items.append({"key": "REPORT_PT_ELIM", "value": 5 * eliminations})
		items.append({"key": "REPORT_PT_KILLBONUS", "value": 10 * (enemy_kills / 100)})
	elif rank == 1:
		items.append({"key": "REPORT_PT_SECOND_BASE", "value": 10})
		items.append({"key": "REPORT_PT_TERR", "value": territories})
		items.append({"key": "REPORT_PT_CONT", "value": 2 * continents})
		items.append({"key": "REPORT_PT_ELIM", "value": 5 * eliminations})
	else:
		items.append({"key": "REPORT_PT_TERR", "value": territories})
	return _nonzero(items)

# XP de profil (rewards.compute_match_xp) : +5/continent et +100 forfait réservés au haut du tableau ;
# Pass Spécial → ×1.25 (floor) sur le TOTAL, matérialisé par un poste bonus (miroir process_match_results).
static func player_xp_breakdown(rank: int, conquests: int, enemy_kills: int,
		continents_conquered: int, pass_applied: bool) -> Array:
	var items: Array = []
	items.append({"key": "REPORT_XP_CONQ", "value": conquests})
	items.append({"key": "REPORT_XP_KILL", "value": enemy_kills})
	if rank <= 1:
		items.append({"key": "REPORT_XP_CONT", "value": 5 * continents_conquered})
	if rank == 0:
		items.append({"key": "REPORT_XP_WIN", "value": 100})
	items = _nonzero(items)
	if pass_applied:
		var base_total := _breakdown_total(items)
		var boosted := int(floor(1.25 * float(base_total)))
		var bonus := boosted - base_total
		if bonus != 0:
			items.append({"key": "REPORT_XP_PASS", "value": bonus})
	return items

# XP HÉROS (rewards.compute_hero_match_xp) : +1/10 unités tuées (arrondi SUP.), +150 objectif,
# +5/territoire en fin, +100/coup de grâce, +1/10 PV de dégâts héros.
static func hero_xp_breakdown(enemy_units_killed: int, objective_win: bool,
		territories_end: int, hero_kills: int, hero_damage: int) -> Array:
	var items: Array = []
	items.append({"key": "REPORT_HXP_UNITS", "value": int(ceil(float(enemy_units_killed) / 10.0))})
	if objective_win:
		items.append({"key": "REPORT_HXP_OBJ", "value": 150})
	items.append({"key": "REPORT_HXP_TERR", "value": 5 * territories_end})
	items.append({"key": "REPORT_HXP_GRAVE", "value": 100 * hero_kills})
	items.append({"key": "REPORT_HXP_DMG", "value": hero_damage / 10})
	return _nonzero(items)

# Somme des postes d'un breakdown (le « total reconstruit »).
static func _breakdown_total(items: Array) -> int:
	var t := 0
	for it in items:
		t += int(it.get("value", 0))
	return t

# Filtre les postes à valeur nulle (aération : on n'affiche pas de « +0 »).
static func _nonzero(items: Array) -> Array:
	var out: Array = []
	for it in items:
		if int(it.get("value", 0)) != 0:
			out.append(it)
	return out

# Auto-vérification debug (pattern G4) : les breakdowns collent EXACTEMENT au barème rewards.py.
static var _self_checked := false

static func _self_check() -> void:
	_self_checked = true
	# Points de match — miroir de rewards.compute_match_points.
	assert(_breakdown_total(player_points_breakdown(0, 5, 1, 2, 250)) == 57)  # 20+5+2+10+20
	assert(_breakdown_total(player_points_breakdown(1, 3, 0, 1, 40)) == 18)   # 10+3+0+5
	assert(_breakdown_total(player_points_breakdown(2, 4, 1, 3, 500)) == 4)   # 1×4 territoires
	# XP de profil — miroir de rewards.compute_match_xp (+ Pass ×1.25 floor).
	assert(_breakdown_total(player_xp_breakdown(0, 3, 10, 1, false)) == 118)  # 3+10+5+100
	assert(_breakdown_total(player_xp_breakdown(0, 3, 10, 1, true)) == 147)   # floor(1.25×118)
	assert(_breakdown_total(player_xp_breakdown(2, 3, 10, 5, false)) == 13)   # rang 3+ : ni cont ni win
	# XP héros — miroir de rewards.compute_hero_match_xp.
	assert(_breakdown_total(hero_xp_breakdown(25, true, 4, 1, 55)) == 278)    # 3+150+20+100+5
	assert(_breakdown_total(hero_xp_breakdown(9, false, 0, 0, 9)) == 1)       # ceil(0.9)=1 ; reste nul

# Détail des POINTS DE MATCH + XP DE PROFIL (onglet 1) — depuis les entrées brutes _detail_inputs,
# réconcilié aux totaux serveur (rewards.match_points / rewards.xp_earned).
func _build_player_detail(box: VBoxContainer, rewards: Dictionary) -> void:
	if _detail_inputs.is_empty():
		return
	var d := _detail_inputs
	var rank := int(d.get("rank", 0))
	var pts_items := player_points_breakdown(rank, int(d.get("territories_final", 0)),
		int(d.get("continents_final", 0)), int(d.get("eliminations", 0)), int(d.get("kills", 0)))
	_render_detail(box, tr("REPORT_PT_EYEBROW"), pts_items,
		int(rewards.get("match_points", _breakdown_total(pts_items))), "REPORT_UNIT_PTS")
	var xp_items := player_xp_breakdown(rank, int(d.get("conquests", 0)), int(d.get("kills", 0)),
		int(d.get("continents_final", 0)), bool(rewards.get("pass_bonus_applied", false)))
	_render_detail(box, tr("REPORT_XP_EYEBROW"), xp_items,
		int(rewards.get("xp_earned", _breakdown_total(xp_items))), "REPORT_UNIT_XP")

# Détail du barème HÉROS (onglet 2) — réconcilié à rewards.hero_xp_earned.
func _build_hero_detail(box: VBoxContainer, rewards: Dictionary) -> void:
	if _detail_inputs.is_empty():
		return
	var d := _detail_inputs
	var items := hero_xp_breakdown(int(d.get("kills", 0)), bool(d.get("objective_done", false)),
		int(d.get("territories_final", 0)), int(d.get("hero_kills", 0)), int(d.get("hero_damage", 0)))
	_render_detail(box, tr("REPORT_HXP_EYEBROW"), items,
		int(rewards.get("hero_xp_earned", _breakdown_total(items))), "REPORT_UNIT_XP")

# Rend un bloc de détail : eyebrow, un poste par ligne (libellé … +valeur), une ligne d'ajustement
# serveur si l'écart n'est pas nul, puis le TOTAL officiel serveur.
func _render_detail(box: VBoxContainer, eyebrow_text: String, items: Array,
		server_total: int, unit_key: String) -> void:
	box.add_child(HSeparator.new())
	box.add_child(_eyebrow(eyebrow_text))
	for it in items:
		_detail_line(box, tr(str(it.get("key", ""))), int(it.get("value", 0)), unit_key, false)
	var delta := server_total - _breakdown_total(items)
	if delta != 0:
		var adj := Label.new()
		adj.text = tr("REPORT_DETAIL_ADJUST") % delta
		adj.add_theme_color_override("font_color", TEXT_MUTED)
		adj.add_theme_font_size_override("font_size", 12)
		box.add_child(adj)
	_detail_line(box, tr("REPORT_DETAIL_TOTAL"), server_total, unit_key, true)

# Une ligne de détail : libellé (s'étire) à gauche, valeur signée + unité (mono) à droite.
func _detail_line(box: VBoxContainer, label: String, value: int, unit_key: String, is_total: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 15 if is_total else 13)
	l.add_theme_color_override("font_color", ACCENT_GOLD if is_total else Color("c8cdd6"))
	row.add_child(l)
	var v := Label.new()
	v.text = ("%+d" % value) + tr(unit_key)
	v.add_theme_font_override("font", RosterHelpers._mono_font())
	v.add_theme_font_size_override("font_size", 16 if is_total else 13)
	v.add_theme_color_override("font_color", Color("eef3f7") if is_total else ACCENT_GOLD)
	row.add_child(v)
	box.add_child(row)


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


# Animation du bloc héros : décompte de l'XP gagnée, remplissage de la barre log, puis décompte
# des coins héros (§8.89). §8.99 : `hero_coins_lbl` est désormais TOUJOURS construit par
# _build_hero_progress (même à 0) — le défaut `null` du paramètre et le test `!= null` plus bas ne
# sont plus que des gardes défensives (appel externe / futur), jamais le cas nominal : le décompte
# des coins héros s'exécute donc à chaque fois, 0 → 0 laissant le texte à « +0 ».
func _animate_hero(hero_xp_lbl: Label, hero_bar: ProgressBar, rewards: Dictionary,
		hero_coins_lbl: Label = null) -> void:
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

	if hero_coins_lbl != null:
		var coins := int(rewards.get("hero_coins_earned", 0))
		var tc := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tc.tween_method(
			func(v: float): hero_coins_lbl.text = "◈ COINS HÉROS : +%d" % int(round(v)),
			0.0, float(coins), 0.6)
		await tc.finished

# `points_lbl` est NULL en partie non classée (§8.88 : aucun compteur de points à animer) — le
# décompte est alors sauté, le reste de la séquence est identique.
func _run_reward_animation(points_lbl: Label, xp_lbl: Label, bar, rewards: Dictionary) -> void:
	# Laisse le layout se résoudre (tailles des nœuds) avant les Tweens d'échelle/pivot.
	await get_tree().process_frame

	# 1) Décompte des Points de Match (0 → match_points) — EN CLASSÉE UNIQUEMENT.
	if points_lbl != null:
		var pts := int(rewards.get("match_points", 0))
		var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t.tween_method(
			func(v: float): points_lbl.text = "POINTS DE MATCH : +%d" % int(round(v)),
			0.0, float(pts), 0.9)
		await t.finished

	# 2) Décompte de l'XP JOUEUR (§8.89) — même pattern que les points / l'XP héros. Le montant est
	#    DÉJÀ boosté par le serveur si le Pass est actif (le bandeau +25 % l'explique).
	if xp_lbl != null:
		var xp := int(rewards.get("xp_earned", 0))
		var tx := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tx.tween_method(
			func(v: float): xp_lbl.text = "XP JOUEUR : +%d" % int(round(v)),
			0.0, float(xp), 0.9)
		await tx.finished

	# 3) La barre d'XP se remplit (avec montées de niveau + lueur Coins aux paliers de 10, §4).
	await bar.play_match_result(rewards)
