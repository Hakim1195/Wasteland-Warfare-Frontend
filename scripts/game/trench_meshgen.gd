extends RefCounted
# =================================================================================================
# LA TRANCHÉE — VUE 3D (§8.152 LOT 3D-0, moitié « maillages ») — LA FONDERIE DE GÉOMÉTRIE.
#
# Port de `War-Of-Indipendence/Claude-of-Duty-main/src/weapons/geometry.js` (447 l.).
# C'est le SOCLE : `trench_wparts.gd` (3D-A), `trench_weapons3d.gd` (3D-B), `trench_hands.gd`
# (3D-D) et `trench_soldier3d.gd` (3D-G) ne construisent RIEN autrement qu'avec les primitives
# d'ici. Aucune ligne de ce fichier ne connaît une arme, une main ou un soldat.
#
# ╔═ LES TROIS RÈGLES DE LA RÉFÉRENCE, RECOPIÉES PARCE QU'ELLES GOUVERNENT TOUT LE CHANTIER ══════╗
# ║ 1. « There is no such thing as a 90-degree edge on a real firearm. » Chaque boîte est         ║
# ║    chanfreinée de 0,3 à 1,5 mm, chaque extrusion est biseautée, chaque bout de tube reçoit    ║
# ║    un profil couronné. C'est CE fait qui sépare « modélisé » de « blockout » : un chanfrein   ║
# ║    accroche une ligne spéculaire et donne sa lisibilité à la silhouette.                      ║
# ║ 2. Les pièces sont écrites en MÈTRES à l'échelle réelle, dans le repère de l'arme :           ║
# ║    **+X à droite, +Y en haut, −Z vers la bouche du canon** (la convention caméra), origine à  ║
# ║    l'ancrage de la main de tir (la commissure du pouce, haut-arrière de la poignée).          ║
# ║    ⚠️ C'est aussi la convention de Godot (la caméra regarde −Z) : rien à transposer.          ║
# ║ 3. Tout passe par `Assembly`, qui transforme chaque pièce dans le repère de l'arme, la RANGE  ║
# ║    PAR MATÉRIAU et fusionne les seaux. « A whole rifle lands in 6-8 draw calls. »             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ ⚠️⚠️ LE SENS DE PARCOURS DES TRIANGLES EST INVERSÉ ENTRE THREE.JS ET GODOT ══════════════════╗
# ║ Three.js suit OpenGL : face AVANT = parcours TRIGONOMÉTRIQUE vu de l'extérieur.               ║
# ║ **Godot fait l'inverse : face avant = parcours HORAIRE.**                                     ║
# ║ Un portage qui recopie l'ordre des indices produit un maillage RETOURNÉ — invisible tant      ║
# ║ qu'on est en `CULL_DISABLED`, et « le modèle a disparu » dès qu'on rétablit le culling.       ║
# ║                                                                                               ║
# ║ PARADE, en deux verrous plutôt qu'en un :                                                     ║
# ║  1. AUCUNE primitive n'écrit d'indices. Tout passe par `_quad()` / `_tri()`, qui reçoivent    ║
# ║     les sommets AVEC LEUR NORMALE et ORIENTENT le triangle d'après elle. Le sens de parcours  ║
# ║     n'est donc jamais « raisonné » par le porteur : il est DÉDUIT de la normale analytique,   ║
# ║     qui est, elle, une donnée du dessin de la pièce. Toute une famille de bourdes disparaît.  ║
# ║  2. La sonde `probe_vue3d_meshgen` ne se contente PAS de re-vérifier ce point (ce serait une  ║
# ║     tautologie) : elle mesure le VOLUME SIGNÉ des solides fermés. Un maillage globalement     ║
# ║     retourné rend un volume NÉGATIF — un contrôle qui ne PEUT PAS être satisfait par          ║
# ║     construction, et qui rougit sur le sabotage « inverser tous les triangles ».              ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ÉCARTS ASSUMÉS vis-à-vis de `geometry.js` :
#   • `THREE.BufferGeometry` → `MeshData` (classe interne, quatre tableaux compacts). On ne passe
#     PAS par `SurfaceTool` : il est fait pour construire UNE surface, pas pour fusionner des
#     centaines de pièces — et `Assembly` ne fait que ça. Les tableaux se concatènent en O(n).
#   • `RoundedBoxGeometry` n'existe pas dans Godot. Reconstruite dans `box()` avec une topologie
#     PROPRE (6 faces + 12 arêtes + 8 coins) au lieu du cube subdivisé que three.js déforme
#     sommet par sommet. **Même surface, mêmes normales analytiques, moins de triangles.**
#   • `LatheGeometry` / `ExtrudeGeometry` / `TorusGeometry` / `OctahedronGeometry` : réécrites.
#     Le schéma de normales du tour reproduit celui de three.js — moyenne des deux segments
#     adjacents — parce que les profils de la référence sont DESSINÉS pour ce lissage-là.
#   • `dispose()` n'a pas d'équivalent : GDScript compte les références.
#   • les UV sont planaires/cylindriques simples. Elles comptent peu ici : le lot 3D-C n'utilise
#     PAS leurs shaders GLSL (le cahier §3 l'interdit) mais des `StandardMaterial3D`, dont l'usure
#     roule sur la courbure et la position, pas sur l'UV.
#
# ⚠️ COÛT : tout ce fichier tourne AU CHARGEMENT, jamais par frame (règle n°5 du cahier §4).
# Une arme se génère une fois, se fusionne, et devient un `ArrayMesh` figé.
# =================================================================================================


