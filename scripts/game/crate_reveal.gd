extends Control

# =========================================================================
# CAISSE DE RAVITAILLEMENT — « unboxing » (BATTLE ROYALE §8.125)
# =========================================================================
# Surcouche PLEIN ÉCRAN de 3 s, jouée quand l'équipe franchit un palier de 50 kills : la caisse
# s'ouvre en grand, la prime s'affiche, et la RÉPARTITION entre coéquipiers défile juste en dessous.
# 100 % procédurale (aucun asset), View PURE — on lui passe un contenu déjà résolu.
#
# ⚠️ La RÉPARTITION est le vrai sujet de cet écran, pas le total. Une caisse est une récompense
# d'ÉQUIPE : c'est de la voir se partager sous ses yeux — « +50 toi, +50 lui, +50 moi » — que naît
# le sentiment collectif. Un simple « +150 PV » aurait été un butin personnel de plus.
#
# ⚠️⚠️ NON BLOQUANTE (`mouse_filter = IGNORE`) : 3 s d'écran mort au milieu d'un tour seraient 3 s
# volées au joueur. Il peut continuer à lire le plateau derrière.

signal finished

const GOLD := Color("e0b249")
const ACCENT := Color("36c5d9")
const TEXT := Color("eef3f7")
const MUTED := Color("8a97a5")
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 0.94)

# Durées (s) — total 3,0 s, dans la borne « 3 ou 4 s max » demandée.
const PUNCH_IN := 0.35     # la caisse arrive en écrasant l'écran
const HOLD := 2.1          # lecture du contenu + répartition
const FADE_OUT := 0.55

var _font: SystemFont
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 190   # sous l'alarme de trahison (200), au-dessus du HUD.

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700


# `reward_id` = "hp" | "units" · `total` = montant de la caisse · `shares` = { pseudo : montant }
# (les ids sont DÉJÀ résolus en pseudos par l'appelant — la vue ne connaît pas les joueurs).
func play(reward_id: String, total: int, shares: Dictionary, kills: int = 0) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = GUNMETAL
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(3)
	sb.border_color = GOLD
	sb.shadow_color = Color(GOLD, 0.5)
	sb.shadow_size = 26
	sb.set_content_margin_all(34.0)
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	var eyebrow := Label.new()
	eyebrow.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	eyebrow.text = "☢  " + tr("BR_CRATE_TITLE")
	eyebrow.add_theme_font_override("font", _font)
	eyebrow.add_theme_font_size_override("font_size", 16)
	eyebrow.add_theme_color_override("font_color", ACCENT)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(eyebrow)

	var amount := Label.new()
	amount.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	amount.text = tr("BR_CRATE_HP" if reward_id == "hp" else "BR_CRATE_UNITS") % int(total)
	amount.add_theme_font_override("font", _font)
	amount.add_theme_font_size_override("font_size", 56)
	amount.add_theme_color_override("font_color", GOLD)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(amount)

	# La RÉPARTITION, ligne par ligne — le cœur de l'écran (cf. l'en-tête).
	# ⚠️ COLONNES, pas du texte centré — défaut CONSTATÉ EN CAPTURE : centrer « HAKIM +50 » puis
	# « VULTURE-7 +50 » désalignait les montants d'une ligne à l'autre, et l'œil ne pouvait plus
	# vérifier d'un coup que le partage est ÉGAL. Or c'est exactement ce qu'il vient lire.
	var names := shares.keys()
	names.sort()
	for who in names:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)

		var name_lbl := Label.new()
		name_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		name_lbl.text = "❯  " + str(who)
		name_lbl.add_theme_font_override("font", _font)
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", TEXT)
		name_lbl.custom_minimum_size = Vector2(240, 0)
		row.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
		val_lbl.text = "+%d" % int(shares[who])
		val_lbl.add_theme_font_override("font", _font)
		val_lbl.add_theme_font_size_override("font_size", 20)
		val_lbl.add_theme_color_override("font_color", ACCENT)
		val_lbl.custom_minimum_size = Vector2(80, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)

	# Rappel du DÉCLENCHEUR — défaut CONSTATÉ EN CAPTURE : cette ligne répétait le titre de la
	# caisse, ce qui ressemblait à un bug d'affichage. Elle dit désormais POURQUOI la caisse tombe,
	# la seule chose que l'écran n'expliquait pas.
	var hint := Label.new()
	hint.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	hint.text = tr("BR_CRATE_TRIGGER") % int(kills)
	hint.add_theme_font_override("font", _font)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	# PUNCH-IN : la caisse arrive en surdimension puis se cale — c'est ce dépassement (1.25 → 1.0)
	# qui donne l'impression qu'elle TOMBE sur l'écran plutôt qu'elle n'y apparaît.
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(1.25, 1.25)
	modulate.a = 0.0
	AudioManager.play_sfx("click")
	var punch := create_tween().set_parallel(true)
	punch.tween_property(self, "modulate:a", 1.0, PUNCH_IN)
	punch.tween_property(_panel, "scale", Vector2.ONE, PUNCH_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await punch.finished

	await get_tree().create_timer(HOLD).timeout
	if not is_inside_tree():
		return
	var out := create_tween()
	out.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	await out.finished
	finished.emit()
	queue_free()
