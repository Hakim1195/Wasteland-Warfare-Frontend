extends SceneTree

# ============================================================================
# GENERATEUR DE CARTE-ID DES TERRITOIRES (outil hors-jeu, jetable/rejouable).
#
# But : produire une texture ou CHAQUE pixel encode le territoire auquel il
# appartient, en suivant les VRAIES frontieres PEINTES de board_bg.png (et non
# les polygones-hitbox approximatifs).
#
# Methode robuste :
#   1) pour chaque territoire, on construit le MASQUE de son polygone (lu en
#      texte depuis board.tscn) par remplissage SCANLINE (rapide) ;
#   2) germe = pixel le plus SATURE du masque pres du centroide (= terre peinte,
#      jamais l'ocean) ;
#   3) FLOOD-FILL borne AU MASQUE + par similarite couleur -> capture la region
#      peinte reelle (cotes), sans fuite dans l'ocean ni les voisins.
#
# Lancer SANS --path (chemins OS absolus) :
#   Godot…_console.exe --headless --script <abs>/tools/gen_territory_idmap.gd
# ============================================================================

const ROOT := "C:/Users/Hamdi/Desktop/pinciopancio/Wasteland-Warfare-Frontend/"
const BOARD_TSCN := ROOT + "scenes/game/board.tscn"
const BOARD_BG := ROOT + "assets/images/board_bg.png"
const OUT_ID := ROOT + "assets/images/territory_id_map.png"
const OUT_DEBUG := ROOT + "assets/images/territory_id_debug.png"
const OUT_JSON := ROOT + "assets/images/territory_id_order.json"

# board_bg affiche a partir de world (8, -8) -> pixel = (world.x - 8, world.y + 8).
const OFF_X := 8.0
const OFF_Y := -8.0
const THRESHOLD := 0.35  # somme |dr|+|dg|+|db| max vs couleur du germe

func _init() -> void:
	var terrs := _parse_board()
	print("Territoires trouves : ", terrs.size())
	var img := Image.load_from_file(BOARD_BG)
	if img == null:
		push_error("board_bg introuvable"); quit(1); return
	var w := img.get_width()
	var h := img.get_height()
	var ids := PackedInt32Array()
	ids.resize(w * h)

	var order := []
	for i in range(terrs.size()):
		var t = terrs[i]
		order.append(t.id)
		var n := _flood_poly(img, ids, w, h, t.poly, i + 1)
		print("  [%2d] %-22s px=%d" % [i + 1, t.id, n])

	var idimg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var dbg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var idx := ids[y * w + x]
			idimg.set_pixel(x, y, Color(float(idx) / 255.0, 0.0, 0.0, 1.0))
			dbg.set_pixel(x, y, _palette(idx))
	idimg.save_png(OUT_ID)
	dbg.save_png(OUT_DEBUG)

	var f := FileAccess.open(OUT_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify({"order": order}))
	f.close()
	print("OK -> id_map / debug / json ecrits.")
	quit()