# =================================================================================================
# `MeshData` — LE TAMPON DE GÉOMÉTRIE : positions, normales, UV, indices
# =================================================================================================
# L'équivalent local de `THREE.BufferGeometry`, réduit aux trois attributs que `normalizeAttributes`
# conserve chez eux (`KEEP_ATTRS = ['position','normal','uv']`) — pas de tangentes, pas de couleurs,
# pas de morphs : rien de ce que la fusion ne saurait réconcilier.
class MeshData:
	extends RefCounted

	# Tolérance de soudure. Déclarée ICI et non au niveau du script : une classe interne GDScript
	# ne voit pas la portée de son script englobant (constantes comprises) — cf. le pavé de
	# `weld_data`, qui documente la vérification faite dans le moteur.
	const WELD_QUANTUM := 1e-6

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# ⚠️ VIDE tant que `bake_curvature()` n'a pas tourné. La couleur de sommet ne porte PAS une
	# couleur : elle porte le MASQUE DE COURBURE (convexité), que le lot 3D-C transforme en usure
	# d'arête. Cf. `bake_curvature`. On la cuit APRÈS la fusion, sur le maillage final.
	var colors := PackedColorArray()

	func vertex_count() -> int:
		return positions.size()

	func tri_count() -> int:
		return indices.size() / 3

	func is_empty() -> bool:
		return indices.is_empty()

	func add_vertex(p: Vector3, n: Vector3, uv := Vector2.ZERO) -> int:
		var i := positions.size()
		positions.push_back(p)
		normals.push_back(n)
		uvs.push_back(uv)
		return i

	# ⚠️ SEUL point du fichier qui écrit dans `indices`. Reçoit ses sommets dans le sens TRIGO VU
	# DE L'EXTÉRIEUR (la convention lisible, celle de la référence) et émet l'ordre HORAIRE de
	# Godot. Personne d'autre n'a le droit de toucher au tableau d'indices.
	func add_tri(a: int, b: int, c: int) -> void:
		indices.push_back(a)
		indices.push_back(c)
		indices.push_back(b)

	func add_quad(a: int, b: int, c: int, d: int) -> void:
		add_tri(a, b, c)
		add_tri(a, c, d)

	func duplicate_data() -> MeshData:
		var m := MeshData.new()
		m.positions = positions.duplicate()
		m.normals = normals.duplicate()
		m.uvs = uvs.duplicate()
		m.indices = indices.duplicate()
		m.colors = colors.duplicate()
		return m

	# Concatène une autre pièce en décalant ses indices. C'est l'opération que `Assembly` répète
	# des centaines de fois — d'où les tableaux compacts plutôt qu'un `SurfaceTool`.
	func append_data(other: MeshData) -> void:
		var base := positions.size()
		# Si une seule des deux pièces porte des couleurs, l'autre reçoit du BLANC : un tableau de
		# couleurs à trous ferait un maillage invalide, et le blanc est le neutre du masque.
		if not colors.is_empty() or not other.colors.is_empty():
			while colors.size() < base:
				colors.push_back(Color.WHITE)
			for i in other.positions.size():
				colors.push_back(other.colors[i] if i < other.colors.size() else Color.WHITE)
		positions.append_array(other.positions)
		normals.append_array(other.normals)
		uvs.append_array(other.uvs)
		var n := other.indices.size()
		var start := indices.size()
		indices.resize(start + n)
		for i in n:
			indices[start + i] = other.indices[i] + base

	# Applique une transformation. La normale suit la matrice INVERSE TRANSPOSÉE de la base : sans
	# ça, une mise à l'échelle non uniforme (il y en a — `sy`, `sz` chez les pièces) tord les
	# normales et l'éclairage ment. Déterminant NÉGATIF (miroir) ⇒ le parcours s'inverse : c'est le
	# `flipWinding` de la référence, déclenché au même endroit.
	func apply_transform(t: Transform3D) -> void:
		var nb := t.basis.inverse().transposed()
		for i in positions.size():
			positions[i] = t * positions[i]
			normals[i] = (nb * normals[i]).normalized()
		if t.basis.determinant() < 0.0:
			flip_winding()

	# ── TRANSFORMATIONS EN PLACE, CHAÎNABLES ──────────────────────────────────────────────────
	# ⚠️ Elles rendent `self`, comme les méthodes de `THREE.BufferGeometry` : `parts.js` écrit
	# couramment `knurlBand(...).translate(0, 0, 0.0102)` et enchaîne `rotateZ` puis `translate`.
	# Rendre `void` obligerait à couper chaque expression en deux et à inventer des variables —
	# c'est là que les ordres d'opérations se perdent, et l'ORDRE COMPTE (leur propre commentaire
	# sur les crans de détente : « Spin in place first, THEN place »).
	func translate(x: float, y: float, z: float) -> MeshData:
		var d := Vector3(x, y, z)
		for i in positions.size():
			positions[i] = positions[i] + d
		return self

	func rotate_x(a: float) -> MeshData:
		apply_transform(Transform3D(Basis(Vector3(1, 0, 0), a), Vector3.ZERO))
		return self

	func rotate_y(a: float) -> MeshData:
		apply_transform(Transform3D(Basis(Vector3(0, 1, 0), a), Vector3.ZERO))
		return self

	func rotate_z(a: float) -> MeshData:
		apply_transform(Transform3D(Basis(Vector3(0, 0, 1), a), Vector3.ZERO))
		return self

	# `geometry.scale(x, y, z)` de three.js. Nommée `scale_by` : `scale` est un mot réservé sur
	# les Node, et l'homonymie coûterait cher un jour.
	func scale_by(x: float, y: float, z: float) -> MeshData:
		apply_transform(Transform3D(Basis.IDENTITY.scaled(Vector3(x, y, z)), Vector3.ZERO))
		return self

	# Alias de `duplicate_data()` sous le nom de la référence — `parts.js` clone beaucoup.
	func clone() -> MeshData:
		return duplicate_data()

	# Retourne les faces ET les normales — la référence fait les deux dans `flipWinding`.
	func flip_winding() -> void:
		var i := 0
		while i < indices.size():
			var t := indices[i]
			indices[i] = indices[i + 2]
			indices[i + 2] = t
			i += 3
		for j in normals.size():
			normals[j] = -normals[j]

	func aabb() -> AABB:
		if positions.is_empty():
			return AABB()
		var lo := positions[0]
		var hi := positions[0]
		for p in positions:
			lo = lo.min(p)
			hi = hi.max(p)
		return AABB(lo, hi - lo)

	# ── VOLUME SIGNÉ (théorème de la divergence) ──────────────────────────────────────────────
	# Sur un solide FERMÉ correctement orienté vers l'extérieur, il est POSITIF et vaut le vrai
	# volume. C'est le contrôle que la sonde du lot 3D-0 ne peut PAS obtenir par construction : il
	# attrape un maillage globalement retourné, que la cohérence locale sens↔normale laisse passer.
	# Triangle émis (A,B,C) en horaire ⇒ son ordre trigo sortant est (A,C,B).
	func signed_volume() -> float:
		var v := 0.0
		var i := 0
		while i < indices.size():
			var a := positions[indices[i]]
			var b := positions[indices[i + 1]]
			var c := positions[indices[i + 2]]
			v += a.dot(c.cross(b))
			i += 3
		return v / 6.0

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# `bake_curvature` — LE MASQUE D'USURE D'ARÊTE
	# ─────────────────────────────────────────────────────────────────────────────────────────
	# ╔═ POURQUOI CE MASQUE EXISTE ═══════════════════════════════════════════════════════════╗
	# ║ La règle n°3 de `materials.js` : « EDGE WEAR. […] bare bright metal on the chamfers of ║
	# ║ high-contact parts — **the single most important cue that a gun has been used** ». Une  ║
	# ║ arme dont les arêtes ne brillent pas lit comme un jouet, quelle que soit la finesse du  ║
	# ║ maillage. La référence bake ce masque dans les sommets ; on fait pareil.                ║
	# ║                                                                                         ║
	# ║ ⚠️ La couleur de sommet ne transporte PAS une couleur : elle transporte la CONVEXITÉ.   ║
	# ║ C'est `trench_wmaterials.gd` (lot 3D-C) qui la traduit en usure, et il le fait SANS     ║
	# ║ shader — le cahier §3 interdit de porter leur GLSL. Voir là-bas l'astuce de l'albédo    ║
	# ║ posé sur la couleur d'USURE et rabattu vers la couleur de base par le masque.           ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════╝
	#
	# Convexité en un point : on regarde si ses voisins passent SOUS son plan tangent. Un coin
	# saillant a tous ses voisins dessous (produit scalaire négatif) ; un méplat n'a que des
	# voisins dans le plan (produit nul) ; un creux les a au-dessus.
	#
	# ⚠️ LE VOISINAGE SE CALCULE PAR **POSITION**, PAS PAR INDICE. La soudure duplique
	# volontairement les sommets d'arête franche (normales différentes) : par indice, chaque
	# facette serait une île isolée et le chanfrein — précisément ce qu'on veut détecter — ne
	# verrait jamais la face voisine.
	# ⚠️ `gain` 2,5 et non 12 : sur une boîte chanfreinée, la convexité d'un sommet d'arête vaut
	# déjà ~0,38 — un gain de 12 la portait à 4,6, donc écrêtée à 1 PARTOUT, masque plat et inutile.
	# La valeur juste se règle au final par CAPTURES (cahier §2.2quater) ; celle-ci est réglée pour
	# que la sonde mesure un vrai contraste entre méplat et arête, pas pour « faire joli ».
	func bake_curvature(gain := 2.5, bias := 0.0) -> void:
		var n := positions.size()
		if n == 0:
			return
		var q := WELD_QUANTUM
		var group := PackedInt32Array()
		group.resize(n)
		var ids := {}
		var reps := []
		for i in n:
			var p := positions[i]
			var key := "%d|%d|%d" % [roundi(p.x / q), roundi(p.y / q), roundi(p.z / q)]
			if not ids.has(key):
				ids[key] = reps.size()
				reps.append({"p": p, "n": Vector3.ZERO, "acc": 0.0, "cnt": 0})
			group[i] = ids[key]
			reps[group[i]]["n"] += normals[i]
		for r in reps:
			var v: Vector3 = r["n"]
			r["n"] = v.normalized() if v.length_squared() > 1e-20 else Vector3.UP
		# Chaque arête de chaque triangle, dans les deux sens.
		var e := 0
		while e < indices.size():
			for k in 3:
				var ga := group[indices[e + k]]
				var gb := group[indices[e + (k + 1) % 3]]
				if ga == gb:
					continue
				var ra: Dictionary = reps[ga]
				var d: Vector3 = (reps[gb]["p"] - ra["p"])
				if d.length_squared() < 1e-20:
					continue
				# Négatif quand le voisin est SOUS le plan tangent, donc convexe.
				ra["acc"] += -d.normalized().dot(ra["n"])
				ra["cnt"] += 1
			e += 3
		if colors.size() != n:
			colors.resize(n)
		for i in n:
			var r: Dictionary = reps[group[i]]
			var c: int = r["cnt"]
			var conv := (float(r["acc"]) / float(c)) if c > 0 else 0.0
			var mask := clampf(conv * gain + bias, 0.0, 1.0)
			colors[i] = Color(mask, mask, mask, 1.0)

	# Tableaux prêts pour `ArrayMesh.add_surface_from_arrays`.
	func to_surface_arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = positions
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_TEX_UV] = uvs
		if not colors.is_empty():
			arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_INDEX] = indices
		return arr

	# ─────────────────────────────────────────────────────────────────────────────────────────
	# FUSION, SOUDURE, TRANSFORMATION — statiques PORTÉES PAR `MeshData`, pas par le script
	# ─────────────────────────────────────────────────────────────────────────────────────────
	# ⚠️ CE N'EST PAS UN CHOIX D'ESTHÉTIQUE, c'est une contrainte du langage, VÉRIFIÉE dans le
	# moteur : **une classe interne GDScript ne peut PAS appeler une fonction statique du script
	# qui la contient** (`Parse Error: Function "..." not found in base self.`, Godot 4.7). Elle
	# atteint en revanche les statiques d'une classe interne SŒUR, et le script englobant aussi.
	# Ces trois fonctions vivent donc ici, où `Assembly` les atteint ; le script expose plus bas
	# `merge_all` / `weld` / `transform_from_dict`, qui n'y délèguent que l'appel, pour garder à ce
	# fichier l'API publique de `geometry.js`.

	# `{x, y, z, rx, ry, rz, sx, sy, sz}` -> `Transform3D`. Euler XYZ, comme un `THREE.Euler`
	# construit avec 'XYZ' — c'est-à-dire la rotation X appliquée en premier.
	static func transform_from_dict(t: Dictionary) -> Transform3D:
		var b := Basis.from_euler(Vector3(
			float(t.get("rx", 0.0)),
			float(t.get("ry", 0.0)),
			float(t.get("rz", 0.0))), EULER_ORDER_XYZ)
		b = b.scaled_local(Vector3(
			float(t.get("sx", 1.0)),
			float(t.get("sy", 1.0)),
			float(t.get("sz", 1.0))))
		return Transform3D(b, Vector3(
			float(t.get("x", 0.0)),
			float(t.get("y", 0.0)),
			float(t.get("z", 0.0))))

	static func merge(list: Array) -> MeshData:
		var clean := []
		for g in list:
			if g != null and g is MeshData and not g.is_empty():
				clean.append(g)
		if clean.is_empty():
			return null
		var out := MeshData.new()
		for g in clean:
			out.append_data(g)
		return weld_data(out)

	# ── `weld_data` — SOUDURE DES SOMMETS IDENTIQUES (`mergeVertices(geo, 1e-6)` chez eux) ────
	# ⚠️ On compare POSITION **ET** NORMALE **ET** UV, comme eux : deux sommets au même endroit
	# mais de normales différentes appartiennent à deux facettes distinctes et NE DOIVENT PAS
	# fusionner — sinon chaque arête franche du modèle s'adoucit toute seule. C'est mot pour mot
	# leur commentaire : « keeping hard edges, since welding compares normals too ».
	static func weld_data(g: MeshData) -> MeshData:
		if g == null or g.is_empty():
			return g
		var out := MeshData.new()
		var remap := PackedInt32Array()
		remap.resize(g.positions.size())
		var lookup := {}
		for i in g.positions.size():
			var p := g.positions[i]
			var nn := g.normals[i]
			var uv := g.uvs[i]
			var key := "%d|%d|%d|%d|%d|%d|%d|%d" % [
				roundi(p.x / WELD_QUANTUM), roundi(p.y / WELD_QUANTUM),
				roundi(p.z / WELD_QUANTUM),
				roundi(nn.x / WELD_QUANTUM), roundi(nn.y / WELD_QUANTUM),
				roundi(nn.z / WELD_QUANTUM),
				roundi(uv.x / WELD_QUANTUM), roundi(uv.y / WELD_QUANTUM)]
			if lookup.has(key):
				remap[i] = lookup[key]
			else:
				var ni := out.add_vertex(p, nn, uv)
				lookup[key] = ni
				remap[i] = ni
		var new_index := PackedInt32Array()
		new_index.resize(g.indices.size())
		for k in g.indices.size():
			new_index[k] = remap[g.indices[k]]
		out.indices = new_index
		return out


