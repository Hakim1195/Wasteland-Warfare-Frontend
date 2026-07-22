extends Control

# RAPPORT POST-OPÉRATION (§4 Warzone Command, refonte RETEX §8.100) — débriefing after-action de
# fin de partie. Fond = flou gaussien de l'arène gelée (report_blur.gdshader) + assombrissement
# gunmetal ; grand panneau central angulaire : titre massif, 4 onglets (XP JOUEUR / XP HÉROS /
# CLASSEMENT / BILAN — registre militaire, AUCUN emoji), CTA « RETOURNER AU LOBBY ». View PURE
# (Règle d'Or §6.1) : aucune logique de jeu / réseau ici — main.gd résout et pousse les données
# (populate*/set_*) et gère la navigation (back_to_lobby).

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
var _hero_tab: VBoxContainer = null             # onglet 2 : identité + progression héros + détail
var _hero_identity_box: VBoxContainer = null    # §8.100 : identité du héros — TOUJOURS peuplée
var _hero_progress_box: VBoxContainer = null    # bloc progression héros animé + détail
var _ranking_tab: VBoxContainer = null          # onglet 3 : podium (le récap de zone a quitté
												# l'onglet au §8.100 — la colonne ZONE du BILAN suffit)
var _podium_list: VBoxContainer = null
var _timeline_wrap: VBoxContainer = null
var _timeline_chart: TimelineChart = null
var _my_stats_box: VBoxContainer = null
# Onglet 4 : BILAN (§8.99) — tableau comparatif de TOUS les belligérants (gains/pertes/échange)
# + timeline de domination. Colonnes : JOUEUR · TERR · CONQ · KILLS · ÉLIM · HÉROS · UNITÉS ·
# ZONE · ÉCHANGE. Écartés à dessein (lisibilité à 700 px) : cards_played, détail des continents.
# §8.100 — rendu en RANGÉES HBox à colonnes de largeur FIXE (plus de GridContainer) : c'est ce
# qui permet la rangée d'EN-TÊTES GROUPÉS « GAINS / PERTES » de la maquette (une grille ne sait
# pas faire de cellule sur plusieurs colonnes) et la surbrillance de la ligne du vainqueur.
const DBF_NAME_W := 176.0   # colonne JOUEUR (pastille couleur + pseudo)
const DBF_COL_W := 46.0     # colonnes chiffrées des GAINS
const DBF_LOSS_W := 54.0    # colonnes chiffrées des PERTES
const DBF_BAR_W := 96.0     # colonne ÉCHANGE (barre kills / pertes)
const ROW_PAD_L := 6.0      # marge gauche COMMUNE (en-têtes + rangées) → colonnes alignées
var _debrief_tab: VBoxContainer = null
var _debrief_eyebrow: Label = null
var _debrief_rows_box: VBoxContainer = null
var _missions_lbl: Label = null
var _return_btn: Button = null
# Poignées DIRECTES vers les nœuds .tscn du récap de zone — MASQUÉS depuis le §8.100 (la colonne
# ZONE du BILAN porte l'information). Conservées : _build_player_rewards/_build_hero_progress les
# gardent comme cible de REPLI défensif, et aucune retouche .tscn n'est nécessaire (piège n° 6).
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
#   BOUCHER max kills · CONQUÉRANT max conquêtes · FOSSOYEUR max héros abattus (si > 0)
#   INDESTRUCTIBLE min pertes · IRRADIÉ max morts à la zone (si > 0).
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

# Indicatif de rang du podium (§8.100 — registre militaire, plus d'emojis) : « 01 », « 02 », …
# Le rendu colore le « 01 » en or (vainqueur) et les suivants en acier (cf. _make_podium_row).
static func medal_for(rank_index: int) -> String:
	return "%02d" % (rank_index + 1)

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

# Bouton « REJOUER » (G3 §8.70), construit par code À CÔTÉ du retour lobby (aucune retouche
# .tscn) : or (CTA de relance), anti double-clic, émet requeue_requested (main.gd décide).
# Références conservées (B.5) : au clic le bouton passe en RECHERCHE (libellé + pulsation sobre) ;
# main.gd le RÉACTIVE via reset_requeue_button() si le re-queue échoue alors que le rapport reste
# affiché.
var _requeue_btn: Button = null
var _requeue_pulse: Tween = null

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
		# État RECHERCHE : le joueur voit que la relance tourne (registre militaire, aucun emoji).
		btn.text = tr("REPORT_REQUEUE_SEARCHING")
		_start_requeue_pulse()
		requeue_requested.emit())
	_requeue_btn = btn
	parent.add_child(btn)
	parent.move_child(btn, anchor.get_index())

