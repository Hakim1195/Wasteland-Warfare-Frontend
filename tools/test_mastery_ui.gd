extends Node

# CONTRE-ÉPREUVES CLIENT — MAÎTRISE DE FACTION (§8.135).
#   & <godot_console> --headless --path frontend res://tools/test_mastery_ui.tscn
#
# ⚠️ CE QUE CE FICHIER GARANTIT, ET POURQUOI CHAQUE BLOC EXISTE :
#   1. les 6 tranches de bordure DESSINENT réellement quelque chose, et le rang 0 RIEN — sans ce
#      contrôle, une clé mal orthographiée dans le registre produirait un cadre vide que seul un
#      œil humain remarquerait ;
#   2. `reduced_motion` FIGE l'irisation du rang 50+ (§8.82) sans retirer la bordure ;
#   3. le sélecteur de titre fait une MAJ OPTIMISTE et un ROLLBACK sur refus — le rollback est
#      éprouvé par SABOTAGE (on injecte un refus serveur) ; sans ce cas, l'optimisme resterait
#      affiché après un refus et le joueur croirait porter un titre qu'il n'a pas ;
#   4. une purge simulée fait retomber la fiche au rang 0 ET déséquipe le titre ;
#   5. le passage de rang au Post-Op NE BLOQUE PAS « REJOUER » (règle §8.129) ;
#   6. la ligne « MAÎTRISE : RANG a → b » n'apparaît QUE si le serveur l'a demandé.
#
# ⚠️ AUCUNE de ces vues n'implémente de règle : on leur donne les payloads que le serveur produit
# (bloc `mastery`, `masteries_summary`, `mastery_rank_up`) et on regarde ce qu'elles PEIGNENT.
#
# ⚠️ LANCER SANS `--headless`. Le bloc 1 compte des PIXELS : sous le pilote de rendu factice il
# mesurerait une image vide et conclurait au vert sans rien voir. Une garde explicite arrête le test
# dans ce cas plutôt que de le laisser mentir.
#
# 📌 BRUIT DE FERMETURE CONNU (mesuré, pas supposé) : le journal se termine par ~14 lignes `ERROR`
# de type « leaked texture / RID allocations ... at exit ». Elles sont émises APRÈS le verdict, à
# l'extinction du moteur, et proviennent des cibles de rendu des ÉCRANS DE PRODUCTION instanciés
# ici (`characters_screen` et son viewport héros 3D, `operation_report` et ses shaders) — pas du
# test : leur nombre est IDENTIQUE avec un seul viewport de mesure ou avec neuf. Le boot isolé de
# ces mêmes écrans reste à 0 ERROR. Ne pas chercher de fuite dans ce fichier.

const MasteryBorder = preload("res://scripts/ui/mastery_border.gd")
const TIERS := ["steel", "bronze", "silver", "gold", "platinum", "prismatic"]

var checks := 0


func _ok(label: String, n: int) -> void:
	checks += n
	print("[OK] %s (%d asserts)" % [label, n])


# Nombre de PIXELS RÉELLEMENT PEINTS par une bordure, mesuré en la rendant dans un SubViewport
# transparent. On ne se contente PAS de vérifier que `_draw()` a été appelé : une fonction de dessin
# peut s'exécuter entièrement et ne rien produire (couleur transparente, géométrie dégénérée,
# tranche inconnue). Ici on compte l'encre.
#
# ⚠️ EXIGE UNE FENÊTRE RÉELLE. En `--headless`, Godot utilise le pilote de rendu factice : le
# viewport rend une image VIDE et ce test passerait au vert en ne mesurant rien (leçon §8.134.2 —
# « un test peut être vert en ne testant rien »). Le lanceur ci-dessous refuse donc de conclure si
# la mesure de référence est nulle.
# UN SEUL viewport de mesure, réutilisé : chaque SubViewport alloue une cible de rendu GL que le
# pilote de compatibilité ne libère qu'à la fermeture du moteur — neuf viewports produisaient neuf
# « leaked texture » à l'extinction, du bruit qui rendait le journal illisible comme verdict.
var _probe_vp: SubViewport = null