# =================================================================================================
# ÉMETTEURS ORIENTÉS — le verrou n°1 contre l'inversion de parcours
# =================================================================================================
# ⚠️ Sous ce seuil d'aire (en m² au carré de la norme du produit vectoriel, donc ~1 µm de côté), un
# triangle est DÉGÉNÉRÉ : pas de normale géométrique, invisible à l'écran, et il casserait le
# contrôle d'étanchéité de la sonde en créant des arêtes de longueur nulle (les pôles des calottes
# en produisent). On ne l'émet donc pas du tout — three.js les garde, ça ne nous sert à rien.
const DEGENERATE_AREA_SQ := 1e-18

# Triangle orienté d'après la normale de ses sommets : (p0,p1,p2) est réordonné si son sens trigo
# ne pointe pas du même côté que la normale analytique moyenne.
static func _tri(m: MeshData, p0: Vector3, p1: Vector3, p2: Vector3,
		n0: Vector3, n1: Vector3, n2: Vector3,
		uv0 := Vector2.ZERO, uv1 := Vector2.ZERO, uv2 := Vector2.ZERO) -> void:
	var ccw := (p1 - p0).cross(p2 - p0)
	if ccw.length_squared() < DEGENERATE_AREA_SQ:
		return
	var i0 := m.add_vertex(p0, n0, uv0)
	var i1 := m.add_vertex(p1, n1, uv1)
	var i2 := m.add_vertex(p2, n2, uv2)
	if ccw.dot(n0 + n1 + n2) >= 0.0:
		m.add_tri(i0, i1, i2)
	else:
		m.add_tri(i0, i2, i1)


# Quadrilatère orienté. Découpé en deux triangles qui reçoivent chacun le même traitement — un quad
# légèrement gauche (il y en a sur les congés) reste ainsi cohérent.
static func _quad(m: MeshData, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		n0: Vector3, n1: Vector3, n2: Vector3, n3: Vector3,
		uv0 := Vector2.ZERO, uv1 := Vector2.ZERO,
		uv2 := Vector2.ZERO, uv3 := Vector2.ZERO) -> void:
	_tri(m, p0, p1, p2, n0, n1, n2, uv0, uv1, uv2)
	_tri(m, p0, p2, p3, n0, n2, n3, uv0, uv2, uv3)


# =================================================================================================
# PRIMITIVES
# =================================================================================================

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `box` — BOÎTE CHANFREINÉE. La primitive la plus utilisée du portage (60 appels côté armes).
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `chamfer` est le rayon du biseau en mètres ; `seg` = 1 donne un chanfrein à 45° franc, 2-3 un
# congé arrondi. Construction : la boîte INTÉRIEURE (demi-cotes moins r) porte 6 faces plates, ses
# 12 arêtes portent des quarts de cylindre de rayon r, ses 8 coins des octants de sphère.
# Les normales sont ANALYTIQUES (direction depuis le point le plus proche de la boîte intérieure) —
# exactement ce que calcule `RoundedBoxGeometry` — donc le raccord face↔congé est continu et le
# chanfrein « accroche une ligne spéculaire » comme l'exige la règle n°1.
static func box(w: float, h: float, d: float, chamfer := 0.0012, seg := 1) -> MeshData:
	var r: float = minf(chamfer, minf(w, minf(h, d)) * 0.49)
	if r <= 1e-5:
		return _plain_box(w, h, d)
	var s: int = maxi(1, seg)
	var e := Vector3(
		maxf(w * 0.5 - r, 0.0),
		maxf(h * 0.5 - r, 0.0),
		maxf(d * 0.5 - r, 0.0))
	var m := MeshData.new()
	# ⚠️ LE MÊME `fseg` pour les faces ET pour l'axe des chanfreins. C'est la condition
	# d'étanchéité : une face subdivisée en 3 le long d'une arête doit trouver 3 segments en face
	# d'elle sur le chanfrein, sinon ce sont des jonctions en T — la sonde D1b a mesuré
	# **96 arêtes de bord** le jour où la face a été subdivisée et le chanfrein oublié.
	var fseg := _face_seg(w, h, d)
	for axis in 3:
		for si in 2:
			_box_face(m, axis, 1.0 if si == 0 else -1.0, e, r, fseg)
	for axis in 3:
		var ua := (axis + 1) % 3
		var va := (axis + 2) % 3
		for su in 2:
			for sv in 2:
				_box_edge(m, axis, ua, va, 1.0 if su == 0 else -1.0,
					1.0 if sv == 0 else -1.0, e, r, s, fseg)
	for sx in 2:
		for sy in 2:
			for sz in 2:
				var sg := Vector3(
					1.0 if sx == 0 else -1.0,
					1.0 if sy == 0 else -1.0,
					1.0 if sz == 0 else -1.0)
				_box_corner(m, Vector3(sg.x * e.x, sg.y * e.y, sg.z * e.z), sg, r, s)
	return m


# Bloc doucement arrondi — poignées, renflements de paume, plaques de couche.
static func blob(w: float, h: float, d: float, radius := 0.006, seg := 3) -> MeshData:
	return box(w, h, d, radius, seg)


# Boîte sans chanfrein — repli quand le chanfrein demandé est sous le micron.
static func _plain_box(w: float, h: float, d: float) -> MeshData:
	var m := MeshData.new()
	var e := Vector3(w * 0.5, h * 0.5, d * 0.5)
	for axis in 3:
		for si in 2:
			# `seg = 1` : sans chanfrein il n'y a aucune arête convexe à marquer, donc aucune
			# raison de payer des sommets intérieurs.
			_box_face(m, axis, 1.0 if si == 0 else -1.0, e, 0.0, 1)
	return m


# ╔═ ⚠️ POURQUOI UNE FACE PLATE EST SUBDIVISÉE ALORS QU'UN SEUL QUAD SUFFIRAIT ═══════════════════╗
# ║ Géométriquement, un quad suffit : la face EST plate. La subdivision n'existe pas pour la      ║
# ║ forme, elle existe pour le MASQUE D'USURE (`bake_curvature`), qui vit dans les SOMMETS.       ║
# ║                                                                                               ║
# ║ Sans elle, une face n'a que 4 sommets, et ces 4 sommets sont TOUS sur la bordure du           ║
# ║ chanfrein, donc tous convexes. Le masque n'a nulle part où redescendre : il est interpolé à   ║
# ║ sa valeur de bord sur toute la face, et l'arme entière s'éclaircit uniformément au lieu de    ║
# ║ voir ses arêtes briller. Mesuré avant correction : masque min = max = 1,0 sur une boîte       ║
# ║ chanfreinée — l'usure couvrait tout, donc ne signalait rien.                                  ║
# ║                                                                                               ║
# ║ C'est exactement pour cette raison que `RoundedBoxGeometry` de three.js est un cube SUBDIVISÉ  ║
# ║ (`segments*2+1` par côté) et non 6 quads : leurs masques de courbure ont besoin de sommets     ║
# ║ intérieurs. Le premier jet de ce fichier avait « amélioré » la topologie en la minimisant —   ║
# ║ et avait supprimé du même geste la résolution dont dépend le lot 3D-C.                        ║
# ║                                                                                               ║
# ║ Coût : une boîte `seg=1` passe de 44 à 140 triangles. Assumé — c'est le prix de la seule      ║
# ║ chose que la référence désigne comme « the single most important cue that a gun has been      ║
# ║ used ».                                                                                       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
const FACE_SEG_MAX := 3
# En dessous de ce côté, une face n'a pas la place d'afficher un dégradé d'usure : la subdiviser ne
# ferait que payer des triangles. 6 mm ≈ la largeur d'une nervure de garde-main.
const FACE_SEG_MIN_SIDE := 0.006