# Pulsation discrète de l'alpha du bouton (bordure or comprise) pendant la recherche : Tween en
# boucle 1.0 ↔ 0.72, ~0.9 s par aller-retour, sinus adouci — sobre, sans clignotement agressif.
func _start_requeue_pulse() -> void:
	if not is_instance_valid(_requeue_btn):
		return
	if _requeue_pulse != null and _requeue_pulse.is_valid():
		_requeue_pulse.kill()
	_requeue_btn.modulate.a = 1.0
	_requeue_pulse = create_tween().set_loops()
	_requeue_pulse.tween_property(_requeue_btn, "modulate:a", 0.72, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_requeue_pulse.tween_property(_requeue_btn, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# Réactive le bouton REJOUER si la relance échoue mais que le rapport reste affiché (appelé par
# main.gd::_on_requeue_failed, défensif via has_method) : stoppe la pulsation, restaure le libellé.
func reset_requeue_button() -> void:
	if _requeue_pulse != null and _requeue_pulse.is_valid():
		_requeue_pulse.kill()
	_requeue_pulse = null
	if is_instance_valid(_requeue_btn):
		_requeue_btn.modulate.a = 1.0
		_requeue_btn.text = tr("REPORT_REQUEUE")
		_requeue_btn.disabled = false

# Refonte EN ONGLETS (E-visuel) PAR CODE : un TabContainer s'insère dans ReportVBox à l'emplacement
# de l'eyebrow d'attrition ; 4 pages (ScrollContainer > VBox) — XP JOUEUR / XP HÉROS / CLASSEMENT /
# BILAN (§8.99, tableau comparatif + timeline). §8.100 : les blocs .tscn du récap de zone (eyebrow +
# stagnation + attrition) sont MASQUÉS, plus reparentés — aucune retouche .tscn (piège n° 6).
# Les conteneurs peuplés par populate*/set_* sont simplement RE-CIBLÉS (contrat main.gd inchangé).
func _build_tabs() -> void:
	# Poignées directes posées D'ABORD (héritage E11 : un reparentage cassait la résolution `%Nom` ;
	# depuis §8.100 on ne reparente plus, on MASQUE — les poignées restent le point d'accès unique).
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
	# §8.100 — placeholder honnête tant que le game_over n'est pas arrivé (course réseau) : l'onglet
	# n'est plus jamais BLANC. _build_player_rewards VIDE la boîte avant de construire (idempotent).
	_player_rewards_box.add_child(_pending_note(tr("REPORT_REWARDS_PENDING")))
	_player_tab.add_child(_eyebrow(tr("REPORT_MYPERF_EYEBROW")))
	_my_stats_box = VBoxContainer.new()
	_my_stats_box.add_theme_constant_override("separation", 3)
	_player_tab.add_child(_my_stats_box)

	# --- Onglet 2 : XP HÉROS (identité §8.100 + progression animée + détail du barème héros) ---
	_hero_tab = _add_tab_page("TabHero")
	# Identité du héros (faction, portrait, niveau, état) — peuplée par populate_hero_identity()
	# depuis des données 100 % LOCALES : visible même si les récompenses n'arrivent jamais.
	_hero_identity_box = VBoxContainer.new()
	_hero_identity_box.add_theme_constant_override("separation", 6)
	_hero_tab.add_child(_hero_identity_box)
	_hero_progress_box = VBoxContainer.new()
	_hero_progress_box.add_theme_constant_override("separation", 6)
	_hero_tab.add_child(_hero_progress_box)
	_hero_progress_box.add_child(_pending_note(tr("REPORT_REWARDS_PENDING")))

	# --- Onglet 3 : CLASSEMENT (podium + objectifs révélés) ---
	# §8.100 — le récap de zone (stagnation + attrition) NE migre PLUS ici : l'information vit dans
	# la colonne ZONE du BILAN (demande produit). Les nœuds .tscn d'origine restent dans l'arbre,
	# simplement MASQUÉS (aucune retouche .tscn — piège n° 6 ; les poignées restent valides).
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
	for node in [eyebrow, _stagnation_ref, _attrition_ref]:
		node.visible = false

	# --- Onglet 4 : BILAN (§8.99) — tableau comparatif de TOUS les belligérants + timeline ---
	# La timeline de domination vit ici : c'est une STATISTIQUE (comment chacun a performé),
	# pas un verdict (qui a gagné et pourquoi, laissé à l'onglet 3).
	_debrief_tab = _add_tab_page("TabDebrief")
	_debrief_eyebrow = _eyebrow(tr("REPORT_DEBRIEF_EYEBROW"))
	_debrief_tab.add_child(_debrief_eyebrow)
	_debrief_rows_box = VBoxContainer.new()
	_debrief_rows_box.add_theme_constant_override("separation", 0)
	_debrief_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debrief_tab.add_child(_debrief_rows_box)
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

	# Titres d'onglets (§8.100 — texte SEUL, sans emoji ; traduits, posés APRÈS l'ajout des pages).
	_tabs.set_tab_title(0, tr("REPORT_TAB_PLAYER"))
	_tabs.set_tab_title(1, tr("REPORT_TAB_HERO"))
	_tabs.set_tab_title(2, tr("REPORT_TAB_RANKING"))
	_tabs.set_tab_title(3, tr("REPORT_TAB_DEBRIEF"))

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

# Note discrète « — … — » (§8.100) : placeholder honnête des boîtes de récompenses tant que le
# game_over n'est pas arrivé. Les constructeurs (_build_player_rewards / _build_hero_progress)
# VIDENT leur boîte avant de poser le contenu réel — la note disparaît alors d'elle-même.
func _pending_note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", TEXT_MUTED)
	l.add_theme_font_size_override("font_size", 13)
	return l

# Badge-puce or bordé (§8.100) — titres honorifiques du podium (tooltip dédié) et chip de
# niveau du panneau héros. Remplace les libellés à emoji.
func _title_badge(text: String, tooltip: String = "") -> Control:
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(ACCENT_GOLD, 0.10)
	sb.set_border_width_all(1)
	sb.border_color = Color(ACCENT_GOLD, 0.65)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", sb)
	if tooltip != "":
		badge.tooltip_text = tooltip
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", ACCENT_GOLD)
	badge.add_child(l)
	return badge

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

# Boutons d'inspection (E11) : « INSPECTER LE CHAMP DE BATAILLE » dans la rangée de CTA +
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
# §8.100 — `provisional` : classement calculé LOCALEMENT (game_over pas encore reçu) → affiché
# quand même (mieux qu'un écran « en attente »), avec une mention discrète ; le verdict serveur
# le REMPLACE dès son arrivée (populate_podium re-appelé par _on_match_over, provisional=false).
func populate_podium(rows: Array, provisional: bool = false) -> void:
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
	if provisional and not rows.is_empty():
		var note := Label.new()
		note.name = "ProvisionalNote"
		note.text = tr("REPORT_PODIUM_PROVISIONAL")
		note.add_theme_color_override("font_color", TEXT_MUTED)
		note.add_theme_font_size_override("font_size", 11)
		_podium_list.add_child(note)

# Une ligne du podium (§8.100 — restylée sans emojis) : panneau à liseré gauche (OR pour le
# vainqueur, cyan discret sinon), indicatif de rang mono « 01 », brique PlayerChip, badges de
# titres, points ; 2e ligne = objectif révélé (✓/✕) + compteurs K·C·E en mono.
func _make_podium_row(r: Dictionary) -> Control:
	var is_first := str(r.get("medal", "")) == "01"
	var wrap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 10
	sb.border_width_left = 3
	if is_first:
		sb.bg_color = Color(ACCENT_GOLD, 0.07)
		sb.border_color = ACCENT_GOLD
	else:
		sb.bg_color = Color(1, 1, 1, 0.02)
		sb.border_color = Color(ACCENT_CYAN, 0.18)
	wrap.add_theme_stylebox_override("panel", sb)

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	wrap.add_child(card)
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 8)
	var rank_lbl := Label.new()
	rank_lbl.text = str(r.get("medal", "—"))
	rank_lbl.custom_minimum_size = Vector2(28, 0)
	rank_lbl.add_theme_font_override("font", RosterHelpers._mono_font())
	rank_lbl.add_theme_font_size_override("font_size", 17)
	rank_lbl.add_theme_color_override("font_color", ACCENT_GOLD if is_first else TEXT_MUTED)
	line1.add_child(rank_lbl)
	var chip := PlayerChipScene.instantiate()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line1.add_child(chip)
	chip.setup(int(r.get("pid", 0)), false)
	for t in r.get("titles", []):
		line1.add_child(_title_badge(tr(str(t)), tr("REPORT_TITLE_TOOLTIP")))
	card.add_child(line1)

	var line2 := HBoxContainer.new()
	line2.add_theme_constant_override("separation", 8)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(28, 0)
	line2.add_child(indent)
	# Objectif révélé (bloc PUBLIC objectives_reveal) — ✓ vert / ✕ acier ; mention neutre si
	# serveur antérieur (has_reveal false).
	var obj := Label.new()
	if bool(r.get("has_reveal", false)):
		var done := bool(r.get("completed", false))
		obj.text = ("✓ " if done else "✕ ") + str(r.get("objective", ""))
		obj.add_theme_color_override("font_color", Color("46b58a") if done else TEXT_MUTED)
	else:
		obj.text = tr("REPORT_OBJ_UNKNOWN")
		obj.add_theme_color_override("font_color", TEXT_MUTED)
	obj.add_theme_font_size_override("font_size", 12)
	obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obj.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	obj.tooltip_text = str(r.get("objective", ""))
	obj.mouse_filter = Control.MOUSE_FILTER_PASS
	line2.add_child(obj)
	var stats := Label.new()
	stats.text = tr("REPORT_STATS_LINE") % [int(r.get("kills", 0)), int(r.get("conquests", 0)),
		int(r.get("eliminations", 0))]
	stats.add_theme_font_override("font", RosterHelpers._mono_font())
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", Color("c8cdd6"))
	stats.tooltip_text = tr("REPORT_STATS_LEGEND")
	stats.mouse_filter = Control.MOUSE_FILTER_PASS
	line2.add_child(stats)
	card.add_child(line2)
	return wrap

# Tableau BILAN (§8.99, rendu maquette §8.100) — `rows` résolues par main.gd via
# WarRoom.debrief_rows (module PUR) + enrichies de `color` (pastille plateau) :
# { pid, username, is_bot, is_alive, is_me, is_winner, rank, territories, conquests, kills,
#   eliminations, hero_damage, hero_kills, losses, zone_deaths, ratio, threat, color }.
# Vue PURE (Règle d'Or §6.1) : aucun calcul ici, uniquement du rendu. Clé `data["debrief"]`
# FACULTATIVE côté populate() (§9.2) : payload legacy → cette fonction n'est jamais appelée, le
# tableau reste vide (l'onglet existe, sans en-têtes), aucune erreur.
func populate_debrief(rows: Array) -> void:
	if _debrief_rows_box == null:
		return
	for c in _debrief_rows_box.get_children():
		_debrief_rows_box.remove_child(c)
		c.queue_free()
	# En-tête d'onglet façon maquette : « ❯ BILAN TACTIQUE — N BELLIGÉRANTS ».
	if _debrief_eyebrow != null:
		_debrief_eyebrow.text = tr("REPORT_DEBRIEF_EYEBROW") \
			+ ((tr("REPORT_DEBRIEF_COUNT") % rows.size()) if not rows.is_empty() else "")

	# Rangée d'EN-TÊTES GROUPÉS : GAINS (5 colonnes) souligné cyan / PERTES (2 colonnes) souligné
	# rouge — la lecture « gains vs pertes » de la maquette, impossible avec l'ancien GridContainer.
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 0)
	groups.add_child(_spacer(ROW_PAD_L))
	groups.add_child(_fixed_cell("", DBF_NAME_W, TEXT_MUTED, 10, HORIZONTAL_ALIGNMENT_LEFT))
	groups.add_child(_group_rule(tr("REPORT_DEBRIEF_GAINS"), ACCENT_CYAN, DBF_COL_W * 5.0))
	groups.add_child(_group_rule(tr("REPORT_DEBRIEF_LOSSES"), DANGER, DBF_LOSS_W * 2.0))
	groups.add_child(_fixed_cell("", DBF_BAR_W, TEXT_MUTED, 10, HORIZONTAL_ALIGNMENT_CENTER))
	_debrief_rows_box.add_child(groups)

	# Rangée des TITRES de colonnes (PERTES en rouge : lisible sans légende).
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override("separation", 0)
	heads.add_child(_spacer(ROW_PAD_L))
	heads.add_child(_fixed_cell(tr("COMMON_OPERATOR"), DBF_NAME_W, TEXT_MUTED, 10, HORIZONTAL_ALIGNMENT_LEFT))
	for h in ["REPORT_DBF_COL_TERR", "REPORT_DBF_COL_CONQ", "REPORT_DBF_COL_KILLS",
			"REPORT_DBF_COL_ELIM", "REPORT_DBF_COL_HEROES"]:
		heads.add_child(_fixed_cell(tr(h), DBF_COL_W, TEXT_MUTED, 10, HORIZONTAL_ALIGNMENT_RIGHT))
	for h in ["REPORT_DBF_COL_UNITS", "REPORT_DBF_COL_ZONE"]:
		heads.add_child(_fixed_cell(tr(h), DBF_LOSS_W, DANGER, 10, HORIZONTAL_ALIGNMENT_RIGHT))
	heads.add_child(_fixed_cell(tr("REPORT_DBF_COL_TRADE"), DBF_BAR_W, TEXT_MUTED, 10, HORIZONTAL_ALIGNMENT_CENTER))
	_debrief_rows_box.add_child(heads)
	_debrief_rows_box.add_child(_spacer_v(3.0))

	for i in range(rows.size()):
		_debrief_rows_box.add_child(_make_debrief_row(rows[i], i % 2 == 1))

