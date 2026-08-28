extends RefCounted
# =================================================================================================
# LA TRANCHÉE — VUE 3D (§8.152 LOT 3D-C) — LES MATÉRIAUX D'ARME.
#
# ADAPTATION de `War-Of-Indipendence/Claude-of-Duty-main/src/weapons/materials.js` (1 215 l.).
# ⚠️ « ADAPTATION », pas « portage » : le cahier §3 l'impose — « à porter en matériaux Godot PBR,
# pas en shaders maison » / « ⛔ ne PAS porter leurs shaders GLSL ». Leur fichier est à 80 % du
# pilotage d'une bibliothèque de surfaces procédurales (triplanaire en espace objet, masques de
# courbure cuits sur GPU, couches de météo) qui n'existe pas ici et que Godot remplace par son
# propre PBR. **Ce qu'on porte, c'est le RAISONNEMENT ; ce qu'on jette, c'est la plomberie.**
#
# ╔═ LA DÉCISION QUI PORTE TOUT LE FICHIER : TROIS CLASSES, SÉPARÉES PAR LA TEINTE ═══════════════╗
# ║ Leur commentaire le dit sans détour, et c'est la seule chose qu'il ne faut surtout pas        ║
# ║ « harmoniser » : la TEINTE est le seul indice de séparation qui survit à une pièce large de   ║
# ║ 40 px en tir à la hanche. D'où trois familles délibérément désaccordées :                     ║
# ║                                                                                               ║
# ║   CLASSE 1 — aluminium anodisé dur (`alu`, `alu_fine`) : diélectrique mat quasi noir, FROID.  ║
# ║              ⚠️ L'anodisation est un REVÊTEMENT d'oxyde, pas du métal nu. Lui donner une      ║
# ║              surface « métal brossé » le fait lire comme du CHROME POLI — « the single        ║
# ║              biggest mistake available on a gun ». D'où `metallic = 0`.                       ║
# ║   CLASSE 2 — polymère moulé (`polymer`, `polymer_tan`, `rubber`) : diélectrique, CHAUD.       ║
# ║   CLASSE 3 — acier (`steel*`, `brass`, `copper`) : `metallic = 1`, donc **pas d'albédo du     ║
# ║              tout** — la couleur EST le F0. Les seuls leviers sont ce F0 et la rugosité.      ║
# ║                                                                                               ║
# ║ Une arme entière en « noir » lit comme un bloc unique. Les trois classes sont ce qui fait     ║
# ║ qu'on distingue la carcasse du garde-main et du canon.                                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️ CE QUI RESTE À CALIBRER — À LIRE AVANT DE JUGER UN RENDU ═══════════════════════════════╗
# ║ Les albédos ci-dessous sont les valeurs LINÉAIRES de la référence (leur `tint` multiplié par  ║
# ║ l'albédo mesuré de leur surface de base — 0,0334 linéaire pour `rubber`, lu sur le GPU et non ║
# ║ deviné). Elles sont TRÈS SOMBRES (~0,01 linéaire) et c'est volontaire chez eux : leur arme    ║
# ║ est « diffuse-dominante », 60 % de ce que l'œil voit est du Fresnel.                          ║
# ║                                                                                               ║
# ║ MAIS ces nombres sont calés sur LEUR exposition, LEUR tonemap et LEUR intensité               ║
# ║ d'environnement. Godot n'a ni le même tonemap ni la même échelle. **Reprises telles quelles,  ║
# ║ elles peuvent rendre une arme presque noire.** Deux boutons sont donc exposés, et un seul     ║
# ║ suffit à recalibrer l'ensemble sans toucher aux rapports entre familles :                     ║
# ║   • `ALBEDO_GAIN` — multiplie TOUS les albédos diélectriques d'un coup ;                      ║
# ║   • `ENV_OCCLUSION` — l'environnement que voit une arme à l'épaule (cf. plus bas).            ║
# ║                                                                                               ║
# ║ ⛔ LA CALIBRATION SE TRANCHE PAR CAPTURES (cahier §2.2quater), et les 9 captures de référence ║
# ║ **ne sont pas encore déposées** dans `assets/reference/claude_of_duty/`. Tant qu'elles        ║
# ║ manquent, personne — agent ou humain — n'est en position de dire « c'est fidèle ». Ces        ║
# ║ valeurs sont un POINT DE DÉPART honnête, pas un résultat validé.                              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# CE QUE GODOT DONNE GRATUITEMENT, ET QU'ILS ONT DÛ ALLER CHERCHER :
#   • `specular = 0` : ils ne pouvaient pas annuler le Fresnel d'un `MeshStandardMaterial`
#     (« it hard-codes F0 = 0.04 ») et ont dû passer à `MeshPhysicalMaterial` pour le seul
#     matériau `cavity`. `StandardMaterial3D.specular` le fait nativement.
#   • HDR, tonemap, bloom, ombres en cascade, GTAO : tout `src/render/`, non porté (cahier §0).
#
# CE QUE GODOT N'A PAS, ET QUI EST DONC APPROXIMÉ (écarts assumés, listés ici et nulle part ailleurs) :
#   • `iridescence` (le film mince d'un traitement antireflet) → approché par `clearcoat`.
#   • `sheen` (le lobe rasant magenta de l'optique) → approché par `rim` + `rim_tint`.
#   • `anisotropy` du brossage : `StandardMaterial3D` l'a (`anisotropy`), mais il exige un
#     `TANGENT` cohérent que nos maillages fusionnés n'ont pas. Laissé à zéro, à revoir si une
#     capture le réclame.
#   • l'usure d'arête ne peut pas moduler la RUGOSITÉ ni la MÉTALLICITÉ par sommet sans shader —
#     voir `get_worn()`, qui explique ce qu'on récupère quand même, et à quel prix.
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")


