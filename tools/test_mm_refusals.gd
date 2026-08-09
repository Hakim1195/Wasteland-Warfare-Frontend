extends Node

# =================================================================================================
# CONTRE-ÉPREUVE §8.144 §7.4 — « PLUS JAMAIS UN CLIC MUET »
# =================================================================================================
#   & <godot_console> --headless --path frontend res://tools/test_mm_refusals.tscn
#
# CE QU'ELLE PROUVE ──────────────────────────────────────────────────────────────────────────────
# Les quatre chemins de refus cartographiés au §8.143 §5.8 — mise en file, CRÉATION de salon privé,
# JOINTURE de salon privé, file d'ÉQUIPE — produisent désormais un message VISIBLE pour :
#   • chaque raison CONNUE du contrat (`banned`, `in_room`, `closed`, `unavailable`, `busy`…) ;
#   • une raison INCONNUE (serveur plus récent que ce build) ;
#   • une réponse VIDE (HTTP non-200 → `data` = {}).
#
# 🩸 C'ÉTAIT LA DETTE EXACTE DU §8.143 : « créer » et « rejoindre » un salon privé ne faisaient
# **RIEN DU TOUT** face à une raison inconnue. Le joueur cliquait, l'écran ne bougeait pas, et le
# bouton passait pour mort. Un message générique vaut infiniment mieux qu'un bouton inerte.
#
# ⚠️ AUCUN `assert` (un assert qui échoue BLOQUE Godot) : on compte, on imprime, on sort avec un code.
# ⚠️ AUCUN RÉSEAU : on appelle les handlers de signal DIRECTEMENT, avec les payloads du contrat.

const SearchScreen := preload("res://scripts/ui/search_screen.gd")
const SquadScreen := preload("res://scripts/ui/squad_screen.gd")

# Toutes les raisons du contrat pour ces chemins, PLUS deux cas qui n'y figurent pas et qui sont
# précisément ceux qui rendaient l'écran muet.
const QUEUE_REASONS := ["banned", "in_room", "closed", "unavailable", "busy",
						"raison_du_futur", ""]
const JOIN_REASONS := ["unavailable", "banned", "busy", "closed", "raison_du_futur", ""]
const SQUAD_REASONS := ["unavailable", "banned", "busy", "full", "not_leader",
						"playlist_closed", "assigned", "closed", "raison_du_futur"]

var _pass := 0
var _fail := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("    [OK]   %s" % label)
	else:
		_fail += 1
		print("    [FAIL] %s" % label)


func _mount(script: Script) -> Control:
	var node: Control = script.new()
	add_child(node)
	return node


# Le message affiché, quel que soit le panneau qui le porte.
func _visible_text(label: Label) -> String:
	if label == null or not is_instance_valid(label):
		return ""
	if not label.visible:
		return ""
	return str(label.text).strip_edges()


func _test_search() -> void:
	print("\n  --- ÉCRAN RECHERCHE (search_screen.gd) ---")
	var screen := _mount(SearchScreen)
	await get_tree().process_frame

	# 1. MISE EN FILE
	for reason in QUEUE_REASONS:
		screen._set_config_status("", Color.WHITE)     # on repart d'un écran MUET
		var payload := {"queued": false, "reason": reason}
		if reason == "closed":
			payload["cause"] = "maintenance"
		if reason == "in_room":
			payload["room_id"] = 42
		screen._on_mm_queue_result(true, payload)
		await get_tree().process_frame
		# `banned` et `in_room` ont leurs propres écrans (bandeau de sanction / reprise de partie) :
		# ils ne passent pas par le label d'état, et c'est LEUR façon de ne pas être muets.
		var handled: bool = _visible_text(screen._config_status_label) != "" \
			or reason in ["banned", "in_room"]
		_check("file : raison %-16s -> retour VISIBLE" % ("« %s »" % reason), handled)

	# 2. CRÉATION DE SALON PRIVÉ — LA dette du §8.143
	for reason in QUEUE_REASONS:
		screen._set_config_status("", Color.WHITE)
		var payload := {"created": false, "reason": reason}
		if reason == "closed":
			payload["cause"] = "feature_disabled"
		if reason == "in_room":
			payload["room_id"] = 42
		screen._on_private_created(true, payload)
		await get_tree().process_frame
		var handled: bool = _visible_text(screen._config_status_label) != "" \
			or reason in ["banned", "in_room"]
		_check("creation salon : raison %-16s -> retour VISIBLE" % ("« %s »" % reason), handled)

	# Réponse ENTIÈREMENT VIDE (HTTP non-200) : le cas le plus muet de tous.
	screen._set_config_status("", Color.WHITE)
	screen._on_private_created(false, {})
	await get_tree().process_frame
	_check("creation salon : reponse VIDE -> retour VISIBLE",
		_visible_text(screen._config_status_label) != "")

	# 3. JOINTURE DE SALON PRIVÉ — l'autre dette (un `match` sans branche par défaut)
	for reason in JOIN_REASONS:
		screen._set_config_status("", Color.WHITE)
		var payload := {"joined": false, "reason": reason}
		if reason == "closed":
			payload["cause"] = "maintenance"
		screen._on_private_join_result(true, payload)
		await get_tree().process_frame
		var handled: bool = _visible_text(screen._config_status_label) != "" or reason == "banned"
		_check("jointure salon : raison %-16s -> retour VISIBLE" % ("« %s »" % reason), handled)

	screen._set_config_status("", Color.WHITE)
	screen._on_private_join_result(false, {})
	await get_tree().process_frame
	_check("jointure salon : reponse VIDE -> retour VISIBLE",
		_visible_text(screen._config_status_label) != "")

	# 4. LE TEXTE EST LE BON — une fermeture ne se raconte pas comme une panne.
	screen._set_config_status("", Color.WHITE)
	screen._on_mm_queue_result(true, {"queued": false, "reason": "closed", "cause": "maintenance"})
	await get_tree().process_frame
	var maint := _visible_text(screen._config_status_label)
	_check("MAINTENANCE : le texte dedie s'affiche  [%s]" % maint,
		maint == tr("MM_CLOSED_MAINTENANCE"))
	_check("MAINTENANCE : en OR (info de service), pas en ROUGE",
		screen._config_status_label.get_theme_color("font_color").is_equal_approx(screen.GOLD))

	screen._set_config_status("", Color.WHITE)
	screen._on_mm_queue_result(true,
		{"queued": false, "reason": "closed", "cause": "feature_disabled"})
	await get_tree().process_frame
	_check("FONCTIONNALITE FERMEE : le texte dedie s'affiche",
		_visible_text(screen._config_status_label) == tr("MM_CLOSED_FEATURE"))

	# Une `cause` INCONNUE ne doit pas rendre l'écran muet non plus.
	screen._set_config_status("", Color.WHITE)
	screen._on_mm_queue_result(true, {"queued": false, "reason": "closed", "cause": "du_futur"})
	await get_tree().process_frame
	_check("cause INCONNUE -> repli sur « ferme », jamais rien",
		_visible_text(screen._config_status_label) != "")

	screen.queue_free()