# Combien de subdivisions mérite une pièce, d'après sa PLUS PETITE cote. Une carcasse de 4 cm en
# reçoit 3 ; une nervure de 1,4 mm en reçoit 1, et retrouve son coût d'origine.
# ⚠️ La valeur est calculée UNE FOIS pour la boîte entière, et non par face : les faces et les
# chanfreins doivent partager exactement les mêmes sommets le long de leurs arêtes communes
# (cf. `_box_edge`), ce qu'un compte variable d'une face à l'autre rendrait impossible.
static func _face_seg(w: float, h: float, d: float) -> int:
	return clampi(roundi(minf(w, minf(h, d)) / FACE_SEG_MIN_SIDE), 1, FACE_SEG_MAX)

# Une face plate perpendiculaire à `axis`, à la distance (e[axis] + r) de l'origine.
static func _box_face(m: MeshData, axis: int, sgn: float, e: Vector3, r: float,
		seg := 1) -> void:
	var ua := (axis + 1) % 3
	var va := (axis + 2) % 3
	var n := Vector3.ZERO
	n[axis] = sgn
	var eu: float = e[ua]
	var ev: float = e[va]
	var d: float = sgn * (e[axis] + r)
	var s: int = maxi(1, seg)
	for iu in s:
		for iv in s:
			var u0 := lerpf(-eu, eu, float(iu) / s)
			var u1 := lerpf(-eu, eu, float(iu + 1) / s)
			var v0 := lerpf(-ev, ev, float(iv) / s)
			var v1 := lerpf(-ev, ev, float(iv + 1) / s)
			var quad := []
			for c in [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]:
				var p := Vector3.ZERO
				p[axis] = d
				p[ua] = c.x
				p[va] = c.y
				quad.append(p)
			_quad(m, quad[0], quad[1], quad[2], quad[3], n, n, n, n,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


# Un quart de cylindre de rayon r, d'axe `axis`, posé sur l'arête (du, dv) de la boîte intérieure.
# `seg` segmente l'ARC (l'arrondi du chanfrein) ; `aseg` segmente la LONGUEUR, et doit valoir
# exactement le pas des faces voisines — voir l'avertissement dans `box()`.
static func _box_edge(m: MeshData, axis: int, ua: int, va: int, du: float, dv: float,
		e: Vector3, r: float, seg: int, aseg := 1) -> void:
	var half: float = e[axis]
	var rows := []
	var norms := []
	for i in seg + 1:
		var a := (float(i) / float(seg)) * (PI * 0.5)
		# La normale balaie de l'axe `ua` vers l'axe `va`, dans le quadrant (du, dv).
		var n := Vector3.ZERO
		n[ua] = du * cos(a)
		n[va] = dv * sin(a)
		var base := Vector3.ZERO
		base[ua] = du * e[ua]
		base[va] = dv * e[va]
		var p := base + n * r
		var col := []
		for j in aseg + 1:
			var q := p
			q[axis] = lerpf(-half, half, float(j) / float(aseg))
			col.append(q)
		rows.append(col)
		norms.append(n)
	for i in seg:
		for j in aseg:
			_quad(m, rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j],
				norms[i], norms[i], norms[i + 1], norms[i + 1],
				Vector2(float(i) / seg, float(j) / aseg),
				Vector2(float(i) / seg, float(j + 1) / aseg),
				Vector2(float(i + 1) / seg, float(j + 1) / aseg),
				Vector2(float(i + 1) / seg, float(j) / aseg))


# Un octant de sphère de rayon r centré sur le coin `c` de la boîte intérieure.
# ⚠️ La rangée `phi = π/2` est un PÔLE : tous ses points y sont confondus. On y émet donc des
# TRIANGLES, pas des quads — sans quoi la moitié d'entre eux serait dégénérée et l'étanchéité du
# maillage (arêtes de longueur nulle) ne serait plus vérifiable.
static func _box_corner(m: MeshData, c: Vector3, sg: Vector3, r: float, seg: int) -> void:
	var rows := []
	for iy in seg + 1:
		var row := []
		var phi := (float(iy) / float(seg)) * (PI * 0.5)
		for ix in seg + 1:
			var th := (float(ix) / float(seg)) * (PI * 0.5)
			row.append(Vector3(
				sg.x * cos(phi) * cos(th),
				sg.y * sin(phi),
				sg.z * cos(phi) * sin(th)))
		rows.append(row)
	var pole := Vector3(0.0, sg.y, 0.0)
	for iy in seg:
		var r0: Array = rows[iy]
		var r1: Array = rows[iy + 1]
		for ix in seg:
			if iy == seg - 1:
				_tri(m, c + r0[ix] * r, c + r0[ix + 1] * r, c + pole * r,
					r0[ix], r0[ix + 1], pole)
			else:
				_quad(m, c + r0[ix] * r, c + r1[ix] * r, c + r1[ix + 1] * r, c + r0[ix + 1] * r,
					r0[ix], r1[ix], r1[ix + 1], r0[ix + 1])


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `lathe_z` — TOUR AUTOUR DE L'AXE Z. 52 appels côté armes : canons, optiques, douilles, vis.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `profile` : liste de `Vector2(z_axial, rayon)` ou `[z, r]`, de l'arrière vers l'avant (ou
# l'inverse). Le rayon est plafonné à 1e-5 par le bas, comme chez eux — un rayon exactement nul
# ferait un sommet unique dont la normale n'est pas définie.
#
# ⚠️ LES NORMALES SONT LISSÉES D'UN SEGMENT À L'AUTRE, comme `THREE.LatheGeometry` : la normale
# d'un point intérieur est la MOYENNE des normales des deux segments qui s'y rejoignent. C'est
# pour ça que tous les profils de la référence portent des couronnes et des chanfreins — sans eux,
# un coin à 90° recevrait une normale à 45° et l'arête serait molle. **Ne pas « corriger » ce
# lissage en cassant les arêtes : ce sont les profils qui sont dessinés pour lui.**
#
# ⚠️ Un tour n'est PAS un solide fermé : ses deux extrémités de profil restent ouvertes (le rayon
# plancher de 1e-5 laisse un micro-trou là où la référence écrit un rayon nul). C'est le cas chez
# eux aussi — les pièces se ferment en s'emboîtant, pas individuellement.
static func lathe_z(profile: Array, seg := 24, phi_start := 0.0, phi_length := TAU) -> MeshData:
	var m := MeshData.new()
	var count := profile.size()
	if count < 2 or seg < 3:
		return m
	var pz := PackedFloat64Array()
	var pr := PackedFloat64Array()
	pz.resize(count)
	pr.resize(count)
	for i in count:
		var pt = profile[i]
		if pt is Vector2:
			pz[i] = pt.x
			pr[i] = maxf(1e-5, pt.y)
		else:
			pz[i] = float(pt[0])
			pr[i] = maxf(1e-5, float(pt[1]))
	# Normale d'un segment (dz, dr) du profil : sa perpendiculaire sortante, composante RADIALE
	# d'abord, AXIALE ensuite.
	var seg_n := []
	for i in count - 1:
		var v := Vector2(pz[i + 1] - pz[i], -(pr[i + 1] - pr[i]))
		if v.length_squared() < 1e-20:
			v = Vector2(1.0, 0.0)
		seg_n.append(v.normalized())
	# Normale par point : les extrémités héritent de leur unique segment, l'intérieur moyenne.
	var pt_n := []
	for i in count:
		if i == 0:
			pt_n.append(seg_n[0])
		elif i == count - 1:
			pt_n.append(seg_n[count - 2])
		else:
			var s: Vector2 = seg_n[i - 1] + seg_n[i]
			pt_n.append((seg_n[i] if s.length_squared() < 1e-20 else s).normalized())
	# Le tour. La référence lathe autour de +Y puis applique `rotateX(+90°)`, qui envoie (x, y, z)
	# sur (x, −z, y) : un point (r·cosφ, axial, r·sinφ) devient (r·cosφ, −r·sinφ, axial). On génère
	# directement sous cette forme — même orientation, sans passe de rotation.
	var closed := absf(phi_length - TAU) < 1e-6
	var rings := []
	var norms := []
	for i in count:
		var row := []
		var nrow := []
		var pn: Vector2 = pt_n[i]
		for j in seg + 1:
			var jj := 0 if (closed and j == seg) else j
			var phi := phi_start + (float(jj) / float(seg)) * phi_length
			var cphi := cos(phi)
			var sphi := -sin(phi)
			row.append(Vector3(pr[i] * cphi, pr[i] * sphi, pz[i]))
			nrow.append(Vector3(pn.x * cphi, pn.x * sphi, pn.y).normalized())
		rings.append(row)
		norms.append(nrow)
	for i in count - 1:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var n0: Array = norms[i]
		var n1: Array = norms[i + 1]
		for j in seg:
			_quad(m, r0[j], r0[j + 1], r1[j + 1], r1[j],
				n0[j], n0[j + 1], n1[j + 1], n1[j],
				Vector2(float(j) / seg, float(i) / maxf(1.0, count - 1)),
				Vector2(float(j + 1) / seg, float(i) / maxf(1.0, count - 1)),
				Vector2(float(j + 1) / seg, float(i + 1) / maxf(1.0, count - 1)),
				Vector2(float(j) / seg, float(i + 1) / maxf(1.0, count - 1)))
	return m


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `tube_z` — TUBE À PAROI RÉELLE : surface extérieure, âme intérieure, bouts COURONNÉS.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Canons, corps d'optique, silencieux, tube de crosse. La couronne (`crown`) est ce qui empêche la
# bouche du canon de se lire comme un trou découpé au ciseau : elle donne l'arrondi que la lumière
# rasante accroche.
static func tube_z(r_outer: float, r_inner: float, length: float, seg := 24,
		crown := 0.0006) -> MeshData:
	var z0 := -length * 0.5
	var z1 := length * 0.5
	var c: float = minf(crown, (r_outer - r_inner) * 0.4)
	return lathe_z([
		Vector2(z0 + c, r_inner),
		Vector2(z0, r_inner + c),
		Vector2(z0, r_outer - c),
		Vector2(z0 + c, r_outer),
		Vector2(z1 - c, r_outer),
		Vector2(z1, r_outer - c),
		Vector2(z1, r_inner + c),
		Vector2(z1 - c, r_inner),
	], seg)