# ╔═ `ENV_OCCLUSION` — combien de ciel voit vraiment une arme à l'épaule ═════════════════════════╗
# ║ 0,24 : la tête, la poitrine et les bras du tireur en cachent le reste, et l'optique, le       ║
# ║ montage et le puits de chargeur s'ombrent mutuellement. Sans ça, l'arme échantillonne tout le ║
# ║ ciel pendant que la tranchée autour d'elle est à l'ombre — « the single most obvious          ║
# ║ "sticker pasted on the frame" tell ».                                                         ║
# ║ ⚠️ EN GODOT, ÇA NE SE POSE PAS SUR LE MATÉRIAU : il n'y a pas d'`envMapIntensity` par         ║
# ║ matériau. Le viewmodel vivant dans son PROPRE `SubViewport` (cahier §4.3), c'est l'           ║
# ║ `Environment` de ce sous-viewport qui doit porter ce facteur. **Le lot 3D-H doit l'appliquer  ║
# ║ là — cette constante est le contrat, pas l'application.**                                     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const ENV_OCCLUSION := 0.24

# ╔═ `ALBEDO_GAIN` — LE BOUTON DE RECALIBRATION, ET LA MESURE QUI L'A RÉGLÉ ══════════════════════╗
# ║ Il multiplie tous les albédos DIÉLECTRIQUES (classes 1 et 2) d'un seul coup. Il ne touche PAS ║
# ║ aux métaux : leur « couleur » est un F0, une propriété physique, pas une exposition.          ║
# ║                                                                                               ║
# ║ 3,0 n'est pas un chiffre choisi à l'œil. MESURÉ le 2026-08-27 en comparant le rendu de         ║
# ║ l'optique du M4A1 à la capture de référence `arme_m4a1_ads.png` :                             ║
# ║                                                                                               ║
# ║   RÉFÉRENCE — corps de l'optique, trois zones identifiées à la grille :                        ║
# ║       médiane 15 · 34 · 61     (moleture des flancs : 9 et 44)                                 ║
# ║       …contre un mur ensoleillé à 139 : l'arme est un objet FRANCHEMENT SOMBRE, entre le       ║
# ║       quart et le dixième du fond. Ce n'est pas une impression, c'est la mesure.               ║
# ║                                                                                               ║
# ║   NOTRE RENDU — balayage du gain, médiane de luminance de l'objet :                            ║
# ║       gain  1,0 ->   2,1   (écrasé au noir : aucune forme lisible)                             ║
# ║       gain  3,0 ->  25,0   ← retenu, en plein dans la bande 15-45 de la référence              ║
# ║       gain  6,0 ->  66,3   (déjà plus clair que la référence)                                  ║
# ║       gain 10,0 -> 117,3   · gain 16,0 -> 171,1 · gain 24,0 -> 209,9 (l'arme devient grise)    ║
# ║                                                                                               ║
# ║ ⚠️ CE QUE CETTE CALIBRATION N'EST PAS : un accord au pixel. Leur scène est une rue en plein    ║
# ║ soleil, notre banc a son propre éclairage, et la lumière DÉFINITIVE de la tranchée appartient  ║
# ║ au lot C du §8.151. Ce réglage garantit que l'arme LIT comme un objet sombre à forme lisible,  ║
# ║ pas qu'elle a les mêmes octets. Il devra être revérifié une fois la lumière de la tranchée     ║
# ║ posée — c'est précisément pour ça que c'est UN SEUL nombre.                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const ALBEDO_GAIN := 3.0


