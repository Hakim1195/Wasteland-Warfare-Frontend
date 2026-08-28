extends Node
# =================================================================================================
# LA TRANCHÉE FP (§8.137) — GÉNÉRATEUR DE LA TABLE ANGULAIRE (scène-outil, patron `gen_*`).
#
# Projette la silhouette exposée de l'adversaire, depuis CHAQUE pose de tir, en FENÊTRE ANGULAIRE
# [yaw_min, yaw_max] × [pitch_min, pitch_max], et écrit `trench_angles.json` **aux DEUX
# emplacements** (§4.2) :
#   • `frontend/resources/trench/trench_angles.json`   — le rendu client (réticule, aide de visée) ;
#   • `backend/api/game/data/trench_angles.json`       — la RÉSOLUTION serveur (autorité).
#
# ╔═ POURQUOI DEUX COPIES ET UN CHECKSUM ════════════════════════════════════════════════════════╗
# ║ Le serveur ne recalcule JAMAIS d'angle : il charge une DONNÉE. C'est ce qui garde la           ║
# ║ simulation pure et le rejeu au bit près (aucun flottant issu d'un moteur 3D dans la boucle).   ║
# ║ Le prix : deux fichiers qui peuvent diverger. On paie ce prix avec un test backend qui compare ║
# ║ les checksums — la désynchronisation géométrique client/serveur devient une suite ROUGE, pas   ║
# ║ un bug de duel introuvable. Les deux fichiers sont écrits depuis LA MÊME chaîne, ici.          ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ⚠️ SÉRIALISATION À LA MAIN (et non `JSON.stringify`) : le formatage `%.4f` rend le fichier
# BYTE-STABLE d'une génération à l'autre et lisible en revue. `JSON.stringify` laisserait la
# représentation flottante décider — et un `24.590000000000003` ferait diverger un checksum sans
# qu'aucune cote n'ait bougé.
#
# LANCEMENT :
#   Godot…_console.exe --headless --path frontend res://tools/gen_trench_angles.tscn --quit-after 5
# =================================================================================================

const Geo := preload("res://scripts/game/trench_geometry.gd")
const BlockoutScene := preload("res://scenes/game/trench_arena_blockout.tscn")

const CLIENT_PATH := "res://resources/trench/trench_angles.json"
const BACKEND_RELATIVE := "../backend/api/game/data/trench_angles.json"


func _ready() -> void:
	var blockout := BlockoutScene.instantiate()
	add_child(blockout)

	# CONTRE-ÉPREUVE DE COTES, AVANT d'écrire quoi que ce soit : si une retouche du registre rendait
	# un ACCROUPI visible, la table entière deviendrait un mensonge et le jeu perdrait sa règle
	# centrale. On refuse de générer plutôt que de livrer une table fausse.
	if not Geo.crouched_is_covered():
		push_error("gen_trench_angles: INVARIANT ROMPU — un accroupi est exposé. " +
			"Corrige PARAPET_Y / EYE_DOWN / SILHOUETTE_TOP_DOWN avant de regenerer.")
		get_tree().quit(1)
		return

	var entries := _collect(blockout)
	var text := _serialize(entries)

	var written := []
	if _write(CLIENT_PATH, text):
		written.append(CLIENT_PATH)
	var backend_path := _backend_path()
	if _write(backend_path, text):
		written.append(backend_path)

	print("gen_trench_angles: %d fenetres generees (version %d)" % [entries.size(),
		Geo.TABLE_VERSION])
	# ╔═ LE BULLETIN DE LISIBILITÉ ═══════════════════════════════════════════════════════════════╗
	# ║ Ces quatre nombres sont LE critère du chantier §8.141 (« un torse de plus de 60 px se VISE, ║
	# ║ il ne se devine plus ») et les deux bornes qui en découlent. Les imprimer ICI, à la          ║
	# ║ génération, c'est refuser qu'un futur rapprochement se juge de mémoire : quiconque touche    ║
	# ║ une cote voit immédiatement ce que ça fait à la cible ET au débattement.                     ║
	# ╚═══════════════════════════════════════════════════════════════════════════════════════════╝
	var pixels_per_deg: float = 1080.0 / 55.0     # 1080p au FOV vertical nominal
	print("gen_trench_angles: silhouette debout au centre = %.3f deg de large (~%d px en 1080p)"
		% [Geo.silhouette_span_deg(), int(Geo.silhouette_span_deg() * pixels_per_deg)])
	print("gen_trench_angles: bande exposee              = %.3f deg de haut  (~%d px en 1080p)"
		% [Geo.silhouette_height_deg(), int(Geo.silhouette_height_deg() * pixels_per_deg)])
	print("gen_trench_angles: fenetre la plus excentree  = %.2f deg" % Geo.max_window_yaw_deg())
	print("gen_trench_angles: debattement de visee       = %.2f deg (camera plafonnee a %.2f)"
		% [Geo.aim_yaw_limit_deg(), Geo.camera_follow_max_deg()])
	for path in written:
		print("gen_trench_angles: ecrit -> %s" % path)
	if written.size() < 2:
		push_error("gen_trench_angles: les DEUX copies n'ont pas ete ecrites — checksum divergent.")
		get_tree().quit(1)
		return
	get_tree().quit(0)


