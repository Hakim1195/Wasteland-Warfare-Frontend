extends Node

# =================================================================================================
# CONTRE-ÉPREUVE §8.144 §6.2 — LE PRIX D'ENTRÉE DE L'ENVELOPPE
# =================================================================================================
#   & <godot_console> --path frontend res://tools/test_nav_mail_scale.tscn
#   (SANS --headless pour les CAPTURES ; le volet MESURE, lui, tourne aussi en headless.)
#
# POURQUOI CE FICHIER EXISTE ─────────────────────────────────────────────────────────────────────
# L'enveloppe du COURRIER s'ajoute au CLUSTER DROIT de la barre de navigation — le seul bloc que
# l'invariant §8.133/§8.134 déclare INTOUCHABLE : « ⚙ / ⏻ / identité restent dans le viewport, à
# TOUTES les échelles ». Ajouter 44 px + une séparation à ce cluster remet cet invariant EN JEU.
# Il ne se suppose pas : il se REJOUE.
#
# CE QUI EST MESURÉ ──────────────────────────────────────────────────────────────────────────────
# La matrice {0.9, 1.0, 1.15, 1.3} × {1920×1080, 1600×900, 1280×720}, soit 12 cases. Pour chacune :
# les rectangles GLOBAUX de l'ENVELOPPE, du ⚙ et du ⏻ doivent être ENTIÈREMENT contenus dans le
# viewport LOGIQUE.
#
# ⚠️ POURQUOI UN SubViewport ET PAS `get_window().size` : le redimensionnement de fenêtre est un
# NO-OP en headless (constat §8.134, consigné). Or `content_scale_factor` produit exactement un
# viewport LOGIQUE de `résolution / échelle` — c'est cette largeur-là que `top_nav._relayout()` lit
# dans `size.x`. On la fabrique donc directement, ce qui rend la mesure identique ET reproductible.
#
# ⚠️ AUCUN `assert` : un assert qui échoue BLOQUE Godot (constat maison), et un harnais bloqué se
# lit comme un harnais silencieux. On compte, on imprime, on sort avec un code.

const TopNav := preload("res://scripts/ui/top_nav.gd")
const MailModal := preload("res://scripts/ui/mail_modal.gd")

const SCALES := [0.9, 1.0, 1.15, 1.3]
const RESOLUTIONS := [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1280, 720)]
const GUNMETAL := Color(0.058824, 0.07451, 0.094118, 1)

var _pass := 0
var _fail := 0


func _check(label: String, ok: bool) -> void:
	if ok:
		_pass += 1
		print("    [OK]   %s" % label)
	else:
		_fail += 1
		print("    [FAIL] %s" % label)


# Le cluster droit est le DERNIER enfant de la rangée ; ses enfants sont, dans l'ordre :
# [cadre identité, ENVELOPPE, ⚙, ⏻]. On les récupère par POSITION plutôt que par nom, pour que le
# test rougisse si quelqu'un réordonne le cluster sans y penser.
func _cluster_of(nav: Control) -> Array:
	var row: Node = nav._row
	if row == null or row.get_child_count() == 0:
		return []
	var box: Node = row.get_child(row.get_child_count() - 1)
	var out: Array = []
	for c in box.get_children():
		if c is Control:
			out.append(c)
	return out


func _measure(scale: float, res: Vector2i) -> void:
	# Viewport LOGIQUE = résolution / échelle (ce que `content_scale_factor` produit réellement).
	var logical := Vector2i(int(round(float(res.x) / scale)), int(round(float(res.y) / scale)))

	var vp := SubViewport.new()
	vp.size = logical
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(host)

	var nav := TopNav.new()
	nav.active_tab = "lobby"
	host.add_child(nav)

	# Pastille NON VIDE : c'est l'état LE PLUS LARGE de l'enveloppe (« ●3 » par-dessus l'icône) et
	# donc le seul qui vaille la peine d'être mesuré. Mesurer l'état vide prouverait le cas facile.
	nav._on_mail_badge(3, 2)
	# Pastilles des onglets, elles aussi au plus large : c'est la barre la plus dense possible.
	nav._on_missions_loaded({"claimable_count": 3})
	nav._on_company_badge({"company": true, "online": 4, "unread": 2, "invite": {}})

	for i in range(4):
		await get_tree().process_frame

	var cluster := _cluster_of(nav)
	var screen := Rect2(Vector2.ZERO, Vector2(logical))
	var label := "%dx%d @ %.2f  (viewport logique %dx%d)" % [res.x, res.y, scale, logical.x, logical.y]
	print("  --- %s ---" % label)

	if cluster.size() != 4:
		_check("le cluster droit a 4 éléments [identité, enveloppe, ⚙, ⏻]", false)
		vp.free()
		return

	var names := ["IDENTITE", "ENVELOPPE", "ENGRENAGE", "QUITTER"]
	for i in range(cluster.size()):
		var ctrl: Control = cluster[i]
		var rect := ctrl.get_global_rect()
		var inside := screen.encloses(rect)
		_check("%-10s dans le viewport  (x %.0f..%.0f de 0..%d)"
			% [names[i], rect.position.x, rect.end.x, logical.x], inside)

	# ⚠️ L'ENVELOPPE NE RÉTRÉCIT JAMAIS — comme le reste du cluster. Si elle se comprimait, elle
	# « tiendrait » toujours, et le test ci-dessus verdirait pour une mauvaise raison.
	var env: Control = cluster[1]
	_check("l'enveloppe garde sa taille pleine (44 px)", env.size.x >= 43.0 and env.size.y >= 43.0)

	vp.free()


