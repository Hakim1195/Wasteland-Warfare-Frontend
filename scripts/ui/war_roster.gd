extends PanelContainer

# ROSTER DE GUERRE (E1 §8.73) — panneau PERMANENT du panneau latéral listant TOUS les
# belligérants avec leur état complet : « qui est qui, qui joue, qui est mort », sans un clic.
# Une ligne par joueur, triée par GameState.turn_order (l'Initiative §4.1 devient lisible) :
#   player_chip (pastille couleur plateau + pseudo + faction) + niveau héros + mini-barre PV
#   (dégradé vert→or→rouge) + compteur de territoires + cartes en main + icônes d'état
#   (▶ tour courant pulsé, 💀 héros abattu/éliminé — ligne grisée, 🏳 abandon Fallen Empire §8.20).
# Bandeau d'ordre de tour en tête : chips compactes dans l'ordre de rotation, la courante en
# surbrillance. Toutes les données sont DÉJÀ publiques (GameState.players §8.28/§8.61 +
# territories) : rafraîchi par hud.update_display() à chaque état reçu — AUCUN nouveau flux
# réseau. View pure (Règle d'Or §6.1) : le clic d'une ligne REMONTE au contrôleur (signal),
# c'est main.gd qui ouvre l'inspecteur et pilote la caméra.

# Clic sur la ligne d'un joueur → main.gd (via hud.roster_player_clicked) : inspecteur héros
# (hud.set_player_inspector, réutilisé tel quel) + focus caméra sur son territoire le plus garni.
signal player_clicked(player_id: int)

const PlayerChipScene := preload("res://scenes/components/player_chip.tscn")

# Charte « Warzone Command » (§2) — mêmes constantes que hud.gd (source de vérité FRONTEND §2).
const ACCENT_CYAN := Color("36c5d9")
const ACCENT_GOLD := Color("e0b249")
const DANGER := Color("d6453f")
const MUTED := Color("8a97a5")
# Vert « santé pleine » du dégradé PV (vert oxydé de la palette plateau — esprit wasteland).
const PV_GREEN := Color("46b58a")
# Opacité d'une ligne neutralisée (héros abattu / éliminé / abandon) — la ligne reste lisible.
const ROW_DIMMED_ALPHA := 0.45

var _order_band: HFlowContainer = null
var _rows_box: VBoxContainer = null

# Auto-vérification debug : une fois par session (pattern G4 §8.63 — combat_odds._self_check).
static var _self_checked := false

func _ready() -> void:
	# Recapte les clics (pattern _hero_panel du HUD) : sans STOP, un clic sur le panneau
	# TRAVERSERAIT jusqu'au plateau (picking Area2D + board_cleared → l'inspecteur ouvert par la
	# ligne serait refermé dans la même frame).
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Panneau interne sombre, même langage que le Journal Militaire / fiche héros (gunmetal,
	# fin liseré cyan, coins DROITS — charte §2).
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.72)
	style.border_color = Color(ACCENT_CYAN, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	var title := Label.new()
	title.text = tr("ROSTER_TITLE")
	title.add_theme_color_override("font_color", ACCENT_CYAN)
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Bandeau d'ordre de tour (Initiative §4.1) : chips compactes, retour à la ligne automatique.
	# TUTO: emplacement candidat pour un tooltip d'onboarding « l'ordre du tour se lit ici ».
	_order_band = HFlowContainer.new()
	_order_band.add_theme_constant_override("h_separation", 3)
	_order_band.add_theme_constant_override("v_separation", 1)
	_order_band.tooltip_text = tr("ROSTER_ORDER_TOOLTIP")
	col.add_child(_order_band)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 2)
	col.add_child(_rows_box)

	if OS.is_debug_build() and not _self_checked:
		_self_check()

# Rafraîchit tout le roster depuis l'état public courant. Appelé par hud.update_display()
# (déjà invoqué par main._refresh() à chaque état reçu) — reconstruction complète, même
# pattern que hud._refresh_cards (queue_free + rebuild).
func refresh() -> void:
	if _rows_box == null:
		return
	var order := sorted_pids(GameState.players, GameState.turn_order)
	_rebuild_order_band(order)
	_rebuild_rows(order)

# =========================================================
# Helpers PURS (statiques — testables par asserts, pattern G4)
# =========================================================

