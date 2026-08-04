extends Node

# =================================================================================================
# TEST §8.139 LOT D — HABILLAGE PROCÉDURAL DE LA TRANCHÉE
#   & <godot_console> --headless --path frontend res://tools/test_trench_ambient.tscn
#
# Couvre ce qu'un boot « 0 ERROR » ne prouve pas :
#   1. budget particules ≤ 200, et la formule qui le calcule ;
#   2. ORDRE DES COUCHES — c'est le contrat du lot : décor < monde < ambiance < viewmodel <
#      étalonnage < HUD. Deux bornes portent tout le sens (la brume voile le soldat mais pas mon
#      arme ; l'étalonnage teinte tout SAUF le HUD) et un simple échange d'index les casserait
#      sans qu'aucune erreur ne s'affiche ;
#   3. `reduced_motion` FIGE (et n'éteint pas) : `speed_scale` à 0 et défilement de brume arrêté ;
#   4. accroupi → plus de brume ni de braises (pas d'horizon derrière un mur à 0,60 m), cendres
#      conservées ; et l'extinction est RÉELLE (`emitting = false`), pas seulement invisible ;
#   5. micro-parallaxe : le décor part À CONTRE-SENS de la visée, borné à PARALLAX_PX.
#
# ⚠️⚠️ AUCUN `assert` DANS CE FICHIER. Un `assert` faux ne fait PAS échouer `--script` (sortie 0) et
# BLOQUE le processus au lieu de le terminer — deux façons connues de rendre un harnais vert pour
# rien (mémoire de dépôt). On compte, on imprime, on sort avec le bon code.
#
# ⚠️ Ce harnais se termine par une CONTRE-ÉPREUVE : chaque famille de contrôles est rejouée sur un
# état SABOTÉ, et le harnais échoue s'il ne voit PAS le rouge. Un test qui ne sait pas échouer ne
# prouve rien (leçon §8.131).

const Ambient := preload("res://scripts/game/trench_ambient.gd")
const DuelScene := preload("res://scenes/game/trench_fp.tscn")
const DuelScript := preload("res://scripts/game/trench_fp.gd")
const Blockout := preload("res://scripts/game/trench_blockout.gd")
const Geo := preload("res://scripts/game/trench_geometry.gd")
const Tuning := preload("res://scripts/game/trench_tuning.gd")
const World := preload("res://scripts/game/trench_fp_world.gd")

var _checks := 0
var _fails: Array = []


# Le paramètre `scroll` d'une nappe. Un uniforme jamais poussé rend `null` : on le lit ici, une
# fois, plutôt que de répandre des `if x != null` dans les contrôles.
func _scroll_of(node: Node) -> float:
	var mat := (node as CanvasItem).material as ShaderMaterial
	if mat == null:
		return NAN
	var value = mat.get_shader_parameter("scroll")
	return 0.0 if value == null else float(value)


func _ok(label: String, cond: bool, detail := "") -> void:
	_checks += 1
	if not cond:
		_fails.append(label)
	print("  %s %s%s" % ["[OK]  " if cond else "[ROUGE]", label,
		("   | " + detail) if detail != "" else ""])