func _test_squad() -> void:
	print("\n  --- FILE D'EQUIPE (squad_screen.gd) ---")
	var screen := _mount(SquadScreen)
	await get_tree().process_frame

	for reason in SQUAD_REASONS:
		screen._status_label.text = ""
		screen._status_label.visible = false
		var payload := {"squad": true, "reason": reason, "in_queue": false,
						"members": [], "code": "ABCD"}
		if reason == "closed":
			payload["cause"] = "maintenance"
		screen._on_squad_state(true, payload)
		await get_tree().process_frame
		_check("escouade : raison %-18s -> retour VISIBLE" % ("« %s »" % reason),
			_visible_text(screen._status_label) != "")

	# Le texte de MAINTENANCE, et sa couleur.
	screen._status_label.text = ""
	screen._on_squad_state(true, {"squad": true, "reason": "closed", "cause": "maintenance",
								  "in_queue": false, "members": [], "code": "ABCD"})
	await get_tree().process_frame
	_check("escouade MAINTENANCE : texte dedie",
		_visible_text(screen._status_label) == tr("MM_CLOSED_MAINTENANCE"))
	_check("escouade MAINTENANCE : en OR",
		screen._status_label.get_theme_color("font_color").is_equal_approx(screen.GOLD))

	screen._status_label.text = ""
	screen._on_squad_state(true, {"squad": true, "reason": "closed", "cause": "feature_disabled",
								  "in_queue": false, "members": [], "code": "ABCD"})
	await get_tree().process_frame
	_check("escouade FONCTIONNALITE FERMEE : texte dedie",
		_visible_text(screen._status_label) == tr("MM_CLOSED_FEATURE"))

	screen.queue_free()


func _test_keys_exist() -> void:
	print("\n  --- CLES i18n (les trois langues) ---")
	var previous := TranslationServer.get_locale()
	for loc in ["fr", "en", "it"]:
		TranslationServer.set_locale(loc)
		for key in ["MM_CLOSED_MAINTENANCE", "MM_CLOSED_FEATURE", "MM_UNKNOWN_REFUSAL",
					"MAIL_TITLE", "MAIL_EMPTY", "MAIL_CLAIM_CTA", "MAIL_CLAIMED",
					"MAIL_EXPIRES_IN", "MAIL_EXPIRED", "MAIL_ATTACHMENT", "MAIL_CLAIM_FAILED",
					"PROFILE_FIN_SRC_MAIL_REWARD", "PROFILE_FIN_SRC_ADMIN_ADJUST"]:
			var value := tr(key)
			# ⚠️ Une clé MANQUANTE est rendue par Godot… comme la clé elle-même. C'est le faux vert
			# classique de l'i18n : le texte s'affiche, il est juste incompréhensible.
			_check("[%s] %-28s traduite" % [loc, key], value != key and value.strip_edges() != "")
	TranslationServer.set_locale(previous)


# CAPTURE de l'écran MAINTENANCE (§7.4 du brief). ⚠️ Inutile en `--headless` : pilote de rendu
# factice → PNG vide (leçon §8.134.2). C'est la seule preuve visuelle que le message de service
# s'affiche en OR et non en rouge d'erreur — une différence qu'aucun assert ne rend lisible.
func _shoot_maintenance() -> void:
	if DisplayServer.get_name() == "headless":
		print("\n  (capture MAINTENANCE sautee : pilote headless)")
		return
	print("\n  --- CAPTURE MAINTENANCE ---")
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.058824, 0.07451, 0.094118, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	var screen: Control = SearchScreen.new()
	vp.add_child(screen)
	await get_tree().process_frame
	screen._on_mm_queue_result(true, {"queued": false, "reason": "closed",
									  "cause": "maintenance"})
	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("user://mm_maintenance.png")
	print("    -> user://mm_maintenance.png (%dx%d)" % [img.get_width(), img.get_height()])
	vp.free()


func _ready() -> void:
	print("=".repeat(78))
	print("  §8.144 §7.4 — RELIQUATS §8.143 : PLUS JAMAIS UN CLIC MUET")
	print("=".repeat(78))
	await _test_search()
	await _test_squad()
	_test_keys_exist()
	await _shoot_maintenance()
	print("\n" + "=".repeat(78))
	print("  RESULTAT : %d OK / %d KO" % [_pass, _fail])
	print("=".repeat(78))
	get_tree().quit(1 if _fail > 0 else 0)