# =================================================================================================
# LE REGISTRE
# =================================================================================================
# Un dictionnaire PUR : aucune ressource n'est créée ici, seulement décrite. C'est ce qui permet
# aux sondes de le lire sans instancier quoi que ce soit, et aux tests de porter sur le REGISTRE
# plutôt que sur des valeurs recopiées en dur (règle projet).
#
# Champs : `class` (1/2/3, la famille) · `albedo` (LINÉAIRE ; pour un métal, c'est le F0) ·
# `roughness` · `metallic` · `specular` (ignoré si metallic = 1) ·
# `wear_color` (linéaire, l'arête mise à NU) · `wear_amount` (0..1, l'amplitude de l'usure) ·
# ⚠️ Les `wear_color` sont les hex de la référence lus comme des valeurs LINÉAIRES, et non
# reconvertis depuis le sRGB. Ce n'est pas une négligence : reconvertis, ils tombent SOUS l'albédo
# de base de plusieurs entrées (l'acier phosphaté, le laiton, les gants), ce qui rendrait l'arête
# usée plus SOMBRE que le méplat — l'inverse exact de « bare bright metal on the chamfers », et
# une valeur que l'astuce de `get_worn` écrêterait en silence. La sonde M5 verrouille ce sens.
# `wear_roughness` / `wear_metallic` (⚠️ documentés mais NON appliqués — cf. `get_worn`).
const SPECS := {
	# ── CLASSE 1 : aluminium anodisé dur — carcasses, rails, garde-mains ───────────────────────
	"alu": {
		"class": 1, "albedo": Color(0.00952, 0.01009, 0.01166),
		"roughness": 0.42, "metallic": 0.0, "specular": 0.11,
		"wear_color": Color(0.2039, 0.2196, 0.2392), "wear_amount": 0.20,
		"wear_roughness": 0.54, "wear_metallic": 0.8,
	},
	# La même anodisation, à grain plus fin — petites pièces et surfaces vues de près.
	"alu_fine": {
		"class": 1, "albedo": Color(0.00451, 0.00481, 0.00551),
		"roughness": 0.35, "metallic": 0.0, "specular": 0.08,
		"wear_color": Color(0.2510, 0.2667, 0.2902), "wear_amount": 0.18,
		"wear_roughness": 0.50, "wear_metallic": 0.8,
	},
	# ── CLASSE 3 : aciers — `metallic = 1`, donc `albedo` EST le F0 ───────────────────────────
	# Phosphatation au manganèse : une vraie conversion de surface, l'une des finitions
	# métalliques les plus sombres qui existent. F0 nettement sous celui de l'acier neutre.
	"steel": {
		"class": 3, "albedo": Color(0.170, 0.162, 0.152),
		"roughness": 0.54, "metallic": 1.0, "specular": 0.5,
		"wear_color": Color(0.3843, 0.4000, 0.4196), "wear_amount": 0.16,
		"wear_roughness": 0.26, "wear_metallic": 1.0,
	},
	# Suie de bouche : une poudre DIÉLECTRIQUE posée SUR la phosphatation — d'où `metallic` 0,12
	# et non 1. Le fond métallique transparaît encore un peu.
	"steel_soot": {
		"class": 3, "albedo": Color(0.022, 0.020, 0.018),
		"roughness": 0.80, "metallic": 0.12, "specular": 0.10,
		"wear_color": Color(0.2275, 0.2353, 0.2431), "wear_amount": 0.06,
		"wear_roughness": 0.55, "wear_metallic": 1.0,
	},
	# Acier nitruré / huilé : celui-là EST poli — culasse, levier d'armement, guidon.
	"steel_bright": {
		"class": 3, "albedo": Color(0.155, 0.155, 0.164),
		"roughness": 0.58, "metallic": 1.0, "specular": 0.5,
		"wear_color": Color(0.3608, 0.3765, 0.4000), "wear_amount": 0.16,
		"wear_roughness": 0.18, "wear_metallic": 1.0,
	},
	"steel_black": {
		"class": 3, "albedo": Color(0.155, 0.158, 0.165),
		"roughness": 0.44, "metallic": 1.0, "specular": 0.5,
		"wear_color": Color(0.4157, 0.4353, 0.4588), "wear_amount": 0.24,
		"wear_roughness": 0.22, "wear_metallic": 1.0,
	},
	# ── CLASSE 2 : polymères moulés — poignées, chargeurs, plaques de couche ───────────────────
	"polymer": {
		"class": 2, "albedo": Color(0.00748, 0.00705, 0.00641),
		"roughness": 0.46, "metallic": 0.0, "specular": 0.13,
		"wear_color": Color(0.2431, 0.2549, 0.2706), "wear_amount": 0.22,
		"wear_roughness": 0.46, "wear_metallic": 0.0,
	},
	# La variante FAUVE. C'est elle qui porte l'essentiel de la chaleur de la classe 2 : sans une
	# pièce tan quelque part, l'arme redevient un bloc monochrome.
	"polymer_tan": {
		"class": 2, "albedo": Color(0.02071, 0.01663, 0.01196),
		"roughness": 0.46, "metallic": 0.0, "specular": 0.14,
		"wear_color": Color(0.3608, 0.3255, 0.2510), "wear_amount": 0.22,
		"wear_roughness": 0.44, "wear_metallic": 0.0,
	},
	# Élastomère : réflectance spéculaire ~0,02, la MOITIÉ de celle du verre. D'où `specular` bas.
	"rubber": {
		"class": 2, "albedo": Color(0.00491, 0.00458, 0.00424),
		"roughness": 0.60, "metallic": 0.0, "specular": 0.12,
		"wear_color": Color(0.1412, 0.1490, 0.1647), "wear_amount": 0.18,
		"wear_roughness": 0.72, "wear_metallic": 0.0,
	},
	# ── CLASSE 3 (suite) : métaux non ferreux — douilles et amorces ────────────────────────────
	# ⚠️ Le `tint` de la référence dépasse 1 (2,3 / 1,58 / 0,74) parce qu'il MULTIPLIE une base
	# sombre. Ce qui compte est le RAPPORT des canaux ; on le renormalise sur un F0 de laiton
	# physiquement plausible plutôt que de recopier un multiplicateur qui n'a pas de sens ici.
	"brass": {
		"class": 3, "albedo": Color(0.720, 0.500, 0.240),
		"roughness": 0.44, "metallic": 1.0, "specular": 0.5,
		"wear_color": Color(0.9098, 0.7882, 0.5412), "wear_amount": 0.12,
		"wear_roughness": 0.12, "wear_metallic": 1.0,
	},
	"copper": {
		"class": 3, "albedo": Color(0.750, 0.470, 0.360),
		"roughness": 0.45, "metallic": 1.0, "specular": 0.5,
		"wear_color": Color(0.8510, 0.6353, 0.4431), "wear_amount": 0.20,
		"wear_roughness": 0.20, "wear_metallic": 1.0,
	},
	# ── Mains et manches (lot 3D-D) ────────────────────────────────────────────────────────────
	# ⭐ §2.2bis B des captures : gants de cuir FAUVE/TAN, doigts distincts. Les valeurs de la
	# référence sont un brun chaud sombre ; c'est SON exposition qui les rend fauves à l'écran.
	# Ne pas les « éclaircir » avant la comparaison par captures.
	"glove": {
		"class": 2, "albedo": Color(0.0475, 0.0388, 0.0318),
		"roughness": 0.86, "metallic": 0.0, "specular": 0.10,
		"wear_color": Color(0.1647, 0.1294, 0.0941), "wear_amount": 0.34,
		"wear_roughness": 0.72, "wear_metallic": 0.0,
	},
	"glove_pad": {
		"class": 2, "albedo": Color(0.0295, 0.0238, 0.0200),
		"roughness": 0.88, "metallic": 0.0, "specular": 0.15,
		"wear_color": Color(0.1412, 0.1098, 0.0784), "wear_amount": 0.40,
		"wear_roughness": 0.78, "wear_metallic": 0.0,
	},
	"glove_seam": {
		"class": 2, "albedo": Color(0.0875, 0.0715, 0.0585),
		"roughness": 0.84, "metallic": 0.0, "specular": 0.11,
		"wear_color": Color(0.2275, 0.1765, 0.1255), "wear_amount": 0.50,
		"wear_roughness": 0.70, "wear_metallic": 0.0,
	},
	"sleeve": {
		"class": 2, "albedo": Color(0.0400, 0.0380, 0.0345),
		"roughness": 0.90, "metallic": 0.0, "specular": 0.09,
		"wear_color": Color(0.2902, 0.2510, 0.2039), "wear_amount": 0.50,
		"wear_roughness": 0.90, "wear_metallic": 0.0,
	},
}

