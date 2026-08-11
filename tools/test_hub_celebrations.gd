extends Node

# TEST §8.122 LOT F (style maison) — célébrations du hub.
#   & <godot_console> --headless --path frontend res://tools/test_hub_celebrations.tscn
#
# Couvre ce qu'un boot d'écran ne prouve pas :
#   • persistance LOCALE `user://seen_items.json` (chip NOUVEAU) + section [progress] ;
#   • règle de PROMOTION : division changée ET points en HAUSSE — jamais la relégation, jamais la
#     remise à zéro de fin de saison, jamais la toute première lecture ;
#   • séquence d'unlock : durée animée ≤ 2,5 s, skip au clic, `reduced_motion` = affichage direct ;
#   • compteur de Coins animé (décompte + valeur finale exacte).

const TopNav := preload("res://scripts/ui/top_nav.gd")
const UnlockScene := preload("res://scenes/ui/unlock_celebration.tscn")
const UnlockScript := preload("res://scripts/ui/unlock_celebration.gd")
const XpCoinsBar := preload("res://scripts/ui/xp_coins_bar.gd")


# Photographie des persistances RÉELLES prise au démarrage, et drapeau d'idempotence de la
# restauration. MEMBRES et non variables locales : c'est ce qui permet à `_exit_tree` de restaurer
# même quand `_ready` ne va PAS jusqu'au bout (§8.149, LOT E).
var _backup := {}
var _restored := false


func _ready() -> void:
	var asserts := 0
	# ⚠️ Ce harnais ÉCRIT dans les vraies persistances de la machine (`user://seen_items.json` et la
	# section [progress] de settings.cfg). On les photographie ici et on les restaure ensuite :
	# sans ça, un `ladder_division` de test resterait en place et supprimerait (ou inventerait) le
	# toast de promotion au prochain lancement du VRAI jeu.
	#
	# ⚠️⚠️ CORRECTIF §8.149 (LOT E) : la restauration ne vivait QU'EN FIN de `_ready`, donc sur le
	# seul chemin heureux. Un `assert` rouge, un `--quit-after` trop court, un Ctrl+C — et la
	# machine gardait une division de test. Le run SUIVANT partait alors d'un état pollué et
	# échouait à son tour : le harnais rendait faux le résultat qu'il servait à mesurer. GDScript
	# n'a pas de `finally` ; `_exit_tree` en tient lieu — il s'exécute à la sortie de l'arbre, y
	# compris quand `_ready` s'est interrompu en chemin. `_restore_all` est idempotente, l'appel de
	# fin de `_ready` et celui de `_exit_tree` ne se marchent donc pas dessus.
	_backup = {
		"seen": _read_seen_file(),
		"division": SettingsManager.get_progress(TopNav.PROGRESS_DIVISION_KEY),
		"points": SettingsManager.get_progress(TopNav.PROGRESS_POINTS_KEY),
	}

	# --- 1) Mémoire « articles vus » (chip NOUVEAU) — 100 % locale, aucun appel réseau ----------
	assert(not SettingsManager.is_item_seen("__test_unseen__"))   # inconnu ⇒ réputé NEUF
	SettingsManager.mark_item_seen("__test_seen__")
	assert(SettingsManager.is_item_seen("__test_seen__"))
	SettingsManager.mark_item_seen("__test_seen__")               # idempotent
	assert(SettingsManager.is_item_seen("__test_seen__"))
	assert(FileAccess.file_exists(SettingsManager.SEEN_ITEMS_PATH))
	asserts += 4
	print("[OK] seen_items.json : défaut NEUF, marquage idempotent, persisté (4 asserts)")

	# --- 2) Mémoires [progress] ----------------------------------------------------------------
	SettingsManager.set_progress("__test_key__", "VALEUR")
	assert(SettingsManager.get_progress("__test_key__") == "VALEUR")
	assert(SettingsManager.get_progress("__inconnu__", "defaut") == "defaut")
	asserts += 2
	print("[OK] mémoires locales [progress] : lecture/écriture typées String (2 asserts)")

	# --- 3) Règle de PROMOTION -----------------------------------------------------------------
	var nav := TopNav.new()
	nav.active_tab = ""
	add_child(nav)
	await get_tree().process_frame

	# Table de vérité : [libellé, division, points, doit_afficher_un_toast]
	# Le 1er cas AMORCE la mémoire (aucune valeur locale) → jamais de toast.
	var cases := [
		["1re lecture (amorçage)", "ARGENT", 700, false],
		["gain de RP, même division", "ARGENT", 900, false],
		["PROMOTION (division ↑, RP ↑)", "OR", 1250, true],
		["relégation (division ↓, RP ↓)", "ARGENT", 1100, false],
		["reset de saison (RP → 0)", "BRONZE", 0, false],
		["PROMOTION après le reset", "ARGENT", 640, true],
	]
	for c in cases:
		_clear_toast(nav)
		nav._maybe_promotion_toast({"division": str(c[1]), "season_points": int(c[2])})
		await get_tree().process_frame
		await get_tree().process_frame
		var shown: bool = _find_toast(nav) != null
		assert(shown == bool(c[3]))
		asserts += 1
		print("    · %-32s → toast=%s (attendu %s)" % [str(c[0]), str(shown), str(c[3])])
	# Division absente du payload (serveur antérieur) : aucun toast, aucune écriture parasite.
	_clear_toast(nav)
	nav._maybe_promotion_toast({})
	await get_tree().process_frame
	assert(_find_toast(nav) == null)
	asserts += 1
	print("[OK] promotion : division ↑ ET RP ↑ seulement ; relégation et reset MUETS (7 asserts)")

	# --- 4) Séquence d'unlock : budget de durée, skip, reduced_motion --------------------------
	# Contrat du chantier : la partie ANIMÉE ne dépasse pas 2,5 s.
	var animated: float = UnlockScript.DIM_TIME + UnlockScript.SILHOUETTE_TIME \
		+ UnlockScript.REVEAL_TIME
	assert(animated <= 2.5)
	asserts += 1

	SettingsManager.set_comfort("reduced_motion", false)
	var cine = UnlockScene.instantiate()
	add_child(cine)
	cine.play({"name": "TEST", "texture": null, "accent": Color.RED})
	assert(not cine._revealed)                      # d'abord une SILHOUETTE, pas l'article
	assert(cine._art.modulate.r < 0.01)             # modulate noir = silhouette
	# Clic n'importe où = SKIP → état final immédiat.
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	cine._gui_input(ev)
	assert(cine._revealed)
	asserts += 3
	var closed := [false]
	cine.finished.connect(func() -> void: closed[0] = true)
	cine._gui_input(ev)                             # 2ᵉ clic (déjà révélé) = fermeture
	assert(closed[0])
	asserts += 1

	# reduced_motion : AFFICHAGE DIRECT — révélé dès `play`, sans attendre la moindre frame.
	SettingsManager.set_comfort("reduced_motion", true)
	var cine2 = UnlockScene.instantiate()
	add_child(cine2)
	cine2.play({"name": "TEST", "texture": null, "accent": Color.RED})
	assert(cine2._revealed)
	assert(cine2._art.modulate.is_equal_approx(Color.WHITE))
	assert(cine2._burst == null)                    # aucune particule en mouvement réduit
	SettingsManager.set_comfort("reduced_motion", false)
	cine2.queue_free()
	asserts += 3
	print("[OK] unlock : %.2f s animés (≤ 2,5), skip au clic, reduced_motion direct (7 asserts)"
		% animated)

	# --- 5) Compteur de Coins animé ------------------------------------------------------------
	var bar = XpCoinsBar.new()
	add_child(bar)
	await get_tree().process_frame
	bar.set_coins(5000)
	assert(bar._coins == 5000)
	# Décompte : la valeur doit AVOIR BOUGÉ en cours de route, et atterrir EXACTEMENT sur la cible.
	bar.animate_coins_to(1200, 0.25)
	await get_tree().create_timer(0.12).timeout
	var midway: int = bar._coins
	assert(midway < 5000 and midway > 1200)
	await get_tree().create_timer(0.30).timeout
	assert(bar._coins == 1200)
	asserts += 3
	print("[OK] compteur de Coins : décompte visible, atterrissage exact (3 asserts)")

	# --- Restauration des persistances RÉELLES (cf. `_backup` en tête) -------------------------
	_restore_all()

	print("[OK] TEST HUB CELEBRATIONS (§8.122 LOT F) : %d asserts verts" % asserts)
	get_tree().quit(0)


