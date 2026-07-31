extends RefCounted

# =========================================================================
# CATALOGUE D'EMBLÈMES DE COMPAGNIE (§8.126) — charte « Warzone Command » §2
# =========================================================================
# Registre CLIENT des 24 emblèmes. Le serveur ne connaît qu'un ENTIER (`emblem_id`) : aucune image
# ne transite jamais par le réseau, et changer un visuel ne demande NI migration NI redéploiement
# backend.
#
# ⚠️ MÉCANIQUE DE REMPLACEMENT AUTOMATIQUE (patron éprouvé de l'audio §8.122). Tant qu'aucun asset
# n'est déposé, chaque emblème est un PLACEHOLDER GÉOMÉTRIQUE dessiné par code (monogramme sur fond
# gunmetal, liseré teinté). Le jour où `res://resources/companies/emblem_00.png` … `emblem_23.png`
# existent, ils sont servis À LA PLACE — **sans toucher une ligne de code**. Déposer les fichiers
# SUFFIT.
#
# ⚠️ MONOGRAMMES ASCII UNIQUEMENT (A..X). Aucun pictogramme, aucun emoji : la police condensée de la
# charte rend en TOFU tout glyphe hors BMP — constat §8.117 (📢 ✉ 🎯) puis §8.123 (🤝 → `↔`). Un
# placeholder illisible serait pire qu'un carré vide.

const EMBLEM_DIR := "res://resources/companies/"
# Nombre d'emblèmes du catalogue. ⚠️ MIROIR de `companies.COMPANY_RULES["emblem_count"]` — mais le
# client ne s'en sert QUE comme repli : `count()` préfère toujours le registre SERVEUR quand il est
# arrivé (le serveur est l'autorité, §9.5), pour qu'agrandir le catalogue ne demande qu'un dépôt de
# fichiers et une constante backend.
const EMBLEM_COUNT := 24

# Monogrammes : une lettre par emblème, dans l'ordre. 24 lettres A..X — ASCII pur, donc rendu
# GARANTI quelle que soit la police de repli.
const MONOGRAMS := "ABCDEFGHIJKLMNOPQRSTUVWX"

# Teintes de liseré — TOUTES issues de la charte §2 (cyan tactique, or, acier, platine, bronze).
# Aucune couleur inventée : un emblème ne doit jamais concurrencer visuellement la couleur PLATEAU
# d'un joueur ni l'accent d'une faction.
const TINTS := [
	Color(0.211765, 0.772549, 0.85098, 1),   # cyan tactique
	Color(0.878431, 0.698039, 0.286275, 1),  # or
	Color(0.541176, 0.592157, 0.647059, 1),  # acier
	Color("9adfea"),                          # platine
	Color("cd7f32"),                          # bronze
	Color(0.933333, 0.952941, 0.968627, 1),  # blanc froid
]

const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1)


# Nombre d'emblèmes proposés. `server_count` = `rules.emblem_count` de `GET /company/mine` : le
# serveur fait autorité dès qu'il a répondu ; 0/absent → repli sur la constante locale.
static func count(server_count: int = 0) -> int:
	return server_count if server_count > 0 else EMBLEM_COUNT


static func tint_of(emblem_id: int) -> Color:
	return TINTS[int(emblem_id) % TINTS.size()]


static func monogram_of(emblem_id: int) -> String:
	return MONOGRAMS[int(emblem_id) % MONOGRAMS.length()]


# Texture de l'emblème si un asset a été déposé, sinon `null` (→ placeholder procédural).
# `ResourceLoader.exists` et NON `FileAccess.file_exists` : en build exporté les PNG deviennent des
# ressources importées (`.ctex`) et le fichier source n'existe plus — c'est le piège classique du
# dépôt (cf. le scan export-safe des `.tres` de factions).
static func texture_of(emblem_id: int) -> Texture2D:
	var path := "%semblem_%02d.png" % [EMBLEM_DIR, int(emblem_id)]
	if not ResourceLoader.exists(path, "Texture2D"):
		return null
	var res := ResourceLoader.load(path, "Texture2D")
	return res as Texture2D


# Vignette d'emblème PRÊTE À POSER, de côté `size`. Asset s'il existe, placeholder sinon — l'appelant
# n'a jamais à savoir lequel des deux il obtient. `font` : police de la charte (le monogramme la
# suit) ; peut être null.
static func make_badge(emblem_id: int, size: float, font: Font = null) -> Control:
	var tint := tint_of(emblem_id)
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = GUNMETAL
	sb.set_corner_radius_all(0)           # ADN angulaire §2 : jamais d'arrondi.
	sb.set_border_width_all(2)
	sb.border_color = Color(tint, 0.85)
	sb.set_content_margin_all(0.0)
	holder.add_theme_stylebox_override("panel", sb)

	var art := texture_of(emblem_id)
	if art != null:
		var rect := TextureRect.new()
		rect.texture = art
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rect)
		return holder

	# --- PLACEHOLDER : monogramme centré, teinté, sur fond gunmetal. ---
	var mono := Label.new()
	mono.auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	mono.text = monogram_of(emblem_id)
	if font != null:
		mono.add_theme_font_override("font", font)
	mono.add_theme_font_size_override("font_size", max(10, int(size * 0.55)))
	mono.add_theme_color_override("font_color", tint)
	mono.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mono.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mono.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(mono)
	return holder
