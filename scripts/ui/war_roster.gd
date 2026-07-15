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
# pattern que _refresh_cards / set_factions_intel (queue_free + rebuild).
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

# Une ligne de belligérant : [état][chip][NIV][barre PV][territoires][cartes].
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

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	row.add_child(line)

	# Icône d'état : ▶ (tour courant, pulsé), 💀 (héros mort / éliminé), 🏳 (abandon).
	var marker := Label.new()
	marker.custom_minimum_size = Vector2(16, 0)
	marker.add_theme_font_size_override("font_size", 12)
	if abandoned:
		marker.text = "🏳"
	elif down:
		marker.text = "💀"
		marker.add_theme_color_override("font_color", DANGER)
	elif is_current:
		marker.text = "▶"
		marker.add_theme_color_override("font_color", ACCENT_GOLD)
		# Léger pulse du chevron de tour (Tween lié au nœud → tué au rebuild suivant).
		var tw := marker.create_tween().set_loops()
		tw.tween_property(marker, "modulate:a", 0.35, 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(marker, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	line.add_child(marker)

	# Identité (brique unique E1) — s'étire, les compteurs restent alignés à droite.
	var chip := PlayerChipScene.instantiate()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(chip)
	chip.setup(pid, false)

	# Niveau du héros (masqué si héros non initialisé — état pré-RPG, aucun « NIV » fantôme).
	var lvl := Label.new()
	lvl.add_theme_font_size_override("font_size", 10)
	lvl.add_theme_color_override("font_color", ACCENT_CYAN)
	lvl.add_theme_font_override("font", _mono_font())
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if pv_max > 0:
		lvl.text = tr("ROSTER_LEVEL") % int(hero.get("level", 1))
	line.add_child(lvl)

	# Mini-barre PV du héros (dégradé vert→or→rouge, vide si abattu, absente si pré-RPG).
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(42, 9)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	if pv_max > 0:
		bar.max_value = float(pv_max)
		if down:
			bar.value = 0.0
			bar.tooltip_text = tr("ROSTER_HERO_DOWN")
		else:
			bar.value = float(pv)
			_tint_progress(bar, pv_color(float(pv) / float(pv_max)))
			bar.tooltip_text = tr("ROSTER_PV_TOOLTIP") % [pv, pv_max]
	else:
		bar.visible = false
	line.add_child(bar)

	# Compteurs publics : territoires possédés + cartes en main (len(cards_in_hand) — public).
	var terr := Label.new()
	terr.text = "🏴%d" % territory_count(GameState.territories, pid)
	terr.add_theme_font_size_override("font_size", 11)
	terr.add_theme_color_override("font_color", Color("eef3f7"))
	terr.add_theme_font_override("font", _mono_font())
	terr.tooltip_text = tr("ROSTER_TERR_TOOLTIP")
	terr.mouse_filter = Control.MOUSE_FILTER_PASS
	terr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(terr)

	var cards_n := 0
	var hand = p.get("cards_in_hand", [])
	if typeof(hand) == TYPE_ARRAY:
		cards_n = (hand as Array).size()
	var cards := Label.new()
	cards.text = "🃏%d" % cards_n
	cards.add_theme_font_size_override("font_size", 11)
	cards.add_theme_color_override("font_color", MUTED)
	cards.add_theme_font_override("font", _mono_font())
	cards.tooltip_text = tr("ROSTER_CARDS_TOOLTIP")
	cards.mouse_filter = Control.MOUSE_FILTER_PASS
	cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(cards)

	return row

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
