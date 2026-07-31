extends Control

# =========================================================================
# ALARME DE TRAHISON — « COUP D'ÉTAT EN COURS » (BATTLE ROYALE §8.125)
# =========================================================================
# Surcouche PLEIN ÉCRAN vue par TOUS au déclenchement d'un Coup d'État : sirène d'alerte, clignotant
# rouge, plaque de DANGER centrale, puis verdict. 100 % procédurale (aucun asset), View PURE
# (Règle d'Or §6.1) — elle ne connaît ni le réseau ni les règles, on lui passe un verdict résolu.
#
# ⚠️ ON DOIT VOIR LE PLATEAU À TRAVERS. C'est la contrainte n° 1, et elle a coûté une première
# version : un voile rouge PLEIN à 0,40 d'alpha noyait la carte et transformait l'évènement le plus
# spectaculaire du jeu en écran de chargement rouge. Le clignotant vit donc dans une **VIGNETTE**
# (bords saturés, CENTRE LIBRE) plus un voile résiduel quasi nul — l'œil lit « alerte » par la
# périphérie, exactement comme un vrai gyrophare, et le regard reste sur l'action.
#
# ⚠️⚠️ STYLE « CAUTION / DANGER » assumé : bandes diagonales jaune-noir (ruban de chantier), plaque
# noire à bordure jaune épaisse, typo capitale. Ce n'est pas de la décoration — c'est le vocabulaire
# visuel universel du danger imminent, et il se lit sans être lu.
#
# ⚠️⚠️⚠️ La sirène est SYNTHÉTISÉE ici (balayage de deux tons, saturé), pas jouée depuis un `.ogg` :
# le projet n'a pas d'asset d'alarme et en fabriquer un aurait signifié livrer un binaire non
# versionnable. Le son reste reproductible et réglable en une constante.

signal finished

const GOLD := Color("e0b249")
const HAZARD := Color("f2c230")      # jaune de ruban de danger (plus saturé que l'or de charte)
const DANGER := Color("d6453f")
const TEXT := Color("eef3f7")
const INK := Color("0b0d10")

# Durées (s). Total ≈ 4 s — la borne haute demandée. Au-delà, une alarme cesse d'être un évènement
# et devient une attente : le joueur qui la subit une 2ᵉ fois voudrait déjà la passer.
const ALARM_DURATION := 2.4
const VERDICT_DURATION := 1.6
const PULSE_HZ := 2.2

# Opacités du clignotant. Le VOILE plein reste dérisoire (le plateau doit rester lisible) ; c'est la
# VIGNETTE de bord qui porte l'alerte. Ne pas remonter `VEIL_MAX` : c'est exactement l'erreur que
# cette version corrige.
const VEIL_MIN := 0.01
const VEIL_MAX := 0.05
const VIGNETTE_MIN := 0.14
const VIGNETTE_MAX := 0.62
# Épaisseur de la vignette, en fraction de l'écran. 0,22 laisse plus des deux tiers de la carte
# parfaitement nets.
const VIGNETTE_RATIO := 0.22

const SIREN_LOW := 440.0
const SIREN_HIGH := 660.0
const SIREN_SAMPLE_RATE := 22050

var _font: SystemFont
var _veil: ColorRect
var _vignette: Control
var _plate: PanelContainer
var _plate_style: StyleBoxFlat
var _title: Label
var _stripes: Array = []
var _player: AudioStreamPlayer
var _elapsed := 0.0
var _pulsing := true


# --- Bande de RUBAN DE DANGER (diagonales jaune/noir), dessinée à la main -------------------------
# Un `_draw()` plutôt qu'une texture : la bande doit s'adapter à la largeur de la plaque, et un
# asset aurait imposé une résolution fixe (ou un étirement visible sur les diagonales).
class HazardTape extends Control:
	var stripe_color: Color = Color("f2c230")
	var ink_color: Color = Color("0b0d10")
	var stripe_width: float = 26.0
	# Décalage de DÉFILEMENT des bandes. ⚠️ Le défilement se fait DANS `_draw()`, pas en bougeant le
	# nœud : cette bande vit dans un `VBoxContainer`, qui repositionne ses enfants à chaque passe de
	# layout — animer `position.x` aurait été un no-op silencieux (rien à l'écran, aucune erreur).
	var scroll: float = 0.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(Vector2.ZERO, size), ink_color)
		# Parallélogrammes à 45°. On démarre à `−h − période` pour que le motif reste plein même au
		# maximum du décalage, sinon un coin vide apparaît à gauche en cours d'animation.
		var period := stripe_width * 2.0
		var x := -h - period + fmod(scroll, period)
		while x < w + h:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, h),
				Vector2(x + h, 0.0),
				Vector2(x + h + stripe_width, 0.0),
				Vector2(x + stripe_width, h),
			]), stripe_color)
			x += period


