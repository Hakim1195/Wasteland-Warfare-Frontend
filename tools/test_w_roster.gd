extends Node

# TEST W (chantier W, écran PERSONNAGES -> ROSTER en grille) — style maison, pattern
# tools/test_e1_roster.gd. Boot headless AVEC autoloads réels, roster FACTICE injecté DIRECTEMENT
# via _on_heroes_loaded (aucun serveur requis), asserts puis quit :
#   & <godot_console> --headless --path frontend res://tools/test_w_roster.tscn
# ⚠️ Signal de réussite FIABLE = la ligne finale « [OK] TEST W ROSTER : tous les asserts verts »
# est présente dans la sortie. NE PAS se fier au code retour : un assert raté BLOQUE le process (il
# n'atteint jamais quit(0), cf. _ready plus bas) au lieu de le faire échouer proprement — lancé avec
# un filet anti-hang du style `--quit-after 30`, Godot quitte de lui-même après N frames avec le
# code 0 MÊME SUR UN RUN ROUGE. Une ligne « SCRIPT ERROR » sur stderr = échec, quel que soit le code
# retour.
#
# Cible en particulier le critère d'acceptation explicite du chantier : « carte N ouvre la fiche N,
# jamais une autre » (piège Callable.bind()), plus la machine à états, le compteur d'en-tête, le
# badge FAVORI et l'absence de persistance au clic (déménagée vers la tâche suivante).

const CharactersScreen := preload("res://scenes/ui/characters_screen.tscn")

const FIDS := ["phalangistes", "nomades", "rad_hunters", "barons_ferraille", "gardiens_eden",
	"corporation_aegis", "ecorcheurs_cendres", "eveilles_ruche", "ordre_eclipse", "chasseurs_ombres"]

# 1 exemplaire de chaque access.type, réparti sur les 10 entrées (index -> access) : 0=owned,
# 1=free, 2=rotation(2/3), 3=pass, 4=locked(4500), 5=owned, 6=free, 7=rotation(1/3), 8=pass,
# 9=locked. Permanents (free/owned) = {0,1,5,6} -> owned_count attendu = 4.
const ACCESS_CYCLE := [
	{"type": "owned"},
	{"type": "free"},
	{"type": "rotation", "free_games_left": 2, "free_games_max": 3},
	{"type": "pass"},
	{"type": "locked", "price": 4500},
]

func _build_mock_heroes() -> Array:
	var out := []
	for i in FIDS.size():
		var fid: String = FIDS[i]
		var template: Dictionary = ACCESS_CYCLE[i % ACCESS_CYCLE.size()]
		var access: Dictionary = template.duplicate()
		if str(access.get("type", "")) == "locked" and i >= ACCESS_CYCLE.size():
			access["price"] = 9999  # 2e cadenas, prix DIFFÉRENT du premier (index 4).
		out.append({
			"faction_id": fid, "faction_name": fid.capitalize(), "faction_category": "test",
			"hero_power": "Test power",
			"hero_name": "Hero " + str(i), "hero_callsign": "", "hero_rank": "captain",
			"identity": {
				"first_name": "Prenom%d" % i, "last_name": "Nom%d" % i, "callsign": "",
				"char_code": "CHAR-%03d" % (i + 1), "rank": "captain",
				"display_name": "Prenom%d Nom%d" % [i, i],
			},
			"level": 10 + i, "xp_total": 1000, "xp_in_level": 100, "xp_for_level": 500,
			"xp_to_next": 400, "stats": {}, "stats_max": {}, "milestones": [],
			"owned": str(access.get("type", "")) in ["free", "owned"],
			"access": access,
			"record": {"games": 0, "wins": 0, "losses": 0, "winrate": 0},
			"evolution": {"levels_left": 0, "coins_potential": {}, "coins_earned": 0},
		})
	return out

