extends VBoxContainer

# KILL FEED (E4 §8.76) — surimpression compacte des entrées MAJEURES du Journal de Guerre
# (conquête, héros abattu, territoire ravagé par la zone) : coin haut-droit HORS panneaux,
# 4 entrées max (la plus récente en tête), fondu de sortie après 6 s. Purement décoratif
# (mouse_filter IGNORE partout) — positionné par le HUD (à gauche du panneau latéral).

const MAX_ENTRIES := 4
const FADE_AFTER := 6.0
const FADE_TIME := 0.8

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)

# Pousse une entrée (BBCode déjà résolu — pseudos colorisés E1). Les plus anciennes au-delà de
# MAX_ENTRIES sont libérées immédiatement.
func push_entry(rich_text: String) -> void:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("normal_font_size", 15)
	line.append_text("[right]%s[/right]" % rich_text)
	add_child(line)
	move_child(line, 0)
	while get_child_count() > MAX_ENTRIES:
		var oldest := get_child(get_child_count() - 1)
		oldest.queue_free()
		remove_child(oldest)
	var tw := line.create_tween()
	tw.tween_interval(FADE_AFTER)
	tw.tween_property(line, "modulate:a", 0.0, FADE_TIME)
	tw.tween_callback(line.queue_free)