# Une ligne du tableau BILAN (§8.100). Vainqueur → panneau lavé OR + liseré gauche or (maquette) ;
# moi → pseudo cyan ; éliminé → muet + ✕ rouge ; sinon texte primaire. Les colonnes UNITÉS/ZONE
# (pertes) restent en rouge quel que soit le tint de la ligne — même logique que l'en-tête.
func _make_debrief_row(r: Dictionary, odd: bool) -> Control:
	var alive := bool(r.get("is_alive", true))
	var is_winner := bool(r.get("is_winner", false))
	var tint: Color = ACCENT_GOLD if is_winner \
		else (ACCENT_CYAN if bool(r.get("is_me", false)) else (TEXT_PRIMARY if alive else TEXT_MUTED))
	var wrap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.content_margin_left = ROW_PAD_L
	if is_winner:
		sb.bg_color = Color(ACCENT_GOLD, 0.08)
		sb.border_width_left = 3
		sb.border_color = ACCENT_GOLD
	else:
		# Zébrage discret une ligne sur deux : balayage horizontal guidé, sans bruit visuel.
		sb.bg_color = Color(1, 1, 1, 0.025) if odd else Color(0, 0, 0, 0)
	wrap.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	wrap.add_child(row)

	# Colonne JOUEUR : pastille couleur PLATEAU + pseudo (+ ✕ rouge si éliminé).
	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 6)
	name_box.custom_minimum_size = Vector2(DBF_NAME_W, 0)
	var sw := ColorRect.new()
	sw.color = r.get("color", Color("8a97a5"))
	sw.custom_minimum_size = Vector2(10, 10)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_box.add_child(sw)
	var tag := tr("REPORT_BOT_TAG") if bool(r.get("is_bot", false)) else ""
	var name_lbl := Label.new()
	name_lbl.text = "%s%s" % [tag, str(r.get("username", "?"))]
	name_lbl.add_theme_color_override("font_color", tint)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_box.add_child(name_lbl)
	if not alive:
		var kia := Label.new()
		kia.text = "✕"
		kia.add_theme_color_override("font_color", DANGER)
		kia.add_theme_font_size_override("font_size", 12)
		name_box.add_child(kia)
	row.add_child(name_box)

	for key in ["territories", "conquests", "kills", "eliminations", "hero_kills"]:
		row.add_child(_num_cell(int(r.get(key, 0)), DBF_COL_W, tint))
	for key in ["losses", "zone_deaths"]:
		row.add_child(_num_cell(int(r.get(key, 0)), DBF_LOSS_W, DANGER))

	# ÉCHANGE : ratio kills/(kills+pertes) — barre CYAN (gains) sur fond ROUGE (pertes) : lecture
	# instantanée, sans comparer les colonnes chiffrées (cf. REPORT_DEBRIEF_LEGEND).
	var bar_wrap := CenterContainer.new()
	bar_wrap.custom_minimum_size = Vector2(DBF_BAR_W, 0)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = float(r.get("ratio", 0.5))
	bar.custom_minimum_size = Vector2(DBF_BAR_W - 20.0, 6)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(DANGER, 0.55)
	bar_bg.set_corner_radius_all(0)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT_CYAN
	bar_fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	bar_wrap.add_child(bar)
	row.add_child(bar_wrap)
	return wrap