# --- VIGNETTE de bord : quatre dégradés rouges vers l'intérieur, CENTRE INTACT --------------------
class RedVignette extends Control:
	var strength: float = 0.6
	var ratio: float = 0.22
	var tint: Color = Color("d6453f")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var bx := w * ratio
		var by := h * ratio
		# 16 bandes par bord : assez pour que le dégradé soit invisible à l'œil, assez peu pour
		# rester gratuit à dessiner (64 rects par frame).
		var steps := 16
		for i in range(steps):
			var t := float(i) / float(steps)          # 0 = bord, 1 = intérieur
			var a: float = strength * pow(1.0 - t, 2.2)  # chute quadratique → bord franc, fond net
			var col := Color(tint.r, tint.g, tint.b, a)
			var sx := bx / steps
			var sy := by / steps
			draw_rect(Rect2(Vector2(i * sx, 0), Vector2(sx + 1.0, h)), col)              # gauche
			draw_rect(Rect2(Vector2(w - (i + 1) * sx, 0), Vector2(sx + 1.0, h)), col)    # droite
			draw_rect(Rect2(Vector2(0, i * sy), Vector2(w, sy + 1.0)), col)              # haut
			draw_rect(Rect2(Vector2(0, h - (i + 1) * sy), Vector2(w, sy + 1.0)), col)    # bas


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200   # au-dessus du HUD ET des badges du plateau (§8.122 : l'ordre d'arbre ne suffit pas).

	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	_font.font_weight = 700

	# 1) Voile plein — volontairement DÉRISOIRE (cf. VEIL_MAX) : il teinte, il ne masque pas.
	_veil = ColorRect.new()
	_veil.color = Color(DANGER, 0.0)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)

	# 2) Vignette clignotante — c'est ELLE qui porte l'alerte, et elle laisse le centre libre.
	_vignette = RedVignette.new()
	_vignette.ratio = VIGNETTE_RATIO
	_vignette.tint = DANGER
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)

	# 3) Plaque DANGER, centrée haut (pas au milieu : le centre de l'écran, c'est la carte).
	# ⚠️ CENTRAGE PAR CONTENEUR, pas par ancres — défaut CONSTATÉ EN CAPTURE : un
	# `set_anchors_preset(PRESET_CENTER_TOP)` sur un PanelContainer qui se dimensionne sur son
	# CONTENU laisse les offsets périmés, et la plaque sortait par la gauche de l'écran. Un
	# VBoxContainer plein écran + `SIZE_SHRINK_CENTER` recentre à chaque passe de layout, quelle que
	# soit la largeur du texte (qui change au verdict !).
	var anchor := VBoxContainer.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.alignment = BoxContainer.ALIGNMENT_BEGIN
	anchor.add_theme_constant_override("separation", 0)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	# Marge haute : la plaque descend sous le bandeau de tour du HUD au lieu de le recouvrir.
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 118)
	top_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(top_gap)

	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_style = StyleBoxFlat.new()
	_plate_style.bg_color = Color(INK, 0.94)
	_plate_style.set_corner_radius_all(0)
	_plate_style.set_border_width_all(4)
	_plate_style.border_color = HAZARD
	_plate_style.shadow_color = Color(DANGER, 0.6)
	_plate_style.shadow_size = 22
	_plate.add_theme_stylebox_override("panel", _plate_style)
	_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	anchor.add_child(_plate)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(col)

	col.add_child(_make_tape())

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 46)
	pad.add_theme_constant_override("margin_right", 46)
	pad.add_theme_constant_override("margin_top", 18)
	pad.add_theme_constant_override("margin_bottom", 18)
	col.add_child(pad)

	_title = Label.new()
	_title.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	_title.text = "⚠  %s  ⚠" % tr("BR_COUP_ALARM")
	_title.add_theme_font_override("font", _font)
	_title.add_theme_font_size_override("font_size", 52)
	# BLANC, jamais rouge : le rouge du décor est déjà pris par le clignotant, et un titre rouge
	# sur alerte rouge devient illisible au pic du battement (défaut constaté en capture).
	_title.add_theme_color_override("font_color", TEXT)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_constant_override("outline_size", 8)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(820, 0)
	pad.add_child(_title)

	col.add_child(_make_tape())


