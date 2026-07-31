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
# Carte choisie pour une partie PUBLIQUE (§8.116) : posée par search_screen (sélecteur CLASSIQUE /
# RAPIDE) ou par requeue. En CLASSÉE, ignorée (le serveur force classic_42). Défaut classic_42.
var selected_map_id: String = "classic_42"

# --- MODE ÉQUIPES (§8.124) ---
# Playlist d'ÉQUIPE choisie au menu ("duo_2v2" | "squad_3v3" | …), "" = aucune. Transportée jusqu'à
# l'écran ESCOUADE, qui la pré-sélectionne. ⚠️ Elle NE PORTE NI carte NI effectif : ces deux
# informations vivent dans le REGISTRE SERVEUR (`NetworkManager.team_playlists`) et nulle part
# ailleurs côté client — c'est ce qui permet d'ouvrir un format sans redéployer le client.
var selected_team_playlist: String = ""


# Pose la playlist d'ÉQUIPE choisie (main_menu → squad_screen). Efface l'intention SOLO : les deux
# chemins sont exclusifs, et laisser traîner un effectif de partie solo ferait mentir l'écran de
# recherche si le joueur revenait en arrière.
func set_team_playlist(playlist_id: String) -> void:
	selected_team_playlist = playlist_id
	selected_mode_id = ""
	selected_player_count = 0
	selected_ranked = false


# Pose le mode choisi (appelé par main_menu.gd au clic « START »).
func set_mode(mode_id: String, player_count: int, ranked: bool) -> void:
	selected_mode_id = mode_id
	selected_player_count = player_count
	selected_ranked = ranked
	# Exclusivité SOLO / ÉQUIPE (cf. set_team_playlist) : choisir un effectif solo annule la
	# playlist d'équipe, sinon l'écran ESCOUADE la retrouverait à la prochaine visite.
	selected_team_playlist = ""


# Pose la carte choisie (search_screen / requeue). Sans effet sur la classée (serveur = autorité).
func set_map(map_id: String) -> void:
	selected_map_id = map_id


# Réinitialise l'intention (appelée au retour au QG — main_menu._ready, §8.116).
func clear() -> void:
	selected_mode_id = ""
	selected_player_count = 0
	selected_ranked = false
	selected_map_id = "classic_42"
	selected_team_playlist = ""
