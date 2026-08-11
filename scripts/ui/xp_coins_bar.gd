extends PanelContainer

# JAUGE XP + COMPTEUR COINS (sprint Économie globale §8.47) — composant RÉUTILISABLE de la charte
# « Warzone Command » (§2). Affiche le niveau du compte, une barre d'XP à remplissage CYAN tactique
# (#36C5D9) et un compteur de Coins en OR (#E0B249) avec une icône hexagonale stylisée.
#
# Construit 100 % PAR CODE (aucun nœud de scène requis) — même pattern que le bouton « CONFIRMER »
# et la zone de chat du HUD → il suffit d'`add_child()` ce composant dans le Menu Principal, le HUD
# d'arène ou le Rapport Post-Opération. View PURE (Règle d'Or §6.1) : aucune logique réseau ici.
#
# Deux usages :
#   • PERSISTANT (menu / HUD) : set_profile(level, current_xp, xp_to_next, coins) — affichage direct.
#   • POST-OP (fin de partie) : await play_match_result(rewards) — décompte de la barre d'XP qui se
#     remplit niveau par niveau, lueur « rim-light » dorée à chaque palier de 10 niveaux (= 100 Coins).

# Émis au clic gauche LORSQUE le panneau est rendu interactif via set_interactive(true) — p.ex.
# dans le Menu Principal pour ouvrir le mini-profil (§8.58). View PURE (§6.1) : le composant signale
# l'INTENTION, l'écran hôte décide de l'action (navigation, etc.) — la jauge ne navigue jamais.
signal profile_widget_clicked

const ACCENT_CYAN := Color("36c5d9")
const ACCENT_GOLD := Color("e0b249")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.9)
const TEXT_PRIMARY := Color("eef3f7")
const TEXT_MUTED := Color("8a97a5")

# Mêmes constantes que la courbe serveur (api/game/rewards.py) — MIROIR pour animer les wraps de
# niveau côté client. ⚠️ À garder synchronisé avec le backend (Phase 1 : 200*niveau ; Phase 2 : 4000).
const PHASE1_LEVEL_CAP := 20
const PHASE1_XP_PER_LEVEL := 200
const PHASE2_XP_FLAT := 4000
const COINS_LEVEL_MILESTONE := 10

# Durées d'animation (Post-Op).
const FILL_TIME_FULL := 0.45     # remplissage d'un niveau plein.
const FILL_TIME_PARTIAL := 0.6   # remplissage du dernier palier partiel.

var _level: int = 1
var _coins: int = 0

var _level_label: Label
var _xp_bar: ProgressBar
var _xp_overlay: Label
var _coins_label: Label
var _coin_icon: Control
var _xp_tween: Tween

# Interactivité OPTIONNELLE (opt-in via set_interactive) : un Button transparent plein-cadre capte
# le clic sur tout le panneau (même pattern « bouton superposé » que les cartes de mode du menu) et
# le survol éclaircit le liseré. Inactif par défaut → en HUD / Post-Op la jauge reste passive.
var _interactive: bool = false
var _hit_button: Button = null
var _panel_style: StyleBoxFlat
var _panel_style_hover: StyleBoxFlat


func _ready() -> void:
	_build()
	set_profile(_level, 0, _xp_required_for_level(_level), _coins)


# =========================================================
# INTERACTIVITÉ OPTIONNELLE (Menu Principal — clic → mini-profil §8.58)
# =========================================================
# Rend la jauge cliquable (OPT-IN). Un Button transparent plein-cadre — ajouté EN DERNIER pour
# rester au-dessus du contenu, donc capter le clic quel que soit le mouse_filter des enfants —
# émet `profile_widget_clicked` au clic gauche ; le curseur passe en main et le survol éclaircit le
# liseré. À appeler APRÈS l'ajout à l'arbre (le contenu existe alors déjà). Idempotent.
func set_interactive(enabled: bool) -> void:
	_interactive = enabled
	if enabled and _hit_button == null:
		_hit_button = Button.new()
		_hit_button.name = "HitButton"
		_hit_button.flat = true
		_hit_button.focus_mode = Control.FOCUS_NONE
		_hit_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		_hit_button.add_theme_stylebox_override("normal", empty)
		_hit_button.add_theme_stylebox_override("hover", empty)
		_hit_button.add_theme_stylebox_override("pressed", empty)
		_hit_button.add_theme_stylebox_override("focus", empty)
		_hit_button.pressed.connect(func() -> void: profile_widget_clicked.emit())
		_hit_button.mouse_entered.connect(_on_hit_hover.bind(true))
		_hit_button.mouse_exited.connect(_on_hit_hover.bind(false))
		add_child(_hit_button)
	if _hit_button:
		# Garantit que le capteur reste le DERNIER enfant (au-dessus du contenu pour l'input).
		move_child(_hit_button, get_child_count() - 1)
		_hit_button.visible = enabled
		_hit_button.disabled = not enabled
	if not enabled:
		_on_hit_hover(false)