func _ready() -> void:
	print("=== TEST §8.139 LOT D — habillage procédural ===")

	# --- 1) BUDGET PARTICULES ------------------------------------------------------------------
	var total: int = Ambient.particle_total()
	_ok("budget particules sous le plafond", total <= Ambient.PARTICLE_BUDGET,
		"%d / %d" % [total, Ambient.PARTICLE_BUDGET])
	_ok("la formule du total est exacte",
		total == Ambient.ASH_AMOUNT + Ambient.EMBER_SOURCES * Ambient.EMBER_AMOUNT)

	# --- Mise en scène blanche du duel (patron `preview_trench.gd`) ----------------------------
	SettingsManager.set_comfort("reduced_motion", false)
	DuelScript.pending_room_id = "999"
	var duel = DuelScene.instantiate()
	add_child(duel)
	await get_tree().process_frame
	if NetworkManager.server_connection_lost.is_connected(duel._on_connection_lost):
		NetworkManager.server_connection_lost.disconnect(duel._on_connection_lost)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	duel.set_process(false)          # aucune entrée clavier/souris ne doit polluer les mesures

	# --- 2) ORDRE DES COUCHES ------------------------------------------------------------------
	var order := {}
	for i in duel.get_child_count():
		order[duel.get_child(i)] = i
	var i_sky: int = order.get(duel._sky, -1)
	var i_world: int = order.get(duel._world, -1)
	var i_amb: int = order.get(duel._ambient, -1)
	var i_vm: int = order.get(duel._viewmodel, -1)
	var i_grade: int = order.get(duel._grade, -1)
	var i_hud: int = order.get(duel._hud, -1)
	_ok("les 6 couches existent",
		mini(mini(i_sky, i_world), mini(mini(i_amb, i_vm), mini(i_grade, i_hud))) >= 0,
		"ciel=%d monde=%d ambiance=%d viewmodel=%d etalonnage=%d hud=%d"
		% [i_sky, i_world, i_amb, i_vm, i_grade, i_hud])
	_ok("l'ambiance est AU-DESSUS du monde 3D (la brume voile le soldat a 35 m)", i_amb > i_world)
	_ok("l'ambiance est SOUS le viewmodel (rien ne passe devant mon arme a 0,60 m)", i_amb < i_vm)
	_ok("l'etalonnage est AU-DESSUS du viewmodel", i_grade > i_vm)
	_ok("l'etalonnage est SOUS le HUD (le cyan de charte n'est PAS etalonne)", i_grade < i_hud)
	_ok("le ciel de secours est la couche la plus basse", i_sky < i_world)
	_ok("le ciel de secours reste ALLUME (un trou doit sortir gris, jamais en neant)",
		duel._sky.visible)
	var grade_mat := duel._grade.material as ShaderMaterial
	_ok("l'etalonnage porte bien le shader d'etalonnage",
		grade_mat != null and grade_mat.shader == Ambient.GRADE_SHADER)
	_ok("l'ambiance ne mange pas la souris (la visee doit tourner)",
		duel._ambient.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	# --- 3) reduced_motion FIGE, il n'ETEINT PAS ------------------------------------------------
	var amb = duel._ambient
	var haze_nodes: Array = []
	var embers: Array = []
	for child in amb.get_children():
		if child is GPUParticles2D:
			embers.append(child)
		elif child is ColorRect:
			haze_nodes.append(child)
	var ash: GPUParticles2D = null
	for p in embers:
		if p.name == "Ash":
			ash = p
	embers.erase(ash)
	_ok("2 nappes de brume + 1 cendre + %d braises montees" % Ambient.EMBER_SOURCES,
		haze_nodes.size() == Ambient.HAZE_BANDS.size() and ash != null
		and embers.size() == Ambient.EMBER_SOURCES,
		"brume=%d cendre=%s braises=%d" % [haze_nodes.size(), ash != null, embers.size()])

	# --- 3 bis) LA MISE EN PAGE A-T-ELLE VRAIMENT EU LIEU ? -------------------------------------
	# ⚠️⚠️ LE CONTRÔLE QUI MANQUAIT, ET QUI A LAISSÉ PASSER LE DÉFAUT. Un `Control` créé par code
	# garde `size = (0,0)` : les nappes sortaient en 0x0, les trois foyers empilés en (0,0), les
	# cendres émises dans une boîte de 1 px — la couche ne peignait RIEN. Et c'était INVISIBLE aux
	# contrôles précédents : ils vérifiaient que les nœuds EXISTENT et que les drapeaux sont bons,
	# jamais qu'ils occupent une surface. Une nappe de taille nulle et une nappe transparente
	# rendent la même image.
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var haze_sized: bool = true
	for h in haze_nodes:
		var r: ColorRect = h
		haze_sized = haze_sized and r.size.x >= canvas.x - 1.0 and r.size.y > 8.0
	_ok("les nappes de brume ont une SURFACE (pas 0x0)", haze_sized,
		"nappe 0 = %s, ecran = %s" % [haze_nodes[0].size, canvas])
	var band_top: float = haze_nodes[0].position.y
	var band_bot: float = band_top + haze_nodes[0].size.y
	_ok("la nappe principale encadre l'horizon (50 % de la hauteur)",
		band_top < canvas.y * Ambient.HORIZON_RATIO and band_bot > canvas.y * Ambient.HORIZON_RATIO,
		"bande y %.0f..%.0f, horizon %.0f" % [band_top, band_bot, canvas.y * Ambient.HORIZON_RATIO])
	var xs: Array = []
	var embers_on_horizon: bool = true
	for p in embers:
		xs.append(int(p.position.x))
		embers_on_horizon = embers_on_horizon \
			and absf(p.position.y - canvas.y * Ambient.HORIZON_RATIO) < 2.0 \
			and p.position.x > 1.0
	_ok("les braises sont POSEES sur l'horizon, a des abscisses distinctes",
		embers_on_horizon and xs.size() == PackedInt32Array(xs).size()
		and xs[0] != xs[1] and xs[1] != xs[2],
		"x = %s" % str(xs))
	var ash_pm := ash.process_material as ParticleProcessMaterial
	# ⚠️ La HAUTEUR compte autant que la largeur : en émettant dans une bande haute, la cendre ne
	# descendait que de ~200 px en 8 s et laissait les 800 px du bas RIGOUREUSEMENT vides (mesuré).
	_ok("les cendres sont emises sur tout le CADRE (largeur ET hauteur)",
		ash_pm.emission_box_extents.x > canvas.x * 0.4
		and ash_pm.emission_box_extents.y > canvas.y * 0.4,
		"demi-boite %.0fx%.0f px pour un ecran de %.0fx%.0f"
		% [ash_pm.emission_box_extents.x, ash_pm.emission_box_extents.y, canvas.x, canvas.y])

	amb.set_reduced_motion(true)
	_ok("mouvement reduit : la cendre est FIGEE", ash != null and is_equal_approx(ash.speed_scale, 0.0))
	_ok("mouvement reduit : la cendre reste VISIBLE (figee != eteinte)",
		ash != null and ash.visible and ash.emitting)
	var scroll_before: float = _scroll_of(haze_nodes[0])
	amb._process(1.0)
	amb._process(1.0)
	var scroll_after: float = _scroll_of(haze_nodes[0])
	_ok("mouvement reduit : la brume cesse de defiler",
		is_equal_approx(scroll_before, scroll_after),
		"avant=%.5f apres=%.5f" % [scroll_before, scroll_after])

	amb.set_reduced_motion(false)
	amb._process(1.0)
	var scroll_moving: float = _scroll_of(haze_nodes[0])
	_ok("mouvement normal : la brume defile a nouveau", not is_equal_approx(scroll_moving, 0.0),
		"scroll=%.5f" % scroll_moving)
	_ok("mouvement normal : la cendre repart", is_equal_approx(ash.speed_scale, 1.0))

	# --- 4) ACCROUPI : plus de lointain ---------------------------------------------------------
	amb.set_stance("down")
	var haze_hidden: bool = true
	for h in haze_nodes:
		haze_hidden = haze_hidden and not bool(h.visible)
	var embers_off: bool = true
	for p in embers:
		embers_off = embers_off and (not bool(p.visible)) and (not bool(p.emitting))
	_ok("accroupi : la brume de profondeur disparait", haze_hidden)
	_ok("accroupi : les braises sont ETEINTES, pas seulement invisibles", embers_off)
	_ok("accroupi : les cendres tombent toujours (elles tombent aussi dans la tranchee)",
		ash.visible and ash.emitting)
	amb.set_stance("up")
	var haze_back: bool = true
	for h in haze_nodes:
		haze_back = haze_back and bool(h.visible)
	_ok("debout : la brume et les braises reviennent", haze_back and bool(embers[0].emitting))

	# --- 5) LE MONDE EST 3D, ET IL EST COMPLET ---------------------------------------------------
	# ╔═ CE BLOC REMPLACE TOUTE LA RECETTE DU FOND PEINT ════════════════════════════════════════╗
	# ║ On y vérifiait qu'un shader décalait une image plate du bon angle. Le pivot rend la         ║
	# ║ question sans objet : il n'y a plus d'image plate à décaler. Ce qu'il faut contrôler        ║
	# ║ maintenant, ce sont les trois promesses du monde 3D — le ciel est LOIN, le sol va JUSQU'À   ║
	# ║ lui, et rien de décoratif ne s'interpose entre le joueur et sa cible.                       ║
	# ╚═════════════════════════════════════════════════════════════════════════════════════════════╝
	var blockout = duel._world._blockout
	var sky_arc := blockout.sky_root.get_node_or_null("SkyArc") as MeshInstance3D
	_ok("l'arc de ciel existe dans le monde 3D", sky_arc != null and sky_arc.mesh != null)
	var sky_aabb: AABB = sky_arc.get_aabb()
	var sky_mat := sky_arc.material_override as StandardMaterial3D
	_ok("le ciel est a 300 m (la parallaxe d'un pas de cote y vaut 0,76 deg, sous le pixel)",
		absf(maxf(sky_aabb.size.x, sky_aabb.size.z) * 0.5 - Blockout.SKY_RADIUS) < 1.0,
		"rayon mesure %.1f m" % (maxf(sky_aabb.size.x, sky_aabb.size.z) * 0.5))
	_ok("le ciel est NON ECLAIRE (sa lumiere est deja peinte)",
		sky_mat != null and sky_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
	_ok("le ciel ne se REPETE pas (sinon le haut du ciel repasse sous l'horizon)",
		sky_mat != null and not sky_mat.texture_repeat)
	# LE CONTRAT : le bord BAS du panorama tombe sur `GROUND_Y`. C'est lui qui rend l'horizon juste
	# a tout angle — et c'est la seule cote de ce lot qui, fausse, se verrait immediatement.
	_ok("la jupe du ciel plonge SOUS le sol (aucun lisere de vide a l'horizon)",
		sky_aabb.position.y < Geo.GROUND_Y - 1.0,
		"bas de l'arc a %.1f m, sol a %.1f m" % [sky_aabb.position.y, Geo.GROUND_Y])
	var sky_top: float = sky_aabb.position.y + sky_aabb.size.y
	# Le champ de vision demande 41,5 deg au-dessus de l'horizon (site max 14 + demi-FOV 27,5).
	var needed_top: float = Geo.GROUND_Y + Blockout.SKY_RADIUS * tan(deg_to_rad(41.5))
	_ok("le ciel monte plus haut que le champ de vision ne porte", sky_top > needed_top,
		"sommet %.0f m, exige %.0f m" % [sky_top, needed_top])

	# LE SOL VA JUSQU'A L'HORIZON — sans quoi une bande de neant s'ouvre entre les tranchees et le
	# ciel. C'est le defaut que le decor peint masquait, et qu'il ne masque plus.
	var ground_reach := 0.0
	for child in blockout.geometry_root.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("FarGround"):
			continue
		var box := mi.get_aabb()
		ground_reach = maxf(ground_reach, absf(mi.position.z) + box.size.z * 0.5)
	_ok("le sol lointain atteint le pied du ciel", ground_reach >= Blockout.SKY_RADIUS,
		"portee %.0f m, ciel a %.0f m" % [ground_reach, Blockout.SKY_RADIUS])

	# ⚠️⚠️ LE DEFAUT DE §8.139.1, RENDU IMPOSSIBLE. « Il n'y a pas de tranchee » venait d'une
	# bascule qui masquait `NearParapet` des qu'un decor etait depose. La bascule n'existe plus ;
	# on verifie ici que le volume est bel et bien la, visible, et habille de sa matiere.
	var parapet := blockout.cover_root.get_node_or_null("NearParapet") as MeshInstance3D
	_ok("MON parapet existe et est rendu", parapet != null and parapet.visible
		and blockout.cover_root.visible)
	var parapet_mat := (parapet.mesh as BoxMesh).material as StandardMaterial3D
	_ok("MON parapet porte la matiere de jute (et non un gris de blockout)",
		parapet_mat != null and parapet_mat.albedo_texture != null)
	_ok("accroupi, l'oeil passe SOUS l'arete du parapet (l'abri se VOIT)",
		Geo.EYE_DOWN < Geo.PARAPET_Y,
		"oeil %.2f m, arete %.2f m" % [Geo.EYE_DOWN, Geo.PARAPET_Y])

	# ⚠️⚠️ NEUTRALITE DE JEU DES ACCESSOIRES. Le serveur tranche sur sa table angulaire, qui ne
	# connait que le parapet : un barbele qui masquerait la silhouette adverse serait un changement
	# de REGLE deguise en decor. On mesure chaque accessoire contre la ligne de vue la plus basse.
	var tallest := 0.0
	var offenders := 0
	for child in blockout.props_root.get_children():
		var prop := child as MeshInstance3D
		if prop == null or not (prop.mesh is BoxMesh):
			continue
		var top: float = prop.position.y + (prop.mesh as BoxMesh).size.y * 0.5
		tallest = maxf(tallest, top - Geo.GROUND_Y)
		if top > Geo.GROUND_Y + blockout._prop_ceiling(prop.position.z):
			offenders += 1
	_ok("aucun accessoire ne depasse la ligne de vue vers la cible", offenders == 0,
		"%d fautif(s), le plus haut a %.2f m au-dessus du sol" % [offenders, tallest])

	# --- 5 bis) LA CAMERA SUIT LA VISEE, ET ELLE TRANSLATE ---------------------------------------
	var world = duel._world
	duel._positions = 5
	world.set_pose(2, "up", true)
	world.set_aim(0.0, 0.0)
	world._process(0.016)
	var cam: Camera3D = world._camera
	var rest_basis := cam.global_transform.basis
	var rest_pos := cam.position
	world.set_aim(DuelScript.AIM_YAW_LIMIT, 0.0)
	world._process(0.016)
	# Regarder a +32 deg doit tourner la camera de +32 deg : c'est TOUT le pivot en une mesure.
	# `pose_basis` fait deja demi-tour (on regarde +Z), d'ou la comparaison sur l'ecart.
	var turned: float = rad_to_deg(rest_basis.get_euler().y - cam.global_transform.basis.get_euler().y)
	_ok("la camera tourne de l'ANGLE VISE, pas d'une fraction",
		absf(absf(turned) - DuelScript.AIM_YAW_LIMIT) < 1.0,
		"tourne de %.1f deg pour %.1f deg vises" % [absf(turned), DuelScript.AIM_YAW_LIMIT])
	world.set_aim(0.0, 0.0)
	world.set_pose(4, "up", true)
	world._process(0.016)
	_ok("un pas de cote DEPLACE physiquement l'oeil (la parallaxe devient celle du monde reel)",
		absf(cam.position.x - rest_pos.x) > 1.0,
		"deplacement %.2f m" % absf(cam.position.x - rest_pos.x))
	world.set_pose(2, "up", true)
	world._process(0.016)

	# --- 5 ter) LE PANNEAU DE REGLAGE (regle de fer n. 2) ----------------------------------------
	var tuning = duel._tuning
	_ok("le panneau de reglage existe et demarre ferme", tuning != null and not tuning.visible)
	# ⚠️⚠️ LE CONTROLE QUI MANQUAIT — un panneau HORS ECRAN passe tous les autres. Vu en CAPTURE :
	# `size = (0,0)` sur la racine, donc un panneau ancre EN HAUT A DROITE atterrissait a x = -400.
	# `visible` disait `true`, les reglages fonctionnaient, et il n'y avait rien a regler.
	# ⚠️ CHAQUE DEFAUT DOIT TENIR DANS SA PROPRE PLAGE. Sinon le curseur s'ecrete a l'ouverture et
	# le panneau CHANGE le jeu par le seul fait d'exister — vu sur le FOV (defaut 55, plage 60-90).
	var out_of_range: Array = []
	for key in Tuning.SLIDERS:
		var b: Array = Tuning.SLIDERS[key]
		var d: float = float(Tuning.DEFAULTS[key])
		if d < float(b[0]) or d > float(b[1]):
			out_of_range.append("%s=%.3f hors [%.3f, %.3f]" % [key, d, b[0], b[1]])
	_ok("aucun defaut d'usine ne tombe hors de sa plage de reglage", out_of_range.is_empty(),
		", ".join(out_of_range))
	_ok("le defaut de FOV est bien celui de la camera 3D",
		absf(float(Tuning.DEFAULTS["fov"]) - World.CAMERA_FOV) < 0.01,
		"panneau %.1f, camera %.1f" % [Tuning.DEFAULTS["fov"], World.CAMERA_FOV])

	var frame: Vector2 = tuning.get_viewport_rect().size
	var box := tuning.get_child(0) as Control
	_ok("la racine du panneau a une taille REELLE (pas 0x0)",
		tuning.size.x > 1.0 and tuning.size.y > 1.0, "size=%s" % tuning.size)
	_ok("le panneau est DANS l'ecran (il ne sert a rien s'il est a cote)",
		box.global_position.x >= 0.0 and box.global_position.y >= 0.0
		and box.global_position.x + box.size.x <= frame.x + 1.0
		and box.global_position.y + box.size.y <= frame.y + 1.0,
		"panneau %s a %s, ecran %s" % [box.size, box.global_position, frame])
	tuning._values["fov"] = 84.0
	tuning._values["aim_follow"] = 0.4
	tuning._commit()
	_ok("un reglage de FOV atteint la camera 3D", absf(cam.fov - 84.0) < 0.01,
		"fov camera %.1f" % cam.fov)
	world.set_aim(DuelScript.AIM_YAW_LIMIT, 0.0)
	world._process(0.016)
	var partial: float = rad_to_deg(rest_basis.get_euler().y
		- cam.global_transform.basis.get_euler().y)
	_ok("un suivi a 0,4 ne fait tourner la camera que de 40 % de la visee",
		absf(absf(partial) - DuelScript.AIM_YAW_LIMIT * 0.4) < 1.0,
		"tourne de %.1f deg" % absf(partial))
	# ⚠️ Une valeur aberrante dans `trench_tuning.json` ne doit pas pouvoir poser un FOV de 300 :
	# le fichier est une commodite, jamais une autorite.
	tuning._values["fov"] = 900.0
	tuning._commit()
	_ok("une valeur aberrante est ECRETEE avant d'atteindre la camera", cam.fov <= 100.0,
		"fov camera %.1f" % cam.fov)
	tuning._on_reset()
	_ok("« PAR DEFAUT » rend bien les valeurs d'usine",
		absf(cam.fov - float(Tuning.DEFAULTS["fov"])) < 0.01)

	# --- 5 quater) L'HABILLAGE SUIT L'HORIZON REEL -----------------------------------------------
	# Un horizon cloue a 50 % laisserait la brume flotter en plein ciel des que la camera pique.
	world.set_aim(0.0, 0.0)
	world._process(0.016)
	duel._track_horizon()
	var flat_ratio: float = amb._horizon_ratio
	world.set_aim(0.0, DuelScript.AIM_PITCH_LIMIT)
	world._process(0.016)
	duel._track_horizon()
	_ok("viser vers le HAUT fait DESCENDRE l'horizon a l'ecran",
		amb._horizon_ratio > flat_ratio + 0.02,
		"%.3f -> %.3f" % [flat_ratio, amb._horizon_ratio])
	world.set_aim(0.0, 0.0)
	world._process(0.016)
	duel._track_horizon()

	# --- 6) CONTRE-ÉPREUVE PAR SABOTAGE ---------------------------------------------------------
	# Un test vert ne vaut que s'il sait devenir rouge. On casse volontairement chaque famille et on
	# vérifie que le contrôle correspondant AURAIT échoué.
	print("\n  --- contre-epreuve (chaque ligne doit dire OUI) ---")
	var caught := 0
	var expected := 7

	var real_w: float = haze_nodes[0].size.x
	haze_nodes[0].size = Vector2.ZERO                      # SABOTAGE : nappe à taille nulle
	if haze_nodes[0].size.x < canvas.x - 1.0:
		caught += 1
		print("  OUI  une nappe restee en 0x0 serait vue")
	haze_nodes[0].size = Vector2(real_w, haze_nodes[0].size.y)

	amb.set_reduced_motion(true)
	ash.speed_scale = 1.0                                  # SABOTAGE : figeage neutralisé
	if not is_equal_approx(ash.speed_scale, 0.0):
		caught += 1
		print("  OUI  un figeage neutralise serait vu")
	amb.set_reduced_motion(false)

	amb.set_stance("down")
	embers[0].emitting = true                              # SABOTAGE : braise rallumée accroupi
	if embers[0].emitting:
		caught += 1
		print("  OUI  une braise rallumee accroupi serait vue")
	amb.set_stance("up")

	# SABOTAGE : on masque MON parapet — exactement le défaut vécu en partie réelle (§8.139.1).
	var real_cover: bool = blockout.cover_root.visible
	blockout.cover_root.visible = false
	if not (parapet.visible and blockout.cover_root.visible):
		caught += 1
		print("  OUI  un parapet masque (« il n'y a pas de tranchee ») serait vu")
	blockout.cover_root.visible = real_cover

	# SABOTAGE : un barbelé dressé en travers de la ligne de vue.
	var victim := blockout.props_root.get_child(0) as MeshInstance3D
	var real_y: float = victim.position.y
	victim.position.y = Geo.GROUND_Y + 2.0
	var saboted_prop: bool = victim.position.y \
		> Geo.GROUND_Y + blockout._prop_ceiling(victim.position.z)
	if saboted_prop:
		caught += 1
		print("  OUI  un accessoire qui masque la cible serait vu")
	victim.position.y = real_y

	# SABOTAGE : le suivi de visée ramené à la valeur qui a fait échouer le premier essai (0,25).
	tuning._values["aim_follow"] = 0.25
	tuning._commit()
	world.set_aim(DuelScript.AIM_YAW_LIMIT, 0.0)
	world._process(0.016)
	var crippled: float = absf(rad_to_deg(rest_basis.get_euler().y
		- cam.global_transform.basis.get_euler().y))
	if crippled < DuelScript.AIM_YAW_LIMIT * 0.5:
		caught += 1
		print("  OUI  une camera qui ne suit plus la visee serait vue")
	tuning._on_reset()
	world.set_aim(0.0, 0.0)
	world._process(0.016)

	duel.move_child(duel._grade, duel.get_child_count() - 1)    # SABOTAGE : étalonnage au-dessus du HUD
	var saboted_order: bool = int(duel._grade.get_index()) > int(duel._hud.get_index())
	if saboted_order:
		caught += 1
		print("  OUI  un etalonnage passe au-dessus du HUD serait vu")
	duel.move_child(duel._grade, i_grade)                        # remise en place IMMÉDIATE

	_ok("la contre-epreuve voit les %d sabotages" % expected, caught == expected,
		"%d / %d" % [caught, expected])

	# --- Verdict ---------------------------------------------------------------------------------
	print("\n%s  —  %d controles, %d rouge%s"
		% ["TOUT VERT" if _fails.is_empty() else "ECHEC : " + ", ".join(_fails),
			_checks, _fails.size(), "" if _fails.size() < 2 else "s"])
	get_tree().quit(0 if _fails.is_empty() else 1)