func _painted_pixels(tier: String, side: float = 96.0) -> int:
	if _probe_vp == null:
		_probe_vp = SubViewport.new()
		_probe_vp.transparent_bg = true
		_probe_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_probe_vp)
	for c in _probe_vp.get_children():
		_probe_vp.remove_child(c)
		c.free()
	_probe_vp.size = Vector2i(int(side), int(side))
	_probe_vp.add_child(MasteryBorder.make(tier, side))
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _probe_vp.get_texture().get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.05:
				n += 1
	return n


func _ready() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)

	# --- 1. LES 6 TRANCHES PEIGNENT, LE RANG 0 NON ----------------------------------------------
	SettingsManager.set_comfort("reduced_motion", false)
	var painted := {}
	for tier in TIERS:
		painted[tier] = await _painted_pixels(tier)
	# GARDE ANTI-FAUX-VERT : en headless (pilote factice) tout rend 0 et les assertions « > 0 »
	# tomberaient — mais si quelqu'un les remplaçait par « >= 0 », le test resterait vert sans rien
	# mesurer. On échoue donc BRUYAMMENT plutôt que de conclure sur une image vide.
	if int(painted[TIERS[0]]) <= 0:
		printerr("[FATAL] aucun pixel rendu : ce test EXIGE une fenetre reelle (pas --headless).")
		get_tree().quit(1)
		return
	for tier in TIERS:
		assert(int(painted[tier]) > 0)   # une tranche connue laisse de l'encre
	# Le rang 0 ("" — aucune bordure) ne doit RIEN peindre : pas d'ornement gratuit sur un joueur
	# qui n'a rien accompli. Et une clé INCONNUE se comporte pareil (défensif, jamais un crash).
	assert(await _painted_pixels("") == 0)
	assert(await _painted_pixels("mithril") == 0)
	# Les tranches sont VISUELLEMENT distinctes : le nombre de crans diffère (lisible aussi par un
	# daltonien — elles ne se distinguent pas QUE par la teinte).
	var ticks := []
	for tier in TIERS:
		ticks.append(int(MasteryBorder.TIERS[tier]["ticks"]))
	assert(ticks.size() == 6 and ticks == [2, 3, 4, 5, 6, 8])
	# ... et elles ne peignent pas toutes la MÊME chose : plus de crans = plus d'encre.
	assert(int(painted["prismatic"]) > int(painted["steel"]))
	_ok("6 tranches peignent (pixels comptes), rang 0 et cle inconnue non, crans distincts", 11)

	# --- 2. `reduced_motion` FIGE l'irisation, sans retirer la bordure ---------------------------
	SettingsManager.set_comfort("reduced_motion", true)
	var frozen: Control = MasteryBorder.make("prismatic", 96.0)
	host.add_child(frozen)
	await get_tree().process_frame
	assert(not frozen.is_processing())          # plus aucune animation
	var c1: Color = frozen._main_color()
	await get_tree().create_timer(0.25).timeout
	assert(frozen._main_color() == c1)          # la teinte NE BOUGE PAS
	assert(await _painted_pixels("prismatic") > 0)  # ... mais la bordure est toujours LÀ
	frozen.queue_free()

	SettingsManager.set_comfort("reduced_motion", false)
	var moving: Control = MasteryBorder.make("prismatic", 96.0)
	host.add_child(moving)
	await get_tree().process_frame
	assert(moving.is_processing())              # contre-épreuve : sans le réglage, ça bouge
	var m1: Color = moving._main_color()
	await get_tree().create_timer(0.9).timeout
	assert(moving._main_color() != m1)
	moving.queue_free()
	# Les tranches NON prismatiques ne s'animent JAMAIS (elles n'ont aucune raison de consommer une
	# frame de traitement par écran).
	for tier in ["steel", "bronze", "silver", "gold", "platinum"]:
		var s: Control = MasteryBorder.make(tier, 40.0)
		host.add_child(s)
		await get_tree().process_frame
		assert(not s.is_processing())
		s.queue_free()
	_ok("reduced_motion fige l'irisation sans retirer la bordure ; seules 6 animent", 10)

	# --- 3. LIBELLÉS DE TITRE -------------------------------------------------------------------
	assert(MasteryBorder.title_i18n_key("veteran") == "TITLE_VETERAN")
	assert(MasteryBorder.title_i18n_key("") == "")
	assert(MasteryBorder.title_label("veteran") != "TITLE_VETERAN")   # la clé est TRADUITE
	assert(MasteryBorder.title_label("") == "")
	# Le catalogue de factions se charge tout seul pour les vues qui n'en ont pas (Post-Op).
	var cat := MasteryBorder.faction_catalogue()
	assert(cat.size() == 10)
	var fid := str(cat.keys()[0])
	var full := MasteryBorder.title_with_faction("%s:veteran" % fid)
	assert(full.contains(str(cat[fid]).to_upper()))       # le NOM DE FACTION y figure
	assert(full != MasteryBorder.title_label("veteran"))  # ... et distingue du titre seul
	# Une source inconnue rend le TITRE SEUL, jamais la chaîne vide (on n'efface pas une récompense).
	assert(MasteryBorder.title_with_faction("event_s3:veteran") == MasteryBorder.title_label("veteran"))
	assert(MasteryBorder.title_with_faction("") == "")
	assert(MasteryBorder.title_with_faction("sans_separateur") == "")
	_ok("libelles de titre : cle i18n, traduction, faction jointe, replis", 10)

	# --- 4. FICHE PERSONNAGE : rang 0 verrouillé / rang 7 / rang 52 -------------------------------
	var chars = load("res://scenes/ui/characters_screen.tscn").instantiate()
	add_child(chars)
	await get_tree().process_frame
	var page := VBoxContainer.new()
	chars.add_child(page)

	# 4a. VERROUILLÉE (héros sous le niveau 50) : le libellé annonce l'échéance, pas un rang.
	chars._build_mastery_block(page, _hero(0, false))
	await get_tree().process_frame
	assert(_finds(page, tr("MASTERY_LOCKED")))
	assert(not _finds(page, tr("MASTERY_RANK_PLAIN") % 0))
	_clear(page)

	# 4b. RANG 0 mais DÉVERROUILLÉE : l'état que « rang > 0 ? » aurait confondu avec le précédent.
	chars._build_mastery_block(page, _hero(0, true))
	await get_tree().process_frame
	assert(_finds(page, tr("MASTERY_RANK_PLAIN") % 0))
	assert(not _finds(page, tr("MASTERY_LOCKED")))
	_clear(page)

	# 4c. RANG 7 : titre ÉLITE, bordure bronze, prochain titre annoncé.
	chars._build_mastery_block(page, _hero(7, true, "elite", "bronze",
			{"rank": 10, "title_key": "master"}))
	await get_tree().process_frame
	assert(_finds(page, MasteryBorder.title_label("elite")))
	assert(_finds(page, tr("MASTERY_NEXT_TITLE") % [MasteryBorder.title_label("master"), 10]))
	_clear(page)

	# 4d. RANG 52 : au-delà du dernier palier — les rangs continuent, les titres non.
	chars._build_mastery_block(page, _hero(52, true, "immortal", "prismatic", null))
	await get_tree().process_frame
	assert(_finds(page, MasteryBorder.title_label("immortal")))
	assert(_finds(page, tr("MASTERY_NEXT_TITLE_NONE")))
	_clear(page)

	# 4e. PERSONNAGE VERROUILLÉ : aucune maîtrise fantôme sur un héros injouable.
	var locked := _hero(12, true, "master", "silver")
	locked["access"] = {"type": "locked", "free_games_left": 0, "free_games_max": 5, "price": 900}
	chars._build_mastery_block(page, locked)
	await get_tree().process_frame
	assert(page.get_child_count() == 0)
	_clear(page)

	# 4f. SERVEUR NON REDÉPLOYÉ (bloc absent) : rien plutôt qu'un bloc inventé.
	var legacy := _hero(0, false)
	legacy.erase("mastery")
	chars._build_mastery_block(page, legacy)
	await get_tree().process_frame
	assert(page.get_child_count() == 0)
	chars.queue_free()
	_ok("fiche EVOLUTION : verrouillee, rang 0, rang 7, rang 52, verrouillee, serveur ancien", 10)

	# --- 5. SÉLECTEUR DE TITRE : optimiste + ROLLBACK par SABOTAGE -------------------------------
	var prof = load("res://scenes/ui/profile.tscn").instantiate()
	add_child(prof)
	await get_tree().process_frame
	var fid2 := str(MasteryBorder.faction_catalogue().keys()[0])
	prof._masteries = [{"faction_id": fid2, "rank": 12, "title_key": "master",
		"border_tier": "silver", "unlocked_titles": ["veteran", "elite", "master"]}]
	prof._equipped_title = "%s:veteran" % fid2
	prof._populate_overview_tab()
	await get_tree().process_frame
	assert(_finds(prof, MasteryBorder.title_label("veteran")))

	# 5a. Choix optimiste : l'écran montre le nouveau titre AVANT la réponse serveur.
	var wanted := "%s:master" % fid2
	prof._request_title(wanted)
	await get_tree().process_frame
	assert(prof._equipped_title == wanted)
	assert(_finds(prof, MasteryBorder.title_label("master")))

	# 5b. ⚠️ SABOTAGE — le serveur REFUSE (droit perdu entre l'ouverture et le clic). L'affichage
	#     DOIT revenir à l'état de vérité renvoyé par le serveur. Sans rollback, le joueur croirait
	#     porter MAÎTRE alors qu'il porte encore VÉTÉRAN.
	prof._on_title_equipped({"ok": false, "equipped_title": "%s:veteran" % fid2,
		"reason": "not_unlocked"})
	await get_tree().process_frame
	assert(prof._equipped_title == "%s:veteran" % fid2)
	assert(_finds(prof, MasteryBorder.title_label("veteran")))
	assert(not _finds(prof, MasteryBorder.title_label("master")))

	# 5c. ÉCHEC DE TRANSPORT : retour à l'état d'AVANT le clic (et non à une valeur serveur, qu'on
	#     n'a pas reçue). Deux chemins distincts, deux issues distinctes — d'où les deux signaux.
	prof._request_title(wanted)
	await get_tree().process_frame
	assert(prof._equipped_title == wanted)
	prof._on_title_equip_failed("KO")
	await get_tree().process_frame
	assert(prof._equipped_title == "%s:veteran" % fid2)

	# 5d. SUCCÈS : la valeur serveur est adoptée telle quelle.
	prof._request_title(wanted)
	prof._on_title_equipped({"ok": true, "equipped_title": wanted, "reason": ""})
	await get_tree().process_frame
	assert(prof._equipped_title == wanted)

	# 5e. RETRAIT du titre (« AUCUN TITRE » — un choix, pas un vide).
	prof._request_title("")
	prof._on_title_equipped({"ok": true, "equipped_title": "", "reason": ""})
	await get_tree().process_frame
	assert(prof._equipped_title == "")
	assert(_finds(prof, tr("TITLE_NONE")))
	_ok("selecteur : optimiste, ROLLBACK par sabotage, echec transport, succes, retrait", 12)

	# 5f. PURGE SIMULÉE : le serveur ne renvoie plus ni titre ni maîtrise → tout retombe, et le
	#     bouton lui-même disparaît (il n'y a plus rien à choisir).
	prof._on_profile_loaded({"username": "T", "equipped_title": "", "masteries_summary": []})
	await get_tree().process_frame
	assert(prof._equipped_title == "")
	assert(prof._masteries.is_empty())
	assert(prof._build_title_row() == null)
	# Contre-épreuve : avec une maîtrise, la ligne EXISTE — le test précédent mesure bien quelque chose.
	prof._on_profile_loaded({"username": "T", "equipped_title": "%s:veteran" % fid2,
		"masteries_summary": [{"faction_id": fid2, "rank": 3, "title_key": "veteran",
			"border_tier": "steel", "unlocked_titles": ["veteran"]}]})
	await get_tree().process_frame
	assert(prof._build_title_row() != null)
	prof.queue_free()
	_ok("purge simulee : titre retombe, palmares vide, bouton masque (contre-epreuve incluse)", 4)

	# --- 6. POST-OP : rank-up sans jamais bloquer REJOUER ----------------------------------------
	var rep = load("res://scenes/game/operation_report.tscn").instantiate()
	add_child(rep)
	await get_tree().process_frame
	var replay := _find_replay(rep)
	assert(replay != null and not replay.disabled)

	# 6a. Aucun franchissement → AUCUNE ligne, AUCUNE séquence.
	rep._arm_mastery_celebration({})
	await get_tree().process_frame
	assert(not rep._mastery_cine_armed)

	# 6b. Rang gagné SANS nouveau titre → pas de célébration (elle s'userait à chaque partie).
	rep._arm_mastery_celebration({"from": 12, "to": 13, "title_key": null})
	await get_tree().process_frame
	assert(not rep._mastery_cine_armed)

	# 6c. NOUVEAU TITRE → séquence jouée, et REJOUER TOUJOURS cliquable (règle §8.129).
	rep._arm_mastery_celebration({"from": 4, "to": 5, "title_key": "elite"})
	await get_tree().process_frame
	await get_tree().process_frame
	assert(rep._mastery_cine_armed)
	assert(replay != null and not replay.disabled)
	# Rejouée une seconde fois (victoire PUIS game_over) : UNE seule surcouche, pas deux.
	var overlays := _count_overlays(rep)
	rep._arm_mastery_celebration({"from": 5, "to": 6, "title_key": "legend"})
	await get_tree().process_frame
	assert(_count_overlays(rep) == overlays)
	assert(not replay.disabled)
	rep.queue_free()
	_ok("Post-Op : celebration seulement sur NOUVEAU titre, une seule fois, REJOUER jamais bloque", 8)

	# Deux frames pour que les `queue_free()` des scènes instanciées soient réellement traités : un
	# `quit()` immédiat laisserait des ressources vivantes et polluerait le journal d'erreurs de
	# fermeture, qu'on veut pouvoir lire comme un verdict.
	if _probe_vp != null:
		_probe_vp.free()
		_probe_vp = null
	host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[OK] TEST MASTERY UI : %d asserts verts" % checks)
	get_tree().quit(0)


