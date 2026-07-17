extends Node

# =========================================================
# PORTEUR DE CONFIGURATION DE MATCH (Menu → Lobby)
# =========================================================
# Le Menu Principal (cartes de mode : Trio/Quad/Five/Exa + Classée) POSE ici l'intention de
# partie au clic « START » ; lobby_screen.gd la LIT pour pré-régler l'effectif (et, à terme, le
# mode classé). Découplage (Règle d'Or §6.1) : le menu ne fait AUCUNE logique réseau, il ne fait
# que déclarer un choix transporté jusqu'au lobby.
#
# ✅ DÉPENDANCE BACKEND CÂBLÉE (§8.88) : le mode « Classée » est désormais appliqué de bout en bout.
# `selected_ranked` part dans le payload de `NetworkManager.create_room(is_ranked=…)` → persisté sur
# `GameRoom.is_ranked` → recopié sur `GameState.is_ranked` → SEUL mode à créditer le ladder
# (points_classement + season_points) en fin de partie. Le SERVEUR fait autorité : il force
# l'effectif à 5 (RANKED_PLAYER_COUNT) et refuse en 400 une carte qui ne le supporte pas.
# L'effectif (3-6) passe nativement via le champ `max_players` de create_room.

# Effectif visé : 3=Trio, 4=Quad, 5=Five/Classée, 6=Exa. 0 = aucune sélection (le lobby garde
# alors son SpinBox par défaut — rétrocompatibilité avec un accès direct au lobby).
var selected_player_count: int = 0
# Mode classé (« Classée ») : exactement 5 joueurs, seul mode au classement. Intention client.
var selected_ranked: bool = false
# Id canonique du mode choisi (pour libellés / télémétrie d'UI). "" si non défini.
var selected_mode_id: String = ""


# Pose le mode choisi (appelé par main_menu.gd au clic « START »).
func set_mode(mode_id: String, player_count: int, ranked: bool) -> void:
	selected_mode_id = mode_id
	selected_player_count = player_count
	selected_ranked = ranked


# Réinitialise l'intention (legacy / après consommation par le lobby).
func clear() -> void:
	selected_mode_id = ""
	selected_player_count = 0
	selected_ranked = false
