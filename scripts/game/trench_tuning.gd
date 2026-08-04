extends Control
# =================================================================================================
# LA TRANCHÉE — LE PANNEAU DE RÉGLAGE EN JEU (touche F10, mode ENTRAÎNEMENT uniquement).
#
# ╔═ POURQUOI CE PANNEAU EXISTE — C'EST UNE LEÇON, PAS UNE COMMODITÉ ═════════════════════════════╗
# ║ La session §8.139.1 a réglé la sensation de visée À L'AVEUGLE : sensibilité de la souris,      ║
# ║ suivi de caméra et plafond d'angle ont été choisis par raisonnement, livrés ensemble, et le    ║
# ║ premier essai réel a rendu « le mouvement de la souris est inversé et pas du tout facile à     ║
# ║ gérer ». Aucune mesure ne pouvait attraper ça : une sensation ne se mesure pas en pixels, elle ║
# ║ s'éprouve manette en main. Chaque aller-retour coûtait alors une livraison complète.           ║
# ║                                                                                                ║
# ║ On inverse donc la charge : le code n'essaie PLUS de deviner. Il expose des bornes honnêtes et ║
# ║ Hakim règle lui-même, en jouant, à la frame. Les valeurs qu'il retient sont écrites sur disque ║
# ║ et deviendront les défauts d'usine à la clôture du chantier.                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ ENTRAÎNEMENT UNIQUEMENT. En classée ou en duel, le panneau ne s'ouvre pas : il relâcherait la
# souris et immobiliserait le joueur pendant qu'un adversaire, lui, continue de jouer.
#
# VUE PURE (Règle d'Or §6.1) : ce nœud ne lit ni `NetworkManager`, ni `GameState`, ni aucune règle.
# Il émet `changed` avec un dictionnaire ; c'est `trench_fp.gd` qui décide quoi en faire.

signal changed(values: Dictionary)

const SETTINGS_PATH := "user://trench_tuning.json"

# ╔═ ⚠️⚠️ LES RÉGLAGES SONT VERSIONNÉS, ET C'EST UN CORRECTIF, PAS UNE PRÉCAUTION ════════════════╗
# ║ Attrapé au harnais après le passage de l'arène à 12 m : un `trench_tuning.json` écrit AVANT le ║
# ║ changement portait `follow_max_deg = 45`. La valeur est parfaitement légale — elle passe les   ║
# ║ bornes — mais son SENS a changé : le débattement de visée est monté à ±58°, donc une caméra    ║
# ║ plafonnée à 45° cesse de suivre le réticule dans les 13 derniers degrés. Le joueur viserait    ║
# ║ une cible que sa propre vue refuse de rejoindre, et il aurait mis ça sur le compte du jeu.     ║
# ║ Un fichier relu tel quel aurait donc SILENCIEUSEMENT dégradé la partie suivante de Hakim, avec ║
# ║ ses propres réglages, sans un message. On INCRÉMENTE donc à chaque fois qu'une borne change de ║
# ║ signification, et un fichier d'une autre version repart des défauts.                           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const SETTINGS_VERSION := 2

const COL_ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const COL_TEXT := Color(0.933333, 0.952941, 0.968627, 1)
const COL_MUTED := Color(0.541176, 0.592157, 0.647059, 1)
const COL_GOLD := Color(0.878431, 0.698039, 0.286275, 1)

# ╔═ LES DÉFAUTS D'USINE ═════════════════════════════════════════════════════════════════════════╗
# ║ Ce sont les valeurs de §8.139.1 — celles qui n'ont jamais été jugées dans de bonnes            ║
# ║ conditions, parce que la caméra ne tournait que de 6° devant un décor peint fixe. Elles ne     ║
# ║ sont donc PAS des vérités : elles sont un point de départ à contester en jouant.               ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const DEFAULTS := {
	"mouse_sensitivity": 0.040,      # degrés de visée par pixel de souris
	"invert_y": false,
	"aim_follow": 1.0,               # part de la visée que la caméra accompagne (0 = tête fixe)
	"follow_max_deg": 70.0,          # plafond de rotation de la caméra (> AIM_YAW_LIMIT = 58°)
	"fov": 55.0,                     # champ de vision VERTICAL
}