# Survol du capteur → bascule le stylebox du panneau (liseré vif vs normal). No-op avant _build.
func _on_hit_hover(hovering: bool) -> void:
	if _panel_style == null:
		return
	add_theme_stylebox_override("panel", _panel_style_hover if (hovering and _interactive) else _panel_style)


# Icône de Coin stylisée (hexagone OR à liseré CYAN + chevron central) — ADN angulaire Warzone.
class CoinIcon extends Control:
	var fill := Color("e0b249")
	var rim := Color("36c5d9")
	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
	func _draw() -> void:
		var c := size * 0.5
		var radius := minf(size.x, size.y) * 0.46
		var pts := PackedVector2Array()
		for i in range(6):
			var a := deg_to_rad(60.0 * i - 90.0)
			pts.append(c + Vector2(cos(a), sin(a)) * radius)
		draw_colored_polygon(pts, fill)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, rim, 1.5, true)
		# Chevron « ❯ » gravé au centre (signature de charte).
		var dark := Color("0f1318")
		draw_line(c + Vector2(-radius * 0.28, radius * 0.26), c + Vector2(0.0, -radius * 0.34), dark, 1.6, true)
		draw_line(c + Vector2(radius * 0.28, radius * 0.26), c + Vector2(0.0, -radius * 0.34), dark, 1.6, true)


func _build() -> void:
	# Panneau gunmetal translucide à fin liseré cyan (glassmorphism militaire §2).
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = GUNMETAL
	pstyle.border_color = Color(ACCENT_CYAN, 0.35)
	pstyle.set_border_width_all(1)
	pstyle.set_corner_radius_all(0)
	pstyle.set_content_margin_all(8)
	_panel_style = pstyle
	# Variante de SURVOL (révélée quand la jauge est interactive) : liseré cyan plus vif + légère
	# lueur → signale la cliquabilité sans casser le glassmorphism militaire (charte §2).
	_panel_style_hover = pstyle.duplicate() as StyleBoxFlat
	_panel_style_hover.border_color = Color(ACCENT_CYAN, 0.9)
	_panel_style_hover.shadow_color = Color(ACCENT_CYAN, 0.35)
	_panel_style_hover.shadow_size = 6
	add_theme_stylebox_override("panel", pstyle)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	# --- Badge de niveau « LV n » (cyan) ---
	_level_label = Label.new()
	_level_label.add_theme_color_override("font_color", ACCENT_CYAN)
	_level_label.add_theme_font_size_override("font_size", 18)
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_level_label)

	# --- Barre d'XP (remplissage cyan) avec texte superposé « xp / xp_max » ---
	var xp_wrap := Control.new()
	xp_wrap.custom_minimum_size = Vector2(170, 16)
	xp_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(xp_wrap)

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.min_value = 0.0
	_xp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.05, 0.065, 0.95)
	bar_bg.border_color = Color(ACCENT_CYAN, 0.3)
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(0)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = ACCENT_CYAN
	bar_fg.set_corner_radius_all(0)
	_xp_bar.add_theme_stylebox_override("background", bar_bg)
	_xp_bar.add_theme_stylebox_override("fill", bar_fg)
	xp_wrap.add_child(_xp_bar)

	_xp_overlay = Label.new()
	_xp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_xp_overlay.add_theme_color_override("font_color", TEXT_PRIMARY)
	_xp_overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_xp_overlay.add_theme_constant_override("outline_size", 3)
	_xp_overlay.add_theme_font_size_override("font_size", 11)
	_xp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_wrap.add_child(_xp_overlay)

	# --- Compteur de Coins (or + icône hexagonale) ---
	_coin_icon = CoinIcon.new()
	row.add_child(_coin_icon)

	_coins_label = Label.new()
	_coins_label.add_theme_color_override("font_color", ACCENT_GOLD)
	_coins_label.add_theme_font_size_override("font_size", 16)
	_coins_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_coins_label)


