extends HBoxContainer

# BRIQUE « IDENTITÉ JOUEUR » (E1 §8.73) — source UNIQUE de la présentation d'un joueur dans
# toute l'UI (Roster de Guerre, Inspecteur de Territoire, puis VS E2 / feed E4) : pastille à la
# couleur PLATEAU du joueur (board.get_player_color — JAMAIS une 2ᵉ palette, piège n° 2 de
# PLAN_EXPERIENCE) + pseudo (préfixe « [IA] » pour un bot, G2 §8.72) + marque ◆ à l'accent de sa
# faction (accent_color du .tres, servi par le board — table unique). View pure (Règle d'Or
# §6.1) : lit l'état PUBLIC (GameState) et le plateau, aucune logique de jeu, aucun réseau.
#
# API : setup(pid, compact).
#   compact = version courte (bandeau d'ordre de tour E1, feed E4, inspecteur) : police réduite
#   et pseudo tronqué à COMPACT_MAX_CHARS (…) pour tenir en rangée serrée.

# Repli neutre quand le plateau n'est pas dans l'arbre (boot isolé du composant) ou que le
# joueur est inconnu — même gris acier que board.NEUTRAL_COLOR.
const NEUTRAL_COLOR := Color("8a97a5")
# Groupe où le plateau s'enregistre (board.gd::_ready) — voie d'accès des briques UI à la
# palette SANS référence câblée (le composant vit dans le HUD, le board dans le SubViewport).
const BOARD_GROUP := "game_board"

const FONT_SIZE_FULL := 13
const FONT_SIZE_COMPACT := 11
# Troncature du pseudo en mode compact (au-delà : « … ») — 6 chips + séparateurs tiennent
# dans le panneau latéral de 320 px (bandeau d'ordre de tour, avec repli FlowContainer).
const COMPACT_MAX_CHARS := 12

var _swatch: ColorRect = null
var _pseudo: Label = null
var _faction_mark: Label = null

func _ready() -> void:
	_ensure_built()

# Construction paresseuse et idempotente : setup() peut être appelé juste après l'instanciation
# (avant _ready) — le premier des deux appels construit les enfants.
func _ensure_built() -> void:
	if _pseudo != null and is_instance_valid(_pseudo):
		return
	add_theme_constant_override("separation", 5)
	# La brique laisse REMONTER les clics (les lignes du roster gèrent le clic) tout en gardant
	# ses tooltips (PASS ≠ IGNORE) ; ses enfants sont transparents aux clics.
	mouse_filter = Control.MOUSE_FILTER_PASS

	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(9, 9)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_swatch)

	_pseudo = Label.new()
	_pseudo.add_theme_font_size_override("font_size", FONT_SIZE_FULL)
	_pseudo.add_theme_color_override("font_color", Color("eef3f7"))
	_pseudo.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pseudo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pseudo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pseudo)

	_faction_mark = Label.new()
	_faction_mark.text = "◆"
	_faction_mark.add_theme_font_size_override("font_size", 10)
	_faction_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_faction_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_faction_mark)

# Alimente la brique pour un joueur. Toutes les données sont PUBLIQUES (GameState.players §8.28,
# is_bot G2 §8.72) ; pids float/clés string normalisés ici (piège JSON §5 — str(int(pid))).
func setup(pid: int, compact: bool = false) -> void:
	_ensure_built()
	var p = GameState.players.get(str(int(pid)), {})
	if typeof(p) != TYPE_DICTIONARY:
		p = {}

	# Pseudo résolu comme main._display_name : username serveur (§8.28), préfixe « [IA] » pour un
	# bot (id négatif OU is_bot public), repli « Joueur N » séquentiel (GameState.player_number).
	# i18n : replis traduits (CHIP_BOT_FALLBACK / WR_PLAYER_FALLBACK — clé partagée waiting_room).
	var is_bot: bool = int(pid) < 0 or bool(p.get("is_bot", false))
	var uname := str(p.get("username", ""))
	if uname == "":
		uname = (tr("CHIP_BOT_FALLBACK") % absi(int(pid))) if is_bot \
			else (tr("WR_PLAYER_FALLBACK") % GameState.player_number(pid))
	var display := ("[IA] " + uname) if is_bot else uname
	# Troncature d'affichage compacte SEULEMENT — le tooltip garde toujours le pseudo COMPLET.
	var label_text := display
	if compact and label_text.length() > COMPACT_MAX_CHARS:
		label_text = label_text.substr(0, COMPACT_MAX_CHARS - 1) + "…"

	var color := _player_color(int(pid))
	_swatch.color = color
	_pseudo.text = label_text
	# Pseudo à la couleur plateau du joueur — cohérent avec IdentityLabel / color_pseudo (§8.23).
	_pseudo.add_theme_color_override("font_color", color)
	_pseudo.add_theme_font_size_override("font_size", FONT_SIZE_COMPACT if compact else FONT_SIZE_FULL)

	# Marque de faction ◆ à l'accent du .tres (via le board — table unique). Masquée si la
	# faction est inconnue / sans ressource (aucun losange gris fantôme).
	var fid := str(p.get("faction", ""))
	var accent := _faction_accent(fid)
	var has_accent: bool = fid != "" and accent != NEUTRAL_COLOR
	_faction_mark.visible = has_accent
	if has_accent:
		_faction_mark.add_theme_color_override("font_color", accent)
	tooltip_text = display + (("\n" + (tr("CHIP_FACTION_TOOLTIP") % fid.capitalize())) if fid != "" else "")

# Couleur plateau du joueur — TOUJOURS board.get_player_color (source unique E1) ; gris neutre
# si le plateau est absent (boot isolé du composant). Engine.get_main_loop() plutôt que
# get_tree() : setup() peut être appelé avant l'entrée de la brique dans l'arbre.
func _player_color(pid: int) -> Color:
	var b := _board()
	if b != null and b.has_method("get_player_color"):
		var c = b.get_player_color(pid)
		if c is Color:
			return c
	return NEUTRAL_COLOR

# Accent d'une faction — servi par board.get_faction_accent (table unique chargée des .tres).
func _faction_accent(fid: String) -> Color:
	if fid == "":
		return NEUTRAL_COLOR
	var b := _board()
	if b != null and b.has_method("get_faction_accent"):
		var c = b.get_faction_accent(fid)
		if c is Color:
			return c
	return NEUTRAL_COLOR

func _board() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(BOARD_GROUP)
