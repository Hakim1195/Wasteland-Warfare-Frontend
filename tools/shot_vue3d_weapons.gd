extends Node

# =================================================================================================
# BANC DE RENDU §8.152 LOT 3D-B — PHOTOGRAPHIE LES **QUATRE ARMES COMPLÈTES**.
#
# ╔═ POURQUOI CE SECOND BANC ════════════════════════════════════════════════════════════════════╗
# ║ `shot_vue3d_parts.gd` photographie des PIÈCES ISOLÉES : il prouve que le vocabulaire du socle ║
# ║ (rails, molettes, chargeurs, garde-mains) tient à l'œil. Il ne prouve RIEN de l'ASSEMBLAGE —  ║
# ║ or c'est l'assemblage qui ment le plus facilement : une pièce mobile posée sur la mauvaise    ║
# ║ ancre, un chargeur qui flotte à 2 cm sous son puits, une glissière restée à y = 0 alors que   ║
# ║ l'âme est à 36 mm… tout cela laisse la sonde `probe_vue3d_weapons` VERTE (elle contrôle des   ║
# ║ ancres et des seaux, pas des pixels) et ne se voit qu'en REGARDANT.                           ║
# ║                                                                                               ║
# ║ Le cahier §5 exige « des captures des 4 armes lues et jugées », et le §2.2quater impose que   ║
# ║ chaque lot mette SON rendu à côté de la référence. Ce banc est l'appareil photo de cette      ║
# ║ soumission-là. Il ne juge rien tout seul : il RENVOIE LES IMAGES À HAKIM. C'est délibéré —    ║
# ║ « une référence issue de la chose qu'elle vérifie ne vérifie rien » (§8.152).                 ║
# ║                                                                                               ║
# ║ ⚠️ RAPPEL POUR LE `condor` : aucune capture de référence n'existe pour lui, il est EXTRAPOLÉ  ║
# ║ du fusil. Ses trois vues sont donc à soumettre AVANT de figer quoi que ce soit à son sujet.   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ DÉCOR ET CADRAGE : STRICTEMENT CEUX DE `shot_vue3d_parts.gd` ═══════════════════════════════╗
# ║ Fond neutre, AgX, lumière clé rasante + appoint froid, FOV 32°, cadrage sur l'AABB en 3/4 :   ║
# ║ recopiés à l'identique, valeur par valeur. Ce n'est pas de la paresse, c'est la condition     ║
# ║ pour que la vue d'une ARME soit comparable à la vue d'une PIÈCE et à la passe d'hier. Si le   ║
# ║ décor dérive entre deux bancs, toute différence observée devient inexploitable : on ne saura  ║
# ║ plus si c'est la géométrie qui a changé ou l'éclairage.                                       ║
# ║ ⛔ Ne JAMAIS « améliorer » l'éclairage ici sans le faire aussi dans l'autre banc.             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ LANCEMENT **FENÊTRÉ OBLIGATOIRE** — surtout PAS `--headless` : le pilote de rendu factice
# renvoie `null` sur `viewport.get_texture()`. Un `SubViewport` a beau avoir sa propre cible de
# rendu, il n'y a aucun rasteriseur derrière. (Même constat que `shot_vue3d_parts.gd`, vérifié le
# 2026-08-27.) Le code ci-dessous le DIT au lieu de planter : si la texture est nulle, il imprime
# la raison et sort en code 1 — un banc muet qui rend 0 serait le pire des faux verts.
#
#   Depuis `C:\Users\Hakim\Documents\Wasteland-Warfare-Project` :
#   & "C:\Users\Hakim\Desktop\Godot_v4.7-stable_win64_console.exe" --path frontend res://tools/shot_vue3d_weapons.tscn
#
# Sorties dans `user://vue3d_shots/` (le même dossier que le banc des pièces — les noms ne
# collisionnent pas : les pièces sont préfixées de leur numéro, les armes de leur id).
# Le chemin absolu est imprimé à la fin.
# =================================================================================================

