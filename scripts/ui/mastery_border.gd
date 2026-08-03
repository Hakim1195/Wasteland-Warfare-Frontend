extends Control

# =========================================================================
# BORDURE DE PORTRAIT — MAÎTRISE DE FACTION (§8.135)
# =========================================================================
# IMPLÉMENTATION UNIQUE des 6 tranches de bordure, utilisée par TOUS les sites d'affichage : fiche
# Personnage, sélecteur de titre, draft, profil, Rapport Post-Op. Une seule mise en scène de
# « ce joueur a une maîtrise », donc une seule chance de la rendre incohérente.
#
# 100 % DESSINÉE PAR CODE, aucun asset requis — parti pris maison éprouvé (HazardPlate du menu,
# PowerGlyph de la nav, CoinIcon de la jauge, emblèmes de compagnie §8.126) : quand l'asset manque,
# on dessine. Déposer un jour de vraies textures ne demandera qu'à toucher CE fichier.
#
# ⚠️ VUE PURE (Règle d'Or §6.1) : aucune règle ici. La tranche est une CLÉ calculée par le serveur
# (`mastery.border_tier` → `border_tier` du payload) ; ce script ne sait ni ce qu'est un rang, ni
# où commence le palier or. Il PEINT une clé, c'est tout — le client n'a aucun seuil en dur.
#
# ⚠️ `reduced_motion` (§8.82) : la tranche « prismatic » (rang 50+) est la SEULE animée. Sous ce
# réglage elle est FIGÉE sur une teinte fixe — la bordure reste distinctive (c'est une récompense,
# on ne la retire pas), elle cesse simplement de bouger.
#
# USAGE
#   var b := MasteryBorder.make("gold", 96.0)   # tranche, côté en pixels
#   portrait_container.add_child(b)             # se pose EN SURCOUCHE d'un portrait déjà en place
#   b.tier = "prismatic"                        # re-peint tout seul
#
# La bordure n'intercepte JAMAIS la souris (`MOUSE_FILTER_IGNORE`) : elle se superpose à des
# portraits cliquables sans les neutraliser.

const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1)

# --- PALETTE DES 6 TRANCHES ---------------------------------------------------------------------
# Le registre serveur (`mastery.MASTERY["borders"]`) donne les SEUILS ; ici vivent les COULEURS,
# qui sont une affaire de charte et n'ont rien à faire dans un payload réseau. Les deux listes de
# clés doivent rester alignées — une clé inconnue rend une bordure INVISIBLE (jamais un crash, et
# jamais un ornement gratuit sur un joueur qui n'a rien accompli : c'est aussi le cas du rang 0,
# qui vaut "").
const TIERS := {
	"steel":     {"main": Color(0.671, 0.714, 0.757, 1), "glow": Color(0.812, 0.855, 0.894, 1), "ticks": 2},
	"bronze":    {"main": Color(0.776, 0.478, 0.239, 1), "glow": Color(0.929, 0.647, 0.373, 1), "ticks": 3},
	# ⚠️ SILVER / PLATINUM / PRISMATIC se suivent et doivent rester DISTINCTS EN IMAGE FIXE (défaut
	# vu en capture au premier jet : platine et irisé se confondaient, tous deux cyan). On les a
	# donc écartés — argent NEUTRE (gris blanc, aucune teinte), platine ICY quasi blanc, irisé
	# SATURÉ. La teinte n'est pas le seul discriminant : le nombre de CRANS (4 / 6 / 8) les sépare
	# aussi, ce qui les rend lisibles en daltonisme comme sur une capture désaturée.
	"silver":    {"main": Color(0.800, 0.812, 0.827, 1), "glow": Color(1.0, 1.0, 1.0, 1),       "ticks": 4},
	"gold":      {"main": Color(0.878, 0.698, 0.286, 1), "glow": Color(1.0, 0.886, 0.573, 1),   "ticks": 5},
	"platinum":  {"main": Color(0.847, 0.953, 0.980, 1), "glow": Color(0.749, 0.898, 1.0, 1),   "ticks": 6},
	"prismatic": {"main": Color(0.211, 0.772, 0.851, 1), "glow": Color(1.0, 1.0, 1.0, 1),       "ticks": 8},
}

