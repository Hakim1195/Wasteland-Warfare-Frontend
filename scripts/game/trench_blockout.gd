extends Node3D
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — LE BLOCKOUT : l'arène 3D en volumes gris, SOURCE DE VÉRITÉ géométrique.
#
# Une scène à DEUX MÉTIERS (§4.1), et c'est délibéré :
#   1. OUTIL DE CALIBRATION — `tools/gen_trench_angles.gd` l'instancie pour projeter la table
#      angulaire, `tools/gen_trench_renders.gd` la photographie pour l'img2img du LOT E ;
#   2. SCÈNE DE PRODUCTION — le `SubViewport` 3D de `trench_fp.gd` l'instancie pour ses REPÈRES
#      (poses de caméra, plans de soldats), et l'affiche telle quelle tant qu'aucun décor
#      pré-rendu n'est déposé (le greybox est le placeholder jouable, doctrine du dépôt).
#
# ⚠️ AUCUNE COORDONNÉE EN DUR ICI NI DANS LE .tscn : tout est bâti au `_ready()` depuis
# `trench_geometry.gd`. C'est la garantie mécanique que le blockout, la table angulaire, les rendus
# et le serveur parlent de la MÊME arène — la désynchronisation géométrique est LE bug fatal de ce
# chantier, on la rend impossible plutôt que de la surveiller.
#
# PERF (critère de recette §5.7) : `MeshInstance3D` + `BoxMesh` plutôt que CSG — les CSG
# recalculent leur maillage et pèsent inutilement sous GL Compatibility. Une douzaine de boîtes,
# un `DirectionalLight3D`, aucune ombre dynamique coûteuse : le budget tient largement.
# =================================================================================================

const Geo := preload("res://scripts/game/trench_geometry.gd")

# Longueur de front bâtie (au-delà des positions, pour que le décor ne s'arrête pas net à l'écran).
const FRONT_OVERSHOOT := 10.0
# Teintes du greybox — neutres et DIFFÉRENCIÉES : un greybox illisible ne se recette pas.
# ⚠️ Elles NE SONT PLUS le rendu nominal : depuis le pivot « monde 3D + ciel peint », le nominal est
# le monde TEXTURÉ ci-dessous, et ces teintes sont le REPLI quand une matière manque sur disque.
const COL_GROUND := Color(0.30, 0.29, 0.27)
const COL_PARAPET := Color(0.46, 0.44, 0.40)
const COL_TRENCH := Color(0.20, 0.19, 0.18)
const COL_WALL := Color(0.26, 0.25, 0.23)

# ╔═ LE PIVOT : LE CIEL EST PEINT ET IL EST LOIN, LE RESTE EST DE LA VRAIE 3D ════════════════════╗
# ║ Un décor peint PLAT ne peut pas suivre une caméra qui tourne : un pan linéaire diverge d'une   ║
# ║ projection en tangente (~11 % à 32°), et un pas de côté lui demande une parallaxe qu'il ne     ║
# ║ sait rendre qu'en la comptant deux fois. Les deux défauts ont été mesurés dans le code de      ║
# ║ §8.139.1, après un essai qui a dégradé le jeu.                                                 ║
# ║                                                                                                ║
# ║ On change donc le RÔLE de la peinture au lieu de la corriger : elle ne sert plus que de CIEL,  ║
# ║ posé sur un arc de cylindre à 300 m. À cette distance, les 4 m d'un pas de côté valent          ║
# ║   atan(4/300) = 0,76° de parallaxe — sous le pixel, donc invisible PAR CONSTRUCTION.           ║
# ║ Aucun shader de compensation, aucun pan : le ciel est un objet 3D ordinaire que la caméra      ║
# ║ regarde, et il répond juste à tout angle parce qu'il EST à sa place.                           ║
# ║                                                                                                ║
# ║ ⚠️ ET LA LIGNE D'HORIZON APPARTIENT DÉSORMAIS À LA GÉOMÉTRIE : le sol lointain rencontre l'arc ║
# ║ de ciel à 300 m. Toute la lutte des sessions précédentes pour « poser l'horizon à 50 % de la   ║
# ║ hauteur » disparaît — c'était un problème d'images plates, il n'en reste rien.                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const TEXTURE_DIR := "res://assets/images/trench/textures/"
const SKY_PATH := "res://assets/images/trench/sky_panorama.png"

# Rayon du ciel ⚙. 300 m est le seuil au-delà duquel la parallaxe d'un pas de côté passe sous le
# pixel (cf. pavé ci-dessus). La caméra porte `far = 400` : le laisser croître demanderait de
# rouvrir CE réglage-là aussi.
const SKY_RADIUS := 300.0
# ╔═ ⚠️ DEUX ARCS, ET C'EST LA CORRECTION DU §8.141 ══════════════════════════════════════════════╗
# ║ L'arc valait ±100°, dimensionné quand le débattement de lacet était de ±32°. Il est passé à     ║
# ║ ±58° (12 m) puis ±60,3° (9 m), et le demi-champ horizontal vaut ~43° en 16:9 : la direction de  ║
# ║ vue extrême atteint donc **103°**, soit 3° AU-DELÀ du ciel. Un liseré du dégradé de secours     ║
# ║ (brun, rien à voir avec le panorama) apparaîtrait au bord de l'écran en visée extrême — et      ║
# ║ personne ne l'aurait vu sans regarder une capture prise à plein débattement.                    ║
# ║                                                                                                 ║
# ║ ⚠️ ÉLARGIR L'ARC EN GARDANT UNE SEULE COTE ÉTIRERAIT LE PANORAMA de 30 % : on repeindrait une   ║
# ║ image déjà validée, pour une bande de 3°. On sépare donc les deux rôles :                       ║
# ║   • `SKY_ARC_DEG`       = la GÉOMÉTRIE bâtie (large, gratuite : 144 triangles) ;                ║
# ║   • `SKY_IMAGE_ARC_DEG` = l'arc sur lequel l'IMAGE est mappée — INCHANGÉ, donc la composition   ║
# ║     que Hakim a validée reste au pixel près dans les ±100° qui comptent.                         ║
# ║ Au-delà, `u` sort de [0,1] et le mode « pas de répétition » CLAMPE : la colonne de bord du       ║
# ║ panorama (une ligne d'arbres noyée de brume) s'étire horizontalement. Invisible, et surtout      ║
# ║ jamais un trou. La hauteur de l'arc se déduit de l'arc de l'IMAGE, sans quoi le panorama         ║
# ║ perdrait son rapport d'aspect.                                                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const SKY_ARC_DEG := 260.0
const SKY_IMAGE_ARC_DEG := 200.0
const SKY_SEGMENTS := 72
# Jupe sous l'horizon : elle passe DERRIÈRE le sol lointain. Elle n'est jamais vue, elle interdit
# seulement qu'un liseré de vide apparaisse si le sol et l'arc se ratent d'un cheveu.
const SKY_SKIRT := 40.0
# Hauteur de repli quand le panorama manque (l'arc est alors un dégradé procédural).
const SKY_FALLBACK_HEIGHT := 260.0