const Meshgen := preload("res://scripts/game/trench_meshgen.gd")
const WMat := preload("res://scripts/game/trench_wmaterials.gd")
const W3D := preload("res://scripts/game/trench_weapons3d.gd")

const SHOT_SIZE := Vector2i(900, 900)
const OUT_DIR := "user://vue3d_shots"

# Les trois vues, dans l'ordre où elles sont prises. Le récapitulatif compare le nombre d'images
# écrites à `WEAPON_IDS.size() * VUES.size()` : une vue SAUTÉE (ancre manquante, texture nulle)
# reste comptée comme attendue, donc elle fait sortir en code 1. Un banc qui ne compterait que ses
# échecs annoncerait « TOUT VERT » alors que rien n'a tourné.
const VUES := ["troisquarts", "profil", "visee"]

# ╔═ LA TABLE DES REPOS — l'assemblage mobile ↔ son ancre dans `nodes` ══════════════════════════╗
# ║ `build()` rend les pièces mobiles SÉPARÉES et AUTHORÉES À L'ORIGINE de leur propre repère :  ║
# ║ le chargeur est modélisé autour de (0,0,0), la glissière du `vipere` à y = 0 alors que l'âme  ║
# ║ est à 36 mm, la culasse du `chacal` à z = 0 alors qu'elle repose à z = +21 mm. Sans cette     ║
# ║ table, les six sous-assemblages s'empileraient tous à l'origine et l'image montrerait une     ║
# ║ arme éventrée — ce qui serait mis sur le dos de la GÉOMÉTRIE alors que la faute serait ici.   ║
# ║ Ces ancres existent précisément pour que personne ne re-devine ces coordonnées en dur.        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const REPOS := {
	"magazine": "magSeat",
	"charging": "chargeRest",
	"bolt": "boltRest",
	"slide": "slideRest",
	"trigger": "triggerPivot",
	"selector": "selectorPivot",
}

# Recul de l'œil derrière l'organe de visée, en mètres, pour la vue `visee`.
# ⚠️ Ce n'est PAS le `eye_relief` du registre de vue (0,104 à 0,34 selon l'arme) : celui-là est
# une valeur de JEU, mesurée sur l'image ADS pour que l'optique occupe le bon tiers d'écran. Ici on
# veut une constante UNIQUE pour les quatre armes, sinon le pistolet (0,34 m) serait photographié
# quatre fois plus loin que la mitraillette et les images ne seraient plus comparables.
# À 0,12 m et 32° de champ, la hauteur vue au niveau de l'optique fait 69 mm : un tube de 31 mm y
# lit à 45 % de l'image — assez gros pour juger la lentille, assez petit pour voir le guidon.
const RECUL_OEIL := 0.12

var _lib: WMat