# Teintes traversées par l'irisation du rang 50+ (une seule boucle, pas un dégradé arc-en-ciel :
# la charte reste gunmetal/cyan/or — l'irisation la cite, elle ne la remplace pas).
const PRISM_HUES := [
	Color(0.211, 0.772, 0.851, 1),   # cyan tactique
	Color(0.878, 0.698, 0.286, 1),   # or
	Color(0.729, 0.510, 0.878, 1),   # améthyste
	Color(0.404, 0.878, 0.678, 1),   # jade
]
const PRISM_PERIOD := 6.0   # secondes pour un tour complet du cycle

@export var tier: String = "":
	set(value):
		tier = str(value)
		queue_redraw()
		set_process(_is_animated())

# Épaisseur du liseré principal. Recalculée depuis le côté à la construction : une bordure de 48 px
# et une de 140 px doivent avoir le MÊME poids visuel, pas la même épaisseur absolue.
var _thickness: float = 3.0
var _phase: float = 0.0


# =========================================================================
# HELPERS DE TEXTE PARTAGÉS (statiques — aucune instance requise)
# =========================================================================
# Ils vivent ICI, avec la bordure, pour une raison simple : ce fichier est DÉJÀ préchargé par les
# cinq écrans qui affichent de la maîtrise. Les isoler dans un second fichier n'ajouterait qu'un
# `preload` de plus à chacun, pour trois fonctions de dix lignes — et ferait exister DEUX endroits
# où « afficher une maîtrise » est défini, ce que tout le chantier cherche à éviter.
# ⚠️ Aucune règle non plus ici : ces fonctions traduisent et concatènent, elles ne décident de rien.

# Clé i18n d'un titre depuis la clé SERVEUR ("veteran" → "TITLE_VETERAN"). "" si aucun titre.
# ⚠️ Le préfixe `TITLE_` est PARTAGÉ avec les titres honorifiques éphémères du Rapport Post-Op
# (TITLE_BUTCHER, TITLE_CONQUEROR… §8.83) : aucune collision de clé aujourd'hui, mais un futur
# titre de maîtrise ne doit pas reprendre l'un de ces six noms.
static func title_i18n_key(title_key: String) -> String:
	var key := str(title_key).strip_edges()
	return "TITLE_" + key.to_upper() if key != "" else ""


# Libellé TRADUIT d'un titre ("VÉTÉRAN"), ou "" si aucun.
static func title_label(title_key: String) -> String:
	var k := title_i18n_key(title_key)
	return TranslationServer.translate(k) if k != "" else ""


# Libellé COMPLET d'un titre équipé, tel qu'affiché sous un pseudo : « VÉTÉRAN — PHALANGES D'ACIER ».
# `title_id` est l'identifiant réseau "<source>:<key>".
#
# ⚠️ LA FACTION EST INDISPENSABLE, pas décorative : le titre porté peut venir d'une AUTRE faction
# que celle jouée (c'est même le cas le plus fréquent — on porte son plus haut fait d'armes). Sans
# elle, un joueur des Éveillés affichant « MAÎTRE » gagné chez les Phalanges deviendrait illisible.
#
# `faction_names` = { faction_id: nom } quand l'appelant possède DÉJÀ le catalogue (Profil, draft) ;
# omis, on retombe sur le catalogue interne mémoïsé ci-dessous — c'est le cas du Rapport Post-Op,
# qui n'a aucune raison de charger dix `.tres` pour une ligne de texte.
# Source inconnue (titre d'événement à venir, faction retirée) → TITRE SEUL plutôt que rien : on
# n'efface pas une récompense parce qu'on ne sait pas la qualifier.
static func title_with_faction(title_id: String, faction_names: Dictionary = {}) -> String:
	var raw := str(title_id).strip_edges()
	if raw == "" or not raw.contains(":"):
		return ""
	var parts := raw.split(":", true, 1)
	var label := title_label(parts[1])
	if label == "":
		return ""
	var names := faction_names if not faction_names.is_empty() else faction_catalogue()
	var fname := str(names.get(parts[0], "")).to_upper()
	if fname == "":
		return label
	return TranslationServer.translate("TITLE_WITH_FACTION") % [label, fname]