# Concatène récursivement le .text de tous les Label descendants (recherche de contenu robuste à
# une réorganisation de la hiérarchie de la carte — pas d'indexation en dur).
func _collect_label_texts(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		_collect_label_texts(c, out)

# `true` si au moins un texte de `texts` contient TOUTES les sous-chaînes de `needles`.
func _any_text_contains_all(texts: Array, needles: Array) -> bool:
	for t in texts:
		var s := str(t)
		var all_found := true
		for n in needles:
			if not s.contains(str(n)):
				all_found = false
				break
		if all_found:
			return true
	return false

# Le bouton-capteur d'une carte n'est PAS forcément le DERNIER enfant : WarzoneUI.add_corner_notches
# ajoute encore 2 Polygon2D (Notch_tl/Notch_br) APRÈS lui. On le retrouve par TYPE, pas par position.
func _find_button(node: Node) -> Button:
	for c in node.get_children():
		if c is Button:
			return c
	return null

func _ready() -> void:
	# Sauvegarde du réglage MACHINE avant toute écriture (revue de code, point 1) :
	# set_selected_faction() écrit IMMÉDIATEMENT dans user://settings.cfg (SettingsManager._save(),
	# pas de mode "test" séparé) — sans restauration, CE harnais changerait SILENCIEUSEMENT, à
	# CHAQUE exécution, le personnage affiché au menu principal du poste qui le lance
	# (main_menu.gd:_explicit_faction lit cette même clé persistée).
	# ⚠️ Fenêtre de mutation VOLONTAIREMENT ÉTROITE (c'est déjà arrivé une fois en développement) :
	# un assert() raté ABORT la pile d'appel IMMÉDIATEMENT (cf. entête de fichier) — tout code PLUS
	# LOIN dans cette fonction, restauration comprise, ne s'exécute alors JAMAIS. Restaurer "juste
	# avant quit(0)" est donc un piège : n'importe lequel des ~20 asserts qui n'ont RIEN à voir avec
	# le favori (badges d'accès, routage carte->fiche, compteur d'en-tête...) peut planter et laisser
	# le settings.cfg RÉEL de l'utilisateur avec la valeur de test. La valeur mutée n'est nécessaire
	# QUE pour les asserts du bloc 3 (badge ★) ci-dessous : on la pose, on fait UNIQUEMENT tourner ce
	# bloc-là (juste après l'injection du roster dont il dépend), on restaure IMMÉDIATEMENT après —
	# puis seulement ENSUITE tous les autres asserts s'enchaînent, avec le réglage déjà propre quoi
	# qu'il arrive.
	var original_faction := SettingsManager.get_selected_faction()

	var inst = CharactersScreen.instantiate()
	# Favori AVANT le chargement du roster (comme en jeu : la faction persistée est déjà connue) —
	# "nomades" (index 1) doit porter le badge ★, aucune autre carte.
	SettingsManager.set_selected_faction("nomades")
	add_child(inst)

	# --- 1) État initial : roster visible, aucune fiche ouverte (auto-sélection RETIRÉE). ---
	assert(inst._state == "roster")
	assert(inst._sheet_index == -1)
	assert(inst.roster_view.visible == true)
	assert(inst.sheet_view.visible == false)
	print("[OK] etat initial : roster visible, sheet ferme, _sheet_index=-1 (4 asserts)")

	# --- 2) Injection du roster FACTICE (contrat /heroes enrichi) — sans passer par le réseau. ---
	var mock := _build_mock_heroes()
	inst._on_heroes_loaded(mock)
	assert(inst.hero_grid.get_child_count() == mock.size())
	print("[OK] grille peuplee : %d cartes pour %d heros (1 assert)" % [inst.hero_grid.get_child_count(), mock.size()])

	# --- 2bis) L'auto-sélection RETIRÉE ne doit PAS réapparaître (revue de code, point 2). Le bloc
	# 1) ne prouvait "aucune fiche ouverte" qu'AVANT _on_heroes_loaded, où aucune auto-sélection
	# n'aurait de toute façon pu se produire — angle mort. On revérifie ICI, APRÈS le chargement du
	# roster RÉEL : si _on_heroes_loaded rappelait un jour _show_sheet(...)/ouvrait une fiche, ces
	# asserts doivent le détecter. Contre-épreuve manuelle faite (cf. rapport de tâche) : ajout
	# temporaire d'un auto-select dans _on_heroes_loaded -> suite ROUGE (assert bloqué) -> retrait ->
	# suite VERTE à nouveau. ---
	assert(inst._state == "roster")
	assert(inst._sheet_index == -1)
	assert(inst.sheet_view.visible == false)
	print("[OK] aucune auto-selection apres reception du roster reel (3 asserts)")

	# --- 3) Badge FAVORI : présent UNIQUEMENT sur la carte "nomades" (index 1). Placé ICI, tout de
	# suite après l'injection du roster dont il dépend (bloc 2) — c'est le SEUL bloc de cette
	# fonction qui a besoin de la faction de test "nomades" encore active. La restauration juste en
	# dessous referme la fenêtre de mutation AVANT que le moindre autre assert (compteur d'en-tête,
	# badges d'accès, routage carte->fiche, persistance) ne puisse planter dessus. Le badge ★ est de
	# toute façon "cuit en dur" dans les nœuds de la carte au moment de sa construction ci-dessus
	# (characters_screen.gd lit SettingsManager UNE SEULE FOIS pendant _on_heroes_loaded, pas de
	# relecture live) : restaurer maintenant ne fait donc PAS disparaître le badge déjà affiché,
	# vérifié plus bas au bloc 5. ---
	for i in mock.size():
		var card := inst.hero_grid.get_child(i) as Control
		var texts: Array = []
		_collect_label_texts(card, texts)
		var has_fav: bool = texts.has("CHAR_FAVORITE")
		assert(has_fav == (i == 1))
	print("[OK] badge FAVORI uniquement sur la carte nomades (index 1) (10 asserts)")

	# Restauration IMMÉDIATE (revue de code, point 1) : reposer EXACTEMENT le réglage trouvé au
	# démarrage dès que les asserts qui en dépendent (bloc 3 ci-dessus) sont passés, plutôt que
	# d'attendre la fin de la fonction (cf. commentaire en tête de _ready). Tous les asserts restants
	# ci-dessous tournent donc avec le settings.cfg RÉEL de l'utilisateur déjà remis en place.
	SettingsManager.set_selected_faction(original_faction)

	# --- 4) Compteur d'en-tête : 4 permanents (free/owned) sur 10, DANS CET ORDRE (locale-agnostique
	# : on ne cherche que les chiffres, jamais le libellé traduit). Sous-chaîne ORDONNÉE "4/10"
	# (revue de code, point 7) — PAS deux .contains() séparés : ["4","10"] indépendants passeraient
	# AUSSI pour un compteur affichant "10/4" ; un renversement des 2 arguments %d de
	# CHAR_ROSTER_COUNT en production passerait alors inaperçu. ---
	var count_txt: String = inst.roster_count_label.text
	assert(count_txt.contains("4/10"))
	print("[OK] compteur roster = '%s' (contient la sous-chaine ordonnee '4/10', 1 assert)" % count_txt)

	# --- 5) Badges d'accès : contenu correct par état, en formes ORDONNÉES/STRUCTURELLES plutôt que
	# la simple présence de sous-chaînes isolées (revue de code, point 8 — un ["2","3"] séparé passe
	# AUSSI pour "3/2" : un renversement des 2 arguments %d de CHAR_ACCESS_ROTATION en production
	# passerait inaperçu). "pass" (carte 3) et "free" (carte 1) étaient jusqu'ici NON testés. ---
	var texts2: Array = []
	_collect_label_texts(inst.hero_grid.get_child(2) as Control, texts2)  # rotation 2/3
	assert(_any_text_contains_all(texts2, ["2/3"]))
	var texts4: Array = []
	_collect_label_texts(inst.hero_grid.get_child(4) as Control, texts4)  # locked 4500
	assert(_any_text_contains_all(texts4, ["4500"]))
	var texts0: Array = []
	_collect_label_texts(inst.hero_grid.get_child(0) as Control, texts0)  # owned, non-favori -> AUCUN badge
	# Absence STRUCTURELLE du badge, pas seulement l'absence de la chaîne "4500" : 3 Labels PILE
	# attendus (nom, faction, niveau) — un badge affichant un AUTRE texte qu'un prix serait
	# désormais détecté aussi (une régression future n'a pas à "deviner" pour être visible ici).
	assert(texts0.size() == 3)
	var texts3: Array = []
	_collect_label_texts(inst.hero_grid.get_child(3) as Control, texts3)  # pass
	assert(_any_text_contains_all(texts3, [tr("CHAR_ACCESS_PASS")]))
	var texts1: Array = []
	_collect_label_texts(inst.hero_grid.get_child(1) as Control, texts1)  # free + favori (nomades)
	# "free" = accès PERMANENT comme "owned" -> AUCUN badge. 4 Labels PILE attendus : rangée FAVORI
	# (cette carte EST "nomades", cf. bloc 3 plus haut) + nom + faction + niveau — PAS de 5e Label
	# de badge.
	assert(texts1.size() == 4)
	print("[OK] badges d'acces : rotation 2/3, locked 4500, owned=aucun badge, pass present, free=aucun badge (5 asserts)")

	# --- 6) LE critère d'acceptation explicite : carte N ouvre la fiche N, JAMAIS une autre. ---
	# Simule le clic (emit du bouton-capteur, retrouvé par TYPE via _find_button) sur plusieurs
	# index dispersés (bord gauche, milieu, bord droit) plutôt qu'un seul, pour détecter tout
	# décalage systématique (piège Callable.bind() décrit par le brief).
	for idx in [0, 4, 9]:
		var card := inst.hero_grid.get_child(idx) as Control
		var overlay_btn := _find_button(card)
		assert(overlay_btn != null)
		overlay_btn.pressed.emit()
		assert(inst._state == "sheet")
		assert(inst._sheet_index == idx)
		assert(inst.roster_view.visible == false)
		assert(inst.sheet_view.visible == true)
		# _sheet_index == idx prouve l'INDEX retenu, mais pas que la fiche RENDU vraiment CE héros-là
		# (revue de code, point 9 — angle mort précédent : _populate_detail pourrait en théorie être
		# appelée avec un autre hero tout en laissant _sheet_index correct). Preuve par le CONTENU :
		# le NIVEAU de ce héros (10 + idx dans le mock, distinct par index) doit apparaître dans
		# detail_box. Comparé à mock[idx] (valeur CONNUE du mock), jamais au catalogue de factions
		# réel — une tentative précédente devinait un nom de faction du catalogue et s'est révélée
		# fragile (supprimée plutôt que réparée, cf. rapport de tâche). Égalité EXACTE sur un élément
		# du tableau (pas .contains()) : le bloc XP de ce mock affiche "100" (contient la sous-chaîne
		# "10") — un simple .contains("10") passerait donc à TORT quel que soit l'idx ouvert ; seul un
		# Label dont le texte VAUT exactement "10"/"14"/"19" (cf. lvl_value.text = str(level) dans
		# _populate_detail) prouve que CE niveau précis est bien affiché.
		var detail_texts: Array = []
		_collect_label_texts(inst.detail_box, detail_texts)
		assert(detail_texts.has(str(mock[idx]["level"])))
		inst._show_roster()
		assert(inst._state == "roster")
		assert(inst._sheet_index == -1)
		assert(inst.roster_view.visible == true)
		assert(inst.sheet_view.visible == false)
		print("[OK] carte %d -> fiche %d (jamais une autre ; niveau %d confirme dans detail_box), retour roster propre (10 asserts)" % [idx, idx, mock[idx]["level"]])

	# --- 7) Aucune persistance au clic sur une carte (déménagée vers la tâche suivante). Comparé à
	# original_faction et non plus au litéral "nomades" : le réglage a déjà été restauré (bloc 3
	# ci-dessus), BIEN AVANT que ces clics n'aient lieu. L'invariant testé reste le même — le CLIC ne
	# touche pas au réglage persisté, quelle que soit sa valeur courante. ---
	assert(SettingsManager.get_selected_faction() == original_faction)
	print("[OK] aucune persistance de favori au clic sur une carte (1 assert)")

	print("[OK] TEST W ROSTER : tous les asserts verts")
	get_tree().quit(0)