func _ready() -> void:
	_lib = WMat.new()

	# ── LE DÉCOR — copie conforme de `shot_vue3d_parts.gd` (cf. le pavé d'en-tête) ─────────────
	var viewport := SubViewport.new()
	viewport.size = SHOT_SIZE
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	var scene := Node3D.new()
	viewport.add_child(scene)

	# Fond NEUTRE et lumière FRANCHE : on juge la GÉOMÉTRIE et les MATÉRIAUX, pas l'éclairage.
	# La lumière rasante est ce qui révèle les chanfreins — c'est ce que la référence dit d'eux.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.70)
	# `ENV_OCCLUSION` du lot 3D-C : une arme à l'épaule ne voit qu'un quart du ciel. C'est ICI que
	# la constante s'applique (Godot n'a pas d'`envMapIntensity` par matériau).
	env.ambient_light_energy = 1.6 * WMat.ENV_OCCLUSION * 4.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	scene.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 3.2
	key.light_color = Color(1.0, 0.96, 0.90)
	key.rotation_degrees = Vector3(-38, 138, 0)
	scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.9
	fill.light_color = Color(0.62, 0.72, 0.92)
	fill.rotation_degrees = Vector3(-14, -46, 0)
	scene.add_child(fill)

	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.near = 0.005
	camera.far = 10.0
	scene.add_child(camera)

	var holder := Node3D.new()
	scene.add_child(holder)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await get_tree().process_frame

	var attendues: int = W3D.WEAPON_IDS.size() * VUES.size()
	var ecrites := 0
	var manquantes: Array = []

	for wid in W3D.WEAPON_IDS:
		var id := String(wid)
		# ⚠️ UNE SEULE CONSTRUCTION PAR ARME, ET UN SEUL MONTAGE : `Assembly.build()` VIDE ses
		# seaux. Un second appel rendrait un dictionnaire vide, donc une image NOIRE — et une image
		# noire écrite avec succès compte comme une réussite. C'est pour ça que le maillage est
		# monté une fois puis photographié trois fois, sans jamais retoucher aux assemblages.
		var arme: Dictionary = W3D.build(id)
		var nodes: Dictionary = arme["nodes"]
		var montee: Dictionary = _monter(arme)

		for c in holder.get_children():
			c.queue_free()
		await get_tree().process_frame
		var mi := MeshInstance3D.new()
		mi.mesh = montee["mesh"]
		holder.add_child(mi)

		var boite: AABB = montee["aabb"]
		# ⚠️ Le passage par une variable TYPÉE est délibéré : `montee["cles"]` est un `Variant`, et
		# `String.join()` attend un `PackedStringArray`. Le typage inféré (`:=`) échouerait ici —
		# c'est la règle GDScript qui mord dès qu'une valeur sort d'un `Dictionary`.
		var cles: PackedStringArray = montee["cles"]
		print("\n[ARME] %-8s %6d triangles · %2d surfaces · L=%.0f mm H=%.0f mm · matieres : %s"
			% [id, int(montee["tris"]), int(montee["surfaces"]),
				boite.size.z * 1000.0, boite.size.y * 1000.0, " ".join(cles)])
		# Un sous-assemblage sans ancre de repos est resté à l'origine : il FAUT le dire, sinon la
		# pièce mal placée sera imputée au modèle et non au banc.
		for orph in montee["orphelines"]:
			push_warning("shot_vue3d_weapons : %s.%s n'a pas d'ancre de repos — laisse a l'origine."
				% [id, orph])
			print("  [!] piece mobile SANS ancre de repos, laissee a l'origine : " + String(orph))

		for v in VUES:
			var vue := String(v)
			var nom := "%s_%s" % [id, vue]
			if not _poser_camera(camera, vue, boite, nodes):
				manquantes.append("%s (ancre de visee absente)" % nom)
				print("  [MANQUE] %-22s ancre `sight` absente — vue non prise" % nom)
				continue
			# Deux frames : la première applique la caméra, la seconde garantit que la cible de
			# rendu du `SubViewport` a bien été rafraîchie avant la lecture.
			await get_tree().process_frame
			await get_tree().process_frame

			var tex := viewport.get_texture()
			if tex == null:
				manquantes.append("%s (texture nulle)" % nom)
				push_error("shot_vue3d_weapons : `get_texture()` est NULL — "
					+ "lancement en --headless ? Ce banc exige une fenetre.")
				print("  [MANQUE] %-22s texture nulle (pilote factice : relancer FENETRE)" % nom)
				continue
			var img := tex.get_image()
			if img == null:
				manquantes.append("%s (image nulle)" % nom)
				print("  [MANQUE] %-22s image nulle" % nom)
				continue
			var path := "%s/%s.png" % [OUT_DIR, nom]
			if img.save_png(path) == OK:
				ecrites += 1
				print("  [SHOT] %-22s %6d triangles  -> %s"
					% [nom, int(montee["tris"]), ProjectSettings.globalize_path(path)])
			else:
				manquantes.append("%s (ecriture impossible)" % nom)
				push_error("shot_vue3d_weapons : ecriture impossible -> " + path)

	print("\n%d/%d vues rendues dans %s"
		% [ecrites, attendues, ProjectSettings.globalize_path(OUT_DIR)])
	if not manquantes.is_empty():
		print("MANQUANTES (%d) : %s" % [manquantes.size(), str(manquantes)])
	get_tree().quit(0 if ecrites == attendues else 1)