# Flood borne au polygone (masque scanline) + similarite couleur.
func _flood_poly(img: Image, ids: PackedInt32Array, w: int, h: int, poly: PackedVector2Array, idval: int) -> int:
	# Bbox entiere clampee a l'image.
	var minx := INF
	var miny := INF
	var maxx := -INF
	var maxy := -INF
	for p in poly:
		minx = minf(minx, p.x); miny = minf(miny, p.y)
		maxx = maxf(maxx, p.x); maxy = maxf(maxy, p.y)
	var bx := clampi(int(floor(minx)), 0, w - 1)
	var by := clampi(int(floor(miny)), 0, h - 1)
	var ex := clampi(int(ceil(maxx)), 0, w - 1)
	var ey := clampi(int(ceil(maxy)), 0, h - 1)
	var bw := ex - bx + 1
	var bh := ey - by + 1
	if bw <= 0 or bh <= 0:
		return 0

	# Masque du polygone (scanline, regle pair-impair) en coords locales bbox.
	var mask := PackedByteArray()
	mask.resize(bw * bh)
	var n := poly.size()
	for ly in range(bh):
		var yc := float(by + ly) + 0.5
		var xs := []
		for i in range(n):
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if (a.y <= yc and b.y > yc) or (b.y <= yc and a.y > yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			var xa := int(ceil(xs[j] - 0.5))
			var xb := int(floor(xs[j + 1] - 0.5))
			for x in range(maxi(xa, bx), mini(xb, ex) + 1):
				mask[ly * bw + (x - bx)] = 1
			j += 2

	# Couleur du germe = COULEUR DOMINANTE (mode) de l'interieur du polygone
	# (= remplissage peint du territoire ; ignore reflets/contours/ocean minoritaire).
	var qq := 10
	var counts := {}
	var sums := {}
	for ly in range(bh):
		for lx in range(bw):
			if mask[ly * bw + lx] == 0:
				continue
			var c := img.get_pixel(bx + lx, by + ly)
			var key := (int(c.r * qq) * qq + int(c.g * qq)) * qq + int(c.b * qq)
			counts[key] = counts.get(key, 0) + 1
			sums[key] = sums.get(key, Vector3.ZERO) + Vector3(c.r, c.g, c.b)
	var best_key := -1
	var best_count := 0
	for key in counts:
		if counts[key] > best_count:
			best_count = counts[key]
			best_key = key
	if best_key < 0:
		return 0
	var sv: Vector3 = sums[best_key] / float(best_count)
	var seed_color := Color(sv.x, sv.y, sv.z)

	# Classification : tout pixel INTERIEUR au polygone proche de la couleur dominante
	# devient ce territoire (pas de connexite -> robuste aux iles / details internes).
	var count := 0
	for ly in range(bh):
		for lx in range(bw):
			if mask[ly * bw + lx] == 0:
				continue
			var x := bx + lx
			var y := by + ly
			var k := y * w + x
			if ids[k] != 0:
				continue
			var c := img.get_pixel(x, y)
			if absf(c.r - seed_color.r) + absf(c.g - seed_color.g) + absf(c.b - seed_color.b) > THRESHOLD:
				continue
			ids[k] = idval
			count += 1
	return count

func _palette(idx: int) -> Color:
	if idx <= 0:
		return Color(0.05, 0.06, 0.08, 1.0)
	return Color.from_hsv(fmod(float(idx) * 0.61803398, 1.0), 0.78, 1.0, 1.0)

# --- Parse board.tscn (texte) -> [{id, poly}] (poly en pixels board_bg). ---
func _parse_board() -> Array:
	var out := []
	var f := FileAccess.open(BOARD_TSCN, FileAccess.READ)
	if f == null:
		push_error("board.tscn introuvable")
		return out
	var lines := f.get_as_text().split("\n")
	f.close()
	var cur_id := ""
	var pos := Vector2.ZERO
	var scl := Vector2.ONE
	var poly := PackedVector2Array()
	var active := false
	for raw in lines:
		var l := raw.strip_edges()
		if l.begins_with("[node "):
			if active and cur_id != "" and poly.size() >= 3:
				out.append({"id": cur_id, "poly": _to_px(poly, pos, scl)})
			active = false
			cur_id = ""
			pos = Vector2.ZERO
			scl = Vector2.ONE
			poly = PackedVector2Array()
			if l.find('type="CollisionPolygon2D"') != -1 and l.find('parent="TerritoriesContainer/') != -1:
				var marker := 'parent="TerritoriesContainer/'
				var rest := l.substr(l.find(marker) + marker.length())
				cur_id = rest.substr(0, rest.find('"'))
				active = true
		elif active:
			if l.begins_with("position = Vector2("):
				pos = _parse_vec2(l)
			elif l.begins_with("scale = Vector2("):
				scl = _parse_vec2(l)
			elif l.begins_with("polygon = PackedVector2Array("):
				poly = _parse_poly(l)
	if active and cur_id != "" and poly.size() >= 3:
		out.append({"id": cur_id, "poly": _to_px(poly, pos, scl)})
	return out

func _to_px(poly: PackedVector2Array, pos: Vector2, scl: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(Vector2(pos.x + p.x * scl.x - OFF_X, pos.y + p.y * scl.y + OFF_Y))
	return out

func _parse_vec2(l: String) -> Vector2:
	var inside := l.substr(l.find("(") + 1)
	inside = inside.substr(0, inside.find(")"))
	var parts := inside.split(",")
	return Vector2(parts[0].to_float(), parts[1].to_float())

func _parse_poly(l: String) -> PackedVector2Array:
	var inside := l.substr(l.find("(") + 1)
	inside = inside.substr(0, inside.rfind(")"))
	var nums := inside.split(",")
	var pts := PackedVector2Array()
	var i := 0
	while i + 1 < nums.size():
		pts.append(Vector2(nums[i].to_float(), nums[i + 1].to_float()))
		i += 2
	return pts