# Cylindre PLEIN d'axe Z, à bords chanfreinés. `r0` arrière, `r1` avant : les deux diffèrent quand
# la pièce est légèrement conique (un canon qui s'affine, un poussoir).
static func rod_z(r0: float, r1: float, length: float, seg := 20, chamfer := 0.0008) -> MeshData:
	var z0 := -length * 0.5
	var z1 := length * 0.5
	var c: float = minf(chamfer, minf(length * 0.4, minf(r0, r1) * 0.5))
	return lathe_z([
		Vector2(z0, 0.0),
		Vector2(z0, r0 - c),
		Vector2(z0 + c, r0),
		Vector2(z1 - c, r1),
		Vector2(z1, r1 - c),
		Vector2(z1, 0.0),
	], seg)


# Calotte sphérique ouverte vers +Z — boutons, bossages, coussinets d'articulation.
# `cut` = fraction de π balayée depuis le pôle : 0,5 donne une demi-sphère, 0,6 (défaut) déborde un
# peu sous l'équateur pour que la pièce s'encastre sans laisser voir sa tranche.
# ⚠️ Même précaution de PÔLE que `_box_corner` : la rangée `th = 0` est un point unique.
static func dome(r: float, seg := 16, cut := 0.6) -> MeshData:
	var m := MeshData.new()
	var rows: int = maxi(4, roundi(seg * 0.5))
	var theta_len := PI * cut
	var grid := []
	for iy in rows + 1:
		var row := []
		var th := (float(iy) / float(rows)) * theta_len
		for ix in seg + 1:
			var phi := (float(ix % seg) / float(seg)) * TAU
			# Sphère lathée autour de +Y puis `rotateX(+90°)` : (x, y, z) → (x, −z, y).
			row.append(Vector3(sin(th) * cos(phi), -sin(th) * sin(phi), cos(th)))
		grid.append(row)
	for iy in rows:
		var r0: Array = grid[iy]
		var r1: Array = grid[iy + 1]
		for ix in seg:
			if iy == 0:
				_tri(m, r0[ix] * r, r1[ix] * r, r1[ix + 1] * r,
					Vector3(0, 0, 1), r1[ix], r1[ix + 1])
			else:
				_quad(m, r0[ix] * r, r1[ix] * r, r1[ix + 1] * r, r0[ix + 1] * r,
					r0[ix], r1[ix], r1[ix + 1], r0[ix + 1])
	return m


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `extrude` — CONTOUR 2D (plan XY) EXTRUDÉ SELON Z, AVEC UN VRAI BISEAU SUR LES DEUX FACES.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# 48 appels côté armes : plaques, dents de rail, boîtiers, pontets, carcasses. `pts` est une liste
# de `[x, y]` (ou de `Vector2`) refermée automatiquement. `opts` : `bevel` (défaut 0,0008),
# `holes` (liste de contours intérieurs).
#
# La profondeur TOTALE rendue vaut `depth`, CENTRÉE sur z = 0 : le corps mesure `depth − 2·bevel`
# et les deux couronnes ajoutent `bevel` de chaque côté. (La référence extrude de 0 à `depth` puis
# translate de `−depth/2 + bevel` ; on arrive au même endroit sans la passe de translation.)
#
# ╔═ ⚠️ LE BISEAU EST UN OFFSET **PAR SOMMET** (onglet), PAS UN OFFSET DE POLYGONE ═══════════════╗
# ║ Première écriture de ce fichier : `Geometry2D.offset_polygon` (Clipper). Rejetée, et la       ║
# ║ raison mérite d'être écrite parce qu'elle ne se voit pas à la lecture — Clipper rend un       ║
# ║ contour dont le NOMBRE DE SOMMETS diffère de l'entrée. Il n'y a alors plus de correspondance  ║
# ║ 1:1 entre le contour et son rétréci : recoudre les deux boucles par « point le plus proche »  ║
# ║ SAUTE des sommets et laisse des FENTES dans la couronne — un maillage non étanche, invisible  ║
# ║ tant qu'on ne regarde pas la pièce à contre-jour.                                             ║
# ║ L'offset PAR SOMMET garde la correspondance 1:1, donc la couronne est une bande de quads       ║
# ║ propre — ET c'est en plus ce que fait `ExtrudeGeometry` (son `getBevelVec` est un onglet).    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func extrude(pts: Array, depth: float, opts := {}) -> MeshData:
	var bevel: float = opts.get("bevel", 0.0008)
	var holes: Array = opts.get("holes", [])
	var m := MeshData.new()
	var outer := _ensure_ccw(_to_polygon(pts))
	if outer.size() < 3:
		return m
	var hole_polys := []
	for h in holes:
		var hp := _to_polygon(h)
		if hp.size() >= 3:
			# Un trou se parcourt dans le sens INVERSE du contour : c'est ce qui le fait creuser,
			# à la triangulation comme à l'orientation de sa paroi.
			hole_polys.append(_ensure_cw(hp))
	var half := depth * 0.5
	var use_bevel := bevel > 1e-6 and depth > bevel * 2.2
	var zb: float = (half - bevel) if use_bevel else half
	# Contours de la FACE : reculés d'un biseau vers l'intérieur de la MATIÈRE. Pour le contour
	# extérieur cela rétrécit la pièce ; pour un trou, cela l'AGRANDIT — c'est le même geste, la
	# matière recule de `bevel` partout.
	var outer_in := _miter_inset(outer, bevel) if use_bevel else outer
	var holes_in := []
	for hp in hole_polys:
		holes_in.append(_miter_inset(hp, bevel) if use_bevel else hp)
	# ── Les deux capots ─────────────────────────────────────────────────────────────────────────
	if holes_in.is_empty():
		var cap_tris := Geometry2D.triangulate_polygon(outer_in)
		if not cap_tris.is_empty():
			_emit_cap(m, outer_in, cap_tris, half, Vector3(0, 0, 1))
			_emit_cap(m, outer_in, cap_tris, -half, Vector3(0, 0, -1))
	else:
		if holes_in.size() > 1:
			push_warning("trench_meshgen.extrude : %d trous demandés, un seul est percé — "
				% holes_in.size()
				+ "la couture d'anneau ne traite qu'un trou (aucun appel de la référence "
				+ "n'en demande plus d'un).")
		_emit_ring_cap(m, outer_in, holes_in[0], half, Vector3(0, 0, 1))
		_emit_ring_cap(m, outer_in, holes_in[0], -half, Vector3(0, 0, -1))
	# ── Parois et couronnes : le contour extérieur, puis chaque trou ─────────────────────────────
	_emit_wall(m, outer, outer_in, zb, half, use_bevel)
	for i in hole_polys.size():
		_emit_wall(m, hole_polys[i], holes_in[i], zb, half, use_bevel)
	return m


# Recule chaque sommet de `dist` vers l'intérieur de la matière, le long de son ONGLET (la
# bissectrice des normales des deux arêtes voisines). Conserve le nombre de sommets — c'est toute
# la raison d'être de cette fonction.
static func _miter_inset(poly: PackedVector2Array, dist: float) -> PackedVector2Array:
	var n := poly.size()
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var cur := poly[i]
		var n0 := _edge_normal2(poly[(i - 1 + n) % n], cur)
		var n1 := _edge_normal2(cur, poly[(i + 1) % n])
		var mdir := n0 + n1
		mdir = (n1 if mdir.length_squared() < 1e-20 else mdir).normalized()
		# Longueur d'onglet : `dist / cos(demi-angle)`. Plafonnée à 4× sur les coins très aigus —
		# sans plafond, un coin rentrant enverrait le sommet à l'infini.
		out[i] = cur - mdir * (dist / maxf(mdir.dot(n1), 0.25))
	return out


# Un capot plat à la cote z, normale ±Z, à partir d'une triangulation déjà calculée.
static func _emit_cap(m: MeshData, poly: PackedVector2Array, tris: PackedInt32Array,
		z: float, n: Vector3) -> void:
	var i := 0
	while i < tris.size():
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		_tri(m, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), n, n, n,
			a, b, c)
		i += 3