# --- Briques du tableau BILAN (§8.100) ---

# Cellule de LARGEUR FIXE (alignement inter-rangées garanti sans grille).
func _fixed_cell(text: String, w: float, color: Color, font_size: int, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = align
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return l

# Cellule CHIFFRÉE (police mono, alignée à droite) — colonne de largeur fixe.
func _num_cell(value: int, w: float, color: Color) -> Label:
	var l := _fixed_cell(str(value), w, color, 12, HORIZONTAL_ALIGNMENT_RIGHT)
	l.add_theme_font_override("font", RosterHelpers._mono_font())
	return l

# En-tête de GROUPE de colonnes (« GAINS » / « PERTES ») : libellé centré + filet 1 px souligné,
# retrait latéral de 8 px (les deux groupes adjacents restent visuellement séparés — maquette).
func _group_rule(text: String, color: Color, w: float) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(w, 0)
	box.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 8)
	mc.add_theme_constant_override("margin_right", 8)
	var rule := ColorRect.new()
	rule.color = Color(color, 0.55)
	rule.custom_minimum_size = Vector2(0, 1)
	mc.add_child(rule)
	box.add_child(mc)
	return box

func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c

func _spacer_v(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

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
		# §8.100 — flag EXPLICITE `hero_dead` (résolu par main.gd) : l'ancien test sur le préfixe
		# emoji du libellé i18n cassait dès que la traduction changeait.
		hero_lbl.add_theme_color_override("font_color",
			DANGER if bool(ms.get("hero_dead", false)) else ACCENT_CYAN)
		_my_stats_box.add_child(hero_lbl)

# §8.100 — identité du héros LOCAL (onglet XP HÉROS, en-tête TOUJOURS visible) : panneau à liseré
# couleur plateau — portrait de faction, nom, chip de niveau, état (PV/PA/PP ou ABATTU). `h` résolu
# par main.gd (_hero_panel_data, données 100 % locales) ; {} (pré-RPG / spectateur) → aucun panneau.
func populate_hero_identity(h: Dictionary) -> void:
	if _hero_identity_box == null:
		return
	for c in _hero_identity_box.get_children():
		_hero_identity_box.remove_child(c)
		c.queue_free()
	if h.is_empty():
		return
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(0.101961, 0.12549, 0.156863, 0.5)
	sb.border_width_left = 3
	sb.border_color = h.get("color", ACCENT_CYAN)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)
	var portrait = h.get("portrait")
	if portrait is Texture2D:
		var tex := TextureRect.new()
		tex.texture = portrait
		tex.custom_minimum_size = Vector2(56, 56)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.clip_contents = true
		hb.add_child(tex)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	col.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = str(h.get("faction_name", "")).to_upper()
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(name_lbl)
	name_row.add_child(_title_badge(tr("REPORT_HERO_LEVEL") % int(h.get("level", 1))))
	# Identité du meneur (refonte 2026-07-18) : « GÉNÉRAL VIKTOR "IRONLINE" STAHL » sous le nom
	# de faction (rang traduit + nom propre invariant, résolu par main._hero_panel_data).
	var leader := str(h.get("leader", ""))
	if leader != "":
		var leader_lbl := Label.new()
		leader_lbl.text = leader.to_upper()
		leader_lbl.add_theme_font_size_override("font_size", 13)
		var lc = h.get("color", ACCENT_CYAN)
		leader_lbl.add_theme_color_override("font_color",
			Color(lc if lc is Color else ACCENT_CYAN, 0.9))
		col.add_child(leader_lbl)
	var state_lbl := Label.new()
	state_lbl.add_theme_font_override("font", RosterHelpers._mono_font())
	state_lbl.add_theme_font_size_override("font_size", 12)
	if bool(h.get("is_dead", false)):
		state_lbl.text = tr("REPORT_HERO_DOWN")
		state_lbl.add_theme_color_override("font_color", DANGER)
	else:
		state_lbl.text = tr("REPORT_HERO_STATE") % [int(h.get("pv_current", 0)),
			int(h.get("pv_max", 0)), int(h.get("pa", 0)), int(h.get("pp", 0))]
		state_lbl.add_theme_color_override("font_color", Color("c8cdd6"))
	col.add_child(state_lbl)
	_hero_identity_box.add_child(panel)

