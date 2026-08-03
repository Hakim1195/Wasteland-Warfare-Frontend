extends Node

# CONTRE-ÉPREUVE — §8.135 LOT 0 : la jauge de Coins de la nav suit un CLAIM DE MISSION.
#   & <godot_console> --headless --path frontend res://tools/test_claim_coins_gauge.tscn
#
# LE DÉFAUT (dette consignée §8.134, note laissée dans `missions_panel._on_mission_claimed`) :
# après un claim, le solde affiché par la nav restait celui du dernier `/auth/me`. Le joueur voyait
# « +120 ¢ » dans le statut du panneau DÉFIS, et une jauge qui n'avait pas bougé — jusqu'à ce qu'il
# navigue ailleurs. Or `POST /missions/claim` renvoie DÉJÀ `coins_balance` (vérifié dans
# `backend/api/v1/endpoints/missions.py`, l. 159-163) : la donnée était là, personne ne la lisait.
#
# CE QUE LE TEST MESURE (comportement, pas implémentation) :
#   1. la jauge affiche le solde du profil ;
#   2. l'émission de `mission_claimed` la porte au NOUVEAU solde — SANS aucun appel réseau ;
#   3. le mini-profil (qui lit `_profile_data`) annonce le MÊME chiffre — sinon deux valeurs
#      contradictoires coexistent à l'écran ;
#   4. une réponse SANS `coins_balance` (serveur antérieur) ne remet pas la jauge à zéro ;
#   5. SABOTAGE : correctif neutralisé → l'assertion 2 DOIT tomber. Sans cette contre-épreuve, le
#      test resterait vert même si le correctif ne servait à rien (leçon §8.131).
#
# ⚠️ Aucun réseau : on n'appelle jamais `claim_mission()`, on ÉMET le signal que le
# NetworkManager émettrait. Le test vérifie le câblage nav ↔ signal, pas le transport HTTP.

const TopNavScript = preload("res://scripts/ui/top_nav.gd")


func _make_nav() -> Control:
	var nav: Control = TopNavScript.new()
	nav.active_tab = "lobby"
	add_child(nav)
	return nav


# Solde RÉELLEMENT affiché par la jauge (on lit la brique, pas une variable de la nav).
func _gauge_coins(nav: Control) -> int:
	return int(nav._xp_bar._coins)


# Solde que le mini-profil AFFICHERAIT s'il était ouvert (même lecture que `_populate_profile_flyout`).
func _flyout_coins(nav: Control) -> int:
	return int(nav._profile_data.get("coins_balance", nav._profile_data.get("coins", 0)))