# =================================================================================================
# MONTAGE — du dictionnaire de `W3D.build()` à UN `ArrayMesh` multi-surfaces
# =================================================================================================
# Rend `{ "mesh", "aabb", "tris", "surfaces", "cles", "orphelines" }`.
#
# ⚠️ UNE SURFACE PAR SEAU ET PAR ASSEMBLAGE, sans regrouper les seaux de même clé entre le corps et
# les pièces mobiles. C'est VOULU : le masque de courbure (`bake_curvature`) se cuit sur un
# maillage FUSIONNÉ, et fusionner le chargeur avec la carcasse ferait considérer leur jonction
# comme une arête interne — donc une usure inventée là où il n'y a qu'un joint. Les surfaces en
# double ne coûtent qu'un `draw call` de banc, pas une seconde de jeu.
func _monter(arme: Dictionary) -> Dictionary:
	var nodes: Dictionary = arme["nodes"]
	var mesh := ArrayMesh.new()
	var tris := 0
	var boite := AABB()
	var premier := true
	var cles := PackedStringArray()
	var orphelines := PackedStringArray()

	# Le CORPS n'a pas de transform : il EST le repère de l'arme (l'âme à `bore`, la bouche en −Z).
	var pieces: Array = [{"asm": arme["body"], "t": Transform3D.IDENTITY}]

	var moving: Dictionary = arme["moving"]
	for nom in moving:
		var ancre := String(REPOS.get(nom, ""))
		var t := Transform3D.IDENTITY
		# ⚠️ TOUTES LES ARMES N'ONT PAS TOUTES LES PIÈCES : le `vipere` a une `slide` et aucune
		# `bolt` ni `charging` ni `selector`; les trois autres l'inverse. On teste donc la présence
		# de l'ancre au lieu de la supposer — une clé absente rendrait `{}` en silence, et la pièce
		# atterrirait à l'origine sans que rien ne le signale.
		if ancre == "" or not nodes.has(ancre):
			orphelines.append(String(nom))
		else:
			var n: Dictionary = nodes[ancre]
			var pos: Vector3 = n.get("pos", Vector3.ZERO)
			var rot: Vector3 = n.get("rot", Vector3.ZERO)
			# On passe par `transform_from_dict` plutôt que de composer un `Basis` à la main :
			# c'est l'ordre d'Euler XYZ de la référence, et c'est celui qu'`Assembly.add` applique
			# partout ailleurs. Recomposer autrement introduirait un désaccord invisible sur les
			# pièces inclinées (le puits de chargeur du `chacal` est à 0,08 rad).
			t = Meshgen.transform_from_dict({
				"x": pos.x, "y": pos.y, "z": pos.z,
				"rx": rot.x, "ry": rot.y, "rz": rot.z,
			})
		pieces.append({"asm": moving[nom], "t": t})

	for p in pieces:
		var seaux: Dictionary = p["asm"].build()
		var tr: Transform3D = p["t"]
		for cle in seaux:
			var g = seaux[cle]
			if g == null or g.is_empty():
				continue
			# La pose AVANT la cuisson du masque : la courbure est invariante par transformation
			# rigide, mais l'ordre inverse obligerait à re-transformer des couleurs déjà cuites.
			if tr != Transform3D.IDENTITY:
				g.apply_transform(tr)
			# L'USURE D'ARÊTE du lot 3D-C. `apply_wear_mask` rend `false` sur les clés qui n'ont pas
			# d'usure définie (verres, cavités, tube d'optique) : dans ce cas et SEULEMENT dans ce
			# cas, on prend le matériau nu — `get_worn` sur une clé sans usure peindrait la pièce
			# avec la couleur d'usure du repli.
			var use := WMat.apply_wear_mask(g, cle)
			var mat := _lib.get_worn(cle) if use else _lib.get_material(cle)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.to_surface_arrays())
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
			tris += g.tri_count()
			if premier:
				boite = g.aabb()
				premier = false
			else:
				boite = boite.merge(g.aabb())
			if not cles.has(cle):
				cles.append(String(cle))

	return {
		"mesh": mesh,
		"aabb": boite,
		"tris": tris,
		"surfaces": mesh.get_surface_count(),
		"cles": cles,
		"orphelines": orphelines,
	}