# §8.100 — MAJ des entrées brutes du détail du barème APRÈS coup (main.gd, à l'arrivée du
# game_over) : le rang serveur définitif remplace le rang deviné à l'ouverture du rapport.
# Sans effet si le détail est déjà construit (garde _rewards_built en amont).
func set_xp_detail(d: Dictionary) -> void:
	if typeof(d) == TYPE_DICTIONARY and not d.is_empty():
		_detail_inputs = d

# Pont missions (M2 §8.65 — E11) : rappel de la boucle de rétention au pied de MA colonne.
func set_missions_summary(progressed: int, claimable: int) -> void:
	if _player_tab == null:
		return
	if _missions_lbl == null or not is_instance_valid(_missions_lbl):
		_missions_lbl = Label.new()
		_missions_lbl.add_theme_font_size_override("font_size", 14)
		_player_tab.add_child(_missions_lbl)
	_missions_lbl.text = tr("REPORT_MISSIONS") % [progressed, claimable]
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
#   debrief: Array (FACULTATIF, §8.99) — tableau BILAN, une ligne/belligérant (populate_debrief),
#   hero_panel: Dictionary (FACULTATIF, §8.100) — identité du héros local (populate_hero_identity),
#   podium_provisional: bool (FACULTATIF, §8.100) — podium issu du repli LOCAL (mention discrète) }
func populate(data: Dictionary) -> void:
	%ReportTitle.text = str(data.get("title", tr("REPORT_TITLE_DEFAULT"))).to_upper()
	%ReportTitle.add_theme_color_override("font_color", data.get("title_color", ACCENT_GOLD))
	# Entrées brutes du détail du barème (FACULTATIF, E-visuel) — stockées AVANT populate_rewards,
	# qui peut arriver plus tard (course réseau) et en aura besoin pour reconstruire les postes.
	_detail_inputs = data.get("xp_detail", {})

	# §8.100 — le récap de zone (stagnation + attrition) n'est PLUS rendu : la colonne ZONE du
	# BILAN porte l'information (demande produit). Les clés `stagnation`/`attrition`/`worst_pseudo`
	# restent ACCEPTÉES dans `data` (contrat main.gd/tests inchangé) mais sont ignorées — les nœuds
	# .tscn correspondants sont masqués par _build_tabs.

	# Blocs E11 (clés FACULTATIVES — payload legacy → sections masquées, aucune erreur §9.2).
	# §8.100 — identité du héros (données 100 % locales) : l'onglet XP HÉROS a TOUJOURS un contenu.
	populate_hero_identity(data.get("hero_panel", {}))
	if data.has("podium"):
		populate_podium(data.get("podium", []), bool(data.get("podium_provisional", false)))
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
	# §8.100 — boîte VIDÉE avant construction : efface le placeholder « en attente » posé par
	# _build_tabs (et rend la construction idempotente).
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = tr("REPORT_REWARDS_HEADER")
	header.add_theme_color_override("font_color", ACCENT_CYAN)
	header.add_theme_font_size_override("font_size", 18)
	block.add_child(header)

	# §8.99 — le serveur n'a envoyé AUCUNE récompense alors que le joueur a bien disputé la partie
	# (populate_rewards ne nous fait atteindre ce point avec `rewards` vide QUE si `has_played`
	# était vrai) : 0 XP ne devrait JAMAIS arriver. On rend l'anomalie VISIBLE plutôt que d'afficher
	# un bloc de zéros silencieux qui passerait pour un résultat normal.
	if rewards.is_empty():
		var anomaly := Label.new()
		anomaly.text = tr("REPORT_REWARDS_NONE")
		anomaly.add_theme_color_override("font_color", DANGER)
		anomaly.add_theme_font_size_override("font_size", 13)
		block.add_child(anomaly)

	# §8.88 : en partie NON classée, mention muette explicite (aucun ladder crédité). En classée,
	# c'est le bloc RP ci-dessous qui porte l'information de classement — les « points de match »
	# (ladder À VIE) ont été RETIRÉS du jeu.
	if not is_ranked:
		var unranked_lbl := Label.new()
		unranked_lbl.text = tr("REPORT_UNRANKED")
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
	xp_lbl.text = tr("REPORT_PLAYER_XP") % 0
	block.add_child(xp_lbl)

	# Pass Spécial (M4 §8.67) : RELAIS du flag serveur (+25 % XP déjà appliqué côté serveur).
	if bool(rewards.get("pass_bonus_applied", false)):
		var pass_lbl := Label.new()
		pass_lbl.text = tr("REPORT_PASS_BONUS")
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
		lvl_lbl.text = tr("REPORT_LEVELS_GAINED") % [gained, int(rewards.get("new_level", 1))]
		lvl_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
		lvl_lbl.add_theme_font_size_override("font_size", 14)
		block.add_child(lvl_lbl)

	# COINS GAGNÉS (§8.89/§8.99) — TOTAL réel = coins de PROFIL (paliers de 10 niveaux) + coins de
	# MONTÉE DE NIVEAU DU HÉROS (même porte-monnaie). §8.99 : TOUJOURS affiché, même à 0 — un
	# compteur masqué à 0 est indiscernable d'un compteur ABSENT (le joueur ne peut pas savoir s'il
	# a gagné 0 ou si l'affichage a échoué). §8.100 — icône hexagonale de la charte (CoinIcon,
	# réutilisée de xp_coins_bar) à la place de l'ancien glyphe « ◈ ».
	var coins_profile := int(rewards.get("coins_earned", 0))
	var coins_hero := int(rewards.get("hero_coins_earned", 0))
	var coins_total := coins_profile + coins_hero
	var coins_row := HBoxContainer.new()
	coins_row.add_theme_constant_override("separation", 8)
	var coin_ic = XpCoinsBarScript.CoinIcon.new()
	coin_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins_row.add_child(coin_ic)
	var coins_lbl := Label.new()
	coins_lbl.text = tr("REPORT_COINS_EARNED") % coins_total
	coins_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	coins_lbl.add_theme_font_size_override("font_size", 18)
	coins_row.add_child(coins_lbl)
	block.add_child(coins_row)
	# Détail muet : uniquement quand les DEUX sources ont contribué (sinon le total se suffit — ce
	# n'est pas un compteur masqué mais une RÉPARTITION, et la part héros reste lisible onglet 2).
	if coins_profile > 0 and coins_hero > 0:
		var coins_sub := Label.new()
		coins_sub.text = tr("REPORT_COINS_SPLIT") % [coins_profile, coins_hero]
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

	await _run_reward_animation(xp_lbl, bar, rewards)