func _make_tape() -> Control:
	var tape := HazardTape.new()
	tape.stripe_color = HAZARD
	tape.ink_color = INK
	tape.custom_minimum_size = Vector2(0, 22)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stripes.append(tape)
	return tape


func _process(delta: float) -> void:
	if not _pulsing:
		return
	_elapsed += delta
	# |sin| : la pulsation touche VRAIMENT le creux entre deux flashs, là où un sinus centré
	# resterait toujours un peu rouge — l'œil ne verrait plus un clignotant mais un fond teinté.
	var pulse: float = absf(sin(_elapsed * PI * PULSE_HZ))
	_veil.color = Color(DANGER, lerpf(VEIL_MIN, VEIL_MAX, pulse))
	_vignette.strength = lerpf(VIGNETTE_MIN, VIGNETTE_MAX, pulse)
	_vignette.queue_redraw()
	# Le ruban de danger DÉFILE (comme un gyrophare qui tourne) — une plaque figée aurait l'air d'un
	# panneau accroché au mur. Le décalage passe par `scroll` + `queue_redraw`, jamais par
	# `position` : ces bandes vivent dans un VBoxContainer qui les repositionnerait aussitôt.
	for tape in _stripes:
		tape.scroll = _elapsed * 60.0
		tape.queue_redraw()
	_plate_style.border_color = HAZARD.lerp(DANGER, pulse)
	_plate_style.shadow_size = int(lerpf(14.0, 30.0, pulse))


# Joue l'alarme puis le verdict. `success` = le coup a-t-il réussi ; `traitor` / `victim` = pseudos
# DÉJÀ résolus (la vue ne connaît pas les ids). Émet `finished` à la fin — l'appelant enchaîne.
func play(success: bool, traitor: String, victim: String) -> void:
	_start_siren()
	await get_tree().create_timer(ALARM_DURATION).timeout
	if not is_inside_tree():
		return

	# VERDICT : le clignotant s'arrête net, la vignette retombe et la COULEUR dit le résultat —
	# or si le traître l'emporte (c'est une victoire, aussi sale soit-elle), rouge s'il y est resté.
	_pulsing = false
	_veil.color = Color(DANGER if not success else GOLD, 0.06)
	_vignette.strength = 0.28
	_vignette.tint = GOLD if success else DANGER
	_vignette.queue_redraw()
	_plate_style.border_color = GOLD if success else DANGER
	_plate_style.shadow_color = Color(GOLD if success else DANGER, 0.6)
	_title.text = tr("BR_COUP_SUCCESS" if success else "BR_COUP_FAILED") % [traitor, victim]
	_title.add_theme_font_size_override("font_size", 38)
	_title.add_theme_color_override("font_color", GOLD if success else TEXT)
	AudioManager.play_sfx("click")

	await get_tree().create_timer(VERDICT_DURATION).timeout
	if not is_inside_tree():
		return
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.35)
	await fade.finished
	finished.emit()
	queue_free()


# Sirène SYNTHÉTISÉE : balayage entre deux tons, saturé pour le grain « alerte ».
func _start_siren() -> void:
	var frames := int(SIREN_SAMPLE_RATE * ALARM_DURATION)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	for i in range(frames):
		var t: float = float(i) / SIREN_SAMPLE_RATE
		# Glissando lent entre les deux tons (2 allers-retours/s) : c'est lui qui fait « sirène »
		# plutôt que « bip ».
		var freq: float = lerpf(SIREN_LOW, SIREN_HIGH, 0.5 + 0.5 * sin(t * PI * 2.0))
		phase += freq / SIREN_SAMPLE_RATE
		var raw: float = sin(phase * TAU)
		var shaped: float = clampf(raw * 1.8, -1.0, 1.0)   # saturation → timbre métallique
		# Fondu de 120 ms aux deux bouts : sans lui, le démarrage et la coupe font un « clac ».
		var env: float = clampf(minf(t, ALARM_DURATION - t) / 0.12, 0.0, 1.0)
		var value := int(shaped * env * 11000.0)
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SIREN_SAMPLE_RATE
	stream.stereo = false
	stream.data = data

	_player = AudioStreamPlayer.new()
	_player.stream = stream
	# Bus SFX s'il existe (§8.122), sinon Master — jamais d'erreur si le bus manque.
	_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_player.volume_db = -6.0
	add_child(_player)
	_player.play()