# =================================================================================================
# LES TROIS POINTS DE VUE
# =================================================================================================
# Rend `false` si la vue ne peut PAS être posée honnêtement (ancre manquante) : l'appelant compte
# alors l'image comme manquante. On n'invente pas un cadrage de repli — une image prise « à peu
# près là » serait indiscernable d'une bonne, et c'est exactement le genre de faux vert que le
# chantier §8.152 s'est juré d'éviter.
func _poser_camera(camera: Camera3D, vue: String, boite: AABB, nodes: Dictionary) -> bool:
	match vue:
		"troisquarts":
			# Le 3/4 canonique de `shot_vue3d_parts.gd` — direction recopiée telle quelle.
			_frame(camera, boite, Vector3(0.62, 0.45, 0.65).normalized())
			return true
		"profil":
			# Profil STRICT sur l'axe +X, regard vers −X, aucune composante verticale : c'est la
			# vue qui met en évidence la ligne de dos (rail → hausse → optique), la garde au
			# pontet et l'inclinaison du chargeur — trois choses qu'un 3/4 raccourcit.
			# ⚠️ HONNÊTETÉ DE NOMMAGE : le côté +X est celui qui porte la FENÊTRE D'ÉJECTION
			# (`nodes["eject"].x > 0` sur les trois armes d'épaule), c'est-à-dire le flanc DROIT au
			# sens armurier. Le nom de fichier reste `profil`, conforme à la commande.
			_frame(camera, boite, Vector3(1.0, 0.0, 0.0))
			return true
		"visee":
			if not nodes.has("sight"):
				return false
			var sight: Vector3 = nodes["sight"]
			# On lit l'axe de visée dans le modèle au lieu de coder −Z en dur : le jour où une arme
			# aura un canon incliné ou une optique décalée, la vue suivra le modèle au lieu de
			# mentir. `sightAxis` vaut (0,0,−1) sur les quatre armes d'aujourd'hui.
			var axe: Vector3 = nodes.get("sightAxis", Vector3(0, 0, -1))
			if axe.length() < 1e-6:
				axe = Vector3(0, 0, -1)
			axe = axe.normalized()
			var oeil := sight - axe * RECUL_OEIL
			camera.position = oeil
			camera.look_at(oeil + axe, Vector3.UP)
			return true
	push_warning("shot_vue3d_weapons : vue inconnue « %s »." % vue)
	return false


# Cadre la caméra sur la boîte englobante de l'arme, dans la direction `dir`. Copie EXACTE de la
# formule de `shot_vue3d_parts.gd` (rayon de la diagonale, marge 1,25) — seule la direction est
# devenue un paramètre, pour que le 3/4 et le profil partagent la même distance apparente.
func _frame(camera: Camera3D, box: AABB, dir: Vector3, zoom := 1.0) -> void:
	var centre := box.get_center()
	var rayon: float = maxf(box.size.length() * 0.5, 1e-4)
	var dist := rayon / tan(deg_to_rad(camera.fov * 0.5)) * 1.25 / zoom
	camera.position = centre + dir.normalized() * dist
	camera.look_at(centre, Vector3.UP)