# Les clés « spéciales » : elles ne sortent PAS du registre ci-dessus parce qu'elles ne sont pas
# des surfaces de la bibliothèque mais des objets optiques à part entière.
const SPECIAL_KEYS := ["cavity", "optic_tube", "glass", "lens_ring", "lens_vig"]


# Toutes les clés valides — c'est CE tableau que les sondes et les lots suivants interrogent,
# jamais une liste recopiée à la main.
static func all_keys() -> Array:
	var out := SPECS.keys()
	out.append_array(SPECIAL_KEYS)
	return out


static func has_key(key: String) -> bool:
	return SPECS.has(key) or SPECIAL_KEYS.has(key)


# =================================================================================================
# FABRIQUE
# =================================================================================================
# ⚠️ Un cache par INSTANCE, pas un cache statique : deux armes affichées côte à côte (le sélecteur
# d'arme) doivent pouvoir vivre et mourir indépendamment. La référence fait pareil (`this.cache`),
# et son commentaire est clair : « the library instance being tuned here is ours alone ».
var _cache := {}


# Le matériau NU, sans usure d'arête. C'est celui des pièces qu'on ne voit pas de près, et le
# repli quand le masque de courbure n'a pas été cuit.
func get_material(key: String) -> StandardMaterial3D:
	var ck := "plain:" + key
	if _cache.has(ck):
		return _cache[ck]
	var m := _build(key, false)
	_cache[ck] = m
	return m


