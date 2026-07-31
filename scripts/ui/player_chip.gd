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
# TAG de compagnie (§8.126) — Label SÉPARÉ du pseudo : teinte atténuée, jamais colorée faction, et
# hors du champ de la troncature compacte (cf. `_ensure_built`).
var _tag: Label = null
var _pseudo: Label = null
var _faction_mark: Label = null
# PACTES (§8.123) : deux marques posées ICI, dans la brique partagée, plutôt que dans chaque écran
# — c'est ce qui les fait apparaître d'un coup PARTOUT où un joueur est nommé (ordre de tour, fiche
# joueur, kill feed, inspecteur). Les deux données sont PUBLIQUES : un pacte actif est diffusé à
# toute la table (c'est son but), et une rupture est annoncée par un bandeau vu de tous.
var _pact_mark: Label = null      # 🤝 — ce joueur est lié par au moins un pacte ACTIF
var _traitor_mark: Label = null   # ⚡ — ce joueur a rompu un pacte CE MATCH (marque définitive)

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

	# TAG DE COMPAGNIE (§8.126) — nœud DÉDIÉ, placé AVANT le pseudo. Deux raisons de ne pas se
	# contenter d'un préfixe dans la chaîne du pseudo :
	#  1. la charte veut le tag en TEINTE ATTÉNUÉE et JAMAIS coloré par la faction — une String n'a
	#     qu'une couleur, un Label voisin en a une autre ;
	#  2. la troncature COMPACTE ne doit ronger que le pseudo : un tag à moitié coupé (« [ALF… »)
	#     n'identifie plus rien.
	_tag = Label.new()
	_tag.add_theme_font_size_override("font_size", FONT_SIZE_COMPACT)
	_tag.add_theme_color_override("font_color", NEUTRAL_COLOR)
	_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.visible = false
	add_child(_tag)

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

	# PACTE ACTIF (§8.123) — la marque doit être lisible DE LOIN : c'est elle qui fait qu'un joueur
	# réfléchit avant d'attaquer. Cyan tactique (couleur de tout ce qui est « accord » dans la
	# charte), et non or : l'or est réservé aux récompenses.
	# ⚠️ GLYPHE : `↔` et NON l'emoji 🤝 du cahier des charges. Les emoji hors BMP (> U+FFFF) rendent
	# en TOFU avec la police condensée de la charte — constat §8.117 (📢 ✉ 🎯), et 🤝 (U+1F91D) est
	# du même bloc que 🎯. `↔` vit dans le bloc Arrows (voisin de `→`, déjà employé) et dit
	# exactement la même chose : un accord à DOUBLE SENS. Le libellé du tooltip l'utilisait déjà.
	_pact_mark = Label.new()
	_pact_mark.text = "↔"
	_pact_mark.add_theme_font_size_override("font_size", 11)
	_pact_mark.add_theme_color_override("font_color", Color("36c5d9"))
	_pact_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pact_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pact_mark.visible = false
	add_child(_pact_mark)

	# TRAÎTRE — reste jusqu'à la fin de la partie. Rouge danger. C'est la SEULE sanction d'une
	# trahison : aucune pénalité mécanique, juste le fait qu'on s'en souvienne.
	_traitor_mark = Label.new()
	_traitor_mark.text = "⚡"
	_traitor_mark.add_theme_font_size_override("font_size", 11)
	_traitor_mark.add_theme_color_override("font_color", Color("d6453f"))
	_traitor_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_traitor_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_traitor_mark.visible = false
	add_child(_traitor_mark)

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

	# TAG de compagnie (§8.126) — teinte ATTÉNUÉE (acier), jamais l'accent de faction : il doit se
	# lire sans jamais concurrencer le pseudo ni la couleur plateau. Absent → Label masqué, donc
	# aucune espace fantôme dans une rangée serrée.
	var company_tag := GameState.company_tag_of(int(pid))
	_tag.visible = company_tag != ""
	if _tag.visible:
		_tag.text = "[%s]" % company_tag
		_tag.add_theme_font_size_override("font_size",
			FONT_SIZE_COMPACT - 1 if compact else FONT_SIZE_COMPACT)

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
	# Le tooltip, lui, porte le pseudo COMPLET *avec* son tag (le Label voisin peut être coupé par
	# la mise en page ; le tooltip est le dernier recours pour lire une identité en entier).
	tooltip_text = GameState.tagged_name(int(pid), display) \
		+ (("\n" + (tr("CHIP_FACTION_TOOLTIP") % fid.capitalize())) if fid != "" else "")
	_refresh_pact_marks(int(pid), display)

# PACTES (§8.123) — état PUBLIC relu à chaque `setup()` (donc à chaque rafraîchissement d'état) :
# la brique n'a rien à mémoriser, elle reflète simplement `GameState.pacts`. Un pacte qui expire ou
# se rompt fait donc disparaître / apparaître les marques tout seul, sans notification dédiée.
func _refresh_pact_marks(pid: int, display: String) -> void:
	if _pact_mark == null or not is_instance_valid(_pact_mark):
		return
	var pacts: Array = GameState.pacts
	var partners := PactState.active_partners(pacts, pid)
	_pact_mark.visible = not partners.is_empty()
	if _pact_mark.visible:
		# Un joueur peut tenir jusqu'à 2 pactes : le tooltip les liste TOUS, avec leur échéance —
		# « avec qui, et jusqu'à quand » est exactement ce qu'un adversaire a besoin de savoir.
		var lines: PackedStringArray = []
		for other in partners:
			var entry := PactState.find_active_between(pacts, pid, int(other))
			lines.append(tr("PACT_ACTIVE_TOOLTIP") % [
				display, _peer_name(int(other)), int(entry.get("expires_at_round", 0))])
		_pact_mark.tooltip_text = "\n".join(lines)
		# Le tooltip du 🤝 doit pouvoir s'ouvrir : PASS laisse malgré tout remonter le clic.
		_pact_mark.mouse_filter = Control.MOUSE_FILTER_PASS
	_traitor_mark.visible = PactState.is_traitor(pacts, pid)
	if _traitor_mark.visible:
		_traitor_mark.tooltip_text = tr("PACT_TRAITOR_MARK")
		_traitor_mark.mouse_filter = Control.MOUSE_FILTER_PASS

# Pseudo COURT d'un autre joueur, pour les tooltips de pacte. Même résolution que ci-dessus
# (username serveur, préfixe [IA], repli traduit) — dupliquée en une ligne plutôt qu'exposée : la
# brique ne doit dépendre d'aucun contrôleur pour se rendre.
func _peer_name(pid: int) -> String:
	var p = GameState.players.get(str(int(pid)), {})
	if typeof(p) != TYPE_DICTIONARY:
		p = {}
	var is_bot: bool = int(pid) < 0 or bool(p.get("is_bot", false))
	var uname := str(p.get("username", ""))
	if uname == "":
		uname = (tr("CHIP_BOT_FALLBACK") % absi(int(pid))) if is_bot \
			else (tr("WR_PLAYER_FALLBACK") % GameState.player_number(pid))
	return ("[IA] " + uname) if is_bot else uname

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