# ╔═ LE SOL LOINTAIN — CE QUI FAIT EXISTER L'HORIZON ═════════════════════════════════════════════╗
# ║ Le blockout ne bâtissait le sol qu'ENTRE les deux tranchées (33,8 m). Au-delà : rien, donc le  ║
# ║ vide transparent du SubViewport. Avec un décor peint par-dessus, ça ne se voyait pas ; avec un ║
# ║ ciel qui commence à 300 m, ça se verrait immédiatement — une bande de néant entre le parapet   ║
# ║ d'en face et l'horizon. On bâtit donc un CADRE de sol autour de l'arène, jusqu'au pied de       ║
# ║ l'arc. ⚠️ Un cadre, et non une nappe pleine : une nappe passerait AU-DESSUS des planchers de   ║
# ║ tranchée (qui sont 1 m plus bas) et boucherait les deux tranchées.                             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const FAR_GROUND_EXTENT := 340.0

# Mètres réels représentés par une tuile ⚙ — l'échelle de chaque matière.
const MUD_METRES := 2.0
const FAR_MUD_METRES := 14.0        # au loin, une tuile serrée moirerait : on l'étale
const JUTE_METRES := 2.4            # un sac de jute fait ~0,5 m : ~5 sacs par tuile
const PLANK_METRES := 1.7
const EARTH_METRES := 2.2

# Racines nommées : `trench_fp.gd` et les outils s'y accrochent (jamais par index d'enfant).
var poses_root: Node3D          # les 10 Marker3D de MON camp
var enemy_root: Node3D          # les 5 Marker3D des positions ADVERSES (ancrage du soldat)
var geometry_root: Node3D       # le monde LOINTAIN (masquable : un décor peint le remplace)
# ╔═ MA PROPRE TRANCHÉE VIT À PART, ET ELLE NE SE MASQUE PAS AVEC LE RESTE ═══════════════════════╗
# ║ ⚠️⚠️ DÉFAUT VÉCU EN PARTIE RÉELLE (§8.139.1). `set_geometry_visible(false)` masquait TOUT dès   ║
# ║ qu'un décor peint était déposé — y compris `NearParapet`, que le commentaire de ce fichier      ║
# ║ appelle lui-même « le parapet de sacs qui décide de tout le jeu ». Le joueur se retrouvait      ║
# ║ DEBOUT EN TERRAIN DÉCOUVERT, avec pour seule couverture une bande peinte de 77 px au bas du     ║
# ║ décor : elle n'occulte rien, ne tourne pas avec la caméra, ne se décale pas quand on fait un    ║
# ║ pas. Verdict du testeur, littéral : « il n'y a pas de tranchée ».                               ║
# ║ Un décor remplace le LOINTAIN (le no man's land, la tranchée d'en face). Il ne remplace JAMAIS  ║
# ║ le volume derrière lequel le joueur s'abrite : celui-là doit rester de la vraie géométrie, pour ║
# ║ occulter juste et bouger juste.                                                                 ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
var cover_root: Node3D          # MA tranchée : plancher, mur arrière, parapet — TOUJOURS rendue
var sky_root: Node3D            # l'arc de ciel peint à 300 m
var props_root: Node3D          # barbelés et débris — décoratifs, JAMAIS occultants (cf. §accessoires)


func _ready() -> void:
	_build()


# Reconstruction complète — idempotente, appelable par un outil après un changement de cote.
func _build() -> void:
	for child in get_children():
		child.queue_free()
	geometry_root = _named_child("Geometry")
	cover_root = _named_child("Cover")
	sky_root = _named_child("Sky")
	props_root = _named_child("Props")
	poses_root = _named_child("Poses")
	enemy_root = _named_child("EnemyAnchors")
	_build_sky()
	_build_terrain()
	_build_props()
	_build_poses()
	_build_light()