# --- Fabrique d'entrée de roster (forme EXACTE du payload `/heroes`) ------------------------------
func _hero(rank: int, unlocked: bool, title_key = null, border := "",
		next_title = {"rank": 1, "title_key": "veteran"}) -> Dictionary:
	return {
		"faction_id": "phalanges_acier", "level": 50 if unlocked else 31,
		"xp_total": 1000, "xp_in_level": 120, "xp_for_level": 400,
		"access": {"type": "free", "free_games_left": 5, "free_games_max": 5, "price": 0},
		"record": {"games": 41, "wins": 12, "losses": 29, "winrate": 29},
		"mastery": {
			"rank": rank, "title_key": title_key, "border_tier": border,
			"unlocked": unlocked, "unlocked_titles": [],
			"xp_into_rank": 1200, "xp_per_rank": 5000, "next_title": next_title,
		},
	}


func _clear(page: Node) -> void:
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()


func _finds(root: Node, needle: String) -> bool:
	if needle == "":
		return false
	if root is Label and str((root as Label).text).findn(needle) != -1:
		return true
	if root is Button and str((root as Button).text).findn(needle) != -1:
		return true
	for c in root.get_children():
		if _finds(c, needle):
			return true
	return false


# Le bouton « REJOUER » (§8.70) — repéré par sa RÉFÉRENCE interne (`_requeue_btn`), pas par son
# libellé : celui-ci bascule en « RETOUR AU QG » après une partie privée, et un test qui le
# chercherait par le texte deviendrait silencieusement aveugle dans ce cas.
func _find_replay(rep: Node) -> Button:
	var btn = rep.get("_requeue_btn")
	if btn is Button:
		return btn
	return rep.find_child("RequeueButton", true, false) as Button


func _count_overlays(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c.get_script() != null and str(c.get_script().resource_path).ends_with("unlock_celebration.gd"):
			n += 1
	return n
