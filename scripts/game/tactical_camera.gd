extends Camera2D

# CAMÉRA TACTIQUE — vit dans le SubViewport `MapContent` (CONTEXTE.md §8.17).
# Vue par défaut : centrée sur la carte, dézoomée pour voir 100 % du plateau (board_bg).
# Vue combat : `focus_on_combat()` fait un travelling vers le point médian des deux
# belligérants avec un zoom 1.5x. AUCUNE logique de jeu ici (Règle d'Or §6.1) :
# c'est main.gd qui décide QUAND focaliser et quand revenir à la vue d'ensemble.

# Espace de conception du plateau ÉLARGI au format 16:9 (§8.50) : la carte utile
# (2200×1530, §8.18) est centrée et le shader `tactical_map` prolonge la MER dans
# les bandes latérales (260 px de chaque côté) → 2720×1530 = 16/9 exact, l'écran est
# rempli sans bande noire ni rognage. `BOARD_CENTER` = centre réel du cadre élargi
# (les territoires n'ont PAS bougé : la zone centrale reste à sa place d'origine).
const BOARD_SIZE := Vector2(2720, 1530)
const BOARD_CENTER := Vector2(1108, 757)
# Multiplicateur appliqué au zoom "plein plateau" pendant un combat (zoom 1.5x).
const COMBAT_ZOOM_FACTOR := 1.5
# Durée du travelling (glissement + zoom).
const FOCUS_DURATION := 0.8

var _tween: Tween

# --- Cadre de référence (lot G5 §8.71 — carte réduite) ---
# La vue « plein plateau » (et ses bornes de pan/zoom) suit CE rect : plateau ENTIER par défaut
# (carte classique, comportement historique intact) ; recadré sur le rect englobant des
# territoires ACTIFS quand une sous-carte est jouée (posé par main.gd depuis board.gd).
var _board_rect := Rect2(BOARD_CENTER - BOARD_SIZE / 2.0, BOARD_SIZE)
# Marge de respiration autour des territoires actifs (px monde).
const ACTIVE_RECT_PADDING := 90.0

func set_board_rect(rect: Rect2) -> void:
	# Rect vide → retour au cadre plein plateau (carte complète).
	var target := Rect2(BOARD_CENTER - BOARD_SIZE / 2.0, BOARD_SIZE)
	if rect.size != Vector2.ZERO:
		target = rect.grow(ACTIVE_RECT_PADDING)
	if _board_rect.is_equal_approx(target):
		return
	_board_rect = target
	if not free_navigation:
		_fit_full_board()

# --- Navigation LIBRE (lot G3 §8.70 — mode observateur) ---
# Activée pour un joueur ÉLIMINÉ (main.gd) : pan au DRAG (clic droit ou molette enfoncée) +
# zoom à la MOLETTE, bornés au plateau. Désactivée par défaut (vue pilotée : plein plateau /
# travelling de combat, comportement historique inchangé).
var free_navigation := false
const FREE_ZOOM_MAX_FACTOR := 4.0   # zoom max = 4× la vue plein plateau.
const FREE_ZOOM_STEP := 1.12        # facteur par cran de molette.
var _dragging := false

func set_free_navigation(enabled: bool) -> void:
	free_navigation = enabled
	if not enabled:
		_fit_full_board()

func _unhandled_input(event: InputEvent) -> void:
	if not free_navigation:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_free_zoom(FREE_ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_free_zoom(1.0 / FREE_ZOOM_STEP)
	elif event is InputEventMouseMotion and _dragging:
		_kill_tween()
		# Déplacement en espace MONDE (relative est en pixels écran → diviser par le zoom).
		position -= event.relative / zoom.x
		_clamp_to_board()

func _apply_free_zoom(factor: float) -> void:
	_kill_tween()
	var base := _full_board_zoom().x
	var z: float = clampf(zoom.x * factor, base, base * FREE_ZOOM_MAX_FACTOR)
	zoom = Vector2(z, z)
	_clamp_to_board()

# Garde la caméra dans le cadre COURANT (plateau entier, ou sous-carte active — G5).
func _clamp_to_board() -> void:
	var half := Vector2(get_viewport().get_visible_rect().size) / (2.0 * zoom.x)
	var top_left := _board_rect.position
	var bottom_right := _board_rect.end
	position.x = clampf(position.x, top_left.x + half.x, maxf(top_left.x + half.x, bottom_right.x - half.x))
	position.y = clampf(position.y, top_left.y + half.y, maxf(top_left.y + half.y, bottom_right.y - half.y))

func _ready() -> void:
	# SubViewportContainer.stretch = true redimensionne le SubViewport à chaque
	# resize de fenêtre → on recadre la vue plein plateau à chaque changement.
	get_viewport().size_changed.connect(_fit_full_board)
	_fit_full_board()

# Le plus grand zoom qui fait tenir 100 % du CADRE COURANT dans le viewport (G5 : le cadre
# suit la sous-carte active). (En Godot 4, zoom < 1 = dézoom : on voit PLUS que le viewport.)
func _full_board_zoom() -> Vector2:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	if vp.x <= 0.0 or vp.y <= 0.0 or _board_rect.size.x <= 0.0 or _board_rect.size.y <= 0.0:
		return Vector2.ONE
	var z := minf(vp.x / _board_rect.size.x, vp.y / _board_rect.size.y)
	return Vector2(z, z)

# Vue par défaut : cadre courant entièrement visible, caméra à son centre (sans animation).
func _fit_full_board() -> void:
	_kill_tween()
	position = _board_rect.get_center()
	zoom = _full_board_zoom()

# Travelling de combat : calcule le point central entre les deux positions, puis glisse
# la caméra vers ce point en zoomant (1.5x la vue plein plateau) en 0.8 s (Sine / Out).
func focus_on_combat(pos_a: Vector2, pos_b: Vector2) -> void:
	var center := (pos_a + pos_b) / 2.0
	var target_zoom := _full_board_zoom() * COMBAT_ZOOM_FACTOR
	_kill_tween()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_parallel(true)
	_tween.tween_property(self, "position", center, FOCUS_DURATION)
	_tween.tween_property(self, "zoom", target_zoom, FOCUS_DURATION)

# Retour fluide à la vue d'ensemble (même cinétique que le focus ; cadre courant — G5).
func reset_view() -> void:
	_kill_tween()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_parallel(true)
	_tween.tween_property(self, "position", _board_rect.get_center(), FOCUS_DURATION)
	_tween.tween_property(self, "zoom", _full_board_zoom(), FOCUS_DURATION)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