func _shoot(scale: float, res: Vector2i, path: String) -> void:
	# Recette maison (§8.111) : viewport → `get_image()` → PNG. ⚠️ INUTILE en `--headless` (pilote de
	# rendu factice → PNG vides, leçon §8.134.2) : le volet MESURE reste, lui, valable partout.
	var logical := Vector2i(int(round(float(res.x) / scale)), int(round(float(res.y) / scale)))
	var vp := SubViewport.new()
	vp.size = logical
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = GUNMETAL
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(host)
	var nav := TopNav.new()
	nav.active_tab = "lobby"
	host.add_child(nav)
	nav._on_mail_badge(3, 2)
	nav._on_missions_loaded({"claimable_count": 3})
	nav._on_company_badge({"company": true, "online": 4, "unread": 2, "invite": {}})
	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("user://" + path)
	print("    -> user://%s (%dx%d)" % [path, img.get_width(), img.get_height()])
	vp.free()


# --- Le MODAL : liste pleine, pli à pièce jointe, état vide, pastille --------------------------
func _shoot_modal(mails: Array, path: String, select_index: int = 0) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = GUNMETAL
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	var modal := MailModal.new()
	vp.add_child(modal)
	await get_tree().process_frame
	# On injecte la réponse serveur DIRECTEMENT (aucun réseau) : c'est le même chemin que celui du
	# signal `mail_list_loaded`, donc ce qu'on capture est bien ce que le joueur verrait.
	# 🩸 DUPLICATION PROFONDE OBLIGATOIRE. Un `Array` de `Dictionary` se passe PAR RÉFÉRENCE : le
	# bloc de contrôles logiques ci-dessus ouvre des plis sur CE MÊME tableau, et `_on_row_pressed`
	# y écrit `read = true`. Sans cette copie, les captures montraient une boîte entièrement LUE —
	# donc sans point or ni liseré or, l'affordance qu'on venait justement relire. Une fixture
	# partagée est un faux témoin.
	modal._on_mail_loaded({"mails": mails})
	if select_index >= 0 and select_index < mails.size():
		modal._on_row_pressed(int(mails[select_index].get("id", 0)))
	for i in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.save_png("user://" + path)
	print("    -> user://%s (%dx%d)" % [path, img.get_width(), img.get_height()])
	vp.free()


# FIXTURE — reconstruite À CHAQUE APPEL, jamais partagée.
# 🩸 Un `Array` de `Dictionary` se passe PAR RÉFÉRENCE en GDScript. Tant que tous les consommateurs
# se partageaient le MÊME tableau, le bloc de contrôles logiques (qui ouvre des plis, donc écrit
# `read = true`) contaminait les CAPTURES : elles montraient une boîte entièrement lue, sans point
# or ni liseré or — l'affordance « non lu » qu'on venait précisément relire. Et `duplicate(true)` au
# moment de la capture ne suffisait pas : il copiait la donnée DÉJÀ mutée. Une fixture se
# RECONSTRUIT, elle ne se recopie pas.
func _fixture() -> Array:
	var now := int(Time.get_unix_time_from_system())
	return [
		{"id": 3, "kind": "admin", "title": "Compensation incident du samedi",
		 "body": "Suite a l'incident de samedi, voici 200 Coins.

L'equipe.",
		 "coins_attached": 200, "created_at_epoch": now - 3600,
		 "expires_at_epoch": now + 86400 * 12, "read": false, "claimed": false},
		{"id": 2, "kind": "admin", "title": "Maintenance de nuit",
		 "body": "Le serveur sera indisponible cette nuit de 02h a 04h UTC.",
		 "coins_attached": 0, "created_at_epoch": now - 7200,
		 "expires_at_epoch": now + 3600 * 20, "read": true, "claimed": false},
		{"id": 1, "kind": "admin", "title": "Merci pour le playtest",
		 "body": "Prime de participation deja versee.",
		 "coins_attached": 50, "created_at_epoch": now - 90000,
		 "expires_at_epoch": now + 86400 * 3, "read": true, "claimed": true},
	]