# {clé: [minimum, maximum, pas, libellé, décimales]}
const SLIDERS := {
	"mouse_sensitivity": [0.010, 0.150, 0.002, "TRENCH_TUNE_SENSITIVITY", 3],
	"aim_follow": [0.0, 1.0, 0.05, "TRENCH_TUNE_FOLLOW", 2],
	# ⚙ Plage ouverte à 80° avec le passage à 12 m : le débattement de visée est monté à ±58°, et
	# une borne de caméra plus basse que lui empêcherait de suivre le réticule dans les extrêmes.
	"follow_max_deg": [10.0, 80.0, 1.0, "TRENCH_TUNE_FOLLOW_MAX", 0],
	# ⚖ ARBITRAGE — le bon de commande demande « FOV (60-90) », le jeu tourne à 55 (`CAMERA_FOV`).
	# Une plage qui ne contient pas la valeur COURANTE n'est pas un réglage : c'est un changement
	# déguisé. Vu en capture — le curseur affichait 60 pour une caméra à 55, et la première
	# ouverture du panneau aurait élargi le champ sans que personne ne l'ait demandé. On descend
	# donc la borne basse à 50 : la plage demandée reste entièrement accessible, et l'état de départ
	# est représentable. C'est la seule des cinq bornes qui s'écarte du bon de commande.
	"fov": [50.0, 90.0, 1.0, "TRENCH_TUNE_FOV", 0],
}

var _values: Dictionary = DEFAULTS.duplicate()
var _sliders: Dictionary = {}
var _readouts: Dictionary = {}
var _invert_box: CheckBox
var _journal: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ╔═ ⚠️⚠️ 7ᵉ RÉCIDIVE DE « UN CONTROL CRÉÉ PAR CODE GARDE size = (0,0) » ═════════════════════╗
	# ║ Vue en CAPTURE, et par aucun autre moyen : le panneau était introuvable à l'écran alors que ║
	# ║ `visible` valait `true` et que ses 45 contrôles étaient verts. Diagnostic : ce nœud sortait  ║
	# ║ de `_ready()` avec `size = (0,0)` — un Control bâti par code et laissé INVISIBLE n'est       ║
	# ║ jamais mis en page. Le PanelContainer, lui, était correctement dimensionné (392 × 434) et    ║
	# ║ ancré EN HAUT À DROITE… d'un parent de largeur nulle : il atterrissait donc à x = −400,     ║
	# ║ intégralement hors de l'écran. Aucune ERROR, aucun test au rouge — juste rien à voir.       ║
	# ║ On cesse donc de faire confiance à la résolution d'ancres pour ce nœud : on lui POSE sa      ║
	# ║ taille, et on la reprend à chaque redimensionnement de fenêtre.                              ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_values = _load()
	_build()
	visible = false


func _fit_to_viewport() -> void:
	size = get_viewport_rect().size


func values() -> Dictionary:
	return _values.duplicate()


# =================================================================================================
# PERSISTANCE
# =================================================================================================
# ⚠️ Toute valeur relue est REVALIDÉE contre les bornes du panneau. Un `trench_tuning.json` édité à
# la main (ou écrit par une version antérieure du panneau) ne doit pas pouvoir poser un FOV de 300
# ni une sensibilité nulle : le fichier est une commodité, jamais une autorité.
func _load() -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return out
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return out
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	if int(parsed.get("version", 1)) != SETTINGS_VERSION:
		# Réglages d'une arène qui n'existe plus : on repart des défauts EN LE DISANT, plutôt que
		# de laisser le joueur jouer une partie dégradée avec ses propres anciens chiffres.
		print("[trench] reglages v%s ignores (version courante %d) : retour aux defauts"
			% [parsed.get("version", 1), SETTINGS_VERSION])
		return out
	for key in DEFAULTS:
		if not parsed.has(key):
			continue
		if key == "invert_y":
			out[key] = bool(parsed[key])
			continue
		var bounds: Array = SLIDERS.get(key, [])
		if bounds.is_empty():
			continue
		out[key] = clampf(float(parsed[key]), float(bounds[0]), float(bounds[1]))
	return out


func _save() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		return
	var payload := _values.duplicate()
	payload["version"] = SETTINGS_VERSION
	file.store_string(JSON.stringify(payload, "  "))
	file.close()


# =================================================================================================
# CONSTRUCTION
# =================================================================================================
func _font(size: int) -> Font:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Bahnschrift", "Oswald", "Saira Condensed",
		"Arial Narrow", "Arial"])
	base.font_weight = 700
	return base