# Ordre d'affichage : turn_order (rotation d'Initiative §4.1) en tête, pids normalisés int
# (piège JSON §5 : floats/clés string) ; les joueurs ABSENTS de la rotation (état pré-game /
# legacy) sont relégués en fin, triés par id croissant (même ordre stable que la palette).
static func sorted_pids(players: Dictionary, turn_order: Array) -> Array:
	var out: Array = []
	for pid in turn_order:
		if players.has(str(int(pid))) and not out.has(int(pid)):
			out.append(int(pid))
	var rest: Array = []
	for k in players.keys():
		if not out.has(int(k)):
			rest.append(int(k))
	rest.sort()
	out.append_array(rest)
	return out

# Nombre de territoires possédés par un joueur (comptage direct de l'état public `territories`).
static func territory_count(territories: Dictionary, pid: int) -> int:
	var n := 0
	for tid in territories:
		var t = territories[tid]
		if typeof(t) == TYPE_DICTIONARY:
			var o = t.get("owner_id")
			if o != null and int(o) == pid:
				n += 1
	return n

# Dégradé de santé du héros (E1) : interpolation continue rouge→or (ratio 0..0,5) puis
# or→vert (0,5..1) — lisible d'un coup d'œil, sans palier brutal.
static func pv_color(ratio: float) -> Color:
	var r := clampf(ratio, 0.0, 1.0)
	if r >= 0.5:
		return ACCENT_GOLD.lerp(PV_GREEN, (r - 0.5) * 2.0)
	return DANGER.lerp(ACCENT_GOLD, r * 2.0)

# Réduction de défense PB en pourcentage entier (0..30) — même conversion que l'inspecteur
# ennemi du HUD (round(pb×100)). Pur, testé (pattern G4) : sert les vitals de la carte roster.
static func _pb_percent(pb: float) -> int:
	return int(round(clampf(pb, 0.0, 1.0) * 100.0))

# Auto-vérification debug (pattern G4 §8.63) : tri conforme à turn_order + comptes de
# territoires exacts sur un état STUB. Build debug uniquement, une fois par session.
static func _self_check() -> void:
	_self_checked = true
	var players := {"11": {}, "7": {}, "-2": {}}
	# 7 joue avant 11 (rotation) ; -2 (bot) hors rotation → relégué en fin, tri par id.
	var order := sorted_pids(players, [7.0, 11.0])
	assert(order == [7, 11, -2])
	# Rotation legacy vide → repli tri par id croissant.
	assert(sorted_pids(players, []) == [-2, 7, 11])
	var terrs := {
		"alaska": {"owner_id": 7.0, "garrison": 3},
		"quebec": {"owner_id": 7, "garrison": 1},
		"peru": {"owner_id": 11, "garrison": 5},
		"ural": {"owner_id": null, "garrison": 0},
	}
	assert(territory_count(terrs, 7) == 2)
	assert(territory_count(terrs, 11) == 1)
	assert(territory_count(terrs, -2) == 0)
	# Formatage PB (réduction de défense) en pourcentage entier — vitals de la carte roster.
	assert(_pb_percent(0.30) == 30)
	assert(_pb_percent(0.0) == 0)
	assert(_pb_percent(0.07) == 7)

# Accès de test (script maison tools/test_e1_roster.gd) : nombre de lignes affichées.
func debug_row_count() -> int:
	return _rows_box.get_child_count() if _rows_box != null else 0

# =========================================================
# Construction des widgets
# =========================================================

func _rebuild_order_band(order: Array) -> void:
	for c in _order_band.get_children():
		c.queue_free()
	for i in range(order.size()):
		var pid := int(order[i])
		if i > 0:
			var sep := Label.new()
			sep.text = "▸"
			sep.add_theme_font_size_override("font_size", 10)
			sep.add_theme_color_override("font_color", MUTED)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_order_band.add_child(sep)
		var chip := PlayerChipScene.instantiate()
		_order_band.add_child(chip)
		chip.setup(pid, true)
		# Joueur courant en surbrillance, les autres en sourdine (l'ordre reste lisible).
		var is_current: bool = GameState.stage == "playing" \
			and int(GameState.current_player_id) == pid
		chip.modulate = Color(1, 1, 1, 1.0) if is_current else Color(1, 1, 1, 0.5)