# ╔═ `get_worn` — L'USURE D'ARÊTE SANS UN SEUL SHADER ════════════════════════════════════════════╗
# ║ L'ASTUCE, qui vaut d'être comprise avant d'être modifiée : on ne pose PAS l'albédo de base sur ║
# ║ le matériau pour l'éclaircir ensuite (la couleur de sommet ne sait que MULTIPLIER, donc que    ║
# ║ FONCER — impossible d'aller vers une arête plus CLAIRE). On fait l'inverse :                   ║
# ║                                                                                                ║
# ║   `albedo_color` porte la couleur d'USURE (la plus claire des deux) ;                          ║
# ║   la couleur de sommet vaut `base / usure` sur un méplat (donc elle FONCE vers la base)        ║
# ║   et 1 sur une arête (donc elle laisse passer l'usure entière).                                ║
# ║                                                                                                ║
# ║ Tout reste dans [0, 1], aucun shader n'est écrit, et le cahier §3 est respecté à la lettre.    ║
# ║                                                                                                ║
# ║ ⚠️ CE QU'ON PERD, ET IL FAUT LE SAVOIR : la couleur de sommet ne module que l'ALBÉDO. La       ║
# ║ rugosité et la métallicité de l'usure (`wear_roughness`, `wear_metallic`) sont dans le         ║
# ║ registre mais **ne sont pas appliquées** — il faudrait un shader pour ça.                      ║
# ║ Ce n'est pas anodin sur un DIÉLECTRIQUE (une arête usée est aussi plus lisse). Ça l'est        ║
# ║ beaucoup moins sur un MÉTAL : à `metallic = 1`, l'albédo EST le F0, donc éclaircir l'albédo    ║
# ║ sur les arêtes éclaircit bel et bien leur reflet — l'essentiel de l'effet passe.               ║
# ║ Dette consignée, à rouvrir si une comparaison par captures la réclame.                         ║
# ╚════════════════════════════════════════════════════════════════════════════════════════════════╝
func get_worn(key: String) -> StandardMaterial3D:
	var ck := "worn:" + key
	if _cache.has(ck):
		return _cache[ck]
	var m := _build(key, true)
	_cache[ck] = m
	return m