func _label(text: String, size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", _font(size))
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


func _build() -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.058824, 0.07451, 0.094118, 0.93)
	style.border_color = COL_ACCENT
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	# ⚠️ La MÉTHODE `set_anchors_preset`, et des offsets explicites : `anchors_preset = X` assigné
	# en code est une commodité d'ÉDITEUR qui ne s'applique pas, et un `Control` créé par code garde
	# `size = (0,0)` — six récidives de cette famille dans ce dépôt (cf. `trench_ambient.gd`).
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -400.0
	panel.offset_top = 130.0
	panel.offset_right = -24.0
	panel.offset_bottom = 560.0
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := _label(tr("TRENCH_TUNE_TITLE"), 19, COL_ACCENT)
	column.add_child(title)
	var hint := _label(tr("TRENCH_TUNE_HINT"), 12, COL_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(356, 0)
	column.add_child(hint)
	column.add_child(HSeparator.new())

	for key in SLIDERS:
		column.add_child(_build_slider(key))

	_invert_box = CheckBox.new()
	_invert_box.text = tr("TRENCH_TUNE_INVERT_Y")
	_invert_box.add_theme_font_override("font", _font(14))
	_invert_box.add_theme_font_size_override("font_size", 14)
	_invert_box.add_theme_color_override("font_color", COL_TEXT)
	_invert_box.button_pressed = bool(_values.get("invert_y", false))
	_invert_box.toggled.connect(func(pressed: bool):
		_values["invert_y"] = pressed
		_commit())
	column.add_child(_invert_box)

	column.add_child(HSeparator.new())
	# LE JOURNAL DES ENTRÉES (§ LOT C.3) : le symptôme « les déplacements ne fonctionnent pas » n'a
	# jamais été reproduit ni diagnostiqué. S'il revient en partie réelle, il faut pouvoir lire À
	# L'ÉCRAN ce que le client croit envoyer — sans quoi on repart pour une session d'hypothèses.
	_journal = _label("", 12, COL_GOLD)
	_journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_journal.custom_minimum_size = Vector2(356, 54)
	column.add_child(_journal)

	var reset := Button.new()
	reset.text = tr("TRENCH_TUNE_RESET")
	reset.add_theme_font_override("font", _font(14))
	reset.add_theme_font_size_override("font_size", 14)
	reset.pressed.connect(_on_reset)
	column.add_child(reset)


func _build_slider(key: String) -> Control:
	var bounds: Array = SLIDERS[key]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	var name_label := _label(tr(String(bounds[3])), 14, COL_TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var readout := _label("", 14, COL_ACCENT)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(readout)
	row.add_child(header)
	_readouts[key] = readout

	var slider := HSlider.new()
	slider.min_value = float(bounds[0])
	slider.max_value = float(bounds[1])
	slider.step = float(bounds[2])
	slider.value = float(_values.get(key, DEFAULTS[key]))
	slider.custom_minimum_size = Vector2(356, 18)
	slider.value_changed.connect(func(value: float):
		_values[key] = value
		_refresh_readout(key)
		_commit())
	row.add_child(slider)
	_sliders[key] = slider
	_refresh_readout(key)
	return row


func _refresh_readout(key: String) -> void:
	var readout: Label = _readouts.get(key)
	if readout == null:
		return
	var decimals: int = int(SLIDERS[key][4])
	readout.text = String.num(float(_values.get(key, 0.0)), decimals)


func _on_reset() -> void:
	_values = DEFAULTS.duplicate()
	for key in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(float(_values[key]))
		_refresh_readout(key)
	if _invert_box != null:
		_invert_box.set_pressed_no_signal(bool(_values["invert_y"]))
	_commit()


# Appliqué À LA FRAME, puis écrit sur disque. L'écriture est bon marché (un fichier de 5 lignes) et
# elle évite le scénario qui viderait le panneau de son sens : régler la sensation pendant dix
# minutes, quitter, et tout retrouver comme avant.
func _commit() -> void:
	_save()
	changed.emit(values())


# =================================================================================================
# JOURNAL DES ENTRÉES — poussé par l'hôte à chaque envoi réseau
# =================================================================================================
func set_journal(line: String) -> void:
	if _journal != null and visible:
		_journal.text = line


func toggle() -> void:
	visible = not visible