func _rebuild_rows(order: Array) -> void:
	for c in _rows_box.get_children():
		c.queue_free()
	for pid in order:
		_rows_box.add_child(_make_row(int(pid)))

# Une carte de belligérant sur DEUX lignes (E-visuel) — « qui est qui » d'un coup d'œil :
#   Ligne 1 (identité) : [état][chip qui s'étire][🏴 territoires][🃏 cartes][NIV n]
#   Ligne 2 (vitals héros, indentée) : [barre PV][PV n/max][🗡 PA n][🛡 PB p%][PP ±n]
# Les compteurs restent sur la ligne d'identité (compacts) pour laisser toute la largeur aux
# vitals ÉTIQUETÉS de la ligne 2 (anti « soupe d'emojis » — chaque valeur porte un libellé).
# TUTO: emplacement candidat pour un tooltip d'onboarding « lisez ici l'état de chaque ennemi ».
func _make_row(pid: int) -> Control:
	var p = GameState.players.get(str(pid), {})
	if typeof(p) != TYPE_DICTIONARY:
		p = {}
	var hero: Dictionary = GameState.hero_of(pid)
	var pv_max := int(hero.get("pv_max", 0))
	var pv := int(hero.get("pv_current", 0))
	var is_current: bool = GameState.stage == "playing" \
		and int(GameState.current_player_id) == pid
	# 🏳 abandon (Fallen Empire §8.20) ; 💀 héros abattu (permadeath §8.61) OU joueur éliminé.
	var abandoned: bool = not bool(p.get("is_active", true))
	var down: bool = bool(hero.get("is_dead", false)) \
		or str(p.get("status", "alive")) == "eliminated"

	var row := PanelContainer.new()
	# STOP : la ligne CONSOMME son clic (aucune fuite vers le plateau derrière le panneau).
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = tr("ROSTER_ROW_TOOLTIP")
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(0)
	style.set_content_margin_all(3)
	if is_current:
		# Ligne du joueur courant surlignée (léger fond + liseré cyan).
		style.bg_color = Color(ACCENT_CYAN, 0.10)
		style.border_color = Color(ACCENT_CYAN, 0.5)
		style.set_border_width_all(1)
	else:
		style.bg_color = Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("panel", style)
	row.gui_input.connect(_on_row_input.bind(pid))
	if down or abandoned:
		row.modulate = Color(1, 1, 1, ROW_DIMMED_ALPHA)

	# Carte = 2 lignes empilées (identité au-dessus, vitals dessous).
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	row.add_child(card)

	# ---------- Ligne 1 : identité ----------
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 5)
	card.add_child(line1)

	# Icône d'état : ▶ (tour courant, pulsé), 💀 (héros mort / éliminé), 🏳 (abandon).
	var marker := Label.new()
	marker.custom_minimum_size = Vector2(16, 0)
	marker.add_theme_font_size_override("font_size", 12)
	marker.mouse_filter = Control.MOUSE_FILTER_PASS
	if abandoned:
		marker.text = "⚐"
	elif down:
		marker.text = "☠"
		marker.add_theme_color_override("font_color", DANGER)
	elif is_current:
		marker.text = "▶"
		marker.add_theme_color_override("font_color", ACCENT_GOLD)
		# Léger pulse du chevron de tour (Tween lié au nœud → tué au rebuild suivant).
		var tw := marker.create_tween().set_loops()
		tw.tween_property(marker, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(marker, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	line1.add_child(marker)

	# Identité (brique unique E1) — s'étire, les compteurs restent alignés à droite.
	var chip := PlayerChipScene.instantiate()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line1.add_child(chip)
	chip.setup(pid, false)

	# Compteurs publics compacts : territoires possédés + cartes en main (len — public).
	line1.add_child(_counter_label("⚑%d" % territory_count(GameState.territories, pid),
		Color("eef3f7"), tr("ROSTER_TERR_TOOLTIP")))
	var cards_n := 0
	var hand = p.get("cards_in_hand", [])
	if typeof(hand) == TYPE_ARRAY:
		cards_n = (hand as Array).size()
	line1.add_child(_counter_label("❖%d" % cards_n, MUTED, tr("ROSTER_CARDS_TOOLTIP")))

	# Niveau du héros (masqué si héros non initialisé — état pré-RPG, aucun « NIV » fantôme).
	var lvl := Label.new()
	lvl.add_theme_font_size_override("font_size", 10)
	lvl.add_theme_color_override("font_color", ACCENT_CYAN)
	lvl.add_theme_font_override("font", _mono_font())
	lvl.mouse_filter = Control.MOUSE_FILTER_PASS
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if pv_max > 0:
		lvl.text = tr("ROSTER_LEVEL") % int(hero.get("level", 1))
	line1.add_child(lvl)

	# ---------- Ligne 2 : vitals du héros ----------
	# Masquée proprement si le héros n'est pas initialisé (état pré-RPG) — aucun « 0/0 » fantôme.
	if pv_max > 0:
		card.add_child(_make_vitals_line(hero, pv, pv_max, down))

	return row

# Ligne 2 de la carte : état COMPLET du héros, aéré et ÉTIQUETÉ (barre PV élargie + PV chiffrés +
# PA/PB/PP libellés). « ABATTU » (DANGER, barre vide) si le héros est mort. Tous les labels en
# MOUSE_FILTER_PASS → le clic de la ligne ouvre toujours l'inspecteur (signal player_clicked).
func _make_vitals_line(hero: Dictionary, pv: int, pv_max: int, down: bool) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)

	# Légère indentation sous la pastille d'identité (lecture hiérarchique, aération §2).
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(14, 0)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(indent)

	# Barre PV élargie (dégradé vert→or→rouge, vide si abattu).
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(48, 9)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.max_value = float(pv_max)
	if down:
		bar.value = 0.0
		bar.tooltip_text = tr("ROSTER_HERO_DOWN")
	else:
		bar.value = float(pv)
		_tint_progress(bar, pv_color(float(pv) / float(pv_max)))
		bar.tooltip_text = tr("ROSTER_PV_TOOLTIP") % [pv, pv_max]
	line.add_child(bar)

	if down:
		# Héros abattu : « ABATTU » en rouge — le reste des vitals n'a plus de sens.
		var dead := _vital_label(tr("ROSTER_PV_DOWN"), DANGER, tr("ROSTER_HERO_DOWN"))
		dead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(dead)
		return line

	# PV chiffrés (visibles, plus seulement en tooltip).
	line.add_child(_vital_label(tr("ROSTER_PV_INLINE") % [pv, pv_max], Color("eef3f7"),
		tr("ROSTER_PV_TOOLTIP") % [pv, pv_max]))
	# 🗡 PA (points d'attaque) — or.
	line.add_child(_vital_label(tr("ROSTER_PA_LABEL") % int(hero.get("pa", 0)),
		ACCENT_GOLD, tr("CHAR_STAT_PA_DESC")))
	# 🛡 PB (réduction de dégâts en %) — cyan.
	line.add_child(_vital_label(tr("ROSTER_PB_LABEL") % _pb_percent(float(hero.get("pb", 0.0))),
		ACCENT_CYAN, tr("ROSTER_PB_TOOLTIP")))
	# PP (momentum de combat) — discret, muet, poussé à droite.
	var pp := _vital_label(tr("ROSTER_PP_LABEL") % int(hero.get("pp_current", 0)),
		MUTED, tr("CHAR_STAT_PP_DESC"))
	pp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(pp)
	return line

# Compteur mono compact de la ligne d'identité (territoires / cartes) — PASS pour laisser le clic
# de ligne ouvrir l'inspecteur, tooltip explicatif.
func _counter_label(text: String, col: Color, tip: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", _mono_font())
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

# Étiquette d'un vital de la ligne 2 (mono, PASS + tooltip) — brique unique pour PV/PA/PB/PP.
func _vital_label(text: String, col: Color, tip: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_override("font", _mono_font())
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _on_row_input(event: InputEvent, pid: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		AudioManager.play_sfx("click")
		player_clicked.emit(pid)

# Police monospace des compteurs (« Share Tech Mono » si installée, replis Windows) — même
# approche SystemFont que territory_badge.tscn (aucun asset fichier requis).
static var _mono: SystemFont = null

static func _mono_font() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(
			["Share Tech Mono", "Consolas", "Lucida Console", "Courier New"])
	return _mono

# Recolore le remplissage d'une ProgressBar — même helper que hud._tint_progress (E1 : réutilisé
# tel quel, coins droits charte §2).
static func _tint_progress(bar: ProgressBar, col: Color) -> void:
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("fill", fill)