# Cuit le masque de courbure du maillage PUIS le convertit en couleurs de sommet pour `key`.
# À appeler sur le maillage FINAL (après fusion) — c'est le pendant de `get_worn`.
# Rend `false` si la clé n'a pas d'usure définie (les optiques, par exemple) : dans ce cas
# l'appelant doit utiliser `get_material()` et non `get_worn()`.
static func apply_wear_mask(mesh, key: String, gain := 12.0, bias := 0.0) -> bool:
	if mesh == null or not SPECS.has(key):
		return false
	var spec: Dictionary = SPECS[key]
	mesh.bake_curvature(gain, bias)
	var base: Color = spec["albedo"]
	var worn := _effective_wear(spec)
	# `base / usure`, canal par canal — la couleur qui RAMÈNE l'usure vers la base sur un méplat.
	var flat := Color(
		clampf(base.r / maxf(worn.r, 1e-6), 0.0, 1.0),
		clampf(base.g / maxf(worn.g, 1e-6), 0.0, 1.0),
		clampf(base.b / maxf(worn.b, 1e-6), 0.0, 1.0), 1.0)
	for i in mesh.colors.size():
		# Le masque est en niveaux de gris : n'importe quel canal le porte.
		var t: float = mesh.colors[i].r
		mesh.colors[i] = flat.lerp(Color.WHITE, t)
	return true


# La couleur d'usure RÉELLEMENT atteinte au sommet d'une arête : la couleur nue de l'arête n'est
# jamais montrée à 100 %, `wear_amount` en donne l'amplitude.
static func _effective_wear(spec: Dictionary) -> Color:
	var base: Color = spec["albedo"]
	var wear: Color = spec.get("wear_color", base)
	var amount: float = spec.get("wear_amount", 0.0)
	var c := base.lerp(wear, amount)
	# Garde : l'astuce de `get_worn` exige que l'usure soit au moins aussi CLAIRE que la base,
	# sinon la couleur de sommet devrait dépasser 1. Aucune entrée du registre ne viole ça
	# aujourd'hui ; ce max le rend impossible demain.
	return Color(maxf(c.r, base.r), maxf(c.g, base.g), maxf(c.b, base.b), 1.0)


func _build(key: String, worn: bool) -> StandardMaterial3D:
	match key:
		"cavity":
			return _cavity()
		"optic_tube":
			return _optic_tube()
		"glass":
			return _glass()
		"lens_ring":
			return _lens_ring()
		"lens_vig":
			return _lens_vignette()
	var m := StandardMaterial3D.new()
	if not SPECS.has(key):
		# Repli VISIBLE et non silencieux : un magenta criard vaut mieux qu'une pièce noire dont
		# personne ne remarque qu'elle a perdu son matériau.
		push_warning("trench_wmaterials : clé de matériau inconnue « %s » — repli magenta." % key)
		m.albedo_color = Color(1, 0, 1)
		return m
	var spec: Dictionary = SPECS[key]
	var metallic: float = spec["metallic"]
	var base: Color = spec["albedo"]
	# `ALBEDO_GAIN` ne s'applique QU'AUX DIÉLECTRIQUES : sur un métal, la couleur est un F0, une
	# propriété physique — la « remonter » ne recalibrerait rien, ça inventerait un autre métal.
	if metallic < 0.5:
		base = Color(base.r * ALBEDO_GAIN, base.g * ALBEDO_GAIN, base.b * ALBEDO_GAIN, 1.0)
	if worn:
		var w := _effective_wear(spec)
		if metallic < 0.5:
			w = Color(w.r * ALBEDO_GAIN, w.g * ALBEDO_GAIN, w.b * ALBEDO_GAIN, 1.0)
		m.albedo_color = w
		m.vertex_color_use_as_albedo = true
	else:
		m.albedo_color = base
	m.roughness = spec["roughness"]
	m.metallic = metallic
	# ⚠️ `metallic_specular`, PAS `specular` : ce dernier n'existe pas sur `BaseMaterial3D` en
	# Godot 4. Il est silencieusement absorbé par la table de remap Godot 3.x, qui se contente d'un
	# WARNING — la valeur n'est JAMAIS appliquée et le matériau garde son 0,5 par défaut. Vérifié
	# dans le moteur (`get_property_list`).
	m.metallic_specular = spec["specular"]
	# ⚠️ Le viewmodel est dessiné avec son propre plan proche : rien de lui ne doit écrire dans les
	# cascades d'ombre du monde. C'est le `shadowSide` de la référence, dit en Godot.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `cavity` — VRAIMENT NOIR, VRAIMENT MAT, et surtout SANS AUCUN LOBE SPÉCULAIRE.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Toutes les gravures, l'âme du canon et les évents de l'arme utilisent ce matériau. Le moindre
