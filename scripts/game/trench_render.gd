extends Node2D
# =================================================================================================
# LA TRANCHÉE (§8.136) — VUE PURE du champ de bataille (Règle d'Or §6.1 : AUCUNE logique de jeu,
# aucun réseau). Le contrôleur (`trench_duel.gd`) construit un VIEW-MODEL à chaque frame
# (interpolation comprise) et l'injecte par `set_view()` ; ici on ne fait que DESSINER — 100 %
# procédural à la charte Warzone Command (aucun asset : ciel toxique, ruines, barbelés, tranchées,
# soldats-silhouettes, projectiles, marqueurs d'impact, laser, arc de visée).
#
# Convention d'écran (décision n° 2) : le joueur LOCAL est TOUJOURS en BAS, l'adversaire en HAUT
# (les deux clients rendent la même partie en miroir). Le view-model parle donc en « mine/theirs »,
# jamais en slots — le mapping slot↔côté est l'affaire du contrôleur.
#
# Daltonisme (E10) : les camps ne sont pas distingués QUE par la couleur — le casque local porte
# une BANDE pleine, le casque adverse des HACHURES.
#
# view = {
#   "positions": int, "reduced_motion": bool, "time": float,
#   "mine":   {"pos": float, "stance": String, "muzzle": float, "hit": float, "disconnected": bool},
#   "theirs": {…même forme…},
#   "projectiles": [{"kind": String, "up": bool, "t": float, "from_pos": float, "target_pos": float}],
#   "markers":     [{"target_pos": int, "on_mine_side": bool, "eta": float}],
#   "lasers":      [{"up": bool, "from_pos": float, "target_pos": float}],
#   "charge":      {"active": bool, "charge": float, "target_pos": int},
#   "explosions":  [{"pos": float, "on_mine_side": bool, "t": float}],
# }
# =================================================================================================

# --- Charte (CLAUDE.md frontend §2) --------------------------------------------------------------
const COL_SKY_TOP := Color(0.045, 0.06, 0.075, 1.0)
const COL_SKY_GLOW := Color(0.12, 0.16, 0.13, 1.0)         # lueur toxique à l'horizon
const COL_RUINS := Color(0.058824, 0.07451, 0.094118, 1.0)
const COL_GROUND := Color(0.101961, 0.12549, 0.156863, 1.0)
const COL_TRENCH := Color(0.075, 0.095, 0.12, 1.0)
const COL_ACCENT := Color(0.211765, 0.772549, 0.85098, 1.0)   # cyan tactique (MOI)
const COL_ENEMY := Color(0.839216, 0.270588, 0.247059, 1.0)   # danger (LUI)
const COL_GOLD := Color(0.878431, 0.698039, 0.286275, 1.0)
const COL_TEXT := Color(0.933333, 0.952941, 0.968627, 1.0)
const COL_MUTED := Color(0.541176, 0.592157, 0.647059, 1.0)
const COL_WIRE := Color(0.32, 0.36, 0.4, 0.9)

# --- Métriques (fractions de l'écran — l'arène suit toute résolution) ----------------------------
const MY_TRENCH_Y := 0.80        # ligne de sol de MA tranchée
const THEIR_TRENCH_Y := 0.26     # ligne de sol de la SIENNE
const FIELD_LEFT := 0.16         # bande horizontale des positions (part de l'écran)
const FIELD_RIGHT := 0.84
const SOLDIER_H := 56.0          # hauteur du soldat DEBOUT (px)
const TRENCH_DEPTH := 34.0       # profondeur visuelle du parapet

var _view: Dictionary = {}


func set_view(view: Dictionary) -> void:
	_view = view
	queue_redraw()


# --- Repères partagés avec le contrôleur (l'arc de visée a besoin des mêmes maths) ---------------
func slot_x(pos: float) -> float:
	var w := get_viewport_rect().size.x
	var count := int(_view.get("positions", 5))
	var span := (FIELD_RIGHT - FIELD_LEFT) * w
	return FIELD_LEFT * w + span * (float(pos) + 0.5) / float(max(1, count))


func side_y(on_mine_side: bool) -> float:
	var h := get_viewport_rect().size.y
	return h * (MY_TRENCH_Y if on_mine_side else THEIR_TRENCH_Y)


