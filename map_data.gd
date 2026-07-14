extends Node

# =====================================================================================
# MapData — Graphe d'adjacence de la carte monde (type Risk classique, 42 territoires).
# Autoload (Singleton) : accessible partout via `MapData.TERRITORIES` / `MapData.CONTINENTS`.
#
# La carte n'est PLUS une grille abstraite : le Level Design 2D est fait MANUELLEMENT
# dans l'éditeur Godot (un nœud par territoire). Ce fichier ne contient que la VÉRITÉ
# mathématique (le graphe) ; board.gd relie les nœuds visuels à ces données par leur NOM.
#
# Identifiants (clés) : snake_case ASCII, stables, servent aussi de NOM de nœud dans la
# scène. Le `name` est le libellé affiché (français). `continent` référence CONTINENTS.
# `neighbors` est la liste des frontières (graphe NON orienté, symétrique).
#
# ⚠️ Contrat réseau : à terme l'état de partie (GameState.territories) doit être indexé
# par ces mêmes ids string (voir backend/api/game/map_data.py, miroir de ce fichier).
# =====================================================================================

# Continents et leur bonus de renforts (valeurs Risk classiques).
const CONTINENTS := {
	"north_america": {"name": "Amérique du Nord", "bonus": 5},
	"south_america": {"name": "Amérique du Sud", "bonus": 2},
	"europe": {"name": "Europe", "bonus": 5},
	"africa": {"name": "Afrique", "bonus": 3},
	"asia": {"name": "Asie", "bonus": 7},
	"oceania": {"name": "Océanie", "bonus": 2},
}