# Filet de sécurité : appelé par Godot à la sortie de l'arbre, donc AUSSI quand `_ready` s'est
# interrompu (assert rouge, `--quit-after` expiré, fermeture). C'est le « finally » que GDScript
# n'a pas. Le seul cas non couvert reste le kill brutal du processus — borne assumée.
func _exit_tree() -> void:
	_restore_all()


# Remet la machine EXACTEMENT dans l'état photographié au démarrage. IDEMPOTENTE (drapeau
# `_restored`) : un double appel ne réécrit rien. Purge aussi les clés de test, qui restaient
# sinon à vie dans le `settings.cfg` du joueur — elles ne cassaient rien, mais un fichier de
# configuration qui accumule les résidus d'anciens harnais finit par mentir sur ce qu'il contient.
func _restore_all() -> void:
	if _restored or _backup.is_empty():
		return
	_restored = true
	_restore_seen_file(_backup["seen"])
	SettingsManager.set_progress(TopNav.PROGRESS_DIVISION_KEY, str(_backup["division"]))
	SettingsManager.set_progress(TopNav.PROGRESS_POINTS_KEY, str(_backup["points"]))
	SettingsManager.set_progress("__test_key__", "")
	print("[OK] persistances de la machine restaurées (seen_items.json + [progress])")


# Contenu BRUT de seen_items.json avant le test — `null` s'il n'existait pas encore.
func _read_seen_file():
	if not FileAccess.file_exists(SettingsManager.SEEN_ITEMS_PATH):
		return null
	var f := FileAccess.open(SettingsManager.SEEN_ITEMS_PATH, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	return txt

func _restore_seen_file(previous) -> void:
	if previous == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SettingsManager.SEEN_ITEMS_PATH))
		return
	var f := FileAccess.open(SettingsManager.SEEN_ITEMS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(previous))
	f.close()


func _find_toast(nav: Node) -> Node:
	for child in nav.get_children():
		if child.name == "PromotionToast" and is_instance_valid(child):
			return child
	return null

func _clear_toast(nav: Node) -> void:
	var t := _find_toast(nav)
	if t != null:
		nav.remove_child(t)
		t.free()
	nav._promo_toast = null