func _draw() -> void:
	if _view.is_empty():
		return
	var size := get_viewport_rect().size
	var t := float(_view.get("time", 0.0))
	var still := bool(_view.get("reduced_motion", false))

	_draw_backdrop(size, t, still)
	_draw_trench(size, false)   # la sienne (haut)
	_draw_trench(size, true)    # la mienne (bas)
	_draw_markers(size, t)
	_draw_charge_arc(size)
	_draw_lasers(size, t, still)
	_draw_soldier(_view.get("theirs", {}), false)
	_draw_soldier(_view.get("mine", {}), true)
	_draw_projectiles(size)
	_draw_explosions(size)


# --- Décor : ciel toxique, ruines, barbelés (parallaxe FIGÉE si reduced_motion) -------------------
func _draw_backdrop(size: Vector2, t: float, still: bool) -> void:
	# Ciel : fond sombre + LUEUR TOXIQUE à l'horizon (bande dégradée en 3 rects — c'est un fond).
	draw_rect(Rect2(0, 0, size.x, size.y * THEIR_TRENCH_Y), COL_SKY_TOP, true)
	for i in range(3):
		var f := float(i + 1) / 3.0
		var band_h := size.y * 0.035
		draw_rect(Rect2(0, size.y * THEIR_TRENCH_Y - band_h * float(3 - i), size.x, band_h),
			COL_SKY_TOP.lerp(COL_SKY_GLOW, f * 0.6), true)
	# Sol du no man's land.
	draw_rect(Rect2(0, size.y * THEIR_TRENCH_Y, size.x,
		size.y * (MY_TRENCH_Y - THEIR_TRENCH_Y)), COL_GROUND, true)
	# Intérieur de MA tranchée jusqu'au bas de l'écran — sans ce rect, la couleur de fond PAR
	# DÉFAUT du viewport (gris clair) apparaissait sous le parapet (défaut vu en capture).
	draw_rect(Rect2(0, size.y * MY_TRENCH_Y, size.x, size.y * (1.0 - MY_TRENCH_Y)),
		COL_TRENCH, true)

	# Ruines en silhouette (parallaxe lente ; figée en reduced_motion). Déterministe : la skyline
	# ne « saute » jamais d'une frame à l'autre.
	var drift := 0.0 if still else fmod(t * 4.0, 97.0)
	for i in range(9):
		var bx := fposmod(float(i) * (size.x / 7.0) - drift, size.x + 120.0) - 60.0
		var bh := 28.0 + 46.0 * absf(sin(float(i) * 2.7))
		var bw := 34.0 + 30.0 * absf(cos(float(i) * 1.3))
		var by := size.y * THEIR_TRENCH_Y
		draw_rect(Rect2(bx, by - bh, bw, bh), COL_RUINS, true)
		# Toit éventré : une encoche triangulaire.
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx + bw * 0.2, by - bh), Vector2(bx + bw * 0.55, by - bh - 9.0),
			Vector2(bx + bw * 0.8, by - bh)]), COL_RUINS)

	# Barbelés au centre : deux fils + croisillons.
	var wy := size.y * (THEIR_TRENCH_Y + MY_TRENCH_Y) * 0.5
	for row in range(2):
		var yy := wy - 8.0 + 16.0 * float(row)
		draw_line(Vector2(0, yy), Vector2(size.x, yy), COL_WIRE, 1.0)
		var step := 46.0
		var x := 10.0
		while x < size.x:
			draw_line(Vector2(x - 5, yy - 5), Vector2(x + 5, yy + 5), COL_WIRE, 1.0)
			draw_line(Vector2(x - 5, yy + 5), Vector2(x + 5, yy - 5), COL_WIRE, 1.0)
			x += step


func _draw_trench(size: Vector2, mine: bool) -> void:
	var y := side_y(mine)
	var accent := COL_ACCENT if mine else COL_ENEMY
	# Fosse (sous la ligne de sol pour moi, au-dessus pour lui — l'écran est un miroir).
	var depth := TRENCH_DEPTH * (1.0 if mine else -1.0)
	draw_rect(Rect2(0, min(y, y + depth), size.x, abs(depth)), COL_TRENCH, true)
	draw_line(Vector2(0, y), Vector2(size.x, y), accent * Color(1, 1, 1, 0.35), 2.0)
	# Sacs de sable : bosses régulières le long du parapet.
	var x := 14.0
	while x < size.x:
		draw_circle(Vector2(x, y), 5.0, COL_GROUND.lerp(COL_TRENCH, 0.5))
		x += 26.0
	# Encoches des POSITIONS discrètes (repères de jeu, pas un ornement).
	var count := int(_view.get("positions", 5))
	for p in range(count):
		var px := slot_x(float(p))
		draw_line(Vector2(px - 9, y), Vector2(px + 9, y), accent * Color(1, 1, 1, 0.7), 3.0)