# Une paroi : le corps droit entre ±zb, puis les deux couronnes de biseau vers ±half.
# Contour ou trou : même code, aucun cas particulier — cf. l'invariant « la matière est à gauche ».
static func _emit_wall(m: MeshData, outline: PackedVector2Array, inner: PackedVector2Array,
		zb: float, half: float, use_bevel: bool) -> void:
	var n := outline.size()
	if n < 3:
		return
	var wn := _outline_normals(outline)
	for i in n:
		var j := (i + 1) % n
		var a := outline[i]
		var b := outline[j]
		_quad(m,
			Vector3(a.x, a.y, -zb), Vector3(b.x, b.y, -zb),
			Vector3(b.x, b.y, zb), Vector3(a.x, a.y, zb),
			wn[i], wn[j], wn[j], wn[i],
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	if not use_bevel or inner.size() != n:
		return
	# Les deux couronnes, en correspondance 1:1 avec le contour. La normale du biseau est la
	# moyenne de la normale de paroi et de l'axe du capot : c'est la facette à 45° qui « accroche
	# une ligne spéculaire ».
	for i in n:
		var j := (i + 1) % n
		var a := outline[i]
		var b := outline[j]
		var a2 := inner[i]
		var b2 := inner[j]
		var mid := (wn[i] + wn[j]) * 0.5
		var bn_f := (mid + Vector3(0, 0, 1)).normalized()
		var bn_b := (mid + Vector3(0, 0, -1)).normalized()
		_quad(m,
			Vector3(a.x, a.y, zb), Vector3(b.x, b.y, zb),
			Vector3(b2.x, b2.y, half), Vector3(a2.x, a2.y, half),
			bn_f, bn_f, bn_f, bn_f)
		_quad(m,
			Vector3(a.x, a.y, -zb), Vector3(b.x, b.y, -zb),
			Vector3(b2.x, b2.y, -half), Vector3(a2.x, a2.y, -half),
			bn_b, bn_b, bn_b, bn_b)


# ╔═ L'INVARIANT « LA MATIÈRE EST À GAUCHE » — ce qui rend un cas particulier inutile ════════════╗
# ║ Le contour extérieur est stocké en TRIGO, les trous en HORAIRE (`_ensure_ccw`/`_ensure_cw`).  ║
# ║ Ce n'est pas qu'une commodité pour la triangulation : dans les DEUX cas, en parcourant la     ║
# ║ boucle, **la matière est à gauche et le vide à droite**. La perpendiculaire DROITE de l'arête ║
# ║ regarde donc toujours le vide — pour un contour comme pour un trou, sans distinction.         ║
# ║                                                                                               ║
# ║ ⚠️ CE FICHIER A EU LE BUG INVERSE, et il a coûté deux contrôles rouges : les trous étaient    ║
# ║ stockés en horaire (déjà un demi-tour) PUIS re-négés par un drapeau `flip`. Résultat : leur   ║
# ║ paroi regardait DANS la matière. Symptômes mesurés par la sonde — une plaque percée dont le   ║
# ║ volume (3845 mm³) DÉPASSAIT celui de la plaque pleine (3504 mm³), le trou AJOUTANT de la      ║
# ║ matière au lieu d'en retirer ; et un biseau qui RÉTRÉCISSAIT le trou au lieu de l'ouvrir,     ║
# ║ d'où 14 arêtes de bord. À l'écran, la pièce aurait eu l'air à peu près normale.               ║
# ║ Le drapeau a donc été SUPPRIMÉ, pas corrigé : un paramètre qui n'a qu'une valeur juste est    ║
# ║ une invitation à se tromper.                                                                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func _edge_normal2(a: Vector2, b: Vector2) -> Vector2:
	var e := b - a
	if e.length_squared() < 1e-20:
		return Vector2(1, 0)
	return Vector2(e.y, -e.x).normalized()


# Normale par SOMMET : moyenne des deux arêtes qui s'y rejoignent. Un contour arrondi
# (`round_rect`) se lisse ainsi tout seul ; un coin franc reçoit une normale à 45°, ce qui est la
# même approximation que fait `ExtrudeGeometry`.
static func _outline_normals(outline: PackedVector2Array) -> Array[Vector3]:
	var n := outline.size()
	# Tableau TYPÉ : sans ça, `wn[i]` est un Variant et toute inférence en aval échoue.
	var out: Array[Vector3] = []
	for i in n:
		var cur := outline[i]
		var s := _edge_normal2(outline[(i - 1 + n) % n], cur) \
			+ _edge_normal2(cur, outline[(i + 1) % n])
		if s.length_squared() < 1e-20:
			s = _edge_normal2(cur, outline[(i + 1) % n])
		s = s.normalized()
		out.append(Vector3(s.x, s.y, 0.0))
	return out


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `_emit_ring_cap` — LE CAPOT AJOURÉ : couture directe des deux boucles
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ╔═ ⚠️⚠️ POURQUOI PAS `Geometry2D.triangulate_polygon` ICI — MESURÉ, PAS SUPPOSÉ ════════════════╗
# ║ La méthode évidente pour trianguler une face percée est le « trou de serrure » : relier le    ║
# ║ contour au trou par une fente pour n'avoir qu'un seul polygone simple, et le donner au        ║
# ║ découpeur d'oreilles du moteur. Cette version a été écrite, puis MESURÉE, puis JETÉE.         ║
# ║                                                                                               ║
# ║ Ce que la mesure a montré (plaque 30 × 20 mm percée d'un trou 16 × 8 mm) :                    ║
# ║   • `triangulate_polygon` rend le BON NOMBRE de triangles — 32, exactement `n − 2`. Tout a    ║
# ║     l'air normal.                                                                             ║
# ║   • mais la somme de leurs aires vaut **488 mm² pour 460 attendus (+6 %)** : des triangles se ║
# ║     CHEVAUCHENT. Le maillage sortait avec 40 arêtes de bord et 40 arêtes non-manifold.        ║
# ║   • et l'écartement des lèvres de la fente n'y change RIEN : balayage de 0 à 1e-4 m, l'erreur ║
# ║     reste bloquée entre +6,1 % et +7,6 %. Ce n'est pas un problème de tolérance numérique,    ║
# ║     c'est le découpeur d'oreilles qui ne sait pas traiter un polygone qui se touche lui-même. ║
# ║                                                                                               ║
# ║ ⚠️ LEÇON À GARDER : « la fonction rend 32 triangles » n'était PAS une preuve qu'elle          ║
# ║ triangule. Le premier contrôle posé ici ne demandait qu'un COMPTE, et il était vert sur une   ║
# ║ triangulation fausse. C'est la mesure d'AIRE qui a parlé.                                     ║
# ║                                                                                               ║
# ║ MÉTHODE RETENUE — une face percée est un ANNEAU, et un anneau se coud. On part du couple de   ║
# ║ sommets le plus proche entre les deux boucles, puis on avance sur l'une ou sur l'autre en     ║
# ║ choisissant à chaque pas la diagonale la plus courte. Exactement `n_ext + n_trou` triangles,  ║
# ║ aucun chevauchement, et — le point décisif — les sommets émis sont EXACTEMENT ceux des deux   ║
# ║ boucles, donc le capot se raccorde au micron près aux couronnes de biseau : étanche par       ║
# ║ CONSTRUCTION, pas par chance.                                                                 ║
# ║                                                                                               ║
# ║ LIMITE ASSUMÉE : un seul trou, et il doit être « en face » du contour (anneau étoilé). Les    ║
# ║ 8 appels ajourés de la référence sont tous dans ce cas (chargeurs, pontet, fenêtre d'éjection,║
# ║ lentille d'optique) — aucun n'en demande deux. Au-delà, `push_warning` le dit tout haut       ║
# ║ plutôt que de rendre une pièce fausse en silence.                                             ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func _emit_ring_cap(m: MeshData, outer: PackedVector2Array, hole_in: PackedVector2Array,
		z: float, n: Vector3) -> void:
	var mo := outer.size()
	if mo < 3 or hole_in.size() < 3:
		return
	# ╔═ ⚠️ LES DEUX BOUCLES DOIVENT TOURNER DANS LE MÊME SENS POUR ÊTRE COUSUES ═════════════════╗
	# ║ Ailleurs dans ce fichier, le trou est stocké en HORAIRE et le contour en TRIGO : c'est     ║
	# ║ l'invariant « la matière est à gauche », et c'est ce qui donne aux DEUX parois leur normale║
	# ║ correcte sans cas particulier. Mais pour COUDRE un anneau, il faut l'inverse : parcourir   ║
	# ║ les deux boucles dans le même sens de rotation, sinon la couture part en VRILLE et les     ║
	# ║ triangles se chevauchent au lieu de paver.                                                 ║
	# ║ Mesuré avant cette correction : capot de 3426 mm³ au lieu de 2760 (le trou ne retirait      ║
	# ║ presque rien) et 26 arêtes de bord. On retourne donc la boucle du trou ICI, localement,    ║
	# ║ **sans toucher à celle que les parois utilisent** — les deux besoins sont contradictoires  ║
	# ║ et chacun garde le sien.                                                                   ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var hole := hole_in
	if (polygon_area(outer) >= 0.0) != (polygon_area(hole_in) >= 0.0):
		hole = hole_in.duplicate()
		hole.reverse()
	var mh := hole.size()
	# Départ au couple de sommets le plus proche : la couture démarre là où elle est la plus courte.
	var ai := 0
	var bj := 0
	var bd := INF
	for i in mo:
		for j in mh:
			var d := outer[i].distance_squared_to(hole[j])
			if d < bd:
				bd = d
				ai = i
				bj = j
	var used_a := 0
	var used_b := 0
	while used_a < mo or used_b < mh:
		var a := outer[ai % mo]
		var a1 := outer[(ai + 1) % mo]
		var b := hole[bj % mh]
		var b1 := hole[(bj + 1) % mh]
		var take_a: bool
		if used_a >= mo:
			take_a = false
		elif used_b >= mh:
			take_a = true
		else:
			# La diagonale la plus courte : c'est ce qui évite les triangles en lame de rasoir
			# quand les deux boucles n'ont pas le même nombre de sommets.
			take_a = a1.distance_squared_to(b) <= b1.distance_squared_to(a)
		# ⚠️ Le sens de parcours n'est PAS raisonné ici : `_tri` oriente d'après la normale du
		# capot, comme partout ailleurs dans ce fichier.
		if take_a:
			_tri(m, Vector3(a.x, a.y, z), Vector3(a1.x, a1.y, z), Vector3(b.x, b.y, z),
				n, n, n, a, a1, b)
			ai += 1
			used_a += 1
		else:
			_tri(m, Vector3(b.x, b.y, z), Vector3(b1.x, b1.y, z), Vector3(a.x, a.y, z),
				n, n, n, b, b1, a)
			bj += 1
			used_b += 1