# Catalogue { faction_id: nom }, chargé UNE fois par session depuis les `.tres` (§4.3, source unique
# des noms de faction) et mémoïsé. Même recette export-safe que les écrans hub : scan `DirAccess`
# gérant les `.remap`, duck-typing sur `id` (aucune dépendance à un `class_name` global).
# Existe pour les vues qui n'ont PAS de catalogue à elles (le Rapport Post-Op) — celles qui en ont
# un continuent de le passer, sans second chargement.
static var _faction_names_cache: Dictionary = {}

static func faction_catalogue() -> Dictionary:
	if not _faction_names_cache.is_empty():
		return _faction_names_cache
	var dir := DirAccess.open("res://resources/factions/")
	if dir == null:
		return _faction_names_cache
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var clean := fname.trim_suffix(".remap")
			if clean.ends_with(".tres"):
				var path := "res://resources/factions/" + clean
				if ResourceLoader.exists(path):
					var res = load(path)
					# Duck-typing : `Object.get()` ne prend QU'UN argument (pas de valeur par
					# défaut, contrairement à `Dictionary.get`) → on teste `null` à la main.
					if res != null and res.get("id") != null:
						var nm = res.get("name")
						_faction_names_cache[str(res.id)] = str(nm) if nm != null else str(res.id)
		fname = dir.get_next()
	dir.list_dir_end()
	return _faction_names_cache


static func make(tier_key: String, side: float = 96.0) -> Control:
	"""Fabrique une bordure carrée de `side` pixels pour la tranche donnée. `""` (rang 0) produit
	un nœud VALIDE mais qui ne dessine rien : l'appelant n'a jamais à tester avant d'ajouter."""
	var b = (load("res://scripts/ui/mastery_border.gd") as Script).new()
	b.custom_minimum_size = Vector2(side, side)
	b.size = Vector2(side, side)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b._thickness = maxf(2.0, side * 0.032)
	b.tier = tier_key
	return b


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_is_animated())


# Seule la tranche prismatique bouge, et seulement si le joueur n'a pas demandé le contraire.
func _is_animated() -> bool:
	if tier != "prismatic":
		return false
	return not bool(SettingsManager.get_comfort("reduced_motion"))


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, PRISM_PERIOD)
	queue_redraw()


# Couleur principale au temps courant. Pour toutes les tranches sauf « prismatic », c'est une
# constante ; pour celle-ci, une interpolation cyclique — FIGÉE sur la première teinte quand
# `reduced_motion` est actif (la bordure reste prismatique, elle cesse de tourner).
func _main_color() -> Color:
	var entry: Dictionary = TIERS.get(tier, {})
	if entry.is_empty():
		return Color(0, 0, 0, 0)
	if tier != "prismatic":
		return entry["main"]
	if not _is_animated():
		return PRISM_HUES[0]
	var t := (_phase / PRISM_PERIOD) * float(PRISM_HUES.size())
	var i := int(floor(t)) % PRISM_HUES.size()
	var j := (i + 1) % PRISM_HUES.size()
	return PRISM_HUES[i].lerp(PRISM_HUES[j], t - floor(t))


