extends CanvasLayer
##
## TransitionManager (autoload) — transitions de scène en fondu « Warzone Command » (R6).
##
## Remplace les `change_scene_to_file` « secs » par un fondu gunmetal : un ColorRect plein écran
## en overlay (CanvasLayer haut) passe opaque, la scène change, puis se ré-efface. L'autoload
## SURVIT au changement de scène → l'overlay reste au-dessus de tout pendant la bascule.
##
## Règle d'Or §6.1 : aucune logique de jeu — pur service de présentation, appelable partout :
##     TransitionManager.change_scene("res://scenes/ui/auth_screen.tscn")
##
## Une scène lancée DIRECTEMENT (sans transition entrante, ex. la 1re scène) peut appeler
##     TransitionManager.fade_in_only()
## dans son _ready pour un dévoilé propre.

# Gunmetal #0F1318 (charte §2) — couleur de couverture au pic du fondu.
const FADE_RGB := Color(0.058824, 0.07451, 0.094118)
const FADE_OUT_DURATION := 0.35  # vers l'écran couvert (avant change_scene)
const FADE_IN_DURATION := 0.45   # dévoile la nouvelle scène

var _rect: ColorRect
var _busy := false


func _ready() -> void:
	layer = 128  # au-dessus de tout (HUD, menus, splash…)
	_rect = ColorRect.new()
	_rect.color = Color(FADE_RGB, 0.0)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # jamais bloquant quand transparent
	add_child(_rect)


# Fondu sortant → change de scène → fondu entrant. Garde anti-spam (_busy) : un appel pendant
# une transition en cours est ignoré (évite d'empiler deux bascules).
func change_scene(path: String) -> void:
	if _busy:
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # bloque les clics pendant la bascule

	var t := create_tween()
	t.tween_property(_rect, "color:a", 1.0, FADE_OUT_DURATION).set_trans(Tween.TRANS_SINE)
	await t.finished

	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_warning("TransitionManager: échec change_scene_to_file %s (err %d)" % [path, err])

	# Laisse une frame à la nouvelle scène pour s'instancier avant de dévoiler.
	await get_tree().process_frame

	var t2 := create_tween()
	t2.tween_property(_rect, "color:a", 0.0, FADE_IN_DURATION).set_trans(Tween.TRANS_SINE)
	await t2.finished

	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


# Dévoilé d'ouverture seul (overlay opaque → transparent), sans changer de scène.
func fade_in_only() -> void:
	_rect.color = Color(FADE_RGB, 1.0)
	var t := create_tween()
	t.tween_property(_rect, "color:a", 0.0, FADE_IN_DURATION).set_trans(Tween.TRANS_SINE)