# =========================================================
# API PERSISTANTE (Menu / HUD)
# =========================================================

# Affichage direct depuis le profil (/auth/me → player_level/current_xp/xp_to_next_level/coins_balance).
func set_profile(level: int, current_xp: int, xp_to_next: int, coins: int) -> void:
	_level = maxi(1, level)
	_coins = maxi(0, coins)
	var maxv := current_xp + maxi(0, xp_to_next)
	set_level(_level)
	set_xp(float(current_xp), float(maxv))
	set_coins(_coins)

func set_level(level: int) -> void:
	_level = maxi(1, level)
	if _level_label:
		_level_label.text = "LV %d" % _level

func set_xp(xp: float, xp_max: float) -> void:
	if _xp_bar == null:
		return
	_xp_bar.max_value = maxf(1.0, xp_max)
	_xp_bar.value = clampf(xp, 0.0, _xp_bar.max_value)
	if _xp_overlay:
		_xp_overlay.text = "%d / %d XP" % [int(round(xp)), int(round(_xp_bar.max_value))]

func set_coins(coins: int) -> void:
	_coins = maxi(0, coins)
	if _coins_label:
		_coins_label.text = str(_coins)


# =========================================================
# COMPTEUR DE COINS ANIMÉ (§8.122, LOT F) — décompte + flash or
# =========================================================
# Durée du DÉCOMPTE après un achat confirmé. Volontairement courte : au-delà, le joueur a le temps
# de cliquer ailleurs et le solde « se termine » sur un autre écran.
const COINS_COUNT_TIME := 0.6

var _coins_tween: Tween = null

# Fait DÉFILER le solde jusqu'à `target` (dépense confirmée en boutique), puis lueur dorée. Le
# décompte est ce qui rend la dépense PALPABLE — un solde qui saute d'un chiffre à l'autre ne
# raconte rien. Réutilise `_flash_coins()`, la lueur déjà écrite pour les paliers du Rapport
# Post-Op : une seule mise en scène de « quelque chose est arrivé aux Coins » dans tout le jeu.
func animate_coins_to(target: int, duration: float = COINS_COUNT_TIME) -> void:
	target = maxi(0, target)
	if _coins_tween and _coins_tween.is_valid():
		_coins_tween.kill()
	if _coins_label == null or target == _coins or duration <= 0.0:
		set_coins(target)
		_flash_coins()
		return
	_coins_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_coins_tween.tween_method(func(v: float) -> void: set_coins(int(round(v))),
		float(_coins), float(target), duration)
	_coins_tween.tween_callback(_flash_coins)


# Lueur dorée seule (sans changement de solde) — exposée pour les appelants qui ont déjà écrit la
# valeur (ex. rafraîchissement d'inventaire arrivé avant l'animation).
func flash_coins() -> void:
	_flash_coins()


# =========================================================
# API ANIMÉE (Rapport Post-Opération)
# =========================================================

# Rejoue les gains d'un match : la barre d'XP se remplit niveau par niveau depuis l'état d'AVANT le
# match (reconstruit à partir de `rewards`), avec une lueur « rim-light » dorée à chaque palier de 10
# niveaux franchi (= 100 Coins). `rewards` = entrée match_rewards du joueur local (game_over §8.47) :
# { new_level, current_xp, xp_to_next_level, xp_earned, levels_gained, coins_earned, ... }.
# Coroutine : à utiliser avec `await` (l'appelant peut enchaîner d'autres animations).
func play_match_result(rewards: Dictionary) -> void:
	var coins_earned := int(rewards.get("coins_earned", 0))
	var target_level := maxi(1, int(rewards.get("new_level", _level)))
	var target_xp := int(rewards.get("current_xp", 0))

	# État d'AVANT le match (rembobinage exact depuis l'état final + l'XP gagnée).
	var start := _compute_start(rewards)
	var level := int(start.level)
	var xp := float(start.xp)

	set_level(level)
	set_xp(xp, float(_xp_required_for_level(level)))
	set_coins(0)  # en Post-Op, le compteur affiche les Coins GAGNÉS ce match (+N), pas le solde total.

	# Remplissage niveau par niveau jusqu'au niveau cible.
	while level < target_level:
		var maxv := float(_xp_required_for_level(level))
		await _animate_bar(maxv, maxv, FILL_TIME_FULL)
		level += 1
		set_level(level)
		set_xp(0.0, float(_xp_required_for_level(level)))
		_pulse_levelup()
		# Palier de 10 niveaux atteint → 100 Coins : lueur dorée + incrément du compteur.
		if level % COINS_LEVEL_MILESTONE == 0:
			set_coins(_coins + 100)
			_flash_coins()

	# Dernier palier partiel jusqu'à l'XP finale.
	await _animate_bar(float(target_xp), float(_xp_required_for_level(target_level)), FILL_TIME_PARTIAL)

	# Garantit le total exact de Coins gagnés (si le calcul par paliers a divergé d'un cas limite).
	if _coins != coins_earned:
		set_coins(coins_earned)
		if coins_earned > 0:
			_flash_coins()