func _draw() -> void:
	var entry: Dictionary = TIERS.get(tier, {})
	if entry.is_empty():
		return   # rang 0 (ou clé inconnue) : aucune bordure, jamais un ornement gratuit.

	var main: Color = _main_color()
	var glow: Color = entry["glow"]
	var ticks: int = int(entry["ticks"])
	var w := size.x
	var h := size.y
	var t := _thickness
	# Longueur des encoches de coin biseautées — signature angulaire de la charte (§2).
	var notch := minf(w, h) * 0.22

	# 1. LISERÉ PRINCIPAL, tracé en 8 segments pour laisser les 4 coins OUVERTS (biseautés).
	#    Un rectangle plein ferait une simple bordure de cadre ; ce sont les coins ouverts qui
	#    donnent le vocabulaire « plaque militaire » du reste de l'interface.
	var half := t * 0.5
	var segs := [
		[Vector2(notch, half), Vector2(w - notch, half)],                 # haut
		[Vector2(w - half, notch), Vector2(w - half, h - notch)],         # droite
		[Vector2(w - notch, h - half), Vector2(notch, h - half)],         # bas
		[Vector2(half, h - notch), Vector2(half, notch)],                 # gauche
	]
	for s in segs:
		draw_line(s[0], s[1], main, t, true)

	# 2. BISEAUX DE COIN à 45° — le liseré « tourne » l'angle au lieu de s'y arrêter net.
	var bevels = [
		[Vector2(half, notch), Vector2(notch, half)],
		[Vector2(w - notch, half), Vector2(w - half, notch)],
		[Vector2(w - half, h - notch), Vector2(w - notch, h - half)],
		[Vector2(notch, h - half), Vector2(half, h - notch)],
	]
	for b in bevels:
		draw_line(b[0], b[1], main, t, true)

	# 3. FILET INTÉRIEUR fin, décalé vers le dedans (profondeur — même recette que les panneaux
	#    de la charte, qui doublent leur bordure d'un filet à 1 px).
	var inset := t * 2.2
	var in_notch := notch * 0.72
	var thin := maxf(1.0, t * 0.34)
	var inner = [
		[Vector2(inset + in_notch, inset), Vector2(w - inset - in_notch, inset)],
		[Vector2(w - inset, inset + in_notch), Vector2(w - inset, h - inset - in_notch)],
		[Vector2(w - inset - in_notch, h - inset), Vector2(inset + in_notch, h - inset)],
		[Vector2(inset, h - inset - in_notch), Vector2(inset, inset + in_notch)],
	]
	for s in inner:
		draw_line(s[0], s[1], Color(main, 0.45), thin, true)

	# 4. CRANS DE RANG : autant de tirets brillants que la tranche est haute (2 pour l'acier, 8 pour
	#    l'irisé). C'est ce qui rend les six tranches lisibles À L'ŒIL sans lire une seule ligne de
	#    texte, y compris pour un daltonien : elles diffèrent par le COMPTE, pas seulement la teinte.
	var span := w - 2.0 * notch
	if span > 0.0 and ticks > 0:
		var gap := span / float(ticks + 1)
		for i in range(ticks):
			var x := notch + gap * float(i + 1)
			draw_line(Vector2(x, half), Vector2(x, half + t * 1.9), glow, thin * 1.4, true)
			draw_line(Vector2(x, h - half), Vector2(x, h - half - t * 1.9), glow, thin * 1.4, true)

	# 5. POINTES DE COIN pleines : quatre petits triangles qui « ferment » visuellement la plaque.
	var tip := notch * 0.34
	for corner in [
		PackedVector2Array([Vector2(0, 0), Vector2(tip, 0), Vector2(0, tip)]),
		PackedVector2Array([Vector2(w, 0), Vector2(w - tip, 0), Vector2(w, tip)]),
		PackedVector2Array([Vector2(w, h), Vector2(w - tip, h), Vector2(w, h - tip)]),
		PackedVector2Array([Vector2(0, h), Vector2(tip, h), Vector2(0, h - tip)]),
	]:
		draw_colored_polygon(corner, Color(glow, 0.85))