# Onglet 2 — bloc PROGRESSION DU HÉROS animé (XP héros + niveau + barre log + paliers de stats)
# SUIVI du détail du barème héros (réconcilié à hero_xp_earned). Coroutine (await l'animation).
func _build_hero_progress(rewards: Dictionary) -> void:
	var box: VBoxContainer = _hero_progress_box if _hero_progress_box != null else _attrition_ref
	# §8.100 — boîte VIDÉE avant construction (efface le placeholder « en attente », idempotent).
	# L'en-tête d'IDENTITÉ du héros vit dans _hero_identity_box, séparée : il n'est pas touché.
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

	var hero_header := Label.new()
	hero_header.text = tr("REPORT_HERO_PROGRESS_HEADER")
	hero_header.add_theme_color_override("font_color", ACCENT_CYAN)
	hero_header.add_theme_font_size_override("font_size", 18)
	block.add_child(hero_header)

	var hero_xp_lbl := Label.new()
	hero_xp_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	hero_xp_lbl.add_theme_font_size_override("font_size", 20)
	hero_xp_lbl.text = tr("REPORT_HERO_XP") % 0
	block.add_child(hero_xp_lbl)

	# COINS HÉROS (§8.89/§8.99) : les montées de niveau du héros créditent des coins sur le MÊME
	# porte-monnaie que le profil. §8.99 : TOUJOURS construit, même à 0 → `hero_coins_lbl` n'est
	# plus jamais null, l'animation de queue d'_animate_hero s'exécute donc toujours (cf. plus bas,
	# le test `!= null` y reste une garde défensive inoffensive, pas une condition d'affichage).
	var hero_coins_row := HBoxContainer.new()
	hero_coins_row.add_theme_constant_override("separation", 8)
	var hero_coin_ic = XpCoinsBarScript.CoinIcon.new()
	hero_coin_ic.custom_minimum_size = Vector2(18, 18)
	hero_coin_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero_coins_row.add_child(hero_coin_ic)
	var hero_coins_lbl := Label.new()
	hero_coins_lbl.add_theme_color_override("font_color", ACCENT_GOLD)
	hero_coins_lbl.add_theme_font_size_override("font_size", 16)
	hero_coins_lbl.text = tr("REPORT_HERO_COINS") % 0
	hero_coins_row.add_child(hero_coins_lbl)
	block.add_child(hero_coins_row)

	var hero_level_lbl := Label.new()
	var h_old := int(rewards.get("hero_level", 1))
	var h_new := int(rewards.get("hero_new_level", h_old))
	hero_level_lbl.text = (tr("REPORT_HERO_LEVEL_CHANGE") % [h_old, h_new]) if h_new > h_old \
			else (tr("REPORT_HERO_LEVEL_CURRENT") % h_new)
	hero_level_lbl.add_theme_color_override("font_color", ACCENT_CYAN if h_new > h_old else TEXT_MUTED)
	hero_level_lbl.add_theme_font_size_override("font_size", 14)
	block.add_child(hero_level_lbl)

	# Niveaux héros gagnés (§8.89) — ligne MIROIR du bloc joueur (« ▲ N NIVEAU(X) GAGNÉ(S) »),
	# pilotée par le flag SERVEUR hero_level_up plutôt que par la déduction h_new > h_old.
	if bool(rewards.get("hero_level_up", false)):
		var hero_gain_lbl := Label.new()
		hero_gain_lbl.text = tr("REPORT_HERO_LEVELS_GAINED") % int(rewards.get("hero_levels_gained", 0))
		hero_gain_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
		hero_gain_lbl.add_theme_font_size_override("font_size", 14)
		block.add_child(hero_gain_lbl)

	# Barre log : remplie à la fraction xp_in_level / xp_for_level (0..1) calculée serveur-side.
	# §8.100 — habillée charte (remplissage CYAN sur gunmetal, angles droits) : la barre au thème
	# gris par défaut détonnait au milieu des jauges stylées (XpCoinsBar, ÉCHANGE du BILAN).
	var hero_bar := ProgressBar.new()
	hero_bar.min_value = 0.0
	hero_bar.max_value = 1.0
	hero_bar.value = 0.0
	hero_bar.show_percentage = false
	hero_bar.custom_minimum_size = Vector2(0, 14)
	hero_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb_bg := StyleBoxFlat.new()
	hb_bg.bg_color = Color(0.101961, 0.12549, 0.156863, 1)
	hb_bg.set_corner_radius_all(0)
	hb_bg.set_border_width_all(1)
	hb_bg.border_color = Color(ACCENT_CYAN, 0.35)
	var hb_fill := StyleBoxFlat.new()
	hb_fill.bg_color = ACCENT_CYAN
	hb_fill.set_corner_radius_all(0)
	hero_bar.add_theme_stylebox_override("background", hb_bg)
	hero_bar.add_theme_stylebox_override("fill", hb_fill)
	block.add_child(hero_bar)

	# Pop-up « Statistiques Améliorées » : un palier franchi → bonus de stats (ex. +50 PV, +1 PA).
	for ms in rewards.get("hero_milestones", []):
		var ms_lbl := Label.new()
		ms_lbl.text = tr("REPORT_HERO_MILESTONE") % [
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

# XP de profil (rewards.compute_match_xp) : +10/conquête, +2/kill, +5/continent et +150 forfait
# réservés au haut du tableau ; Pass Spécial → ×1.25 (floor) sur le TOTAL, matérialisé par un poste
# bonus (miroir process_match_results).
static func player_xp_breakdown(rank: int, conquests: int, enemy_kills: int,
		continents_conquered: int, pass_applied: bool, pass_bonus_override: int = -1) -> Array:
	var items: Array = []
	items.append({"key": "REPORT_XP_CONQ", "value": 10 * conquests})
	items.append({"key": "REPORT_XP_KILL", "value": 2 * enemy_kills})
	if rank <= 1:
		items.append({"key": "REPORT_XP_CONT", "value": 5 * continents_conquered})
	if rank == 0:
		items.append({"key": "REPORT_XP_WIN", "value": 150})
	items = _nonzero(items)
	# Bonus Pass : le SERVEUR fait foi (`xp_inputs.xp_pass_bonus`, qui porte le multiplicateur du
	# PALIER RÉEL — Plus ×1.10, Premium ×1.25, Infinity ×1.50). Repli LOCAL (override < 0, serveur
	# antérieur) : on ne peut que supposer PREMIUM ×1.25 — c'était la source historique d'un
	# « Ajustement serveur » systématique pour tout détenteur d'un AUTRE palier.
	var bonus := 0
	if pass_bonus_override >= 0:
		bonus = pass_bonus_override
	elif pass_applied:
		var base_total := _breakdown_total(items)
		bonus = int(floor(1.25 * float(base_total))) - base_total
	if bonus != 0:
		items.append({"key": "REPORT_XP_PASS", "value": bonus})
	return items

# XP HÉROS (rewards.compute_hero_match_xp) : +1/unité tuée, +150 objectif, +5/territoire en fin,
# +100/coup de grâce, +1/4 PV de dégâts héros.
static func hero_xp_breakdown(enemy_units_killed: int, objective_win: bool,
		territories_end: int, hero_kills: int, hero_damage: int) -> Array:
	var items: Array = []
	items.append({"key": "REPORT_HXP_UNITS", "value": enemy_units_killed})
	if objective_win:
		items.append({"key": "REPORT_HXP_OBJ", "value": 150})
	items.append({"key": "REPORT_HXP_TERR", "value": 5 * territories_end})
	items.append({"key": "REPORT_HXP_GRAVE", "value": 100 * hero_kills})
	items.append({"key": "REPORT_HXP_DMG", "value": hero_damage / 4})
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
	# XP de profil — miroir de rewards.compute_match_xp (+ Pass ×1.25 floor).
	assert(_breakdown_total(player_xp_breakdown(0, 3, 10, 1, false)) == 205)  # 30+20+5+150
	assert(_breakdown_total(player_xp_breakdown(0, 3, 10, 1, true)) == 256)   # floor(1.25×205)
	assert(_breakdown_total(player_xp_breakdown(2, 3, 10, 5, false)) == 50)   # rang 3+ : ni cont ni win
	# XP héros — miroir de rewards.compute_hero_match_xp.
	assert(_breakdown_total(hero_xp_breakdown(25, true, 4, 1, 55)) == 308)    # 25+150+20+100+ (55/4=13)
	assert(_breakdown_total(hero_xp_breakdown(9, false, 0, 0, 9)) == 11)      # 9 + (9/4=2)

# Entrées EXACTES du barème telles que le SERVEUR les a utilisées (bloc ADDITIF `xp_inputs` de
# `match_rewards`). {} si le serveur est antérieur → chaque appelant retombe sur son estimation
# locale (comportement historique, l'écart restant absorbé par « Ajustement serveur »).
func _server_inputs(rewards: Dictionary) -> Dictionary:
	var srv = rewards.get("xp_inputs", {})
	return srv if typeof(srv) == TYPE_DICTIONARY else {}

# Détail de l'XP DE PROFIL (onglet 1) — entrées SERVEUR prioritaires, repli sur les entrées
# locales `_detail_inputs`. Réconcilié au total serveur (xp_earned).
func _build_player_detail(box: VBoxContainer, rewards: Dictionary) -> void:
	if _detail_inputs.is_empty():
		return
	var d := _detail_inputs
	var srv := _server_inputs(rewards)
	var rank := int(srv.get("rank", d.get("rank", 0)))
	var kills := int(srv.get("enemy_kills", d.get("kills", 0)))
	# XP : continents CONQUIS PENDANT la partie — métrique DIFFÉRENTE de celle des points (un
	# continent pris puis perdu compte ici). Le client ne la trace pas : sans le bloc serveur, il
	# retombe sur les continents possédés en fin, d'où l'ancien écart de ±5/continent.
	var xp_items := player_xp_breakdown(rank,
		int(srv.get("conquests", d.get("conquests", 0))), kills,
		int(srv.get("continents_conquered", d.get("continents_final", 0))),
		bool(rewards.get("pass_bonus_applied", false)),
		int(srv.get("xp_pass_bonus", -1)))
	_render_detail(box, tr("REPORT_XP_EYEBROW"), xp_items,
		int(rewards.get("xp_earned", _breakdown_total(xp_items))), "REPORT_UNIT_XP")

# Détail du barème HÉROS (onglet 2) — mêmes entrées SERVEUR prioritaires (ses `statistics` locales
# peuvent être en retard d'une action sur l'état final). Réconcilié à rewards.hero_xp_earned.
func _build_hero_detail(box: VBoxContainer, rewards: Dictionary) -> void:
	if _detail_inputs.is_empty():
		return
	var d := _detail_inputs
	var srv := _server_inputs(rewards)
	var items := hero_xp_breakdown(
		int(srv.get("enemy_kills", d.get("kills", 0))),
		bool(srv.get("objective_win", d.get("objective_done", false))),
		int(srv.get("territories_end", d.get("territories_final", 0))),
		int(srv.get("hero_kills", d.get("hero_kills", 0))),
		int(srv.get("hero_damage", d.get("hero_damage", 0))))
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
# Abréviations de stats i18n : réutilise CHAR_STAT_* (PV/PA/PB → HP/ATK/DEF en anglais).
func _format_milestone_bonus(bonus: Dictionary) -> String:
	var parts: Array[String] = []
	if int(bonus.get("pv_max", 0)) != 0:
		parts.append("+%d %s" % [int(bonus.get("pv_max", 0)), tr("CHAR_STAT_PV")])
	if int(bonus.get("pa", 0)) != 0:
		parts.append("+%d %s" % [int(bonus.get("pa", 0)), tr("CHAR_STAT_PA")])
	if float(bonus.get("pb", 0.0)) != 0.0:
		parts.append("+%d%% %s" % [int(round(float(bonus.get("pb", 0.0)) * 100.0)), tr("CHAR_STAT_PB")])
	return ", ".join(parts) if not parts.is_empty() else tr("REPORT_MILESTONE_FALLBACK")


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
		func(v: float): hero_xp_lbl.text = tr("REPORT_HERO_XP") % int(round(v)),
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
			func(v: float): hero_coins_lbl.text = tr("REPORT_HERO_COINS") % int(round(v)),
			0.0, float(coins), 0.6)
		await tc.finished

func _run_reward_animation(xp_lbl: Label, bar, rewards: Dictionary) -> void:
	# Laisse le layout se résoudre (tailles des nœuds) avant les Tweens d'échelle/pivot.
	await get_tree().process_frame

	# 1) Décompte de l'XP JOUEUR (§8.89) — même pattern que les points / l'XP héros. Le montant est
	#    DÉJÀ boosté par le serveur si le Pass est actif (le bandeau +25 % l'explique).
	if xp_lbl != null:
		var xp := int(rewards.get("xp_earned", 0))
		var tx := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tx.tween_method(
			func(v: float): xp_lbl.text = tr("REPORT_PLAYER_XP") % int(round(v)),
			0.0, float(xp), 0.9)
		await tx.finished

	# 3) La barre d'XP se remplit (avec montées de niveau + lueur Coins aux paliers de 10, §4).
	await bar.play_match_result(rewards)
