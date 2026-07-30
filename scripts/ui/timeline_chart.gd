extends Control

# TIMELINE DE DOMINATION (E11 §8.83) — Control custom `_draw()` : une polyligne par joueur,
# X = rounds globaux, Y = territoires possédés, quadrillage discret de charte (§2).
#
# ⚠️ EXTRAIT de `operation_report.gd` au §8.121 : la CARTE DE PARTAGE (LOT D) dessine la même
# courbe, et l'onglet TRAHISONS une sous-fenêtre de cette même courbe. Trois copies auraient
# divergé au premier réglage de style ; un `preload` croisé entre `share_card.gd` et
# `operation_report.gd` aurait créé une inclusion CYCLIQUE de ressources. Un fichier neutre partagé
# règle les deux problèmes. Aucun changement de comportement : `setup()` et `_draw()` sont repris à
# l'identique, seuls le style de trait et la largeur sont désormais paramétrables (défauts = les
# valeurs historiques du Rapport Post-Op).

var series: Array = []   # [{ "color": Color, "points": Array[int] }]
var vmax := 1
# Épaisseur du trait : 2 px dans le rapport (700 px de large), relevée par la carte de partage
# (1920 px → un trait de 2 px y serait un cheveu).
var line_width := 2.0
# Opacité du quadrillage (4 lignes horizontales, cyan très dilué).
var grid_alpha := 0.12


func setup(s: Array) -> void:
	series = s
	vmax = 1
	for entry in s:
		for v in entry.get("points", []):
			vmax = maxi(vmax, int(v))
	queue_redraw()


func _draw() -> void:
	var r := size
	var grid := Color(0.211765, 0.772549, 0.85098, grid_alpha)
	for i in range(5):
		var y := r.y * float(i) / 4.0
		draw_line(Vector2(0, y), Vector2(r.x, y), grid, 1.0)
	var n := 0
	for entry in series:
		var pts_a: Array = entry.get("points", [])
		n = maxi(n, pts_a.size())
	if n < 2:
		return
	for entry in series:
		var pts_in: Array = entry.get("points", [])
		var poly := PackedVector2Array()
		for i in range(pts_in.size()):
			poly.append(Vector2(
				r.x * float(i) / float(n - 1),
				r.y * (1.0 - float(int(pts_in[i])) / float(vmax))))
		if poly.size() >= 2:
			draw_polyline(poly, entry.get("color", Color.WHITE), line_width, true)