# Les 42 territoires du Risk classique. Frontières exactes (terrestres + routes maritimes).
const TERRITORIES := {
	# --- Amérique du Nord (9) ---
	"alaska": {"name": "Alaska", "continent": "north_america", "neighbors": ["northwest_territory", "alberta", "kamchatka"]},
	"northwest_territory": {"name": "Territoire du Nord-Ouest", "continent": "north_america", "neighbors": ["alaska", "alberta", "ontario", "greenland"]},
	"greenland": {"name": "Groenland", "continent": "north_america", "neighbors": ["northwest_territory", "ontario", "quebec", "iceland"]},
	"alberta": {"name": "Alberta", "continent": "north_america", "neighbors": ["alaska", "northwest_territory", "ontario", "western_united_states"]},
	"ontario": {"name": "Ontario", "continent": "north_america", "neighbors": ["northwest_territory", "alberta", "greenland", "quebec", "western_united_states", "eastern_united_states"]},
	"quebec": {"name": "Québec", "continent": "north_america", "neighbors": ["greenland", "ontario", "eastern_united_states"]},
	"western_united_states": {"name": "Ouest des États-Unis", "continent": "north_america", "neighbors": ["alberta", "ontario", "eastern_united_states", "central_america"]},
	"eastern_united_states": {"name": "Est des États-Unis", "continent": "north_america", "neighbors": ["ontario", "quebec", "western_united_states", "central_america"]},
	"central_america": {"name": "Amérique Centrale", "continent": "north_america", "neighbors": ["western_united_states", "eastern_united_states", "venezuela"]},

	# --- Amérique du Sud (4) ---
	"venezuela": {"name": "Venezuela", "continent": "south_america", "neighbors": ["central_america", "peru", "brazil"]},
	"peru": {"name": "Pérou", "continent": "south_america", "neighbors": ["venezuela", "brazil", "argentina"]},
	"brazil": {"name": "Brésil", "continent": "south_america", "neighbors": ["venezuela", "peru", "argentina", "north_africa"]},
	"argentina": {"name": "Argentine", "continent": "south_america", "neighbors": ["peru", "brazil"]},

	# --- Europe (7) ---
	"iceland": {"name": "Islande", "continent": "europe", "neighbors": ["greenland", "great_britain", "scandinavia"]},
	"scandinavia": {"name": "Scandinavie", "continent": "europe", "neighbors": ["iceland", "great_britain", "northern_europe", "ukraine"]},
	"great_britain": {"name": "Grande-Bretagne", "continent": "europe", "neighbors": ["iceland", "scandinavia", "northern_europe", "western_europe"]},
	"northern_europe": {"name": "Europe du Nord", "continent": "europe", "neighbors": ["scandinavia", "great_britain", "western_europe", "southern_europe", "ukraine"]},
	"western_europe": {"name": "Europe de l'Ouest", "continent": "europe", "neighbors": ["great_britain", "northern_europe", "southern_europe", "north_africa"]},
	"southern_europe": {"name": "Europe du Sud", "continent": "europe", "neighbors": ["northern_europe", "western_europe", "ukraine", "north_africa", "egypt", "middle_east"]},
	"ukraine": {"name": "Ukraine", "continent": "europe", "neighbors": ["scandinavia", "northern_europe", "southern_europe", "ural", "afghanistan", "middle_east"]},

	# --- Afrique (6) ---
	"north_africa": {"name": "Afrique du Nord", "continent": "africa", "neighbors": ["brazil", "western_europe", "southern_europe", "egypt", "east_africa", "congo"]},
	"egypt": {"name": "Égypte", "continent": "africa", "neighbors": ["southern_europe", "north_africa", "east_africa", "middle_east"]},
	"east_africa": {"name": "Afrique de l'Est", "continent": "africa", "neighbors": ["north_africa", "egypt", "congo", "south_africa", "madagascar", "middle_east"]},
	"congo": {"name": "Congo", "continent": "africa", "neighbors": ["north_africa", "east_africa", "south_africa"]},
	"south_africa": {"name": "Afrique du Sud", "continent": "africa", "neighbors": ["congo", "east_africa", "madagascar"]},
	"madagascar": {"name": "Madagascar", "continent": "africa", "neighbors": ["east_africa", "south_africa"]},

	# --- Asie (12) ---
	"ural": {"name": "Oural", "continent": "asia", "neighbors": ["ukraine", "siberia", "china", "afghanistan"]},
	"siberia": {"name": "Sibérie", "continent": "asia", "neighbors": ["ural", "yakutsk", "irkutsk", "mongolia", "china"]},
	"yakutsk": {"name": "Iakoutsk", "continent": "asia", "neighbors": ["siberia", "kamchatka", "irkutsk"]},
	"kamchatka": {"name": "Kamtchatka", "continent": "asia", "neighbors": ["yakutsk", "irkutsk", "mongolia", "japan", "alaska"]},
	"irkutsk": {"name": "Irkoutsk", "continent": "asia", "neighbors": ["siberia", "yakutsk", "kamchatka", "mongolia"]},
	"mongolia": {"name": "Mongolie", "continent": "asia", "neighbors": ["siberia", "irkutsk", "kamchatka", "japan", "china"]},
	"japan": {"name": "Japon", "continent": "asia", "neighbors": ["kamchatka", "mongolia"]},
	"afghanistan": {"name": "Afghanistan", "continent": "asia", "neighbors": ["ukraine", "ural", "china", "middle_east", "india"]},
	"china": {"name": "Chine", "continent": "asia", "neighbors": ["ural", "siberia", "mongolia", "afghanistan", "india", "siam"]},
	"middle_east": {"name": "Moyen-Orient", "continent": "asia", "neighbors": ["southern_europe", "ukraine", "egypt", "east_africa", "afghanistan", "india"]},
	"india": {"name": "Inde", "continent": "asia", "neighbors": ["afghanistan", "china", "middle_east", "siam"]},
	"siam": {"name": "Siam", "continent": "asia", "neighbors": ["china", "india", "indonesia"]},

	# --- Océanie (4) ---
	"indonesia": {"name": "Indonésie", "continent": "oceania", "neighbors": ["siam", "new_guinea", "western_australia"]},
	"new_guinea": {"name": "Nouvelle-Guinée", "continent": "oceania", "neighbors": ["indonesia", "western_australia", "eastern_australia"]},
	"western_australia": {"name": "Australie occidentale", "continent": "oceania", "neighbors": ["indonesia", "new_guinea", "eastern_australia"]},
	"eastern_australia": {"name": "Australie orientale", "continent": "oceania", "neighbors": ["new_guinea", "western_australia"]},
}

# --- Helpers ---

# =====================================================================================
# REGISTRE MULTI-CARTES (lot G5 §8.71) — miroir strict de backend/api/game/map_data.py
# =====================================================================================
# La carte « Théâtre Atlantique » est DÉRIVÉE du graphe 42 (sous-graphe induit NA+SA+EU,
# voisins filtrés) — aucune duplication de données, mêmes noms/bonus. Les constantes
# historiques (TERRITORIES/CONTINENTS) restent la carte classique : rien ne casse.