static func _to_polygon(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.push_back(p if p is Vector2 else Vector2(float(p[0]), float(p[1])))
	return out


# Aire SIGNÉE : positive dans le sens trigonométrique (repère Y vers le haut).
static func polygon_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _ensure_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	if polygon_area(poly) >= 0.0:
		return poly
	var r := poly.duplicate()
	r.reverse()
	return r


static func _ensure_cw(poly: PackedVector2Array) -> PackedVector2Array:
	if polygon_area(poly) <= 0.0:
		return poly
	var r := poly.duplicate()
	r.reverse()
	return r


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `round_rect` — CONTOUR de rectangle à coins arrondis. 31 appels : c'est le contour par défaut de
# la référence, parce qu'aucune plaque d'arme n'a de coin vif (règle n°1).
# ─────────────────────────────────────────────────────────────────────────────────────────────────
static func round_rect(w: float, h: float, r: float, seg := 3) -> Array:
	var pts := []
	var rr: float = minf(r, minf(w, h) * 0.499)
	var hw := w * 0.5 - rr
	var hh := h * 0.5 - rr
	for c in [[hw, hh, 0.0], [-hw, hh, PI * 0.5], [-hw, -hh, PI], [hw, -hh, -PI * 0.5]]:
		for i in seg + 1:
			var a: float = c[2] + (float(i) / float(seg)) * (PI * 0.5)
			pts.append([c[0] + cos(a) * rr, c[1] + sin(a) * rr])
	return pts


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `ring` — TORE dans le plan XY : passants de bretelle, arceaux de pontet, anneaux QD.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ⚠️ Ordre des paramètres repris de l'appel de la référence
# (`new THREE.TorusGeometry(radius, thickness, rings, seg, arc)`) : `rings` segmente le TUBE et
# `seg` le grand cercle. C'est l'inverse de l'intuition — conservé pour que les appels se recopient
# sans réfléchir.
static func ring(radius: float, thickness: float, seg := 20, rings := 8, arc := TAU) -> MeshData:
	var m := MeshData.new()
	var closed := absf(arc - TAU) < 1e-6
	var pos := []
	var nrm := []
	for i in seg + 1:
		var ii := 0 if (closed and i == seg) else i
		var u := (float(ii) / float(seg)) * arc
		var cu := cos(u)
		var su := sin(u)
		var prow := []
		var nrow := []
		for j in rings + 1:
			var v := (float(j % rings) / float(rings)) * TAU
			var cv := cos(v)
			var sv := sin(v)
			prow.append(Vector3((radius + thickness * cv) * cu,
				(radius + thickness * cv) * su, thickness * sv))
			nrow.append(Vector3(cu * cv, su * cv, sv))
		pos.append(prow)
		nrm.append(nrow)
	for i in seg:
		for j in rings:
			_quad(m, pos[i][j], pos[i + 1][j], pos[i + 1][j + 1], pos[i][j + 1],
				nrm[i][j], nrm[i + 1][j], nrm[i + 1][j + 1], nrm[i][j + 1])
	return m


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `disc` et `flat_ring` — DEUX SURFACES PLATES DANS LE PLAN XY, normale +Z
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Équivalents de `THREE.CircleGeometry` et `THREE.RingGeometry`. Elles n'existent que pour
# l'OPTIQUE (lot 3D-B2), et ce sont deux des trois pièces qui font qu'une lunette contient du VERRE
# plutôt qu'un trou :
#   • `disc`      → le VIGNETTAGE : 6 à 8 % d'assombrissement vers le bord de la pupille de sortie,
#                    parce que le diaphragme de champ et la paroi du tube mangent les rayons
#                    extérieurs. Un disque à rampe alpha radiale, posé juste derrière l'oculaire.
#   • `flat_ring` → le HALO DE LENTILLE : l'arc fin et vif à l'intérieur du bord de l'objectif,
#                    l'intérieur de la bague réfléchi dans la face avant du verre.
# ⚠️ La référence a MESURÉ que ce halo doit rester un CHEVEU : son premier essai (0,9 à 0,965 du
# rayon utile, intensité 0,55) rendait « une bande blanche cramée de 12 px » — pire que le défaut
# qu'il corrigeait. Il vit maintenant entre 0,965 et 0,99, soit ~0,4 mm.
static func disc(radius: float, seg := 32) -> MeshData:
	var m := MeshData.new()
	if seg < 3 or radius <= 0.0:
		return m
	var n := Vector3(0, 0, 1)
	for i in seg:
		var a0 := (float(i) / float(seg)) * TAU
		var a1 := (float(i + 1) / float(seg)) * TAU
		_tri(m, Vector3.ZERO,
			Vector3(cos(a0) * radius, sin(a0) * radius, 0.0),
			Vector3(cos(a1) * radius, sin(a1) * radius, 0.0),
			n, n, n,
			Vector2(0.5, 0.5),
			Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5),
			Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5))
	return m