func _ready() -> void:
	var checks := 0
	var nav := _make_nav()
	await get_tree().process_frame

	# --- 0. État de départ : la nav a reçu un profil (comme après /auth/me) ----------------------
	# Le float est VOLONTAIRE : `JSON.parse_string` rend des float (piège §5) — si un `int()` manque
	# quelque part sur le chemin, c'est ici que ça se voit.
	nav._on_profile_loaded({
		"username": "TESTEUR", "player_level": 12.0, "current_xp": 300.0,
		"xp_to_next_level": 700.0, "coins_balance": 250.0,
	})
	await get_tree().process_frame
	assert(_gauge_coins(nav) == 250)
	assert(_flyout_coins(nav) == 250)
	checks += 2
	print("[OK] etat initial : jauge et mini-profil a 250 (2 asserts)")

	# --- 1. LE CORRECTIF : le claim porte la jauge au nouveau solde ------------------------------
	# `duration = 0` n'est PAS utilisable ici (l'animation passe par un Tween réel) : on émet, puis
	# on laisse le décompte s'achever avant de mesurer l'atterrissage.
	NetworkManager.mission_claimed.emit({
		"coins_balance": 370.0, "reward_paid": 120.0, "pass_bonus_applied": false,
	})
	await get_tree().create_timer(0.9).timeout
	assert(_gauge_coins(nav) == 370)          # ← l'assertion que le SABOTAGE doit faire tomber
	assert(_flyout_coins(nav) == 370)         # les deux affichages sont d'accord
	checks += 2
	print("[OK] claim : jauge ET mini-profil a 370, sans appel reseau (2 asserts)")

	# --- 2. Le mini-profil OUVERT se repeint sur-le-champ ---------------------------------------
	nav._open_profile_flyout()
	await get_tree().process_frame
	NetworkManager.mission_claimed.emit({
		"coins_balance": 500.0, "reward_paid": 130.0, "pass_bonus_applied": true,
	})
	await get_tree().create_timer(0.9).timeout
	assert(_gauge_coins(nav) == 500)
	assert(_flyout_coins(nav) == 500)
	# Le chiffre est RÉELLEMENT écrit dans le panneau ouvert (et pas seulement dans les données).
	assert(_flyout_shows(nav, "500"))
	nav._close_profile_flyout()
	checks += 3
	print("[OK] mini-profil ouvert : repeint a 500 dans l'arbre (3 asserts)")

	# --- 3. Réponse SANS `coins_balance` : on ne casse rien -------------------------------------
	# Un serveur antérieur (ou un refus mal formé) ne doit pas afficher un solde de 0 : ce serait
	# pire que l'inertie qu'on corrige.
	NetworkManager.mission_claimed.emit({"reward_paid": 40.0})
	await get_tree().create_timer(0.9).timeout
	assert(_gauge_coins(nav) == 500)
	assert(_flyout_coins(nav) == 500)
	checks += 2
	print("[OK] payload sans coins_balance : solde INCHANGE, pas de 0 (2 asserts)")

	# --- 4. SABOTAGE : correctif neutralisé → le défaut d'origine revient -----------------------
	# On coupe le SEUL fil ajouté par le lot (l'abonnement de la nav au signal) et on rejoue le
	# claim : la jauge doit alors rester figée, exactement comme avant §8.135. Si elle bougeait
	# quand même, c'est que le test mesurait autre chose que le correctif.
	nav._on_profile_loaded({"player_level": 12.0, "current_xp": 300.0,
		"xp_to_next_level": 700.0, "coins_balance": 250.0})
	await get_tree().process_frame
	NetworkManager.mission_claimed.disconnect(nav._on_mission_claimed)
	NetworkManager.mission_claimed.emit({"coins_balance": 999.0, "reward_paid": 749.0})
	await get_tree().create_timer(0.9).timeout
	assert(_gauge_coins(nav) == 250)   # le DÉFAUT, reproduit à la demande
	assert(_flyout_coins(nav) == 250)
	# On RESTAURE dans le MÊME bloc (règle maison : ne jamais laisser un sabotage derrière soi).
	NetworkManager.mission_claimed.connect(nav._on_mission_claimed)
	NetworkManager.mission_claimed.emit({"coins_balance": 999.0, "reward_paid": 749.0})
	await get_tree().create_timer(0.9).timeout
	assert(_gauge_coins(nav) == 999)   # correctif rebranché → la jauge suit de nouveau
	checks += 3
	print("[OK] SABOTAGE : sans l'abonnement la jauge reste figee, rebranchee elle suit (3 asserts)")

	print("[OK] TEST CLAIM COINS GAUGE : %d asserts verts" % checks)
	get_tree().quit(0)


# Le panneau du mini-profil contient-il ce texte ? (parcours de l'arbre — on lit ce que le joueur
# VOIT, pas ce que la nav croit savoir.)
func _flyout_shows(nav: Control, needle: String) -> bool:
	return _find_label_text(nav._flyout_body, needle)


func _find_label_text(root: Node, needle: String) -> bool:
	if root == null:
		return false
	if root is Label and str((root as Label).text).find(needle) != -1:
		return true
	for c in root.get_children():
		if _find_label_text(c, needle):
			return true
	return false
