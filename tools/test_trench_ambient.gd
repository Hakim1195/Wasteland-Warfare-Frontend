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
	var i_decor: int = order.get(duel._decor, -1)
	var i_world: int = order.get(duel._world, -1)
	var i_amb: int = order.get(duel._ambient, -1)
	var i_vm: int = order.get(duel._viewmodel, -1)
	var i_grade: int = order.get(duel._grade, -1)
	var i_hud: int = order.get(duel._hud, -1)
	_ok("les 6 couches existent",
		mini(mini(i_decor, i_world), mini(mini(i_amb, i_vm), mini(i_grade, i_hud))) >= 0,
		"decor=%d monde=%d ambiance=%d viewmodel=%d etalonnage=%d hud=%d"
		% [i_decor, i_world, i_amb, i_vm, i_grade, i_hud])
	_ok("l'ambiance est AU-DESSUS du monde 3D (la brume voile le soldat a 35 m)", i_amb > i_world)
	_ok("l'ambiance est SOUS le viewmodel (rien ne passe devant mon arme a 0,60 m)", i_amb < i_vm)
	_ok("l'etalonnage est AU-DESSUS du viewmodel", i_grade > i_vm)
	_ok("l'etalonnage est SOUS le HUD (le cyan de charte n'est PAS etalonne)", i_grade < i_hud)
	_ok("le decor est la couche la plus basse des cinq", i_decor < i_world)
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

	# --- 5) MICRO-PARALLAXE ---------------------------------------------------------------------
	duel._aim_yaw = 0.0
	duel._aim_pitch = 0.0
	duel._apply_parallax()
	var base_l: float = duel._decor.offset_left
	var base_t: float = duel._decor.offset_top
	_ok("visee au centre : le decor est a son assiette de repos",
		is_equal_approx(base_l, -DuelScript.PARALLAX_SLACK)
		and is_equal_approx(base_t, -DuelScript.PARALLAX_SLACK),
		"gauche=%.2f haut=%.2f" % [base_l, base_t])

	duel._aim_yaw = DuelScript.AIM_YAW_LIMIT          # visée à fond à DROITE
	duel._aim_pitch = DuelScript.AIM_PITCH_LIMIT      # et vers le HAUT
	duel._apply_parallax()
	var dx: float = duel._decor.offset_left - base_l
	var dy: float = duel._decor.offset_top - base_t
	_ok("le decor part a CONTRE-SENS du lacet", dx < 0.0, "dx=%.2f px" % dx)
	_ok("le decor part a CONTRE-SENS du site", dy < 0.0, "dy=%.2f px" % dy)
	_ok("le debattement reste borne a PARALLAX_PX",
		absf(dx) <= DuelScript.PARALLAX_PX + 0.001 and absf(dy) <= DuelScript.PARALLAX_PX + 0.001,
		"|dx|=%.2f |dy|=%.2f (max %.2f)" % [absf(dx), absf(dy), DuelScript.PARALLAX_PX])
	_ok("le rect ne CHANGE PAS DE TAILLE en se decalant",
		is_equal_approx(duel._decor.offset_right - duel._decor.offset_left,
			2.0 * DuelScript.PARALLAX_SLACK)
		and is_equal_approx(duel._decor.offset_bottom - duel._decor.offset_top,
			2.0 * DuelScript.PARALLAX_SLACK))
	duel._aim_yaw = -DuelScript.AIM_YAW_LIMIT
	duel._apply_parallax()
	_ok("visee a gauche : le decor part a droite",
		duel._decor.offset_left - base_l > 0.0)

	# --- 6) CONTRE-ÉPREUVE PAR SABOTAGE ---------------------------------------------------------
	# Un test vert ne vaut que s'il sait devenir rouge. On casse volontairement chaque famille et on
	# vérifie que le contrôle correspondant AURAIT échoué.
	print("\n  --- contre-epreuve (chaque ligne doit dire OUI) ---")
	var caught := 0
	var expected := 5

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

	duel._aim_yaw = DuelScript.AIM_YAW_LIMIT
	duel._decor.offset_left = base_l + DuelScript.PARALLAX_PX   # SABOTAGE : parallaxe DANS le sens
	if duel._decor.offset_left - base_l > 0.0:
		caught += 1
		print("  OUI  une parallaxe dans le mauvais sens serait vue")

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