static func flat_ring(r_inner: float, r_outer: float, seg := 32) -> MeshData:
	var m := MeshData.new()
	if seg < 3 or r_outer <= r_inner:
		return m
	var n := Vector3(0, 0, 1)
	for i in seg:
		var a0 := (float(i) / float(seg)) * TAU
		var a1 := (float(i + 1) / float(seg)) * TAU
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		_quad(m,
			Vector3(c0.x * r_inner, c0.y * r_inner, 0.0),
			Vector3(c0.x * r_outer, c0.y * r_outer, 0.0),
			Vector3(c1.x * r_outer, c1.y * r_outer, 0.0),
			Vector3(c1.x * r_inner, c1.y * r_inner, 0.0),
			n, n, n, n)
	return m


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `screw` — VIS À TÊTE CYLINDRIQUE SIX PANS CREUX, axe +Z, tête à z = 0 tournée vers −Z.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Le six-pans est un VRAI lamage (couronne de tête + fond au fond du trou), pas un point peint :
# c'est ce qui le fait lire comme un creux sous une lumière rasante.
static func screw(r_head: float, r_shank: float, head_h: float, shank_l: float,
		seg := 12) -> MeshData:
	var r_socket := r_head * 0.52
	return merge_all([
		lathe_z([
			Vector2(0.0, r_socket),
			Vector2(0.0, r_head - 0.0002),
			Vector2(0.0002, r_head),
			Vector2(head_h, r_head),
			Vector2(head_h, r_shank),
			Vector2(head_h + shank_l, r_shank),
			Vector2(head_h + shank_l, 0.0),
		], seg),
		# Paroi + fond du lamage.
		lathe_z([
			Vector2(head_h * 0.62, 0.0),
			Vector2(head_h * 0.62, r_socket),
			Vector2(0.0, r_socket),
		], 6),
	])


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `knurl_band` — MOLETURE : une bande de petites pyramides autour d'un cylindre.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# ⭐ C'est LA pièce que les captures de Hakim imposent (§2.2bis A : « surfaces moletées » sur les
# molettes de l'optique, flancs « très moletés » du M4A1). Une moleture peinte en texture disparaît
# de profil ; celle-ci a du relief et découpe la silhouette.
# Les rangées sont DÉCALÉES d'un demi-pas une fois sur deux — c'est ce qui fait le motif en losange
# d'une vraie moleture croisée plutôt qu'un quadrillage.
static func knurl_band(radius: float, length: float, count := 28, depth := 0.0004,
		rows := 3) -> MeshData:
	var parts := []
	for r in rows:
		var z := -length * 0.5 + ((float(r) + 0.5) / float(rows)) * length
		for i in count:
			var a := (float(i) / float(count)) * TAU + float(r % 2) * (PI / float(count))
			var cell := _octahedron(depth * 2.2)
			# `cell.scale(1, 1, 0.55)` puis `rotateZ(a)` puis translation — même ordre que chez eux.
			var b := Basis(Vector3(0, 0, 1), a) * Basis.IDENTITY.scaled(Vector3(1.0, 1.0, 0.55))
			cell.apply_transform(Transform3D(b,
				Vector3(cos(a) * radius, sin(a) * radius, z)))
			parts.append(cell)
	return merge_all(parts)


# Octaèdre régulier de « rayon » r — 6 sommets sur les axes, 8 faces. C'est la cellule de moleture
# de la référence (`THREE.OctahedronGeometry(r, 0)`). Facettes FRANCHES : la normale est celle du
# plan, partagée par les trois sommets — une moleture doit scintiller, pas fondre.
static func _octahedron(r: float) -> MeshData:
	var m := MeshData.new()
	var v := [
		Vector3(r, 0, 0), Vector3(-r, 0, 0),
		Vector3(0, r, 0), Vector3(0, -r, 0),
		Vector3(0, 0, r), Vector3(0, 0, -r),
	]
	for f in [[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
			[2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]]:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var c: Vector3 = v[f[2]]
		var n := (a + b + c).normalized()
		_tri(m, a, b, c, n, n, n)
	return m


# Cannelures longitudinales fines — prise de glissière, panneaux de garde-main, nervures de
# chargeur. `axis` dit sur quel axe les nervures se répartissent.
static func serrations(w: float, h: float, length: float, count: int, depth := 0.0006,
		axis := "x") -> MeshData:
	var parts := []
	var on_x := axis == "x"
	for i in count:
		var t := -0.5 + (float(i) + 0.5) / float(count)
		var step := (w if on_x else h) / float(count)
		var rib := box(step * 0.55 if on_x else w, h if on_x else step * 0.55, length,
			depth * 0.9, 1)
		if on_x:
			rib.translate(t * w, 0.0, 0.0)
		else:
			rib.translate(0.0, t * h, 0.0)
		parts.append(rib)
	return merge_all(parts)


# ─────────────────────────────────────────────────────────────────────────────────────────────────
# `picatinny` — RAIL MIL-STD-1913 le long de Z. ⭐ Pièce contractuelle du §2.2bis A des captures.
# ─────────────────────────────────────────────────────────────────────────────────────────────────
# Cotes réelles : 21,2 mm au sommet, flancs à 45° descendant vers une taille de 15,7 mm, encoches
# de recul de 5,35 mm au pas de 10,55 mm (donc une dent de 5,2 mm). Le rail est bâti comme une
# SUITE DE BLOCS de la longueur d'une dent, pour que les encoches soient de vrais trous dans la
# silhouette — pas un placage de texture.
#
# ╔═ ⚠️ LA SURFACE TOURNÉE VERS LE CIEL EST TOUT LE PROBLÈME ═════════════════════════════════════╗
# ║ Commentaire de la référence, recopié parce qu'il porte une MESURE et une leçon, pas une       ║
# ║ opinion : leur coupe précédente posait un MÉPLAT de 20,4 mm directement sur chaque dent (le   ║
# ║ profil passait de la demi-largeur pleine à 62 % de hauteur à la demi-largeur pleine moins     ║
# ║ 0,4 mm au sommet — soit un chanfrein de 0,4 mm, c'est-à-dire aucun). 21 × 4,65 mm de métal    ║
# ║ parfaitement plat pointant vers le haut attrapent d'un coup tout le lobe spéculaire de la     ║
# ║ lumière du viewmodel : ils ont MESURÉ le rail à 0,194 en linéaire contre 0,076 pour la        ║
# ║ carcasse — un peigne brillant à 1,35 diaphragme d'écart, « le tell "jouet" le plus cité de    ║
# ║ toute l'arme ».                                                                               ║
# ║ CORRECTION, qui est aussi la vraie coupe d'un rail usiné : un chanfrein à 45° de 1,5 mm sur   ║
# ║ LES DEUX arêtes du sommet. Cela convertit 3 des 21,2 mm de largeur d'une orientation « vers   ║
# ║ le ciel » vers une orientation à 45° et — bien plus important — pose une ARÊTE GÉOMÉTRIQUE    ║
# ║ FRANCHE de part et d'autre du méplat, sur laquelle le masque de courbure (celui que suit la   ║
# ║ couche d'usure) vient se caler au lieu de baver sur toute la dent.                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func picatinny(length: float, opts := {}) -> MeshData:
	var width: float = opts.get("width", 0.0212)
	var waist: float = opts.get("waist", 0.0157)
	var base_h: float = opts.get("baseH", 0.0042)
	var top_h: float = opts.get("topH", 0.0032)
	# Pas de 10,55 mm − encoche de 5,35 mm = une dent de 5,2 mm, per MIL-STD-1913.
	var pitch: float = opts.get("pitch", 0.01055)
	var slot: float = opts.get("slot", 0.00535)
	# Chanfrein à 45° sur chaque arête du sommet. Largeur == hauteur, par définition.
	var ch: float = opts.get("crownChamfer", 0.0015)

	var teeth: int = maxi(1, floori((length + slot) / pitch))
	var tooth_len := pitch - slot
	var parts := []

	var base := box(width, base_h, length, 0.00035, 1)
	base.translate(0.0, base_h * 0.5, 0.0)
	parts.append(base)

	var profile := [
		[-waist * 0.5, 0.0],
		[-width * 0.5, top_h - ch],
		[-width * 0.5 + ch, top_h],
		[width * 0.5 - ch, top_h],
		[width * 0.5, top_h - ch],
		[waist * 0.5, 0.0],
	]
	for i in teeth:
		var z := length * 0.5 - tooth_len * 0.5 - float(i) * pitch
		if z - tooth_len * 0.5 < -length * 0.5:
			break
		var tooth := extrude(profile, tooth_len, {"bevel": 0.00025})
		tooth.translate(0.0, base_h, z)
		parts.append(tooth)
	return merge_all(parts)


# Encoche façon M-LOK : une poche en creux bordée d'une lèvre en relief, pour les lattes de
# garde-main.
static func mlok_slot(length := 0.032, wide := 0.0075, depth := 0.0022) -> MeshData:
	var inner := extrude(round_rect(length - 0.0016, wide, 0.0012, 3), depth, {"bevel": 0.0003})
	inner.translate(0.0, 0.0, -depth * 0.35)
	return merge_all([
		extrude(round_rect(length, wide + 0.0028, 0.0014, 3), 0.0016, {"bevel": 0.0004}),
		inner,
	])


# =================================================================================================
# `Assembly` — LE COLLECTEUR : range par matériau, porte les ancres, fusionne
# =================================================================================================
# ╔═ CE QUE `nodes` PORTE, ET POURQUOI C'EST AUSSI IMPORTANT QUE LA GÉOMÉTRIE ════════════════════╗
# ║ Une arme n'est pas qu'un maillage. Le rig a besoin de savoir OÙ est la bouche du canon (la    ║
# ║ flamme, la fumée), OÙ passe l'axe de visée (l'optique, et l'ADS du lot 3D-F2), OÙ se posent   ║
# ║ les deux mains (lot 3D-D), OÙ vit chaque pièce mobile (culasse, chargeur, détente — 3D-E).    ║
# ║ Ces ancres sont NOMMÉES et voyagent avec l'arme. Sans elles, chaque consommateur re-devinerait║
# ║ des coordonnées en dur, et la première retouche de modèle les ferait toutes mentir d'un coup. ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
class Assembly:
	extends RefCounted

	var name: String
	# clé de matériau -> Array[MeshData]
	var buckets := {}
	# nom d'ancre -> { "pos": Vector3, "rot": Vector3 }
	var nodes := {}

	func _init(p_name := "") -> void:
		name = p_name

	# `t` accepte les mêmes clés que la référence : x/y/z, rx/ry/rz, sx/sy/sz.
	# ⚠️ La pièce source n'est JAMAIS modifiée (`geo.clone()` chez eux) : les pièces sont
	# réutilisées d'un appel à l'autre, une mutation en place les corromprait toutes.
	func add(geo: MeshData, mat: String, t := {}) -> Assembly:
		if geo == null or geo.is_empty():
			return self
		var g := geo.duplicate_data()
		if not t.is_empty():
			g.apply_transform(MeshData.transform_from_dict(t))
		if not buckets.has(mat):
			buckets[mat] = []
		buckets[mat].append(g)
		return self

	# La même pièce des deux côtés de l'arme. Le miroir passe par un `sx` NÉGATIF, ce qui rend le
	# déterminant négatif et déclenche le retournement des faces dans `apply_transform`.
	func add_mirrored(geo: MeshData, mat: String, t := {}) -> Assembly:
		add(geo, mat, t)
		var t2 := t.duplicate()
		t2["x"] = -float(t.get("x", 0.0))
		t2["sx"] = -float(t.get("sx", 1.0))
		add(geo, mat, t2)
		return self

	func node(p_name: String, x: float, y: float, z: float,
			rx := 0.0, ry := 0.0, rz := 0.0) -> Assembly:
		nodes[p_name] = {"pos": Vector3(x, y, z), "rot": Vector3(rx, ry, rz)}
		return self

	func get_node(p_name: String) -> Dictionary:
		return nodes.get(p_name, {})

	# Total de triangles, tous seaux confondus — le « budget nommé » que le cahier §5 exige de
	# borner. À lire AVANT `build()`, qui vide les seaux.
	func total_tris() -> int:
		var n := 0
		for mat in buckets:
			for g in buckets[mat]:
				n += g.tri_count()
		return n

	# Fusionne chaque seau. Rend `{ clé_matériau: MeshData }` — un seau, un futur `draw call`.
	func build() -> Dictionary:
		var out := {}
		for mat in buckets:
			var merged := MeshData.merge(buckets[mat])
			if merged != null and not merged.is_empty():
				out[mat] = merged
		buckets.clear()
		return out


# =================================================================================================
# OUTILS DE FUSION — façade publique
# =================================================================================================
# Le TRAVAIL est dans `MeshData` (contrainte de portée du langage, expliquée là-bas). Ces fonctions
# ne font que rendre à ce fichier l'API de `geometry.js`, pour que les lots 3D-A à 3D-G appellent
# `Meshgen.merge_all(...)` là où la référence appelle `mergeAll(...)`.

static func transform_from_dict(t: Dictionary) -> Transform3D:
	return MeshData.transform_from_dict(t)


static func merge_all(list: Array) -> MeshData:
	return MeshData.merge(list)


static func weld(g: MeshData) -> MeshData:
	return MeshData.weld_data(g)


# Nombre de triangles d'une pièce finie — pour le journal de budget.
static func tri_count(g: MeshData) -> int:
	return 0 if g == null else g.tri_count()


# Un `ArrayMesh` d'une seule surface, prêt pour un `MeshInstance3D`.
static func to_array_mesh(g: MeshData, mat: Material = null) -> ArrayMesh:
	var am := ArrayMesh.new()
	if g == null or g.is_empty():
		return am
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.to_surface_arrays())
	if mat != null:
		am.surface_set_material(0, mat)
	return am