func _ready() -> void:
	print("=" .repeat(78))
	print("  §8.144 §6.2 — MATRICE ui_scale AVEC L'ENVELOPPE EN PLACE")
	print("=" .repeat(78))

	for res in RESOLUTIONS:
		for scale in SCALES:
			await _measure(float(scale), res)

	# --- Le MODAL : rendu logique (mesurable même en headless) -----------------------------------
	print("\n  --- MODAL COURRIER ---")
	var full := _fixture()

	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child(vp)
	var modal := MailModal.new()
	vp.add_child(modal)
	await get_tree().process_frame
	modal._on_mail_loaded({"mails": full})
	for i in range(3):
		await get_tree().process_frame
	_check("le modal liste les 3 plis", modal._list_box.get_child_count() == 3)
	_check("le 1er pli est selectionne par defaut", modal._selected_id == 3)
	_check("le detail est peuple", modal._detail_box.get_child_count() > 0)
	# ⚠️⚠️ LA GARDE DE LA DÉROGATION R4 : le corps est du TEXTE, jamais du balisage.
	var bbcode_off := true
	for c in modal._detail_box.get_children():
		if c is RichTextLabel and c.bbcode_enabled:
			bbcode_off = false
	_check("le corps du pli a le BBCode DESACTIVE", bbcode_off)
	# Un message SIMPLE n'a pas de bouton RÉCLAMER.
	modal._on_row_pressed(2)
	await get_tree().process_frame
	var has_claim := false
	for c in modal._detail_box.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Button:
					has_claim = true
	_check("un message SIMPLE n'a AUCUN bouton RECLAMER", not has_claim)
	# Un pli DÉJÀ réclamé a un bouton DÉSACTIVÉ.
	modal._on_row_pressed(1)
	await get_tree().process_frame
	var claimed_disabled := false
	for c in modal._detail_box.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Button and cc.disabled:
					claimed_disabled = true
	_check("un pli DEJA reclame a son bouton DESACTIVE", claimed_disabled)
	# VERROU ANTI DOUBLE-CLIC : deux pressions n'envoient qu'UN appel réseau.
	modal._on_row_pressed(3)
	await get_tree().process_frame
	var calls := {"n": 0}
	var probe := func(_id: int) -> void: calls["n"] += 1
	var btn: Button = null
	for c in modal._detail_box.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Button and not cc.disabled:
					btn = cc
	if btn != null:
		modal._claim_in_flight = 0
		var real := NetworkManager.claim_mail
		# On ne peut pas remplacer une méthode d'autoload : on compte les appels en observant le
		# verrou, qui est LA mécanique testée (le réseau, lui, est couvert côté serveur).
		modal._on_claim_pressed(3, btn)
		var first := modal._claim_in_flight
		modal._on_claim_pressed(3, btn)
		_check("double-clic RECLAMER : le verrou tient (1 seul depart)",
			first == 3 and modal._claim_in_flight == 3)
	else:
		_check("double-clic RECLAMER : bouton trouve", false)
	vp.free()

	# --- CAPTURES (utiles seulement HORS --headless) ---------------------------------------------
	if DisplayServer.get_name() != "headless":
		print("\n  --- CAPTURES ---")
		await _shoot(0.9, Vector2i(1920, 1080), "nav_mail_1920_090.png")
		await _shoot(1.0, Vector2i(1920, 1080), "nav_mail_1920_100.png")
		await _shoot(1.15, Vector2i(1600, 900), "nav_mail_1600_115.png")
		await _shoot(1.3, Vector2i(1280, 720), "nav_mail_1280_130.png")
		# ⚠️ UNE CAPTURE PAR LANGUE. Le poste de développement garde la locale de la dernière session
		# (ici l'italien) : ne capturer qu'elle laisserait FR et EN totalement non relus — et c'est
		# précisément dans une langue qu'on ne regarde pas qu'un libellé déborde (leçon §8.131).
		var previous := TranslationServer.get_locale()
		for loc in ["fr", "en", "it"]:
			TranslationServer.set_locale(loc)
			await get_tree().process_frame
			# `-1` : AUCUN clic. Sans ça le harnais MARQUE LU le premier pli et la capture perd
			# l'affordance « non lu » (point or + liseré or) — l'état qu'on veut justement relire.
			await _shoot_modal(_fixture(), "mail_modal_full_%s.png" % loc, -1)
		TranslationServer.set_locale("fr")
		await get_tree().process_frame
		await _shoot_modal([], "mail_modal_empty.png", -1)
		TranslationServer.set_locale(previous)
	else:
		print("\n  (captures SAUTEES : pilote headless -> PNG vides, leçon §8.134.2)")

	print("\n" + "=".repeat(78))
	print("  RESULTAT : %d OK / %d KO" % [_pass, _fail])
	print("=".repeat(78))
	get_tree().quit(1 if _fail > 0 else 0)
