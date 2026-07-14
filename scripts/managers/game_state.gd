extends Node

var players: Dictionary = {}
var territories: Dictionary = {}
var current_turn: int = 1
var current_player_id: int = 1
var current_phase: int = 1

# --- Pré-game (Lot 1) : exposés pour l'UI à venir (Lots 2/3), pas encore affichés ici. ---
# stage ∈ {"initiative", "placement", "playing"}.
var stage: String = "playing"
var turn_order: Array = []
var setup_index: int = 0
var initiative_rolls: Dictionary = {}
var objectives: Dictionary = {}
var winner_id = null  # null tant que la partie n'est pas gagnée

# Carte jouée (registre multi-cartes G5 §8.71 : "classic_42" | "skirmish_atlantic").
# Posée à chaque update_from_json ; défaut classic (rétro-compat serveur antérieur).
var map_id: String = "classic_42"

# Version du client (auto-updater, CONTEXTE.md §9). Renseignée par le bootloader au démarrage
# à partir de user://client_version.txt (défaut "1.0.0"). Envoyée au serveur dans l'URL du
# WebSocket (network_manager) pour la validation de version stricte côté backend.
var client_version: String = "1.0.0"

# Zone radioactive (§8.27) : modèle CLUSTER {"territories": [tid, ...], "probability": float}.
# Déclarée AVEC un défaut {} pour que la propriété existe TOUJOURS sur le singleton, même avant
# le 1er message réseau. Sans ça, board.gd accédant à GameState.contamination_zone avant synchro
# plante (« Invalid access to property 'contamination_zone' ») et bloque le client sur un écran
# gris (race condition au lancement). Avec ce défaut, board retombe proprement sur un cluster vide.
var contamination_zone: Dictionary = {}

# « Mémoire Tactique » (§8.35 CONTRAT_RESEAU / §8.36 FRONTEND) : statistiques GLOBALES PUBLIQUES de
# la partie, diffusées intégralement par le serveur (non rédigées). Modèle backend `GameStatistics` :
#   - zone_kills_by_player : { "<player_id>": <kills> } — clés STR en JSON (§5), valeurs en float.
#   - zone_stagnation_turns : int — rounds globaux consécutifs sans déplacement de la zone.
# Défaut {} pour que la propriété existe TOUJOURS (même avant le 1er message, ou état Redis antérieur
# sans le champ). Consommée par main.gd -> hud.set_intel (tiroir Intel), jamais par le HUD en direct
# (Règle d'Or §6.1 : le HUD est une View, le contrôleur résout pseudos + couleurs).
var statistics: Dictionary = {}

func update_from_json(state_data: Dictionary):
	players = state_data.get("players", {})
	territories = state_data.get("territories", {})
	current_turn = state_data.get("current_turn", 1)
	current_player_id = state_data.get("current_player_id", 1)
	# Le serveur (state_schemas.GameState) sérialise la clé "phase" (0 à 5), pas "current_phase".
	current_phase = state_data.get("phase", 0)

	# Champs de préparation de partie.
	stage = state_data.get("stage", "playing")
	turn_order = state_data.get("turn_order", [])
	setup_index = state_data.get("setup_index", 0)
	initiative_rolls = state_data.get("initiative_rolls", {})
	objectives = state_data.get("objectives", {})
	winner_id = state_data.get("winner_id", null)
	# Carte jouée (registre multi-cartes G5 §8.71) — diffusée dans l'état ; défaut classic
	# (serveur antérieur / état legacy). Consommée par board.gd (masquage) et MapData (adjacence).
	map_id = str(state_data.get("map_id", "classic_42"))
	# NB : `is_bot` (G2 §8.72) est un champ PUBLIC de chaque PlayerState (dans `players`) — lu
	# directement via GameState.players[pid].is_bot par main.gd/hud.gd (pas de miroir dédié ici).
	# Le serveur sérialise la zone radioactive ; défaut {} si absente (état pré-game/placement).
	contamination_zone = state_data.get("contamination_zone", {})
	# « Mémoire Tactique » (§8.35) : statistiques globales publiques (alimente le tiroir Intel, §8.36).
	statistics = state_data.get("statistics", {})
	# Le rafraîchissement de l'UI est piloté par le contrôleur d'arène (main.gd) via le
	# signal NetworkManager.game_state_updated — l'état ne connaît pas l'UI (Règle d'Or §6.1).

# Numéro de joueur SÉQUENTIEL (1..N) pour l'affichage, calculé par rang croissant des
# player_id (= User.id). Découple le libellé affiché de l'id brut de la base, dont les trous
# d'auto-incrément (inscriptions échouées, comptes supprimés) faisaient apparaître des "Joueur
# #1, #3, #4…" sans jamais de #2. Même ordre que la palette du plateau (board.gd trie aussi
# les ids), donc "Joueur N" et sa couleur sont cohérents.
func player_number(pid) -> int:
	var ids: Array = []
	for k in players.keys():
		ids.append(int(k))
	ids.sort()
	var idx := ids.find(int(pid))
	return idx + 1 if idx >= 0 else int(pid)


# =====================================================================
# Couche RPG « Héros » (sprint RPG & Survie)
# =====================================================================
# Les stats du héros sont sérialisées DANS chaque entrée players[pid] par le serveur (PlayerState) :
# hero_pv_current/max, hero_pa, hero_pb (réduction 0..0.30), hero_pp_current/min/max, hero_level,
# hero_regen, is_dead. Champs PUBLICS (aucune redaction → inspection adverse OK, cf. CONTRAT_RESEAU
# « la redaction ne masque que les objectifs »). On les expose normalisés pour le HUD/l'inspecteur.
# Piège JSON float (§5) : les clés de `players` sont des STR ("1","2") et les nombres des float → on
# normalise (int/str) ici pour que les vues n'aient jamais à le refaire.
func hero_of(pid) -> Dictionary:
	var p = players.get(str(int(pid)), null)
	if p == null:
		p = players.get(int(pid), null)
	if not (p is Dictionary):
		return {}
	return {
		"pv_current": int(p.get("hero_pv_current", 0)),
		"pv_max": int(p.get("hero_pv_max", 0)),
		"pa": int(p.get("hero_pa", 0)),
		"pb": float(p.get("hero_pb", 0.0)),
		"pp_current": int(p.get("hero_pp_current", 0)),
		"pp_min": int(p.get("hero_pp_min", 0)),
		"pp_max": int(p.get("hero_pp_max", 0)),
		"level": int(p.get("hero_level", 1)),
		"regen": float(p.get("hero_regen", 0.0)),
		"is_dead": bool(p.get("is_dead", false)),
		"faction": str(p.get("faction", "")),
		# Barre d'XP du panneau héros (snapshot méta-jeu, statique pendant le match ; 0/0 = niveau max
		# ou état pré-RPG → la vue masque la barre). Voir PlayerState.hero_xp_in_level/for_level.
		"xp_in_level": int(p.get("hero_xp_in_level", 0)),
		"xp_for_level": int(p.get("hero_xp_for_level", 0)),
	}


# Vrai si le joueur a un héros INITIALISÉ (pv_max > 0). Faux pour un état pré-RPG / pré-game : le HUD
# masque alors le panneau héros (rétro-compat, pas de jauges à 0 trompeuses).
func has_hero(pid) -> bool:
	return hero_of(pid).get("pv_max", 0) > 0