const DEFAULT_MAP_ID := "classic_42"
# Définitions du registre : label + continents inclus + bornes joueurs (miroir backend).
const MAP_DEFS := {
	"classic_42": {
		"label": "Guerre Mondiale",
		"continent_ids": ["north_america", "south_america", "europe", "africa", "asia", "oceania"],
		"min_players": 3, "max_players": 6,
	},
	"skirmish_atlantic": {
		"label": "Théâtre Atlantique",
		"continent_ids": ["north_america", "south_america", "europe"],
		"min_players": 3, "max_players": 4,
	},
}
# Cache des sous-cartes dérivées (calculées une fois par map_id).
var _maps_cache: Dictionary = {}

# Entrée du registre pour `map_id` (repli DÉFENSIF sur classic_42 — même contrat que le backend).
# Retour : { "label": String, "territories": Dictionary, "continent_territories": Dictionary }.
func get_map(map_id: String) -> Dictionary:
	var mid: String = map_id if MAP_DEFS.has(map_id) else DEFAULT_MAP_ID
	if _maps_cache.has(mid):
		return _maps_cache[mid]
	var def: Dictionary = MAP_DEFS[mid]
	var cont_ids: Array = def["continent_ids"]
	var terrs := {}
	var cont_terrs := {}
	for cid in cont_ids:
		cont_terrs[cid] = []
	for tid in TERRITORIES:
		var d: Dictionary = TERRITORIES[tid]
		if not cont_ids.has(d["continent"]):
			continue
		var nbrs: Array = []
		for n in d["neighbors"]:
			if cont_ids.has(TERRITORIES[n]["continent"]):
				nbrs.append(n)
		terrs[tid] = {"name": d["name"], "continent": d["continent"], "neighbors": nbrs}
		cont_terrs[d["continent"]].append(tid)
	var out := {
		"label": str(def["label"]),
		"territories": terrs,
		"continent_territories": cont_terrs,
	}
	_maps_cache[mid] = out
	return out

# Territoires de la carte donnée ("" → carte classique, comportement historique).
func map_territories(map_id: String = DEFAULT_MAP_ID) -> Dictionary:
	return get_map(map_id)["territories"]

# Libellé lisible d'une carte (radar du lobby, sélecteur de création).
func map_label(map_id: String) -> String:
	return str(get_map(map_id)["label"])

# Adjacence SUR LA CARTE DONNÉE (G5) : les voisins des sous-cartes sont filtrés — passer
# GameState.map_id en jeu. Sans map_id → carte classique (comportement historique intact).
func are_adjacent(a: String, b: String, map_id: String = DEFAULT_MAP_ID) -> bool:
	var terrs: Dictionary = get_map(map_id)["territories"]
	return terrs.has(a) and b in terrs[a]["neighbors"]

func neighbors_of(territory_id: String, map_id: String = DEFAULT_MAP_ID) -> Array:
	return get_map(map_id)["territories"].get(territory_id, {}).get("neighbors", [])

func continent_of(territory_id: String) -> String:
	return TERRITORIES.get(territory_id, {}).get("continent", "")

func territories_in_continent(continent_id: String) -> Array:
	var out: Array = []
	for tid in TERRITORIES:
		if TERRITORIES[tid]["continent"] == continent_id:
			out.append(tid)
	return out

func display_name(territory_id: String) -> String:
	return TERRITORIES.get(territory_id, {}).get("name", territory_id)

# Vérifie l'intégrité du graphe au démarrage (debug uniquement) : couverture, symétrie,
# pas de boucle, continents valides, connexité globale. N'altère pas le jeu en prod.
func _ready() -> void:
	if not OS.is_debug_build():
		return
	assert(TERRITORIES.size() == 42, "Le graphe doit contenir exactement 42 territoires.")
	for tid in TERRITORIES:
		var t: Dictionary = TERRITORIES[tid]
		assert(CONTINENTS.has(t["continent"]), "Continent inconnu pour %s" % tid)
		for n in t["neighbors"]:
			assert(n != tid, "%s ne peut pas être adjacent à lui-même." % tid)
			assert(TERRITORIES.has(n), "Voisin inconnu %s de %s" % [n, tid])
			assert(tid in TERRITORIES[n]["neighbors"], "Adjacence non symétrique : %s-%s" % [tid, n])
	# Connexité (BFS depuis alaska).
	var seen := {"alaska": true}
	var stack := ["alaska"]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		for n in TERRITORIES[cur]["neighbors"]:
			if not seen.has(n):
				seen[n] = true
				stack.append(n)
	assert(seen.size() == 42, "Le graphe doit être entièrement connexe.")