# reste de Fresnel et ils s'allument tous en incidence rasante — la référence décrit un
# « croissant clair peint en travers du bas de la lunette ». Elle a dû changer de CLASSE de
# matériau pour l'obtenir ; `StandardMaterial3D.specular = 0` le donne directement.
func _cavity() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.0031, 0.0037, 0.0044)
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# Le corps de l'optique vu de l'INTÉRIEUR : sombre, très mat, à peine spéculaire.
func _optic_tube() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.0065, 0.0072, 0.0080)
	m.roughness = 0.92
	m.metallic = 0.0
	m.metallic_specular = 0.12
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `glass` — LA LENTILLE DE L'OPTIQUE. ⭐ Pièce contractuelle (§2.2bis C des captures).
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Un traitement antireflet à large bande est un FILM MINCE : sa réflexion résiduelle change de
# teinte avec l'angle — vert en incidence normale (le milieu du spectre, que le traitement ne sait
# pas annuler), puis violet, puis magenta vers 70°. C'est CE virage qui dit « il y a du verre dans
# le tube » ; sans lui la lentille lit comme un TROU.
#
# ⚠️ ÉCART ASSUMÉ : `StandardMaterial3D` n'a ni `iridescence` ni `sheen`. On les approche par
# `clearcoat` (le film) et `rim` (le lobe rasant). Ce n'est pas la même physique, c'est la même
# LECTURE. Le verdict revient aux captures.
# ⚠️ L'opacité reste BASSE (0,1) : c'est l'ABSORPTION. À 0,3 la lunette lit comme un verre fumé et
# le monde derrière devient boueux.
func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.0055, 0.0110, 0.0158, 0.10)
	m.roughness = 0.03
	m.metallic = 0.0
	m.metallic_specular = 1.0
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.03
	m.rim_enabled = true
	m.rim = 0.42
	m.rim_tint = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return m


# L'arc clair juste à l'intérieur du bord de l'objectif : en regardant dans une vraie lentille
# traitée, l'indice le plus reconnaissable est ce reflet fin et vif de l'intérieur de la bague.
# ⚠️ C'est un phénomène de la LENTILLE, pas de la bague : il vit sur son propre anneau de 0,4 mm,
# non éclairé et ADDITIF, posé sur le verre. Le mettre sur la géométrie de la bague donnait « un
# gros anneau crème ».
func _lens_ring() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.624 * 0.14, 0.769 * 0.14, 0.847 * 0.14, 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


# Rampe alpha radiale, 1 au bord et 0 au centre : une vraie lunette s'assombrit de 6 à 8 % vers le
# bord de sa pupille de sortie, parce que le diaphragme de champ et la paroi du tube mangent les
# rayons extérieurs. Ce lent assombrissement est une grande partie de ce qui distingue « regarder
# à travers du verre » de « regarder à travers un trou ».
func _lens_vignette() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 1)
	m.albedo_texture = _rim_ramp()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


# La rampe elle-même, générée (aucun fichier d'asset — c'est la contrainte fondatrice du portage).
static func _rim_ramp() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.88, 1.0])
	g.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.45),
		Color(0, 0, 0, 1.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t