# --- Soldat-silhouette procédural (casque, buste, fusil) — accroupi = profil écrasé ---------------
func _draw_soldier(model: Dictionary, mine: bool) -> void:
	if model.is_empty():
		return
	var x := slot_x(float(model.get("pos", 2.0)))
	var ground := side_y(mine)
	var accent := COL_ACCENT if mine else COL_ENEMY
	var crouched: bool = str(model.get("stance", "up")) == "down"
	var h := SOLDIER_H * (0.42 if crouched else 1.0)
	# Les DEUX soldats sont DEBOUT tête en haut, chacun derrière son parapet (première capture :
	# l'adversaire « miroir » pendait tête en bas sous sa tranchée — illisible, corrigé).
	var top := ground - h
	var body := COL_RUINS.lerp(accent, 0.22)
	if bool(model.get("disconnected", false)):
		body.a = 0.5
		accent.a = 0.5

	# Buste trapézoïdal.
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 11, ground), Vector2(x + 11, ground),
		Vector2(x + 8, top + 10.0), Vector2(x - 8, top + 10.0)]), body)
	# Casque.
	var helmet_c := Vector2(x, top + 4.0)
	draw_circle(helmet_c, 9.0, body.lerp(accent, 0.35))
	# Daltonisme E10 : bande pleine (MOI) vs hachures (LUI) sur le casque.
	if mine:
		draw_line(helmet_c + Vector2(-8, 0), helmet_c + Vector2(8, 0), accent, 3.0)
	else:
		for i in range(3):
			var hx := -6.0 + 6.0 * float(i)
			draw_line(helmet_c + Vector2(hx, -6), helmet_c + Vector2(hx + 4, 6), accent, 2.0)
	# Fusil : une ligne inclinée vers la tranchée adverse (seulement DEBOUT).
	if not crouched:
		var aim_dir := -1.0 if mine else 1.0   # je vise vers le haut de l'écran, lui vers le bas
		var muzzle := Vector2(x + 15.0, top + 8.0 + aim_dir * 5.0)
		draw_line(Vector2(x - 2, top + 12.0), muzzle, COL_TEXT * Color(1, 1, 1, 0.8), 3.0)
		var flash := float(model.get("muzzle", 0.0))
		if flash > 0.0:
			draw_circle(muzzle, 5.0 + 7.0 * flash, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b,
				0.85 * flash))
	# Flash d'impact reçu : silhouette soulignée de rouge un instant.
	var hurt := float(model.get("hit", 0.0))
	if hurt > 0.0:
		draw_rect(Rect2(x - 13, top - 2, 26, h + 4),
			Color(COL_ENEMY.r, COL_ENEMY.g, COL_ENEMY.b, 0.5 * hurt), false, 2.0)


# --- Projectiles : le CLIENT interpole la trajectoire (§2.3) --------------------------------------
func _proj_points(up: bool, from_pos: float, target_pos: float) -> Array:
	# `up` = le projectile MONTE (tiré par moi, du bas vers le haut). Le départ est à hauteur de
	# canon (les DEUX soldats se tiennent au-dessus de leur ligne de tranchée).
	var y0 := side_y(up)
	var y1 := side_y(not up)
	var a := Vector2(slot_x(from_pos), y0 - 28.0)
	var b := Vector2(slot_x(target_pos), y1)
	return [a, b]


func _draw_projectiles(size: Vector2) -> void:
	for proj in _view.get("projectiles", []):
		var up := bool(proj.get("up", true))
		var t := clampf(float(proj.get("t", 0.0)), 0.0, 1.0)
		var pts := _proj_points(up, float(proj.get("from_pos", 2.0)),
			float(proj.get("target_pos", 2.0)))
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		if str(proj.get("kind", "")) == "grenade":
			# Cloche : Bézier quadratique dont le sommet culmine au milieu du no man's land.
			var apex := Vector2((a.x + b.x) * 0.5, size.y * 0.5 - size.y * 0.22)
			var p := a.lerp(apex, t).lerp(apex.lerp(b, t), t)
			draw_circle(p, 5.0, COL_GOLD)
			draw_arc(p, 7.5, 0.0, TAU, 12, COL_GOLD * Color(1, 1, 1, 0.5), 1.5)
		else:
			# Balle : traceur rectiligne, courte traîne dans le sens du vol.
			var p := a.lerp(b, t)
			var tail := a.lerp(b, max(0.0, t - 0.08))
			var col := COL_ACCENT if up else COL_ENEMY
			draw_line(tail, p, col, 2.5)
			draw_circle(p, 2.5, COL_TEXT)