# Reconstruit l'état (niveau, xp-dans-le-niveau) d'AVANT le match en « rembobinant » l'XP gagnée
# depuis l'état final. Borné par levels_gained (+2 de garde) → jamais de boucle infinie.
func _compute_start(rewards: Dictionary) -> Dictionary:
	var level := maxi(1, int(rewards.get("new_level", _level)))
	var xp := int(rewards.get("current_xp", 0))
	var to_undo := int(rewards.get("xp_earned", 0))
	var guard := int(rewards.get("levels_gained", 0)) + 2
	while to_undo > 0 and guard > 0:
		guard -= 1
		if xp >= to_undo:
			xp -= to_undo
			to_undo = 0
		elif level > 1:
			to_undo -= xp
			level -= 1
			xp = _xp_required_for_level(level)  # la barre était pleine juste avant ce passage de niveau.
		else:
			xp = maxi(0, xp - to_undo)  # plancher au niveau 1.
			to_undo = 0
	return {"level": level, "xp": xp}

# Anime la valeur de la barre vers `target_value` (max ajusté d'abord) sur `duration` s.
func _animate_bar(target_value: float, xp_max: float, duration: float) -> void:
	if _xp_bar == null:
		return
	_xp_bar.max_value = maxf(1.0, xp_max)
	if _xp_tween and _xp_tween.is_valid():
		_xp_tween.kill()
	_xp_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_xp_tween.tween_method(_set_bar_value, _xp_bar.value, clampf(target_value, 0.0, _xp_bar.max_value), duration)
	await _xp_tween.finished

func _set_bar_value(v: float) -> void:
	if _xp_bar == null:
		return
	_xp_bar.value = v
	if _xp_overlay:
		_xp_overlay.text = "%d / %d XP" % [int(round(v)), int(round(_xp_bar.max_value))]

# Pulse cyan bref sur le badge de niveau (montée de niveau).
func _pulse_levelup() -> void:
	if _level_label == null:
		return
	var t := create_tween()
	_level_label.scale = Vector2(1.35, 1.35)
	_level_label.pivot_offset = _level_label.size * 0.5
	t.tween_property(_level_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Lueur « rim-light » dorée sur le compteur de Coins (palier de 100 Coins atteint, §4).
func _flash_coins() -> void:
	for node in [_coins_label, _coin_icon]:
		if node == null:
			continue
		var t := create_tween()
		node.modulate = Color(1.8, 1.55, 1.0)  # surbrillance dorée
		t.tween_property(node, "modulate", Color.WHITE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# ⚠️ `reduced_motion` — LE REBOND DE L'ICÔNE EST DU MOUVEMENT, LA LUEUR N'EN EST PAS.
	# La règle du dépôt est « couleur seule, pas de mouvement » : on garde donc la surbrillance
	# dorée ci-dessus (l'information « il s'est passé quelque chose » reste intégralement lisible)
	# et on retire le seul élément qui bouge. Garde AJOUTÉE au chantier CORRECTIFS ÉCONOMIQUES :
	# cette lueur devient le geste partagé de la mise en valeur du Pass (jauge du hub, §7.4), et
	# une animation qu'on généralise doit d'abord être conforme là où elle existait déjà.
	if _coin_icon and not bool(SettingsManager.get_comfort("reduced_motion")):
		var s := create_tween()
		_coin_icon.pivot_offset = _coin_icon.size * 0.5
		_coin_icon.scale = Vector2(1.4, 1.4)
		s.tween_property(_coin_icon, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Miroir EXACT de api/game/rewards.xp_required_for_level (Phase 1 : 200*niveau ; Phase 2 : 4000).
func _xp_required_for_level(level: int) -> int:
	level = maxi(1, level)
	return PHASE1_XP_PER_LEVEL * level if level <= PHASE1_LEVEL_CAP else PHASE2_XP_FLAT