# =================================================================================================
# COLLECTE — 5 poses de tir × 5 positions cibles, cible DEBOUT uniquement
# =================================================================================================
# ⚠️ L'ABSENCE D'ENTRÉE EST LA RÈGLE, pas un oubli : une cible ACCROUPIE n'a AUCUNE fenêtre, donc
# aucune ligne. Côté serveur, « pas de fenêtre » = « ne peut pas être touché par une balle » —
# l'invariant « accroupi injouable aux balles » est porté par la DONNÉE, pas par un `if` qu'on
# pourrait oublier. Idem pour le tireur : une pose accroupie ne tire pas (la sim le refuse en
# amont), elle n'a donc pas de ligne non plus.
func _collect(blockout) -> Array:
	var entries: Array = []
	for shooter_pos in range(Geo.POSITIONS):
		# On lit la pose SUR LE BLOCKOUT (et non via le registre) : la scène est la source de
		# vérité, le générateur n'a pas le droit d'avoir sa propre idée de l'endroit où sont les yeux.
		var eye: Vector3 = blockout.pose_transform(shooter_pos, "up").origin
		for target_pos in range(Geo.POSITIONS):
			var window: Dictionary = Geo.aim_window(eye, target_pos, "up")
			if window.is_empty():
				continue
			entries.append({
				"shooter_pos": shooter_pos,
				"target_pos": target_pos,
				"target_stance": "up",
				"yaw_min": float(window["yaw_min"]),
				"yaw_max": float(window["yaw_max"]),
				"pitch_min": float(window["pitch_min"]),
				"pitch_max": float(window["pitch_max"]),
				"pitch_head_min": float(window["pitch_head_min"]),
			})
	return entries


# =================================================================================================
# SÉRIALISATION — JSON écrit à la main, byte-stable, trié, lisible en revue
# =================================================================================================
func _f(value: float) -> String:
	# `%.4f` = 0,0001° de résolution — trois ordres de grandeur sous le quantum d'envoi (0,1°),
	# donc sans effet sur le jeu, et sans bruit de représentation flottante sur le checksum.
	# Le `+ 0.0` neutralise le « -0.0000 » que produirait un zéro négatif (piège de checksum).
	return "%.4f" % (value + 0.0)


func _serialize(entries: Array) -> String:
	var lines: Array = []
	lines.append("{")
	lines.append("  \"version\": %d," % Geo.TABLE_VERSION)
	lines.append("  \"generated_by\": \"frontend/tools/gen_trench_angles.gd\",")
	lines.append("  \"aim_quantum_deg\": %s," % _f(Geo.AIM_QUANTUM_DEG))
	lines.append("  \"note\": \"Fenetres angulaires de la silhouette exposee, en DEGRES, depuis " +
		"chaque pose de tir DEBOUT. Une cible accroupie n'a AUCUNE entree : elle est injoignable " +
		"aux balles. Regenere par gen_trench_angles.tscn — NE PAS EDITER A LA MAIN.\",")

	# --- Cotes (traçabilité : d'où sortent ces angles) ---
	var geometry: Dictionary = Geo.geometry_block()
	var geo_keys: Array = geometry.keys()
	geo_keys.sort()
	lines.append("  \"geometry\": {")
	for i in range(geo_keys.size()):
		var key := String(geo_keys[i])
		var value = geometry[key]
		var rendered: String = ("%d" % int(value)) if typeof(value) == TYPE_INT else _f(float(value))
		lines.append("    \"%s\": %s%s" % [key, rendered, "," if i < geo_keys.size() - 1 else ""])
	lines.append("  },")

	# --- Fenêtres (ordre canonique : tireur croissant, puis cible croissante) ---
	lines.append("  \"windows\": [")
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		lines.append("    {\"shooter_pos\": %d, \"target_pos\": %d, \"target_stance\": \"%s\", %s"
			% [int(e["shooter_pos"]), int(e["target_pos"]), String(e["target_stance"]),
			"\"yaw_min\": %s, \"yaw_max\": %s, \"pitch_min\": %s, \"pitch_max\": %s, \"pitch_head_min\": %s}%s" % [
				_f(e["yaw_min"]), _f(e["yaw_max"]), _f(e["pitch_min"]), _f(e["pitch_max"]),
				_f(e["pitch_head_min"]),
				"," if i < entries.size() - 1 else ""]])
	lines.append("  ]")
	lines.append("}")
	# Fin de ligne LF et saut final : mêmes conventions que le reste du dépôt (i18n CSV §8.x).
	return "\n".join(lines) + "\n"


# =================================================================================================
# ÉCRITURE
# =================================================================================================
func _backend_path() -> String:
	# `res://` globalisé + remontée d'un cran : le dépôt backend est le frère du dépôt frontend.
	return ProjectSettings.globalize_path("res://").path_join(BACKEND_RELATIVE).simplify_path()


func _write(path: String, text: String) -> bool:
	var directory := path.get_base_dir()
	if directory.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	else:
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("gen_trench_angles: ecriture impossible -> %s (err %d)"
			% [path, FileAccess.get_open_error()])
		return false
	file.store_string(text)
	file.close()
	return true