# --- Marqueurs d'impact de grenade : VISIBLES PAR LA CIBLE DÈS LE LANCER (décision n° 4) ----------
func _draw_markers(size: Vector2, t: float) -> void:
	for marker in _view.get("markers", []):
		var on_mine := bool(marker.get("on_mine_side", true))
		var x := slot_x(float(marker.get("target_pos", 2)))
		var y := side_y(on_mine)
		var eta := clampf(float(marker.get("eta", 1.0)), 0.0, 1.0)   # 1 = loin, 0 = imminent
		var pulse := 0.65 + 0.35 * sin(t * 9.0)
		var col := COL_GOLD if not on_mine else COL_ENEMY
		var radius := 16.0 + 10.0 * eta
		draw_arc(Vector2(x, y), radius, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.85 * pulse), 2.0)
		draw_line(Vector2(x - radius, y), Vector2(x + radius, y),
			Color(col.r, col.g, col.b, 0.5 * pulse), 1.0)
		draw_line(Vector2(x, y - radius), Vector2(x, y + radius),
			Color(col.r, col.g, col.b, 0.5 * pulse), 1.0)


# --- Laser du CONDOR : la cible DOIT le lire (règle de design, pas un détail) ---------------------
func _draw_lasers(size: Vector2, t: float, still: bool) -> void:
	for laser in _view.get("lasers", []):
		var up := bool(laser.get("up", true))
		var pts := _proj_points(up, float(laser.get("from_pos", 2.0)),
			float(laser.get("target_pos", 2.0)))
		var blink := 1.0 if still else (0.55 + 0.45 * sin(t * 22.0))
		var col := COL_ENEMY if not up else COL_ACCENT
		draw_line(pts[0], pts[1], Color(col.r, col.g, col.b, 0.8 * blink), 2.0)
		draw_circle(pts[1], 6.0, Color(col.r, col.g, col.b, 0.6 * blink))


# --- Arc de visée de MA grenade (jauge tenue) : miroir EXACT du mapping serveur -------------------
func _draw_charge_arc(size: Vector2) -> void:
	var charge = _view.get("charge", {})
	if not bool(charge.get("active", false)):
		return
	var target := int(charge.get("target_pos", 0))
	var a := Vector2(slot_x(float(_view.get("mine", {}).get("pos", 2.0))),
		side_y(true) - 28.0)
	var b := Vector2(slot_x(float(target)), side_y(false))
	var apex := Vector2((a.x + b.x) * 0.5, size.y * 0.5 - size.y * 0.22)
	# Chevrons le long de la Bézier (savoir-faire attack_arrow : le tracé raconte le trajet).
	var steps := 14
	for i in range(steps):
		var f := float(i) / float(steps - 1)
		var p := a.lerp(apex, f).lerp(apex.lerp(b, f), f)
		var nxt := a.lerp(apex, f + 0.02).lerp(apex.lerp(b, f + 0.02), f + 0.02)
		var dir := (nxt - p).normalized()
		var side := Vector2(-dir.y, dir.x) * 4.0
		draw_line(p - dir * 4.0 + side, p, COL_GOLD * Color(1, 1, 1, 0.75), 2.0)
		draw_line(p - dir * 4.0 - side, p, COL_GOLD * Color(1, 1, 1, 0.75), 2.0)
	# Position d'arrivée : réticule fantôme.
	draw_arc(b, 15.0, 0.0, TAU, 20, COL_GOLD, 2.0)


func _draw_explosions(size: Vector2) -> void:
	for explosion in _view.get("explosions", []):
		var on_mine := bool(explosion.get("on_mine_side", true))
		var c := Vector2(slot_x(float(explosion.get("pos", 2.0))), side_y(on_mine))
		var t := clampf(float(explosion.get("t", 0.0)), 0.0, 1.0)   # 0 = début, 1 = fini
		var radius := 8.0 + 42.0 * t
		var alpha := 0.85 * (1.0 - t)
		draw_circle(c, radius * 0.5, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, alpha * 0.5))
		draw_arc(c, radius, 0.0, TAU, 24, Color(1.0, 0.6, 0.25, alpha), 3.0)