func _named_child(node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	return node


# --- Matières -------------------------------------------------------------------------------
# La tuile d'une matière, ou `null` si le fichier n'est pas déposé. ⚠️ `ResourceLoader.exists` et
# SURTOUT PAS `FileAccess.file_exists` : ce dernier échoue en build exporté (leçon `company_emblems`
# §8.126, déjà payée une fois sur ce dépôt).
# ⚙ Interrupteur d'OUTILLAGE seulement : il force le repli greybox sans toucher au disque, pour que
# la mesure de performance puisse comparer les DEUX rendus dans le même processus. Le jeu ne le pose
# jamais. (Sans lui, comparer « texturé » et « greybox » demanderait de déplacer des fichiers — donc
# de mesurer deux processus différents, ce qui n'est plus une comparaison.)
static var force_greybox := false


func _tile(tex_name: String) -> Texture2D:
	if force_greybox:
		return null
	var path := TEXTURE_DIR + tex_name + ".png"
	return load(path) if ResourceLoader.exists(path) else null


# ╔═ POURQUOI DU TRIPLANAIRE PLUTÔT QUE DES UV PAR FACE ══════════════════════════════════════════╗
# ║ Les volumes de cette arène sont des boîtes d'orientations et de proportions très différentes   ║
# ║ (un sol de 36 × 34 m, un parapet de 36 × 1,25 m, un mur de 0,4 m d'épaisseur). Avec les UV     ║
# ║ 0..1 par face d'un `BoxMesh`, chaque face demande son propre facteur d'échelle — et il suffit  ║
# ║ d'en calculer un sur le mauvais axe pour que les sacs fassent trois mètres de large sans que    ║
# ║ rien ne le signale. Le triplanaire EN COORDONNÉES MONDE supprime la question : l'échelle est   ║
# ║ une fréquence spatiale, la même sur les six faces et d'un volume à l'autre. La boue du no      ║
# ║ man's land et celle du sol lointain se raccordent alors sans qu'on ait rien à aligner.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# ⚠️ LA RUGOSITE N EST PLUS UNIFORME (§8.153). Elle valait 0,95 pour TOUT, ce qui revenait a dire
# que la boue d une tranchee de la Grande Guerre est aussi seche que la toile d un sac. Une
# tranchee est un endroit MOUILLE : la boue et les caillebotis renvoient une lueur diffuse, le
# jute et la terre n en renvoient aucune. C est la seule difference de MATIERE que le rendu en
# Compatibility sache exprimer — il n y a ni SSAO ni reflexion d ecran pour le dire autrement.
# ⛔ La table est fermee sur les quatre textures existantes : une matiere inconnue retombe sur
# 0,95, l ancienne valeur. L ajout ne peut donc rien changer a ce qu il ne connait pas.
const RUGOSITE := {"mud": 0.80, "planks": 0.78, "jute": 0.95, "earth": 0.95}


func _matter(tex_name: String, metres: float, fallback: Color,
		tint := Color(1, 1, 1)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = float(RUGOSITE.get(tex_name, 0.95))
	material.metallic = 0.0
	var tex := _tile(tex_name)
	if tex == null:
		# REPLI : le greybox nu. Le jeu reste jouable et recettable sans une seule matière déposée
		# (doctrine du dépôt) — il est seulement gris.
		material.albedo_color = fallback
		return material
	material.albedo_texture = tex
	material.albedo_color = tint
	# ⭐ LE RELIEF (§8.153). Le projet rend en **GL Compatibility** : SSAO, SSIL, SDFGI et le
	# brouillard volumetrique y sont SILENCIEUSEMENT INERTES — les activer ne produirait rien du
	# tout et couterait des heures de reglage d un effet qui n existe pas. La carte de NORMALES,
	# elle, marche. Sur une tranchee faite de 34 boites a faces planes, c est le seul levier de
	# relief disponible, et de tres loin le plus rentable.
	# ⚠️ Le chargement est OPTIONNEL et silencieux : une matiere sans normale garde EXACTEMENT
	# le rendu d avant. Et `force_greybox` n en charge aucune (c est `_tile` qui filtre), donc le
	# banc de performance continue de comparer ce qu il croit comparer.
	var normale := _tile(tex_name + "_normal")
	if normale != null:
		material.normal_enabled = true
		material.normal_texture = normale
		# ⛔ L amplitude est CUITE DANS LA CARTE (`tools/gen_trench_normals.py`, une force par
		# matiere). La remultiplier ici creerait un second reglage pour la meme grandeur, et le
		# jour ou l un des deux bougerait, plus personne ne saurait lequel regarder.
		material.normal_scale = 1.0
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	# En triplanaire, `uv1_scale` est une FRÉQUENCE : 1/mètres par tuile.
	var f := 1.0 / maxf(0.01, metres)
	material.uv1_scale = Vector3(f, f, f)
	return material


# --- Volumes ---------------------------------------------------------------------------------
func _box(parent: Node3D, node_name: String, size: Vector3, center: Vector3,
		material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = center
	parent.add_child(instance)
	return instance


func _build_terrain() -> void:
	var front: float = float(Geo.POSITIONS - 1) * Geo.POSITION_SPACING + FRONT_OVERSHOOT * 2.0
	var no_mans_land: float = Geo.NO_MANS_LAND
	# ⚙ La tuile de boue est peinte CLAIRE (elle doit rester lisible en tuile isolée) ; sous une
	# lumière de ciel couvert, elle ressortait en béton gris pâle — RGB 101 au premier plan, pour
	# une terre détrempée qui devrait être sombre et chaude. On la ramène par l'albédo plutôt qu'en
	# assombrissant la lumière, qui sert aussi à sculpter le parapet et la silhouette d'en face.
	var mud := _matter("mud", MUD_METRES, COL_GROUND, Color(0.73, 0.65, 0.56))
	var jute := _matter("jute", JUTE_METRES, COL_PARAPET, COVER_TINT)
	var planks := _matter("planks", PLANK_METRES, COL_TRENCH)
	var earth := _matter("earth", EARTH_METRES, COL_WALL)

	# Sol du no man's land : entre les deux parapets, à `GROUND_Y` au-dessus des plancher de
	# tranchée. C'est la surface que les grenades frappent et sur laquelle courent les ombres.
	var land_depth: float = no_mans_land - Geo.PARAPET_THICKNESS * 2.0
	_box(geometry_root, "NoMansLand", Vector3(front, 0.2, land_depth),
		Vector3(0.0, Geo.GROUND_Y - 0.1, Geo.PARAPET_THICKNESS + land_depth * 0.5), mud)
	_build_far_ground(front, no_mans_land)

	# MA tranchée : plancher, mur arrière, et le parapet de sacs qui décide de tout le jeu.
	# ⚠️ Sous `cover_root`, PAS sous `geometry_root` : rien ne doit pouvoir l'effacer.
	# Le plancher est un CAILLEBOTIS : accroupi, le joueur est aveugle sur le CHAMP, pas dans le
	# noir — il doit voir SA tranchée, du bois et des sacs. C'est ce qui fait la différence entre
	# « je suis à l'abri » et « l'écran s'est éteint ».
	_box(cover_root, "NearFloor", Vector3(front, 0.2, Geo.TRENCH_WIDTH),
		Vector3(0.0, -0.1, -Geo.TRENCH_WIDTH * 0.5), planks)
	_box(cover_root, "NearBackWall", Vector3(front, Geo.GROUND_Y + 0.4, 0.4),
		Vector3(0.0, (Geo.GROUND_Y + 0.4) * 0.5, -Geo.TRENCH_WIDTH - 0.2), earth)
	_box(cover_root, "NearParapet", Vector3(front, Geo.PARAPET_Y, Geo.PARAPET_THICKNESS),
		Vector3(0.0, Geo.PARAPET_Y * 0.5, Geo.PARAPET_THICKNESS * 0.5), jute)
	_build_sacs(front, jute)

	# La tranchée ADVERSE, en miroir : son parapet a son arête PROCHE à `far_parapet_near_edge_z`
	# — c'est CETTE arête qui coupe le bas de la silhouette (cf. `occlusion_floor_at_target`).
	var far_parapet_center: float = Geo.far_parapet_near_edge_z() + Geo.PARAPET_THICKNESS * 0.5
	_box(geometry_root, "FarParapet", Vector3(front, Geo.PARAPET_Y, Geo.PARAPET_THICKNESS),
		Vector3(0.0, Geo.PARAPET_Y * 0.5, far_parapet_center), jute)
	_box(geometry_root, "FarFloor", Vector3(front, 0.2, Geo.TRENCH_WIDTH),
		Vector3(0.0, -0.1, no_mans_land + Geo.TRENCH_WIDTH * 0.5), planks)
	_box(geometry_root, "FarBackWall", Vector3(front, Geo.GROUND_Y + 0.4, 0.4),
		Vector3(0.0, (Geo.GROUND_Y + 0.4) * 0.5, no_mans_land + Geo.TRENCH_WIDTH + 0.2), earth)


# Le CADRE de sol lointain : quatre dalles autour de l'arène, jusqu'au pied de l'arc de ciel.
# ⚠️ Leur face supérieure est EXACTEMENT à `GROUND_Y`, comme celle du no man's land : c'est cette
# égalité qui fait que le terrain part d'un seul tenant vers l'horizon.
# =================================================================================================
# LES SACS DE SABLE (§8.153) — du relief sur MON parapet, et sur lui seul
# =================================================================================================
# ╔═ ⛔ TROIS INTERDITS, ET CHACUN COÛTERAIT UNE PARTIE ═══════════════════════════════════════════╗
# ║ 1. AUCUN SAC AU-DESSUS DE `PARAPET_Y`. La hauteur du parapet ne décide pas de ce que JE vois   ║
# ║    (mon œil est à 1,70, bien au-dessus) : elle décide de ce que l'ADVERSAIRE peut me toucher,  ║
# ║    et le serveur la lit dans la table. Un sac qui dépasse me ferait croire couvert là où la    ║
# ║    règle me dit exposé. Le sommet est donc borné, et une sonde le vérifie sur la géométrie     ║
# ║    RENDUE, pas sur l'intention.                                                                ║
# ║ 2. RIEN SUR LE PARAPET ADVERSE. C'est son arête PROCHE qui coupe le bas de la silhouette       ║
# ║    (`occlusion_floor_at_target`). Le moindre sac qui déborde vers moi occulterait PLUS que la  ║
# ║    règle, et on tirerait sur un torse que le serveur déclare visible. Le parapet d'en face ne  ║
# ║    gagne donc que sa carte de normales — de l'ombre, jamais de la matière.                     ║
# ║ 3. LA CRÊTE RESTE DROITE, et ce n'est pas un oubli. C'est la ligne qui « fait greybox » dans   ║
# ║    les captures, et la casser demanderait de monter ou de descendre des sacs — les deux        ║
# ║    mentent. On casse donc l'arête PROCHE (celle qu'on enjambe du regard) et la profondeur,     ║
# ║    jamais la ligne d'horizon du parapet.                                                       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ UN SEUL `ArrayMesh` POUR TOUTE LA RANGÉE. Un `MeshInstance3D` par sac aurait donné ~110 appels
# de dessin de plus, sur un moteur en Compatibility où chaque appel compte — pour 12 triangles
# pièce. La géométrie est gratuite, les appels ne le sont pas.
const SAC_LARGEUR := 0.62       # largeur nominale d'un sac ⚙
const SAC_HAUTEUR := 0.30       # hauteur d'un sac ⚙
const SAC_CREUX_MAX := 0.06     # de combien un sac peut être ENFONCÉ sous la crête ⚙
const SAC_DEBORD_AVANT := 0.07  # débord côté no man's land ⚙ (reste très sous la ligne de vue)
# 🩸 0,11 → 0,05 m, SUR CAPTURE. Accroupi, l œil est a y = 0,90 et z = −0,5 : un sac qui déborde
# de 11 cm vers la tranchée se retrouve a **39 cm du nez**, et une seule de ses faces couvre 60 %
# de la largeur d écran. La vue accroupie est devenue un empilement de facettes géantes, dont la
# moitié dans l ombre — franchement pire que le mur lisse d avant.
# ⚠️ Le défaut ne se voyait PAS debout, la seule pose que je regardais. Une modification de décor
# se juge sur TOUTES les poses du banc, pas sur la plus flatteuse.
const SAC_DEBORD_ARRIERE := 0.05  # débord côté MA tranchée ⚙
# ⛔ UNE SEULE RANGÉE, ET C EST LA MÊME LEÇON. La seconde s asseyait sur y ∈ [0,61 ; 0,95],
# c est-à-dire EXACTEMENT à hauteur d œil accroupi. Les sacs n ont de sens que sur la CRÊTE —
# celle qu on enjambe du regard ; plus bas, ils ne décorent rien, ils bouchent.
const SAC_RANGEES := 1

func _build_sacs(front: float, jute: StandardMaterial3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var compteur := 0
	var n: int = int(front / SAC_LARGEUR)
	var pas: float = front / float(maxi(1, n))
	# Deux rangées : la crête, et un cours plus bas légèrement décalé (l'appareillage en quinconce
	# d'un vrai mur de sacs — deux rangées alignées se liraient comme une grille).
	for rangee in SAC_RANGEES:
		var haut_base: float = Geo.PARAPET_Y - float(rangee) * SAC_HAUTEUR
		var decalage: float = pas * 0.5 * float(rangee)
		for i in range(n + 1):
			var x: float = -front * 0.5 + pas * float(i) + decalage
			if absf(x) > front * 0.5:
				continue
			# Bruit DÉTERMINISTE : la scène doit se rebâtir à l'identique, sinon deux captures du
			# même banc diffèrent et toute mesure d'image devient inutilisable.
			var g := sin(float(i) * 12.9898 + float(rangee) * 4.1414) * 43758.5453
			var r0: float = g - floor(g)
			var g2 := sin(float(i) * 78.233 + float(rangee) * 1.618) * 24634.6345
			var r1: float = g2 - floor(g2)
			# ⛔ LE SOMMET NE MONTE JAMAIS : `haut_base` est un PLAFOND, le creux ne fait que
			# descendre. Une variation bilatérale aurait été plus jolie et aurait menti.
			var sommet: float = haut_base - r0 * SAC_CREUX_MAX
			var bas: float = sommet - SAC_HAUTEUR * (0.9 + r1 * 0.25)
			var demi: float = SAC_LARGEUR * (0.42 + r1 * 0.12)
			var z0: float = -SAC_DEBORD_ARRIERE * (0.4 + r0 * 0.6)
			var z1: float = Geo.PARAPET_THICKNESS + SAC_DEBORD_AVANT * (0.3 + r1 * 0.7)
			compteur = _sac(st, compteur, Vector3(x, (sommet + bas) * 0.5, (z0 + z1) * 0.5),
				Vector3(demi, (sommet - bas) * 0.5, (z1 - z0) * 0.5),
				deg_to_rad(-9.0 + 18.0 * r0))
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = "NearParapetSacs"
	instance.mesh = st.commit()
	instance.material_override = jute
	cover_root.add_child(instance)


# Un sac : une boîte dont le HAUT est rétréci (un sac posé s'affaisse et s'évase vers le bas), avec
# un léger lacet. ⚠️ Le rétrécissement s'applique en X et en Z, jamais en Y : la cote qui compte
# est la hauteur, et elle est déjà bornée par l'appelant.
func _sac(st: SurfaceTool, base: int, centre: Vector3, demi: Vector3, lacet: float) -> int:
	var rot := Basis(Vector3.UP, lacet)
	var pincement := 0.82
	var coins: Array[Vector3] = []
	for sy in [-1.0, 1.0]:
		var k: float = 1.0 if sy < 0.0 else pincement
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				coins.append(centre + rot * Vector3(demi.x * sx * k, demi.y * sy,
					demi.z * sz * k))
	# ⭐ HUIT SOMMETS PARTAGES, ET C EST TOUT LE SUJET DE CETTE FONCTION.
	# Premiere version : 24 sommets, quatre par face, aucun partage. `generate_normals()` donnait
	# alors une normale PAR FACE — un plat parfait, six aretes vives, et le resultat se lisait en
	# capture comme un bloc de beton chanfreine, pas comme un sac. Avec des sommets PARTAGES, les
	# normales des trois faces qui se rejoignent sont moyennees : le sac s arrondit comme un coussin,
	# ce qu il est. Meme geometrie, meme cout, la seule difference est la topologie.
	# ⚠️ Le sens de parcours reste `[0, 2, 1] / [0, 3, 2]` — il a ete etabli par le VOLUME SIGNE
	# (mesure : −5,45 m3 sur la version derivee a la main), et l indexation ne le change pas.
	for c: Vector3 in coins:
		st.add_vertex(c)
	var faces := [
		[0, 1, 3, 2],  # bas   (y-)
		[4, 6, 7, 5],  # haut  (y+)
		[0, 2, 6, 4],  # z-
		[1, 5, 7, 3],  # z+
		[0, 4, 5, 1],  # x-
		[2, 3, 7, 6],  # x+
	]
	for f: Array in faces:
		for tri: Array in [[0, 2, 1], [0, 3, 2]]:
			for k2 in tri:
				st.add_index(base + int(f[int(k2)]))
	return base + coins.size()


func _build_far_ground(front: float, no_mans_land: float) -> void:
	var far := _matter("mud", FAR_MUD_METRES, COL_GROUND, Color(0.66, 0.60, 0.53))
	var reach := FAR_GROUND_EXTENT
	var y := Geo.GROUND_Y - 0.1
	# Bords de l'arène déjà bâtie : au-delà, la dalle est libre.
	var back: float = -Geo.TRENCH_WIDTH - 0.4                       # face arrière de MA tranchée
	var front_z: float = no_mans_land + Geo.TRENCH_WIDTH + 0.4      # face arrière de la LEUR
	var half: float = front * 0.5
	_box(geometry_root, "FarGroundBeyond", Vector3(reach * 2.0, 0.2, reach - front_z),
		Vector3(0.0, y, (front_z + reach) * 0.5), far)
	_box(geometry_root, "FarGroundBehind", Vector3(reach * 2.0, 0.2, reach + back),
		Vector3(0.0, y, (-reach + back) * 0.5), far)
	_box(geometry_root, "FarGroundLeft", Vector3(reach - half, 0.2, front_z - back),
		Vector3(-(half + reach) * 0.5, y, (back + front_z) * 0.5), far)
	_box(geometry_root, "FarGroundRight", Vector3(reach - half, 0.2, front_z - back),
		Vector3((half + reach) * 0.5, y, (back + front_z) * 0.5), far)


# --- Le ciel ---------------------------------------------------------------------------------
# ╔═ LE CONTRAT DU PANORAMA : SON BORD INFÉRIEUR *EST* LA LIGNE D'HORIZON ════════════════════════╗
# ║ On ne demande plus à un modèle génératif où poser l'horizon — cinq séries d'img2img ont montré ║
# ║ qu'il ne sait pas le faire (§8.139, il l'a placé entre y=288 et y=346 pour une cible à 360).   ║
# ║ Le panorama est commandé SANS AUCUN SOL : ses silhouettes lointaines sont coupées par le bord  ║
# ║ bas du cadre. Ici, ce bord bas est simplement collé à `GROUND_Y`. L'horizon est alors juste    ║
# ║ par construction, à TOUT angle de caméra et depuis les 5 positions — il n'y a plus rien à      ║
# ║ recaler, et plus rien qui puisse dériver.                                                      ║
# ║                                                                                                ║
# ║ La hauteur de l'arc se DÉDUIT du rapport de l'image : une tuile de 200° d'arc à 300 m mesure   ║
# ║ 1047 m de long, donc une image en 21:9 fait 449 m de haut — soit 56° au-dessus de l'horizon,   ║
# ║ là où le champ de vision n'en demande que 42. Le ciel ne peut pas manquer de hauteur.          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
func _build_sky() -> void:
	var tex := load(SKY_PATH) as Texture2D if ResourceLoader.exists(SKY_PATH) else null
	# ⚠️ L'arc de l'IMAGE, pas celui de la géométrie : c'est lui qui porte le rapport d'aspect.
	var arc_length: float = deg_to_rad(SKY_IMAGE_ARC_DEG) * SKY_RADIUS
	var height := SKY_FALLBACK_HEIGHT
	if tex != null and tex.get_width() > 0:
		height = arc_length * float(tex.get_height()) / float(tex.get_width())

	var material := StandardMaterial3D.new()
	# NON ÉCLAIRÉ : la lumière du ciel est DÉJÀ PEINTE. La rééclairer serait la peindre deux fois —
	# même raison que pour le sprite du soldat (§8.138).
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Faces des DEUX côtés : le sens d'enroulement de l'arc cesse d'être une question, et une
	# inversion silencieuse ne peut pas rendre un écran vide. 144 triangles — le coût est nul.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# ⚠️ PAS DE RÉPÉTITION : la jupe sous l'horizon dépasse v = 1, et c'est VOULU — le bord bas de
	# l'image s'y étire vers le bas. En mode répétition, le haut du ciel réapparaîtrait sous
	# l'horizon, dans la mince bande où le sol et l'arc se rejoignent.
	material.texture_repeat = false
	# ⚠️⚠️ L'EXEMPTION DE BRUME — SANS ELLE, LE PANORAMA EST INTÉGRALEMENT EFFACÉ. Cet arc est un
	# MAILLAGE à 300 m : la brume de profondeur (`trench_fp_world._build_fog`) s'y applique comme à
	# n'importe quelle géométrie lointaine, et elle le remplace par un aplat gris. Le réglage
	# `fog_sky_affect` de l'Environment ne le couvre PAS : il ne vaut que pour un ciel `BG_SKY`.
	# Défaut vu en CAPTURE au premier rendu, et par aucun autre moyen.
	material.disable_fog = true
	if tex != null:
		material.albedo_texture = tex
	else:
		material.albedo_texture = _fallback_sky_gradient()
	var instance := MeshInstance3D.new()
	instance.name = "SkyArc"
	instance.mesh = _sky_arc_mesh(height)
	instance.material_override = material
	# Le ciel ne reçoit ni ne projette rien : il n'est pas un objet du monde, il en est le fond.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(instance)


# Dégradé de repli, quand `sky_panorama.png` n'est pas déposé — le monde garde un haut et un bas.
func _fallback_sky_gradient() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.30, 0.33, 0.37))
	gradient.set_color(1, Color(0.62, 0.63, 0.63))
	var out := GradientTexture2D.new()
	out.gradient = gradient
	out.width = 8
	out.height = 256
	out.fill_from = Vector2(0.0, 0.0)
	out.fill_to = Vector2(0.0, 1.0)
	return out


# L'arc lui-même : une bande de quadrilatères sur un cylindre, centrée sur +Z (la tranchée adverse).
func _sky_arc_mesh(height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span := deg_to_rad(SKY_ARC_DEG)
	var y_top: float = Geo.GROUND_Y + height
	var y_bottom: float = Geo.GROUND_Y - SKY_SKIRT
	# `v` = 0 en haut de l'image, 1 sur son bord bas — qui tombe pile sur `GROUND_Y`. La jupe
	# poursuit au-delà de 1 ; le mode « pas de répétition » y étire la dernière ligne de pixels.
	var v_bottom: float = (height + SKY_SKIRT) / maxf(0.01, height)
	# `u` est mappé sur l'arc de l'IMAGE et laissé SORTIR de [0,1] sur les ailes de l'arc bâti : le
	# mode « pas de répétition » clampe alors sur la colonne de bord (cf. le pavé de `SKY_ARC_DEG`).
	var image_span := deg_to_rad(SKY_IMAGE_ARC_DEG)
	for i in range(SKY_SEGMENTS):
		var a0: float = -span * 0.5 + span * float(i) / float(SKY_SEGMENTS)
		var a1: float = -span * 0.5 + span * float(i + 1) / float(SKY_SEGMENTS)
		var u0: float = 0.5 + a0 / image_span
		var u1: float = 0.5 + a1 / image_span
		var top0 := Vector3(sin(a0) * SKY_RADIUS, y_top, cos(a0) * SKY_RADIUS)
		var top1 := Vector3(sin(a1) * SKY_RADIUS, y_top, cos(a1) * SKY_RADIUS)
		var low0 := Vector3(sin(a0) * SKY_RADIUS, y_bottom, cos(a0) * SKY_RADIUS)
		var low1 := Vector3(sin(a1) * SKY_RADIUS, y_bottom, cos(a1) * SKY_RADIUS)
		for corner in [[u0, 0.0, top0], [u1, 0.0, top1], [u1, v_bottom, low1],
				[u0, 0.0, top0], [u1, v_bottom, low1], [u0, v_bottom, low0]]:
			st.set_uv(Vector2(corner[0], corner[1]))
			st.add_vertex(corner[2])
	st.generate_normals()
	return st.commit()


# --- Accessoires ------------------------------------------------------------------------------
# ╔═ ⚠️⚠️ RÈGLE ABSOLUE : UN ACCESSOIRE NE DOIT JAMAIS OCCULTER LA SILHOUETTE ADVERSE ════════════╗
# ║ Le serveur tranche les touches sur SA table angulaire, qui ne connaît que le parapet. Un objet ║
# ║ posé dans le no man's land qui masquerait l'ennemi à l'écran ne le masquerait PAS pour la      ║
# ║ simulation : le joueur verrait ses balles traverser un obstacle, ou tirerait sur une cible     ║
# ║ qu'il croit couverte. Ce serait un changement de RÈGLE déguisé en décor — précisément ce que   ║
# ║ le hors-périmètre interdit.                                                                    ║
# ║ On borne donc la hauteur de chaque accessoire SOUS la ligne de vue la plus basse : celle qui   ║
# ║ va d'un œil debout (1,70 m) au BAS de la bande exposée d'en face (1,15 m au plan des soldats). ║
# ║ est CALCULÉE ici, pas recopiée : si une cote de `trench_geometry.gd` bouge, elle suit.         ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const PROP_SAFETY := 0.12          # marge sous la ligne de vue ⚙


# Hauteur maximale admissible pour un accessoire posé à cette profondeur, au-dessus du sol.
func _prop_ceiling(z: float) -> float:
	var eye: float = Geo.EYE_UP
	var from_z: float = Geo.near_soldier_z()
	var to_z: float = Geo.far_soldier_z()
	var t: float = clampf((z - from_z) / maxf(0.01, to_z - from_z), 0.0, 1.0)
	var sight: float = lerpf(eye, Geo.SILHOUETTE_BOTTOM, t)
	return maxf(0.0, sight - Geo.GROUND_Y - PROP_SAFETY)


# Barbelés et débris — juste assez pour que le no man's land ne soit pas une nappe vide, jamais
# assez pour disputer la lecture d'une silhouette.
func _build_props() -> void:
	var wood := _matter("planks", 0.8, COL_WALL, Color(0.55, 0.52, 0.48))
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.20, 0.19, 0.18)
	wire_mat.roughness = 0.9
	var ground: float = Geo.GROUND_Y
	# ╔═ ⚠️ DEUX CORRECTIONS VENUES DE LA PREMIÈRE CAPTURE, ET DE NULLE PART AILLEURS ════════════╗
	# ║ Version initiale : deux rangs à 2,6 m et 5,4 m de l'œil, avec des brins TENDUS SUR 29 m.   ║
	# ║ À 2,6 m, un brin de 3,5 cm couvre 0,77° — soit 14 px de haut EN TRAVERS DE TOUT L'ÉCRAN.   ║
	# ║ Six brins ainsi posés ne se lisaient pas comme des barbelés : c'étaient six bandes noires   ║
	# ║ barrant le no man's land. Aucun contrôle ne pouvait l'attraper — ils étaient bien SOUS la  ║
	# ║ ligne de vue, donc « neutres » au sens du jeu, et parfaitement hideux à l'écran.            ║
	# ║   1. on les ÉLOIGNE (10 m et 15 m) : le même brin n'y fait plus que 3 px ;                 ║
	# ║   2. on les BRISE — chaque brin ne relie que deux piquets voisins, à une hauteur qui varie. ║
	# ║      Une ligne continue lit « barre » ; une ligne rompue lit « enchevêtrement ».            ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	# ⚠️ Profondeurs exprimées en FRACTION du no man's land, jamais en mètres absolus : la cote est
	# passée de 35 m à 12 m (§8.140.1) puis à 9 m (§8.141) sur verdict de partie réelle, et deux
	# rangs posés « à 10 et 15 m » se seraient retrouvés l'un au milieu du terrain, l'autre DERRIÈRE
	# la tranchée adverse. Écrites ainsi, elles ont traversé les deux rapprochements sans une ligne.
	for row in [{"t": 0.30, "n": 6}, {"t": 0.50, "n": 5}]:
		var z: float = Geo.NO_MANS_LAND * float(row["t"])
		var ceiling: float = _prop_ceiling(z)
		# ⚠️ 0,85 × le plafond, et non le plafond : bâtir PILE sur la limite la faisait franchir à
		# l'erreur d'arrondi près (5 fautifs relevés par le contrôle, à 0,42 m pour une limite de
		# 0,4196 m). Une borne qu'on touche n'est pas une borne — et un piquet qui rase la ligne de
		# vue frôlerait de toute façon les pieds de la cible à l'écran.
		var post_h: float = minf(0.42, ceiling * 0.85)
		if post_h <= 0.05:
			continue
		var count: int = int(row["n"])
		var span := 30.0
		for i in range(count):
			var x: float = lerpf(-span * 0.5, span * 0.5, float(i) / float(maxi(1, count - 1)))
			var post := _box(props_root, "WirePost_%.0f_%d" % [z * 10.0, i],
				Vector3(0.07, post_h, 0.07), Vector3(x, ground + post_h * 0.5, z), wood)
			# Penchés, et chacun d'un angle différent : un rang de piquets d'aplomb sonne faux.
			post.rotation_degrees = Vector3(0.0, 0.0, 5.0 + 7.0 * sin(float(i) * 2.3 + z))
			if i == 0:
				continue
			# Le brin qui rejoint le piquet précédent, à une hauteur tirée de la position — donc
			# stable d'un lancement à l'autre, et jamais alignée avec sa voisine.
			var prev_x: float = lerpf(-span * 0.5, span * 0.5, float(i - 1) / float(maxi(1, count - 1)))
			var h: float = post_h * (0.45 + 0.35 * absf(sin(float(i) * 1.7 + z)))
			if h > ceiling:
				continue
			_box(props_root, "WireStrand_%.0f_%d" % [z * 10.0, i],
				Vector3(absf(x - prev_x) * 0.92, 0.025, 0.025),
				Vector3((x + prev_x) * 0.5, ground + h, z), wire_mat)
	# Deux poutres échouées, à plat : du relief au sol, aucune hauteur.
	for i in range(2):
		var z: float = Geo.NO_MANS_LAND * (0.22 + 0.34 * float(i))
		var beam_h: float = minf(0.22, _prop_ceiling(z) * 0.85)
		if beam_h <= 0.05:
			continue
		var beam := _box(props_root, "Beam_%d" % i, Vector3(2.6, beam_h, 0.35),
			Vector3(-6.0 + 11.0 * float(i), ground + beam_h * 0.5, z), wood)
		beam.rotation_degrees = Vector3(0.0, 14.0 - 31.0 * float(i), 0.0)


# --- Repères ---------------------------------------------------------------------------------
func _build_poses() -> void:
	# Les 10 poses de MON camp (5 positions × 2 postures) — nommées `cam_p{i}_{up|down}`.
	for pose in Geo.all_poses():
		var marker := Marker3D.new()
		marker.name = String(pose["name"])
		marker.transform = Geo.pose_transform(int(pose["pos"]), String(pose["stance"]))
		poses_root.add_child(marker)
	# Les 5 ancrages ADVERSES : le soldat placeholder (et demain le .glb) s'y accroche, au SOL de
	# sa tranchée — la posture est jouée par l'animation, pas par le repère.
	for i in range(Geo.POSITIONS):
		var anchor := Marker3D.new()
		anchor.name = "enemy_p%d" % i
		anchor.position = Vector3(Geo.position_x(i), 0.0, Geo.far_soldier_z())
		# Il fait FACE à moi (demi-tour par rapport à mes caméras).
		anchor.rotation = Vector3.ZERO
		enemy_root.add_child(anchor)


func _build_light() -> void:
	# Lumière rasante unique : elle sculpte les sacs de sable pour que le greybox se lise en
	# capture (§6.4) sans coûter d'ombre dynamique.
	# ⚠️ LE SOLEIL VIENT DE DERRIÈRE LE JOUEUR (lacet ~200°) : c'est la seule orientation qui
	# éclaire les faces TOURNÉES VERS LA CAMÉRA — parapet proche, mur de sacs, silhouette adverse.
	# Un soleil de face laissait tout le champ visible dans son ombre et rendait le greybox
	# quasiment noir (défaut vu en CAPTURE, invisible au boot headless).
	#
	# ⚙ ACCORDÉE AU PANORAMA (pivot « monde 3D + ciel peint »). Le ciel déposé est un couvert lourd
	# et froid, avec une seule trouée pâle : c'est la lumière qu'il faut rendre. L'énergie descend
	# de 1,35 à 0,85 et la teinte passe au gris bleuté — à 1,35 en blanc, la boue et le jute
	# sortaient plus clairs que le ciel derrière eux, et l'œil lisait deux images différentes
	# collées l'une à l'autre. C'est cet accord-là qui « colle » la peinture et la 3D.
	#
	# ⚠️ TOUJOURS AUCUNE OMBRE PORTÉE, et ce n'est plus seulement une économie : sous un ciel
	# entièrement couvert, il n'y a physiquement pas d'ombre franche. En ajouter serait démentir le
	# ciel qu'on vient de peindre — et payer des millisecondes pour ça.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-34.0, 200.0, 0.0)
	sun.light_color = Color(0.86, 0.89, 0.94)
	sun.light_energy = 0.85
	sun.shadow_enabled = false
	add_child(sun)


# --- API pour les outils et pour `trench_fp.gd` ---------------------------------------------
# Transform d'une pose de caméra, LU sur le blockout (et non recalculé) : c'est ainsi que la vue
# de production et la table angulaire ne peuvent pas diverger.
func pose_transform(pos_index: int, stance: String) -> Transform3D:
	if poses_root == null:
		return Geo.pose_transform(pos_index, stance)
	var marker := poses_root.get_node_or_null(Geo.pose_name(pos_index, stance))
	if marker is Marker3D:
		return (marker as Marker3D).transform
	return Geo.pose_transform(pos_index, stance)


# Point d'ancrage au sol d'une position adverse (pose du soldat ennemi).
func enemy_anchor(pos_index: int) -> Vector3:
	if enemy_root != null:
		var marker := enemy_root.get_node_or_null("enemy_p%d" % clampi(pos_index, 0, Geo.POSITIONS - 1))
		if marker is Marker3D:
			return (marker as Marker3D).position
	return Vector3(Geo.position_x(pos_index), 0.0, Geo.far_soldier_z())


# ⚠️ Le parapet est À CONTRE-JOUR (le soleil vient de derrière le joueur, cf. `_build_light`) : sa
# face tournée vers l'œil ne reçoit presque rien. Teinté à 0,62 il sortait en BANDEAU NOIR — la
# matière de jute ne se lisait pas, et l'abri se lisait donc comme un défaut d'affichage plutôt que
# comme un mur de sacs. On compense par l'albédo plutôt qu'en tordant l'éclairage, qui sert aussi à
# sculpter le soldat d'en face.
# ⚙ RELEVÉE DE 1,30 À 1,70 avec le pivot, et pour une raison arithmétique : l'ambiance est passée
# de 1,35 à 1,0 pour s'accorder au panorama, donc le parapet — qui ne reçoit presque QUE de
# l'ambiante, puisqu'il est à contre-jour — a perdu un quart de sa lumière du même coup. Mesure sur
# la capture accroupie : luminance moyenne 60/255, avec 40 % de l'écran sous 40. Le bon de commande
# est explicite : accroupi, le joueur est aveugle SUR LE CHAMP, pas dans le noir.
const COVER_TINT := Color(1.70, 1.67, 1.62)


# ╔═ `set_cover_texture()` A ÉTÉ RETIRÉE, ET AVEC ELLE TOUTE LA BASCULE DÉCOR/GREYBOX ════════════╗
# ║ Elle habillait ma tranchée avec le décor peint de la pose accroupie, parce que le monde 3D     ║
# ║ n'était alors qu'un figurant devant une image. Depuis le pivot, le monde texturé EST le rendu  ║
# ║ nominal : `_build_terrain()` pose les matières une fois pour toutes, et il n'y a plus deux     ║
# ║ états à synchroniser — donc plus de bascule capable de masquer `NearParapet` par mégarde,      ║
# ║ ce qui était LA cause du « il n'y a pas de tranchée » vécu en partie réelle (§8.139.1).        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
# Masque le monde LOINTAIN. Conservée pour l'outillage de calibration (`gen_trench_angles.gd`
# instancie ce blockout pour projeter la table angulaire, sans avoir besoin du paysage).
func set_geometry_visible(visible_geometry: bool) -> void:
	if geometry_root != null:
		geometry_root.visible = visible_geometry
	if sky_root != null:
		sky_root.visible = visible_geometry
	if props_root != null:
		props_root.visible = visible_geometry
