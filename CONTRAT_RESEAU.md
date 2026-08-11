# 📡 CONTRAT RÉSEAU — Wasteland Warfare

> **Rôle de ce fichier :** Architecture de l'**API (FastAPI)**, schémas de données, gestion des **WebSockets**, payloads du **Chat**, et logique de **« State Redaction » par destinataire**. C'est la source de vérité du contrat client↔serveur (REST + temps réel).
>
> **Index / Routeur :** [`CONTEXTE.md`](CONTEXTE.md) — **Voir aussi :** [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md) · [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md) · [`PIPELINE_ET_BOOTLOADER.md`](PIPELINE_ET_BOOTLOADER.md)
>
> **DIRECTIVE IA :** La **numérotation d'origine** (`§5`, `§8.x`…) est **CONSERVÉE** pour préserver les renvois croisés. Ce fichier contient la section **§5** et les entrées du journal **§8** réseau/backend-serveur : **§8.9, §8.12, §8.20, §8.26, §8.28, §8.31, §8.33, §8.34, §8.35, §8.46, §8.47, §8.48, §8.61**. **Rappel critique :** un correctif **backend nécessite push + redéploiement VPS** pour être actif (voir §1 dans [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md) et §8.7 dans [`PIPELINE_ET_BOOTLOADER.md`](PIPELINE_ET_BOOTLOADER.md)). Si tu modifies un **endpoint**, un **message WS**, un **schéma** ou un **payload**, mets à jour CE fichier.

---

# 📡 PROTOCOLE DE SYNCHRONISATION INTER-IA

> **🤖 À L'ATTENTION DE L'AGENT IA FRONTEND.** Ce document est la **SOURCE DE VÉRITÉ UNIQUE ET
> NORMATIVE** de tous les formats de données échangés entre le client Godot et le serveur FastAPI :
> **payloads JSON REST**, **messages WebSocket**, **schémas d'état** et **payloads de Chat**. Il est
> rédigé et maintenu par l'agent IA **Backend** ; il fait foi.
>
> **RÈGLE ABSOLUE — INTERDICTION DE DEVINER.** Tu n'as **PAS** le droit d'inventer, de supposer ou de
> « deviner » une structure réseau (nom de clé, type, enveloppe de message, forme d'un dictionnaire
> imbriqué) qui ne serait **pas explicitement documentée ici**. Si une donnée dont tu as besoin
> **n'apparaît pas** dans ce contrat : **ne code pas un parseur spéculatif** — signale-le dans ta
> réponse pour que l'agent Backend ajoute le champ au schéma ET à ce fichier. Tout champ lu côté
> client DOIT correspondre, **au nom et au type près**, à une entrée de ce document.
>
> **PROCÉDURE DE MODIFICATION.** Tout ajout/changement de clé, de type, d'endpoint, de message WS ou
> de payload se fait **d'abord ici** (côté Backend), puis est consommé côté client. Un correctif
> backend n'est **actif** qu'après **push + redéploiement VPS** (§1 dans [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md)) :
> tant que le VPS n'est pas à jour, le client doit lire les nouveaux champs **défensivement** (valeur
> par défaut si absent).

### ⚠️ RÈGLE DE TYPAGE N°1 — Le « Piège JSON float » (Godot)

`JSON.parse_string` (Godot) **convertit TOUS les nombres JSON en `float`**, et les **clés d'objet JSON
sont TOUJOURS des `string`**. Conséquences **NORMATIVES** côté client :

- Un `id` (joueur, salle, territoire numérique…) lu du réseau arrive en `float` → `11.0`. **Toujours
  appliquer `int(...)` AVANT de l'utiliser** comme entier, comme clé, ou dans une URL.
- ⚠️ **`str(11.0)` produit `"11.0"` en Godot, PAS `"11"`.** Pour indexer un dictionnaire dont les clés
  sont des `player_id`/`territory_id` (`players`, `objectives`, `initiative_rolls`,
  `statistics.zone_kills_by_player`…), il faut **`str(int(pid))`** — jamais `str(pid)` sur un float
  (sinon la clé `"11"` n'est jamais trouvée). *(Cf. régression historique « salle 11.0 » §8.9.)*
- Un `bool` JSON (`true`/`false`) → `bool` Godot ; lire avec un défaut (`bool(d.get("is_active", true))`).

### 🧩 SCHÉMAS DE RÉFÉRENCE TYPÉS (annotés)

> Les blocs ci-dessous sont des **schémas annotés** (commentaires `// <type>`), **pas du JSON strict**.
> Les `int`/`float` transitent en nombres JSON (donc `float` côté Godot, cf. règle ci-dessus). Les
> **clés de dictionnaire indexées par id sont des `string`** dans le JSON.

**A. REST — `GET /lobby/rooms` → `Array<GameRoomResponse>` ; `POST /lobby/rooms` → `GameRoomResponse`** (cf. `models/schemas.py`) — ⚠️ **BLOC SUPERSÉDÉ EN INTÉGRALITÉ PAR §8.116.** Ces routes (+ `POST .../join`, `DELETE .../leave`) **N'EXISTENT PLUS** (`api/v1/endpoints/lobby.py` supprimé). Remplacées par **§G** (files d'attente) et **§H** (salons privés) plus bas. Bloc conservé pour l'historique.
```jsonc
{
  "id": 11,                 // int  — id de salle (⚠️ int() avant str()/URL)
  "status": "waiting",      // string — "waiting" | "playing" | ...
  "max_players": 6,         // int  — borné serveur aux bornes de la CARTE (§8.71) ; FORCÉ à 5 si is_ranked (§8.88)
  "is_private": false,      // bool — les salles privées sont masquées de la liste publique
  "secret_code": null,      // string | null
  "current_players": 3,     // int  — OCCUPATION COURANTE (§8.34). Défaut 0 si VPS pas redéployé.
  "is_ranked": false,       // bool — partie CLASSÉE (§8.88). ADDITIF, défaut false. Décidé à la CRÉATION.
  "created_at": null        // string (ISO-8601) | null
}
```
> **`POST /lobby/rooms` — gate CLASSÉE (§8.88).** `is_ranked: true` dans le payload ⇒ le serveur **FORCE `max_players = 5`** (`ranked.RANKED_PLAYER_COUNT` — le `max_players` du client est ignoré) et **refuse en `400`** si la carte demandée ne supporte pas 5 joueurs (aujourd'hui `skirmish_atlantic`, bornée 3-4 → seule `classic_42` accepte une classée). Helper PUR `api/game/ranked.ranked_room_bounds(game_map, requested_max, is_ranked)`.

**F. REST — `GET /api/v1/leaderboard?limit=N&offset=0` → `LeaderboardResponse`** (PUBLIC ; bloc `me` ajouté si un token Bearer est joint ; tri `stats_victoires` desc, départage `niveau` desc puis `points_classement` desc ; cf. `models/schemas.py`, §9.2/§8.46)
```jsonc
{
  "entries": [
    {
      "rank": 1,                    // int  — rang GLOBAL 1-based (offset inclus)
      "username": "Hakim",          // string — pseudo du joueur
      "level": 4,                   // int  — alias canonique de "niveau" (§9.2)
      "wins": 12,                   // int  — alias canonique de "stats_victoires" (clé de tri, desc)
      "niveau": 4,                  // int  — alias historique (= level)
      "stats_victoires": 12,        // int  — alias historique (= wins)
      "stats_parties_jouees": 30,   // int  — parties jouées
      "points_classement": 1530     // int  — points de classement (départage)
    }
  ],
  "me": {                           // null si la requête n'est PAS authentifiée
    "rank": 137,                    // int  — rang GLOBAL du joueur courant (même hors page)
    "username": "Hakim", "level": 4, "wins": 12
  }
}
```

**B. WebSocket — enveloppes serveur → client** (champ discriminant : `type`)
```jsonc
{ "type": "action_result", "event": { /* Event, voir §D */ }, "state": { /* GameState, voir §C */ } }
{ "type": "game_started",  "state": { /* GameState */ },
  "draft_deadline_at": 1752505600.0 }   // échéance UNIX (s) d'auto-verrouillage du draft (G2 durci) | null
{ "type": "player_abandoned", "player_id": 11, "state": { /* GameState */ } }   // player_id: int
{ "type": "error",   "message": "Ce n'est pas votre tour." }                     // message: string
{ "type": "player_disconnected", "player_id": 11 }                              // player_id: int
// ⚠️ SUPPRIMÉ §8.116 : { "type": "lobby_state", "players": [...], "ready": [...], "usernames": {...}, "bot_fill_at": ..., "max_players": ... } — n'existe plus, avec toute la machinerie ready/unready/get_lobby/bot-fill lobby
{ "type": "salon_state", "count": 2, "max_players": 4, "is_creator": false }   // NOUVEAU §8.116 — salon privé UNIQUEMENT ; envoyé INDIVIDUELLEMENT à chaque socket (handshake, départ d'un membre, réponse à get_salon) ; count/max_players: int, is_creator: bool ; AUCUN pseudo/id/liste (décision produit n°2)
{ "type": "salon_closed", "reason": "host_cancelled" }   // NOUVEAU §8.116 — reason: string ; diffusé à la salle puis fermeture des sockets (code 1000, normal)
{ "type": "faction_locked", "player_id": 11, "faction_id": "culte_isotope" }    // player_id: int, faction_id: string
{ "type": "draft_state", "locked": { "11": "culte_isotope", "-1": "barons_ferraille" }, // PRIVÉ (réponse à get_draft) — { "<player_id:str>": faction_id }
  "draft_deadline_at": 1752505600.0 }   // photographie COMPLÈTE des verrouillages (bots compris) ; rattrape les faction_locked manqués (G2 durci)
{ "type": "game_over", "winner_id": 11, "match_type": "objective", "rankings": [11, 12, 13], // rankings: Array<int> (1er d'abord ; départage 2e place serveur, §8.47)
  "is_ranked": false,   // bool — PUBLIC (§8.88, piège n° 9). Non classée ⇒ AUCUN ladder crédité (RP saisonnier).
  "is_private": false,  // bool — NOUVEAU §8.116, PUBLIC explicitement (piège n° 9). Partie issue d'un salon privé ⇒ le client masque REJOUER (salons éphémères)
  "attack_log": [ { "turn": 12, "round": 3, "attacker_id": 11, "defender_id": 12,   // NOUVEAU §8.121 — PUBLIC, cap 300 ; defender_id null = territoire NEUTRE
                    "kills": 2, "conquered": true, "hero_kill": false,
                    "pact_broken": false } ],                                       // 8ᵉ clé §8.123 — ⚠️ ABSENT des diffusions d'état (voir §8.121)
  "pacts": [ { "id": 3, "a_id": 11, "b_id": 12, "proposed_by": 11, "status": "broken",  // NOUVEAU §8.123 — PUBLIC, cap 50
               "created_round": 3, "expires_at_round": 5, "ended_round": 4, "broken_by": 11 } ], // redaction LEVÉE en fin de partie
  "match_rewards": { "11": { "xp_earned": 372, "coins_earned": 100,        // { "<player_id:str>": MatchRewards } — gains (§8.47 ; « points de match » RETIRÉS, §8.112)
    "level_up_triggered": true, "new_level": 12, "current_xp": 300, "xp_to_next_level": 100, "levels_gained": 2 } } } // ⚠️ toutes valeurs ENTIÈRES (piège float §5)
{ "type": "spy_result", "target_player_id": 12, "description": "Conquérir l'Asie" } // PRIVÉ (espion seul)
// PACTES DE NON-AGRESSION (§8.123) — messages PRIVÉS, envoyés aux DEUX joueurs concernés UNIQUEMENT
// (patron spy_result) : savoir qui négocie avec qui est déjà une information de jeu. Une ACCEPTATION,
// elle, n'a pas de message privé — elle est PUBLIQUE (évènement `pact_active`, voir §D).
{ "type": "pact_offer", "pact_id": 3, "proposer_id": 11, "target_id": 12,
  "created_round": 3, "duration_rounds": 2 }                                     // ints
{ "type": "pact_response", "pact_id": 3, "accept": false, "proposer_id": 11, "target_id": 12 }
{ "type": "chat_message", "tab": "general", "sender_id": 11, "sender_name": "Hakim",
  "text": "gg", "target_id": 12 }   // tab: "general"|"private" ; target_id: int (privé uniquement)
```

**C. `GameState` (objet `state` diffusé)** (cf. `state_schemas.py` ; **rédigé par destinataire** : `objectives` des autres = marqueur générique)
```jsonc
{
  "room_id": 11,                  // int
  "current_turn": 4,              // int
  "current_player_id": 11,        // int (⚠️ str(int()) pour indexer players)
  "phase": 3,                     // int — 0..5
  "stage": "playing",             // string — "initiative" | "placement" | "playing"
  "turn_order": [11, 12, 13],     // Array<int>
  "setup_index": 0,               // int
  "initiative_rolls": { "11": [6, 4, 2] },     // { "<player_id:str>": Array<int> }
  "winner_id": null,              // int | null  (null tant que la partie continue)
  "objectives": { "11": { "type": "string", "params": {}, "description": "string" } }, // { "<pid:str>": {...} }
  "players": {                    // { "<player_id:str>": PlayerState }
    "11": {
      "player_id": 11,            // int
      "username": "Hakim",        // string  ("" si non résolu)
      "faction": "culte_isotope", // string  (id de faction, miroir factions.py)
      "units_in_stock": 5,        // int
      "status": "alive",          // string — "alive" | "eliminated"
      "is_active": true,          // bool — false = a abandonné (Fallen Empire §8.20)
      "cards_in_hand": [3, 7],    // Array<int> (valeurs de troupes)
      "pending_eclipse_choice": [4, 9],   // Array<int> (vide = pas de choix Éclipse en cours)
      "pending_spy_choice": false,        // bool
      "pending_blind_deploy": {}          // { "<territory_id:str>": int } — ⚠️ MASQUÉ ({}) en stage "placement"
    }
  },
  "territories": {                // { "<territory_id:str>": TerritoryState }
    "alaska": {
      "territory_id": "alaska",   // string (id Risk snake_case = nom de nœud)
      "owner_id": 11,             // int | null (null = neutre)
      "garrison": 3               // int
    }
  },
  "contamination_zone": {         // dictionnaire imbriqué (§8.27)
    "territories": ["alaska", "kamchatka"], // Array<string> (ids de territoires contaminés)
    "probability": 1.0            // float
  },
  "pacts": [                      // PACTES DE NON-AGRESSION (§8.123) — ⚠️ REDACTÉ PAR DESTINATAIRE
    { "id": 3,                    // int — 1-based
      "a_id": 11,                 // int — le PROPOSANT (sens conservé)
      "b_id": 12,                 // int — le destinataire
      "proposed_by": 11,          // int
      "status": "active",         // string — "pending"|"active"|"broken"|"declined"|"expired"
      "created_round": 3,         // int — round GLOBAL de l'offre
      "expires_at_round": 5,      // int — acceptation + 2 (0 tant que pending)
      "ended_round": 0,           // int — round de la FIN (rupture/refus/expiration ; 0 sinon)
      "broken_by": null }         // int | null — le TRAÎTRE (status == "broken")
  ],                              // active/broken/expired = PUBLICS ; pending/declined = les 2 concernés SEULEMENT
  "statistics": {                 // « Mémoire Tactique » (§8.35) — PUBLIC, JAMAIS rédigé
    "zone_kills_by_player": { "11": 15, "12": 3 }, // { "<player_id:str>": int } (⚠️ clés str, valeurs float→int())
    "zone_stagnation_turns": 2,   // int — rounds globaux consécutifs sans déplacement de zone
    // --- Compteurs d'ÉCONOMIE (§8.47) — alimentent points & XP de fin de partie ET l'Intel ---
    "combat_kills_by_player": { "11": 120 },         // { "<pid:str>": int } — unités tuées AU COMBAT (≠ zone)
    "conquests_by_player": { "11": 18 },             // { "<pid:str>": int } — territoires conquis (cumul partie)
    "eliminations_by_player": { "11": 2 },           // { "<pid:str>": int } — joueurs éliminés par lui
    "continents_conquered_by_player": { "11": ["asia", "oceania"] } // { "<pid:str>": Array<string> } — continents pris ≥1 fois (count = .size())
  }
}
```

**D. `event` (clé discriminante : `event_type` — string)** — exemples des types les plus consommés
```jsonc
{ "event_type": "attack_result", "attacker_territory_id": "alaska", "defender_territory_id": "kamchatka",
  "attacker_player_id": 11, "defender_player_id": 12,   // ADDITIFS §8.85 — int ; defender = null si NEUTRE
  "attacker_rolls": [6,4], "defender_rolls": [5], "attacker_losses": 0, "defender_losses": 1, // Array<int>/int
  "conquered": true, "conquer_pending": true, "conquer_from": "alaska", "conquer_to": "kamchatka",
  "conquer_min": 1, "conquer_max": 2, "time_bank_bonus_seconds": 10 }   // ints / bools / strings
{ "event_type": "blind_deploy_submitted", "ready_count": 2, "expected_count": 3, "setup_complete": false }
{ "event_type": "blind_deploy_resolved", "forced": false }
{ "event_type": "turn_timeout", "player_id": 11 }     // player_id: int
{ "event_type": "units_deployed", "amount": 5, "deployments": { "alaska": 3, "brazil": 2 } } // deployments: { "<tid:str>": int }
{ "event_type": "card_played", "card_value": 7 }      // int
// PACTES (§8.123). L'offre et le REFUS sont diffusés SANS AUCUNE IDENTITÉ (la part nominative part
// en message PRIVÉ, voir §B) ; l'ACCEPTATION est publique — c'est tout l'intérêt du dispositif.
{ "event_type": "pact_offer" }                        // aucun autre champ : « une offre a eu lieu »
{ "event_type": "pact_response" }                     // idem — jamais « X a refusé Y »
{ "event_type": "pact_active", "pact_id": 3, "a_id": 11, "b_id": 12,
  "proposed_by": 11, "expires_at_round": 5 }          // PUBLIC (ints)
// La RUPTURE et l'EXPIRATION voyagent en `system_events` (codes `pact_broken` / `pact_expired`),
// respectivement sur `attack_result` (qui gagne aussi `"pact_broken": bool`) et `turn_passed`.
```

**E. WebSocket — actions client → serveur** (enveloppe standard `{ "action": string, "payload": object }`)
```jsonc
{ "action": "deploy_units", "payload": { "deployments": { "alaska": 2, "brazil": 1 } } } // { "<tid:str>": int }
{ "action": "attack_territory", "payload": { "attacker_territory_id": "alaska",
    "defender_territory_id": "kamchatka", "attacker_dice": 3 } }   // strings + int
{ "action": "move_units", "payload": { "source_territory_id": "alaska",
    "target_territory_id": "brazil", "amount": 2 } }
{ "action": "conquer_move", "payload": { "from_tid": "alaska", "to_tid": "kamchatka", "troops": 2 } }
{ "action": "play_card",   "payload": { "card_index": 0 } }       // int
{ "action": "keep_card",   "payload": { "card_index": 1 } }       // int (Ordre de l'Éclipse §8.24)
{ "action": "spy_objective", "payload": { "target_player_id": 12 } } // int (Chasseurs d'Ombres §8.24)
{ "action": "faction_choice", "payload": { "faction_id": "culte_isotope" } } // string — REFUSÉ (erreur privée) une fois la Phase 0 lancée (G2 durci)
{ "action": "get_draft", "payload": {} }                          // resync draft → réponse PRIVÉE draft_state (G2 durci)
{ "action": "abandon", "payload": {} }                            // payload vide
{ "action": "pass_turn", "payload": {} }
// PACTES DE NON-AGRESSION (§8.123) — `pact_offer` = action de MON tour (phases 1-4, pipeline standard) ;
// `pact_respond` = HORS TOUR, pré-routée AVANT la vérification de tour (voir §8.123). Refus zéro-4xx
// avec `reason` ∈ {not_your_turn, invalid_target, pair_busy, cap_reached, cooldown, final_protocol,
// not_pending, ranked_disabled} ; `cooldown` porte EN PLUS `remaining_rounds: int`.
{ "action": "pact_offer",   "payload": { "target_player_id": 12 } }   // int
{ "action": "pact_respond", "payload": { "pact_id": 3, "accept": true } } // int + bool
// IDEMPOTENCE / ANTI-REJEU (correctif « double déduction de PV ») — PUBLIC, OPTIONNEL : le client PEUT
// joindre à TOUTE action de jeu un champ `action_id` (string UNIQUE par action VOULUE, ex.
// "<nonce_session>-<seq>"). Ex. { "action": "attack_territory", "payload": { …, "action_id": "1752505600-9931-7" } }.
// Le serveur REJETTE (erreur privée « Action déjà traitée (doublon ignoré). ») tout message dont
// l'action_id figure dans la FENÊTRE des derniers ids déjà résolus pour ce joueur → une attaque rejouée
// (retransmission WS, rejeu à la reconnexion, 2ᵉ socket) ne re-résout JAMAIS le duel des héros (sinon les
// PV du défenseur baissaient « une 2ᵉ fois »), même si le rejeu arrive APRÈS une action intercalée. Deux
// actions DISTINCTES portent des id différents → toutes deux traitées (assauts répétés légaux, §8.79).
// Absent OU `null` (ancien client) → aucune dédup. Fenêtre serveur `PlayerState.recent_action_ids`
// (plafonnée) = INTERNE : jamais diffusée (retirée de l'état par router._state_payload).
// ⚠️ SUPPRIMÉ §8.116 : Lobby { "action": "ready" | "unready" | "get_lobby", "payload": {} } — plus aucun système « prêt »
{ "action": "get_salon", "payload": {} }   // NOUVEAU §8.116 — salon privé : resync → réponse individuelle salon_state (voir §B)
// CHAT (§8.33) — forme À PLAT acceptée (contrat principal) OU enveloppe standard :
{ "type": "send_chat_message", "tab": "general", "text": "gg", "target_id": 12 } // tab: "general"|"private"; target_id requis si "private"
```

**G. REST — Matchmaking : files d'attente publique/classée — §8.116** (cf. `api/v1/endpoints/matchmaking.py`, `models/schemas.py` : `QueueJoinRequest/Response`, `QueueStatusResponse`, `QueueLeaveResponse`)
```jsonc
// POST /api/v1/matchmaking/queue — corps CLASSÉE :
{ "queue": "ranked" }                                              // queue: "ranked"
// corps PUBLIQUE :
{ "queue": "casual", "map_id": "classic_42", "mode_players": 4 }    // queue: "casual" ; map_id: string ; mode_players: int
// réponses (200 systématique — convention zéro 4xx nominal §8.112) :
{ "queued": false, "reason": "banned", "banned_until_epoch": 1753500000.0 }  // sanction anti-bruteforce active (§H) — le ban de recherche de code bloque AUSSI la mise en file
{ "queued": false, "reason": "in_room", "room_id": 42 }             // déjà membre d'une salle waiting/in_progress — room_id: int (transport)
{ "queued": true, "already": true, "state": "searching" }          // idempotent — déjà en file
{ "queued": true, "state": "searching" }                            // nominal — ticket créé
// 400 { "detail": "Parametres de file invalides" } — queue hors {ranked,casual}, ou map_id/mode_players hors bornes de la carte (map_data.MAPS)

// GET /api/v1/matchmaking/status — heartbeat : rafraîchit le TTL du ticket (MM_HEARTBEAT_TTL_S = 15 s) à CHAQUE appel ; le client polle toutes les MM_STATUS_POLL_S = 2 s
{ "state": "idle",                  // string — "idle" | "searching" | "extending" | "starting" | "ready" | "in_game"
  "since_s": 12,                    // int — ancienneté du ticket (0 si idle/in_game)
  "room_id": null }                 // int | null — renseigné UNIQUEMENT pour "ready" / "in_game"
// extending = ticket en file depuis ≥ MM_SEARCH_EXTEND_S (30 s, purement un état d'AFFICHAGE, la file ne change pas)
// in_game = pas de ticket mais membership sur une room in_progress (reconnexion / reprise au boot)

// DELETE /api/v1/matchmaking/queue
{ "left": true }                                  // ticket searching/extending → retiré
{ "left": false, "reason": "assigned" }            // ticket starting/ready → désistement REFUSÉ (le client affiche MM_TOO_LATE et laisse la séquence continuer)
{ "left": false, "reason": "not_queued" }          // pas de ticket
```
> Machine à états du ticket (par joueur, Redis) : `idle → searching (0-30 s) → extending (30-60 s) → starting → ready {room_id} → in_game`. Buckets FIFO (ZSET, membre = user_id, score = epoch d'entrée) : `mm:q:ranked` (effectif `RANKED_PLAYER_COUNT`=5, `classic_42` FORCÉE) et `mm:q:casual:{map_id}:{n}` (bornes de la carte). Formation d'une salle : dès que le bucket atteint l'effectif `n` (0 bot), OU dès que le ticket de TÊTE de file a `MM_QUEUE_BOT_FILL_S` (60 s) d'ancienneté (bots pour les places manquantes). Une salle formée n'est **plus jamais rejoignable** (aucune liste, aucun id exposé — décision produit n°2).

**H. REST — Salons privés (code à 5 caractères) — §8.116** (cf. `api/v1/endpoints/matchmaking.py`, `models/schemas.py` : `PrivateCreateRequest/Response`, `PrivateJoinRequest/Response`, `PrivateLeaveResponse`, `PrivateStartResponse`)
```jsonc
// POST /api/v1/private/rooms (créer) — corps : { "map_id": "classic_42", "mode_players": 4 }
{ "created": true, "code": "K7RD2", "room_id": 17, "max_players": 4 }   // code: string(5) — alphabet ABCDEFGHJKMNPQRSTUVWXYZ23456789 (sans I/L/O/0/1), généré par `secrets` (jamais random)
{ "created": false, "reason": "banned", "banned_until_epoch": 1753500000.0 }
{ "created": false, "reason": "in_room", "room_id": 42 }
// 400 { "detail": "Parametres de salon invalides" } — JAMAIS de salon classé (is_ranked toujours false ici)

// POST /api/v1/private/join — corps : { "code": "k7rd2 " }   // le SERVEUR normalise strip+upper, le client peut envoyer brut
{ "joined": true, "room_id": 17, "max_players": 4 }
{ "joined": true, "already": true, "room_id": 17, "max_players": 4 }     // idempotent (double-clic)
{ "joined": false, "reason": "unavailable",                              // RAISON UNIFIÉE : code inexistant ET salon plein/démarré rendent EXACTEMENT la même réponse — zéro oracle d'énumération (§9 sécurité)
  "failed_attempts": 2, "remaining_attempts": 3 }                        // ces 2 clés n'apparaissent qu'À PARTIR de la 2e erreur, sinon absentes
{ "joined": false, "reason": "banned", "banned_until_epoch": 1753500000.0, "ban_hours": 1 }
{ "joined": false, "reason": "busy" }                                    // déjà en file ou dans une salle active — NE COMPTE PAS comme erreur

// DELETE /api/v1/private/rooms/leave
{ "left": true, "closed": true }    // appelant = créateur → ferme le salon (broadcast WS salon_closed, salle + code détruits)
{ "left": true }                    // membre simple (salon détruit si devenu vide)
{ "left": false }                   // appelant pas membre

// POST /api/v1/private/rooms/start (créateur uniquement, salon waiting, ≥ 1 humain) — complète avec des bots et lance
{ "started": true }
{ "started": false, "reason": "not_creator" }
{ "started": false, "reason": "not_waiting" }
```
> **Politique de sanctions — ce que le client voit (§9 sécurité, détail complet en §8.116 du journal).** Une tentative sur un code inexistant OU pointant vers un salon complet/démarré compte comme une « erreur de recherche » (`banned`/`busy` ne comptent JAMAIS). Quota `MM_FAIL_LIMIT` = 5 erreurs par fenêtre `MM_FAIL_WINDOW_S` = 1 h ; dès la 2ᵉ erreur, `remaining_attempts` avertit gentiment ; à la 6ᵉ, sanction posée (ban `MM_BAN_SHORT_S` = 1 h pour les 2 premiers bans, `MM_BAN_LONG_S` = 24 h à partir du 3ᵉ — `MM_BANS_BEFORE_LONG` = 2) et la réponse devient `banned`. Le client ne reçoit JAMAIS : le quota exact restant avant la 2ᵉ erreur, l'historique des bans, ni la distinction inexistant/plein — uniquement l'avertissement au bon moment et l'échéance du ban.

---

## 📡 5. ARCHITECTURE RÉSEAU (Backend / Frontend)

- **Authentification — « SIGN IN THROUGH STEAM » (OpenID 2.0), SEUL moyen de connexion (§8.113).** `POST /auth/register` et `POST /auth/login` **N'EXISTENT PLUS** (404) : il n'y a plus ni mot de passe, ni email, ni inscription. Le jeu n'étant pas encore distribué par le client Steam, la connexion passe par le **navigateur externe** du joueur (flux OpenID) et non par le SDK Steamworks — l'architecture reste prête à accueillir plus tard une route de validation de **tickets Steamworks** À CÔTÉ de celle-ci. Godot ne pouvant pas recevoir la redirection de retour, il **interroge** le backend (polling) : une « session de login » en Redis fait le pont.
  - **`POST /api/v1/auth/steam/session`** — sans auth, sans corps → `200 {"session_id": "<token_urlsafe(32)>"}`. Écrit `steam_login:{session_id} = "pending"` en Redis, **TTL 600 s**.
  - **`GET /api/v1/auth/steam/login?session_id=…`** — session inconnue → `404 {"detail": …}` ; sinon **302** vers `https://steamcommunity.com/openid/login` (`openid.ns`/`mode=checkid_setup`/`claimed_id`+`identity=identifier_select`/`return_to={PUBLIC_API_URL}/api/v1/auth/steam/return?session_id=…`/`realm={PUBLIC_API_URL}`). C'est l'URL passée à `OS.shell_open` côté client.
  - **`GET /api/v1/auth/steam/return`** — callback appelé par le NAVIGATEUR. Réponse = **page HTML** statique (succès/erreur), jamais du JSON : le destinataire est un navigateur. Contrôles dans un ordre STRICT, tout échec = refus SANS émission de JWT (§9 sécurité) : (1) session `"pending"` **consommée atomiquement** (`SET … GET` → sentinelle `"checking"`, usage unique) ; (2) `openid.mode == "id_res"` ; (3) `openid.return_to` préfixé par `{PUBLIC_API_URL}/api/v1/auth/steam/return` ; (4) **`check_authentication` serveur→Steam OBLIGATOIRE** (re-POST de tous les `openid.*` avec `mode=check_authentication`, réponse devant porter `is_valid:true`) ; (5) SteamID64 extrait du regex STRICT `^https://steamcommunity\.com/openid/id/(\d{17})$` ; (6) upsert du compte par `steam_id` + JWT déposé en Redis (**TTL 300 s**).
  - **`GET /api/v1/auth/steam/poll?session_id=…`** — interrogé toutes les **2 s** par le client (rebours global **180 s**). `200 {"status":"pending"}` (y compris pendant la vérification serveur→Steam) · `200 {"access_token": …, "token_type":"bearer"}` **une seule fois**, la clé est détruite à la lecture · `404 {"detail": …}` = session inconnue, expirée, échouée ou déjà servie (le client abandonne aussitôt). Statut **200** et non 202 pour le cas « pending » : le parseur GDScript reste trivial.
  - **Le JWT est INCHANGÉ** (§3 de la migration) : même secret `SECRET_KEY_FASTAPI`, même **HS256**, même claim **`sub` = `username`**, même TTL `ACCESS_TOKEN_EXPIRE_MINUTES`. Tout ce qui le consomme est donc intact : `get_current_user`, `GET /auth/me`, le **handshake WebSocket `?token=`**, et la **session persistée** `user://session.dat` (reconnexion silencieuse au boot).
  - **Avatar (§8.114)** : `GET /auth/me` expose `steam_avatar_url` (chaîne, `""` = inconnu). Rafraîchi à **CHAQUE** connexion (le persona name, lui, reste figé — voir ci-dessous), et **validé côté serveur** avant stockage : https obligatoire, hôte en `.steamstatic.com`/`.akamaihd.net`, longueur bornée. Exposé UNIQUEMENT dans le profil privé de l'appelant — jamais dans `PublicProfileResponse` ni `LeaderboardEntry`.
  - **Compte** : l'identité est le **SteamID64** (`users.steam_id`, UNIQUE) — un même SteamID retrouve TOUJOURS le même compte et sa progression. Le `username` (= claim `sub`) est le **persona name Steam** assaini (contrôles retirés, 24 car. max) avec anti-collision `_<4 derniers chiffres>` puis `_2`, `_3`… ; repli **`Vagabond_<6 derniers chiffres>`** si `STEAM_API_KEY` est absente ou si GetPlayerSummaries échoue — **le login n'échoue JAMAIS pour cette raison**. `email`/`hashed_password` sont désormais **NULL** (colonnes conservées et devenues nullables). Le persona name n'est PAS resynchronisé aux connexions suivantes.
  - **Variables `.env` (NOUVELLES)** : `PUBLIC_API_URL` (realm + return_to ; URL publique de l'API, jamais un nom de service Docker) et `STEAM_API_KEY` (**optionnelle**, persona name uniquement). Rate limiting : les routes restant sous `/api/v1/auth/…`, le limiteur `RL_AUTH_*` de Traefik s'applique déjà — **rien à changer côté infra ni docker-compose**.
  - **Historique (§8.46, toujours valable)** : (a) la **durée de vie du JWT** est lue depuis la config (`settings.ACCESS_TOKEN_EXPIRE_MINUTES`, défaut **1440** surchargeable via `.env`) — fin du plafond figé à 30 min codé en dur ; (b) l'**hôte des URL** (HTTP et WS) provient de l'autoload **`ApiConfig`** (`api_config.gd`, source unique `http_host`/`ws_host`, bascule dev/prod sans recompiler). *(L'encodage `.uri_encode()` du corps de login n'a plus d'objet : il n'y a plus de formulaire.)*
- **Déconnexion (client, §8.52 frontend) :** l'action **« DÉCONNEXION »** vit DÉSORMAIS dans l'écran **Paramètres** (`settings.gd`) et non plus dans le lobby. Elle (1) ferme le WebSocket s'il est ouvert (`socket.close()` + `connected=false` + `current_room_id=""`), (2) **purge la session** via `AuthManager.clear_session()` (`jwt_token`/`user_id`/`username` en mémoire **+** le fichier `user://session.dat` de la persistance §P1), puis (3) renvoie à `auth_screen`. **Aucun impact protocole** : pas de nouvel endpoint ni message WS — c'est une fermeture WS côté client + purge locale du JWT. Le lobby ne propose plus qu'un **« ❮ RETOUR »** vers `main_menu` (cf. [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md) §8.52).
- **Erreurs REST (enveloppe standard) :** toute réponse d'erreur HTTP renvoie un **JSON** `{"detail": <string>}` — **jamais** de texte brut. Les `HTTPException` métier le font nativement : `steam/login` et `steam/poll` **404** `{"detail":"Session inconnue ou expirée"}` (§8.113) ; routes authentifiées **401** `{"detail":"Could not validate credentials"}` ; lobby **400** `{"detail":"Room is full"}`. **UNIQUE EXCEPTION assumée : `GET /auth/steam/return`**, qui répond une **page HTML** — son destinataire est le navigateur du joueur, pas le client Godot (lequel n'apprend l'issue que par `steam/poll`). Cette page est **statique et sans aucune interpolation** de la requête (zéro XSS par construction) et son message d'erreur est **générique** : un attaquant ne doit pas apprendre LEQUEL des contrôles a échoué. **Depuis l'ajout d'un handler global** (`main.py`, `@app.exception_handler(Exception)`), même une exception serveur **non gérée** renvoie un **`500 {"detail":"Internal server error"}` JSON** (et logue la stack côté serveur) — fin de l'« Internal Server Error » en **texte brut** qui faisait échouer `JSON.parse` côté Godot (« got 'Internal' », cf. §8.47). **Côté client :** lire `data.get("detail")` pour le message ; ne **jamais** supposer qu'un corps 4xx/5xx est non-JSON.
- **Classement mondial (public) :** `GET /api/v1/leaderboard?limit=N` (`leaderboard.py`, §8.46) — **aucune authentification** requise (cohérent avec `GET /lobby/rooms`). Tri par `points_classement` **décroissant**, départage par `stats_victoires` **décroissant**. Réponse = `List[LeaderboardEntry]` (schéma annoté en §F ci-dessus). Côté client : `NetworkManager.fetch_leaderboard()` + signal `leaderboard_loaded(entries)` ; `leaderboard.gd` consomme les vraies données (repli mock gracieux si le serveur répond 404 tant que le VPS n'est pas redéployé). ⚠️ **Forme livrée ≠ contrat §9.2** (qui demande un tri par victoires, une enveloppe `{entries, me}` et un `offset`) — **à réconcilier** (cf. §9.2).
- **Matchmaking — files d'attente serveur-autoritaire + salons privés à code (§8.116, ACTUEL).** Le joueur n'entre plus jamais un ID/liste de salle : il rejoint une **file FIFO** (publique par carte+effectif, ou classée unique) via `POST/GET/DELETE /api/v1/matchmaking/queue|status`, ou un **salon privé à code de 5 caractères** via `POST/DELETE /api/v1/private/rooms|join|rooms/leave|rooms/start`. Schémas jsonc complets : **§G** (files) et **§H** (salons) ci-dessus. Machine d'état du ticket, buckets Redis, sanctions anti-bruteforce : détail complet en **§8.116** du journal ci-dessous. `POST /game/rooms/{room_id}/start` (backdoor de démarrage alternatif) est **SUPPRIMÉ**.
- **Matchmaking — BLOC HISTORIQUE, SUPERSÉDÉ EN INTÉGRALITÉ PAR §8.116 ci-dessus.** ⚠️ Le système ci-dessous (« liste de salles / scan / rejoindre par ID ») **N'EXISTE PLUS** (`api/v1/endpoints/lobby.py` supprimé). Conservé pour l'historique : ~~Requêtes HTTP REST sur `/lobby/rooms` (préfixe `/api/v1/lobby`) pour lister/créer/rejoindre.~~
  - `GET /lobby/rooms` : liste les salles **réellement joignables** = `status == "waiting"` **ET non pleines** (joueurs actuels `<` `max_players`, filtré serveur §8.31). Chaque salle expose désormais **`current_players: int`** (occupation courante, §8.34) → la jauge « joueurs/max » du radar affiche un vrai compteur (fin du repli `—/max`). Le client (`fetch_rooms`) envoie un header **`Cache-Control: no-cache`** pour que le bouton « Actualiser » ne serve jamais une liste périmée.
    - **🖥️ Note FRONTEND (§8.57) :** depuis que le **mode de jeu est choisi au Menu Principal** (autoload `MatchConfig`, effectif 3-6), le client **filtre le radar CÔTÉ CLIENT** pour n'afficher que les salles dont `max_players` **==** l'effectif du mode (la création de salle utilise le même effectif hérité). **Aucun paramètre de requête de capacité n'existe** dans ce contrat — et il n'en est **pas inventé** (règle « interdiction de deviner »). *Piste backend optionnelle (différée) : exposer un `GET /lobby/rooms?max_players=N` permettrait un **filtrage serveur** (moins de trafic, salles plus fraîches) ; à ajouter **Backend-first ici** puis à consommer côté client (`fetch_rooms`).*
  - `POST /lobby/rooms` : crée une salle. Le serveur **borne `max_players` entre 3 et 6** (`max(3, min(6, ...))`) et auto-inscrit le créateur via un `GameRoomPlayer`.
  - `POST /lobby/rooms/{room_id}/join` : refuse si la salle n'est pas `waiting` (404), si le joueur y est déjà (400), ou **si la salle est pleine** (400 « Room is full », via comparaison `count(GameRoomPlayer) >= room.max_players`).
  - `DELETE /lobby/rooms/{room_id}/leave` : retire le joueur ; supprime la salle si elle devient vide.
  - ⚠️ **PIÈGE GODOT (IDs) :** `JSON.parse_string` convertit **tous les nombres en `float`**. Un `id` de salle lu d'une réponse REST vaut donc `11.0`, et `str(11.0)` produit `"11.0"`. Comme `ConnectionManager` indexe les salles WebSocket par cette **chaîne**, ouvrir `"11.0"` crée une salle DISTINCTE de `"11"` (créateur isolé des autres joueurs). **Règle :** toujours convertir un id JSON via `int(...)` avant de le `str()`/l'utiliser dans une URL WS (appliqué dans `network_manager.gd` ; `lobby_screen.gd` a disparu §8.116, la règle reste valable pour le `room_id` de transport rendu par le matchmaking/salon).
- **Temps Réel (Arène) :** Géré par `NetworkManager.gd`. Connexion au `ConnectionManager` Python en WebSocket (`wss://.../ws/{room_id}/{player_id}?client_version=<v>&token=<jwt>`, où `player_id` = `User.id` récupéré via `/auth/me`) — le JWT passe par la **query string `token`** (les en-têtes du handshake ne sont pas fiables selon les plateformes WebSocket ; l'en-tête `Authorization` est encore envoyé par compat mais **n'est pas lu**). L'état du jeu est synchronisé via JSON.
  - ⚠️ **Validation de version stricte (auto-updater §9) :** la query string `client_version` (= `GameState.client_version`, posé par le bootloader) est comparée par le serveur à `version.json`. Si elle **diffère**, le WS **rejette** la connexion : `accept()` puis `close(code=4000, reason="Version obsolete …")`. Le client lit `socket.get_close_code() == 4000` et émet un `game_error`/`lobby_error` clair. *(Détails bootloader/patchs : voir [`PIPELINE_ET_BOOTLOADER.md`](PIPELINE_ET_BOOTLOADER.md) §9.)*
  - 🔒 **Handshake AUTHENTIFIÉ (ULTRAREVIEW C2 — lot M1, 2026-07-14).** Après le contrôle de version, le serveur **exige un JWT valide** dans la query `?token=` : il le décode (même secret/algorithme que l'auth REST), résout l'utilisateur par `sub` (username) et **DÉRIVE `pid` de cet utilisateur vérifié** — le `{player_id}` du path n'est plus une source d'identité (s'il diffère du token → rejet). Puis il vérifie la **membership** (`GameRoomPlayer` de la salle) **AVANT** `manager.connect` : un non-membre ne reçoit jamais l'état (même redacté). **Codes de fermeture applicatifs :** `4000` = version obsolète ; `4001` = token absent/invalide/expiré, utilisateur inconnu, path incohérent ou paramètres non numériques ; `4003` = utilisateur authentifié mais **pas membre** de la salle. Fail-closed : toute panne DB pendant l'auth/membership refuse la connexion. Côté client, `network_manager.gd` ajoute `&token=` (jamais journalisé) et affiche la raison des closes 4001/4003 via `game_error`/`lobby_error`. Couverture : `backend/test_security_locks.py`.
  - **Messages serveur→client :** `{"type":"action_result","event":...,"state":...}`, `{"type":"error","message":...,"reason":... (ADDITIF §8.119 — code machine du refus, présent uniquement pour les refus CODÉS comme `hero_ability` ; sinon absent)}`, `{"type":"player_disconnected","player_id":...}`, ~~`{"type":"lobby_state","players":[...],"ready":[...]}`~~ (SUPPRIMÉ §8.116, remplacé par `salon_state`/`salon_closed` — salon privé uniquement, voir §8.116 et §B), `{"type":"game_started","state":...}`, `{"type":"game_over","winner_id":...,"match_type":...,"rankings":[...],"is_private":...}` (**`is_private`** NOUVEAU champ PUBLIC §8.116 — masque REJOUER côté client si la partie venait d'un salon), `{"type":"player_abandoned","player_id":...,"state":...}` (Fallen Empire §8.20 — l'état diffusé porte le `is_active=false` du joueur), `{"type":"spy_result","target_player_id":...,"description":...}` (Chasseurs d'Ombres §8.24 — message **PRIVÉ**, envoyé uniquement à l'espion, jamais diffusé). **Chat (§8.33) :** `{"type":"chat_message","tab":"general"|"private","sender_id":...,"sender_name":...,"text":...,"target_id":... (privé uniquement)}` — relais serveur **estampillé** (id + pseudo réel de l'expéditeur, pas d'usurpation) ; en **général** diffusé à toute la salle (écho compris), en **privé** envoyé **uniquement à la cible + écho à l'expéditeur**. Le client les route via les signaux `game_state_updated` / `game_event` / `game_error` / `lobby_state_updated` / `game_started_signal` / `player_abandoned` / `spy_result`. La victoire est aussi portée par `GameState.winner_id` dans l'état diffusé ; `game_over` déclenche en plus l'enregistrement des résultats (`process_match_results`). NB : certains évènements portent un champ `system_messages: [str]` (lignes de journal diffusées en BBCode, désormais en anglais invariant — ex. immunité de l'Isotope Covenant §8.24) **et son pendant structuré `system_events: [{code, params}]`** que le client traduit localement (§8.104).
  - **Confidentialité des objectifs secrets — State Redaction par destinataire (§4.4 / §8.6 résolu).** L'état complet n'est **JAMAIS** diffusé tel quel : chaque message porteur d'un `state` (`game_started`, `action_result`, `player_abandoned`) passe par **`ConnectionManager.broadcast_state_to_room`**, qui **itère sur `manager.players[room_id]`** (`{ player_id: websocket }`) et envoie à CHAQUE joueur une copie **personnalisée** via `connection.send_json(...)`. La redaction (`connection_manager._redact_state_for_player`, **deepcopy** → l'état Redis source et les autres copies ne sont jamais mutés) **conserve uniquement `state.objectives[player_id]`** (l'objectif du destinataire) et **écrase ceux de tous les autres** par un marqueur générique `{"type":"hidden","description":"Objectif classifié"}`. L'état initial envoyé à un joueur qui (re)joint (`router._send_current_state`) est redacted **de la même façon**. ⚠️ **Inconditionnel, même après un espionnage** : les Chasseurs d'Ombres (§8.24) reçoivent l'objectif d'une cible via le message **PRIVÉ** `spy_result`, mais l'état global **ne re-divulgue jamais** ce secret (l'espion l'a déjà mémorisé côté client). Les messages **sans état sensible** (`lobby_state`, `faction_locked`, `game_over`, `player_disconnected`) restent en diffusion identique (`broadcast_to_room`). Test : `backend/test_state_redaction.py`. (À ne pas confondre avec le masquage de `pending_blind_deploy` en Phase 0, qui est global et géré par `router._state_payload`, §8.31.)
  - **Actions client→serveur :** `{"action": <type>, "payload": {...}}`. Lobby (SUPPRIMÉ §8.116) : ~~`ready`, `unready`, `get_lobby`~~ — plus aucun système « prêt », voir §8.116. Salon privé (NOUVEAU §8.116) : `get_salon`. Draft : `faction_choice` (`payload.faction_id`). Jeu : `place_initial` (pré-game), `deploy_units`, `attack_territory`, `move_units`, `play_card` (`payload.card_index` — la valeur de la carte est créditée au stock à déployer, §8.4/§8.22), `conquer_move` (`payload = {from_tid, to_tid, troops}` — répartition des troupes après une conquête, §8.23), `keep_card` (`payload.card_index` — Ordre de l'Éclipse §8.24 : conserve l'une des 2 cartes proposées, état bloquant `pending_eclipse_choice`), **`hero_ability`** (`payload = {ability, target_territory_id?}` — **CAPACITÉS DE HÉROS §8.119** : dépense de PP pour RATIONNER (`ability:"ration"`, sans cible) ou pour le POUVOIR DE FACTION du trio pilote (`ability:"faction_power"`, cible requise pour BASTION/ABSOLUTION) — refus porteur d'un code `reason` traduisible), `pass_turn`. Hors-tour : `abandon` (payload vide — Fallen Empire, traité par `router.py` AVANT le moteur car autorisé même quand ce n'est pas son tour, voir §8.20 ; côté client, l'abandon **quitte immédiatement l'arène** vers `main_menu.tscn`, §8.23), `spy_objective` (`payload.target_player_id` — Chasseurs d'Ombres §8.24 : traité par `router.py`, renvoie un message **privé** `spy_result` à l'espion). **Chat (§8.33) :** `send_chat_message` — accepté **à plat** (`{"type":"send_chat_message","tab","text","target_id"}`, contrat principal) **OU** dans l'enveloppe standard (`{"action":"send_chat_message","payload":{...}}`). Traité par `router.py` **HORS verrou d'état** (ne mute aucun état de jeu). `tab` ∈ {`general`, `private`} — l'onglet « Alliés » est **abandonné** (jeu chacun-pour-soi) ; `target_id` **requis** si `tab == "private"`. Debug : `init_game`.
  - **Draft / sélection de faction (frontend + backend câblés, DURCI G2 2026-07-14) :** après `game_started`, chaque client est sur `faction_selection`. La confirmation appelle `NetworkManager.send_faction_choice(faction_id)` → message `{"action":"faction_choice","payload":{"faction_id":...}}`. Le serveur (`router.py:_handle_faction_choice`) applique la faction au `PlayerState` dans l'état Redis (source unique `_apply_faction_to_player` : faction + héros au niveau persisté + skin équipé) puis **rediffuse** `{"type":"faction_locked","player_id":...,"faction_id":...}` à toute la salle. **Resynchronisation (nouveau)** : les `faction_locked` des BOTS partent juste après `game_started`, pendant la transition de scène des clients → `faction_selection.gd` demande à son `_ready` la photographie complète via `get_draft` → réponse **PRIVÉE** `draft_state` (`{locked, draft_deadline_at}`, relayée par le signal `draft_state_received`). **Complétion** : le client bascule vers `main.tscn` quand tous les joueurs **ACTIFS** (`is_active`, abandons exclus — signal `player_abandoned` écouté) sont verrouillés — côté serveur, même règle (`_draft_complete`) pour armer la Phase 0 (`_begin_phase0` : minuterie 90 s + déploiement immédiat des bots, **sous le verrou de l'appelant** — l'ancien `submit_bot_blind_deploys` re-prenait le verrou → deadlock de salle). **Rebours de draft (nouveau)** : `DRAFT_TIMEOUT_S` (60 s, `.env`) — à l'échéance, le serveur verrouille D'OFFICE la faction provisoire (gratuite) des actifs non confirmés, diffuse leurs `faction_locked` et lance la Phase 0 ; `faction_choice` est **refusé** (erreur privée) une fois la Phase 0 lancée. Filet client : si `GameState.stage == "playing"` arrive alors que l'écran de draft est encore affiché, bascule inconditionnelle vers l'arène. Voir §8.13 (dans [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)).
  - **Salle d'attente & démarrage (Lot 2) — ⚠️ SUPERSÉDÉ PAR §8.116 (conservé pour l'historique) :** le `ConnectionManager` suit l'identité des joueurs par salle et leurs états "prêt". Quand tous les joueurs connectés sont prêts (3-6), le routeur WS appelle automatiquement `GameEngine.create_initial_state` et diffuse `game_started` avec l'état initial → tous les clients basculent vers l'arène. ~~L'endpoint REST `POST /game/rooms/{id}/start` existe aussi (chemin alternatif).~~ **`POST /api/v1/game/rooms/{room_id}/start` est SUPPRIMÉ (§8.116, backdoor de démarrage)** : `create_initial_state` n'est plus appelé QUE par `launch_room` (matchmaker ou `POST /private/rooms/start`, voir §8.116). Le système « tous prêts » lui-même n'existe plus (actions `ready`/`unready` supprimées, §E). L'état passe toujours par les stages `placement` puis `playing` (`GameState.stage`, INCHANGÉ).
  - **Destruction d'une salle vidée (déconnexion WS) :** `ConnectionManager.disconnect()` renvoie `True` quand la **dernière** connexion d'une salle se ferme. Le routeur appelle alors `_destroy_room()` qui supprime l'état de partie en Redis (`delete_game_state`) **et** la ligne `GameRoom` + ses `GameRoomPlayer` en base — mécanisme **INCHANGÉ et toujours actif**, désormais invoqué aussi par le matchmaker (échec de `launch_room`) et par le salon privé. *(⚠️ Historique : `GET /lobby/rooms` n'existe plus depuis §8.116 — plus aucune liste à « polluer ». Symétrique désormais de `DELETE /api/v1/private/rooms/leave` (créateur) qui détruit le salon devenu vide, et de `_close_salon` sur déconnexion du créateur — voir §8.116.)*

---

## 🧭 8. ÉTAT D'AVANCEMENT (MVP) & POINT DE REPRISE — *Journal : réseau & backend serveur*

> **DIRECTIVE IA :** Le journal §8 est **réparti par thème** entre les 4 fichiers (index dans [`CONTEXTE.md`](CONTEXTE.md)) ; **numéros d'origine conservés**. Vue d'ensemble du MVP : voir §8.1 dans [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md).
>
> **Entrées présentes dans CE fichier :** §8.9 (matchmaking), §8.12 (destruction salle vidée), §8.20 (Fallen Empire / abandon), §8.26 (déploiement en masse), §8.28 (pseudos réels), §8.31 (sprint matchmaking/déploiement aveugle/zone/timers), §8.33 (Time Bank + Chat), §8.34 (`current_players` dans le lobby), §8.35 (`GameState.statistics` / Mémoire Tactique — prép. Intel), §8.46 (liaison frontend↔backend : `ApiConfig` + session persistante + classement réel `/leaderboard`), §8.47 (**Économie globale : Points de Match, XP, Niveaux infinis, Coins**), §8.48 (anti double-avance), §8.61 (contrat héros RPG), §8.62 (minuterie par phase), §8.63 (chasse aux bugs moteur), **§8.64 (lot G6 — télémétrie d'équilibrage)**.

### 8.9. Correctifs Matchmaking (post-MVP)
> Bugs critiques du lobby diagnostiqués et corrigés. Détail des causes pour éviter les régressions.

1. **Limite de salle figée à 3 joueurs.**
   - *Cause A (frontend) :* `NetworkManager.create_room()` avait `max_players` codé en dur à `3` par défaut, et les boutons de création n'envoyaient aucune taille → toutes les salles naissaient à 3 places. *Fix :* défaut porté à `6` **et** sélecteur `SpinBox` (3-6) câblé dans `lobby_screen.gd` (la valeur choisie est transmise).
   - *Cause B (backend) :* la route `join` **ne vérifiait jamais la capacité** → `max_players` non respecté. *Fix :* ajout du contrôle `count(GameRoomPlayer) >= room.max_players` → 400 « Room is full ».
2. **Créateur isolé dans une salle « 11.0 ».** *Cause :* float JSON → `str(11.0) = "11.0"`, clé WebSocket distincte de `"11"` (voir piège §5). *Fix :* coercition `int()` de tous les ids de salle dans `lobby_screen.gd` (`_on_lobby_success`, liste publique) et `network_manager.gd` (`join_room`).
3. **Bouton « Actualiser » sans effet visuel.**
   - *Cause A :* `queue_free()` est différé (fin de frame) → anciens nœuds encore présents pendant le redessin (doublons/affichage figé). *Fix :* `remove_child()` immédiat avant `queue_free()` dans `_on_rooms_loaded`.
   - *Cause B :* réponse `GET /lobby/rooms` potentiellement mise en cache. *Fix :* header `Cache-Control: no-cache` (voir §5).
4. **Liste des salles figée pour les autres joueurs (pas de rafraîchissement « temps réel »).**
   - *Symptôme :* quand un joueur crée/quitte une salle, les autres joueurs déjà sur l'écran Lobby ne voyaient pas le changement tant qu'ils ne recliquaient pas « Actualiser ».
   - *Cause racine (architecturale, PAS un bug de code) :* le lobby est **100 % REST**. Le backend n'émet **aucun** push WebSocket à la création/jointure d'une salle, et un joueur qui parcourt le lobby **n'est connecté à aucun WebSocket** (la connexion WS `/ws/{room_id}/{player_id}` n'a lieu qu'*après* avoir rejoint une salle, dans `waiting_room`). La liste ne se redéclenchait donc que sur clic manuel ou à l'ouverture de l'écran (`_on_refresh_pressed` dans `_ready`). Le maillon rompu était **l'absence de tout redéclencheur automatique**, pas la réception/l'affichage (signal `rooms_loaded` + nettoyage `remove_child`/`queue_free` déjà corrects).
   - *Fix (frontend exclusif, `lobby_screen.gd`) :* ajout d'un `Timer` d'auto-rafraîchissement (`AUTO_REFRESH_INTERVAL = 3.0 s`, `autostart`) créé dans `_ready()` qui repolle `NetworkManager.fetch_rooms()` en silence (sans écraser le `status_label` du clic manuel ; `_on_rooms_loaded` met à jour le compteur). Le timer étant enfant de l'écran, il est **détruit automatiquement au changement de scène** → le polling s'arrête seul en quittant le lobby. **Backend non modifié** (un vrai push nécessiterait un canal WS lobby côté serveur — voir piste hors-MVP ci-dessous).
   - *Piste future (si push temps réel souhaité) :* ouvrir un WebSocket « lobby » global côté backend qui broadcast un message `rooms_update` à chaque create/join/leave, puis émettre un signal `rooms_updated` dans `network_manager.gd` — remplacerait le polling par du vrai push. **Nécessite une modification backend**, donc différé.

### 8.12. Destruction automatique d'une salle vidée (déconnexion WS)
> Besoin : quand **tous** les joueurs quittent une salle (fermeture du client / WebSocket), la salle doit être détruite et ne plus apparaître dans la liste publique.

- *Avant :* une déconnexion WS ne nettoyait que les structures in-memory du `ConnectionManager`. La ligne `GameRoom` en base (et l'état Redis si la partie avait démarré) **survivaient** → salle fantôme listée dans `GET /lobby/rooms`.
- *Fix (backend, 2 fichiers) :*
  - `connection_manager.py` : `disconnect()` renvoie désormais `bool` (`True` si la salle vient d'être entièrement vidée).
  - `sockets/router.py` : nouveau helper `_destroy_room(room_id)` (Redis `delete_game_state` + suppression `GameRoomPlayer`/`GameRoom` via `SessionLocal`, mêmes patterns que `_finalize_if_over`). Le handler `WebSocketDisconnect` appelle `_destroy_room` si `disconnect()` a renvoyé `True`, sinon diffuse `player_disconnected` + `lobby_state` comme avant.
- *Robustesse :* suppressions encapsulées dans des `try/except` (un échec Redis ou DB ne casse pas la fermeture du socket). ⚠️ **Backend → nécessite push + redéploiement VPS** pour être actif (§1).

### 8.20. Fallen Empire — Abandon de partie (Backend)
> Implémentation serveur du bouton « ☠ ABANDONNER » (§8.17) : le joueur qui envoie `{"action":"abandon","payload":{}}` devient un **Empire déchu** — marqué inactif, ses tours sont sautés, ses territoires restent sur la carte et se défendent automatiquement. **Backend exclusif** (⚠️ push + redéploiement VPS requis, §1/§8.7).

- **Schéma (`state_schemas.py`) :** nouveau champ `PlayerState.is_active: bool = Field(default=True)`. `False` = a abandonné. **Distinct de `status`** : un joueur abandonné reste `"alive"` tant que ses territoires tiennent (il peut encore être éliminé militairement) ; le défaut `True` garde les états Redis existants valides (rétro-compatible).
- **Routage (`sockets/router.py`) :** l'action `abandon` est interceptée **dans le routeur** (nouveau handler `_handle_abandon`, branché entre `faction_choice` et les actions de jeu) et **PAS via `GameEngine.process_action`** — car ce dernier exige « c'est votre tour », alors que l'abandon est autorisé à tout moment. Le handler : (1) refuse si déjà abandonné ou éliminé (erreur personnelle `{"type":"error",...}`), (2) passe `is_active=False`, (3) gère le stage courant (voir ci-dessous), (4) vérifie la victoire (`_check_victory`), (5) si c'était le tour du joueur et que la partie continue, force `engine._end_turn` (le tour passe au prochain joueur actif), (6) sauvegarde dans Redis, (7) diffuse `{"type":"player_abandoned","player_id":...,"state":...}` à toute la salle, (8) appelle `_finalize_if_over` (si l'abandon couronne le dernier actif → `game_over` + `process_match_results`).
- **Moteur (`engine.py`) — tours sautés :** `_end_turn` ne donne le tour qu'aux joueurs `status=="alive"` **ET** `is_active==True`. La boucle de recherche reste **bornée** (`for _ in range(len(player_ids))`) → jamais infinie ; s'il ne reste qu'un actif, c'est `_check_victory` qui clôt. Gardes complémentaires : `_calculate_reinforcements` renvoie 0 et `_draw_card_for_current_player` ne pioche pas pour un joueur inactif ; `process_action` refuse toute action d'un joueur inactif (« Vous avez abandonné la partie »).
- **Abandon pendant le `placement` (anti soft-lock) — ⚠️ MAJ §8.31 (déploiement aveugle) :** le stock du joueur ET son tampon `pending_blind_deploy` sont vidés ; si, lui retiré, **tous les joueurs actifs restants ont déjà soumis** leur déploiement aveugle, la Phase 0 est **résolue immédiatement** (`_all_blind_deploys_ready` → `_resolve_blind_deployment`). `_start_playing` donne le 1ᵉʳ tour au premier joueur **actif** de `turn_order`. *(Historique pré-§8.31 : placement séquentiel, `_all_stocks_empty`/`_advance_setup_index` sautaient les inactifs — ces helpers sont désormais legacy.)* **Déclenché aussi automatiquement sur déconnexion brutale** (Alt+F4/crash) en partie en cours (§8.31).
- **Victoire « Last Man Standing » (`_check_victory`) :** les prétendants sont les joueurs vivants **ET actifs** (`contenders`). S'il n'en reste **qu'un, il gagne automatiquement** (tous les autres éliminés OU abandonnés). Les objectifs secrets ne sont vérifiés que pour les actifs (un abandonné ne peut plus gagner). Si tous abandonnent (0 actif), pas de vainqueur (la salle finit détruite à la dernière déconnexion, §8.12).
- **Défense automatique :** aucun code ajouté — c'est le comportement par défaut du moteur : les territoires gardent leur `owner_id` et leurs garnisons, et `_handle_attack` fait toujours lancer les dés de défense pour le propriétaire. Un Empire déchu se défend donc « tout seul », jusqu'à l'élimination éventuelle (`status="eliminated"` quand son dernier territoire tombe).
- **Frontend (FAIT) :** `network_manager.gd` route `player_abandoned` → applique l'état diffusé (`GameState.update_from_json`) puis émet `game_state_updated` (refresh générique plateau/HUD) **et** le signal dédié `player_abandoned(player_id: int)` (id coercé `int()`, piège JSON §5). ⚠️ Convention du projet : `game_state_updated` est un signal **sans argument** — l'état est appliqué à `GameState` AVANT l'émission (même pattern qu'`action_result`). `main.gd` s'y abonne (`_on_player_abandoned`) : journal **rouge** dans le `MilitaryLog` (« Le Joueur N a abandonné ! Défense automatique activée. », numéro séquentiel `GameState.player_number`) ; si c'est le joueur **local** : `hud.lock_abandon_button()` (bouton « 🏳️ ABANDONNÉ » désactivé — anti double-envoi ; `_disarm_abandon` respecte le verrou si son timer de 3 s retombe après coup) et `_update_instruction` affiche « Vous avez abandonné — vos territoires se défendent automatiquement » via le helper `_am_abandoned()` (lit `is_active` dans l'état ; clics plateau/cartes déjà neutralisés par les contrôles de tour, le serveur ne rendant plus jamais la main). **MAJ §8.23 :** côté joueur **LOCAL**, l'abandon **quitte désormais immédiatement l'arène** (retour `main_menu.tscn` après envoi de l'action) — `lock_abandon_button()` / l'instruction « Vous avez abandonné » ne concernent donc plus que le suivi de l'abandon des **autres** joueurs. Validation : compilation headless + boot runtime `main.tscn` 0 erreur.
- **Validation :** `py_compile` OK sur `state_schemas.py`, `engine.py`, `router.py`, `state_manager.py`. Machine d'état inchangée par ailleurs (stages/phases intacts ; `is_active` a un défaut → désérialisation des parties existantes OK).

### 8.26. Déploiement EN MASSE (`deploy_units` bulk) + tampon de confirmation (full-stack)
> ⚠️ **MAJ §8.31 :** en **placement** (Phase 0), `deploy_units` est désormais une **soumission AVEUGLE & SIMULTANÉE** (stockée puis appliquée pour tous à la résolution) et non plus une pose immédiate séquentielle ; `_handle_place_initial` est **déprécié**. La partie ci-dessous décrit le flux d'origine — toujours valable pour les **renforts de Phase 2** (`_handle_deploy_units`), mais supersédé pour la Phase 0.
> Correctif de playtest : le placement « 1 clic = 1 envoi serveur » était brouillon et bavard. Nouveau flux UX : un **tampon local** alimenté au clic, puis un **bouton de confirmation** qui envoie TOUT d'un coup. **Frontend → actif au relancement du client ; Backend → push + redéploiement VPS requis (§1/§8.7).**

- **Contrat réseau (nouveau).** L'action `deploy_units` ne reçoit plus une troupe unique mais un **dictionnaire complet** : `{"action": "deploy_units", "payload": {"deployments": {"alaska": 2, "brazil": 1}}}`. L'ancien format unitaire `{"territory_id", "amount"}` reste **toléré** (rétro-compat, `GameEngine._parse_deployments` le normalise ; les nombres JSON en float entier sont acceptés). Cette même action sert aux **deux** contextes de pose de troupes.
- **Backend — deux handlers, un parseur.** `_parse_deployments(payload)` valide le dict (entiers > 0). En **placement initial** (stage `placement`), `process_action` route `deploy_units` vers `_handle_bulk_setup_placement` **AVANT** la garde « playing » (le tour de placement suit `setup_index`, pas `current_player_id`) : somme **exactement = stock**, application groupée, stock **vidé**, puis `_advance_setup_index` / `_start_playing`. En **Phase 2** (renforts), `_handle_deploy_units` applique le dict (somme **≤ stock**), débite le stock, et reste en phase 2 (l'avance vers l'attaque se fait au `pass_turn`). Évènement `units_deployed` / `initial_units_placed` enrichi d'une clé `deployments`. L'ancien `_handle_place_initial` (fournée de 3) est **conservé** (action `place_initial`, tests de régression `test_setup_phase.py`).
- **Frontend — tampon `pending_deployments` (main.gd).** `_in_deploy_mode()` = mon tour de placement OU ma Phase 2. Dans ce mode, le **clic GAUCHE** sur un territoire allié ajoute +1 au tampon (`_buffer_add`), le **clic DROIT** retire −1 (nouveau signal `board.territory_right_clicked`, câblé sur l'`input_event` des Area2D). Le badge affiche alors **`Troupes+X` en doré** (`territory_badge.set_data(..., pending)`, `board.set_pending_deployments(dict)`). Le tampon est **purgé** hors mode déploiement (changement de tour/phase) dans `_refresh`.
- **Frontend — bouton « CONFIRMER LE DÉPLOIEMENT » (hud.gd).** Construit **par code** et inséré dans la TopBar juste avant « Fin de Phase » (`_build_confirm_button`). `set_deploy_confirm(active, total, quota)` : masqué hors déploiement, **activé uniquement** quand `total == quota` (= le stock à placer), libellé `✔ CONFIRMER (total/quota)`. Au clic → signal `deploy_confirmed` → `main._on_deploy_confirmed` envoie le dict bulk puis vide le tampon. Tests moteur : `backend/test_deploy_contamination.py` (placement bulk, Phase 2 bulk, parseur).

### 8.28. Propagation des pseudos réels (`PlayerState.username`) (full-stack)
> Correctif de playtest : les joueurs étaient désignés par « Joueur #X » (id DB) au lieu de leur vrai pseudo. Le pseudo réel est désormais injecté côté serveur et affiché **partout**. **Backend → push + redéploiement VPS requis (§1/§8.7).**

- **Schéma.** Nouveau champ **`PlayerState.username: str = ""`**, peuplé à la création de la partie par `create_initial_state` (lit `players_data[i]["username"]`).
- **Source du pseudo (Backend).** Le WebSocket ne transporte que l'`player_id` (le JWT met le username dans `sub`, §5). Le routeur résout donc le pseudo via la **base** : `_lookup_username(player_id)` (helper `router.py`, session DB dédiée, tolérant aux pannes), passé à `manager.connect(..., username)`. Le `ConnectionManager` suit `usernames[room_id][pid]` et l'expose (`get_usernames`) ; `_try_start_game` et l'endpoint REST `start_game` (via la relation `GameRoomPlayer.user.username`) injectent ces pseudos dans `players_data`. Le message lobby `lobby_state` porte désormais une clé **`usernames` {id: pseudo}**.
- **Affichage (Frontend).** `main.gd._display_name(pid)` lit `PlayerState.username` diffusé (replis : pseudo local `AuthManager`, puis « Joueur N »). `hud.gd.update_display` affiche le vrai pseudo du joueur actif (plus seulement le nôtre). `waiting_room.gd._on_lobby_state(players, ready, usernames)` et le signal `network_manager.lobby_state_updated` à **3 arguments** affichent les vrais noms dès la salle d'attente. Le journal d'abandon et l'écran de victoire/`game_over` utilisent aussi `_display_name`.

### 8.31. Sprint « Matchmaking, Déploiement aveugle, Zone stricte, Timers/AFK » (Backend)
> Sprint backend : (1) salles complètes filtrées du lobby + abandon immédiat sur déconnexion brutale ; (2) zone radioactive en **BLOC STRICT de 4** qui se **téléporte** (ne grandit plus) + immunité du Culte étendue ; (3) refonte de la Phase 0 en **DÉPLOIEMENT AVEUGLE & SIMULTANÉ** ; (4) **MINUTERIES** de tour (90 s / 60 s) + gestion **AFK**. **Backend → push + redéploiement VPS requis (§1/§8.7).** ⚠️ **Nécessite des ajustements FRONTEND** (voir « Suites frontend » en fin de section) : tel quel l'arène reste fonctionnelle, mais l'UX de la Phase 0 et l'affichage du timer doivent être adaptés côté client.

**1. Matchmaking & déconnexions (`lobby.py`, `router.py`).**
- `GET /lobby/rooms` (`lobby.py`) ne renvoie une salle QUE si `status == "waiting"` **ET** que le nombre de joueurs actuels (`count(GameRoomPlayer)`) est **strictement inférieur** à `max_players` → les salles pleines (ou en partie) disparaissent de la liste, évitant un `POST /join` voué au « Room is full » (§5).
- **Hard disconnect (Alt+F4 / crash, `_maybe_abandon_on_disconnect`) :** sur `WebSocketDisconnect`, si la salle n'est pas vidée et qu'une **partie est en cours** (état Redis présent, non terminée, joueur encore actif), le routeur déclenche **immédiatement** `_handle_abandon()` pour ce joueur (Empire déchu, §8.20) — au lieu d'un simple `player_disconnected` — pour ne pas bloquer la salle. En lobby (pas de partie), comportement inchangé.

**2. Zone radioactive — bloc strict de 4, téléportation, Culte (`engine.py`).**
- **Ne grossit plus.** `_expand_contamination` (extension du cluster) est **supprimé** au profit de `_relocate_contamination` : à **chaque nouveau round global** (`_end_turn`, `is_new_global_round`), la zone se **TÉLÉPORTE** intégralement sur un nouveau foyer aléatoire.
- **Bloc strict de 4.** `_form_contamination_block` tire un foyer parmi les territoires ayant **≥ 3 voisins** (quasi tous les 42), puis **exactement 3** de ses voisins (`random.sample`) → un bloc **toujours = 4 territoires**. Utilisé par `_initialize_contamination` (démarrage) ET `_relocate_contamination` (rounds). `probability` est figée à `1.0` (mécanique de pression/croissance retirée ; clé conservée pour la forme de l'état, §8.27).
- **Culte de l'Isotope — passif réparé (`_apply_contamination_damage`).** L'immunité s'applique désormais à **TOUS** les territoires du Culte présents dans la zone (**0 dégât chacun** + une ligne de journal verte par territoire), et non plus seulement au mieux garni. `_isotope_protected_territory` (sélection du « meilleur ») est **supprimé**. Dégâts normaux inchangés (−1/territoire, neutralisation à 0 → neutre). *(Modèle de zone détaillé : §8.27 dans [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md).)*

**3. Phase 0 — DÉPLOIEMENT AVEUGLE ET SIMULTANÉ (`engine.py`, `state_schemas.py`).**
- **Schéma.** Nouveau champ **`PlayerState.pending_blind_deploy: Dict[str, int] = {}`** : tampon `{territory_id: nb}` soumis d'un coup, **STOCKÉ sans être appliqué** (aveugle). Vide = pas encore soumis.
- **Plus d'ordre de tour.** `_handle_bulk_setup_placement` (action `deploy_units` en stage `placement`) n'utilise **plus** `setup_index` : **n'importe quel joueur actif** peut soumettre, **en parallèle**. Validation inchangée (somme **== stock**, territoires possédés), puis stockage dans `pending_blind_deploy` (la carte ne bouge pas → « aveugle »). Refus si déjà soumis ou si le joueur a abandonné. Évènement **`blind_deploy_submitted`** `{player_id, ready_count, expected_count}`.
- **Résolution simultanée.** Quand **TOUS** les joueurs actifs ont soumis (`_all_blind_deploys_ready`), `_resolve_blind_deployment` applique **tous** les tampons d'un coup sur la carte, vide tampons + stocks, puis `_start_playing` (stage → `playing`, phase 1, bloc de contamination posé). L'évènement final porte `setup_complete=True`.
- **Confidentialité.** Le routeur **masque** `pending_blind_deploy` de **tous** les joueurs dans l'état diffusé tant qu'on est en `placement` (`router._state_payload`) → personne ne voit où les autres posent avant la résolution. Les garnisons ne se révèlent qu'à la résolution.
- **`place_initial` DÉPRÉCIÉ.** L'ancien placement séquentiel (`_handle_place_initial`, 3 troupes/tour) **lève une erreur explicite**. `setup_index` / `_advance_setup_index` / `_all_stocks_empty` deviennent **legacy** (plus utilisés dans le flux Phase 0 ; supersède §8.26).

**4. Minuteries de tour & AFK (`router.py`, `connection_manager.py`).**
- **Stockage runtime — `RoomTimers` (`connection_manager.py`, instance `timers`).** Par salle : la **tâche asyncio** courante, un **verrou** (`get_lock`) sérialisant **toutes** les mutations d'état (actions joueur ET expirations) pour éviter les races Redis, la **signature de tour armée** `(stage, current_turn, current_player_id)`, les **compteurs AFK** par joueur, et le flag « a agi ce tour ». Pur stockage, aucune logique de jeu.
- **Temps impartis (`router.py`).** **90 s** pour la Phase 0 (`PHASE0_TIMEOUT_SECONDS`), **60 s** par tour (`TURN_TIMEOUT_SECONDS`, couvre les phases 1-4 ; phases 0/5 automatiques). La minuterie de Phase 0 est armée quand **tous les joueurs ont verrouillé leur faction** (= l'arène se charge) ; celle d'un tour à chaque **changement de tour** (`_post_action_timer` : (ré)arme si la signature change, sinon note l'activité du joueur courant).
- **AFK Phase 0 (90 s) — `_resolve_phase0_afk`.** `fill_missing_blind_deploys` répartit **aléatoirement** le stock des joueurs n'ayant pas validé (sur leurs propres territoires), puis force la résolution simultanée et diffuse (`blind_deploy_resolved`, `forced=True`).
- **AFK tour (60 s) — `_handle_turn_afk`.** Si le joueur a **agi** ce tour-ci → on termine juste son tour (`force_end_turn`, pas de pénalité). Sinon → **strike** (tours consécutifs sans action) ; à **2 strikes** → `_handle_abandon` automatique (Empire déchu) ; en deçà → passage de tour forcé (évènement `turn_timeout`). Un strike retombe à 0 dès que le joueur agit. `GameEngine.force_end_turn` saute proprement toutes les phases restantes (abandonne tout état bloquant en attente : conquête / Éclipse / espionnage).
- **Robustesse.** L'expiration s'exécute sous verrou et **vérifie la signature de tour** : si l'état a changé entre-temps (le joueur a agi), la minuterie est **obsolète** et ne fait rien. Annulée à la fin de partie (`_finalize_if_over`) et purgée à la destruction de salle (`timers.cleanup`).

**Contrat réseau (nouveautés, §5).** Évènements serveur→client ajoutés (enveloppe `action_result`) : **`blind_deploy_submitted`** (décompte des prêts en Phase 0), **`blind_deploy_resolved`** (`forced` si AFK), **`turn_timeout`** (tour forcé pour AFK). **`player_abandoned`** est désormais aussi émis sur **déconnexion brutale**. `deploy_units` en stage `placement` = **soumission aveugle** (et non plus pose immédiate). `pending_blind_deploy` est **masqué** dans l'état diffusé en Phase 0.

**Validation.** `py_compile` OK (`engine.py` / `router.py` / `connection_manager.py` / `state_schemas.py` / `lobby.py`). Suites moteur (réel, sans Redis) : `test_setup_phase.py` **37 ✅** (réécrit pour le modèle aveugle/simultané), `test_deploy_contamination.py` **24 ✅** (bloc strict de 4, téléportation, déploiement aveugle), `test_factions.py` **42 ✅** (immunité Culte étendue à tous ses territoires de la zone).

**Suites frontend (⚠️ À FAIRE — `frontend/`, hors périmètre de ce sprint backend).**
- **Phase 0 :** le client gate aujourd'hui la pose sur `setup_index` (`main.gd._is_my_setup_turn`). Avec le modèle aveugle/simultané, autoriser **tout joueur actif** à composer son déploiement et à le **CONFIRMER une fois** (un seul envoi `deploy_units` couvrant tout le stock), puis afficher un état **« en attente des autres (X/Y) »** (via `ready_count`/`expected_count` de `blind_deploy_submitted`). `setup_index` n'est plus pertinent en Phase 0.
- **Timer :** le HUD affiche déjà un compteur MM:SS côté client (`hud.gd`, remis à zéro au changement de signature de tour) — l'aligner sur **90 s** (placement) / **60 s** (tour). Le serveur reste l'autorité (force résolution / passage / abandon).
- **Évènements :** router `blind_deploy_submitted` / `blind_deploy_resolved` / `turn_timeout` dans le journal, et gérer `player_abandoned` reçu sur déconnexion brutale d'un adversaire. → **RÉALISÉ en §8.32** (voir [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)).

### 8.33. Time Bank (timer de combat) + Chat de salle (Général / Privé) (Backend)
> Sprint **backend** : (1) **Time Bank** — amortir le temps des animations de combat (Split-Screen VS) en créditant **+10 s** au timer du tour à chaque attaque réussie, **plafonné à 90 s** au total (anti-abus) ; (2) **Chat de salle** fonctionnel via les WebSockets, limité à **2 canaux** — l'onglet « Alliés » est **officiellement abandonné** (jeu chacun-pour-soi). **Aucun changement du schéma d'état** (`state_schemas.py` inchangé). Validé par une suite moteur dédiée (`test_time_bank_chat.py`, **33 ✅**) + non-régression (`test_factions` 42 / `test_deploy_contamination` 24 / `test_setup_phase` 37).

**1. Time Bank — échéance de tour DYNAMIQUE (`engine.py`, `connection_manager.py`, `router.py`).**
- **Bonus déclaré par l'engine.** Constante `GameEngine.TIME_BANK_ATTACK_BONUS_SECONDS = 10`. L'évènement `attack_result` porte désormais le champ **`time_bank_bonus_seconds`** : l'engine se contente de **DÉCLARER** le bonus (séparation des responsabilités — il ne connaît pas le temps réel) ; le plafonnement et l'application à la tâche asyncio sont du ressort des minuteries.
- **Échéance monotone + plafond (`RoomTimers`).** Deux nouveaux dicts par salle : **`deadlines`** (échéance monotone courante `loop.time()`) et **`hard_caps`** (plafond absolu du tour). Méthodes : `arm_deadline(now, delay, max_total)` (pose `now+delay` et `now+max_total` → **réinitialise la bank** du nouveau tour), `get_deadline`, **`extend_deadline(bonus)`** (`min(deadline+bonus, hard_cap)`, no-op si rien d'armé), `clear_deadline`. Purgés par `cleanup` et au `clear_deadline` de fin de partie.
- **Minuterie à échéance dynamique (`_turn_timeout`, refonte).** La coroutine ne dort plus un `delay` fixe : elle **boucle** en dormant jusqu'à l'échéance courante, puis **SOUS VERROU relit l'échéance** — si la Time Bank l'a repoussée pendant le sommeil ou l'attente du verrou, elle **se rendort** ; sinon elle applique l'AFK. L'extension repoussant **toujours** l'échéance plus tard, se réveiller à l'ancienne échéance puis se rendormir est correct (et borné par le plafond). La garde de **signature de tour** (obsolescence si l'état a changé) est conservée. ⇒ **Pas besoin de réveiller/recréer** la tâche à chaque attaque.
- **Application (`router.py`).** `_arm_next_timer` pose l'échéance : **placement** `90 s` **sans bank** (`max_total == delay`) ; **jeu** `60 s`, `max_total = TURN_MAX_TIMEOUT_SECONDS = 90`. Dans la branche action de jeu : après une action réussie, si `event["time_bank_bonus_seconds"]` est présent **ET** qu'on est en `playing`, joueur **actif courant**, partie **non gagnée** → `timers.extend_deadline(room_id, bonus)`.
- **Anti-abus.** Plafond **dur à 90 s par tour** (= base 60 + 30 de bank max) : un joueur qui attaque en boucle ne peut **pas** faire remonter indéfiniment son timer pour bloquer la salle.

**2. Chat de salle — canaux « Général » et « Privé » (`router.py`).**
- **2 canaux SEULEMENT.** `CHAT_TABS = ("general", "private")`. L'onglet **« Alliés » est abandonné** (chacun-pour-soi) : tout `tab` hors de ces deux valeurs est **rejeté** (erreur privée à l'expéditeur).
- **Protocole tolérant.** `_handle_chat_message` accepte le payload **à plat** (`{type:"send_chat_message", tab, text, target_id}`, contrat principal) **OU** en enveloppe `{action, payload}`. Intercepté **HORS verrou** dans la boucle WS (un message de chat ne mute aucun état → ne doit pas être sérialisé derrière les actions de jeu / les minuteries).
- **Général.** Diffusé à **toute la salle** (`broadcast_to_room`) — l'expéditeur reçoit son propre **écho**.
- **Privé.** `target_id` **requis**, **distinct** de l'expéditeur et **connecté** (sinon erreur). Envoyé **uniquement à la cible** + **écho à l'expéditeur** ; jamais reçu par un tiers.
- **Sécurité / robustesse.** Message **estampillé serveur** (`sender_id` + `sender_name` = pseudo réel résolu, repli `Joueur {id}` — **pas d'usurpation** côté client) ; `target_id` normalisé en **int** (piège des ids JSON §5) ; texte **strippé**, message **vide ignoré** silencieusement, **tronqué** à `CHAT_MAX_LENGTH = 500` (anti-spam). **Côté serveur**, le chat est traité **indépendamment du `stage`** (techniquement accepté en lobby comme en arène). ⚠️ **DÉCISION PRODUIT (frontend, §8.42) : le chat n'existe QUE dans l'arène.** Le client **n'expose AUCUNE UI de chat en lobby / `waiting_room`** (choix délibéré) → il n'émet ni n'affiche jamais de chat hors arène ; la capacité serveur « lobby » reste donc inutilisée par design.

**Contrat réseau (§5 mis à jour).** Client→serveur : `send_chat_message`. Serveur→client : `chat_message` (`tab`, `sender_id`, `sender_name`, `text`, `target_id` en privé). `attack_result` porte en plus `time_bank_bonus_seconds`.

**Frontend (✅ FAIT — §8.42, cf. [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)).** L'UI chat est désormais **câblée au réseau** : `network_manager.send_chat_message` (forme à plat) + signal `chat_message_received` → `hud.add_chat_message`. **2 canaux Général/Privé** (l'onglet Alliés 🤝 a été **retiré**, ainsi que sa page de tab). ⚠️ **Le chat n'existe QUE dans l'arène** (`main.tscn`) — **décision produit : aucun chat en lobby / `waiting_room`** (pas d'UI prévue ailleurs). Le rebours HUD (local, §8.32) **reflète désormais** la Time Bank : à réception d'`attack_result`, `main.gd` lit `time_bank_bonus_seconds` et appelle `hud.add_time_to_timer(bonus)`, qui crédite le compteur du tour courant (cumul `_turn_bonus`, **plafond visuel 90 s = `TURN_TIME_MAX`**, miroir du `hard_cap` serveur). Appliqué sur **tous les clients** (compteur du tour commun à tous), **avant** l'animation VS. L'étiquette « ⏱ TIME BANK +10 s » du Split-Screen VS subsiste (cosmétique, attaquant local). Le serveur reste l'autorité.

**Fichiers touchés (backend).** `api/game/engine.py` (constante + champ `time_bank_bonus_seconds`), `api/sockets/connection_manager.py` (`RoomTimers` : `deadlines`/`hard_caps` + méthodes), `api/sockets/router.py` (`TURN_MAX_TIMEOUT_SECONDS`, `_arm_next_timer`/`_turn_timeout` refondus en échéance dynamique, extension après attaque, `_handle_chat_message`/`_send_room_error` + interception WS). **NOUVEAU** `backend/test_time_bank_chat.py`.

**Validation.** `py_compile` OK (`engine.py` / `router.py` / `connection_manager.py`). `test_time_bank_chat.py` **33 ✅** (Time Bank : +10/attaque, plafond 90, placement sans bank, réarmement, clear/cleanup ; Chat : général+écho, privé ciblé+écho, Alliés rejeté, gardes cible-manquante/soi-même/déconnecté/vide, enveloppe `{action,payload}` tolérée, troncature 500, repli pseudo). Non-régression moteur (réel, sans Redis) : `test_factions` **42 ✅**, `test_deploy_contamination` **24 ✅**, `test_setup_phase` **37 ✅**.

### 8.34. `current_players` exposé dans la liste des salles (Backend)
> Le « Radar des Opérations » du lobby (§2.2, [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)) affichait `—/max` faute d'occupation courante dans la réponse. Le payload de salle expose désormais **`current_players: int`** → vraie jauge « joueurs/max ». **Backend → push + redéploiement VPS requis (§1/§8.7).** Lève la « limite backend » notée en §2.2 (le frontend lisait déjà ce champ **défensivement**, il devient donc actif sans modification client).

- **Schéma (`models/schemas.py`).** `GameRoomResponse` gagne **`current_players: int = 0`**. Défaut `0` → rétro-compatible (toute réponse qui ne le peuple pas reste valide) ; avec `from_attributes=True`, Pydantic lit l'**attribut transitoire** posé sur l'objet ORM s'il existe, sinon retombe sur le défaut.
- **Route liste (`GET /lobby/rooms`, `lobby.py`).** Le compteur `count(GameRoomPlayer)` **était déjà calculé** pour le filtre « non pleine » (§8.31) ; il est désormais **posé sur l'objet ORM** (`room.current_players = current_players`) avant d'être renvoyé. **Attribut transitoire NON persisté** (ce n'est pas une colonne `GameRoom` ; aucun `commit` ne suit la lecture).
- **Route création (`POST /lobby/rooms`).** Renseigne aussi `db_room.current_players` (= 1, le créateur étant auto-inscrit) pour un payload cohérent au lieu du défaut `0`.
- **Contrat (§5 mis à jour).** `GET /lobby/rooms` → chaque salle porte `current_players`. **Aucun nouveau champ persistant en base** (calcul à la volée).
- **Validation.** `py_compile` OK (`api/v1/endpoints/lobby.py`, `models/schemas.py`). ⚠️ Runtime complet (FastAPI/SQLAlchemy) à vérifier sur le VPS après redéploiement.

### 8.35. « Mémoire Tactique » : `GameState.statistics` (Backend — schéma + câblage moteur)
> Nouveau champ d'état destiné à alimenter les onglets de renseignements « Intel » du HUD (§3 ; **consommé côté client par le tiroir « INTEL : ZONE », §8.36** [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)) : il centralise les statistiques **GLOBALES** de la partie. ✅ **Schéma + alimentation moteur câblés** — le champ est diffusé dans l'état ET peuplé par le moteur à chaque résolution de tour (attrition de zone + stagnation, voir §4.2 dans [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md)). Pas de migration ni de redéploiement bloquant : champ à défaut → rétro-compatible avec les états Redis existants.

- **Schéma (`state_schemas.py`).** Nouveau modèle imbriqué **`GameStatistics`** + champ **`GameState.statistics: GameStatistics = Field(default_factory=GameStatistics)`**. Deux compteurs au départ : `zone_kills_by_player: Dict[int, int] = {}` (clé = `player_id`, valeur = unités détruites par la zone, ex. `{1: 15, 2: 3}`) et `zone_stagnation_turns: int = 0` (rounds globaux consécutifs sans déplacement de la zone). **Modèle typé** (et non `Dict[str, Any] = {}`) → la structure par défaut est **garantie présente** (un `Dict = {}` partirait vide, exposant les consommateurs à un `KeyError`) et le frontend dispose d'un contrat stable. Clé `int` choisie pour rester homogène avec `players` / `initiative_rolls` / `objectives`.
- **Diffusion & State Redaction.** Données **PUBLIQUES** → propagées telles quelles par `router._state_payload` (`model_dump()` du modèle entier, aucune liste blanche à mettre à jour) et **NON rédigées** par `_redact_state_for_player` (qui ne masque que les objectifs secrets). En JSON, les clés `int` de `zone_kills_by_player` deviennent des `str` (`{"1": 15}`) — exactement comme `objectives` / `players`.
- **Rétro-compatibilité.** `default_factory` → toute partie neuve démarre avec la structure complète ; un état Redis **antérieur** (sans `statistics`) se redésérialise sans erreur (`model_validate_json` applique le défaut), comme pour `stage` / `is_active`. **Aucun nouveau champ persistant en base** (l'état de partie vit dans Redis).
- **Alimentation moteur (`engine.py`).** Deux points de câblage, dans la résolution de tour (Phase 0) :
  - **Attrition — `_apply_contamination_damage`.** Un compteur local recense les troupes RÉELLEMENT détruites pour le joueur entrant (1 par territoire contaminé qu'il possède), puis `zone_kills_by_player[player_id] += kills` (clé initialisée à 0 via `.get`). **Immunité respectée** : le Culte de l'Isotope (et toute immunité environnementale via le retour anticipé `immune_to_contamination`) → 0 dégât → **aucun kill compté, aucune entrée parasite**. Un territoire ravagé jusqu'à 0 (→ neutre) compte bien sa dernière troupe comme kill.
  - **Stagnation — `_relocate_contamination`.** L'ancien bloc est capturé **avant** la téléportation ; si le nouveau bloc recoupe l'ancien (`old & new` ≥ 1 territoire), `zone_stagnation_turns += 1`, sinon il retombe à `0` (déménagement complet, ou aucune zone précédente). Appelé une seule fois par **round global** (cf. `is_new_global_round`) → cadence d'incrément = 1/round.
- **Validation.** `py_compile` OK (`state_schemas.py`, `engine.py`, `router.py`, `connection_manager.py`, `state_manager.py`). Smoke-test Pydantic **2.13.4** (schéma) : défauts, **isolation des instances**, auto-remplissage, **rétro-compat** (état sans le champ), round-trip JSON Redis + clés `int→str`. Test comportemental moteur (stubs SQLAlchemy/Redis, **réel sans Redis**) : attrition normale, accumulation, territoire→neutre, **immunité Culte = 0 kill**, stagnation overlap/disjoint/zone-absente — **tous verts**. Suites de non-régression : `test_deploy_contamination.py` **24 ✅**, `test_factions.py` **42 ✅**, `test_setup_phase.py` **37 ✅**. ⚠️ Runtime complet (FastAPI/Redis) à revalider sur le VPS.

### 8.46. Liaison Frontend↔Backend : config centralisée, session persistante, classement (full-stack)
> Session de **câblage frontend↔backend** : (P0) deux correctifs de session/login ; (P1) un autoload **`ApiConfig`** source unique des hôtes + **session persistante avec reconnexion auto** ; (P2) **classement mondial RÉEL** via un nouvel endpoint public. **`frontend/` est un dépôt git imbriqué SÉPARÉ** ; moteur **Godot 4.7**.
>
> ⚠️ **IMPORTANT — REDÉPLOIEMENT BACKEND REQUIS (Docker/VPS, §1/§8.7).** Tant que le VPS n'est pas à jour : `GET /leaderboard` répond **404** (le client retombe proprement sur le classement de prévisualisation) **et** le token reste **plafonné à 30 min**. La **`SECRET_KEY_FASTAPI`** du `.env` reste un **placeholder à remplacer** (sécurité — NON traité dans cette session).

**P0a — Durée de vie du JWT lue depuis la config (`auth.py`, `core/config.py`).** `auth.py` figeait `ACCESS_TOKEN_EXPIRE_MINUTES = 30` **en dur**, ce qui ignorait le `.env` (`1440`) et **coupait les sessions au bout de 30 min**. *Fix :* la valeur vient désormais de **`settings.ACCESS_TOKEN_EXPIRE_MINUTES`** — champ **AJOUTÉ** à `core/config.py` (défaut **1440**, surchargé par `.env`).

**P0b — Login robuste : encodage du corps (`auth_manager.gd`).** `AuthManager.login` envoyait `username=...&password=...` **SANS encodage** → un `&`, `=`, `+` ou espace cassait le corps `x-www-form-urlencoded`. *Fix :* chaque valeur est désormais **`.uri_encode()`-ée**.

**P1a — `ApiConfig` (NOUVEL autoload, `api_config.gd`).** Enregistré comme **PREMIER autoload** dans `project.godot` (avant `AuthManager`/`NetworkManager`). **Source UNIQUE des hôtes backend** : expose `http_host` et `ws_host`. `auth_manager`, `network_manager` et `bootloader` lisent leur hôte ici au démarrage (`get_node_or_null` + **repli sur la prod si absent** → aucune régression). **Bascule dev/prod sans recompiler :** argument de ligne de commande **`--local`** (→ `http://127.0.0.1:8000` / `ws://127.0.0.1:8000`) **OU** fichier **`user://server_host.txt`** (URL `http(s)` libre, hôte WS déduit). *Avant :* l'URL de prod (`api.wasteland-warfare.com`) était **dupliquée en dur dans 3 fichiers**.

**P1b — Session persistante + reconnexion auto (`auth_manager.gd`, `auth_screen`, `lobby_screen`).** Le JWT est sauvegardé dans **`user://session.dat`** à chaque login réussi (`AuthManager._save_session`). Au démarrage, `auth_screen` tente une reconnexion **SILENCIEUSE** (`AuthManager.try_restore_session()` → validation via **`GET /auth/me`**) : token valide → **entrée directe au menu** ; expiré/invalide → purge (`clear_session`) + écran de login normal. La déconnexion (`lobby_screen._on_back_pressed`) appelle **`AuthManager.clear_session()`** qui efface mémoire **ET** disque (sinon l'auto-login relogguerait après un logout volontaire).

**P2 — Classement mondial RÉEL (`leaderboard.py`, `models/schemas.py`, `network_manager.gd`, `leaderboard.gd`).** NOUVEL endpoint **PUBLIC** `GET /api/v1/leaderboard?limit=N` (`leaderboard.py`, enregistré dans `api/__init__.py`) — **aucune authentification** (cohérent avec `GET /lobby/rooms`). Tri par `points_classement` **décroissant**, départage par `stats_victoires` **décroissant**. Réponse = `List[LeaderboardEntry]` — **NOUVEAU schéma Pydantic** dans `models/schemas.py` (champs `username`, `niveau`, `stats_victoires`, `stats_parties_jouees`, `points_classement` ; schéma annoté en §F du contrat). Côté client : **`NetworkManager.fetch_leaderboard()`** + signal **`leaderboard_loaded(entries)`** ; `leaderboard.gd` **REMPLACE le mock** par les vraies données (repli mock gracieux si le serveur ne répond pas ; au passage la stat victoires locale lit enfin le bon champ `stats_victoires`). ✅ **Écart RÉCONCILIÉ (cf. §9.2) :** l'endpoint a depuis été **réaligné sur §9.2** — tri par **victoires** (départage niveau puis points), **enveloppe `{entries, me}`**, **`offset`**, **rang global** et **bloc `me`** (auth optionnelle). Signaux client mis à jour en conséquence (`leaderboard_loaded(entries, me)` ; `fetch_leaderboard(limit, offset)`), avec **tolérance à l'ancienne forme** pendant la fenêtre de redéploiement VPS.

**Contexte projet (rappels).** L'ancienne ouverture `intro_video.tscn` a été retirée au profit de `title_splash.tscn` ; il n'existe **PLUS** de `splash_screen.tscn` (ancien nom). Les écrans Profile/Leaderboard/Shop étaient des maquettes : **Leaderboard est désormais relié** (P2), **Shop reste un mock** (aucun backend).

**Validation.** Éditions appliquées ; ⚠️ runtime complet (token 1440 min, `GET /leaderboard`) **actif uniquement après redéploiement VPS** (voir bandeau IMPORTANT).

### 8.47. Économie globale : Points de Match, XP, Niveaux (cap infini), Coins (Backend)
> Sprint **backend** : implémentation de l'économie de fin de partie — **points de classement**, **XP**, **courbe de niveaux INFINIE** et **monnaie virtuelle « Coins »**. Le calcul de fin de partie (`process_match_results`) est **réécrit** selon les règles exactes du GDD ; les payloads `/auth/me` (profil) et `game_over` (clôture) sont enrichis. **Backend → push + redéploiement VPS requis (§1/§8.7).** Validé : `py_compile` OK (7 fichiers) + suite de tests `rewards.py` (**112/112 ✅**).
>
> ⚠️ **MIGRATION DB — désormais AUTOMATIQUE au démarrage.** Nouvelle colonne **`users.coins`** (`Integer`, `default=0`, `server_default="0"`, `nullable=False`). `Base.metadata.create_all` (au `startup`) **ne fait que CRÉER** les tables manquantes → il n'ajoute **JAMAIS** une colonne à une table `users` déjà existante (sur une base persistée, la colonne resterait absente → `UndefinedColumn` → 500). **C'est désormais géré automatiquement** par **`core/db_migrations.py` → `sync_missing_columns(engine)`**, appelée dans `main.py` **juste après `create_all`** : au boot, elle inspecte la base réelle et ajoute les colonnes ORM manquantes (idempotent, non destructif, pré-crée les types ENUM nommés, warn sur les colonnes FK). **Plus aucune étape manuelle requise.** Le script `migration_coins.sql` (`ALTER … ADD COLUMN IF NOT EXISTS`) est conservé comme **archive / fallback** + son étape **FACULTATIVE** de reset d'XP (que l'auto-migration ne fait pas).

**1. Module de calcul PUR (`api/game/rewards.py`, NOUVEAU).** Aucune dépendance Redis/Pydantic/SQLAlchemy (testable isolément, comme `objectives.py`). ⚠️ **Toutes les valeurs renvoyées sont des `int`** (piège float §5). Règles :
- **Points de Match (selon le rang final).**
  - **1er (Gagnant) :** `20` (base) `+ 1×territoires` (possédés en fin) `+ 2×continents` (possédés en fin) `+ 5×joueurs éliminés par lui` `+ 10×(unités ennemies tuées // 100)`.
  - **2e :** `10` (résilience) `+ 1×territoires + 2×continents + 5×éliminations`. **PAS** les 20 pts de victoire ni le bonus de 100 unités tuées. *Départage de la 2e place :* territoires > continents > unités tuées (décroissants — `rank_players`).
  - **3e et + :** `1×territoires` **uniquement**.
- **XP de match.** `+10 / territoire conquis` (pendant la partie) `+2 / unité ennemie tuée` ; `+5 / continent conquis` (**1er & 2e uniquement**) ; `+150` forfait (**1er uniquement**).
- **Courbe de niveaux (cap INFINI).** Phase 1 (niv. 1→20) : `XP_requise = 200 × niveau`. Phase 2 (niv. 21+) : `XP_requise = 4000` constante. Transition LISSE (`200×20 == 4000`). `xp_required_for_level(level)` est la source unique (mirroir client `xp_coins_bar.gd`).
- **Coins.** `+100` Coins **à chaque palier de 10 niveaux atteint** (10, 20, 30, …).

**2. Persistance & schémas (`state_manager.process_match_results`, `models/models.py`, `models/schemas.py`).**
- `process_match_results(db, winner_id, match_stats)` (**signature changée** — ne prend plus `match_type`/`rankings` mais le dict `match_stats` produit par `GameEngine.build_match_stats`) calcule rangs + points + XP + niveaux + Coins, **persiste** (`points_classement`, `experience`, `niveau`, `coins`, `stats_victoires`, `stats_parties_jouees`) et **renvoie** `{ player_id : MatchRewards }`.
- **`User.coins`** : nouvelle colonne (cf. bandeau migration).
- **`UserResponse` (`/auth/me`)** expose désormais **`coins`** + 4 alias canoniques DÉRIVÉS et **typés `int`** : **`player_level`** (= niveau), **`current_xp`** (= experience), **`xp_to_next_level`** (= `xp_required_for_level(niveau) − experience`), **`coins_balance`** (= coins). Le client lit indifféremment l'ancien nom ou le nouveau (réconcilie une partie de §9.1 : `level`/`xp`/`xp_max`/`credits`).

```jsonc
// GET /api/v1/auth/me → UserResponse (extrait économie, §8.47) — clés AJOUTÉES :
{
  "niveau": 12, "experience": 300, "coins": 250,   // champs ORM bruts (rétro-compat)
  "player_level": 12,        // int — alias de niveau
  "current_xp": 300,         // int — XP dans le niveau courant
  "xp_to_next_level": 100,   // int — XP restante pour le niveau suivant
  "coins_balance": 250       // int — solde de Coins
}
```

**3. Câblage moteur (`engine.py`, `state_schemas.py`).** `GameStatistics` gagne 4 compteurs (cf. bloc `statistics` du §C) peuplés dans `_handle_attack`, attribués à l'**ATTAQUANT** : `combat_kills_by_player` (+= pertes défensives infligées), `conquests_by_player` (+1 / conquête), `eliminations_by_player` (+1 quand la cible perd son dernier territoire), `continents_conquered_by_player` (liste dédoublonnée des continents pris à 100 % — `_credit_continent_conquests`). `GameEngine.build_match_stats(state)` agrège, EN FIN de partie, possessions finales (territoires/continents) + ces compteurs.

**4. Contrat réseau (§5 & §C/§B mis à jour).** `game_over` porte désormais **`rankings: Array<int>`** (ordre 1er→dernier, départage 2e place serveur) **et `match_rewards`** = `{ "<player_id:str>": MatchRewards }`. **`MatchRewards`** (nouveau schéma `models/schemas.py`) : `{ match_points, xp_earned, coins_earned, level_up_triggered, new_level, current_xp, xp_to_next_level, levels_gained }` — **toutes valeurs ENTIÈRES**. Le client (`network_manager.gd`) relaie via le signal **`match_over(winner_id, match_type, rankings, match_rewards)`** + cache `last_match_rewards` ; le Rapport Post-Op (`operation_report.gd` + `xp_coins_bar.gd`) anime le décompte des points puis le remplissage de la barre d'XP (lueur dorée aux paliers de 10 niveaux). *(Côté frontend : FRONTEND_INTERFACES.md §8.48.)*

**Fichiers touchés (backend).** **NOUVEAU** `api/game/rewards.py`, **NOUVEAU** `test_rewards.py` (suite de tests), **NOUVEAU** `migration_coins.sql` (ALTER) ; `api/game/state_manager.py` (`process_match_results` réécrit) ; `api/game/engine.py` (compteurs combat + `build_match_stats`/`_credit_continent_conquests`) ; `api/game/state_schemas.py` (`GameStatistics` +4 compteurs) ; `api/sockets/router.py` (`_finalize_if_over` → `build_match_stats` + broadcast `match_rewards`) ; `models/models.py` (colonne `coins`) ; `models/schemas.py` (`UserResponse` + `MatchRewards`). **MAJ auto-migration & robustesse :** **NOUVEAU** `core/db_migrations.py` (`sync_missing_columns` — ajout auto des colonnes ORM manquantes au démarrage, remplace l'ALTER manuel) ; `main.py` (appel après `create_all` **+** handler global `@app.exception_handler(Exception)` → 500 JSON).

**Validation.** `py_compile` OK (7 fichiers). **Suite dédiée `backend/test_rewards.py` : 112 OK / 0 FAIL** (`python test_rewards.py`, style maison sans pytest — bootstrap qui stube SQLAlchemy + faux `models.models.User`, ni FastAPI ni serveur Redis requis). Couvre **100 % de `rewards.py`** (courbe 200×niv / 4000 plat + garde anti-boucle ; points 1er/2e/3e + bornes du bonus de kills ; XP par rang ; montées multi-niveaux ; **bascule Phase 1→2 18→21 avec 100 Coins au niveau 20** ; saut franchissant 10 ET 20 → 200 Coins ; départage 2e place) **+** `process_match_results` (orchestration + persistance via faux Session, dont **2e éliminé à 0 territoire → 10+5×elim de résilience**, et joueur introuvable) **+** `GameEngine.build_match_stats`/`_credit_continent_conquests` (agrégat continents + dédoublonnage). ⚠️ Runtime complet (FastAPI/SQLAlchemy/Redis) à revalider sur le VPS après redéploiement. **La colonne `coins` est désormais ajoutée AUTOMATIQUEMENT au boot** (`core/db_migrations.py`) — `migration_coins.sql` n'est plus à appliquer à la main.

### 8.48. Correctifs « boucle de gameplay » — anti double-avance, ordre d'Initiative & verrou UI (full-stack)
> Autopsie de 3 régressions de playtest (tours sautés, sauts d'étapes, double-confirmation/gel).
> ⚠️ **Le moteur de minuteries/verrou/AFK (§8.31/§8.33) est resté CORRECT** — vérifié : pas de race
> sur `get_lock`, pas de double-fire de minuterie, pas de faux AFK d'un joueur actif (le strike est
> purgé dès la 1ʳᵉ action « même-tour » de chaque tour). Les causes racines étaient ailleurs.

**1. `pass_turn` idempotent par phase (`engine.py`, `_handle_pass_turn`).** L'action accepte un champ
**optionnel `from_phase`** (`{"action":"pass_turn","payload":{"from_phase":<int>}}`) = la phase que le
CLIENT croit courante. Le serveur **rejette** (`ValueError` → `type:error`) toute requête dont
`from_phase` ≠ `state.phase`. Une 2ᵉ trame `pass_turn` bufferisée (double-clic / latence) porte donc
l'ANCIENNE phase et devient un **no-op**, au lieu d'avancer une 2ᵉ fois et de **sauter une étape**.
Champ absent (ancien client) → aucune contrainte (rétro-compatible). Même esprit que la garde de
signature de tour des minuteries (§8.31).

**2. Ordre des tours = `turn_order` à CHAQUE tour (`engine.py`, `_end_turn`).** **Bug corrigé :** la
rotation se faisait sur `sorted(players.keys())` (ids croissants) dès le tour 2, **ignorant l'ordre
d'Initiative** (§4.1.1) que seul `_start_playing` respectait (1ᵉʳ tour). `_end_turn` tourne désormais
sur **`state.turn_order`** (figé à la création, jamais muté), avec repli défensif sur l'ordre trié si
`turn_order` est absent (état Redis antérieur). Joueurs inactifs/éliminés toujours sautés (Fallen
Empire) ; `is_new_global_round` (téléportation de zone §8.31) inchangé sémantiquement (détecté au
bouclage de `turn_order`).

**3. Frontend — verrou « action en vol » + tampon de déploiement préservé (`main.gd`, `hud.gd`).** Le
bouton **« Fin de Phase »** est désactivé dès le clic (`hud.set_pass_enabled(false)`) et un verrou
`_pass_in_flight` interdit un 2ᵉ envoi tant que le serveur n'a pas répondu (levé par
`game_state_updated` / `game_error`) ; `pass_turn` joint `from_phase = GameState.current_phase`. Le
tampon `deploy_units` est **mémorisé avant purge** (`_deploy_snapshot`) et **restauré** si le serveur
refuse → plus de placement reperdu ni de soft-lock « en attente » en Phase 0.

**4. Durcissement AFK (`router.py`, `_post_action_timer`).** Le compteur de *strikes* est aussi remis
à zéro sur l'action qui **clôt** le tour (branche de ré-armement), garantissant la sémantique « 2
tours **consécutifs** sans action » même si une action met directement fin au tour. Défensif (aucun
impact sur le plafond 60/90 s ni la Time Bank §8.33).

**Fichiers touchés.** Backend : `api/game/engine.py` (`_end_turn`, `_handle_pass_turn`),
`api/sockets/router.py` (`_post_action_timer`). Frontend : `scripts/game/main.gd`,
`scripts/ui/hud.gd`. **NOUVEAU** `backend/test_turn_loop_fixes.py`.

**Validation.** `py_compile` OK ; Godot `--import` du frontend **propre (0 ERROR)** ; non-régression
moteur `test_setup_phase` **37** / `test_deploy_contamination` **24** / `test_factions` **42** /
`test_time_bank_chat` **33** ✅ ; **nouvelle suite `test_turn_loop_fixes.py` 13 ✅ / 0 ❌** (rotation
`turn_order` + saut d'inactifs, garde `from_phase` anti double-avance, purge du strike sur fin de
tour). ⚠️ Runtime complet (FastAPI/Redis) à revalider sur le VPS après redéploiement.

### 8.61. Couche RPG Héros — contrat réseau (state / combat / fin de partie) + réalignement économie (Backend)
> Référence réseau de la **surcouche RPG des héros** (sprint RPG & Survie) — **jamais documentée ici** jusqu'ici — et **réalignement** du réglage sur le cahier des charges. Côté client, le HUD qui consomme tout ceci est détaillé en **§8.60** de [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md). ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**. Toutes les valeurs entières = **entiers PURS** (piège JSON float §5 ; clés de `players`/`objectives` = `string` après JSON).
- **Stats héros dans le `state` diffusé (`PlayerState`, PUBLIQUES).** Chaque `players[pid]` porte : `hero_level`, `hero_pv_max`, `hero_pv_current`, `hero_pa`, `hero_pb` (réduction **fraction 0.0–0.30**, PAS un %), `hero_pp_min`, `hero_pp_max`, `hero_pp_current`, `hero_regen` (fraction), `is_dead`. **La State Redaction ne masque QUE les objectifs secrets** → les stats héros sont **publiques** (inspection d'un adversaire OK). Tous à défaut 0/False → rétro-compat (un état Redis antérieur se redésérialise sans erreur). **Éphémères** (Redis only) : `hero_pv_current`/`hero_pp_current`/`is_dead` ne sont **jamais** persistés en SQL.
- **NEUFS — barre d'XP in-game.** `hero_xp_in_level` / `hero_xp_for_level` : **instantané méta-jeu pris au DÉMARRAGE** de la partie (XP dans le niveau courant / coût du niveau), **statique pendant le match** (les montées de niveau s'appliquent en FIN de partie) ; `0/0` = niveau max (barre masquée). Peuplés par `hero_progression.get_hero_progress` côté REST `start_game` ET draft WS `faction_choice`. Éphémères (Redis), non SQL.
- **Combat — `action_result.event.hero_duel`.** UN duel par ATTAQUE (pas par dé). Dict `{attacker_id, defender_id, pp_delta, attacker_pp, pp_counted, damage, defender_pv, defender_pv_max, hero_died}` (ou `null` si héros non initialisés / défenseur déjà mort). Asymétrique : seul le PP de l'**attaquant** bouge (`pp_delta` : **+dés gagnés** si au moins un dé gagné, sinon **−dés perdus** — règle §8.150 ; le résultat est ensuite borné `[pp_min,pp_max]` dans `attacker_pp`), seul le PV du **défenseur** baisse (`damage = max(1, floor((PA + pp_counted)·(1−PB)))`). **`pp_counted`** (ADDITIF §8.150) = part des PP réellement comptée dans les dégâts : égale à `attacker_pp` tant que le tunable `PP_DUEL_DAMAGE_CAP` vaut 0 (état livré). **Permadeath** : `defender_pv ≤ 0` → joueur `status="eliminated"`, **tous ses territoires garnison forcée à 1** (conservés, pas neutres). La mécanique Risk (dés/troupes/conquête) et la Time Bank (+10 s/attaque, max 90 s) sont **inchangées**.
- **Fin de partie — `game_over.match_rewards[pid]` (champs héros).** `hero_xp_earned`, `hero_level` (avant), `hero_new_level`, `hero_levels_gained`, `hero_total_xp`, `hero_level_up`, `hero_xp_in_level`, `hero_xp_for_level`, `hero_milestones[{level,bonus}]`, **+ NEUF `hero_coins_earned`**. Barème XP héros : +1/unité tuée, +150 objectif, +5/territoire en fin, +100/coup de grâce, +1/4 PV de dégâts. **Coins par niveau** : 1-5 aléatoire **par niveau** franchi (sans gating Pass pour l'instant — palier « avec Pass Season » 10-20 différé), crédités sur `User.coins`. La progression (`HeroProgression(user_id, faction_id)` : `hero_level`, `hero_xp` lifetime) est la **SEULE** donnée héros persistée en SQL.
- **Fin de partie — `game_over.match_rewards[pid].xp_inputs` (bloc ADDITIF).** Les entrées **EXACTES** du barème telles que le serveur les a utilisées : `rank`, `territories_end`, `continents_end`, `continents_conquered`, `eliminations`, `enemy_kills`, `conquests`, `hero_kills`, `hero_damage`, `objective_win`, `xp_pass_bonus`. Le Rapport Post-Op rend son détail **depuis ce bloc** au lieu de ré-estimer localement → la ligne « Ajustement serveur » retombe structurellement à **0**. Il corrige deux divergences historiques : (1) `continents_conquered` (continents conquis **pendant** la partie, métrique de l'XP) ≠ `continents_end` (continents **possédés en fin**, métrique des POINTS et seule dont disposait le client) ; (2) `xp_pass_bonus` = surplus RÉEL du Pass (palier exact ×1.10 / ×1.25 / ×1.50), là où le client supposait ×1.25 pour tout le monde. Bloc **absent** sur un serveur antérieur → le client retombe sur son estimation locale (rétro-compatible). Entiers/booléens purs (§5).
  > **§8.147 — deux mises à jour de CE bloc.** (1) Le Pass n'a plus qu'**UN** palier : `xp_pass_bonus` est le surplus du seul `×1.50` (la liste « ×1.10 / ×1.25 / ×1.50 » ci-dessus est HISTORIQUE — elle décrit les trois paliers retirés, dont les détenteurs actifs sont lus `season`, cf. §8.147). (2) Clé **ADDITIVE `hero_xp_pass_bonus`** = le JUMEAU côté héros (`hero_xp_earned − base_hero_xp`, 0 sans Pass), né en même temps que l'axe « XP de héros ×2 ». ⚠️ Sans elle le client rejouait le barème héros **sans** connaître le multiplicateur et retombait sur la BASE : l'onglet XP HÉROS affichait un « Ajustement serveur » égal au bonus entier (mesuré : 329 reconstruit contre 658 crédités) — exactement le défaut que `xp_pass_bonus` avait fermé côté profil, et que l'axe neuf avait rouvert côté héros.
- **Objectifs DOUBLES (redaction préservée).** Chaque objectif = `{type:"double", kill_objective, classic_objective, params}` (sémantique **OU** : tuer le héros X **OU** conquérir territoire/continent Y). Le volet « tuer X » exige `eliminated_by[X] == self_id` (le **coup de grâce** crédite le tueur, pas un « chasseur » au hasard). L'objectif entier est **masqué** aux adversaires (`{type:"hidden", description:"Objectif classifié"}`).
- **Endpoint roster.** `GET /api/v1/heroes` (authentifié) — schéma détaillé en **§8.59** de [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md).
- **⚠️ Réalignement cahier des charges (2026-06-26).** **Cap héros = 50** (était 100 ; `rewards.HERO_LEVEL_MAX` + `factions.HERO_LEVEL_MAX`, à garder synchro). **Courbe d'XP FIGÉE** `step(N→N+1)=round(348·1.05^(N-1))`, N=1..49, **total 69050 @50** (générée au boot). **Paliers de stats = exactement 10/20/30/40/50** (10 héros re-tunés en préservant les totaux max). **`pp_max ∈ [15,20]`**. Validé par TDD (16 suites backend vertes).

### 8.62. Minuterie PAR PHASE — le rebours repart à chaque « Fin de Phase » (full-stack, 2026-07-01)
> **Correctif gameplay.** L'ancien modèle « **60 s pour tout le tour** » (couvrant les phases 1-4) **coupait le tour** d'un joueur en pleine phase tardive : le temps passé en Renforts/Déploiement grignotait celui de l'Attaque/Mouvement, et l'expiration forçait la fin de tour. Désormais le serveur **repart le rebours à neuf à CHAQUE « Fin de Phase »**, avec un **budget par type de phase**. ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**.
- **Budgets par phase (`router.py`).** `DEFAULT_PHASE_TIMEOUT_SECONDS = 60` (Renforts 1 / Déploiement 2 / Mouvement 4) ; **Attaque (phase 3)** `ATTACK_PHASE_TIMEOUT_SECONDS = 90`, **extensible jusqu'à `ATTACK_PHASE_MAX_TIMEOUT_SECONDS = 180`** par la Time Bank (§8.33). Table `PHASE_TIMEOUT_SECONDS` + helper `_playing_phase_budget(phase) -> (delay, max_total)` (plafond == délai hors Attaque → **pas d'extension** : aucune attaque hors phase 3). Les constantes `TURN_TIMEOUT_SECONDS`/`TURN_MAX_TIMEOUT_SECONDS` (60/90 globaux) sont **supprimées**. Phase 0 inchangée (`PHASE0_TIMEOUT_SECONDS = 90`).
- **Réarmement intra-tour (`router.py` + `RoomTimers`).** `_arm_next_timer` pose le budget de la **phase courante** et mémorise `timers.set_armed_phase(phase)` (nouveau dict `armed_phases` dans `RoomTimers`, purgé par `clear_deadline`/`cleanup`). `_post_action_timer` : si la **signature de tour est inchangée** (même tour/joueur) mais que la **phase a changé** (clic « Fin de Phase »), il appelle le **NEUF `_rearm_deadline_for_phase`** → annule la tâche, repose l'échéance + plafond selon la nouvelle phase, **relance** la coroutine d'expiration (gère un budget plus COURT que le reliquat, ex. sortie d'Attaque prolongée). **Le bookkeeping AFK reste au niveau du TOUR** : `acted`/`afk_strikes` ne sont **pas** réinitialisés au changement de phase → un joueur qui enchaîne ses phases reste « actif » (aucun strike), mais l'inactivité prolongée sur **une** phase finit toujours par expirer. Une action **intra-phase** (déploiement, attaque) **ne** réarme **pas** (sinon la Time Bank serait remise à zéro à chaque attaque).
- **Time Bank (§8.33) — plafond porté à 180 s.** Le hard_cap est désormais celui de la **phase d'Attaque** (180 s) et non plus 90 s tour-large ; il est reposé à neuf à l'entrée de la phase 3. `extend_deadline` borne toujours à `hard_caps[room]`. Aucun changement de protocole (`attack_result.time_bank_bonus_seconds` inchangé).
- **Client (`frontend/hud.gd`) — miroir visuel.** Le rebours local est **keyé sur `étape|tour|joueur|phase`** (était sans phase) → il **repart à chaque phase**. Helper `_phase_turn_limit()` (90 s + bonus jusqu'à 180 s en Attaque, 60 s sinon) ; `add_time_to_timer` plafonne à `ATTACK_PHASE_TIME_MAX = 180`. Constante `TURN_TIME_MAX` (90) remplacée. Le serveur reste l'**autorité** (force passage/abandon).
- **Validation.** `test_turn_loop_fixes.py` **20 ✅** (dont 7 NEUVES : budget 60/90 s par phase, plafond 180 s, `armed_phase`, activité préservée, échéance Time Bank intacte sur action intra-phase) ; `test_time_bank_chat.py` **33 ✅** ; `py_compile` OK (`router.py`/`connection_manager.py`) ; réimport headless `frontend/` **0 ERROR** (`hud.gd`).

### 8.63. Chasse aux bugs moteur — 3 correctifs de robustesse/équité (Backend, 2026-07-01)
> Revue adversariale multi-agents du moteur (`engine.py`) + routeur/minuteries. **3 bugs CONFIRMÉS** corrigés (2 candidats écartés après réfutation : le plafond Aegis `>= 2` est volontaire et correct ; le `KeyError` d'attaque via aéroporté est du **code mort** — `airborne_attacks_left` n'est jamais incrémenté). ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**.
- **(HAUT) XP héros « objectif » offerte aux PERDANTS (`objectives.py`).** `is_objective_complete` (volet `eliminate_player`) posait `last_standing = alive_count <= 1` **sans vérifier que le porteur est le survivant**. En fin de partie par élimination (1 seul vivant), `build_match_stats` — qui évalue l'objectif de **TOUS** les joueurs, éliminés compris — créditait donc l'objectif (et le bonus **+150 XP héros**, `rewards.compute_hero_match_xp`) à **chaque perdant**. ✅ Garde ajoutée : `last_standing` n'est vrai que si `players_status[self_id] == "alive"` (sans `self_id` — anciens appelants/tests — ancien comportement conservé). Sans effet sur `_check_victory` (qui n'évalue que des `contenders` vivants et tranche `len<=1` en amont).
- **(MOYEN) `_handle_move_units` — entrées non validées (`engine.py`).** (1) `amount` n'était ni typé ni borné : un **float** (`2.5`, piège JSON §5) **corrompait la garnison en float** (persistée en Redis) ; une **chaîne** faisait planter `amount <= 0` sur un **`TypeError`** non capturé par le routeur (qui n'attrape que `ValueError`) → **socket coupé**. (2) Les ids de territoires source/cible n'étaient pas vérifiés → **`KeyError`** brut sur un id absent/inconnu (None…). ✅ Validations ajoutées en tête (miroir de `_handle_conquer_move`/`_handle_deploy_units`) : `amount` entier strict (rejette bool/float/str) puis `>0` ; `source`/`target` ∈ `state.territories` → sinon `ValueError` propre.
- **(MOYEN) Minuterie corrompue par l'abandon/déconnexion d'un TIERS (`router.py`).** Un abandon **hors tour** (`action "abandon"`, autorisé) ou la **déconnexion brutale d'un joueur non courant** appelait `_schedule_turn_timer` → `_arm_next_timer`, qui **réinitialisait l'échéance ET le flag « a agi »** (`reset_acted`) du **joueur courant** : faux **strike AFK** (→ abandon auto au 2ᵉ) pour un joueur ayant pourtant joué, et **rebours remis à plein** à chaque départ d'un tiers (vecteur de blocage de salle). ✅ NEUF `_reschedule_timer_if_turn_changed` : ne (ré)arme **que si la signature de tour a réellement changé** (le sortant était le joueur courant → `_end_turn`, ou Phase 0 résolue) ; les deux sites d'abandon (action + `_maybe_abandon_on_disconnect`) l'utilisent.
- **Validation.** `test_turn_loop_fixes.py` **30 ✅** (+10 : validations `move_units`, minuterie préservée hors-tour) ; `test_objectives_double.py` **28 ✅** (+3 : repli « dernier survivant » réservé au survivant) ; non-régression complète (`test_rewards` 121, `test_factions` 42, `test_hero_xp` 35, `test_hero_stats` 188, `test_heroes_roster` 247, `test_setup_phase` 37, `test_deploy_contamination` 24, `test_state_redaction` 15, `test_hero_combat` 28, `test_repro_*`, `test_updater_installer` 10) — **17 suites vertes** ; `py_compile` OK. *(`test_simulation.py` exige `fastapi` installé — non lancé dans l'env de tests léger ; échec d'import pré-existant, sans rapport.)*

---

## 📥 9. DEMANDES FRONTEND EN ATTENTE — endpoints REST à spécifier (R1 / R2 / R3)

> **🤖 À L'ATTENTION DE L'AGENT IA BACKEND.** Section **rédigée par l'agent Frontend** (procédure « signalement » du protocole inter-IA en tête de fichier — *« signale-le… pour que l'agent Backend ajoute le champ au schéma ET à ce fichier »*). Les écrans **R1 Boutique/Inventaire**, **R2 Profil** et **R3 Classement mondial** sont **déjà réalisés côté client** (§8.39 / §8.40 / §8.41 dans [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)) mais tournent sur des **données MOCK** faute d'endpoints. Ci-dessous, le **contrat dont le client a besoin**, ancré sur ce qu'il **lit déjà défensivement** → une fois l'endpoint livré, **« seul le peuplement changera »** côté client (aucune refonte UI). Les clés proposées sont **canoniques** : si le backend en retient d'autres, **documenter le choix ICI** pour que le client s'aligne (il accepte aujourd'hui plusieurs alias, listés par écran). **Rappels normatifs :** piège **JSON float §5** (ids/nombres → `int()`, clés de dict indexées = `string`) ; auth **JWT** (`Authorization: Bearer`), préfixe **`/api/v1`** ; aujourd'hui le client lit le profil via **`GET /api/v1/auth/me`** (`UserResponse` : `id`, `username`, `email`, `niveau`/`level`) et n'a **aucun** autre endpoint joueur. ⚠️ **Backend → push + redéploiement VPS requis** (§1) ; tant que le VPS n'est pas à jour, le client garde ses mocks (lecture défensive).

### 9.1. R2 — Profil & statistiques joueur ✅ LIVRÉ (refonte §8.106 : hub à onglets)
**QUATRE routes**, toutes **authentifiées** (JWT `Authorization: Bearer`, préfixe `/api/v1`). Tout est **ADDITIF** : aucune clé historique n'a été renommée ni supprimée, tout champ neuf a un **défaut sûr**, et les deux routes NEUVES répondent **404** sur un serveur non redéployé → le client dégrade proprement (jamais un écran vide, jamais un crash).

> ⚠️ **Piège JSON float §5.** Aucune valeur fractionnaire ne circule. Les grandeurs naturellement décimales sont transportées en **ENTIER MIS À L'ÉCHELLE** : taux en **pourcentage arrondi** (`winrate: 60`), place moyenne en **DIXIÈMES** (`avg_rank_x10: 24` = 2,4ᵉ). Les multiplicateurs du Pass sont exposés en **bonus % entier** (×1.25 → `25`).

#### `GET /profile/stats` — identité, progression, agrégats
Réponse (les 10 clés historiques sont **INCHANGÉES** ; les 4 blocs sont ADDITIFS) :
```jsonc
{
  "username": "HAKIM", "level": 27, "xp": 1200, "xp_max": 4000,
  "games_played": 48, "wins": 21, "losses": 27,   // losses DÉRIVÉ (games_played - wins)
  "heaviest_toll": 1843,                          // = User.units_lost (pertes cumulées)
  "favorite_faction": "barons_ferraille",         // id snake_case (miroir factions.py)
  "credits": 12450,                               // = User.coins (solde Boutique R1)
  "pacts_broken": 3,                              // ADDITIF §8.123 — = User.pacts_broken (défaut 0)

  // --- ADDITIF §8.106 — carte DIVISION de l'en-tête (source : seasons.rank_info + ladder) ---
  "season": { "rp": 1405, "division": "OR", "tier": "II", "label": "OR II",
              "tier_floor": 1400, "tier_span": 200, "rp_in_tier": 5,
              "global_rank": 37, "season_ends_at": "2026-09-29T04:00:00Z" },
  // tier_span == 0  ⇒  AUCUNE barre d'échelon (ÉLITE, ladder ouvert — ou repli). Le client ne
  // distingue pas les deux cas : il masque la barre dans les deux.

  // --- ADDITIF — agrégat PAR PERSONNAGE (GROUP BY match_history.faction_id + HeroProgression) ---
  "factions": [ { "faction_id": "phalanges_acier", "games": 20, "wins": 12, "losses": 8,
                  "winrate": 60,          // % ENTIER arrondi
                  "avg_rank_x10": 24,     // DIXIÈMES ; 0 = aucune place connue (lignes legacy)
                  "xp_total": 15400, "rp_net": 130,   // rp_net SIGNÉ
                  "hero_xp_total": 22000, "hero_level": 18 } ],   // source : HeroProgression (XP à VIE)

  // --- ADDITIF — agrégat PAR MODE (GROUP BY is_ranked) ---
  "modes": { "ranked": { "games": 25, "wins": 14, "winrate": 56, "rp_net": 130 },
             "casual": { "games": 23, "wins": 7,  "winrate": 30, "rp_net": 0 } },

  // --- ADDITIF — bande de FORME : 10 derniers matchs, le plus RÉCENT d'abord ---
  "form": [ { "win": true, "is_ranked": true } ],

  // --- ADDITIF §8.107 — agrégat PAR CARTE (GROUP BY match_history.map_id) ---
  "maps": [ { "map_id": "classic_42", "games": 30, "wins": 18, "losses": 12,
              "winrate": 60, "avg_rank_x10": 25 } ]
  // `map_id` = id ASCII du registre multi-cartes (G5) — le serveur n'envoie AUCUN libellé
  // affichable (R4) : le client résout via ses clés MAP_*_LABEL. Volontairement plus maigre que
  // `factions` (ni XP ni RP) : le mode CLASSÉ impose sa carte, un « RP par carte » serait dégénéré.
  // ⚠️ Les lignes de carte INCONNUE (`map_id == ""`, tous les matchs antérieurs à §8.107) sont
  // EXCLUES de l'agrégat — les inclure créerait une « carte fantôme » sans nom.
}
```
- **Tri `factions`** : `games` décroissant, départage par `faction_id` (ordre STABLE d'un appel à l'autre).
- **Reset lazy de saison** : la route appelle `settle_previous_season(db)` **puis** `ensure_season(user)` (+ commit si reset) — **même séquence et même ordre** que `/auth/me` et le bloc `me` du classement (§8.98 : régler d'abord, reseter ensuite).
- **`global_rank`** vient de `api/game/ladder.season_rank_of` — **SOURCE UNIQUE partagée** avec `GET /leaderboard` (§9.2) : le rang annoncé au Profil est toujours celui qu'occupe le joueur dans la liste du Classement.
- ⚠️ **Honnêteté des lignes LEGACY** : les matchs antérieurs à §8.106 ont `is_ranked = false` et `final_rank = 0` (défauts d'auto-migration). Ils comptent donc en **NORMALES** même s'ils étaient classés, et leur place est **INCONNUE** — jamais « 1ᵉʳ ». Le client l'explicite (`PROFILE_MODE_LEGACY_NOTE`) et affiche « — ».

#### `GET /profile/history?limit=15&offset=0&wins_only=&ranked_only=` — matchs, filtrables et paginés
`limit` 1-50 (défaut **5**), `offset` ≥ 0, `wins_only` / `ranked_only` booléens **cumulables**. **Tous les paramètres neufs ont un défaut NEUTRE** : l'appel historique `?limit=5` produit exactement la requête d'avant.
```jsonc
// Les 3 clés historiques (win, faction_id, detail) sont INCHANGÉES ; le reste est ADDITIF.
{ "win": true, "faction_id": "barons_ferraille", "detail": "Victoire · 12 territoires · 8 tours",
  "created_at": "2026-07-19T08:00:00Z",   // ISO 8601 « Z » ; "" si absente
  "territories": 12, "turns": 8, "units_lost": 4,
  "is_ranked": true,
  "final_rank": 1,        // 1-BASED ; 0 = place INCONNUE (ligne legacy), surtout pas « 1ᵉʳ »
  "players_count": 5,     // effectif TOTAL de la partie, bots compris
  "xp_earned": 472,       // XP RÉELLEMENT créditée (bonus Pass ×1.25 déjà appliqué)
  "rp_delta": 32,         // SIGNÉ ; toujours 0 hors partie classée
  "hero_xp_earned": 525, "coins_earned": 118 }   // coins = paliers de niveau + niveaux de héros
```
> ⚠️ `final_rank` est **1-based** ici, alors que `MatchParticipant.rank` (télémétrie G6) est **0-based**. Conventions volontairement différentes : le 0 est réservé au « inconnu ». Ne pas les confondre.

#### `GET /profile/public/{username}` — profil PUBLIC d'un autre joueur **(NOUVEAU §8.107)**
Palmarès consultable **uniquement depuis le Classement** (demande produit). **Authentifié** — contrairement à `GET /leaderboard` qui est public : l'écran n'est atteignable que depuis le jeu, et l'exiger limite le moissonnage. `404` si le pseudo est inconnu.
```jsonc
{ "username": "RAVAGEUR_PRIME", "level": 58,
  "games_played": 500, "wins": 412, "losses": 88, "heaviest_toll": 12000,
  "favorite_faction": "barons_ferraille",
  "pacts_broken": 3,                              // ADDITIF §8.123 — PUBLIC par construction (défaut 0)
  "season": { … }, "factions": [ … ], "modes": { … }, "form": [ … ], "maps": [ … ] }
```
- **IDENTIFIANT = LE PSEUDO, pas l'id technique.** `LeaderboardEntry` exclut délibérément l'id (« Données PUBLIQUES uniquement (pas d'email ni d'id technique) ») et **cette décision est maintenue** : router par `username` évite d'exposer un identifiant séquentiel, qui permettrait d'énumérer tous les profils par simple incrément. Le pseudo est déjà affiché par le Classement, est `unique` et indexé → aucune donnée nouvelle n'est divulguée. **Aucun changement au contrat du Classement (§9.2).**
- ⚠️ **FRONTIÈRE DE CONFIDENTIALITÉ.** La réponse est bornée par `PublicProfileResponse`, une **LISTE BLANCHE explicite** — surtout PAS un héritage de `ProfileStatsResponse`, sinon tout champ ajouté demain au profil privé deviendrait public tout seul. Sont **absents par construction et ne doivent jamais y entrer** : `credits`, tout le bloc FINANCES (solde, transactions, potentiel), tout le bloc PASS (état, gains, coût, objets), `email`, l'`id`, `xp`. `/profile/finance` et `/profile/pass` n'acceptent d'ailleurs **aucun paramètre de cible** : ils ne lisent que `current_user`. Verrou de non-régression : `test_profile_data.py`, suite [H]. *(§8.123 : `pacts_broken` a été ajouté à cette liste blanche **délibérément** — un compteur de pactes rompus n'a de sens que s'il est consultable, c'est la seule sanction d'une trahison. Il reste du **palmarès**, au même titre que `wins` ou `heaviest_toll`.)*
- ⚠️ **LECTURE SEULE.** L'endpoint n'appelle **ni `settle_previous_season` ni `ensure_season`** sur le joueur consulté : ce serait ÉCRIRE dans la ligne d'un tiers au passage d'un visiteur (reset de saison déclenché par un GET, avec course entre visiteurs simultanés). Conséquence assumée : si `season_id` n'est plus la saison courante, le joueur n'a pas joué cette saison → **0 RP et rang inconnu**, sans rien persister. Son reset restera déclenché par sa propre activité.

#### `GET /profile/finance?limit=20&offset=0` — livre de comptes Coins **(NOUVEAU)**
```jsonc
{ "balance": 12450, "total_earned": 31000, "total_spent": 18600,   // total_spent POSITIF
  "by_reason": { "match_level_coins": 8000, "hero_level_coins": 4500, "mission_claim": 12500,
                 "season_reward": 6000, "shop_purchase": -13600, "pass_purchase": -5000 },
  "entries": [ { "delta": -500, "balance_after": 12450, "reason": "pass_purchase",
                 "ref": "special_pass", "created_at": "2026-07-18T09:12:00Z" } ],
  "hero_potential": [ { "faction_id": "phalanges_acier", "hero_level": 18, "levels_left": 32,
                        "coins_min": 32, "coins_max": 160,
                        "coins_min_pass": 320, "coins_max_pass": 640 } ],
  "constants": { "hero_coins": [1, 5], "hero_coins_pass": [10, 20],
                 "level_milestone": { "every": 10, "amount": 100 }, "hero_level_max": 50 } }
```
- **RAISONS CANONIQUES** (valeurs **persistées** → stables à vie ; définies dans `api/game/economy.py`) : `match_level_coins`, `hero_level_coins`, `mission_claim`, `shop_purchase`, `pass_purchase`, `coin_pack`, `season_reward`. Le serveur ne renvoie **jamais** de texte affichable : le client dérive la clé i18n `PROFILE_FIN_SRC_<RAISON_MAJ>` et retombe sur la raison brute en muet si elle lui est inconnue → **on peut en ajouter sans casser les clients**.
- **Ordre de `by_reason`** : canonique (gains puis dépenses), conservé par la sérialisation → le client itère sans retrier.
- **`constants`** existe pour que le client n'écrive **aucun barème en dur** (règle §6).
- ⚠️ **AUCUNE donnée rétroactive** : le ledger démarre à §8.106. `balance` est le solde RÉEL (`User.coins`) et **n'est donc PAS égal à `total_earned - total_spent`** pour un joueur préexistant. **Ne jamais reconstruire un solde en sommant les deltas** — c'est `users.coins` qui fait foi.

#### `GET /profile/pass` — Pass Spécial **(NOUVEAU)**
```jsonc
{ "active": true, "expires_at": "2026-09-29T04:00:00Z", "tier_id": "special",
  "tiers": [ { "id": "special", "name_key": "PASS_TIER_SPECIAL", "benefits": [
      { "id": "xp_mult",      "kind": "percent", "value": 25,       "desc_key": "PASS_BENEFIT_XP" },
      { "id": "hero_coins",   "kind": "range",   "value": [10, 20], "desc_key": "PASS_BENEFIT_HERO_COINS" },
      { "id": "mission_mult", "kind": "percent", "value": 50,       "desc_key": "PASS_BENEFIT_MISSIONS" },
      { "id": "season_skin",  "kind": "grant",   "value": "",       "desc_key": "PASS_BENEFIT_SKIN" } ] } ],
  "granted_items": [ { "item_id": "skin_pass_s1", "name_key": "SHOP_SKIN_PASS_S1", "category": "skin" } ],
  "gains": { "bonus_xp_total": 1240, "bonus_mission_coins_total": 380,
             "hero_coins_with_pass_total": 210, "coins_spent_on_pass": 500 } }
```
- **`active` / `expires_at`** : dérivés par les **mêmes helpers que la boutique** (`shop._has_active_pass` / `_pass_expires_iso`) — une seule convention dans tout le dépôt, jamais une troisième. `expires_at` est `null` si le Pass n'est plus actif.
- **`tiers`** vient du registre PUR `api/game/pass_catalog.py`. Les valeurs sont **DÉRIVÉES** des constantes de `rewards.py` (source unique du barème), jamais dupliquées. `kind` ∈ {`percent`, `range`, `grant`} pilote le seul FORMATAGE ; un `kind` inconnu d'un client ancien retombe sur le libellé seul. **Ajouter un tier ici le fait apparaître au client SANS modification cliente.**
- **`granted_items`** = inventaire ∩ articles `purchasable == false` (par construction, ils ne s'obtiennent QUE par le Pass). Rendu client **générique par `category`** (clé `SHOP_CAT_<CATEGORY>`) → le jour où un Pass offrira une FACTION, la ligne s'affiche sans une ligne de code de plus.
- **`gains`** = MESURE RÉELLE, pas une estimation : compteurs incrémentés au point exact où chaque avantage s'applique. Les deux premiers sont **DIFFÉRENTIELS** (le « en plus » dû au Pass) ; `hero_coins_with_pass_total` est un **TOTAL** (le barème premium étant un tirage aléatoire, le « sans Pass » correspondant n'existe pas et serait une invention). ⚠️ Mesure démarrée à §8.106 → un Pass acheté avant affiche 0 (le client l'explicite, `PASS_GAINS_NOTE`).

- **Consommé par :** `scripts/ui/profile.gd` (hub à onglets §8.106) et, pour `/profile/history` non filtré uniquement, `main_menu.gd` + `top_nav.gd`.

### 9.2. R3 — Classement mondial — `GET /leaderboard?limit=50&offset=0` ✅ LIVRÉ & ALIGNÉ
Tri **serveur** par **victoires décroissantes** (départage par **niveau** desc, puis **points de classement** desc, puis **id** asc → rang déterministe et pagination cohérente). Pagination par `limit` (1–100, défaut 20) / `offset` (≥ 0). **PUBLIC** ; le bloc **`me`** n'est renseigné que si la requête porte un **token Bearer valide** (sinon `null` — l'endpoint reste accessible sans auth).
> ✅ **ÉCART RÉCONCILIÉ (décision : aligner le backend sur §9.2).** L'endpoint `GET /api/v1/leaderboard` (livré en §8.46) a été **réaligné** : tri par **victoires** (et non plus `points_classement`), **enveloppe `{entries, me}`**, **`offset`** ajouté, **rang global** par entrée, **bloc `me`** (auth optionnelle via `get_current_user_optional`). Chaque entrée porte **les deux jeux de clés** (canoniques `rank`/`level`/`wins` **et** historiques `niveau`/`stats_victoires`/…) → rétro-compatible. *(Implémenté dans `leaderboard.py` + `models/schemas.py` ; schéma résumé en §F.)*
```jsonc
{
  "entries": [
    // Clés CANONIQUES + alias historiques (cf. §F). Triées, rang global 1-based (offset inclus).
    { "rank": 1, "username": "RAVAGEUR_PRIME", "level": 58, "wins": 412,
      "niveau": 58, "stats_victoires": 412, "stats_parties_jouees": 500, "points_classement": 9001 }
  ],
  "me": { "rank": 137, "username": "HAKIM", "level": 23, "wins": 118 }  // null si non authentifié
}
```
- **Consommé par :** `scripts/ui/leaderboard.gd`. Quand le serveur répond avec des rangs (forme §9.2), le client **respecte l'ordre et les rangs serveur** et surligne le joueur courant (ajouté en bas via `me` s'il est hors page). Repli **mock/legacy** : tant que le serveur est muet/hors-ligne **ou** sur l'ancienne forme « liste plate » (avant redéploiement VPS), le client trie/range côté client. Clés `wins`/`level` = mêmes alias qu'en §9.1. *(Détail mock : §8.41.)*

### 9.3. R1 — Boutique / Inventaire / Économie
- **`GET /shop/catalog`** → `Array<ShopItem>` (PUBLIC ; catalogue **persistant** en base `shop_items`, **seedé au démarrage** depuis `api/game/shop_catalog.py`). **§8.102 : paramètre optionnel `?include_all=1`** → renvoie AUSSI les articles `purchasable=false` (skins exclusifs de saison) — le client n'affiche ces articles que **possédés**, sans CTA d'achat. Sans le paramètre : filtre `purchasable == True` historique (rétro-compat des clients déployés ; un serveur ANTÉRIEUR ignore simplement le paramètre) :
```jsonc
{
  "id": "corporation_aegis",            // string — id snake_case (clé d'inventaire / d'achat)
  "category": "faction",                // string — "faction" | "skin" | "pass" | "currency"
  "price": 5000,                        // int — Coins si currency_type=virtual ; CENTIMES € si fiat
  "name_key": "SHOP_ITEM_AEGIS_NAME",   // string — CLÉ i18n (R4)
  "desc_key": "SHOP_ITEM_AEGIS_DESC",   // string — CLÉ i18n (R4)
  "currency_type": "virtual",           // string — "virtual" (Coins) | "fiat" (argent réel)
  "grant_amount": null,                 // int|null — Coins crédités par un pack 'currency' fiat
  "hero_key": null,                     // string|null — id de faction liée à un 'skin'
  "purchasable": true,                  // bool (§8.102) — false = retiré de la vente (skin de saison)
  // --- §8.108 : enrichissement à la volée des SEULS articles category == "pass" ---
  "tier": "",                           // string — "season" DEPUIS §8.147 ("" hors Pass).
                                        //   Valeurs HISTORIQUES "plus"|"premium"|"infinity" : plus
                                        //   jamais servies (leurs articles sont purchasable:false).
  "rank": 0,                            // int — 1 (unique niveau) ; 0 hors Pass. Champ CONSERVÉ
                                        //   bien qu'il ne départage plus rien (cf. §8.147)
  "perk_keys": []                       // string[] — CLÉS i18n ORDONNÉES des avantages du niveau
}
```
> **§8.147 — LE PASS UNIQUE.** Un seul article de Pass est vendu : **`pass_season`, FIAT, `price: 1999`** (19,99 €), `tier: "season"`, `rank: 1`, **10 `perk_keys`** (`SHOP_PASS_SEASON_PERK_1` … `_10`). `pass_plus` / `pass_premium` / `pass_infinity` passent **`purchasable: false`** et **RESTENT au catalogue** — le seed est un upsert qui ne supprime JAMAIS une ligne orpheline, les effacer du code les laisserait **EN VENTE en base** (précédent `special_pass`). Ils ne remontent donc que via `?include_all=1`, sans CTA. **La liste des Pass reste une LISTE** : elle n'a plus qu'un élément, un client qui itère ne casse pas (§1.5).

> **§8.108 — prix en vigueur.** Personnages **10 000 / 10 500 / 11 000 / 12 000** Coins ; skins **1 200-1 500** (UN par personnage, les 10 sont couverts) ; **3 Pass FIAT** `pass_plus` 799 ¢, `pass_premium` 1299 ¢, `pass_infinity` 1999 ¢ ; packs de Coins **5 000 / 12 000 / 25 000 / 80 000** (prix € inchangés). L'ancien `special_pass` (7 500 Coins) est **retiré de la vente** (`purchasable=false`) mais **conservé au catalogue** — le seed ne supprime jamais une ligne orpheline, l'effacer du module le laisserait en vente en base.

- **`GET /shop/rotation`** → `{ "week_key": "2026-W29", "free_faction_ids": ["ordre_eclipse"], "rotates_at": iso Z, "free_games_max": 5, "free_games_used": 2, "free_games_left": 3 }`. **PUBLIC mais à AUTH OPTIONNELLE (§8.109)** (`get_current_user_optional`, patron du leaderboard — jamais de 401) : `free_games_max` est TOUJOURS présent ; `free_games_used`/`free_games_left` **seulement si authentifié**. ⚠️ `free_faction_ids` reste une **LISTE** bien qu'elle n'ait plus qu'**UN** élément (`ROTATION_COUNT = 1`) — la forme du contrat est inchangée.
- **`GET /shop/inventory`** → `{ "credits": 2500, "items": { "skin_aegis_obsidienne": 1 }, "has_active_pass": false, "pass_expires_at": null, "payments_enabled": false, "pass_tier": "", "pass_faction_grants": [] }` (`credits: int` ; `items` = `{ "<item_id:str>": int }` = factions/skins possédés ; `has_active_pass: bool` **dérivé** de `User.special_pass_expires_at` ; `pass_expires_at: str|null` = date ISO 8601 d'expiration du Pass si actif, sinon `null` → le client en dérive les jours restants ; **`payments_enabled: bool` (§8.102)** = miroir de `PAYMENTS_ENABLED` (gate C3) → `false` = le client affiche les packs de Coins « BIENTÔT DISPONIBLE » au lieu d'un achat voué au 501 ; champ ABSENT (serveur antérieur) = le client conserve son défaut `false` ; **`pass_tier: str` (§8.108)** = niveau DÉTENU (`""` si aucun Pass actif — vaut `"premium"` pour un détenteur de l'ANCIEN Pass Spécial, cf. mapping legacy §8.108) ; **`pass_faction_grants: string[]` (§8.108)** = personnages débloqués par le Pass pour la SAISON COURANTE, `[]` sinon). Authentifié.
  > **§8.147 — deux mises à jour.** (1) **`pass_tier` vaut `"season"` pour TOUT Pass actif**, y compris celui d'un ancien détenteur de Plus / Premium / Infinity / Pass Spécial — la mention « vaut `"premium"` pour l'ANCIEN Pass Spécial » ci-dessus est **CADUQUE** (collapse par LECTURE, `pass_catalog.tier_of`, aucune migration de données). (2) Champ **ADDITIF `skin_access: { "<skin_id>": "owned" | "pass" }`** — titre d'accès de chaque skin du CATALOGUE. ⚠️ **Les skins `locked` sont OMISES : leur absence EST le verrou** (et la réponse reste courte). `owned` = ligne d'inventaire, DÉFINITIF ; `pass` = prêt temporaire du Pass. `items` reste la vérité de la POSSESSION — un client antérieur ignore `skin_access` et retombe dessus. ⚠️ **`GET /shop/inventory` est un SITE DE PURGE PARESSEUSE** : la lecture supprime la ligne `EquippedSkin` d'une skin retombée `locked` (cf. §8.147).
- **`POST /shop/purchase/virtual`** payload `{ "item_id": "corporation_aegis" }` → achat en **Coins** (faction/skin = **définitif**). Succès `{ "credits", "items", "has_active_pass", "pass_expires_at" }` ; échec HTTP 400 (« Crédits insuffisants » / « Article déjà acquis » / « Cet article s'achète en argent réel » / « Article inconnu » / **« Article non disponible à l'achat » (§8.102 — CORRECTIF SÉCURITÉ : un article `purchasable=False` était achetable par POST direct, les skins de saison prix 0 étaient donc gratuits ; même garde sur la route fiat)** / **« Ce skin nécessite de posséder le personnage. » (§8.108 — GATE SKINS : un accès TEMPORAIRE, rotation ou Pass, ne permet PAS d'acheter le skin d'un personnage qu'on va perdre ; seule une possession DÉFINITIVE, gratuite ou achetée, l'autorise)**). Authentifié.
- **`POST /shop/purchase/fiat`** payload `{ "item_id": "coins_pack_small" }` → achat en **argent réel** : packs « currency » (crédite `grant_amount` Coins) **ou, depuis §8.108, l'un des 3 Pass** (pose le niveau — aucun Coin crédité). ⚠️ **GATE C3 : la route entière renvoie HTTP 501 tant que `PAYMENTS_ENABLED` est faux** — les 3 Pass sont donc **visibles mais inachetables** aujourd'hui (décision produit assumée ; le client affiche « BIENTÔT DISPONIBLE » plutôt qu'un achat voué à l'échec). Succès `{ "credits", "items", "has_active_pass", "pass_expires_at" }` ; échecs HTTP 501 (paiements fermés) / 400 (« Article inconnu » / « Cet article s'achète en Coins » / **« Pass déjà actif de niveau supérieur ou égal »** — on ne peut qu'**MONTER** de niveau, jamais rétrograder ni racheter le même). Authentifié.
  > **§8.147.** « L'un des 3 Pass » devient **le Pass unique `pass_season`** (1999 ¢). Le message d'erreur « Pass déjà actif de niveau supérieur ou égal » est **CONSERVÉ AU CARACTÈRE PRÈS** (le client l'affiche tel quel, deux suites le lisent), mais sa portée change : à registre à UN niveau, `rank(season) <= rank(season)` est vrai dès qu'un Pass court — **ce refus n'est pas devenu inatteignable, il est devenu LE SEUL**. La branche UPGRADE (§8.108 §2.10) n'a plus de chemin d'accès ; acheter par-dessus un Pass actif est refusé, ce qui interdit la double dépense et l'allongement déguisé d'un abonnement. **Le gate 501 est INCHANGÉ** : le Pass reste visible et inachetable tant que `PAYMENTS_ENABLED` est faux.
- **`POST /shop/purchase`** — **ALIAS DÉPRÉCIÉ** de `/purchase/virtual` (rétro-compat des clients antérieurs au split virtual/fiat).
- **Consommé par :** `scripts/ui/shop.gd` (`_catalog` / `_owned` / `_credits` / `_has_active_pass` / `_payments_enabled` — **boutique à 4 onglets de catégorie §8.102**, inventaire fusionné) + `scripts/managers/network_manager.gd` (`fetch_shop_catalog` = `?include_all=1`, `purchase_item_virtual` / `purchase_item_fiat`). Le client résout `name_key`/`desc_key`/`SHOP_CAT_<CATEGORY>` via `tr()` (R4) et choisit la route d'achat selon `currency_type`.

> **Aucune de ces données n'est sensible** (pas de redaction par destinataire, §4.4) ni temps-réel (REST simple, pas de WS). **Priorité suggérée :** §9.1 (débloque R2 **et** R3) → §9.2 → §9.3.

### 8.64 (lot G6 — PLAN_EVOLUTIONS). Télémétrie d'équilibrage — tables match_records/match_participants + endpoint public stats/factions (Backend, 2026-07-14)
> ⚠️ **Numérotation :** les §8.62-§8.72 « réservés » par `PLAN_EVOLUTIONS.md` entrent en collision avec des entrées historiques (§8.62/§8.63 de CE fichier, §8.62-§8.68 de `FRONTEND_INTERFACES.md`). Les entrées issues du plan portent le suffixe « (lot XX — PLAN_EVOLUTIONS) » pour rester traçables sans renuméroter le plan.
> **But (G6).** Impossible d'équilibrer 10 factions asymétriques (ni de justifier les prix boutique) sans données : chaque **fin de partie** persiste désormais 1 enregistrement de match + 1 par participant, et un agrégat public expose le **win-rate par faction**. **La télémétrie ne fait JAMAIS échouer une fin de partie** (no-raise par contrat, doublé d'un try/except au call-site). **Backend → push + redéploiement VPS requis (§1).**

- **2 tables neuves (`models/models.py`, créées par `create_all`) :**
  - **`match_records`** : `room_id`, `map_id` (défaut `classic_42` — prêt pour le registre multi-cartes G5), `ended_at` (idx), `duration_turns`, `winner_user_id` (**NULL si vainqueur bot**), `match_type` (`"objective"|"elimination"`, même dérivation que le broadcast `game_over`), `human_count`, `bot_count`.
  - **`match_participants`** : `match_id` FK→`match_records` (idx), `user_id` (**NULL pour un bot** — pas de FK vers users, volontaire), `is_bot`, `faction_id` (idx), `hero_level_start`, `rank` (0 = 1ᵉʳ, ordre `rewards.rank_players` = celui du broadcast), `is_winner`, `objective_type`, `objective_completed`, `units_killed` (= `enemy_kills`), `units_lost` (combat + zone), `eliminations`, `territories_final`.
- **NOUVEAU [`api/game/telemetry.py`](backend/api/game/telemetry.py)** : `record_match(db, state, match_stats, rankings)` — construit les lignes depuis `GameState` + `GameEngine.build_match_stats` + `rank_players` ; **avale TOUTE exception** (log + rollback, no-raise). Appelé dans **`router.py::_finalize_if_over`** juste après `process_match_results`, **session dédiée** + try/except intégral (une panne télémétrie n'affecte jamais un `game_over`).
- **NOUVEAU endpoint `GET /api/v1/stats/factions`** ([`api/v1/endpoints/stats.py`](backend/api/v1/endpoints/stats.py), **PUBLIC**, enregistré comme `leaderboard.py`) : paramètres `?map_id=` (vide = toutes) `&days=30` (clamp 1-365). Réponse `{ "sample_matches": int, "since": "YYYY-MM-DD", "factions": [ { "faction_id", "picks", "wins", "win_rate", "avg_rank" } ] }`, triée win_rate desc (départage picks desc, id asc). **Bots EXCLUS de l'agrégat** (`is_bot == False`). ⚠️ Les floats de CET endpoint sont assumés (statistiques, pas un état de jeu) — arrondis 3 décimales.
- **Validation.** `py_compile` OK ; **NOUVEAU `backend/test_telemetry.py`** (fake Session, moteur réel) : **31 ✅ / 0 ❌** — lignes fidèles (rangs, bots user_id NULL, compteurs, objectifs, vainqueur bot → NULL), garantie no-raise (session empoisonnée + match_stats corrompu), post-traitement pur de l'agrégat (`build_faction_stats` : arrondis, tri, zéro-division). Frontend : rien en v1 (extension future notée : onglet « Intel Global » du classement).

### 8.65 (lot M2 — PLAN_EVOLUTIONS). Missions quotidiennes & hebdomadaires — robinet de Coins serveur (Backend + Frontend, 2026-07-14)
> **But (M2).** Le robinet Coins (~100/10 niveaux) rendait une faction payante inatteignable. Cible : **~100 Coins/jour (1 fixe + 3 tirées × 25) + 300/semaine (3 × 100)** → première faction en ~6-10 semaines gratuites. **Progression 100 % SERVEUR** (compteurs `GameStatistics`, jamais confiance au client). **Backend → push + redéploiement VPS requis (§1).**

- **Catalogue** : [`api/game/missions_catalog.py`](backend/api/game/missions_catalog.py) (source de vérité code, pattern shop_catalog) — `DAILY_FIXED` (première victoire, 25), `DAILY_POOL` (7 candidates, 25 chacune), `WEEKLY_POOL` (6, 100 chacune) ; clés i18n `MISSION_*`. Nouveau compteur `GameStatistics.cards_played_by_player` (défaut rétro-compat Redis), incrémenté dans `engine._handle_play_card` et exposé par `build_match_stats` (clé `cards_played`).
- **Table `user_missions`** (`models.py`, `create_all`) : SNAPSHOT (metric/target/reward copiés à l'assignation), contrainte **UNIQUE(user_id, mission_id, period_key)**.
- **Périodes** ([`api/game/missions_progress.py`](backend/api/game/missions_progress.py)) : jour = date UTC de `now−4h` (reset **04:00 UTC**, `"2026-07-07"`), semaine = ISO de `now−4h` (bascule **lundi 04:00 UTC**, `"2026-W28"`). ⚠️ MÊME convention pour M3/M4/M6 (piège transverse n° 7). **Assignation lazy déterministe** au 1ᵉʳ `GET /missions` de la période : `random.Random(f"{user_id}:{period_key}")` → re-appeler ne re-tire JAMAIS (anti-reroll) ; course absorbée par la contrainte UNIQUE (rollback).
- **Progression** : `apply_match(db, per_player_aggregates)` appelé dans `router._finalize_if_over` (try/except intégral, session dédiée — même pattern que la télémétrie G6). `build_match_aggregates(match_stats, rankings)` construit les deltas PAR HUMAIN (`matches_played/won`, `top2_finishes`, `units_killed`, `territories_conquered`, `players_eliminated`, `hero_damage`, `cards_played`) — **bots (ids < 0) JAMAIS crédités**. `progress = min(target, progress+delta)` ; mission réclamée = FIGÉE.
- **Endpoints** ([`api/v1/endpoints/missions.py`](backend/api/v1/endpoints/missions.py), authentifiés, préfixe `/api/v1/missions`) :
  - **`GET /missions`** → `{ "daily": [ { mission_id, mission_type, name_key, desc_key, progress, target, reward_coins, completed, claimed } ], "weekly": [...], "daily_resets_at": iso Z, "weekly_resets_at": iso Z, "claimable_count": int }` — TOUT en int/bool/string (aucun float §5).
  - **`POST /missions/claim`** `{ "mission_id" }` : row lock `with_for_update` sur la mission + `_lock_user` (pattern shop) ; refus 400 (« Mission inconnue » / « Mission non terminée » / « Déjà réclamée ») ; **bonus Pass ×1.5 floor** (`rewards.PASS_MISSION_COINS_MULT`, M4) ; réponse `{ "coins_balance", "reward_paid", "pass_bonus_applied" }`. Idempotent sous verrou.
- **Frontend** : écran **OPÉRATIONS** (`scenes/ui/missions.tscn` + `scripts/ui/missions.gd` — l'ex-maquette mock est BRANCHÉE au réel : sections quotidiennes/hebdos, ProgressBar cyan→or, bouton RÉCLAMER or, comptes à rebours de reset, statut claim/erreur, re-fetch après claim) ; `network_manager.gd` : `fetch_missions()` / `claim_mission(id)` + signaux `missions_loaded` / `mission_claimed` / `mission_claim_failed` ; `main_menu` : **onglet « OPÉRATIONS »** (`missions_tab`, entre BOUTIQUE et CLASSEMENT) avec **pastille or « ●N »** = `claimable_count` (rafraîchie à chaque retour menu + locale) ; **44 clés i18n** `MISSION*` ajoutées (fr/en/it).
- **Validation.** `py_compile` OK ; **NOUVEAU `backend/test_missions.py`** : **41 ✅ / 0 ❌** (bascules 03:59/04:01, déterminisme/idempotence, snapshot, agrégats depuis un VRAI `build_match_stats`, bots exclus, plafonnement/figeage, claim refus/crédit/idempotent, Pass ×1.5 floor 25→37 & 100→150, payloads sans float). Frontend : `--import` + boot headless `main_menu.tscn` ET `missions.tscn` = 0 ERROR.

### 8.66 (lot M3 — PLAN_EVOLUTIONS). Rotation gratuite hebdomadaire des factions payantes + enforcement serveur du draft (Backend + Frontend, 2026-07-14)
> ⚠️ **PARTIELLEMENT SUPERSÉDÉ PAR §8.109** (2026-07-19) : la rotation offre désormais **UN** personnage (et non une paire), pour un **crédit de 5 parties** par semaine, et la progression du héros acquise à ce titre est **purgée** à la fin de l'accès. L'enforcement du draft ne passe plus par `_owns_faction` (supprimé) mais par `api/game/access.py`. **Lire §8.109 pour l'état courant** ; ce qui suit décrit le modèle d'origine.
> **But (M3).** Modèle LoL : chaque semaine, **2 des 4 factions payantes** sont jouables gratuitement (neutralise le pay-to-win perçu, fait essayer, donne envie d'acheter). Et surtout : **le serveur devient la SOURCE D'AUTORITÉ sur qui peut jouer quoi** — l'ancien `_handle_faction_choice` ne validait que l'existence de la faction. **Backend → push + redéploiement VPS requis (§1).** Dépend de M1-C2 (l'identité WS est vérifiée, donc `pid` est fiable au draft).

- **NOUVEAU [`api/game/rotation.py`](backend/api/game/rotation.py)** (pur, sans DB) : `PAID_FACTION_IDS` **dérivé** de `shop_catalog.py` (catégorie "faction" — aucune liste dupliquée ; lecture défensive `getattr` → les suites qui stubbent le catalogue retombent sur « aucune payante ») ; `FREE_FACTION_IDS = FACTIONS − payantes` (6). `current_rotation(now)` : les C(4,2)=6 paires énumérées sur `sorted(PAID_FACTION_IDS)`, index = `SHA-256(week_key) % 6` → `{ "week_key": "2026-W29", "free_faction_ids": [id, id], "rotates_at": iso Z }`. **Semaine = MÊME convention que M2** (réutilise `missions_progress.mission_week_key`/`weekly_resets_at` — bascule lundi 04:00 UTC, jamais une 2ᵉ convention). Déterministe sur tous les workers, zéro état. ⚠️ Mesuré : l'index SHA-256 couvre les 6 paires en **19 semaines** (pas 12) — la variété est au rendez-vous mais pas un cycle parfait (assumé, spec du plan conservée).
- **NOUVEAU endpoint `GET /api/v1/shop/rotation`** (PUBLIC, dans `shop.py`) → le dict ci-dessus tel quel.
- **Enforcement du draft (`router.py::_handle_faction_choice`)** : après le contrôle `faction_id in FACTIONS`, une PAYANTE choisie par un HUMAIN (`pid > 0`) n'est appliquée que si **en rotation** (pur, prioritaire — zéro DB) **ou possédée** (`_owns_faction` : `inventory_items` quantité > 0, session courte pattern `_load_hero_progress`, FAIL-CLOSED sur panne DB). Sinon : **erreur PRIVÉE** « Faction verrouillée — disponible en boutique ou en rotation. » et choix **NON appliqué** (aucune exception — le draft continue, le carrousel reste utilisable). Bots (`pid < 0`) : contrôle DB sauté (aucune ligne users ; `bot_ai` G2 ne pioche que des gratuites).
- **Garde moteur (`engine.create_initial_state`)** : la faction PROVISOIRE (pré-draft) est désormais TOUJOURS tirée de `FREE_FACTION_IDS` (l'ancien fallback sur `FACTION_IDS` pouvait poser une payante).
- **Frontend** : `network_manager.gd` — `fetch_shop_rotation()` + signal `shop_rotation_loaded(data)` (repli gracieux : rotation muette → aucun signal, comportement sûr). `faction_selection.gd` — charge **catalogue + inventaire + rotation** au `_ready` ; par carte payante : **possédée → normale**, **en rotation → bandeau or « ★ GRATUITE CETTE SEMAINE »**, **sinon → carte grisée + bandeau verrou avec prix + CONFIRMER désactivé (« 🔒 VERROUILLÉE — VOIR BOUTIQUE »)** ; double garde dans `_on_confirm_pressed`. `shop.gd` — **bannière or « ★ ROTATION DE LA SEMAINE : F1 · F2 »** au-dessus de la grille + **badge** sur les cartes faction concernées. 5 clés i18n ajoutées (fr/en/it).
- **Validation.** `py_compile` OK ; **NOUVEAU `backend/test_rotation.py`** : **18 ✅ / 0 ❌** (dérivation catalogue 4/6, déterminisme, bascule lundi 03:59/04:01, changement de paire, couverture 6 paires sur 26 semaines, garde moteur provisoire gratuite, matrice d'enforcement : gratuite ✔ / rotation ✔ / possédée ✔ / verrouillée ✘ erreur privée sans application / qty 0 ✘ / bot sauté ✔). Frontend : `--import` + boot headless `faction_selection.tscn` ET `shop.tscn` = 0 ERROR.

### 8.67 (lot M4 — PLAN_EVOLUTIONS). Saisons de 90 jours + Pass Spécial à valeur réelle (Backend + Frontend, 2026-07-14)
> ⚠️ **PARTIELLEMENT SUPERSÉDÉ PAR §8.108** (2026-07-19) : le Pass UNIQUE décrit ici est remplacé par **3 niveaux** (Plus / Premium / Infinity) vendus en **euros**, dont les multiplicateurs vivent dans `pass_catalog.PASS_TIERS`. Les constantes `PASS_*` de `rewards.py` citées plus bas sont **obsolètes** — elles restent définies parce qu'elles décrivent exactement le niveau `premium`, ce qui garantit qu'un détenteur de l'ancien Pass ne voit AUCUN changement (mapping legacy). Les SAISONS, elles, sont inchangées. **Lire §8.108 pour l'état courant.**
> **But (M4).** Le Pass à 7500 Coins n'offrait AUCUN bénéfice actif. Les **saisons de 90 jours** deviennent l'horloge du live service (Pass, divisions M6, skin exclusif), et le Pass reçoit **4 avantages concrets** immédiatement mesurables. **Backend → push + redéploiement VPS requis (§1).**

- **NOUVEAU [`api/game/seasons.py`](backend/api/game/seasons.py)** (pur, sans DB — fondation aussi utilisée par M6) : `SEASON_EPOCH = 2026-07-01 04:00 UTC` (aligné sur l'heure de reset commune), `SEASON_DAYS = 90`. `current_season(now)` → `{ "id": "S1", "index": 0, "starts_at": iso Z, "ends_at": iso Z }` (index clampé ≥ 0, déterministe tous workers). `current_season_end_dt()` → datetime **NAÏF UTC** (convention `special_pass_expires_at`). `season_skin(index)` → `{ "skin_id": "skin_pass_s<N>", "hero_key": vitrine }` avec `SEASON_VITRINE_ORDER` = factions **gratuites** (S1=phalanges_acier, S2=pillards_poussiere, wrap % 6).
- **Les 4 avantages du Pass** (constantes NOMMÉES dans `rewards.py`, jamais en dur) :
  1. **Coins héros ×~4** : `HERO_COINS_PASS_MIN/MAX = 10/20` — `hero_levelup_coins(levels, has_pass=True)` tire [10-20]/niveau au lieu de [1-5] (relayé par `credit_hero_xp(has_pass=)` depuis `process_match_results`). L'ex-« différé » de §8.61 est câblé.
  2. **+25 % d'XP de profil par match** : `PASS_XP_MULT = 1.25`, appliqué en **floor** dans `process_match_results` AVANT la courbe de niveaux → visible tel quel dans le Rapport Post-Op. `match_rewards[pid]` gagne **`pass_bonus_applied: bool`** (relais client).
  3. **+50 % de Coins missions** : `PASS_MISSION_COINS_MULT = 1.5` (déjà câblé au claim M2).
  4. **Skin exclusif de saison** : à l'achat du Pass, `skin_pass_s<N>` est crédité dans `inventory_items` (idempotent). Les skins `skin_pass_s*` sont seedés **`purchasable=False`, prix 0** → introuvables autrement (exclusivité réelle).
- **Boutique** : `ShopItem.purchasable` (bool, `server_default "true"`, auto-migré — archive SQL : `migration_seasons.sql`, livrée avec M6) ; **`GET /shop/catalog` filtre `purchasable == True`** ; seed normalisé (`_seed_value` : absent → True). **Branche pass de `_apply_virtual_purchase`** : (a) Pass actif → 400 « Pass déjà actif » (anti double-dépense) ; (b) `special_pass_expires_at = fin de la saison COURANTE` (REMPLACE le +90 j flottant — un achat tardif expire à la même date : assumé, documenté dans SHOP_ITEM_PASS_DESC) ; (c) skin saisonnier crédité. **`GET /shop/inventory`** : bloc **`"season": {"id", "ends_at"}`** (schéma `InventoryResponse.season`).
- **Frontend** : `shop.gd` — panneau Pass réécrit (4 avantages `SHOP_PASS_PERK_1..4`, mention skin saisonnier, compte à rebours `FIN DE SAISON {S} : J-{n}` dérivé du bloc season, badge ACTIF existant conservé) ; `operation_report.gd` — suffixe or discret « ★ +25 % XP — PASS SPÉCIAL ACTIF » si `pass_bonus_applied` (pur relais serveur). 10 clés i18n ajoutées + desc du Pass réécrite (saisonnier).
- **Validation.** `py_compile` OK ; **NOUVEAU `backend/test_seasons.py`** : **23 ✅ / 0 ❌** (bornes S1/S2 au 2026-09-29 03:59/04:01, clamp pré-époque, end_dt naïf, achat J89 → même saison, skins mapping/vitrines gratuites, catalogue purchasable, achat Pass : débit/expiration/skin/refus double/idempotence) ; `test_rewards.py` étendu (§8 Pass) : **131 ✅ / 0 ❌** (bornes [1,5] vs [10,20] par spy randint, XP floor(113×1.25)=141, flag relayé, Pass expiré = aucun bonus). Frontend : `--import` + boot `shop.tscn` et `operation_report.tscn` = 0 ERROR.

### 8.68 (lot M6 — PLAN_EVOLUTIONS). Divisions & classement SAISONNIER — reset lazy, scope leaderboard (Backend + Frontend, 2026-07-14)
> **But (M6).** Un ladder mondial unique démotive (être 4000ᵉ ne donne aucun objectif). Ajout : **points de saison** (remis à zéro tous les 90 j — module `seasons.py` de M4), **5 divisions à seuils fixes**, bascule **SAISON/GÉNÉRAL** dans l'écran classement. Reset **LAZY** (aucun cron — cohérent avec l'auto-migration au boot). **Backend → push + redéploiement VPS requis (§1).**

- **`models.User`** : `season_points` (int, NOT NULL, `server_default "0"`) + `season_id` (String, `server_default ""`) — auto-migrées ; **archive SQL : [`migration_seasons.sql`](backend/migration_seasons.sql)** (couvre aussi `shop_items.purchasable` de M4).
- **`seasons.py`** : `DIVISIONS = BRONZE 0 / ARGENT 500 / OR 1200 / PLATINE 2200 / ELITE 3500` (seuils fixes v1 ; top-% dynamique = extension notée) + `division_for(points)` (dernier seuil atteint, 499→BRONZE, 500→ARGENT…). **`ensure_season(user, now)`** : si `user.season_id != saison courante` → `season_points = 0`, `season_id` mis à jour ; renvoie True si reset (l'appelant committe). Appelé : (a) `process_match_results` AVANT crédit, (b) bloc `me` du leaderboard, (c) `/auth/me`. Idempotent, pas d'archive v1 (extension : table `season_history`).
- **Crédit DOUBLE** : `process_match_results` ajoute `match_points` à `points_classement` (à vie, existant) **ET** à `season_points`.
- **`GET /api/v1/leaderboard`** : paramètre **`scope=season|lifetime`** (défaut **season**). `season` → tri `season_points` desc (départage `stats_victoires` desc, `niveau` desc, `id` asc — déterminisme §9.2 conservé, `_SEASON_ORDER_BY` + `_season_rank_of` jumeaux des versions à vie) ; chaque entrée gagne `season_points` (int, NULL→0) + `division` (str, transitoire posé par la route) ; `me` idem (+ reset lazy committé au passage) ; réponse enrichie du bloc **`"season": {"id", "ends_at"}`**. `lifetime` → comportement historique §9.2 inchangé. **Toutes les clés historiques conservées** (rétro-compat).
- **`GET /auth/me`** : applique `ensure_season` (reset lazy au premier login post-bascule) et expose `season_points` (NULL→0) + **`division`** (computed_field dérivé — jamais persisté).
- **Frontend** : `network_manager.gd` — `fetch_leaderboard(limit, offset, scope="season")` + propriété `last_leaderboard_season` (le signal `leaderboard_loaded(entries, me)` garde sa signature pour le top-3 du menu). `leaderboard.gd` — **onglets SAISON/GÉNÉRAL** construits par code (défaut SAISON), **colonne DIVISION** (badge coloré : bronze `#cd7f32`, argent `#c0c0c0`, or charte, platine `#9adfea`, élite cyan) + points de saison par ligne, **statut « VOTRE DIVISION : X · FIN DE SAISON : J-N »** (bloc season) ; **repli legacy** : réponse sans `division` → onglets masqués, GÉNÉRAL seul (client défensif §9.2). `profile.gd` — cartes **DIVISION (SAISON)** + **POINTS DE SAISON** depuis `/auth/me`. 7 clés i18n ajoutées.
- **Validation.** `py_compile` OK ; `test_seasons.py` étendu (M6) : **29 ✅ / 0 ❌** (division_for aux bornes exactes, 5 seuils croissants, ensure_season no-op/reset/idempotent/init) ; `test_rewards.py` étendu : **135 ✅ / 0 ❌** (crédit DOUBLE lifetime+saison du même montant, season_id posé au 1ᵉʳ crédit, perdant aussi). Frontend : `--import` + boot headless `leaderboard.tscn`, `profile.tscn`, `main_menu.tscn` = 0 ERROR.

### 8.69 (lot M5 — PLAN_EVOLUTIONS). Skins équipables et VISIBLES — equip + PlayerState.equipped_skin (Backend + Frontend, 2026-07-14)
> **But (M5).** Des skins existaient au catalogue (`hero_key`) mais rien ne permettait de les équiper ni de les voir : un cosmétique invisible ne se vend pas. Moment vitrine = le **Split-Screen VS** (l'adversaire DOIT voir ton skin), secondairement le carrousel de draft. **Backend → push + redéploiement VPS requis (§1).**

- **Table `equipped_skins`** (`models.py`, `create_all`) : `user_id` FK idx, `faction_id`, `skin_id`, contrainte **UNIQUE(user_id, faction_id)** — un seul skin équipé par faction.
- **NOUVEAU `POST /api/v1/shop/equip`** (authentifié, `shop.py`) : `{ "skin_id": "<id>" }` (équipe — possession `inventory_items` + `category == "skin"` vérifiées, **`faction_id` DÉRIVÉ de `item.hero_key`** — on ne fait pas confiance au client) ou `{ "faction_id": "<id>", "skin_id": null }` (déséquipe). Upsert sous `_lock_user` + rejeu IntegrityError (course entre deux equips). Réponse = **inventaire complet** (forme `GET /shop/inventory`). Refus 400 : « Skin inconnu » / catégorie non-skin / « Skin non possédé » / déséquipement sans faction_id.
  > **§8.147 — le gate d'ÉQUIPEMENT s'assouplit, le gate d'ACHAT ne bouge pas.** « Skin non possédé » n'est plus prononcé que si `access.skin_access` rend **`locked`** : l'équipement accepte désormais `owned` **OU** `pass` (prêt temporaire du Pass unique). Le refus d'ACHAT « Ce skin nécessite de posséder le personnage » (§8.108) est **INCHANGÉ à un caractère près** — on n'achète toujours pas le cosmétique d'un personnage qu'on va perdre. Shape et code HTTP identiques.
- **`GET /shop/inventory`** : bloc **`"equipped": { "<faction_id>": "<skin_id>" }`** (schéma `InventoryResponse.equipped`, string→string).
- **État de partie** : **`PlayerState.equipped_skin: str = ""`** (PUBLIC — la Redaction ne masque que les objectifs §8.6 ; défaut → rétro-compat Redis). Posé au draft (`router._handle_faction_choice` via `_load_equipped_skin`, session courte fail-safe) ET à la voie REST `start_game` (requête `equipped_skins` par joueur). **Bots : toujours ""** (`_load_equipped_skin` court-circuite pid < 0).
- **Frontend — registre data-driven (pattern factions §4.3)** : **NOUVEAU `resources/skins/skin_data.gd`** (`class_name SkinData` : id = ShopItem.id, faction_id, name_key, portrait_path, model_path, accent_override) + **5 `.tres`** (skins du catalogue + `skin_pass_s1`) en **placeholders teintés** (chemins vides → ColorRect `accent_override`, convention §4.3). `split_screen_vs.gd::_load_faction(faction_id, fallback, equipped_skin="")` — surcharge portrait/modèle (si les chemins EXISTENT) + accent ; les skins des DEUX camps passent par `meta.attacker_skin/defender_skin` (lus des PlayerState publics par `main.gd::_equipped_skin_of`). `faction_selection.gd::_set_portrait` — même résolution pour SON skin équipé (bloc `equipped` de l'inventaire, déjà chargé par M3). ⚠️ Le panneau héros du HUD (§8.60) n'affiche AUCUN portrait (barres de stats seules) — rien à skinner là. `shop.gd` — bouton **ÉQUIPER (or) / ÉQUIPÉ ✓** sur les skins possédés (boutique ET inventaire) via `NetworkManager.equip_skin/unequip_skin` + signaux `skin_equipped`/`skin_equip_failed` (la réponse étant un inventaire complet, le handler d'inventaire est réutilisé). 3 clés i18n ajoutées.
- **Validation.** `py_compile` OK ; **NOUVEAU `backend/test_equip.py`** : **16 ✅ / 0 ❌** (matrice equip complète, remplacer = UPDATE unique par faction, déséquiper, `equipped_skin` posé voie REST / défaut / bot vide, PRÉSENT dans l'état diffusé et NON masqué par la redaction, rétro-compat legacy). Frontend : `--import` + boot headless `shop`, `faction_selection`, `main`, `split_screen_vs` = 0 ERROR.

### 8.71 (lot G5 — PLAN_EVOLUTIONS). Carte réduite « Théâtre Atlantique » — registre multi-cartes data-driven (Backend + Frontend, 2026-07-14)
> **But (G5).** Une 2ᵉ carte SANS nouvel asset : sous-ensemble CONNEXE de la carte 42 — **NA (9) + SA (4) + EU (7) = 20 territoires**, DÉRIVÉ programmatiquement (voisins intersectés, aucune duplication). Parties ~20-30 min, 3-4 joueurs. **Backend → push + redéploiement VPS requis (§1).**

- **`api/game/map_data.py` — registre `MAPS`** : `classic_42` (alias module-level intacts, AUCUN import ne casse) + `skirmish_atlantic` (dérivée par `_derive_submap` — noms/bonus de continents conservés : NA +5, SA +2, EU +5 ; ponts `central_america↔venezuela` et `greenland↔iceland` conservés, arêtes vers Asie/Afrique coupées). Chaque entrée porte `label`, `territories`, `continents`, `continent_territories`, `min/max_players`, **`initial_troops`** (classic {3:35,4:30,5:25,6:20} ; skirmish {3:18,4:15}). `get_map(map_id)` (repli défensif classic) ; `are_adjacent`/`neighbors_of`/`continent_of`/`territories_in_continent` gagnent `map_id="classic_42"`. **Intégrité par carte au chargement** : symétrie + connexité BFS (couverture 42 ET 20).
- **`state_schemas.py`** : `GameState.map_id: str = "classic_42"` (défaut → rétro-compat Redis prouvée par test). **`objectives.py`** : `OBJECTIVE_PARAMS_BY_MAP` (classic : conquer 24 / continents 2 ; skirmish : conquer 12 / continents 2 sur 3) ; `assign_objectives(player_ids, map_id)` — les objectifs doubles §8.61 suivent automatiquement.
- **`engine.py` map-aware** : `create_initial_state(room_id, players_data, map_id)` (distribution sur les territoires DE LA CARTE, dotation par carte, refus d'un effectif hors bornes) ; `_check_victory`/`build_match_stats`/`_credit_continent_conquests`/`_calculate_reinforcements` itèrent les continents de `get_map(state.map_id)` ; `_handle_attack`/`_handle_move_units` valident l'adjacence PAR CARTE (une attaque `brazil→north_africa` est REFUSÉE sur skirmish) ; `_has_friendly_path` (Éveillés) borne son BFS au sous-graphe ; **la zone radioactive tire ses blocs (courant ET télégraphe G1) dans les territoires de la partie** — jamais hors-carte. Cartes Évènement / Time Bank inchangées.
- **Lobby & modèle** : `GameRoom.map_id` (String, `server_default "classic_42"`, auto-migrée) ; `GameRoomCreate.map_id` ; **`POST /lobby/rooms`** valide `map_id in MAPS` (400 « Carte inconnue ») et **clampe `max_players` aux bornes de la carte** (skirmish → 3-4) ; **`GET /lobby/rooms`** expose `map_id` + `map_label` (attribut transitoire, NULL→défauts par validateurs). `router._try_start_game` lit la carte de la salle (`_room_map_id`, session courte fail-safe) → dotation par carte + garde défensive (effectif hors dotation → pas de démarrage) ; la voie REST `start_game` borne l'effectif par carte et propage `map_id`. La télémétrie G6 enregistre désormais le vrai `map_id`.
- **Frontend** : `game_state.gd.map_id` (posé à chaque état, défaut classic) ; **`map_data.gd` — miroir du registre** (`MAP_DEFS` + dérivation cachée `get_map`/`map_territories`/`map_label`, `are_adjacent`/`neighbors_of` map-aware à défaut classic) ; `board.gd::generate_board` **masque les territoires hors carte** (`visible=false`, `input_pickable=false`, badge masqué/ré-affiché au retour) et calcule le **rect englobant des actifs** (`get_active_map_rect`, vide sur carte complète) ; `tactical_camera.gd::set_board_rect` — la vue « plein plateau », le retour de combat ET les bornes pan/zoom (observateur G3) suivent ce cadre (marge 90 px ; **cadrage classic inchangé**) ; `main.gd` : adjacences du clic/survol (`are_adjacent(..., GameState.map_id)`) + recadrage à chaque refresh ; `lobby_screen.gd` : **OptionButton « CARTE »** construit par code au-dessus de « CRÉER UNE OPÉRATION » (classique / Atlantique), effectif de création clampé aux bornes de la carte, **label de carte** sur chaque ligne du radar (serveur `map_label`, repli miroir local). 3 clés i18n.
- **Validation.** `py_compile` OK ; **NOUVEAU `backend/test_map_registry.py`** : **28 ✅ / 0 ❌** (dérivation 20/9+4+7, symétrie, ponts/coupures, connexité BFS, non-régression classic + alias intacts, get_map défensif, objectifs 24/12, simulation moteur skirmish : état 20 territoires, zone en-carte 20 rounds télégraphe compris, attaque hors-carte refusée / en-carte acceptée, renforts SA +2, victoire à 12, rétro-compat legacy sans map_id) ; suite complète backend verte. Frontend : `--import` + boot headless `lobby_screen`, `main`, `main_menu` = 0 ERROR.

### 8.72 (lot G2 — PLAN_EVOLUTIONS). Bots de remplissage — IA de tour serveur + fill lobby (Backend + Frontend, 2026-07-14)
> **But (G2).** Jeu 100 % multi, minimum 3 joueurs → sans liquidité, aucune partie ne démarre. v1 : une salle avec ≥ 1 humain prêt et < 3 joueurs est COMPLÉTÉE À 3 par des bots qui jouent toute la partie côté serveur. **Hors scope v1** (extensions notées) : remplacement d'un déconnecté par un bot, difficultés d'IA. **Backend → push + redéploiement VPS requis (§1).**

- **Identité des bots (conventions strictes)** : `player_id` **NÉGATIF** (-1, -2, … — jamais en collision avec `User.id`, AUCUNE ligne `users`) ; `PlayerState.is_bot: bool = False` (PUBLIC, défaut rétro-compat) ; `username` = indicatif de `BOT_CALLSIGNS` (`bot_ai.callsign_for`). **Aucune persistance** : `process_match_results` saute les ids < 0 (entrée neutre pour le broadcast, aucune requête DB) ; `router._lookup_username` renvoie l'indicatif sans DB pour un id < 0.
- **NOUVEAU [`api/game/bot_ai.py`](backend/api/game/bot_ai.py)** (PUR — state in → décision out, aucun Redis/DB) : `decide_faction` (aléatoire parmi `FREE_FACTION_IDS` — jamais une payante, cohérent M3) ; `decide_blind_deploy` (répartit tout le stock, pondéré `1 + voisins non-alliés` — frontières renforcées) ; `next_action(state, pid, attacks_made)` — machine d'états par phase : états bloquants d'abord (conquer « tout sauf 1 » / eclipse « carte max » / spy « cible vivante »), phases 1-2 (jouer les cartes puis déployer sur le territoire le plus menacé), phase 3 (attaque tant que `garnison_src-1 ≥ garnison_cible+1`, source par surplus max, **plafond 12**), phase 4 (1 mouvement intérieur→frontière faible), sinon `pass_turn` avec `from_phase` (anti double-avance §8.48).
- **NOUVEAU [`api/sockets/bot_runner.py`](backend/api/sockets/bot_runner.py)** (orchestration réseau, séparée de l'IA pure — comme RoomTimers) : `ensure_bots_play(room_id)` (idempotent, point d'entrée unique appelé par `_arm_next_timer` quand le joueur courant devient un bot) → task qui, SOUS le verrou de salle, fait jouer le bot toutes les **`BOT_ACTION_DELAY` = 1.0 s** (lisibilité), applique via `GameEngine.process_action`, sauvegarde, rediffuse (MÊME State Redaction), finalise ; sort dès qu'un humain reprend la main. `submit_bot_blind_deploys` (Phase 0 : les bots déploient immédiatement, les humains gardent 90 s). `cancel_room_bots` (fin de partie / salle détruite).
- **Minuteries** : `_arm_next_timer` — si `current_player_id < 0` → `ensure_bots_play` **ET rebours standard conservé en « watchdog »** (durci 2026-07-14, cf. encart ci-dessous ; l'ancien « pas de rebours pour un bot » laissait la salle gelée à vie si la task bot mourait). Broadcast : `broadcast_state_to_room` saute les destinataires sans socket (bots).
- **Remplissage lobby (`router.py`)** : config `BOT_FILL_ENABLED=True`, `BOT_FILL_TIMEOUT_S=60` (`.env`). `_maybe_arm_bot_fill` (armé/annulé à chaque changement de composition : ready/unready, arrivée, départ) → à expiration, `_bot_fill_after` complète `manager.players` à 3 avec des bots (ids négatifs, socket None, marqués prêts) et lance `_try_start_game` (qui pose `is_bot`, drafte les bots via `_draft_bots`, puis soumet leur Phase 0). **`lobby_state` gagne `bot_fill_at`** (timestamp UNIX s | null).
- **Frontend** (transparent — les bots n'ont pas de socket) : `waiting_room.gd` — préfixe **« 🤖 [IA] »** sur les bots + **compte à rebours « REMPLISSAGE IA DANS Xs »** (propriété `NetworkManager.last_bot_fill_at`, le signal `lobby_state_updated` garde sa signature) ; `main.gd::_display_name` / `hud.gd::update_display` — préfixe **« [IA] »** (id négatif ou `is_bot` public). 1 clé i18n.
- **Validation.** `py_compile` OK ; **NOUVEAU `backend/test_bot_ai.py`** : **18 ✅ / 0 ❌** — **partie complète 3 bots sur le moteur réel se termine (victoire/cap 200 tours) SANS aucune action rejetée**, `decide_blind_deploy` épuise exactement le stock sur ses seuls territoires, états bloquants toujours résolus, plafond 12 attaques, `process_match_results` sans AUCUNE requête/persistance pour un id < 0. Suite backend complète verte (25 suites). Frontend : `--import` + boot headless `waiting_room`, `main`, `lobby_screen` = 0 ERROR.

> **🔧 DURCISSEMENT G2 (2026-07-14) — « parcours joueur » complet des bots, 5 blocages corrigés.** Audit de bout en bout de la chaîne lobby → draft → Phase 0 → tours :
> 1. **Auto-démarrage du fill réparé** : `_bot_fill_after` s'AUTO-annulait (`_cancel_bot_fill` sur sa propre task → `CancelledError` au premier `await`) → bots inscrits mais `_try_start_game` jamais appelé (il fallait re-cliquer « Prêt »). Désormais la task se **retire du registre sans s'annuler** puis démarre la partie.
> 2. **Deadlock de fin de draft supprimé** : `submit_bot_blind_deploys` re-prenait `timers.get_lock` déjà tenu par la branche `faction_choice` (`asyncio.Lock` NON réentrant) → salle gelée à vie au dernier verrouillage. Signature refondue `submit_bot_blind_deploys(room_id, state)` — **s'exécute SOUS le verrou de l'appelant** (`_begin_phase0`).
> 3. **Draft resynchronisable + borné** : action `get_draft` → message privé `draft_state` (photographie des verrouillages — les `faction_locked` des bots partaient pendant la transition de scène et étaient perdus → compteur client figé à 1/3) ; **rebours `DRAFT_TIMEOUT_S` = 60 s** avec auto-verrouillage de la faction provisoire des retardataires ; complétion sur joueurs **ACTIFS** (`_draft_complete`) côté serveur ET client ; un départ pendant le draft peut le compléter (`_maybe_abandon_on_disconnect`) au lieu d'armer un 90 s prématuré ; `game_started`/`draft_state` portent `draft_deadline_at` (compte à rebours affiché par `faction_selection.gd`, clé i18n `FS_AUTO_LOCK_IN`).
> 4. **Handoff bot → humain réparé + watchdog** : `_run_bots` appelle désormais `_post_action_timer` après CHAQUE action (l'ancien code n'armait RIEN au passage bot → humain : plus d'anti-AFK, humain muet = salle gelée) ; `_arm_next_timer` arme le rebours standard MÊME pour un tour de bot (une task bot morte est rattrapée par l'expiration AFK : passage forcé → `ensure_bots_play` idempotente ressuscite la boucle → abandon du bot à 2 strikes en dernier recours).
> 5. **`spy_objective` (latent)** : `next_action` pouvait le proposer mais l'action n'existe PAS dans `GameEngine.process_action` (voie routeur réservée aux humains) → le runner la résout désormais en direct (`GameEngine.resolve_spy`, flag soldé même sur refus — plus de boucle possible). Inatteignable en prod v1 (chasseurs_ombres payante, bots = gratuites) mais piégeux.
>
> **Validation durcissement.** **NOUVEAU `backend/test_bot_flow.py` : 36 ✅ / 0 ❌** (fill → auto-start ; fin de draft sous verrou SANS deadlock (`wait_for` = détecteur de régression) ; auto-verrouillage à l'échéance ; abandon pendant le draft → partie bots seuls SANS gel ; watchdog + minuterie armée au handoff ; spy soldé). Suites affectées re-vertes : `test_bot_ai` 18, `test_turn_loop_fixes` 37, `test_time_bank_chat` 33, `test_setup_phase` 37, `test_hero_faction_draft` 17, `test_security_locks` 38. Frontend : `--import` + boot headless `faction_selection`, `waiting_room` = 0 ERROR.

### 8.83 (lot E11 — PLAN_EXPERIENCE). DÉBRIEFING 2.0 — `game_over` PAR DESTINATAIRE, `objectives_reveal`, `territory_history` (Backend + Frontend, 2026-07-15)
> **But (E11).** La fin de partie devient un vrai débriefing : **classement**, **gains PRIVÉS** (chacun ne voit que les siens — redaction), **objectifs révélés**, **timeline de domination**, titres honorifiques. **Backend → push + redéploiement VPS requis (§1)** — MÊME redéploiement que E3 (§8.75).
>
> - **`state_schemas.GameStatistics.territory_history: List[Dict[int, int]] = []`** (défaut → rétro-compat Redis) : un instantané `{pid: nb_territoires}` appendé à CHAQUE nouveau round global. **`engine._append_territory_snapshot`** appelé dans `_end_turn` (bloc `is_new_global_round`, même endroit que la zone §8.31), **PLAFOND `TERRITORY_HISTORY_CAP = 200`** (garde-fou Redis — au-delà, plus d'append). Diffusé avec l'état (clés string en JSON §5) → le client l'a AVANT le `game_over`.
> - **`game_over` REDACTÉ PAR DESTINATAIRE** (`router._finalize_if_over`) : l'unique `broadcast_to_room` est remplacé par un **envoi PAR SOCKET** (pattern State Redaction / `spy_result`) sur `manager.players[room_id]`. Partie **COMMUNE** : `winner_id`, `match_type`, `rankings`, **`objectives_reveal`** (bloc PUBLIC `[{player_id, username, description, completed}]`, ordre = `rankings`, `completed` depuis `build_match_stats.objective_win`). Partie **PRIVÉE** : `match_rewards` ne contient QUE l'entrée du destinataire, **en conservant la forme dict `{"<pid>": MatchRewards}`** (le client pioche déjà sa clé → compatible SANS modification, `main.gd` l.~1236). Destinataire sans gains (spectateur) → `{}`. Bots (socket None) → aucun envoi. ⚠️ **Piège n° 9 (PLAN_EXPERIENCE)** : tout champ FUTUR de `game_over` doit être explicitement classé PUBLIC ou PRIVÉ — jamais de retour à un broadcast unique porteur de données personnelles.
> - **Frontend** : `network_manager` — `last_objectives_reveal` (bloc PUBLIC mémorisé, signal `match_over` inchangé) ; `operation_report.gd` **refonte 2 COLONNES par code** (aucune retouche `.tscn` — le récap de zone `%StagnationReport`/`%AttritionList` MIGRE en colonne gauche via `reparent`, poignées directes car `reparent` invalide `%`) : **gauche LA PARTIE** (podium `rankings` + `player_chip` E1 + **titres honorifiques** formules exactes départage pid + objectifs révélés ✔/✘ + 3 stats publiques/joueur + **timeline** Control `_draw()` une polyligne/joueur + récap zone) ; **droite MA PERFORMANCE** (récompenses animées existantes CONSERVÉES + stats perso + état final héros `PV/PP/NIV` ou `💀 ABATTU` + **pont missions** `fetch_missions` post-`game_over`). **NOUVEAU bouton `🔍 INSPECTER LE CHAMP DE BATAILLE`** (masque rapport+flou, caméra libre E1/G3 via `battlefield_inspect` → `camera.set_free_navigation`, bouton `◀ RAPPORT`). Sections E11 masquées sur payload legacy (§9.2). 22 clés i18n `REPORT_*`/`TITLE_*`.
> - **Validation.** **NOUVEAU `backend/test_game_over_redaction.py` : 19 ✅ / 0 ❌** (chaque destinataire → SEULE sa clé, forme dict conservée ; spectateur `{}` ; bot sans socket → aucun envoi ; `objectives_reveal` identique pour tous + ordonné par `rankings` ; `territory_history` : instantané/round, plafond 200, défaut rétro-compat) ; suites affectées re-vertes (`test_state_redaction` 15, `test_rewards` 135, `test_setup_phase` 37). Frontend : **NOUVEAU `tools/test_e11_report.tscn` 16 ✅** (titres+départage pid, médailles, rapport complet podium/timeline/inspection, rapport legacy masqué) ; `--import` + boot `main.tscn` = 0 ERROR. **AUCUN COMMIT.**

### 8.75 (lot E3 — PLAN_EXPERIENCE). CHRONO SERVEUR — `turn_timer` dans l'état, message `timer_update`, `server_time` (Backend + Frontend, 2026-07-15)
> **But (E3).** Le temps est une RÈGLE (§8.31/§8.33) : le rebours affiché doit être CELUI qui déclenche le timeout serveur (reconnexion comprise), plus une estimation locale. **Backend → push + redéploiement VPS requis (§1)** — même redéploiement possible que le volet backend E11 (§8.83). *(NB : §8.73/§8.74 sont des lots 100 % frontend — entrées dans FRONTEND_INTERFACES.md.)*
>
> - **Registre (`connection_manager.RoomTimers`)** : `arm_deadline` mémorise désormais aussi le **budget** `(délai, plafond_total)` (`budgets`, purgé par `clear_deadline`/`cleanup`) ; **NOUVEAU `get_deadline_info(room_id)`** → `(échéance monotone, budget_s, plafond_total_s) | None`. ⚠️ `get_deadline` (échéance seule) reste le contrat INCHANGÉ de la coroutine d'expiration — le plan prévoyait de l'étendre, un getter séparé évite de toucher ce chemin critique.
> - **`router._turn_timer_payload(state)`** : photographie du chrono — l'échéance du registre (temps MONOTONE `loop.time()`) est **convertie en EPOCH MUR** (`time.time() + reliquat`). Renvoie **None** si : rien d'armé, partie finie, **tour de BOT** (id négatif, G2 — aucun rebours affiché), ou hors boucle asyncio (tests maison).
> - **`_state_payload` enrichi (CHAQUE rediffusion d'état)** : `"turn_timer": { "deadline_epoch": <epoch>, "budget_seconds": 60|90, "time_bank_cap": 60|90|180 } | null` + **`"server_time": <epoch>`** (horloge de référence → le client calcule un OFFSET `server_time − horloge_locale` et affiche `deadline − (locale + offset)` — immunisé contre une horloge PC fausse). Clés ADDITIVES (client antérieur : ignorées, §9.2).
> - **NOUVEAU message léger `{"type": "timer_update", "reason": "turn_start"|"phase_change"|"time_bank", "deadline_epoch", "budget_seconds", "time_bank_cap", "server_time"}`** diffusé par `_broadcast_timer_update` (fire-and-forget `create_task`, no-op bot/fini/hors-boucle) : dans **`_arm_next_timer`** (turn_start — couvre aussi `_schedule_turn_timer`/`_post_action_timer`), **`_rearm_deadline_for_phase`** (phase_change), et au **site Time Bank** du handler d'attaque (`extend_deadline` non-None → time_bank, le +10 s §8.33 devient VISIBLE).
> - **Frontend** : `network_manager` — signal **`timer_updated(deadline_epoch, budget, reason, server_time)`** ; `game_state` — champs `turn_timer` ({} si null) + `server_time` (0.0 = serveur antérieur) ; **`hud`** — `%TimerLabel` piloté par l'échéance serveur (`apply_server_timer`/`apply_timer_update` ; `reason=="time_bank"` → **flotteur « +N s » or** près du chrono, delta calculé sur l'échéance précédente ; `add_time_to_timer` legacy devient NO-OP en mode serveur — anti double-comptage) ; **REPLI LEGACY intact** (état sans `server_time` → estimation locale historique `_phase_turn_limit`) ; **pré-alerte AFK** : sous 15 s sur NOTRE tour, chrono pulsé rouge + `play_sfx("timer_tick")`/s (l'abandon auto §8.31 ne surprend plus). Bandeaux de tour/phase : voir FRONTEND_INTERFACES §8.75-front.
> - **Validation.** **NOUVEAU `backend/test_timer_broadcast.py` : 26 ✅ / 0 ❌** (registre + budgets purgés ; epochs cohérents `deadline > server_time` ; bot/fini/désarmé → null ; les 3 raisons aux 3 points ; tour de bot → AUCUN timer_update) ; suite affectée `test_time_bank_chat` re-verte (33 ✅). Frontend : **NOUVEAU `tools/test_e3_timer.tscn`** (arène réelle + stubs : repli legacy intact, échéance serveur affichée « 00:42 », tour de bot → « --:-- », time_bank appliqué) **9 ✅** ; `--import` = 0 ERROR. **AUCUN COMMIT.**
### 8.85 (chantier A.1). `attack_result` porte l'IDENTITÉ des deux camps — fin du « mon personnage attaque mon personnage » (Backend + Frontend, 2026-07-17)
> **Symptôme.** Pendant le tour d'un BOT, l'écran Split-Screen VS et le bandeau compact pouvaient afficher le pseudo, la couleur, le skin ET le héros d'un JOUEUR HUMAIN comme ATTAQUANT — parfois des DEUX côtés du duel (« mon personnage attaque mon personnage »), d'où le ressenti global « les bots attaquent n'importe comment ». **Backend → push + redéploiement VPS requis (§1).**
>
> - **Cause racine (client).** `main.gd` résolvait les identités depuis le SNAPSHOT d'affichage `_displayed_owners`. Or un bot enchaîne une attaque toutes les ~1 s (`bot_runner.BOT_ACTION_DELAY`) alors qu'une animation VS dure plusieurs secondes → les combats s'empilent dans `_combat_queue` et `_refresh()` (qui met à jour `_displayed_owners`) est DIFFÉRÉ jusqu'au drainage complet (`_refresh_pending`). Et comme l'IA déplace le maximum de troupes dans le territoire conquis (`conquer_move` « tout sauf 1 »), sa prochaine attaque part très souvent DE CE territoire : au moment où le 2ᵉ combat s'anime, le snapshot porte encore l'ANCIEN propriétaire (souvent l'humain). **L'IA elle-même n'a JAMAIS été en cause.**
> - **Correctif — le SERVEUR fait autorité (champs ADDITIFS §9.2).** `engine._handle_attack` ajoute à l'event : **`"attacker_player_id": int`** (toujours `state.current_player_id`) et **`"defender_player_id": int | null`** (propriétaire capturé **AVANT** le transfert de propriété — variable `defender_owner_id` déjà présente ; `null` = territoire NEUTRE). Valeurs `int` PURES (piège JSON §5).
> - **Frontend (`main.gd`).** Nouveau helper **`_event_pid(event, key, fallback)`** : champ serveur PRIORITAIRE, sinon `fallback` = la valeur historique PROPRE À CHAQUE SITE (leurs sentinelles diffèrent : `-1` « neutre » via `_owner()`, `-9999` « inconnu ») → repli SILENCIEUX sur le comportement actuel si le VPS n'est pas redéployé. `defender_player_id: null` → `-1`, sentinelle « sans propriétaire » déjà rendue par `_owner()` (aucune régression sur les attaques de neutres). Appliqué aux **4 consommateurs** : `_do_play_combat` (VS + bandeau via son appelant), `_play_event_feedback` (VFX douleur héros + flash de conquête), `_feed_ctx` (kill feed E4 → `war_feed.parse`), `_maybe_defense_toast`. `war_feed.gd` et `hud.show_combat_banner` consomment le `atk_pid`/`def_pid` déjà résolus par `main.gd` — aucune dérivation indépendante à corriger.
> - **`local_is_attacker` corrigé** : basé sur l'ATTAQUANT DE CE COMBAT (`int(atk_owner) == _my_id()`) et non plus sur `GameState.current_player_id`, qui peut être PÉRIMÉ quand un combat DÉFILÉ depuis la file s'anime (« ⏱ TIME BANK +10 s » s'affichait au mauvais camp).
> - **Validation.** **NOUVEAU `backend/test_attack_event_identity.py` : 11 ✅ / 0 ❌** — l'event porte l'attaquant courant et le propriétaire PRÉ-conquête (test probant : sur conquête `territories[b].owner_id` vaut DÉJÀ l'attaquant, l'event doit malgré tout désigner l'ancien), cible neutre → `null`, ints purs. Frontend : `--import` + boot `main.tscn` = 0 ERROR.

### 8.86 (chantier A.2). Unicité des factions au draft des BOTS — plus jamais le même héros des deux côtés du VS (Backend, 2026-07-17)
> **Symptôme.** Un bot pouvait jouer la faction d'un humain (ou d'un autre bot) → le Split-Screen VS résolvant ses visuels à partir du SEUL id de faction (`split_screen_vs.start_combat_resolution(attacker_faction_id, defender_faction_id, …)`), le MÊME personnage apparaissait des deux côtés du duel. **Backend → push + redéploiement VPS requis (§1).**
>
> - **Cause racine.** `create_initial_state` attribue des factions provisoires UNIQUES (set `used_factions`), mais `router._draft_bots` les ÉCRASAIT ensuite via `bot_ai.decide_faction` = `random.choice(sorted(FREE_FACTION_IDS))` **sans AUCUNE exclusion**. Il y a **6 factions gratuites** pour **6 joueurs** maximum → l'unicité est TOUJOURS réalisable.
> - **Correctif.** `bot_ai.decide_faction(state, pid, taken=None)` (signature RÉTRO-COMPATIBLE — les sites d'appel historiques restent valides) : tirage dans `pool = sorted(set(FREE_FACTION_IDS) - set(taken or ()))` ; pool vide **ou** catalogue stubbé → repli sur la faction PROVISOIRE déjà posée (unique par construction). `router._draft_bots` construit `taken` = factions des **AUTRES** joueurs de l'état ∪ verrouillages `manager.get_locked_factions`, **recalculé à CHAQUE itération** (`_apply_faction_to_player` mute l'état → les bots déjà re-draftés sont couverts).
> - ⚠️ **Le bot COURANT est exclu de `taken`** : à 6 joueurs les 6 gratuites sont toutes posées provisoirement — s'inclure viderait le pool à chaque fois. *(Nuance VÉRIFIÉE expérimentalement : cela ne recréerait PAS de doublons — le repli rend la faction provisoire du bot, unique par construction — mais figerait tous les bots sur leur provisoire, supprimant tout aléa.)*
> - **Draft HUMAIN inchangé** : l'unicité entre humains reste une décision produit ouverte (`_handle_faction_choice` accepte toujours les doublons).
> - **Validation.** `test_bot_ai.py` **30 OK** (exclusion 5/6 → tire la 6ᵉ, `taken` en liste acceptée, pool vide → repli sans exception, signature rétro-compatible) ; `test_bot_flow.py` **47 ✅** dont un test **DÉTERMINISTE** (`random.choice` figé sur le 1ᵉʳ candidat → le doublon devient CERTAIN sans le correctif ; contre-épreuve : 2 ❌ avec l'ancien code) + unicité à **6 joueurs, pool à saturation**.

### 8.87 (chantier B). Remplissage IA à l'EFFECTIF DE LA SALLE (et non plus à 3 en dur) (Backend + Frontend, 2026-07-17)
> **Symptôme.** Quel que soit le mode choisi au menu (Quad 4 / Five 5 / Exa 6 / Classée 5), le remplissage IA ajoutait toujours 2 bots — la partie démarrait à 3. **Backend → push + redéploiement VPS requis (§1).**
>
> - **Cause racine — trois `3` EN DUR dans `router.py` :** `_maybe_arm_bot_fill` (`len(connected) < 3` — qui, en prime, n'armait JAMAIS le fill d'une salle 4/5/6 contenant déjà 3 humains), `_bot_fill_after` (garde `>= 3` et boucle `while … < 3`). L'effectif choisi arrivait pourtant bien en base (`MatchConfig.selected_player_count` → `lobby_screen._required_players` → `create_room(max_players=…)` → `GameRoom.max_players`) : le `ConnectionManager` ignorait simplement cette capacité.
> - **Correctif — `_room_settings(room_id) -> dict` (UNE lecture DB pour tous les réglages).** Regroupe `map_id` / `max_players` / `is_ranked` (pattern `_load_hero_progress` : session courte dédiée, replis DÉFENSIFS par champ = `classic_42` / **3** / `False`). `_room_map_id` devient un mince wrapper (contrat G5 §8.71 inchangé) et **`_room_capacity(room_id)`** rend `max_players` clampé `[3..6]`. Les trois `3` sont remplacés par `target = _room_capacity(room_id)`, lu **une fois par appel**. `BOT_CALLSIGNS` compte 6 indicatifs → jusqu'à 5 bots pour 1 humain. Commentaire `core/config.py` mis à jour.
> - **Additif réseau.** `_broadcast_lobby_state` ajoute **`"max_players": int`** (§5) → `waiting_room.gd` affiche « **X / Y joueurs** » via `NetworkManager.last_max_players` (propriété, le signal `lobby_state_updated` garde sa signature — pattern `last_bot_fill_at`) ; **repli** sur le libellé historique si le champ est absent (`-1`). ⚠️ L'ancienne clé `WR_LOBBY_STATE` annonçait « (3 requis pour lancer) » — **un 3 en dur de plus**, faux dès Quad/Five/Exa ; nouvelle clé **`WR_LOBBY_STATE_CAP`** (3 arguments).
> - **Interaction chantier C.** Une salle Classée naît avec `max_players = 5` → le remplissage complète naturellement à 5. Aucun cas particulier.
> - **Validation.** `test_bot_flow.py` **47 ✅ / 0 ❌** — (a) capacité 5 + 1 humain → **4 bots**, démarrage à 5 ; (b) capacité 6 avec **3 humains déjà prêts** → fill ARMÉ (régression historique) et complété à 6 ; (c) capacité illisible (panne DB) → **repli 3 = comportement historique**. Nouveau contexte de test `fake_room_settings` (sans stub, le repli défensif rendrait toujours 3 et masquerait le bug).

### 8.88 (chantier C). Mode CLASSÉE — SEUL mode à créditer le classement (Backend + Frontend, 2026-07-17)
> **But.** Le ladder (à vie `User.points_classement` + saisonnier `User.season_points`, M6 §8.68) était crédité par **TOUTES** les parties. Il ne l'est désormais QUE par les parties **classées**. L'intention « Classée » existait côté client seulement (`MatchConfig.selected_ranked`, **jamais lu ensuite**) : elle est câblée de bout en bout. **Backend → push + redéploiement VPS requis (§1)** + **auto-migration DB au boot**.
>
> - **Design.** Une salle est classée ou non, décidé **À LA CRÉATION**. Salle classée = **EXACTEMENT 5 joueurs** (gate serveur) sur une carte qui les supporte. **Toutes** les parties créditent XP joueur, XP héros, coins, historique, missions, télémétrie, stats — **seuls** les points de ladder deviennent conditionnels. Le remplissage IA fonctionne aussi en classée (complète à 5, §8.87).
> - **Schéma.** `models.GameRoom.is_ranked = Column(Boolean, default=False, server_default="false", nullable=False)` → ajoutée au boot par `core/db_migrations.sync_missing_columns` ; archive `backend/migration_ranked.sql` (patron `migration_seasons.sql`). `schemas.GameRoomBase.is_ranked: bool = False` (hérité par `GameRoomCreate`, exposé dans `GameRoomResponse`). `state_schemas.GameState.is_ranked: bool = False` (défaut Pydantic → **rétro-compat Redis**).
> - **Module PUR `api/game/ranked.py`** (Règle d'Or §6, patron `rotation.py`/`seasons.py`) : `RANKED_PLAYER_COUNT = 5`, `RankedRoomError(ValueError)`, `ranked_room_bounds(game_map, requested_max, is_ranked)` → classée = effectif FORCÉ à 5 (payload client ignoré) + `RankedRoomError` si la carte ne le supporte pas ; non classée = clamp historique aux bornes de la carte. Appelé par `lobby.create_room` (→ HTTP **400** explicite).
> - **Propagation.** `engine.create_initial_state(room_id, players_data, map_id="classic_42", is_ranked=False)` pose le flag sur l'état. Les DEUX appelants le fournissent : `router._try_start_game` (via `_room_settings`) et `game.start_game` (`getattr(room, "is_ranked", False)` — défensif, base pré-migration).
> - **Crédit conditionnel.** `state_manager.process_match_results(db, winner_id, match_stats, total_turns=0, **is_ranked=True**)` — défaut `True` = **comportement LEGACY** (tous les appelants et tests historiques inchangés). Si faux : `match_points = 0` pour tous (valeur EXPLICITE dans `match_rewards`) et **ni `ensure_season`, ni `points_classement`, ni `season_points`** ne sont touchés (une partie non classée est totalement neutre pour le classement). **TOUT LE RESTE est identique.** `router._finalize_if_over` passe `is_ranked=bool(getattr(state, "is_ranked", False))` et ajoute **`"is_ranked"` au bloc COMMUN du `game_over`** (**PUBLIC** — piège n° 9 : même valeur pour tous, aucune donnée personnelle).
> - ⚠️ **Effet assumé du redéploiement** : une partie EN COURS dont l'état Redis n'a pas le champ sera traitée **non classée** (une seule fois).
> - **Frontend.** `lobby_screen.gd` lit `MatchConfig.selected_ranked` → `_required_ranked` ; si classé : effectif forcé à 5, **carte verrouillée sur `classic_42`** (sélecteur calé + désactivé — garde d'UI, le serveur re-valide) et **badge « ◆ CLASSÉE »** or `#E0B249` (purement local, aucun champ réseau). `network_manager.create_room(…, is_ranked := false)` (paramètre en QUEUE → appelants historiques valides), passé sur les DEUX créations (publique/privée). `network_manager.last_match_is_ranked` relaie le `game_over` — **défaut `true` VOLONTAIRE** : un serveur ANTÉRIEUR n'envoie pas le champ mais crédite ENCORE le ladder, afficher « non classée » y serait un MENSONGE. `main.gd` résout le flag (`_match_is_ranked()`) et le passe au rapport (Vue pure §6.1) ; podium `points = -1` en non classé. Commentaire « DÉPENDANCE BACKEND » de `match_config.gd` mis à jour (câblée). 2 clés i18n.
> - **Validation.** `test_rewards.py` **231 OK / 0 FAIL** — nouveau cas qui **rejoue le MÊME match deux fois** (classé / non classé, générateur aléatoire semé à l'identique — sinon les coins de niveau héros diffèreraient) : `match_points = 0` partout, ladder INTOUCHÉ (`season_points` jamais écrit → `ensure_season` non appelé), et **XP / niveaux / coins / héros / historique / stats STRICTEMENT identiques**. **NOUVEAU `backend/test_ranked_room.py` : 17 ✅** (gate pur : payload menteur ignoré, carte 3-4 refusée, clamps non classés intacts ; propagation → `GameState.is_ranked` ; **rétro-compat Redis** : état sans le champ → `False`). `test_game_over_redaction.py` **23 ✅** (+ `is_ranked` PUBLIC identique pour tous, propagé à `process_match_results` ; ⚠️ son stub `process_match_results` a dû être élargi à `is_ranked` — trop étroit, il levait un `TypeError` AVALÉ par le fail-safe du routeur → 2 ❌ faussement attribuables au frontend).

### 8.90 (chantier A.3). IA des bots — cohérence OFFENSIVE : continent > moribond > garnison faible (Backend, 2026-07-17)
> **But.** `_action_attack` choisissait le couple (source, cible) au **surplus max** seul → la source sautait d'un bout à l'autre de la carte, sans aucune notion d'objectif (« attaques décousues »). L'IA reste PURE, déterministe, même signature. **Backend → push + redéploiement VPS requis (§1).**
>
> - **Hiérarchie de priorité** (constantes nommées en tête de module — aucun nombre magique) : **`PRIO_CONTINENT = 0`** (la conquête complèterait un continent) > **`PRIO_ELIMINATION = 1`** (cible d'un joueur **moribond** ≤ `MORIBUND_TERRITORIES = 2`) > **`PRIO_NONE = 2`**. Départage STABLE : priorité, puis **garnison cible croissante**, puis **surplus décroissant**, puis ordre lexicographique `(tid_cible, tid_source)` → reproductibilité totale à état égal.
> - **`_completes_continent`** utilise `get_map(state.map_id)["continent_territories"]` — **MÊME source de vérité que `engine._credit_continent_conquests`** : le bot vise exactement ce que le moteur récompense. La **garde de surplus** (`src-1 >= tgt+1`) et le plafond `MAX_ATTACKS_PER_TURN = 12` sont INCHANGÉS.
> - **Validation.** `test_bot_ai.py` **30 OK / 0 KO** — nouveaux cas dédiés : « préfère compléter le continent » (brazil, surplus 7, plutôt que kamchatka, surplus 19), « préfère la cible moribonde » (joueur à 2 territoires plutôt que la garnison 1 d'un joueur bien installé), « sans priorité → la plus faible », déterminisme sur 20 appels, garde de surplus tenue. **Contre-épreuve : 3 ❌ avec l'ancienne heuristique** (les tests discriminent réellement).

### 8.95 (chantier H). Ladder « Warzone » — RP, divisions/échelons, planchers, récompenses de saison (Backend, 2026-07-17)
> **But.** Le ladder saisonnier ne pouvait QUE monter (`season_points += match_points`, toujours ≥ 0) → **aucune relégation, aucun enjeu**, et l'écran triait sur `season_points` tout en mettant les **VICTOIRES** en avant (ordre incompréhensible). Le barème est refondu en **RP (Rating Points)** signés, avec divisions/échelons, protections et récompenses de fin de saison. **Réécrit §8.68** (barème saisonnier) — les seuils M6 d'origine (0/500/1200/2200/3500) ne sont plus valides. **Backend → push + redéploiement VPS requis (§1).** Aucune colonne nouvelle : on garde `User.season_points` (le LIBELLÉ affiché devient « RP »).
>
> - **Échelle (`api/game/seasons.py`, module PUR).** `TIER_RP = 100`, `TIERS = ("III","II","I")`, `DIVISIONS = (("BRONZE",0),("ARGENT",300),("OR",600),("PLATINE",900),("ELITE",1200))`, `SEASON_REWARD_COINS = {BRONZE:50, ARGENT:150, OR:300, PLATINE:600, ELITE:1000}`. BRONZE/ARGENT/OR/PLATINE = 3 échelons de 100 RP ; **ÉLITE = ladder OUVERT** (1200+, sans échelon). `division_for` conservé (mêmes appelants : leaderboard, `/auth/me`) sur les NOUVEAUX seuils.
> - **`rank_info(points) -> dict`** (entiers purs) : `{division, tier ("III"/"II"/"I", "" en ÉLITE), label ("OR II" / "ÉLITE"), floor (plancher de DIVISION), tier_floor (plancher d'ÉCHELON), rp_in_tier, tier_span (100 ; **0 en ÉLITE** = signal « pas de barre »)}`. ⚠️ Les **ids** restent ASCII (`"ELITE"`), seul le **label** est accentué (`DIVISION_LABELS`) — le client applique le même mapping pour ne pas afficher « ELITE » d'un côté et « ÉLITE » de l'autre.
> - **Barème par partie CLASSÉE (`api/game/rewards.py`, module PUR).** `SEASON_RP_BY_RANK = (30, 15, 5, -10, -20)` (index = rang ; rang ≥ 5 → dernière valeur), `SEASON_RP_PER_ELIMINATION = 1` plafonné par `SEASON_RP_ELIM_CAP = 5`, `BRONZE_LOSS_DIVISOR = 2`. **Deux helpers purs** (trivialement testables) plutôt qu'un `compute_season_rp` monolithique :
>   - `raw_season_rp_delta(rank, eliminations) -> int` — barème + bonus d'élims plafonné, **AUCUNE protection** ;
>   - `apply_season_rp(current_points, delta) -> dict` — applique les protections via `seasons.rank_info` et renvoie `{points_before, points_after, raw_delta, delta, bronze_protected, floor_protected, promoted, demoted}`. **Convention : `points_after` = NOUVEAU TOTAL à écrire ; `delta` = delta RÉELLEMENT appliqué (= after − before) → c'est CE delta qu'on affiche.**
>   - **Ordre des protections :** BRONZE `/2` (arrondi **vers zéro** ; les GAINS ne sont jamais divisés) → **plancher de la division d'AVANT match** → plancher global 0. Promotion/démotion se lisent sur `tier_floor` (⇒ en ÉLITE, progresser n'est ni une promotion ni une démotion).
> - **Plancher de division (anti-relégation, style Apex).** Le RP ne descend JAMAIS sous le plancher de la division COURANTE : on peut redescendre d'échelon (OR I → OR III) mais **pas de division** (OR III → ARGENT I impossible dans la saison).
> - **Fin de saison (`ensure_season`, reset lazy 90 j existant).** Au rollover, AVANT la remise à zéro, `user.coins += SEASON_REWARD_COINS[division_for(anciens points)]`. **Idempotence par le flip de `season_id`** (un seul crédit par saison ; les appelants committent déjà). ⚠️ **ÉCART ASSUMÉ vs la spec :** la récompense n'est versée que si `season_id` était **non vide** — un `season_id` vide est une *initialisation* (`models.User` : « "" = jamais initialisé »), pas une bascule ; sans ce garde-fou **tout nouveau compte encaissait 50 Coins BRONZE à sa première requête authentifiée**. Documenté + testé.
> - **`state_manager.process_match_results` — branche CLASSÉE uniquement (§8.88).** `points_classement += match_points` **INCHANGÉ** (ladder à vie, formule legacy). `season_points` passe par le calcul RP (delta brut → protections → nouveau total). Champs **ADDITIFS** de `match_rewards[player_id]` (bloc **PRIVÉ**, redacté par destinataire E11 §8.83) : `rp_delta` (int **signé**), `rp_after` (int), `rp_division` (str), `rp_tier` (str), `rp_label` (str), `rp_promoted` (bool), `rp_demoted` (bool), `rp_floor_protected` (bool). **Ces 8 clés sont TOUJOURS présentes** — zéros/`""`/`false` pour les bots (id < 0), les joueurs introuvables et les parties NON classées → le client lit toujours les mêmes clés.
> - **`GET /leaderboard` (tout ADDITIF, §9.2 préservé).** Chaque entrée **et** le bloc `me` gagnent `division_tier` (str), `rp_in_tier` (int), `tier_span` (int) — défauts sûrs dans `LeaderboardEntry`/`LeaderboardMe`. **`division` et `season_points` NE SONT PAS retirés** (le client détecte le mode M6 par la présence de `division` — ne jamais l'enlever). La réponse `season` s'enrichit de :
>   - **`rules`** (TOUJOURS présent, dict statique) : `{rp_by_rank:[30,15,5,-10,-20], elim_bonus:1, elim_cap:5, bronze_loss_divisor:2, division_floor_lock:true, tier_rp:100, rewards_coins:{…}}` → **le client rend les règles DEPUIS ce bloc, jamais en dur** ;
>   - **`divisions`** : `[{id, floor, ceiling|null, players}]` — effectifs par division, **UN SEUL `GROUP BY`** (expression `CASE` sur les bornes, pas 5 requêtes). **Scope `season` UNIQUEMENT** (lecture littérale de la spec + évite un agrégat inutile sur l'onglet GÉNÉRAL) ; le client masque la bande si la clé est absente.
> - ⚠️ **Effet ponctuel assumé au déploiement.** Les `season_points` DÉJÀ accumulés sont **réinterprétés** sur la nouvelle échelle (un joueur à 700 « ancien barème » se retrouve **OR III**). Acceptable une seule saison — **aucune migration**, rien à convertir.
> - **Validation (réelle, rejouée).** `py_compile` OK sur les 8 `.py` touchés. `test_seasons.py` **51 OK / 0 KO** (nouvelles bornes −5/0/299→BRONZE, 300/599→ARGENT, 600/899→OR, 900/1199→PLATINE, 1200/9999→ÉLITE ; `rank_info` ; rollover crédité UNE fois + idempotent). `test_rewards.py` **297 OK / 0 FAIL** (les **DEUX** cas obsolètes « season_points = match_points » — dans `test_process_match_results_unranked` ET `test_pass_benefits` — refaits en sémantique RP ; barème par place, cap élims, /2 BRONZE, plancher de division « OR III à 600 perd 20 → reste 600 », plancher 0, promotion/démotion, ÉLITE sans plafond). **NOUVEAU `test_ladder_payload.py` 31 OK / 0 KO** (`rank_info` → champs additifs leaderboard ; `leaderboard.py` n'avait aucune couverture). Non-régression : `test_bot_flow.py` 47 ✅, `test_bot_ai.py` 30 OK, `test_ranked_room.py` 17 ✅, `test_game_over_redaction.py` 23 ✅. ⚠️ `test_missions.py` **37 OK / 4 KO — ÉCHEC PRÉ-EXISTANT**, prouvé en rejouant la suite sur un snapshot `git archive HEAD` intact (mêmes 4 KO **avant** ce chantier). ⚠️ `sqlalchemy`/`fastapi` **absents du poste** → le `CASE … GROUP BY` de `_division_counts` est testé **avec un stub** (bornes/effectifs validés ; **SQL réel à confirmer en intégration**).

### 8.98 (ladder v2, partie BACKEND). Échelle 200 RP, chute de division, règlement CENTRALISÉ des podiums (Backend, 2026-07-17)
> **But (retours produit de Hakim sur §8.95, AVANT tout déploiement — le ladder RP v1 n'a jamais atteint le VPS, aucune migration).** (1) Échelons élargis : « 300 RP pour monter 3 divisions […] c'est un peu trop juste » → **200 RP/échelon** ; (2) « il faut la possibilité de descendre de division si quelqu'un perd beaucoup » → **verrou de division SUPPRIMÉ** ; (3) récompenses de fin de saison versées **aux podiums de chaque sous-division** (enveloppes par division, réparties 50/30/20 puis 50/30/20). **Redéploiement VPS requis (§1)** + table neuve créée au boot.
>
> - **Échelle (`seasons.py`).** `TIER_RP = 200`, `DIVISIONS = (("BRONZE",0),("ARGENT",600),("OR",1200),("PLATINE",1800),("ELITE",2400))` — BRONZE III [0,200) … PLATINE I [2200,2400), **ÉLITE [2400,∞)** sans échelon. Nouvelles fonctions PURES : `tier_bounds(division, tier="") -> (floor, ceiling|None)` (plafond EXCLUSIF ; ÉLITE → (2400, None), tier ignoré ; tier vide sur division à échelons → bornes de la DIVISION ; inconnu → `ValueError`) et `tier_envelope(division, tier="")`.
> - **Chute de division (`rewards.py`).** `apply_season_rp` : le plancher de division est RETIRÉ — ordre des protections désormais **BRONZE ÷2 (pertes seules, arrondi vers zéro) → plancher GLOBAL 0**. Les clés du dict renvoyé sont INCHANGÉES (compat réseau) ; `floor_protected` ne vaut True que si le clamp à 0 a réellement rogné la perte (atterrir PILE à 0 → False). `promoted`/`demoted` (comparaison de `tier_floor`) couvrent naturellement les changements de DIVISION — cas prouvé : 1210 − 20 = 1190, OR III → ARGENT I, `demoted=True` ; la sortie d'ÉLITE par le bas est possible.
> - **Récompenses de fin de saison = PODIUMS (remplace la prime « tout le monde »).** `SEASON_REWARD_COINS = {BRONZE:500, ARGENT:1000, OR:2000, PLATINE:4000, ELITE:10000}` — ⚠️ **changement de SÉMANTIQUE** : c'est désormais l'**ENVELOPPE de la division**, répartie `TIER_REWARD_SPLIT = {I:50, II:30, III:20}` (%) entre sous-divisions puis `PODIUM_REWARD_SPLIT = (50,30,20)` (%) entre les places 1/2/3 de chaque podium. Enveloppes de sous-division : BRONZE 250/150/100 · ARGENT 500/300/200 · OR 1000/600/400 · PLATINE 2000/1200/800 ; **ÉLITE = UN podium sur l'enveloppe entière (5000/3000/2000)**. Valeurs actuelles → aucune perte d'arrondi (floor div exact). `seasons.season_podium_rewards(standings) -> {user_id: coins}` (PURE) : bucketing par `rank_info`, tri (points desc, wins desc, level desc, id asc) = hiérarchie du leaderboard, podiums de moins de 3 → seules les places occupées payées (aucune redistribution).
> - **Règlement CENTRALISÉ (`api/game/season_settlement.py`, NOUVEAU).** Payer des podiums exige le CLASSEMENT FINAL à la bascule — impossible avec l'ancien crédit paresseux par joueur (`ensure_season` ne crédite PLUS rien : reset seul, garde « initialisation » retirée). `settle_previous_season(db) -> bool`, appelé AVANT chaque `ensure_season` (leaderboard `me`, `/auth/me`, `process_match_results` — UNE fois avant la boucle) : chemin RAPIDE par cache de processus + marqueur `SeasonSettlement` (table `season_settlements`, PK `season_id` — **créée au boot** par `create_tables()`/`Base.metadata.create_all`, `main.py:59` ; archive `migration_season_settlements.sql`). Au premier appel après bascule : balaie TOUTES les saisons périmées présentes (pas seulement la précédente — couvre une saison entière sans trafic), classe les users `season_id == old`, crédite les podiums, insère les marqueurs, **UNE transaction** ; concurrence inter-workers par PK + `IntegrityError → rollback`. ⚠️ Avantage clé : les joueurs INACTIFS (points non resetés) sont inclus dans le règlement de leur saison. `router._finalize_if_over` enveloppe déjà `process_match_results` dans un try/except → un échec de règlement ne casse jamais un game_over.
> - **`GET /leaderboard` (additif).** Nouveaux params `division` (BRONZE|ARGENT|OR|PLATINE|ELITE) et `tier` (I|II|III), **scope season uniquement** : filtre `season_points` par `tier_bounds`, tri `_SEASON_ORDER_BY`, **`rank` = position DANS LA TRANCHE** (navigation par sous-division du client §8.98). `rules` : `tier_rp: 200`, `division_floor_lock: false`, `rewards_coins` = enveloppes, **nouvelle clé `reward_splits: {"tiers":[50,30,20], "podium":[50,30,20]}`** (ordres I/II/III et 1ᵉʳ/2ᵉ/3ᵉ). Le bloc `divisions` (CASE/GROUP BY) dérivait déjà de `DIVISIONS` → suit les nouveaux seuils sans retouche (floors 0/600/1200/1800/2400, ceilings 599/1199/1799/2399/null).
> - **Validation (agent, puis RE-VÉRIFIÉE indépendamment).** `py_compile` OK (12 fichiers). `test_seasons.py` **72 OK** (bornes, `tier_bounds`/`tier_envelope` — les 12 enveloppes assertées —, `season_podium_rewards`, `ensure_season` SANS crédit) ; `test_rewards.py` **303 OK** (chute de division, ÷2 BRONZE, plancher 0 strict) ; **NOUVEAU `test_season_settlement.py` 22 OK** (crédits = fonction pure, idempotence marqueur, balayage multi-saisons, marqueur posé même sans joueur, saison courante intouchée) ; `test_ladder_payload.py` **32 OK** ; non-régression `test_bot_flow.py` 47 ✅, `test_ranked_room.py` 17 ✅, `test_bot_ai.py` 30 OK. Dump de contrat rejoué à la main : `rank_info(1547)` → OR II 147/200 ; podiums {OR I ×4 → 500/300/200 + 4ᵉ rien ; ÉLITE ×2 → 5000/3000 ; BRONZE III ×1 → 50}. ⚠️ `test_bot_ai.py` retouché HORS liste initiale (seed du cache de règlement dans son bootstrap) : ses stubs sans `SeasonSettlement` auraient cassé au premier run POSTÉRIEUR à la bascule S1→S2 (2026-09-29) — bombe à retardement désamorcée, même seed dans `test_rewards.py`.

### 8.101 (bug de prod). `game_over` PERDU quand la partie se termine sur une action de BOT ou une minuterie — self-cancel dans `_finalize_if_over` (Backend, 2026-07-17)
> **Symptôme (constaté par Hakim, systématique).** Quand il ne gagnait PAS (éliminé, ou bot vainqueur), le Rapport Post-Op restait sur « en attente du classement… » et les onglets XP JOUEUR / XP HÉROS sur « récompenses en attente du serveur » **à perpétuité** — alors que la DB, elle, créditait bien XP/coins/ladder. Quand il gagnait, tout marchait. **Aucune erreur côté client** (logs Godot propres).
>
> - **Cause racine (asymétrie vainqueur/perdant = CHEMIN de fin de partie).** `_finalize_if_over` appelle `cancel_room_bots(room_id)` et `timers.cancel(room_id)` AVANT d'envoyer le `game_over`. Or quand la partie se clôt sur une **action de BOT** (cas : joueur humain battu), `_finalize_if_over` s'exécute **À L'INTÉRIEUR de la task bot** (`_run_bots` → `_finalize_if_over`) : la `.cancel()` visait la **task COURANTE** (self-cancel — piège asyncio déjà documenté au G2) → `CancelledError` levée au premier `await` suivant, précisément le `asyncio.gather(...)` d'ENVOI du `game_over` → **message jamais livré à personne**, et `manager.finished` (posé AVANT l'envoi) interdisant toute seconde chance. L'exception mourait silencieusement dans le `except CancelledError` de `_run_bots`. Même piège latent sur les fins par MINUTERIE (AFK → `_force_end_and_broadcast`/`_handle_abandon` s'exécutent DANS la coroutine d'expiration que `timers.cancel` annulait). Quand un HUMAIN clôt la partie (son attaque), `_finalize_if_over` tourne dans SA task routeur → les annulations visent d'AUTRES tasks → envoi OK. Contre-épreuve asyncio pure : self-cancel → `CancelledError` au gather, 0 envoi abouti.
> - **Correctif — garde anti self-cancel dans les TROIS annulateurs** (`connection_manager.RoomTimers.cancel`, `bot_runner.cancel_room_bots`, `router._cancel_draft_timer`) : si la task à annuler EST `asyncio.current_task()`, on ne l'annule pas — on l'OUBLIE seulement du registre (elle se termine d'elle-même juste après, gardes `manager.finished` en tête de boucle). Annuler une AUTRE task : comportement historique intact. Aucun changement de contrat réseau — le message `game_over` (§8.83/§8.88) est enfin livré dans TOUS les scénarios de fin.
> - **Tests (`test_bot_flow.py`, cas 9-10 — suite 57 ✅/0 ❌).** (9) fin de partie finalisée DEPUIS la task bot enregistrée → la task survit, le `game_over` EST délivré au perdant humain (rankings vainqueur en tête, `match_rewards` redacté par destinataire) ; chemin humain : la task bot est toujours annulée (non-régression). (10) gardes unitaires `timers.cancel`/`_cancel_draft_timer` (pas de self-cancel, oubli du registre, annulation d'une autre task intacte).
> - ⚠️ **Redéploiement VPS requis** (push sur `main` → deploy auto) : tant que la prod n'a pas ce correctif, les fins de partie sur action de bot/minuterie continuent de perdre le `game_over` — le client §8.100 affiche alors un classement PROVISOIRE calculé localement, mais les récompenses, elles, ne peuvent pas s'inventer côté client.

### 8.104. Refonte des identités de factions (noms propres EN) + i18n réseau (full-stack, 2026-07-18)
> **Refonte d'identité + internationalisation.** Chaque faction porte un **nom propre ANGLAIS INVARIANT** (« Steel Phalanx », « Dust Reavers », « Aegis Corporation », « Isotope Covenant », « Hive Ascendant », « Scrap Barons », « Ash Flayers », « Eden Wardens », « Shadow Hunters », « Eclipse Order ») et son héros est un **personnage nommé**, Général ou Capitaine de la faction (table complète : `ARCHITECTURE_ET_REGLES.md` §4.3). Les **ids réseau sont INCHANGÉS**. Volet frontend : §8.104 de [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md). ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**.
> - **`GET /api/v1/heroes` — 3 champs ADDITIFS par héros :** `hero_name` (ex. `"Viktor Stahl"`), `hero_callsign` (ex. `"Ironline"`), `hero_rank` (`"general"` | `"captain"` — code TRADUIT côté client via `RANK_GENERAL`/`RANK_CAPTAIN`). `faction_name` et `hero_power` restent émis mais leurs **valeurs passent en anglais invariant** ; le client à jour affiche ses propres clés locales (`HERO_POWER_NAME/DESC_<ID>`) et n'utilise plus ces champs qu'en repli. Test : `test_heroes_roster.py` (contrat de clés étendu).
> - **NEUF `system_events: [{code, ...params}]`** — évènements système STRUCTURÉS, portés par les mêmes évènements que `system_messages` (`turn_passed` / `units_moved` / `card_kept` / `blind_deploy_submitted`). Codes : `zone_forecast` `{territory_ids: [str]}` (télégraphe G1) et `zone_protected` `{faction_id, territory_id}` (immunité Isotope Covenant). Un client à jour **traduit les codes localement** (clés `FEED_ZONE_*`) et **ignore** alors les `system_messages` ; un vieux client ignore le champ inconnu (rétro-compatible). Les chaînes `system_messages` legacy passent en **anglais invariant** (`☢ WEATHER ALERT: …`, `Isotope Covenant shielded <Territory>` — libellés territoire = id title-case, `GameEngine._territory_label`). ⚠️ Le repli de classement du War Feed par sous-chaîne (`war_feed.gd`) détecte désormais `"shielded"` (l'ancien motif FR reste en double pour un serveur legacy).
> - **Objectifs — descriptions serveur en anglais invariant** (`objectives.py` : « Control at least N territories. », « Kill the hero of player #X — OR — … »). Le client compose la description TRADUITE de **son propre** objectif à partir de `type`/`params` (composeur `objective_tracker.describe`, clés `OBJ_DESC_*`) ; les descriptions serveur ne servent plus qu'aux révélations de fin de partie et au `spy_result` (affichées telles quelles, EN).
> - **Bots :** indicatif `HALFLIFE` → `ASHFANG` (collision avec le callsign du héros Ezra « Halflife » Voss). `PlayerState.username` et le préfixe client « [IA] » sont inchangés.
> - **Périmètre stable :** `PlayerState.faction` = id ; `faction_id` partout (draft, boutique, télémétrie, DB) ; drapeaux de combat (`phalanges_reroll`, `aegis_kill`, `terror_kill`, `first_strike`, `razzia_reroll`) = clés réseau inchangées.

### 8.105. Objectifs révélés/espionnés TRADUISIBLES — forme structurée additive (Backend, 2026-07-18)
> **Finition de §8.104.** Les deux seuls endroits où un objectif devient légitimement visible envoyaient uniquement une `description` texte (anglais invariant depuis §8.104) : le client ne pouvait donc pas la traduire. Ils portent désormais AUSSI la forme **structurée**. ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**.
> - **Helper `objectives.public_shape(objective) -> dict`** : renvoie `{type, params}` (+ `kill_objective` / `classic_objective` pour un objectif DOUBLE, même forme), **SANS `description`**, avec **copies défensives** des `params` (muter le retour ne touche jamais l'état de la partie). Entrée vide/mal formée → `{}`.
> - **`game_over.objectives_reveal[]` += `objective`** (bloc PUBLIC, inchangé par ailleurs : `player_id`, `username`, `description`, `completed`).
> - **`spy_result` += `objective`** (message PRIVÉ à l'espion). Lu APRÈS `GameEngine.resolve_spy` (qui ne mute que les drapeaux de l'ESPION, jamais l'objectif de la cible).
> - **Aucune fuite nouvelle** (piège n° 9) : c'est le MÊME contenu que la `description` déjà envoyée à côté, sous forme exploitable. `public_shape` n'est appelée qu'à ces 2 points — jamais dans l'état diffusé en cours de partie, où la redaction reste intacte.
> - **Rétro-compat DOUBLE SENS :** champ ADDITIF → un vieux client l'ignore ; un client à jour face à un serveur non redéployé reçoit `{}` et **retombe sur `description`** (`main._objective_text`).
> - **Tests.** `test_objectives_double.py` **40 ✅ / 0 ❌** (suite [6] NEUVE, 12 cas : type/params/volets conservés, aucune `description`, non-aliasing des `params`, objectif simple, entrées dégénérées `{}`/`None`/sans type). Régression : 19 suites backend vertes (`test_missions.py` échoue **à l'identique sur HEAD** — préexistant, vérifié en worktree isolé).

### 8.106. Refonte PROFIL — fondations de données, livre de comptes Coins, 4 endpoints (Backend, 2026-07-19)
> **Chantier J de `PROMPT_PROFIL_REFONTE.md`.** L'écran Profil devient un hub à onglets (volet client : §8.106 de `FRONTEND_INTERFACES.md`) ; le backend lui livre tout ce qui lui manquait. Contrat détaillé **réécrit en §9.1**. ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**.
> - **`MatchHistory` += 7 colonnes ADDITIVES** (`is_ranked`, `final_rank`, `players_count`, `xp_earned`, `rp_delta`, `hero_xp_earned`, `coins_earned`), toutes `server_default` → auto-migrées au boot (`db_migrations.sync_missing_columns`). Écrites par `process_match_results`, qui disposait déjà de toutes ces valeurs sans les persister. ⚠️ **`db.add(MatchHistory(...))` a été DÉPLACÉ après le crédit héros** : `coins_earned` doit totaliser les DEUX sources de Coins du match — le laisser en place l'aurait sous-évalué silencieusement.
> - **`final_rank` est 1-BASED** (0 = place INCONNUE, réservé aux lignes legacy), alors que `MatchParticipant.rank` (télémétrie G6) est 0-based. Divergence VOULUE et commentée aux deux endroits.
> - **LIVRE DE COMPTES `CoinTransaction`** (table neuve) + module DB-aware **`api/game/economy.py`** : `record_coins(db, user, delta, reason, ref)` devient l'**UNIQUE point de mutation de `User.coins`** du dépôt. Delta 0 → no-op total (aucune ligne). Garde bots (id < 0). Débit insolvable → clamp à 0 + WARNING, en journalisant le delta RÉELLEMENT appliqué (le ledger ne ment jamais sur le solde). Ne commit pas (transaction de l'appelant).
> - **6 sites de mutation refactorés** — le prompt en listait 5, le 6ᵉ (`season_settlement.py`, primes de podium) a été trouvé au grep et inclus : `state_manager` ×2 (paliers de niveau / niveaux de héros), `missions.claim`, `shop._charge_coins` (débit), `shop.purchase_fiat` (crédit), `season_settlement`. **Comportement extérieur et montants strictement INCHANGÉS.** Vérification : `\.coins\s*=` ne matche plus QUE `economy.py:129` en code de production.
> - **Compteurs de GAIN RÉEL du Pass** sur `User` (`pass_bonus_xp_total`, `pass_bonus_mission_coins_total`, `pass_hero_coins_total`), incrémentés au point exact où chaque avantage s'applique. Les deux premiers sont **DIFFÉRENTIELS** (surplus seul) ; le troisième est un TOTAL assumé (tirage aléatoire → le « sans Pass » n'existe pas).
> - **Registre PUR `api/game/pass_catalog.py`** (multi-tiers prêt) : valeurs DÉRIVÉES de `rewards.py`, jamais dupliquées. ⚠️ Les multiplicateurs y sont convertis en **bonus % ENTIER** (1.25 → 25) : le piège JSON float §5 interdit d'exposer un flottant, et c'est aussi la forme qu'attendent les libellés i18n (`%d %%`).
> - **`api/game/ladder.py` NEUF** : `season_rank_of` + `SEASON_ORDER_BY` EXTRAITS de `leaderboard.py` (plus de copie). Le Profil et le Classement annoncent désormais le même rang par construction — une seconde implémentation aurait dérivé.
> - **`api/game/profile_stats.py` NEUF** (PUR) : tout le post-traitement des GROUP BY (winrate, place moyenne en dixièmes, tris stables, repli du bloc `season`). Règle d'Or §6 : le SQL reste dans l'endpoint, le CALCUL vit dans `api/game/*` — et devient testable sans DB ni FastAPI.
> - **4 endpoints** : `/profile/stats` ÉTENDU (+`season`/`factions`/`modes`/`form`), `/profile/history` ÉTENDU (filtres `wins_only`/`ranked_only` + `offset`, tous à défaut neutre), `/profile/finance` NEUF, `/profile/pass` NEUF.
> - **Tests.** `test_economy.py` NEUF **76 ✅ / 0 ❌** ; `test_profile_data.py` NEUF **66 ✅ / 0 ❌** ; `test_rewards.py` ÉTENDU (2 suites : détail de match persisté, ledger, compteurs Pass, cas non classé). Régression : suite backend complète **au niveau du BASELINE** — les 3 seuls échecs restants (`test_missions` 37/4, `test_seasons`, `test_simulation`) sont **PRÉEXISTANTS et identiques sur HEAD**, vérifiés dans un worktree isolé (`git worktree` sur HEAD) avant/après.
> - **Stubs de test mis à jour** (5 suites) : les doublures `models.models` doivent exposer `CoinTransaction`. `economy` l'importe **à l'appel** (convention de `state_manager`) pour ne pas forcer toute suite important `economy` à connaître une table qu'elle ne teste pas.
> - ⚠️ **Piège rencontré.** `record_coins` ne doit PAS faire `int()` sur `user.id` : c'est une clé étrangère repassée telle quelle, et les doublures maison exposent un objet-colonne quand l'instance ne shadowe pas l'attribut de classe (`TypeError` dans `test_rewards`). Garde bots réécrite en `isinstance(user_id, int) and user_id < 0`.
> - **Archive** : `backend/migration_profile.sql` (7+3 colonnes + table + index), patron `migration_seasons.sql`.
### 8.107. Stats par CARTE + PROFIL PUBLIC consultable depuis le Classement (Backend, 2026-07-19)
> **Options 1 et 2 du §9 de `PROMPT_PROFIL_REFONTE.md`, validées par Hakim.** Consigne : **strictement ADDITIF, ne rien modifier à l'existant**. Contrat détaillé en **§9.1**. ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**.
> - **`MatchHistory.map_id`** (additive, auto-migrée). ⚠️ `server_default=""` = carte **INCONNUE**, et NON `"classic_42"` comme sur `game_rooms` : les lignes legacy couvrent aussi des parties POSTÉRIEURES au registre multi-cartes (G5), les estampiller « classique » inventerait une donnée. L'agrégat EXCLUT les `""` (patron de `faction_id != ""`).
> - **`process_match_results(…, map_id: str = "")`** — paramètre à **défaut neutre** : tous les appelants historiques et les tests restent valides sans modification. Seul `router._finalize_if_over` passe la vraie valeur (`getattr(state, "map_id", "")`, même garde défensive que `is_ranked`). `game.py` n'appelle pas cette fonction (vérifié).
> - **Bloc `maps` ADDITIF** sur `/profile/stats` + helpers PURS `profile_stats.map_entry` / `sort_maps`.
> - **`GET /profile/public/{username}` NEUF** — palmarès d'un tiers.
>   - **Routé par PSEUDO, pas par id.** `LeaderboardEntry` exclut délibérément l'id technique ; la décision est **maintenue** plutôt que contournée. Router par `username` (déjà public, `unique`, indexé) évite d'introduire un identifiant **séquentiel énumérable** — et ne change RIEN au contrat du Classement (§9.2).
>   - **`PublicProfileResponse` = LISTE BLANCHE explicite**, jamais un héritage de `ProfileStatsResponse` : par héritage, tout champ ajouté demain au profil privé (un solde, un bloc finance) deviendrait public **tout seul**. Ni `credits`, ni FINANCES, ni PASS, ni `email`/`id`/`xp`.
>   - ⚠️ **LECTURE SEULE** : `_public_season_block` n'appelle **ni `settle_previous_season` ni `ensure_season`**. Les déclencher ferait ÉCRIRE dans la ligne d'un AUTRE joueur au passage d'un visiteur (reset de saison provoqué par un GET d'un tiers, course entre visiteurs). Joueur hors saison courante → **0 RP et rang inconnu**, sans persistance.
> - **Tests.** `test_profile_data.py` **85 ✅ / 0 ❌** (+19 : suite [G] cartes, suite [H] **frontière de confidentialité** — liste blanche EXACTE, aucun champ interdit, non-héritage du schéma privé, témoin `credits` côté privé). `test_rewards.py` : `map_id` persisté sur chaque ligne du match, et `""` quand l'appelant ne le fournit pas. `test_game_over_redaction.py` **30 ✅ / 0 ❌** (+1 : propagation du `map_id` de l'état).
> - ⚠️ **Piège rencontré (2ᵉ fois).** Les stubs `_fake_pmr` de `test_game_over_redaction.py` doivent suivre la signature RÉELLE de `process_match_results` : un stub trop étroit lève un `TypeError` **AVALÉ par le try/except fail-safe du routeur** → récompenses vides et test faussement rouge (4 KO). Le fichier le documentait déjà pour `is_ranked` ; l'avertissement a été étendu à `map_id`. **Élargir CES stubs à chaque paramètre ajouté.**
> - Régression : suite backend **35/38 vertes** — les 3 rouges (`test_missions` 37/4, `test_seasons`, `test_simulation`) sont **PRÉEXISTANTES et identiques sur HEAD**.

### 8.108. Refonte BOUTIQUE — catalogue, prix, et les 3 Pass (Plus / Premium / Infinity) (Backend, 2026-07-19)
> **Chantiers P et R de `PROMPT_BOUTIQUE_REFONTE.md`.** Contrat détaillé en **§9.3**. ⚠️ **Backend → redéploiement VPS requis** (tant qu'il ne l'est pas, un client à jour verra l'ANCIEN catalogue : c'est ce qui a été observé en validation visuelle) ; **AUCUN COMMIT**.
> - **Prix recalibrés** : personnages **10 000-12 000** Coins (au lieu de 4 500-5 500) → un personnage vaut désormais ≈ le pack Vétéran, et la rotation hebdomadaire (§8.109) devient le chemin d'essai. Packs de Coins re-dotés **5 000 / 12 000 / 25 000 / 80 000** à prix € INCHANGÉS ; ratios Coins/€ vérifiés **strictement croissants** (1002 < 1201 < 1251 < 1600) → l'incitation « meilleure valeur sur les gros packs » est préservée. Renommages : « Pack Éclaireur » → **Explorateur**, « Pack Seigneur de Guerre » → **Seigneur de la Guerre**.
> - **Couverture SKINS complète** : 6 skins ajoutés → **1 par personnage** pour les 10 factions (il en manquait 6). Côté client, le système est data-driven (scan `DirAccess` de `resources/skins/*.tres`) : 6 `.tres` neufs, aucune table à étendre.
> - **`api/game/pass_catalog.py` porté à 3 NIVEAUX.** `PASS_TIERS` (dict) devient la SOURCE unique des multiplicateurs — `state_manager`, `missions.claim` et le Profil lisent tous ICI. `rewards.PASS_XP_MULT` / `PASS_MISSION_COINS_MULT` / `HERO_COINS_PASS_*` sont marquées **OBSOLÈTES mais conservées** : elles décrivent EXACTEMENT le niveau `premium`, ce qui sert de non-régression au mapping legacy (test dédié).
>   | niveau | € | coins héros | XP | missions | personnages |
>   |---|---|---|---|---|---|
>   | `plus` | 7,99 | ×2 (2-10) | +10 % | +30 % | 1 aléatoire |
>   | `premium` | 12,99 | ×4 (4-20) | +25 % | +50 % | la moitié (2) |
>   | `infinity` | 19,99 | ×5 (5-25) | +50 % | +100 % | tous |
> - **Nouvelle convention des coins de héros** : le tirage de BASE `randint(1,5)` est **multiplié** par `hero_coins_mult` (au lieu d'une fourchette dédiée par niveau). `rewards.hero_levelup_coins` gagne `coins_mult` ; `has_pass` devient un **alias DÉPRÉCIÉ** consulté uniquement si `coins_mult == 1` — les appelants et tests historiques restent donc verts sans modification.
> - **`User.pass_tier`** (String, auto-migrée) + **table `pass_faction_grants`** (`create_all`, UNIQUE user+faction+season). **Mapping LEGACY (§2.3)** : un pass ACTIF sans `pass_tier` = ancien Pass Spécial → lu comme **premium** jusqu'à expiration, **aucune migration de données** (2 lignes dans `tier_of`).
> - **Achat** : helper PARTAGÉ `_apply_pass_purchase` (route fiat ET route virtuelle) → pose du niveau, expiration = fin de saison, skin de saison, puis TIRAGE des personnages. **Upgrade** : uniquement vers un rang STRICTEMENT supérieur, expiration INCHANGÉE, tirage **COMPLÉMENTAIRE** (les grants déjà accordés sont conservés et complétés jusqu'au volume du nouveau niveau). Rang égal/inférieur → 400.
> - ⚠️ **`CURRENT_TIER_ID` SUPPRIMÉ** de `pass_catalog` : « le seul niveau vendu » n'a plus de sens à 3 niveaux. `GET /profile/pass` renvoie désormais `tier_id = tier_of(user)` — le niveau **réellement détenu** (`""` si aucun).
> - **Tests.** NOUVEAU `test_pass_tiers.py` **91 ✅ / 0 ❌** (registre, `tier_of` incl. legacy et niveau inconnu, tirages déterministes via `rng` injecté, wiring RÉEL dans `process_match_results` — XP en floor et `coins_mult` espionné —, missions, upgrade/refus, gate 501). `test_economy.py` §C réécrit pour les 3 niveaux (**79 ✅**), `test_seasons.py` porté sur `_apply_pass_purchase` (**77 OK — il était ROUGE sur HEAD**, fixture `PassItem` sans `purchasable`).

### 8.109. ACCÈS TEMPORAIRES — rotation à 1 personnage, 5 parties gratuites, PURGE de progression (Backend, 2026-07-19)
> **Chantier Q de `PROMPT_BOUTIQUE_REFONTE.md`.** Remplace le modèle « 2 factions gratuites en illimité » de §8.66. ⚠️ **Backend → redéploiement VPS requis** ; **AUCUN COMMIT**.
> - **`rotation.py`** : `ROTATION_COUNT = 1` (au lieu d'une paire) et `FREE_ROTATION_GAMES_MAX = 5` — **source unique** du plafond, lue par `access.py`, l'endpoint et les messages d'erreur. `free_faction_ids` **reste une LISTE** (contrat inchangé, §1.5).
> - **NOUVEAU [`api/game/access.py`](backend/api/game/access.py)** — SOURCE UNIQUE de « ce joueur peut-il jouer cette faction, et à quel TITRE ? ». Cinq titres, du plus fort au plus faible : `free` / `owned` / `pass` / `rotation` / `locked`. Avant, la réponse était éparpillée (rotation dans le routeur, possession dans `_owns_faction`, et `/heroes` répondait `owned: true` PARTOUT). `faction_access_map` répond pour les 10 factions en **3 requêtes** (et non 30).
> - **Table `free_rotation_plays`** (UNIQUE user+week) : le compteur porte la SEMAINE → il se remet à zéro **tout seul** au changement de semaine, sans purge ni cron. Le crédit est consommé au **VERROUILLAGE du draft** (§2.6) — abandonner ensuite ne rend pas la partie (anti-esquive) ; l'auto-verrouillage à l'échéance pose une faction PROVISOIRE toujours gratuite, il ne consomme donc jamais rien.
> - ⚠️ **ANTI DOUBLE-DÉBIT (garde ajoutée en revue).** Le draft reste OUVERT tant que la Phase 0 n'est pas armée : un client peut ré-émettre `faction_choice` (re-clic, reconnexion, client modifié — le verrou `_confirmed` côté client n'est **qu'un confort**, §1.3). Sans garde, **chaque envoi débitait une partie gratuite** : le joueur pouvait en perdre jusqu'à 5 pour UNE seule partie. Le crédit n'est désormais consommé qu'**UNE fois par (joueur, salle)** (registre in-memory `_rotation_charged`, même durée de vie que `manager.locked_factions`, purgé à la destruction de la salle). Couvert par `test_rotation.py` (re-verrouillage → aucun second débit ; salle neuve → débit repris ; gratuite et bot → jamais de débit).
> - **PERTE DE PROGRESSION** — `HeroProgression.access_context` (additive) mémorise sous quel titre la progression a été gagnée : `""` = permanent, `"rot:<week_key>"`, `"pass:<season_id>"`. **PURGE LAZY** (`ensure_hero_progress_access`) à **4 points de lecture** : draft WS, démarrage REST, roster `/heroes`, fin de partie. Au changement de semaine / à l'expiration du Pass, la progression du personnage temporaire **disparaît à la première lecture**. Acheter le personnage **PÉRENNISE** l'état courant (contexte remis à `""`). Les lignes ANTÉRIEURES à cette mise à jour valent `""` → **jamais purgées rétroactivement**.
> - ⚠️ **La purge est une SUPPRESSION** : chaque point de lecture doit committer. `game.py::start_game` n'avait **aucun commit après sa boucle** — un commit conditionnel a été ajouté, sans quoi la purge était silencieusement rollbackée à la fermeture de la session.
> - **`GET /shop/rotation`** passe en **auth OPTIONNELLE** pour servir le compteur du joueur (jamais de 401). **`GET /heroes`** expose un bloc `access` par personnage et `owned` devient **RÉEL** (fin du stub).
> - **Code mort supprimé** : `router._owns_faction` et `state_manager._pass_active` (remplacés par `access.py` et `pass_catalog.tier_of`).
> - ⚠️⚠️ **`db.flush()` OBLIGATOIRE après le `db.delete()` de la purge (trouvé en revue).** Les sessions du projet sont créées avec **`autoflush=False`** (`core/database.py`). Sans flush, le DELETE n'est émis qu'au commit : **toute requête ultérieure de la même session retrouve la ligne** (identity map) avec ses anciennes valeurs, et SQLAlchemy **jette au flush les modifications faites sur un objet marqué `deleted`**. Concrètement, `credit_hero_xp` ressuscitait la ligne condamnée, y écrivait l'XP du match… qui partait à la poubelle au commit : le Rapport Post-Op annonçait « niveau 14, +380 XP » et la partie suivante retrouvait le héros **au niveau 1**. Même racine au démarrage de partie (stats vivantes chargées depuis une ligne déjà condamnée). ⚠️ Les doublures de test qui suppriment IMMÉDIATEMENT masquent ce bug — celles de `test_access.py` / `test_pass_tiers.py` reproduisent désormais `autoflush=False`, et une **contre-épreuve** (flush retiré → 6 ❌) prouve que la suite l'attrape.
> - ⚠️ **`access_context_for("locked")` ne renvoie PAS `""` (trouvé en revue).** Une partie peut se **terminer** alors que le titre qui la permettait vient d'expirer (bascule de semaine à 04:00 UTC, ou Pass échu, PENDANT la partie). Estampiller « permanent » offrait une progression **définitive** sur un personnage payant à qui savait faire chevaucher sa partie sur la bascule. Nouveau contexte **`CTX_EXPIRED = "expired"`** : le match est crédité honnêtement (le rapport dit vrai) puis la ligne est purgée à la première lecture. ⚠️ Ce trou était **masqué** par le bug de flush ci-dessus — le corriger seul l'aurait activé ; les deux ont été traités ensemble.
> - **Tests.** NOUVEAU `test_access.py` **63 ✅ / 0 ❌** — matrice des 5 titres, priorité (possédée ET en rotation → `owned`), grant d'une saison PASSÉE sans effet, rotation épuisée (le titre reste `rotation`, c'est le compteur qui tombe à 0), décompte hebdomadaire, purge (semaine suivante / Pass expiré / changement de saison / pérennisation à l'achat / legacy intouchée / préfixe inconnu préservé), gate skins. `test_rotation.py` porté à 1 personnage (**20 OK**). ⚠️ La session factice y **filtre réellement** (colonnes renvoyant un prédicat) : un fake « qui rend toujours la même ligne » ne saurait pas éprouver des filtres par semaine et par saison.

### 8.110. BOUTIQUE / DRAFT / PERSONNAGES / PROFIL — vitrine des 3 Pass et états d'accès (Frontend, 2026-07-19)
> **Chantiers S, T, U de `PROMPT_BOUTIQUE_REFONTE.md`.** Détail d'écran dans `FRONTEND_INTERFACES.md`. **AUCUN COMMIT**.
> - ⚠️ **Chantier S.1 SAUTÉ sur décision de Hakim** : le prompt demandait d'ajouter des « chips de filtre » à une « grille plate sans sections », mais §8.102 a déjà livré **4 onglets de catégorie** qui remplissent exactement ce rôle. On ne réécrit pas une UI livrée : seuls S.2-S.6 ont été faits.
> - **Vitrine des 3 Pass** : les avantages viennent des `perk_keys` SERVEUR (le `range(1,5)` en dur a disparu) — le client n'écrit plus **aucun chiffre du barème**. Badge « ★ POPULAIRE » sur Premium (choix de merchandising isolé dans une constante), **liseré or COMPLET** sur le niveau haut de gamme (les autres cartes n'ont qu'une arête gauche), et états par carte : niveau détenu → badge « PASS ACTIF · J-N » sans bouton ; rang inférieur → « INCLUS DANS VOTRE PASS » grisé ; rang supérieur → « AMÉLIORER ❯ ». ⚠️ Le badge « actif » ne s'affiche QUE sur la carte du niveau détenu (l'afficher sur les 3 laisserait croire qu'elles sont toutes acquises).
> - **Gate des SKINS** : un skin dont le personnage n'est possédé que TEMPORAIREMENT affiche « ✕ Nécessite le personnage : X » au lieu d'un CTA. Le serveur refuse de toute façon — le client explique POURQUOI plutôt que de laisser échouer l'achat.
> - **Draft & Personnages** : 4 états d'accès rendus (rien / chip or « ★ n/m » / chip cyan « PASS » / cadenas ✕ + prix), bannières dédiées au draft (compteur de parties, crédits épuisés, déblocage par Pass), et **ligne d'avertissement** dans le détail d'un personnage à accès temporaire — le joueur doit savoir AVANT d'investir des heures que la progression sera purgée.
> - **Profil, onglet APERÇU** : carte « PERSONNAGE GRATUIT DE LA SEMAINE » — pastille de faction, jauge à **5 pips** (◆ or = disponible, ◇ muet = consommée), « n/m PARTIES RESTANTES », « NOUVEAU PERSONNAGE DANS J-n ». Masquée si la rotation est inconnue ou le joueur non authentifié. Placée AVANT la bande de forme, qui sort de la fonction par un `return` quand l'historique est vide (sinon le widget disparaissait pour un nouveau joueur — précisément sa cible).
> - **Gate 501** : `network_manager` expose `last_purchase_http_code` (le signal `shop_purchase_failed` ne transporte qu'un message ; **on n'a PAS changé sa signature**, ce qui aurait cassé toute callable connectée). Un 501 devient « Paiements réels bientôt disponibles. » au lieu du texte technique du serveur.
> - **GLYPHES** : le prompt demandait 🔒 et ✦. Mesure sur `ui_strings.csv` : **0** emoji cadenas (purge §8.102), 0 ✦, mais ★ ×36, ⚠ ×15, ✕ ×6, ❯ ×216. On s'en tient aux glyphes **éprouvés** (✕ pour le verrou, ★ pour la rotation, ⚠ pour l'avertissement) — un dingbat inconnu de la police condensée donne du tofu (cf. le « ⏻ » hérité).
> - **Doublon corrigé après capture visuelle** : le prompt demandait À LA FOIS un perk « déblocage personnages » ET une mention « nombre de personnages débloqués » — à l'écran, la même information s'affichait deux fois sur chaque carte. La version SERVEUR (data-driven) est conservée, la ligne cliente supprimée. Libellés « PASS SPÉCIAL » → « PASS » (il y a 3 niveaux, l'ancien article est retiré).
> - **Outil de validation `tools/preview_shop_v2.gd` remis à jour** (catalogue miroir, 3 Pass, compteurs) et **2 bugs corrigés** : il appelait encore `_on_history_loaded` (renommé `_on_history_page_loaded` en §8.106), et son chemin de sortie absolu datait d'une session morte (→ variable d'environnement `WW_PREVIEW_OUT`, repli `user://`).
> - ⚠️ **PIÈGE DE VALIDATION VISUELLE (2 fois de suite).** (1) Éditer un `.gd` **après** un `--import` ne suffit pas : il faut **ré-importer** avant de relancer, sinon le script exécuté est celui du cache. (2) Le `_ready()` de `shop.tscn` lance de VRAIS fetchs : si un backend est joignable, sa réponse **écrase** les données de démonstration ~1 s plus tard — on capture alors le catalogue du serveur **déployé** (périmé) en croyant valider le code local. L'outil injecte désormais APRÈS que le réseau ait parlé.
> - **Validation.** `--import` **0 ERROR** ; boot headless **0 ERROR** sur `shop`, `characters_screen`, `profile`, `main_menu`, `faction_selection` ; captures PNG des 4 onglets boutique + profil conformes aux critères d'acceptation (3 pips pleins sur 5 pour « 3/5 parties restantes »). **28 clés i18n** ajoutées/mises à jour en fr/en/it (954 au total).
### 8.111. `GET /api/v1/heroes` ENRICHI — identité, palmarès, évolution (Backend + Frontend, 2026-07-20)
> **But.** Alimenter la refonte de l'écran Personnages (roster en cartes + fiche à 4 onglets,
> `FRONTEND_INTERFACES.md` §8.111). **Blocs 100 % ADDITIFS** : aucune clé existante n'est renommée
> ni supprimée (`faction_id, faction_name, hero_power, level, xp_*, stats, stats_max, milestones,
> owned, access` inchangés) — un client antérieur qui les ignore fonctionne à l'identique (§1.5).
>
> - **`identity`** `{first_name, last_name, callsign, char_code, rank, display_name}` — noms propres
>   **INVARIANTS** (non localisés : ce sont des données, pas des libellés). `display_name` est
>   **PRÊT À AFFICHER** : le client ne concatène ni ne découpe jamais lui-même. Repli si une faction
>   n'a pas d'identité : `display_name` = nom de la faction (jamais la chaîne « None »).
> - **`faction_category`** `str` — `combat` / `cartes` / `zone` / `mouvement` / `renforts`. Jusqu'ici
>   le client devait redemander `/factions` pour l'obtenir. Traduit côté client par
>   `FACTION_CATEGORY_<CATEGORIE>` ; clé absente → la mention est masquée, jamais affichée brute.
> - **`record`** `{games, wins, losses, winrate}` — palmarès **par personnage**, agrégé sur
>   `MatchHistory` en **UNE requête `GROUP BY faction_id`** pour les 10 factions (pas 10 requêtes).
>   Bloc TOUJOURS présent, zéros compris : « jamais joué » est une donnée, pas une absence.
> - **`evolution`** `{levels_left, coins_potential{base, plus, premium, infinity}, coins_earned}` —
>   `levels_left` et `coins_potential` sont **PURS** (`pass_catalog.hero_coin_potential`, aucune DB) ;
>   `coins_earned` vient du **ledger** (`CoinTransaction`, `reason = hero_level_coins`, `ref =
>   faction_id`) et est injecté par l'endpoint, qui seul a la session. Fourchettes `[min, max]`
>   d'**entiers purs**. Niveau 50 → `levels_left = 0` et toutes les fourchettes à `[0, 0]`.
>   ⚠️ **`coins_earned` ABSENT** (ledger non déployé) est un cas légitime : le client MASQUE la carte
>   plutôt que d'afficher « 0 », qui serait un mensonge et non un repli.
> - **Dérivation côté client, pas de barème dupliqué.** Le comparatif des Pass affiche les Coins
>   **par niveau** en divisant `coins_potential[tier]` par `levels_left` (exact par construction) —
>   les valeurs 1-5 / 2-10 / 4-20 / 5-25 ne sont recopiées nulle part dans le client.
> - **Aucun paramètre neuf sur `/shop/catalog`.** Les skins EXCLUSIFS de Pass (`purchasable: false`)
>   sont déjà servis par **`?include_all=1`** (§8.102), que `NetworkManager.fetch_shop_catalog()`
>   passe déjà — le paramètre `?include_exclusive=true` initialement envisagé aurait été un synonyme.
> - **`pass_tier`** (déjà servi par `GET /shop/inventory`) sert à surligner la colonne du Pass ACTIF.
> - **Correction documentaire.** Les docstrings parlaient de stats « au niveau 100 » alors que le cap
>   réel est `HERO_LEVEL_MAX = 50` et que `stats_max` était déjà calculé à 50.
> - **Validation.** `backend/test_heroes_roster.py` **483 ✅ / 0 ❌** (forme des 4 blocs, fourchettes
>   exactes par tier, niveau 50 → zéros, absence propre des blocs optionnels, pureté JSON : aucun
>   float hors `pb`/`regen`).

---

> **§8.112 — Nettoyage « points de match » + lobby idempotent + observabilité 4xx (chantiers AA/AB/AC, `PROMPT_NETTOYAGE_SECURITE.md`).** ⚠️ **Backend → push + redéploiement VPS requis.**
> - **« Points de match » RETIRÉS (AA).** Le schéma `MatchRewards` de `game_over.match_rewards` n'a **plus** la clé `match_points` (économie de fin de partie = XP joueur, XP héros, Coins, **RP saisonnier** — seul ladder). La colonne `User.points_classement` est **SUPPRIMÉE du modèle ORM** (option §8.1 ; `backend/migration_drop_points.sql` retire la colonne SQL orpheline — à exécuter APRÈS déploiement, sinon l'auto-migration la recréerait). Le classement mondial (`GET /leaderboard`, §9.2) ne renvoie plus `points_classement` dans `LeaderboardEntry` ; le **départage lifetime** est désormais `stats_parties_jouees` (victoires > niveau > parties > id). Le champ `is_ranked` reste PUBLIC : une partie non classée ne crédite simplement aucun ladder.
> - **REJOUER = MÊME MODALITÉ (AB, §8.70).** Le re-queue reproduit EXACTEMENT la partie terminée : même carte (`map_id`), même effectif (`max_players`), même statut classé (`is_ranked`) — capturés sur l'état joué (repli `MatchConfig`). Le scan ne rejoint qu'une salle compatible ; sinon une salle est CRÉÉE à l'identique (payload `create_room` étendu `map_id`/`is_ranked`).
> - **Lobby IDEMPOTENT (AC — zéro 4xx en jeu normal).** `POST /lobby/rooms/{id}/join` ne renvoie plus de 4xx sur les courses bénignes : `200 {"joined": true}` (succès), `200 {"joined": true, "already": true}` (déjà membre, double-clic non fautif), `200 {"joined": false, "reason": "unavailable"}` (salle absente/plus `waiting`), `200 {"joined": false, "reason": "full"}` (pleine). `DELETE /lobby/rooms/{id}/leave` devient idempotent : `200 {"left": true}` (succès + suppression de la salle vide inchangée) / `200 {"left": false}` (plus dans la salle — plus AUCUN 404). Le `message` texte historique reste en clé ADDITIVE. **Lecture client DÉFENSIVE** : un `200` sans clé `joined` = succès legacy.
> - **Observabilité 4xx/5xx.** Un middleware (`backend/main.py` → `core/http_observability.py`, testable hors app) journalise en `WARN` structuré toute réponse `status ≥ 400` (méthode, chemin, statut, User-Agent, user si le Bearer se décode) — best-effort, JAMAIS bloquant. But : après AC, un 4xx en jeu NORMAL est une ANOMALIE tracée (`docker logs backend` / Loki).
> - **Tests.** `test_lobby_idempotent.py` **17 ✅** (contrat join/leave + middleware, FakeSession) ; `test_game_over_redaction.py` **30 ✅** (fixtures `match_points`→`xp_earned`). `grep -ri match_points backend/ frontend/scripts/` = **0**. *(Edge/CrowdSec — chantier AD — documenté dans `infra/README.md` §10 + `infra/crowdsec/RUNBOOK_BANS.md`.)*
> - **Options §8 (TOUTES appliquées le 2026-07-23).** §8.1 : `points_classement` retirée de l'ORM + `migration_drop_points.sql`. §8.2 : polling lobby **5 s**. §8.3 : **blocage scan Traefik** (`infra/traefik/dynamic/scan-block.yml` → 403 immédiat, exclut `/api`+`/ws`, rechargé à chaud). §8.4 : **simulation** des scénarios http comportementaux (`infra/crowdsec/simulation.yaml` — le scénario CMS/AD bannit toujours). §8.5 : **alerte Prometheus** `Erreurs4xxApplicativesResiduelles` (401/404 backend soutenus > 15 min).

---

### 8.113. AUTHENTIFICATION STEAM EXCLUSIVE — « Sign in through Steam » (OpenID 2.0) (Backend + Frontend, 2026-07-24)

> Remplacement INTÉGRAL de l'authentification par mot de passe (`/auth/register` + `/auth/login`) par une connexion **exclusivement Steam**. ⚠️ **Backend → push + redéploiement VPS requis**, ET **deux actions humaines** : (1) ajouter `PUBLIC_API_URL` + `STEAM_API_KEY` au `.env` du coffre-fort VPS (vérifier avec `python tools/preflight_compose.py docker-compose.yml --env .env` — une variable oubliée = chaîne vide SILENCIEUSE) ; (2) appliquer `backend/migration_steam_auth.sql` sur la base de prod (l'auto-migration ne sait ni poser l'index UNIQUE ni relâcher un NOT NULL). ⚠️ **Conséquence ASSUMÉE : les comptes créés par mot de passe deviennent inaccessibles** — aucune passerelle de liaison n'est prévue.
>
> - **Le flux (client → backend → Steam).** Le jeu n'est pas (encore) lancé par le client Steam : la connexion passe par le **navigateur externe** du joueur, pas par le SDK Steamworks (l'architecture reste prête à recevoir plus tard une route de tickets Steamworks À CÔTÉ de celle-ci). Godot ne pouvant pas être rappelé (ni serveur HTTP local, ni deep-link), il **interroge** le backend. Contrat complet des 4 routes en **§5** : `POST /auth/steam/session` (session Redis `pending`, TTL 600 s) → `GET /auth/steam/login` (302 vers Steam, ouvert par `OS.shell_open`) → `GET /auth/steam/return` (callback navigateur, page HTML) → `GET /auth/steam/poll` (toutes les 2 s, rebours global 180 s, token servi UNE fois).
> - **Le JWT ne change PAS — c'est la clé de voûte.** Même secret, même HS256, même claim `sub` = `username`, même TTL. Aucune modification dans `get_current_user`/`get_current_user_optional`/`GET /auth/me`, dans `api/sockets/router.py` (`_authenticate_ws_token`, handshake `?token=`), ni dans les 7 endpoints consommateurs. Côté client, `user://session.dat` et la **reconnexion silencieuse au boot** fonctionnent à l'identique (vérifié en réel : un JWT sauvegardé AVANT la migration ouvre toujours le menu).
> - **Sécurité (ce qui empêche de forger une identité).** (1) **`check_authentication` serveur→Steam OBLIGATOIRE** — les `openid.*` arrivent par la barre d'adresse du joueur, donc entièrement forgeables ; sans ce round-trip, `?openid.mode=id_res&openid.claimed_id=…/765…` délivrerait le JWT de n'importe qui. (2) **Regex `claimed_id` STRICTE** `^https://steamcommunity\.com/openid/id/(\d{17})$` (point ÉCHAPPÉ, ancrée, https imposé) = seule source du SteamID. (3) **`return_to` vérifié en préfixe** avant tout appel — sans quoi une assertion authentique obtenue pour un AUTRE service serait rejouable ici. (4) `session_id` = `secrets.token_urlsafe(32)`, **usage unique** consommé atomiquement (`SET … GET` → sentinelle `checking`, jamais un `DEL` : la vérification dure plusieurs secondes et le poll doit continuer de répondre `pending`), TTL courts, destruction à la consommation et à tout échec. (5) Page de retour **statique** (aucune donnée de la requête réfléchie → zéro XSS) et **message d'erreur générique**. (6) Aucun secret (`STEAM_API_KEY`, JWT) journalisé — les exceptions `httpx` ne sont JAMAIS formatées, leur message porte l'URL complète donc la clé.
> - **Compte & pseudo.** Identité = **SteamID64** (`users.steam_id`, String — piège JSON float §5 : 17 chiffres ne survivraient pas à un `float`). `username` = persona name assaini (caractères de contrôle Unicode `C*` retirés, 24 car.) + anti-collision `_<4 derniers chiffres>` puis `_2`/`_3`… (boucle BORNÉE + garde `IntegrityError`/rollback/retry pour les courses inter-workers, qui re-cherche d'abord par `steam_id`). Repli **`Vagabond_<6 derniers chiffres>`** : `STEAM_API_KEY` absente, GetPlayerSummaries en panne/timeout/vide → **le login aboutit quand même** (l'API de profil n'est JAMAIS sur le chemin critique). Le persona name n'est pas resynchronisé ensuite (hors périmètre).
> - **Schéma.** `users.steam_id` (String, UNIQUE, indexé, nullable côté ORM pour l'auto-migration) ; `email` et `hashed_password` deviennent **NULLABLE** et ne sont plus jamais écrits — colonnes CONSERVÉES (pas de `DROP COLUMN` destructif). `UserBase.email` reste **EXPOSÉ à `null`** dans `/auth/me` (compat : un client installé qui lit la clé ne plante pas) ; `UserCreate` est SUPPRIMÉ. Archive : `backend/migration_steam_auth.sql`.
> - **Dépendances.** `+httpx>=0.27.0` (async — `requests` bloquerait la boucle d'événements pendant le round-trip Steam). `−passlib[bcrypt]`, `−bcrypt`, `−email-validator` (aucune occurrence restante, vérifié par grep) ; `python-multipart` et `python-jose` CONSERVÉS.
> - **Frontend.** `auth_manager.gd` : `register()`/`login()` supprimés → `start_steam_login()` / `cancel_steam_login()` + `HTTPRequest` et `Timer` DÉDIÉS (un `HTTPRequest` ne traite qu'une requête à la fois : mutualiser produirait des `ERR_BUSY`), garde `_steam_poll_in_flight`, rebours 180 s. ⚠️ **Correctif de détection** : la réponse `/auth/me` est reconnue par `has("username") and has("id")` — plus par `has("email")`, devenu trompeur (champ présent mais `null`). `auth_screen` : le `TabContainer` Connexion/Inscription est retiré de la scène au profit d'un **unique `SteamLoginButton`** (charte §2 conservée : parallaxe 2.5D, cendres, sélecteur de langue, `QuitButton`, auto-login) ; le bouton se désactive pendant l'attente et se réarme sur `auth_failed`. 4 clés i18n FR/EN/IT ajoutées, 10 clés orphelines retirées.
> - **Tests.** `backend/test_steam_auth.py` **99 ✅** (parsing `check_authentication` et ses pièges de sous-chaîne, 10 cas de regex `claimed_id`, anti-collision, tolérance aux pannes de GetPlayerSummaries, cycle de session pending→token→404, callback nominal + 6 refus fail-closed, invariants §3). Suite backend complète : **41/43 verts** — `test_missions.py` (4 KO) et `test_simulation.py` (fastapi absent du poste) échouaient **DÉJÀ à l'identique sur `HEAD`** (vérifié par `git archive HEAD`), hors périmètre. Godot : `--import` **0 ERROR**, boot `auth_screen` **0 ERROR**, capture PNG 1920×1080 de l'écran refondu, 4 clés résolues dans les 3 locales via `get_message()`. **Aucun commit.**

---

### 8.114. AVATAR STEAM — reconnaissance du compte au retour du navigateur (Backend + Frontend, 2026-07-24)

> Complément de **§8.113**. Après un aller-retour par le navigateur, le joueur doit reconnaître d'un coup d'œil que c'est bien SON compte : le pseudo Steam y suffisait à peine, l'avatar est le vrai signal. ⚠️ **Backend → push + redéploiement VPS requis**, mais **AUCUNE action manuelle** cette fois : la colonne a un `server_default`, donc `sync_missing_columns` l'ajoute seule au démarrage (contrairement à `steam_id`, dont l'index UNIQUE avait exigé du SQL à la main).
>
> - **Un seul appel réseau, deux usages.** `_fetch_steam_persona` devient **`_fetch_steam_summary`** → `{"persona", "avatar"}`. `GetPlayerSummaries` était déjà appelé à la création d'un compte ; il l'est désormais à **chaque** connexion, et sert les deux besoins d'un coup — les séparer aurait doublé la latence du callback pour rien. Toujours aussi **tolérant aux pannes** : clé absente, HTTP non-200, timeout ou payload vide → `{"", ""}`, la connexion aboutit.
> - **Rafraîchi, mais pas le pseudo.** `users.steam_avatar_url` est remis à jour à chaque login ; `username` **NE L'EST PAS** et ne peut pas l'être : il est le claim `sub` du JWT **et** la clé UNIQUE en base — le resynchroniser invaliderait les sessions en cours et entrerait en conflit avec l'anti-collision. Un pseudo Steam changé après coup restera donc figé côté jeu (dette assumée ; le remède propre serait un `display_name` découplé, non fait).
> - **Deux garde-fous à l'écriture** (`_refresh_steam_avatar`) : une URL **vide n'écrase jamais** celle en base (une panne momentanée de Steam ne doit pas effacer l'avatar d'un joueur), et une URL **identique n'écrit rien** (sinon chaque connexion produirait un COMMIT inutile). Ne lève jamais : un avatar est un confort, il ne peut pas faire échouer une connexion.
> - **Sécurité — `sanitize_avatar_url` (fonction PURE).** Cette URL provient d'une API EXTERNE et sera **téléchargée par le client** : elle est donc filtrée avant stockage (https imposé, hôte se terminant par `.steamstatic.com` ou `.akamaihd.net`, longueur bornée, pas d'`@` ni d'espace). Sans ce contrôle, une réponse altérée ferait émettre à tous les joueurs une requête vers un hôte arbitraire — traçage par IP au minimum. Rejet ⇒ `""` ⇒ gabarit par défaut, jamais d'erreur visible.
> - **Schéma.** `users.steam_avatar_url` (String, NOT NULL, `server_default=""`) — **auto-migrée**. `UserResponse.steam_avatar_url` (défaut `""` + coercition NULL→`""`, patron de `coins`).
> - **Client.** `AuthManager` : `avatar_url` + `avatar_texture` + signal `avatar_loaded` + `ensure_avatar()`, avec `HTTPRequest` DÉDIÉ en **TLS vérifié EN DUR** (`TLSOptions.client()`, pas `_tls_options()` — la cible est un CDN tiers, la tolérance dev local n'a pas à s'y appliquer). Cache **en mémoire** pour toute la session : `top_nav` étant reconstruit à chaque écran, un cache disque n'aurait économisé qu'un téléchargement par lancement pour le prix d'une invalidation à gérer. `clear_session()` purge l'avatar (poste partagé). `top_nav.gd` : cadre 44 px bordé cyan (charte §2, `corner_radius = 0`) placé AVANT le pseudo, **masqué tant qu'aucune texture n'existe** → la mise en page se referme, jamais de gabarit vide. Le Profil hérite de l'affichage sans une ligne de code : il monte déjà `TopNav`.
> - **Tests & validation.** `test_steam_auth.py` **117 ✅** (+18) : forme `{persona, avatar}`, avatar absent du payload, 11 cas de `sanitize_avatar_url` (http, domaine tiers, domaine SUFFIXÉ `steamstatic.com.evil.tld`, credentials dans l'URL, `javascript:`, URL démesurée), enregistrement à la création, rafraîchissement à la reconnexion, **avatar conservé quand l'API Steam est en panne**, aucun COMMIT quand l'avatar est inchangé. Suite backend **41/43** (mêmes 2 échecs pré-existants sur `HEAD`). Godot : `--import` **0 ERROR / 0 WARNING**, **capture 1920×1080** du menu avec avatar injecté — cadre correct, hauteur de la barre de navigation inchangée. **Aucun commit.**

---

### 8.115. Durcissement auth Steam — identifiants hors des logs + anti-fixation de session (Backend + Infra, 2026-07-24)

> Deux failles remontées par la revue de sécurité de l'authentification, corrigées avant ouverture aux joueurs. ⚠️ **Backend → push + redéploiement VPS** ET **redéploiement du conteneur `alloy`** (config de collecte de logs). Aucune action DB, aucune variable `.env`, **aucun changement client**.
>
> - **Faille n°1 — identifiants vivants dans les logs (défense en profondeur).** Le champ `RequestPath` de Traefik ET l'access-log applicatif incluent la QUERY STRING, où voyagent deux secrets : le **JWT du handshake WebSocket** (`/ws/…?token=<JWT>`, identifiant 24 h) et le **`session_id` de login Steam** (`/auth/steam/…?session_id=<S>`). Ils partaient EN CLAIR dans Loki (requêtable via Grafana). **Correctif** : caviardage au niveau Alloy (`stage.replace`, `token=`/`session_id=` → `REDACTED`) sur les DEUX pipelines — logs Docker (`loki.process "redaction_docker"`, nouveau) et access-log Traefik (`stage.replace` en tête de `loki.process "traefik"`). Protège la surface consultée (Loki). **Résidu ASSUMÉ** : les logs bruts sur le disque de l'hôte (json-file Docker + `/var/log/traefik/access.log` que lit CrowdSec) gardent la query — accès root only, et Traefik ne sait pas caviarder sa propre query string. Sortir le `?token=` du WS de la query (en-tête de handshake Godot) est un chantier plus lourd, différé.
> - **Faille n°2 — fixation de session → vol de compte.** Le flux navigateur+polling ne liait pas QUI ouvre la session à QUI la complète : un attaquant pouvait pré-créer une session (`POST /steam/session`), piéger une victime pour qu'elle la complète avec SON Steam, puis récupérer le JWT de la victime via `/poll`. **Correctif (§9.7)** : la session mémorise l'**IP qui l'a OUVERTE** (clé Redis parallèle `steam_login_ip:{session_id}`, même TTL). Le callback `/return` REFUSE de minter un JWT si l'IP de complétion diffère (le JWT de la victime n'est jamais émis), et `/poll` ne sert le token qu'à cette même IP. En usage normal, jeu et navigateur sont sur la même machine → même IP publique (le serveur est **IPv4-only** en entrée, pas de piège dual-stack). L'IP réelle vient de la **DERNIÈRE** entrée de `X-Forwarded-For` (celle que Traefik appose ; la gauche, envoyée par le client, est ignorée — sinon ce serait la faille de spoofing XFF classique). `client_ip()` retombe sur la connexion directe (127.0.0.1) en local, où les 3 requêtes coïncident.
> - **Effet croisé** : l'IP-binding rend aussi un `session_id` FUITÉ (faille n°1 résiduelle sur disque) inexploitable depuis une autre machine — le `/poll` d'une IP tierce reçoit 404 et DÉTRUIT la session.
> - **Non corrigé (points mineurs, cf. revue)** : JWT 24 h non révocable (un token moissonné reste valide 24 h) ; `/steam/session` non authentifié (surface de remplissage Redis, bornée par `RL_AUTH` + TTL) ; repli `Vagabond_<6 chiffres>` exposant une fraction du SteamID. À traiter séparément.
> - **Tests & validation.** `test_steam_auth.py` **128 ✅** (+11) : extraction IP (XFF droite, anti-spoof de la gauche, repli connexion directe), fixation bloquée (complétion IP ≠ ouverture → 400, Steam pas même contacté), flux légitime même-IP de bout en bout, `session_id` volé → 404 + session détruite. Regex de caviardage Alloy **vérifiée hors-ligne** (réplique Python RE2 sur des lignes `/ws?token=`, `/steam/…?session_id=` réalistes : secret retiré, JSON préservé, lignes sans secret intactes). Suite backend **41/43** (mêmes 2 échecs pré-existants sur `HEAD`). ⚠️ La syntaxe Alloy n'a PAS pu être bootée localement (Alloy absent du poste) — revue structurelle seule (accolades équilibrées, références de blocs valides) : **à confirmer par `docker logs alloy` au déploiement** (le conteneur refuse de démarrer sur une config invalide). **Aucun commit.**

---

### 8.116. Refonte MATCHMAKING — files d'attente serveur-autoritaire + salons privés à code + anti-bruteforce (Backend + Frontend, 2026-07-25)

> Remplacement INTÉGRAL de l'ancien système « liste de salles / scan / rejoindre par ID » (`lobby_screen`, `GET/POST /lobby/rooms`, join par ID numérique) par un **matchmaking 100 % serveur-autoritaire** : le joueur n'entre plus jamais un ID de salle et n'en voit jamais aucun — il rejoint une **file d'attente** (publique par carte+effectif, ou classée unique, FIFO strict) ou un **salon privé identifié par un code à 5 caractères**. S'y ajoute une **politique de sanctions anti-bruteforce** sur la recherche de codes privés. ⚠️ **Backend → push + redéploiement VPS COORDONNÉ avec le client** (le gate de version WS `client_version` protège la transition — aucun fallback caché). **Aucune action humaine VPS** (pas de nouvelle variable `.env` obligatoire, `sanctions`/`creator_id` auto-migrés au boot). **AUCUN COMMIT.**
>
> - **Files d'attente (§4.2-§4.3 du prompt).** `POST/GET/DELETE /api/v1/matchmaking/queue|status` — contrat complet en **§G** ci-dessus. Ticket Redis `mm:ticket:{user_id}`, machine d'état `idle → searching (0-30 s) → extending (30-60 s) → starting → ready {room_id} → in_game`. Buckets FIFO en ZSET (`mm:q:ranked` effectif 5 carte forcée `classic_42` ; `mm:q:casual:{map_id}:{n}` par bornes de carte). Le **matchmaker** (`api/sockets/matchmaker_runner.py`, NOUVEAU, patron `bot_runner.py`) tique toutes les `MM_TICK_S` (1 s) : forme un groupe dès que le bucket atteint l'effectif, ou dès que le ticket de TÊTE a `MM_QUEUE_BOT_FILL_S` (60 s) — complète alors avec des bots. Heartbeat : chaque poll `status` (cadence client 2 s) rafraîchit le TTL 15 s du ticket — un client mort disparaît de la file tout seul, aucun ticket fantôme possible. Échec de `launch_room` (ex. `initial_troops` insuffisant) : la room créée est détruite et les tickets repassent en `searching` avec leur ancienneté d'ORIGINE (le joueur ne perd pas sa place).
> - **Salons privés (§4.4/§4.7 du prompt).** `POST/DELETE /api/v1/private/rooms|join|rooms/leave|rooms/start` — contrat complet en **§H** ci-dessus. Code de **5 caractères**, alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (sans I/L/O/0/1 — zéro ambiguïté à la dictée), généré par **`secrets.choice`** (jamais `random`), unicité par `SET mm:code:{code} NX EX 86400`. Démarrage automatique dès l'effectif atteint ; le créateur dispose en plus de « LANCER AVEC BOTS ». Une déconnexion WS du créateur pendant `waiting` ferme le salon (même traitement que le `DELETE` créateur) — un salon ne survit jamais à son hôte. Pas de système « prêt ».
> - **Anti-bruteforce des codes — sanctions PAR COMPTE (table `sanctions`, pas par IP).** Une tentative sur un code inexistant OU pointant vers un salon plein/démarré compte comme une « erreur de recherche » (`banned`/`busy` ne comptent JAMAIS) ; **raison UNIFIÉE `unavailable`** — le client ne peut JAMAIS distinguer « code inexistant » de « salon plein » (zéro oracle d'énumération). Quota **5 erreurs / fenêtre fixe d'1 h** (`EXPIRE` posé au 1ᵉʳ `INCR` — fenêtre fixe assumée, plus simple qu'une fenêtre glissante) ; dès la **2ᵉ** erreur, avertissement avec `remaining_attempts` ; à la **6ᵉ**, sanction posée : **1 h** pour les 2 premiers bans, **24 h** à partir du 3ᵉ (`ban_duration_s`, fonction PURE). Le compteur est purgé sur join réussi et sur prononcé de ban. Ordre STRICT des contrôles au join privé : ban d'abord (un banni ne « consomme » pas de tentative), busy ensuite (double-clic gratuit), comptage seulement après.
> - **WebSocket — évolutions lobby uniquement (moteur in-game INCHANGÉ).** ❌ **Supprimés** : actions `ready`/`unready`/`get_lobby`, message `lobby_state`, toute la machinerie `_maybe_arm_bot_fill`/`_bot_fill_after`/`_cancel_bot_fill`/`_broadcast_lobby_state` (`ConnectionManager.all_ready`/`.ready` aussi supprimées, mortes). ➕ **Nouveaux** (salon privé uniquement) : action `get_salon` ; messages `salon_state{count,max_players,is_creator}` (envoyé INDIVIDUELLEMENT — jamais de liste de joueurs/pseudos/ids, décision produit n°2) et `salon_closed{reason}` (broadcast + fermeture des sockets code 1000). `GameState.is_private: bool = False` (défaut rétro-compat Redis, même technique que `is_ranked` §8.88) exposé en champ **PUBLIC** de `game_over` (piège n°9 — classé explicitement) : masque REJOUER côté client pour une partie issue d'un salon.
> - **Supprimé (backdoors).** `POST /api/v1/game/rooms/{room_id}/start` (chemin de démarrage alternatif) ; `GET/POST/DELETE /api/v1/lobby/rooms*` (+ fichier `api/v1/endpoints/lobby.py` supprimé et son montage retiré de `api/__init__.py`) ; le bug connu `ConnectionManager.all_ready(min_players=3, max_players=6)` en dur disparaît AVEC le code qui le portait. Le WS `init_game` (debug solo) : aucune branche dédiée dans `router.py` (vérifié par grep) — le helper client `send_init_game()` est supprimé côté `network_manager.gd`.
> - **Nouveaux fichiers backend.** `api/game/matchmaking.py` (module PUR : `generate_code`/`normalize_code`, `bucket_key`/`validate_queue_request`/`plan_bucket`, `ticket_state`, `ban_duration_s`/`should_warn`/`remaining_attempts` — zéro I/O, patron `ranked.py`) ; `api/v1/endpoints/matchmaking.py` (2 `APIRouter` : `/matchmaking` + `/private`) ; `api/sockets/matchmaker_runner.py` (orchestrateur, démarré dans `main.py` après `create_tables()`, purge Redis `mm:q:*`/`mm:ticket:*`/`mm:code:*` au boot — les compteurs `mm:fail:*` SURVIVENT, un reboot ne blanchit pas un bruteforceur) ; `migration_sanctions.sql` (archive — table créée automatiquement par `create_all`). `models.py` += `Sanction` (table `sanctions`) et `GameRoom.creator_id` (nullable). `state_manager.save_game_state` durci avec TTL `GAME_STATE_TTL_S` (24 h, rafraîchi à chaque sauvegarde — une partie abandonnée par crash n'est plus immortelle dans Redis).
> - **Constantes NOUVELLES (`core/config.py`, surchargeables `.env`) :** `MM_TICK_S`(1.0), `MM_SEARCH_EXTEND_S`(30), `MM_QUEUE_BOT_FILL_S`(60), `MM_HEARTBEAT_TTL_S`(15), `MM_STATUS_POLL_S`(2.0, documentaire — vit côté client), `MM_FAIL_LIMIT`(5), `MM_FAIL_WINDOW_S`(3600), `MM_BAN_SHORT_S`(3600), `MM_BAN_LONG_S`(86400), `MM_BANS_BEFORE_LONG`(2), `PRIVATE_CODE_LEN`(5), `GAME_STATE_TTL_S`(86400). ⚠️ **`BOT_FILL_ENABLED`/`BOT_FILL_TIMEOUT_S` deviennent OBSOLÈTES** (le remplissage IA se décide désormais AVANT le démarrage, par le matchmaker ou `/private/rooms/start`) — **laissés dans `config.py`** (commentaire « obsolète depuis §8.116 ») après vérification par grep qu'aucun code vivant ne les référence plus hors tests adaptés.
> - **Frontend.** Nouveaux écrans `search_screen`/`salon_screen` (détail complet : **§8.116 de `FRONTEND_INTERFACES.md`**), suppression de `lobby_screen`/`waiting_room`. Nouveau flux : `main_menu → search_screen → [salon_screen] → faction_selection → game`. `network_manager.gd` : suppression de `fetch_rooms`/`create_room`/`join_room`/`send_init_game` et des signaux `rooms_loaded`/`rooms_fetch_failed` ; ajout de `mm_queue_join`/`mm_queue_status`/`mm_queue_leave`/`private_create`/`private_join`/`private_leave`/`private_start_bots`/`leave_room` (tous authentifiés, `HTTPRequest` DÉDIÉ au polling) ; `leave_room()` corrige le bug historique du QUITTER (peer `STATE_CLOSING`, calqué sur `_requeue_enter`) ; `requeue()` réécrit — plus de scan/join/create, capture la modalité puis `leave_room()` + `mm_queue_join(...)` (ou `requeue_unavailable` si la partie était privée — REJOUER masqué, retour QG).
> - **⚠️ Effets assumés.** Déploiement **COORDONNÉ** backend+client (le gate de version WS protège la transition, sans lui un client legacy parlerait à un serveur qui n'a plus `/lobby/rooms`). `BOT_FILL_ENABLED`/`BOT_FILL_TIMEOUT_S` obsolètes mais **laissés** dans `config.py`. Le matchmaker hérite de la **contrainte 1 worker** de `ConnectionManager`/`RoomTimers` (globaux de process — documenté, pas résolu). Fenêtre du compteur d'échecs **FIXE** (pas glissante) — plus simple, assumé. Le matchmaker est un **singleton de process** (flag module `_mm_task`, idempotent au restart). Aucune UNIQUE `(user_id, game_room_id)` ajoutée sur `game_room_players` (hors périmètre, `create_all` ne modifie pas une table existante).
> - **Piste différée : rate-limit edge dédié `rl-mm` si le poll 2 s pèse — non implémenté** (les nouveaux endpoints vivent sous `/api/v1`, déjà couverts par `crowdsec`/`rl-api`/`inflight`/`sec-headers`).
> - **Validation.** `python -m py_compile` OK sur **chaque** `.py` touché. Suite backend complète **44/46** (`test_missions.py` + `test_simulation.py` en échec **PRÉ-EXISTANT sur HEAD**, hors périmètre, non lié à ce chantier). **NOUVEAUX** : `test_matchmaking_queue.py` **25 ✅ / 0 ❌**, `test_private_codes.py` **24 ✅ / 0 ❌**, `test_search_sanctions.py` **23 ✅ / 0 ❌**. **Adaptés** : `test_lobby_idempotent.py` **5 ✅**, `test_requeue_lobby.py` **7 ✅**, `test_bot_flow.py` **55 ✅**, `test_security_locks.py` **38 ✅**. Godot : `--headless --import` **0 ERROR** ; boot `main_menu`/`search_screen`/`salon_screen` **0 ERROR** chacun. ⚠️ **La mise en page VISUELLE des 2 nouveaux écrans n'est PAS prouvée par le headless** (0 ERROR ne certifie que la compilation/le boot, jamais la disposition réelle) — à vérifier par une capture humaine (cf. `FRONTEND_INTERFACES.md` §8.116). **AUCUN COMMIT.** ⚠️ **Backend → push + redéploiement VPS requis (§1)**, coordonné avec la mise à jour du client.
> - **Revue adversariale finale (multi-agent) — 4 défauts trouvés, TOUS corrigés puis revalidés.** (1) **CRITIQUE** : rien ne passait `GameRoom.status → "finished"` à la victoire → tant qu'un joueur lisait encore son rapport (sockets ouverts, salle non détruite), les memberships `in_progress` des AUTRES bloquaient leur re-file (`in_room` → « REPRENDRE » sur une partie terminée). Correctif : **`_mark_room_finished(room_id)`** (patron `_mark_room_in_progress`) appelé dans `_finalize_if_over` dès la victoire — les contrôles matchmaking ne matchent que `waiting`/`in_progress`. (2) **ÉLEVÉ** : 3 Vues fermaient encore `NetworkManager.socket` à la main (abandon `main.gd`, sortie spectateur, déconnexion `settings.gd`) → le peer restait en `STATE_CLOSING` et la recherche suivante échouait en silence. Correctif : `leave_room()` partout + ceinture-bretelles dans `connect_to_server` (peer **NEUF** systématique si ni OPEN ni CONNECTING). (3) **MOYEN** : cul-de-sac `search_screen` si la connexion WS échouait à l'état `ready` (poll stoppé, ni ANNULER ni RETOUR) → RETOUR ré-affiché + relance du poll sur `lobby_error` (récupération via `/status`). (4) **FAIBLE** : course `DELETE /queue` ↔ formation (un `ANNULER` intercalé entre les `await` du matchmaker recevait `left:true` alors que la salle se créait avec lui) → le matchmaker flippe les tickets en `starting` **AVANT** son ZREM (`SET … XX` : un ticket disparu n'est JAMAIS ressuscité, le joueur est remplacé par un bot) et `queue_leave` re-lit le ticket APRÈS son ZREM (`assigned` si sélectionné entre-temps). Revalidation post-correctifs : `py_compile` OK, suite **44/46** (le 3ᵉ échec apparu, `test_deploy_contamination.py`, est un **flake RNG confirmé** — 4 re-runs consécutifs verts 37 ✅/0 ❌), `--import` + boot `main_menu`/`search_screen`/`salon_screen`/`settings` **0 ERROR**. La revue a aussi tenté de réfuter — sans succès — : backdoor `init_game` morte, `is_private` correctement PUBLIC, discipline de verrou saine (aucun deadlock réentrant possible), ordre des contrôles de sanctions conforme, `unavailable` réellement indiscernable, cycle de vie Redis sans fuite, bots jamais persistés.

### 8.117. REFONTE UI DE L'ARÈNE — volet RÉSEAU : `reinforcements_granted`, `equipped_finisher`, catégorie `finisher`, rythme des bots (Backend ADDITIF, 2026-07-27)

> **Périmètre.** Volet backend de `PROMPT_REFONTE_UI_ARENE.md` (détail frontend : **§8.117 de `FRONTEND_INTERFACES.md`**). **Strictement ADDITIF** (règle §1.5) : aucune clé de payload existante n'est renommée ni supprimée, aucune règle de jeu n'est modifiée. Un client antérieur ignore les nouveautés ; un client à jour face à un serveur non redéployé retombe silencieusement sur l'ancien comportement (§9.2). **AUCUN COMMIT — redéploiement VPS requis pour que ces 3 points prennent effet.**
>
> **1) Nouvel évènement système `reinforcements_granted` (mécanique `_push_system_event` / `_drain_system_events`).** Poussé par `engine._calculate_reinforcements` à CHAQUE phase de renforts, drainé dans `event["system_events"]` par les sites existants (`_start_playing`, `_end_turn`) :
> ```json
> {"code": "reinforcements_granted", "player_id": 11, "base": 4, "continent_bonus": 2, "faction_bonus": 1, "total": 7}
> ```
> - `base` = `territoires // 3` · `continent_bonus` = somme des bonus BRUTS des continents entièrement contrôlés · `faction_bonus` = **part attribuable au POUVOIR** = « Barons de la Ferraille » (`bonus_reinforcement_flat`) **+** « Gardiens d'Éden » (`continent_bonus_plus` × nombre de continents contrôlés) · `total` = somme des trois, **rigoureusement identique** à l'ancien calcul (seule la VENTILATION est nouvelle : la part Éden était auparavant fondue dans `continent_bonus`).
> - **POURQUOI** : le client ne recevait qu'un total (`units_in_stock`) — les bonus de faction étaient **invisibles par construction**, le joueur ne pouvait pas percevoir son propre pouvoir. Rendu client : ligne de Journal « RENFORTS : 7 (base 4 + continents 2 + pouvoir **1**) », part pouvoir en OR si > 0.
> - **Faction sans bonus → `faction_bonus: 0`** (jamais de clé absente). Tests : `test_factions.py` §8 (12 asserts, dont l'égalité stricte des totaux avant/après).
>
> **2) `PlayerState.equipped_finisher: str = ""` — champ PUBLIC.** Miroir exact d'`equipped_skin` (M5 §8.69) : posé au draft WS par `router._load_equipped_finisher(pid)` et à la création REST par `engine.create_initial_state` (`pdata["equipped_finisher"]`). **PUBLIC par design** (la State Redaction ne masque que les objectifs §8.6) : la cinématique de mise à mort est vue par TOUS, chacun doit donc connaître le finisher du **TUEUR**. `""` = finisher **BASIQUE GRATUIT** — défaut de tout le monde, valeur de repli d'un état Redis antérieur et d'un bot (toujours `""`, pid < 0).
>
> **3) Catalogue : nouvelle catégorie `finisher`** (`shop_catalog.SHOP_CATALOG`) — 3 articles en **Coins** (`currency_type: "virtual"`), **sans `hero_key`** (un finisher appartient au JOUEUR, pas à un personnage) : `finisher_barrage_acier` 2000, `finisher_nuage_cendres` 2200, `finisher_frappe_orbitale` 2500. Le basique gratuit **n'est PAS au catalogue**. Achat : chemin `POST /shop/purchase/virtual` inchangé (garde « article déjà acquis » étendue à la catégorie). Équipement : `POST /shop/equip` accepte désormais `category ∈ {skin, finisher}`.
> - ⚠️ **AUCUNE nouvelle table, AUCUNE migration.** Le finisher occupe le **slot réservé `shop.FINISHER_SLOT = "__finisher__"`** de la table `equipped_skins` (colonne `faction_id`). Aucun id de faction ne porte ce nom (ids snake_case sans `__`) → collision impossible, contrôlée par un assert de `test_equip.py`. Conséquence VISIBLE côté client : le bloc `equipped` de `GET /shop/inventory` porte une entrée supplémentaire `"__finisher__": "<finisher_id>"` — c'est là que la boutique lit le finisher équipé. Déséquiper ce slot (`{"faction_id": "__finisher__", "skin_id": null}`) = **retour au basique gratuit**, toujours autorisé (rien à posséder).
>
> **4) Rythme des bots configurable — `settings.BOT_ACTION_DELAY_SECONDS` (défaut 2,0 s, surchargeable `.env`).** Remplace la constante figée `bot_runner.BOT_ACTION_DELAY = 1.0`, qui enchaînait les actions plus vite que le client ne peut les raconter. Lu **à chaque attente** par `bot_runner.bot_action_delay()`, via un **import PARESSEUX** de `core.config` protégé par `try/except` : un import de module déclencherait `Settings()` (donc pydantic-settings ET la validation fail-closed du secret JWT) au simple chargement de `bot_runner` — ce qui cassait `test_game_over_redaction.py`, qui ne stubbe pas `core.config`. Repli : la constante de module (`2.0`), jamais l'ancien `1.0`. Aucune règle de jeu touchée (les timers serveur, les dés et l'IA sont inchangés).
>
> **Fichiers.** MODIFIÉS : `api/game/engine.py` (`_calculate_reinforcements`, `create_initial_state`), `api/game/state_schemas.py`, `api/game/shop_catalog.py`, `api/game/factions.py` (**correction de doc** : la note d'état disait que `attack_reroll_all_low_dice` et `first_strike_bonus_die` restaient à câbler — ils l'étaient DÉJÀ, seul l'affichage client manquait), `api/sockets/router.py`, `api/sockets/bot_runner.py`, `api/v1/endpoints/shop.py`, `core/config.py`. TESTS ÉTENDUS : `test_factions.py`, `test_equip.py`, `test_shop_v2.py`, `test_bot_flow.py`.
>
> **Validation.** Suite backend complète verte — **sauf `test_missions.py` et `test_simulation.py`, en échec PRÉ-EXISTANT sur HEAD** (dépendances absentes du poste), hors périmètre.

### 8.119. CAPACITÉS DE HÉROS — les PP deviennent une MONNAIE (`hero_ability`, RATIONNER + 3 pouvoirs pilotes) (Backend ADDITIF, 2026-07-30)

> **Périmètre.** Volet réseau/moteur de `PROMPT_PP_DOUBLE_EMPLOI.md` (détail frontend : **§8.119 de `FRONTEND_INTERFACES.md`** ; valeurs d'équilibrage : **§4 de `ARCHITECTURE_ET_REGLES.md`**). **Strictement ADDITIF** (règle §1.5) : aucune clé existante renommée ou supprimée, **aucune règle de combat modifiée** — la formule du duel `(PA + PP) × (1 − PB)` est **INTOUCHÉE**, les capacités ne modifient que ses ENTRÉES. **AUCUN COMMIT — redéploiement VPS requis.** Client et serveur doivent partir **ENSEMBLE** (gate de version WS §9) : le client à jour affiche des boutons que seul le serveur redéployé accepte.
>
> **Le problème résolu.** Les PP (`hero_pp_current`) étaient **purement passifs** : ils fluctuaient au rythme des dés et entraient dans les dégâts du duel, mais le joueur ne pouvait **rien en faire** et ne comprenait ni ce qu'ils font ni pourquoi ils bougent. Ils deviennent une **monnaie tactique** dépensable.
>
> **1) Nouvelle action WS `hero_ability`** (enveloppe standard, donc idempotence `action_id` incluse — voir plus bas) :
> ```json
> { "action": "hero_ability", "payload": {
>     "ability": "ration" | "faction_power",
>     "action_id": "<uuid client>",
>     "target_territory_id": "alaska"
> } }
> ```
> ⚠️ **`target_territory_id` est une CHAÎNE** (clé Risk de `map_data.py`, ex. `"alaska"`), **pas un entier** — comme partout ailleurs dans ce contrat depuis §8.15. Requis pour BASTION et ABSOLUTION ; **absent** pour `ration` et pour FRAPPE FANTÔME (une valeur fournie inutilement est ignorée, tolérance §1.5).
>
> **2) Évènement de succès** — dans le flux `action_result` standard, **PUBLIC** (aucune information secrète). Le discriminant est **`event_type`** (convention de TOUS les évènements moteur), et non `type` :
> ```json
> { "event_type": "hero_ability", "room_id": 42, "player_id": 2, "ability": "ration",
>   "detail": { "pp_spent": 5, "pv_healed": 30 },
>   "system_events": [ { "code": "ability_used", "player_id": 2, "ability": "ration",
>                        "power_id": "", "territory_id": "", "pp_spent": 5, "pv_healed": 30 } ] }
> ```
> `detail` pour un pouvoir de faction : `{ "power_id": "bastion_acier", "pp_spent": 6, "target_territory_id": "alaska", "shield_turns": 3 }` · `{ "power_id": "frappe_fantome", "pp_spent": 8, "airborne_attacks_left": 1 }` · `{ "power_id": "absolution", "pp_spent": 5, "target_territory_id": "ukraine" }`.
> Le `system_event` **`ability_used`** est **UNIQUE et PARAMÉTRÉ** (un seul code, jamais un code par pouvoir) : le client choisit sa phrase depuis `power_id`/`ability`, donc ajouter les 7 pouvoirs restants n'ajoutera **aucun** code réseau.
>
> **3) Refus — convention zéro-4xx §8.112.** Réponse d'erreur applicative du pipeline existant (`{"type":"error"}`), **jamais un 4xx**, désormais porteuse de la clé **ADDITIVE `reason`** = code machine que le client **TRADUIT** (`ABILITY_ERR_*`) au lieu d'afficher la phrase serveur non localisée. Jeu **FERMÉ** de 8 raisons : `not_your_turn` (hors tour, éliminé, héros mort) · `wrong_phase` (phase interdite, partie non démarrée ou déjà gagnée) · `already_used` · `ranked_disabled` · `insufficient_pp` · `invalid_target` · `no_power` (faction hors trio pilote **ou** `ability` inconnue) · `blocked_state` (`pending_conquer` / `pending_eclipse_choice`). Implémenté par `hero_abilities.AbilityRefused(ValueError)` → le `except ValueError` du routeur l'attrape déjà, et n'ajoute `reason` **que** s'il y en a une (tous les autres refus du jeu restent inchangés ; un client antérieur ne lit que `message`).
>
> **4) État (ADDITIF, rétro-compat Redis).** `PlayerState.ability_ration_used: bool = False` et `PlayerState.ability_power_used: bool = False` — **DEUX drapeaux distincts** car les deux capacités sont **CUMULABLES dans le même tour** (rationner PUIS lancer son pouvoir est un jeu voulu). Remis à `False` dans le bloc de reset du joueur SORTANT de `_end_turn`, **au même endroit** que `airborne_attacks_left` et les autres modificateurs temporaires. Champs **PUBLICS** diffusés tels quels (aucune redaction : le client en a besoin pour griser ses boutons, et « cet adversaire a déjà rationné » n'est pas un secret). `GameStatistics.abilities_used: Dict[int,int]` — compteur ADDITIF par joueur (télémétrie d'équilibrage de la phase pilote, futures missions). Une partie EN COURS pendant le redéploiement se redésérialise sans ces champs.
>
> **5) Règles (source de vérité = registre PUR `api/game/hero_abilities.py`, JAMAIS le moteur).**
> - **RATIONNER — les 10 héros.** Coût `min(5, pp_current − pp_min)` PP → **6 PV par PP**, total **plafonné aux PV manquants**. Un seul clic (pas de sélecteur de quantité). Phases **2-4**, **1 fois par tour**. **DISPONIBLE EN CLASSÉE** : étant universel aux 10 héros, il ne crée aucune asymétrie — c'est le sens de la décision « casual uniquement », qui vise les POUVOIRS pilotes (cf. `casual_only` au registre : `False` pour RATIONNER, `True` pour les 3 pouvoirs ; basculer l'un ou l'autre est une décision d'une ligne). Refus `invalid_target` si le héros est **à PV pleins** (on ne laisse pas brûler des PP pour zéro gain — sa seule « cible » est son propre héros).
> - **BASTION D'ACIER** (`phalanges_acier`, Général Viktor Stahl) — **6 PP**, phases 2-4, cible = **un de SES territoires non déjà protégé** → `shield_turns_left = hero_abilities.shield_turns_for(state)` = **nombre de joueurs encore en lice** (éliminés et abandons exclus, plancher défensif 1). ⚠️ Ce n'est pas une valeur arbitraire : le décrément de `_end_turn` est **GLOBAL** (il tombe à chaque tour de N'IMPORTE QUEL joueur) → il faut N tours pour offrir **un round complet** de protection.
> - **FRAPPE FANTÔME** (`chasseurs_ombres`, Capitaine Sable Renko) — **8 PP**, **phase 3 UNIQUEMENT**, sans cible → `airborne_attacks_left += 1` : la prochaine attaque du tour peut viser un territoire **non adjacent** (chemin moteur existant, consommé par `_handle_attack`, remis à 0 en fin de tour).
> - **ABSOLUTION** (`culte_isotope`, Capitaine Ezra Voss) — **5 PP**, phases 2-4, cible = **n'importe quel territoire de la zone COURANTE** (y compris ennemi ou neutre : le Culte assainit la carte, la purge ne dépend pas de la possession) → retiré de `contamination_zone.territories`. Le **télégraphe** `next_territories` est **PRÉSERVÉ** (la zone continue d'évoluer, promesse G1 §8.62 tenue) et n'est **jamais** purgeable. Un état LEGACY « position unique » est migré au passage (clé `position` retirée), sans quoi le territoire purgé serait relu comme encore contaminé.
> - **Paiement** : toujours `pp_current − coût ≥ pp_min` — le plancher n'est **jamais** franchi. **Activation pendant SON tour uniquement** : aucune réaction hors tour, aucun système d'interruption, 1 clic + 1 cible au maximum. **Les bots n'utilisent pas les capacités** (`bot_ai.py` INTOUCHÉ).
>
> **6) Architecture.** `api/game/hero_abilities.py` est un module **PUR** (patron `matchmaking.py` / `bot_ai.py` / `ranked.py`) : zéro I/O, et **l'engine importe hero_abilities, jamais l'inverse**. `can_use(state, pid, ability, target)` **DÉCIDE** (toutes les validations, dans un ORDRE FIGÉ par les tests — il détermine quelle raison le joueur voit quand plusieurs refus s'appliquent) ; `engine._handle_hero_ability` **APPLIQUE**, en routant sur des codes d'**EFFET** (`EFFECT_SHIELD` / `EFFECT_AIRBORNE` / `EFFECT_PURGE_ZONE`) et **jamais** sur un id de faction en dur (§6.5). Ajouter un 4ᵉ pouvoir = une entrée de registre, plus éventuellement un code d'effet. `engine._zone_territory_ids` **DÉLÈGUE** désormais à `hero_abilities.zone_territory_ids` (source UNIQUE : ABSOLUTION valide sa cible sur exactement la zone qui infligera les dégâts).
>
> **7) Idempotence & routeur.** L'action passe par le pipeline **GÉNÉRIQUE** `process_action` → elle hérite gratuitement de la fenêtre `recent_action_ids` (correctif « double déduction de PV »), des gardes de tour / d'état bloquant, de `_check_victory` et de la rediffusion **State Redaction**. Un rejeu du même `action_id` est rejeté **AVANT** toute mutation → **aucune double dépense de PP**. `router.py` n'a donc reçu qu'**une seule** modification : l'ajout de la clé `reason` sur l'erreur applicative.
>
> **Fichiers.** NOUVEAUX : `api/game/hero_abilities.py`, `test_hero_abilities.py` (91 asserts — registre, `ration_plan`, chaque raison de refus, `describe`, `zone_territory_ids`, `shield_turns_for`), `test_hero_abilities_flow.py` (73 asserts — bouclier qui fait refuser l'attaque puis expire après un round complet, frappe non adjacente à usage unique, purge de zone + télégraphe intact + état legacy, plafond de soin, rechargement des drapeaux, gate classée, `no_power`, idempotence sans double dépense, contre-épreuve « formule du duel intouchée »). MODIFIÉS : `api/game/engine.py`, `api/game/state_schemas.py`, `api/sockets/router.py`.
>
> **Validation.** `test_hero_abilities.py` **91 ✅ / 0 ❌** · `test_hero_abilities_flow.py` **73 ✅ / 0 ❌** · suite backend complète verte — **sauf `test_missions.py` (37 OK / 4 KO) et `test_simulation.py` (`fastapi` absent du poste)**, en échec **PRÉ-EXISTANT sur HEAD** (vérifié en rejouant `test_missions.py` contre les sources extraites de `HEAD` : échec identique), hors périmètre. **Contre-épreuve de mutation** : 5 régressions injectées à chaud (bouclier ramené à 1 tour, taux de conversion faussé, fenêtre d'idempotence désarmée, drapeau 1-usage/tour jamais posé, garde classée sautée) → **5/5 détectées** par les tests, sources restaurées dans le même bloc.
>
> **HORS PÉRIMÈTRE (chantier suivant, après RETEX du trio).** Les 7 autres pouvoirs de faction · usage des capacités par les bots · réactions hors tour · missions/succès adossés à `abilities_used` · entrée des pouvoirs en Classée (quand les 10 factions auront le leur : passer `casual_only` à `False` au registre suffira).


---

## §8.120 — TENSION & FIN DE PARTIE : zone croissante, timer global, victoire au score, objectifs élargis, XP de placement, paris d'observateur (volet RÉSEAU/MOTEUR)

> **Périmètre.** Volet backend de `PROMPT_TENSION_FIN_DE_PARTIE.md` (détail frontend : **§8.120 de
> `FRONTEND_INTERFACES.md`** ; valeurs d'équilibrage et règles : **§4 de `ARCHITECTURE_ET_REGLES.md`**).
> **Strictement ADDITIF** (règle §1.5) : aucune clé de payload existante n'est renommée ou supprimée.
> `victory_reason` gagne une VALEUR (`"timeout"`) — additif, le client a des replis (§9.2). **AUCUN
> COMMIT — redéploiement VPS requis.** Client et serveur partent **ENSEMBLE** (gate de version WS §9).

### 1. Champs ADDITIFS de l'état (`GameState` / `PlayerState` / `GameStatistics`)

| Champ | Type | Défaut | Rôle |
|---|---|---|---|
| `GameState.match_deadline_epoch` | `float` | `0.0` | Échéance ABSOLUE de la partie en **epoch MUR** (`time.time()`), posée à la **création de l'état** = `now + settings.MATCH_TIME_LIMIT_S`. Le client en dérive son compte à rebours global via l'offset d'horloge existant (pattern `timer_update` §8.31) — **aucun message périodique**. `0.0` = aucune limite (état antérieur, ou `MATCH_TIME_LIMIT_S=0`). |
| `GameState.final_protocol_active` | `bool` | `False` | PROTOCOLE FINAL armé (T−`FINAL_PROTOCOL_LEAD_S`) : bandeau client, plafond de croissance de zone **DOUBLÉ**, paris d'observateur **FERMÉS**. |
| `GameState.zone_growth_this_round` | `int` | `0` | Territoires ajoutés par CROISSANCE depuis le début du round global. Remis à 0 par `_relocate_contamination` (seul point de reset). |
| `PlayerState.observer_bets` | `dict` | `{}` | Paris du joueur : `{ "<bet_type>": {"value": ..., "at_hero_deaths": int} }`. **REDACTÉ** — chaque destinataire ne voit QUE les siens (cf. §4). |
| `GameStatistics.hero_down_order` | `List[int]` | `[]` | Ids des joueurs dont le héros est tombé, **dans l'ordre chronologique**. Rend résoluble le pari « prochain héros abattu ». Donnée PUBLIQUE. |

### 2. Évènements système (pipeline `system_events` existant, PUBLICS)

- `{"code": "zone_grew", "territory_id": "<tid>"}` — la zone s'est étendue d'un territoire CONTIGU
  (croissance intra-round). Émis **après** les dégâts, à l'entame de chaque tour de joueur. Une
  ligne LEGACY `system_messages` accompagne l'évènement (anglais invariant, anciens clients).
- `{"code": "final_protocol_started"}` — le PROTOCOLE FINAL vient d'être armé. Diffusé dans un
  `action_result` d'`event_type` `final_protocol_started`, avec l'état à jour.
- La fin au temps est diffusée comme un `action_result` d'`event_type` **`match_timeout`**
  (`{"winner_id": ...}`), suivi du `game_over` standard. L'état diffusé porte déjà
  `winner_id` + `victory_reason` : un client qui ignore l'évènement bascule quand même (§9.2).

### 3. Action WS `observer_bet` (réservée aux joueurs ÉLIMINÉS)

```json
{"action": "observer_bet", "payload": {"action_id": "...", "bet_type": "winner", "value": 42}}
```

- `bet_type` ∈ `winner` · `next_hero_down` · `end_reason`.
- `value` = `player_id` (les deux premiers) **ou** `"objective"|"elimination"|"timeout"` (`end_reason`).
  « abandon » n'est **pas** pariable (ce n'est pas une victoire lisible sur le plateau).
- **Pas de pari sur la ZONE** : son télégraphe est PUBLIC un round à l'avance, le pari serait gratuit.
- Traitée **hors** `process_action` (le parieur n'est ni le joueur courant ni vivant) et **sans**
  `_post_action_timer` : parier n'est pas une action de tour et ne touche pas le compteur AFK.
- Réponse **PRIVÉE** au parieur : `{"type": "observer_bet_ack", "bet_type", "value", "reward": {"xp","coins"}}`.
- Refus (convention zéro-4xx §8.112) : `{"type": "error", "message": ..., "reason": <code>}` avec
  `reason` ∈ `not_eliminated` · `too_late` · `already_bet` · `invalid_value`. **Ordre des contrôles
  figé** : éligibilité → fenêtre → unicité → valeur (dire « valeur invalide » à un joueur VIVANT
  serait trompeur : sa vraie erreur est qu'il n'a rien à parier).
- Le contrat tolère aussi la forme « à plat » `{"type": "observer_bet", ...}` (comme le chat) : le
  routeur accepte `type` en alias d'`action` quand `action` est absent.

### 4. State Redaction — extension aux paris

`connection_manager._redact_state_for_player` masque désormais, **en plus** des objectifs secrets,
`players[*].observer_bets` de **tous les autres** joueurs (écrasé par `{}`, la clé restant présente
pour que le contrat soit stable). Un pari public serait un signal tactique gratuit (« l'éliminé a
parié sur X » désignerait le favori à toute la table). Révélation au `game_over`, en bloc **PRIVÉ**.

### 5. `game_over` — deux blocs ADDITIFS

- **`final_scores` (PUBLIC)** : tableau de DÉPARTAGE **déjà trié** par le barème serveur, une entrée
  par joueur : `{player_id, username, objective_pct, hero_pv_pct, kills, contender}`. Envoyé dans
  **TOUS** les modes de fin (il alimente l'onglet BILAN du Rapport Post-Op — « où en étaient les
  autres ? » a du sens même après une victoire par objectif). Pourcentages **ENTIERS** 0..100
  (piège JSON float §5) et **plancherisés AVANT comparaison** : le classement affiché est
  exactement celui que le serveur a appliqué.
- **`bet_results` (PRIVÉ, par destinataire — piège n° 9)** : `{results: [{bet_type, value, won, xp,
  coins}], totals: {xp, coins, won, total}}`. **Absent** pour qui n'a pas parié.
- `victory_reason` accepte la valeur ADDITIVE **`"timeout"`**. `derive_match_type` la range sous
  `elimination` (le `match_type` n'a que 2 valeurs, et une victoire au temps n'est **pas** une
  victoire par objectif).

### 6. Barème de DÉPARTAGE (module PUR `api/game/final_scoring.py`)

Ordre **STRICT** — on ne compare le critère suivant qu'à égalité parfaite sur le précédent :
1. **% d'accomplissement d'objectif** (= le MAX des deux volets du double objectif) ;
2. **% de PV restants du héros** (héros non initialisé → 0 %, jamais 100 %) ;
3. **unités ennemies tuées AU COMBAT** (jamais les kills de zone : la zone tue sans mérite).

Égalité parfaite sur les trois → **ordre du tour** (`turn_order`, le premier à avoir joué gagne).
Ce n'est pas « juste », c'est **déterministe et documenté** — tirer au sort une victoire serait pire.
Les **contenders** sont les mêmes que dans `_check_victory` (vivants **ET** non retirés — Fallen
Empire : un joueur qui a abandonné ne gagne pas au temps).

### 7. Ledger — 8ᵉ raison canonique

`economy.REASON_OBSERVER_BET = "observer_bet"` (**crédits uniquement** : parier ne coûte rien).
Ajoutée à `ALL_REASONS` entre `mission_claim` et `season_reward`. Plafond structurel : **20 coins**
par partie. Les coins de PALIER de niveau éventuellement franchi par la prime d'XP restent, eux,
journalisés sous `match_level_coins` — jamais sous `observer_bet`.

### 8. Configuration (`core/config.py`, surchargeable `.env`)

| Variable | Défaut | Effet |
|---|---|---|
| `MATCH_TIME_LIMIT_S` | `900` | Durée max d'une partie. **`0` DÉSACTIVE** la limite (aucune fin au temps, aucun PROTOCOLE FINAL). ⚠️ Le rebours démarre à la **création de l'état** — draft (≤ 60 s) + placement (≤ 90 s) compris : c'est une borne de **durée de session**, pas de temps de jeu net. |
| `FINAL_PROTOCOL_LEAD_S` | `120` | Avance du PROTOCOLE FINAL sur l'échéance. |

### 9. Où vit le rebours global (et pourquoi pas dans une task dédiée)

Les jalons vivent dans la **boucle de minuterie de salle EXISTANTE** (`router._turn_timeout`) :
elle dort jusqu'au **plus tôt** de l'échéance de phase et du prochain jalon global, et appelle
`_check_match_deadline` à **chaque** réveil, **avant** le test d'obsolescence de signature (le
rebours global est indépendant du tour courant : il ne doit pas mourir avec la minuterie d'un tour
périmé). Un cache in-memory par salle (`_match_deadlines`, même nature que `timers.*`) sert
uniquement à calculer le prochain réveil **hors verrou** ; l'**autorité reste l'état Redis**.
Sans ce réveil anticipé, la granularité du « T−2 min » serait celle du timer de phase — jusqu'à
**180 s** d'erreur en phase d'Attaque, soit un bandeau qui arrive à T−0.

**Cas limites couverts** : expiration pendant `pending_conquer`/`pending_eclipse_choice` (état résolu
tel quel, rien n'est annulé) · pendant un tour de bot (le verrou de salle sérialise déjà) · pendant
une animation client (le serveur n'attend jamais le client) · état sans joueur (aucune clôture, et
**aucune boucle CPU** : le calcul de réveil renvoie `None` et jamais `0.0` quand l'échéance est passée).


### 10. CORRECTIF « REJOUER coince sur l'écran de création de partie » (bug §8.116/§8.70)

> Signalé pendant la recette de §8.120. **Deux défauts INDÉPENDANTS**, tous deux ANTÉRIEURS à ce
> chantier (code §8.116 / §8.70), sur le chemin `REJOUER` — rapport post-op ET overlay observateur.

**(a) Course de requête, côté CLIENT.** `NetworkManager.requeue()` appelait `mm_queue_join()` juste
avant `TransitionManager.change_scene("search_screen.tscn")`. La réponse HTTP arrivait donc alors que
`search_screen` n'était PAS ENCORE dans l'arbre, et sa garde `if not is_inside_tree(): return`
**jetait** le signal `mm_queue_result` : personne ne basculait sur le panneau RECHERCHE. Pire, le
`mm_queue_status()` que l'écran émet à son `_ready` pouvait répondre `idle` (ticket pas encore écrit)
→ `_on_mm_status_updated` faisait `_poll_timer.stop()` + `_show_config(false)` : **plus aucun poll ne
repartait**, l'écran restait figé sur CONFIGURATION alors qu'un ticket existait côté serveur.
→ **Correctif** : `requeue()` ne met plus en file ; il mémorise la modalité
(`NetworkManager.consume_pending_requeue()`) et c'est **`search_screen._ready()` qui émet le
`mm_queue_join`**. Émetteur et écouteur sont le même nœud, déjà dans l'arbre : la course disparaît
par construction au lieu d'être rattrapée après coup. Le panneau RECHERCHE s'affiche
OPTIMISTE (le joueur a cliqué, il doit voir qu'il se passe quelque chose), ANNULER reste masqué
jusqu'à la confirmation serveur, et tout refus (`banned`/`in_room`/HTTP≠200) rebascule sur
CONFIGURATION via `_on_mm_queue_result`.

**(b) Un joueur ÉLIMINÉ était encore « en salle », côté SERVEUR.** Rien ne retire la ligne
`GameRoomPlayer` d'un éliminé (seul `_destroy_room` purge, au départ du DERNIER socket) et la salle
reste `in_progress` tant que la partie tourne. Les gardes du matchmaking le voyaient donc en salle :
`POST /matchmaking/queue` → `in_room`, `GET /matchmaking/status` → `in_game` → `_offer_resume()` →
panneau CONFIGURATION en sous-état « reprise », polling arrêté. Un mort devait attendre que les
AUTRES finissent leur partie pour pouvoir rejouer — alors que la PERMADEATH (§8.61) lui interdit tout
retour, et que le bouton REJOUER de l'overlay observateur (§8.70) promet exactement le contraire.
→ **Correctif** : nouvelle garde `_blocking_membership_room(db, redis, uid, …)` — `_active_membership_room`
**plus** le filtre `_is_out_of_room()` qui lit l'état de partie en Redis et considère la salle NON
BLOQUANTE si le joueur y est `eliminated` **ou** si la partie a déjà un `winner_id`. Utilisée par
`queue_join`, `GET /status`, `private_create` et `private_join` ; **pas** par `private_leave` /
`private_start`, qui s'en servent comme *résolution* de la salle du joueur et non comme *garde*.
- La ligne de membership est **CONSERVÉE** : elle sert encore à `router._is_room_member`, donc un mort
  qui crashe peut se reconnecter pour continuer à regarder. On rend la salle non bloquante, on ne
  supprime rien.
- **FAIL-OPEN INVERSÉ, assumé** : état Redis absent / corrompu / joueur absent de l'état → la garde
  reste **BLOQUANTE**. On préfère un REJOUER refusé à un joueur bien VIVANT éjecté de sa partie.
- La garde reste pleinement efficace pour un joueur vivant (contre-épreuve dans le test).

> **Fichiers.** MODIFIÉS : `api/v1/endpoints/matchmaking.py` (garde + helpers),
> `test_private_codes.py` (+9 asserts). Côté client : `scripts/managers/network_manager.gd`,
> `scripts/ui/search_screen.gd`.
>
> **Validation.** `test_private_codes.py` **33 ✅ / 0 ❌** · suite backend inchangée (2 échecs
> pré-existants). **Contre-épreuve de mutation** : garde remise à `_active_membership_room` →
> **3 asserts tombent** (le test couvre donc réellement le bug), source restaurée dans le même bloc,
> aucun marqueur résiduel. Client : `--import` **0 ERROR**, boots `search_screen.tscn`,
> `game/main.tscn`, `spectator_overlay.tscn`, `main_menu.tscn` **0 ERROR**.
>
> ⚠️ **NON REJOUÉ EN PARTIE RÉELLE** : le scénario complet (mourir → REJOUER → file → nouvelle
> partie) demande une vraie salle multijoueur. Les deux causes sont couvertes par des tests, mais
> l'enchaînement bout en bout reste à confirmer en partie locale.

> **Fichiers.** NOUVEAUX : `api/game/zone_settings.py`, `api/game/final_scoring.py`,
> `api/game/observer_bets.py`, `test_zone_growth.py`, `test_match_timer.py`,
> `test_objectives_new_types.py`, `test_rewards_placement.py`, `test_observer_bets.py`.
> MODIFIÉS : `api/game/engine.py`, `api/game/objectives.py`, `api/game/rewards.py`,
> `api/game/economy.py`, `api/game/state_manager.py`, `api/game/state_schemas.py`,
> `api/sockets/router.py`, `api/sockets/connection_manager.py`, `core/config.py`.
>
> **Validation.** `test_zone_growth.py` **43 ✅** · `test_match_timer.py` **55 ✅** ·
> `test_objectives_new_types.py` **90 ✅** · `test_rewards_placement.py` **26 ✅** ·
> `test_observer_bets.py` **59 ✅** · suite backend complète verte (non-régressions mises à jour :
> `test_rewards.py` 317 ✅, `test_objectives_double.py` 40 ✅, `test_economy.py`, `test_map_registry.py`,
> `test_setup_phase.py`, `test_bot_ai.py`, `test_repro_turn_combat.py`) — **sauf `test_missions.py` et
> `test_simulation.py`**, en échec **PRÉ-EXISTANT sur HEAD** (vérifié en rejouant les deux suites
> contre les sources extraites de `HEAD` : échecs identiques), hors périmètre.
>
> **⚠️ DÉFAUT D'ÉQUILIBRAGE CORRIGÉ EN COURS DE ROUTE.** `fortified_hold` était spécifié à
> `min_garrison = 3` : à ce seuil l'objectif est **DÉJÀ REMPLI à la sortie du déploiement initial**
> (3 j sur classic_42 : 14 territoires / 49 troupes ⇒ 8 × 3 = 24 troupes suffisent) et la partie se
> terminait **au tour 1, sans qu'aucune action ne soit jouée** — reproduit par `test_bot_ai.py`
> (vainqueur en 0 pas de boucle). Porté à **7** (8 × 7 = 56 > 49 sur tous les effectifs des deux
> cartes) : arithmétique complète en commentaire dans `objectives.OBJECTIVE_PARAMS_BY_MAP`.
>
> **⚠️ POINT D'ÉQUILIBRAGE À TRANCHER AU PLAYTEST (livré tel que spécifié).** `conquer_territories`
> à **15** sur classic_42 rend l'objectif atteignable **en UNE conquête à 3 joueurs** (distribution
> initiale : 14 territoires chacun) — la partie de bots de non-régression se termine désormais au
> **tour 3**. À 4/5/6 joueurs il faut respectivement +4/+6/+8 conquêtes, ce qui est sain. Valeur de
> registre : une seule ligne à changer (18-20 rendrait les parties à 3 comparables aux autres).

---

## §8.121 — STREAMABILITÉ & PARTAGE : le JOURNAL D'ATTAQUES (volet RÉSEAU — unique ajout backend)

> **Périmètre.** Volet backend de `PROMPT_STREAMABILITE_PARTAGE.md` (LOT A). Détail frontend :
> **§8.121 de `FRONTEND_INTERFACES.md`** (Rapport de Trahison, révélation théâtrale, carte de
> partage, mode streamer — **100 % client**). **Strictement ADDITIF** (règle §1.5) : aucune clé de
> payload existante n'est renommée ou supprimée, **aucune règle de jeu modifiée** — le journal est
> une TRACE, il n'influence rien. **AUCUN COMMIT — redéploiement VPS requis.** Client et serveur
> partent **ENSEMBLE** (gate de version WS §9) : sans serveur redéployé, l'onglet TRAHISONS du
> Rapport Post-Op se masque proprement (repli §9.2) et la carte de partage s'exporte sans sa ligne
> de trahison.
>
> **Le problème résolu.** `GameStatistics` ne contient que des **agrégats PAR JOUEUR**
> (`combat_kills_by_player`, `conquests_by_player`, `eliminations_by_player`…). Il est donc
> **impossible de savoir QUI a frappé QUI** — donc impossible de raconter la partie (« le coup de
> poignard », la matrice d'agression, la chaîne des chutes). C'est la SEULE donnée manquante ;
> l'ANALYSE narrative, elle, est de la **présentation** et vit côté client (vues pures §6.1).
>
> ### 1. Champ ADDITIF `GameStatistics.attack_log: List[dict]` (défaut `[]`)
>
> Une entrée par attaque **RÉSOLUE**, appendée au site **UNIQUE** `engine._handle_attack` :
>
> ```jsonc
> { "turn": 12,             // int — GameState.current_turn (compteur GLOBAL de tours-joueur)
>   "round": 3,             // int — round GLOBAL (voir 2. ci-dessous)
>   "attacker_id": 11,      // int — toujours le joueur courant
>   "defender_id": 12,      // int | null — null = territoire NEUTRE (aucun adversaire)
>   "kills": 2,             // int — pertes DÉFENSIVES infligées par cette attaque
>   "conquered": true,      // bool — le territoire a changé de main
>   "hero_kill": false }    // bool — le duel de CETTE attaque a achevé le héros défenseur
> ```
>
> Valeurs `int`/`bool` **PURES** (piège JSON float §5). **PLAFOND `engine.ATTACK_LOG_CAP = 300`** :
> au-delà, plus aucun append (même garde-fou que `TERRITORY_HISTORY_CAP`, borne mémoire/Redis).
> 300 attaques couvrent très largement une partie bornée à 15 min (`MATCH_TIME_LIMIT_S`, §8.120) ;
> une partie qui dépasserait ce volume garde son **début** de récit — exactement ce que le Rapport
> de Trahison raconte. L'append est posé **APRÈS** le bloc de permadeath, à dessein : sans quoi
> `hero_kill` ne pourrait pas refléter le coup de grâce de l'attaque en cours.
>
> ### 2. `round` — DÉRIVÉ de la timeline de domination, jamais de `current_turn`
>
> Le moteur n'a pas de compteur de round. `engine.current_global_round(state)` renvoie
> **`len(statistics.territory_history) + 1`** : `_append_territory_snapshot` est appelé exactement
> une fois par nouveau round global (`_end_turn`), donc le snapshot d'indice `i` photographie la
> **FIN du round `i+1`**. Conséquence VOULUE : les rounds du journal sont **exactement l'axe X** de
> la courbe de domination du Rapport Post-Op — « coup de poignard au round N » et « moment décisif
> au round N » se lisent sur la même échelle. ⚠️ Ne **jamais** re-dériver le round depuis
> `current_turn / effectif` : le nombre de tours par round **diminue** avec les éliminations.
>
> ### 3. Diffusion — EXCLU du chemin chaud, INCLUS dans le `game_over`
>
> - **`router._state_payload` RETIRE `statistics.attack_log`** de chaque rediffusion d'état (`pop`
>   défensif). C'est le point de passage **unique** de toutes les diffusions porteuses d'état
>   (`broadcast_state_to_room` depuis `router` **et** `bot_runner`, plus `_send_current_state`) —
>   vérifié : aucun autre `model_dump` ne sort vers le réseau. Motif : le journal ne sert à **aucune
>   vue en jeu** et grossit à chaque attaque ; le diffuser ferait payer à CHAQUE `action_result`
>   (plusieurs par tour) le poids cumulé de toutes les attaques de la partie.
> - **`game_over` gagne `attack_log`**, champ **PUBLIC** (piège n° 9 : identique pour tous, aucune
>   donnée personnelle). Aucune redaction nécessaire : « qui a frappé qui » a déjà été diffusé en
>   direct par les évènements `attack_result` (§8.85) — on ne fait que le **remettre d'un bloc**
>   pour que le client puisse en tirer un récit sans avoir eu à mémoriser 300 évènements.
>
> ### 4. Rétro-compatibilité
>
> Défaut Pydantic `[]` → une partie **EN COURS** pendant le redéploiement se redésérialise sans le
> champ et se remet à journaliser aussitôt (son récit démarre au redéploiement). Un client antérieur
> ignore la clé du `game_over` ; un client à jour face à un serveur non redéployé lit `[]` et masque
> l'onglet TRAHISONS (§9.2).
>
> > **Fichiers.** NOUVEAU : `test_attack_log.py`. MODIFIÉS : `api/game/state_schemas.py`,
> > `api/game/engine.py`, `api/sockets/router.py`.
> >
> > **Validation.** `test_attack_log.py` **40 ✅ / 0 ❌** (append, forme exacte à 7 clés, types purs,
> > défenseur neutre, cohérence `conquered` ↔ carte sur 60 tirages, `hero_kill` au coup de grâce +
> > contre-épreuve « seulement blessé », attaque refusée sans trace, dérivation du round et son
> > indépendance à `current_turn`, plafond 300, ABSENCE dans `_state_payload` avec non-régression des
> > autres agrégats, présence dans l'export `game_over`, rétro-compat Redis). Suite backend complète
> > verte — **sauf `test_missions.py` (37 OK / 4 KO) et `test_simulation.py` (`fastapi` absent du
> > poste)**, en échec **PRÉ-EXISTANT sur HEAD** (déjà constaté en §8.119/§8.120), hors périmètre.
> > **Contre-épreuve de mutation** : 5 régressions injectées à chaud (append supprimé, champ laissé
> > dans les diffusions d'état, plafond désarmé, `hero_kill` jamais posé, round re-dérivé de
> > `current_turn`) → **5/5 détectées**, sources restaurées dans le même bloc, 0 marqueur résiduel.
>
> ### 5. HORS PÉRIMÈTRE (assumé)
>
> Aucun `territory_id` dans les entrées : le récit se joue à l'échelle des **joueurs**, et les ids de
> territoires doubleraient le poids du bloc sans nourrir aucune des quatre analyses du client. ⚠️
> Conséquence documentée : la clause « **voisins depuis ≥ 2 rounds** » de la définition produit du
> coup de poignard n'est **pas** calculable (il faudrait un historique de **propriété** par round,
> alors que `territory_history` ne stocke que des **comptes**) — le client la remplace par la seule
> durée de **calme** entre les deux joueurs, cf. §8.121 de `FRONTEND_INTERFACES.md`.

---

## §8.123 — PACTES DE NON-AGRESSION : diplomatie éphémère, trahison publique, réputation (volet RÉSEAU/MOTEUR)

> **Périmètre.** Volet backend de `PROMPT_PACTES_DIPLOMATIE.md` (LOTS A→C ; détail frontend :
> **§8.123 de `FRONTEND_INTERFACES.md`** ; règle de jeu : **§4.11 de `ARCHITECTURE_ET_REGLES.md`**).
> **Strictement ADDITIF** (règle §1.5) : aucune clé de payload existante n'est renommée ou
> supprimée. **AUCUN COMMIT — redéploiement VPS requis.** Client et serveur partent **ENSEMBLE**
> (gate de version WS §9) : le client à jour affiche un bouton que seul le serveur redéployé
> accepte, et sans serveur redéployé la section « LES PACTES » du Rapport Post-Op se masque
> proprement (repli §9.2).
>
> ⛔ **AUCUN EFFET MÉCANIQUE — c'est LA décision produit de ce chantier.** Un pacte n'accorde aucun
> bonus, n'inflige aucun malus, ne bloque **aucune** attaque (frapper son partenaire est
> parfaitement LÉGAL et se résout exactement comme n'importe quelle attaque), et n'influence ni le
> matchmaking, ni le RP, ni les récompenses. Sa seule force est d'être **PUBLIC** : le rompre
> déclenche un bandeau « ⚡ TRAHISON », alimente le Rapport de Trahison et s'inscrit à vie sur le
> profil. *Le drame EST la mécanique ; la réputation est la seule punition.* Aucun canal privé
> n'est réintroduit (le chat par destinataire reste le seul lieu de négociation, §4 — le pacte ne
> fait qu'**officialiser**).

### 1. Champ ADDITIF de l'état — `GameState.pacts: List[dict]` (défaut `[]`)

Historique **COMPLET** de la partie (offres comprises), une entrée par pacte :

```jsonc
{ "id": 3,                   // int — 1-based, croissant
  "a_id": 11,                // int — le PROPOSANT (le sens de la proposition est conservé)
  "b_id": 12,                // int — le destinataire
  "proposed_by": 11,         // int — redit explicitement qui a tendu la main (le client ne déduit rien)
  "status": "active",        // string — "pending" | "active" | "broken" | "declined" | "expired"
  "created_round": 3,        // int — round GLOBAL de l'OFFRE
  "expires_at_round": 5,     // int — round d'acceptation + 2 (0 tant que l'offre est pendante)
  "ended_round": 0,          // int — round de la FIN (rupture / refus / expiration ; 0 sinon)
  "broken_by": null }        // int | null — le TRAÎTRE, si status == "broken"
```

- **`ended_round` n'est pas du confort** : il porte le départ du **cooldown** *et* la ligne
  « ROMPU PAR X **AU ROUND N** » du Rapport de Trahison. `expires_at_round` ne pouvait pas jouer ce
  rôle (une rupture survient AVANT l'échéance prévue, et une offre refusée n'en a jamais eu).
- **Le `round` est celui du journal d'attaques** (§8.121) : `pacts.current_round_of` applique la
  même dérivation que `engine.current_global_round` (`len(territory_history) + 1`). « Coup de
  poignard au round N » et « pacte rompu au round N » se lisent donc sur **la même échelle** que la
  courbe de domination du Rapport Post-Op. Un test de non-divergence garde les deux alignées.
- **PLAFOND `pacts.PACT_RULES["history_cap"]` = 50 entrées.** Atteint, une nouvelle OFFRE est
  **refusée** (`cap_reached`) — jamais acceptée puis oubliée silencieusement. Hors de portée d'une
  partie bornée à 15 min (§8.120) avec 1 offre pendante par joueur.
- Défaut `[]` → une partie **EN COURS** pendant le redéploiement se redésérialise sans le champ.

### 2. State Redaction — LE point délicat du chantier

`connection_manager._redact_state_for_player` filtre désormais `state.pacts` via
`pacts.redact_pacts_for` (règle énoncée **une seule fois**, dans le module pur, et testée) :

| Statut | Visibilité |
|---|---|
| `active` · `broken` · `expired` | **PUBLICS** — un pacte EST un signal, une trahison un spectacle. |
| `pending` · `declined` | **Les DEUX joueurs concernés, et eux seuls.** |

Diffuser une négociation donnerait à toute la table la carte des discussions en cours, et ferait
d'un refus une humiliation publique — deux choses que le dispositif ne veut pas. La **redaction est
LEVÉE au `game_over`** (bloc public `pacts`, cf. §5) : le secret protégeait une partie en cours.

### 3. Messages client→serveur

```jsonc
{ "action": "pact_offer",   "payload": { "target_player_id": 12, "action_id": "…" } }
{ "action": "pact_respond", "payload": { "pact_id": 3, "accept": true } }
```

- **`pact_offer`** passe par le **pipeline standard** de `process_action` : c'est une action de MON
  tour (phases **1-4**). Elle hérite donc de la vérification de tour, des gardes d'état bloquant
  (aucune diplomatie tant qu'une conquête ou un choix d'Éclipse est en suspens) et de l'idempotence
  `action_id` — un double-clic ne crée jamais deux offres.
- **`pact_respond` est routée AVANT la vérification de tour** (`process_action`, précédent
  `place_initial`). **POURQUOI** : répondre est *par construction* ce qu'on fait quand ce n'est PAS
  son tour — l'offre arrive pendant le tour de quelqu'un d'autre ; la garde « c'est votre tour »
  refuserait 100 % des réponses légitimes. Ce qu'on **garde** : le verrou de salle (l'action mute
  l'état) et la rediffusion redactée. Ce qu'on **abandonne sciemment** : la fenêtre `action_id`,
  inutile ici — un second clic sur ACCEPTER trouve l'offre en `active` et repart en `not_pending`,
  la garde est structurelle.

**Refus — convention zéro-4xx §8.112.** Réponse `{"type":"error","message":…,"reason":<code>}`,
jamais un 4xx. Jeu **FERMÉ** de 8 raisons, chacune traduite côté client (`PACT_ERR_*`) :

| `reason` | Quand |
|---|---|
| `not_your_turn` | hors tour, partie non démarrée ou gagnée, **phase hors 1-4**, joueur retiré |
| `invalid_target` | cible inconnue / morte / retirée / soi-même ; ou proposant disparu à la réponse |
| `pair_busy` | un pacte actif OU une offre pendante existe déjà entre les deux (dans un sens ou l'autre) |
| `cap_reached` | 2 pactes actifs (chez l'un **ou** l'autre), 1 offre sortante déjà pendante, ou historique plein |
| `cooldown` | trêve en cours — **porte en plus `remaining_rounds: int`** (voir ci-dessous) |
| `final_protocol` | PROTOCOLE FINAL (§4.7) : on ne négocie plus dans les 2 dernières minutes |
| `not_pending` | réponse sur une offre déjà résolue, qui ne vous vise pas, ou à sa propre offre |
| `ranked_disabled` | **DORMANTE** : jamais émise tant que `PACT_RULES["in_ranked"]` vaut `True` |

- ⚠️ « phase interdite / partie non démarrée / partie gagnée » retombent volontairement sur
  `not_your_turn` : le jeu de raisons est FERMÉ, et ces trois cas disent au joueur exactement la
  même chose. En pratique le client ne montre le bouton qu'en phases 1-4 de son tour.
- **`remaining_rounds`** (clé ADDITIVE, `int`) n'accompagne que le refus `cooldown` — le seul refus
  chiffré du jeu : sans lui le joueur ne sait pas quand réessayer. Absente partout ailleurs.
- **ORDRE DES CONTRÔLES FIGÉ** (il décide quelle raison s'affiche quand plusieurs s'appliquent) :
  légitimité du proposant → validité de la cible → PROTOCOLE FINAL → paire occupée → plafonds →
  trêve. Du plus fondamental au plus circonstanciel : « vous ne pouvez pas agir », puis « pas avec
  lui », puis « pas maintenant ».

### 4. Évènements — ce qui est PUBLIC, et ce qui ne l'est pas

Une offre et un refus sont des informations **PRIVÉES** (savoir qui négocie avec qui est déjà une
information de jeu). Or l'`event` d'une action part en diffusion **identique** à toute la salle —
seul le `state` est redacté par destinataire. Le moteur isole donc la part nominative dans un bloc
`pact_private` que **`router._drain_pact_private` RETIRE de l'évènement AVANT toute diffusion**,
puis route en messages personnels (patron `spy_result` §8.24).

| Action | Évènement DIFFUSÉ (`action_result`) | Message PRIVÉ (aux 2 concernés) |
|---|---|---|
| offre | `{"event_type":"pact_offer"}` — **aucune identité** | `{"type":"pact_offer","pact_id","proposer_id","target_id","created_round","duration_rounds"}` |
| réponse — **refus** | `{"event_type":"pact_response"}` — **aucune identité** | `{"type":"pact_response","pact_id","accept":false,"proposer_id","target_id"}` |
| réponse — **acceptation** | `{"event_type":"pact_active","pact_id","a_id","b_id","proposed_by","expires_at_round"}` — **PUBLIC, c'est le but** | — |

**Évènements système structurés** (pipeline `system_events` existant, tous **PUBLICS**, doublés
d'une ligne `system_messages` LEGACY en anglais invariant sauf mention contraire) :

```jsonc
{ "code": "pact_active",  "pact_id": 3, "a_id": 11, "b_id": 12, "expires_at_round": 5 }
{ "code": "pact_broken",  "pact_id": 3, "betrayer_id": 11, "victim_id": 12 }
{ "code": "pact_expired", "pact_id": 3, "a_id": 11, "b_id": 12 }
```

- `pact_broken` voyage dans les **`system_events` de l'évènement `attack_result`** : `_handle_attack`
  draine désormais le tampon, sans quoi le bandeau « ⚡ TRAHISON » attendrait le prochain
  `turn_passed` — plusieurs actions plus tard.
- **Une offre restée sans réponse ne produit AUCUN évènement** : elle est soldée en `declined`
  **silencieux** au tour suivant de son auteur. Que personne n'ait répondu n'est pas un fait de
  jeu, et l'annoncer reviendrait à dire à toute la table « X a été ignoré ». Seule la trêve en
  découle.

### 5. Autres champs ADDITIFS

- **`attack_result.pact_broken: bool`** — cette attaque a-t-elle rompu un pacte (détail dans
  `system_events`).
- **`GameStatistics.attack_log[*].pact_broken: bool`** — **8ᵉ clé** du journal d'attaques (§8.121).
  C'est elle qui fait d'une attaque **LE COUP DE POIGNARD** du Rapport de Trahison, sans aucune
  heuristique : une trahison DÉCLARÉE prime toute analyse de voisinage.
- **`GameStatistics.pacts_broken_by_player: Dict[int,int]`** — compteur de partie, incrémenté au
  site UNIQUE de la rupture.
- **`game_over.pacts`** — champ **PUBLIC** (piège n° 9) : l'historique COMPLET, redaction levée.
- **`GET /profile/stats` et `GET /profile/public/{username}` : `pacts_broken: int`** (défaut 0).
  Donnée **publique par construction** — un compteur de trahisons que personne ne peut consulter ne
  sert à rien. Il reste du **palmarès** : la liste blanche de `PublicProfileResponse` (§8.107) est
  élargie **délibérément**, aucune donnée économique ou de compte n'entre par cette porte.

### 6. Registre (module PUR `api/game/pacts.py`) — aucune valeur en dur dans le moteur

| Clé de `PACT_RULES` | Valeur | Rôle |
|---|---|---|
| `duration_rounds` | **2** | `expires_at_round = round d'acceptation + 2`. Court à dessein : une fenêtre de respiration, pas une alliance de fait. |
| `max_active_per_player` | **2** | Sans plafond, un joueur signerait avec toute la table et neutraliserait le « chacun-pour-soi » sans rien risquer. |
| `max_pending_outgoing` | **1** | Proposer est un engagement, pas un mailing. |
| `cooldown_rounds` | **2** | Trêve entre les deux MÊMES joueurs après rupture / refus / expiration / offre ignorée. Empêche le harcèlement et donne du poids au refus. |
| `in_ranked` | **`True`** | Aucun avantage mécanique ⇒ aucune raison d'exclure. Le passer à `False` ferme la mécanique en classée **sans toucher une ligne de moteur** (refus `ranked_disabled` déjà câblé). |
| `history_cap` | **50** | Garde-fou mémoire/Redis, même nature que `ATTACK_LOG_CAP`. |

### 7. Cycle de vie et sites d'accrochage

`PENDING` → (`ACTIVE` | `DECLINED`) → (`BROKEN` | `EXPIRED`).

- **Expiration** — `pacts.sweep_expired` à l'entame de **chaque** tour de joueur, **après**
  l'éventuelle téléportation de zone : le numéro de round vient tout juste d'être arrêté par
  `_append_territory_snapshot`, dont il dérive. Le faire plus tôt daterait toutes les échéances
  d'un round (un pacte durerait 3 rounds au lieu de 2). Appelé à chaque tour et non seulement aux
  transitions : la fonction est idempotente, et cette redondance garantit qu'aucune échéance ne
  peut être sautée.
- **Offre ignorée** — `pacts.offer_timeout_sweep` au même endroit, pour le joueur ENTRANT : une
  offre faite au tour précédent a donc vécu un round complet. Sans ce balayage, une offre ignorée
  bloquerait à vie l'unique créneau sortant de son auteur.
- **Rupture** — dans `_handle_attack`, **après** la résolution complète (dés, pertes, conquête,
  permadeath) et **avant** l'append du journal d'attaques. C'est une pure LECTURE suivie d'un
  enregistrement : aucune ligne au-dessus ne consulte les pactes.
  **NE ROMPENT PAS un pacte, à dessein :** les **dégâts de zone** (personne ne les décide) ·
  **ABSOLUTION** (§8.119 — purger un territoire contaminé du partenaire l'**AIDE**) · **BASTION
  D'ACIER** (§8.119 — ne cible que SES propres territoires) · une attaque sur un territoire
  **NEUTRE** ayant appartenu au partenaire (plus de camp à trahir). **Rompent en revanche :** toute
  attaque RÉSOLUE, y compris **perdue**, y compris la **FRAPPE FANTÔME** non adjacente — c'est
  l'intention de frapper qui trahit, pas le résultat.

### 8. BOTS — ils répondent, ils honorent, ils ne trahissent JAMAIS

Sans participation des bots, la mécanique serait morte en partie mixte — majoritaire aujourd'hui.

- **Ils ne PROPOSENT jamais** : initier une diplomatie demande une intention de partie qu'une IA de
  remplissage n'a pas.
- **Ils RÉPONDENT** via `bot_ai.decide_pact(state, bot_id, proposer_id)` — heuristique PURE et
  déterministe, volontairement lisible en une phrase pour que le joueur puisse l'apprendre en
  jouant : *j'accepte si tu n'es pas plus fort que moi (comparaison des territoires) et s'il me
  reste de la place (`max_active_per_player`)*. Un pacte avec le meneur ne protègerait que lui.
- **Réponse IMMÉDIATE, dans le traitement de l'offre** (`engine._handle_pact_offer`) : aucune task
  asyncio nouvelle — une task de plus par offre serait un ordonnancement entier à maintenir pour
  une décision qui ne demande aucune attente. Le **rythme d'affichage** (« le bot réfléchit ») est
  purement CLIENT : la réponse passe par la file de narration des actions adverses du HUD.
- **FILTRE D'HONNEUR** (`bot_ai._action_attack`) : les territoires des partenaires actifs sont
  exclus des cibles. C'est une restriction de **CIBLAGE**, pas une règle de jeu — le moteur
  accepterait parfaitement l'attaque. **Un bot ne trahit JAMAIS : la trahison est un privilège
  humain**, c'est le seul geste du jeu dont le sel vient entièrement de qui l'accomplit.
  *(`_enemy_neighbors` reste volontairement AVEUGLE aux pactes : elle sert aussi à mesurer la
  MENACE pour le déploiement — un partenaire peut trahir à tout moment.)*

### 9. Persistance — `users.pacts_broken INTEGER NOT NULL DEFAULT 0`

Auto-migrée au boot (`db_migrations.sync_missing_columns` — `server_default` présent, aucune action
humaine sur la prod, contrairement à `migration_steam_auth.sql`). Archive de parité :
`backend/migration_pacts.sql`. Accumulée en fin de partie par `process_match_results` depuis
`build_match_stats["pacts_broken"]`, **bots exclus** (ids < 0, sortis de la boucle bien avant).
N'entre dans **aucun** barème — ni XP, ni Coins, ni RP, ni classement.

> **Fichiers.** NOUVEAUX : `api/game/pacts.py`, `migration_pacts.sql`, `test_pacts.py`,
> `test_pacts_flow.py`. MODIFIÉS : `api/game/engine.py`, `api/game/state_schemas.py`,
> `api/game/bot_ai.py`, `api/game/state_manager.py`, `api/sockets/router.py`,
> `api/sockets/connection_manager.py`, `models/models.py`, `models/schemas.py`,
> `api/v1/endpoints/profile.py`.
>
> **Validation.** `test_pacts.py` **113 ✅ / 0 ❌** · `test_pacts_flow.py` **83 ✅ / 0 ❌** · suite
> backend complète verte, non-régressions mises à jour (`test_attack_log.py` → 8ᵉ clé,
> `test_profile_data.py` → liste blanche publique élargie DÉLIBÉRÉMENT, `test_rewards.py` /
> `test_bot_ai.py` / `test_pass_tiers.py` → doublures `User` dotées de `pacts_broken`) — **sauf
> `test_missions.py` et `test_simulation.py`**, en échec **PRÉ-EXISTANT sur HEAD** (vérifié en
> rejouant les deux suites contre les sources extraites de `HEAD` : échecs identiques,
> `IndexError` et `fastapi` absent du poste), hors périmètre.

---

## §8.124 — MODE ÉQUIPES : escouades, files DUO 2v2 & ESCOUADE 3v3, victoire commune

> **Jouer entre amis, contre le monde.** Trois piliers : les **ESCOUADES** (groupe pré-partie à
> code, mis en file d'un bloc par son chef), deux **PLAYLISTS d'équipe**, et les **règles d'équipe**
> en partie (tir allié interdit, logistique partagée, objectif secret d'ÉQUIPE, victoire commune).
> **Casual uniquement — la Classée reste solo à 5, intouchée.**
>
> ⚠️ **INVARIANT N° 1 DU CHANTIER : `team_id = 0` = SANS ÉQUIPE.** Une partie FFA porte
> `team_mode == ""` et `team_id == 0` partout, et TOUT ce qui suit y est neutre. Une partie solo
> classique est bit-à-bit celle d'avant le chantier — c'est vérifié par contre-épreuve
> (`test_team_flow.py` [8] : à graine RNG identique, les MÊMES dés sortent).

### 1. Registre des playlists — SOURCE SERVEUR (`api/game/teams.TEAM_PLAYLISTS`)

| id | carte | équipes × taille | effectif | ouverte |
|---|---|---|---|---|
| `duo_2v2` | `skirmish_atlantic` | 2 × 2 | 4 | ✅ |
| `squad_3v3` | `classic_42` | 2 × 3 | 6 | ✅ |
| `trio_2v2v2` | `classic_42` | 3 × 2 | 6 | ⛔ `enabled: False` |

`GET /squad/playlists` (PUBLIC, sans auth) → `{"playlists": {id: {map_id, team_size, team_count,
capacity, enabled}}}` — **seules les OUVERTES sont servies**. Le client n'en code AUCUNE valeur en
dur : une playlist fermée est **ABSENTE** du hub, pas grisée (une carte grisée est une promesse).
Anti-fragmentation : chaque file divise le pool, on n'en ouvre que DEUX.

⚠️⚠️ Les seuils d'objectifs de `trio_2v2v2` (`objectives.TEAM_OBJECTIVE_PARAMS_BY_PLAYLIST`) sont
**PROVISOIRES** et à revalider AVANT toute activation : ils n'ont jamais été joués et ne se
déduisent pas des deux autres (à 3 équipes sur classic_42, la parité tombe à 14 territoires par
équipe — le seuil du 3v3, 24, serait hors d'atteinte).

### 2. Escouades (REST, préfixe `/squad`) — pattern `/private`, sécurité IDENTIQUE

`POST /squad/create {playlist}` · `POST /squad/join {code}` · `POST /squad/leave` ·
`GET /squad/status` · `POST /squad/queue {playlist?}` · `POST /squad/dequeue`.

Les SIX routes rendent la **MÊME shape** `SquadStateResponse` : `{squad, code, playlist, team_size,
members: [{user_id, name, is_leader}], is_leader, in_queue, queued_since_s, reason, …}`. Un seul
callback client (`NetworkManager._on_squad_response`) : six handlers auraient été six occasions
d'oublier de propager `reason`.

- **Sécurité des codes : RÉUTILISÉE À L'IDENTIQUE.** Même `generate_code`/`normalize_code`
  (alphabet sans I/L/O/0/1, `secrets`), même table `sanctions`, même compteur `mm:fail:{uid}`,
  même escalade, même raison unifiée **`unavailable`** — format invalide, code inconnu, escouade
  PLEINE et escouade DÉJÀ EN FILE rendent tous le même code. **Aucun oracle** : un bruteforceur ne
  doit pas pouvoir cartographier les codes valides. Il n'y a pas deux systèmes de codes ici, il y
  en a UN.
- ⚠️ **DIFFÉRENCE ASSUMÉE AVEC LE SALON PRIVÉ : les PSEUDOS sont exposés.** Le salon est anonyme
  (« N/max », décision §8.116) parce qu'un code peut circuler n'importe où. Une escouade se rejoint
  parce qu'un AMI vous a passé le code ; savoir qui est déjà là est le minimum vital d'un groupe.
- **Le CHEF** met en file et dissout ; un membre qui part ne dissout rien. Aucun transfert de rôle
  (ce serait une mécanique de clan — chantier distinct).
- **Redis** : `mm:squad:{CODE}` (JSON) + `mm:squadof:{uid}` (index inverse, auto-réparant), TTL 24 h
  rafraîchi à chaque écriture. L'escouade **SURVIT à la partie** — c'est sa raison d'être.
- Une escouade PLUS GRANDE que l'équipe visée est refusée **AVANT** la file (`reason: "full"`) :
  le packing ne scindant jamais un groupe, elle attendrait sinon indéfiniment sans qu'on lui dise
  pourquoi.

### 3. File d'équipe — GROUPES ATOMIQUES

- ZSET `mm:q:team:{playlist}` (`matchmaking.team_bucket_key`). ⚠️ Ses membres sont des ids de
  **GROUPE** (code d'escouade, ou `solo:<uid>`), jamais des ids de joueur : **l'atomicité est
  structurelle, la file ne sait même pas découper**.
- Un joueur SOLO est un **groupe de taille 1** → `POST /squad/queue` est l'UNIQUE point d'entrée des
  deux cas. Un second chemin aurait été un second packing, un second heartbeat, une seconde purge.
- **Ticket** : la MÊME clé `mm:ticket:{uid}` que les files solo (toutes les gardes « déjà en file »
  du dépôt continuent de fonctionner sans une ligne de plus), enrichie de
  `{queue: "team", playlist, group_id, group_size}`.
- `GET /matchmaking/status` gagne un bloc **ADDITIF** `{"squad": {playlist, code, size}}`, **présent
  uniquement pour un ticket d'équipe** : la réponse d'une file solo est bit-à-bit celle d'avant.
  `code` vide = joueur solo en file d'équipe (« VOUS SEREZ ASSOCIÉ À DES COÉQUIPIERS »).
- **PACKING** (`matchmaking.plan_team_bucket`, PUR) — deux passes, et la séparation compte :
  1. **SÉLECTION** (densité, FIFO) : first-fit — décide QUI joue, maximise les humains embarqués ;
  2. **RÉPARTITION** (équilibre) : plus grand groupe d'abord → équipe la moins peuplée — interdit
     « une équipe 100 % humaine contre une 100 % bots » chaque fois qu'un autre packing existe.

  Les mélanger COÛTE des humains : à 2×3 avec la file `[1, 1, 3]`, placer « dans la moins peuplée »
  dès la sélection sépare les solos et le groupe de 3 ne rentre plus → 2 embarqués au lieu de 5.
- **Bot-fill 60 s** (même `MM_QUEUE_BOT_FILL_S` que partout), mesuré sur le plus ANCIEN ticket
  retenu. Une salle COMPLÈTE part immédiatement.
- **HEARTBEAT — purge par GROUPE ENTIER** : un seul membre au ticket mort sort TOUTE l'escouade de
  la file (tickets effacés). Jamais de scission silencieuse ; l'escouade reste FORMÉE, le chef
  relance. Même règle à la formation : si un ticket disparaît entre la purge et l'engagement, la
  salle entière est ANNULÉE et les groupes re-filés (la file solo, elle, remplace le disparu par un
  bot — impossible ici sans scinder un groupe).
- ⛔ **JAMAIS de playlist d'équipe CLASSÉE** : `_form_team_room` crée toujours `is_ranked=False`.

### 4. État de partie — CHAMPS ADDITIFS

| champ | défaut | rôle |
|---|---|---|
| `PlayerState.team_id` | `0` | équipe du joueur (**0 = FFA**). PUBLIC. |
| `GameState.team_mode` | `""` | id de playlist (**"" = FFA**) — LA bascule de toutes les règles. PUBLIC. |
| `GameState.team_objectives` | `{}` | `{team_id: objectif}` — **REDACTÉ** (voir ci-dessous). |
| `GameState.winning_team_id` | `None` | équipe victorieuse. PUBLIC. |

**REDACTION** (`connection_manager._redact_state_for_player`) : chaque joueur ne reçoit QUE
l'objectif de SON équipe — mais il le reçoit **EN ENTIER**, et ses coéquipiers voient exactement le
même. C'est la seule information volontairement **PARTAGÉE** du jeu : sans elle, une équipe ne peut
pas coordonner sa course et le mode se réduit à « on ne se tire pas dessus ». Redaction **LEVÉE** au
`game_over`.

### 5. Événements & chat

- **`team_victory {team_id, member_ids, victory_reason}`**, diffusé AVANT le `game_over` : le client
  joue son bandeau pendant que le Rapport Post-Op se prépare. Purement SCÉNIQUE — tout est aussi
  dans le `game_over`, un client qui l'ignore ne perd rien (§9.2).
- **Chat : `tab: "team"`** — le serveur résout les destinataires **SUR L'ÉTAT**, aucun id n'est
  transmis : un `tab:"team"` forgé ne peut donc pas adresser un autre camp. Hors partie d'équipe, le
  canal n'existe pas (refusé comme canal inconnu).
- **Refus de tir allié** : `ValueError` métier (convention zéro-4xx §8.112), traduction cliente
  `ERR_FRIENDLY_FIRE`.
- **Paris d'observateur** : nouveau code de refus `own_team` (clé `BET_ERR_OWN_TEAM`) sur le seul
  pari « vainqueur ». Le client retire déjà son propre camp du sélecteur.

### 6. `game_over` — QUATRE blocs additifs, tous PUBLICS (piège n° 9)

`team_mode` · `winning_team_id` · `team_podium: [{team_id, rank, member_ids, score}]` (l'équipe
VICTORIEUSE est placée en tête **d'autorité**, pas au score : elle a pu gagner par objectif alors
qu'une autre menait au départage) · `team_objectives_reveal: [{team_id, objective, description,
completed}]`. Tous vides en FFA. Les récompenses individuelles restent dans le bloc **PRIVÉ**
`match_rewards`.

⚠️ **`winner_id` reste renseigné en mode équipe** (le membre au meilleur score, cf.
`engine._award_team_victory`) : tout l'aval du jeu est bâti sur « UN vainqueur » (récompenses,
`MatchRecord`, historique, télémétrie, règlement des paris). Le rendre nullable aurait touché une
dizaine de sites pour un gain nul. Ce n'est **qu'un porte-drapeau** : il ne décide PLUS des
récompenses, `rewards.rank_map` raisonnant sur l'ÉQUIPE.

### 7. Persistance — `game_room_players.team_id INTEGER NOT NULL DEFAULT 0`

Auto-migrée au boot (`server_default` présent → aucune action humaine sur la prod). Archive de
parité : `backend/migration_teams.sql`. Toutes les lignes historiques prennent 0 et redeviennent
exactement ce qu'elles étaient : des parties chacun-pour-soi.

> **Fichiers.** NOUVEAUX : `api/game/teams.py`, `api/v1/endpoints/squad.py`, `migration_teams.sql`,
> `test_teams.py`, `test_team_packing.py`, `test_objectives_team.py`, `test_squad_flow.py`,
> `test_team_flow.py`. MODIFIÉS : `api/game/matchmaking.py`, `objectives.py`, `rewards.py`,
> `engine.py`, `state_schemas.py`, `state_manager.py`, `pacts.py`, `bot_ai.py`, `observer_bets.py`,
> `telemetry.py`, `missions_progress.py`, `api/sockets/router.py`, `connection_manager.py`,
> `matchmaker_runner.py`, `api/v1/endpoints/matchmaking.py`, `api/__init__.py`, `models/models.py`,
> `models/schemas.py`.
>
> **Validation.** `test_teams.py` **60 ✅** · `test_team_packing.py` **42 ✅** (dont 200 scénarios
> générés vérifiés sur 9 invariants) · `test_objectives_team.py` **52 ✅** · `test_squad_flow.py`
> **63 ✅** · `test_team_flow.py` **58 ✅** — **0 ❌**. Non-régressions vertes :
> `test_matchmaking_queue`, `test_private_codes`, `test_search_sanctions`, `test_pacts`,
> `test_pacts_flow`, `test_bot_ai`, `test_hero_abilities(_flow)`, `test_economy`, `test_factions`,
> `test_victory_reason`. Client : `--import` **0 ERROR**, boot headless des écrans de hub
> **0 ERROR**, capture PNG de l'écran ESCOUADE relue (un défaut de sélection de playlist corrigé
> grâce à elle).
>
> ⚠️ **DÉPLOIEMENT : VPS + CLIENT ENSEMBLE.** Le client interroge `/squad/playlists` : sur un
> serveur non redéployé la réponse est vide → aucune carte de mode d'équipe, et le hub reste
> exactement celui d'avant (dégradation propre, mais le mode est invisible).

---

## §8.125 — BATTLE ROYALE : refonte du mode Équipes (parcours, objectif, bonus, TRAHISON)

> **Correctif de parcours + montée en enjeu.** Le §8.124 livrait deux cartes de mode qui menaient à
> un écran générique, sans chrono ni feedback de recherche, avec des objectifs mous (24 territoires
> à trois, 2 continents). Ce chantier en fait **UN mode identifié** — BATTLE ROYALE — avec sa
> destination propre, un objectif public sans pitié, des bonus d'équipe, et une mécanique de
> **trahison secrète**.
>
> ⚠️ L'invariant du §8.124 tient : **`team_id = 0` = SANS ÉQUIPE**, et tout ce qui suit est INERTE
> en FFA. Chaque `can_*` de `battle_royale.py` commence par vérifier `state.team_mode`.

### 1. Registre — les deux formats sur `classic_42`, 30 min, objectif PUBLIC

| id | carte | format | effectif | timer | trahison |
|---|---|---|---|---|---|
| `duo_2v2` | `classic_42` | 2 × 2 | 4 | 30 min | ⛔ |
| `squad_3v3` | `classic_42` | 2 × 3 | 6 | 30 min | ✅ |
| `trio_2v2v2` | `classic_42` | 3 × 2 | 6 | 30 min | ⛔ (playlist DÉSACTIVÉE) |

- **Le Théâtre Atlantique quitte le mode** : l'objectif « 5 continents sur 6 » y était impossible
  (3 continents). Un seul équilibrage à régler, une seule lecture pour le joueur.
- **`match_time_limit_of`** : la playlist IMPOSE 30 min et écrase `settings.MATCH_TIME_LIMIT_S`.
  Hors playlist d'équipe elle rend 0 → réglage global inchangé.
- ⚠️⚠️ Les seuils de `trio_2v2v2` restent **PROVISOIRES** : à 3 camps, 5 continents sur 6 est
  probablement hors d'atteinte (il est réglé à 4). À revalider AVANT activation.

### 2. Objectif — UN seul, IDENTIQUE, et PUBLIC

`teams.objective_of()` rend la spec ; `assign_team_objectives` la donne à TOUTES les équipes.
**5 continents sur 6, ou l'annihilation.** La redaction des objectifs d'équipe est **SUPPRIMÉE**.

**Pourquoi ce revirement** : trois types tirés au hasard et cachés donnaient une course que personne
ne pouvait lire chez l'adversaire — chaque camp avançait à l'aveugle et la fin tombait sans
prévenir. Public, l'objectif devient un compte à rebours partagé : les deux camps savent ce que vise
l'autre ET à combien il en est, et une remontée se lit des deux côtés. Le secret change de porteur —
c'est désormais la TRAHISON qui le détient.

### 3. `battle_royale.py` — module PUR, registre `BR_RULES`

| mécanique | règle | pourquoi |
|---|---|---|
| **RÉANIMATION** | transfert de **100 PV** du réanimateur vers le mort ; plancher 1 PV ; 1 fois par joueur, 1 fois par victime | vrai coût → la permadeath garde son poids. Le ressuscité revient à **100 PV, pas à son max** : ramené *in extremis*, pas guéri |
| **CAISSES** | tous les **50 kills d'équipe**, plafond 4, contenu (150 PV ou 12 unités) **RÉPARTI** entre les vivants | une caisse est une récompense d'ÉQUIPE ; la voir se partager est ce qui la rend collective |
| **REDDITION** | vote **UNANIME** des vivants, à partir du round 3 | protège les coéquipiers qui y croient encore d'un joueur découragé |
| **COUP D'ÉTAT** | tirage **TOUT-OU-RIEN**, résolution **DÉTERMINISTE**, round 4 min. | voir ci-dessous |

- **Réanimation / coup d'État** passent par le pipeline GÉNÉRIQUE (`action_handlers`) → idempotence
  `action_id` gratuite : un double-clic ne réanime pas deux fois et ne déclenche pas deux coups.
- **La reddition est PRÉ-ROUTÉE hors tour** (comme `pact_respond`) : on décide de se rendre en
  regardant l'autre camp écraser le sien, donc presque toujours pendant le tour de quelqu'un
  d'autre. À l'unanimité, l'équipe est ÉLIMINÉE et `_check_victory` constate « dernière équipe
  debout » — aucune seconde voie de victoire n'est recodée.
- **Les caisses sont résolues dans `_handle_attack`**, seul endroit du moteur où un compteur de
  kills bouge. Les accrocher en fin de tour les aurait décalées de l'action qui les mérite.

### 4. TRAHISON — le secret le plus strict du jeu

- **Tirage GLOBAL, tout-ou-rien** : soit CHAQUE équipe a exactement un traître, soit AUCUNE. Un
  tirage indépendant par équipe aurait permis de raisonner sur les probabilités ; ici il n'y a rien
  à calculer, seulement à se méfier. Un joueur SANS ordre ne peut rien déduire sur son équipe,
  seulement qu'il n'est pas LE traître.
- **La victime est désignée dès l'assignation** : le traître vit toute la partie avec un nom en
  tête, et c'est cette cible fixe qui donne son poids à chaque échange avec elle.
- **REDACTION à la source** (`_redact_state_for_player`) : chaque joueur ne reçoit QUE son propre
  ordre ; un non-traître reçoit `{}`, **indiscernable d'une partie sans traître**. Diffuser ne
  serait-ce que le NOMBRE de traîtres viderait le dispositif de tout son sens.
- **Résolution DÉTERMINISTE, aucun dé** (`coup_outcome` : puissance = garnisons + PV de héros,
  strictement supérieur). Ce coup décide la partie d'un geste et coûte la vie à celui qui échoue :
  le laisser au hasard en ferait une loterie qu'on tente sans réfléchir. Déterministe, il devient un
  CALCUL — accumuler l'avantage en silence, sous les yeux de sa victime, et choisir son moment. Et
  la victime peut le VOIR venir en regardant la carte.
- **RÉUSSITE** → `victory_reason = "coup"`, le traître gagne **SEUL**. ⚠️ Il reçoit un `team_id`
  NEUF (son propre camp) : sans ça, `rewards.rank_map` classerait ses ex-coéquipiers avec lui et
  ceux qu'il vient de trahir toucheraient le barème « 1ᵉʳ ». Prime : **100 coins**, 9ᵉ raison du
  livre de comptes (`REASON_TRAITOR_BOUNTY` — le seul gain récompensant un geste contre son propre
  camp mérite sa propre ligne dans le relevé).
- **ÉCHEC** → le traître meurt, sa victime est **restaurée à l'identique**, et ses territoires sont
  RÉPARTIS entre les survivants de son ancienne équipe (`_redistribute_territories`). Les laisser
  en place aurait fait d'un coup raté un non-évènement ; les rendre neutres aurait offert un
  boulevard à l'équipe adverse, qui n'y est pour rien.
- `game_over` gagne **`traitors_reveal`** (redaction levée) et **`traitor_bounty`**. `{}` = partie
  sans traître, et le client doit le DIRE : après 30 minutes de méfiance, le silence serait la pire
  des réponses.

### 5. Client — parcours et mise en scène

- **UNE carte BATTLE ROYALE**, plus grande (210×160), OR, tout à droite et séparée de la rangée
  d'effectifs. Sept choix alignés au même niveau visuel faisaient lire « deux effectifs de plus »
  au lieu de « voici le mode entre amis ». Le format (2v2 / 3v3) descend d'un cran : il se choisit
  DANS l'écran dédié, où l'on voit ce qu'il implique.
- **Écran BATTLE ROYALE** : titre du mode, **règles annoncées avant de s'engager** (30 min,
  objectif public, trahison possible en 3v3 — le découvrir en jeu serait une trahison du joueur),
  et **CHRONO de recherche à la seconde**. C'est le correctif signalé : sans lui, la mise en file
  n'affichait rien de vivant et le joueur ne savait pas si la recherche tournait.
- **`coup_alarm.gd`** : voile rouge pulsant plein écran (|sin|, 2,2 Hz), **sirène SYNTHÉTISÉE**
  (deux tons balayés, saturés, enveloppe 120 ms — le projet n'a pas d'asset d'alarme et en livrer
  un aurait signifié un binaire non versionnable), bandeau « TRAHISON EN COURS », puis verdict.
  NON BLOQUANTE : le joueur doit VOIR ce qui se passe pendant l'alarme.
- **`crate_reveal.gd`** : « unboxing » de 3 s, punch-in en dépassement, montant en 56 px et
  **répartition en COLONNES**.
- ⚠️ **Deux défauts CONSTATÉS EN CAPTURE et corrigés** : (1) le titre de l'alarme était rouge sur
  voile rouge, **illisible au pic du battement** — il est passé en blanc à contour noir, c'est le
  VOILE qui porte la couleur ; (2) la caisse répétait son propre titre en pied de panneau et
  centrait ses lignes de partage, empêchant de vérifier d'un coup d'œil que le partage est ÉGAL.

> **Fichiers.** NOUVEAUX : `api/game/battle_royale.py`, `test_battle_royale.py`,
> `frontend/scripts/game/coup_alarm.gd`, `frontend/scripts/game/crate_reveal.gd`.
> MODIFIÉS : `teams.py`, `objectives.py`, `engine.py`, `state_schemas.py`, `economy.py`,
> `connection_manager.py`, `router.py` · `main_menu.gd`, `squad_screen.gd`, `main.gd`,
> `ui_strings.csv` (+28 clés).
>
> **Validation.** `test_battle_royale.py` **74 ✅** · `test_team_flow.py` **100 ✅** (13 sections,
> dont réanimation / reddition / coup d'État / caisses par le pipeline réel) · `test_teams.py`
> **60 ✅** · `test_objectives_team.py` **52 ✅** · `test_squad_flow.py` **64 ✅** ·
> `test_team_packing.py` **42 ✅** — **0 ❌**. **Suite backend COMPLÈTE verte**, à l'exception de
> `test_missions.py` / `test_simulation.py`, en échec **PRÉ-EXISTANT** (IndexError ; `fastapi`
> absent du poste). Client : `--import` **0 ERROR**, boot headless de 4 scènes **0 ERROR**,
> **captures PNG relues** (menu, écran BR, caisse, alarme, verdict).
>
### 6. Actions au HUD — carte POUVOIR (onglet ACTIONS)

Les trois actions vivent dans la **même carte que les capacités de héros** plutôt que dans un
panneau à part : du point de vue du joueur, « rationner », « réanimer mon coéquipier » et « lancer
le coup d'État » répondent à la même question — *que puis-je faire d'autre que déplacer des
troupes ?*. Les séparer aurait obligé à chercher à deux endroits.

| bouton | visible | grisé si | note |
|---|---|---|---|
| **RÉANIMER — *pseudo*** | mon tour, phases 1-4, un coéquipier mort réanimable | déjà réanimé, ou PV insuffisants | **UN bouton par mort** (au plus deux en 3v3) : deux boutons nommés se lisent plus vite qu'une liste déroulante |
| **COUP D'ÉTAT** | **le traître SEUL**, tant qu'il est vivant | round < 4, hors phase 3, hors mon tour, victime morte, déjà joué | **rouge danger** + **confirmation en deux temps** |
| **SE RENDRE** | tout membre vivant | round < 3, ou déjà voté | sous-titre = compteur de voix (`1/3`) |

- **L'ORDRE SECRET du traître** s'affiche en **rouge** en tête de la carte (extension additive de
  `hud.set_power_card`, qui accepte désormais `{text, color}` en plus d'une chaîne). C'est
  l'information la plus lourde que le jeu confie à un joueur : la laisser en cyan la faisait lire
  comme un compteur de renforts.
- **Confirmation en deux temps du Coup d'État** : le 1ᵉʳ clic ARME (le bouton devient
  « ⚠ CONFIRMER »), le 2ᵉ envoie. L'idempotence serveur protège du double-envoi, pas du clic
  MALHEUREUX — et ici le clic malheureux tue son auteur et clôt la partie. **L'armement ne survit
  pas au changement de tour** (`_coup_armed` remis à false) : une confirmation qui traverserait le
  tour suivant serait un piège.
- Refus traduits par `BR_ERROR_KEYS` (`BR_ERR_*`), aiguillés par `_last_coded_action == "br"` — les
  jeux de codes des capacités, des pactes et du Battle Royale partagent des noms
  (`already_used`, `invalid_target`, `not_your_turn`) et seul le contexte les distingue.

### 7. Alarme de trahison — « on doit voir le plateau à travers »

⚠️ **Contrainte n° 1, et elle a coûté une première version** : un voile rouge PLEIN à 0,40 d'alpha
noyait la carte et transformait l'évènement le plus spectaculaire du jeu en écran de chargement
rouge. Le clignotant vit donc dans une **VIGNETTE de bord** (périphérie saturée, **centre libre**)
plus un voile résiduel quasi nul (0,02 → 0,10) — l'œil lit « alerte » par la périphérie, comme
devant un vrai gyrophare, et le regard reste sur l'action.

**Style « CAUTION / DANGER » assumé** : plaque noire à bordure jaune épaisse, encadrée de deux
**rubans de danger** (diagonales jaune-noir) qui DÉFILENT, titre capitale blanc à contour noir.
Ce n'est pas de la décoration — c'est le vocabulaire visuel universel du danger imminent, et il se
lit sans être lu.

⚠️ Deux pièges payés ici : (1) le défilement des bandes passe par un **décalage dans `_draw()`**,
jamais par `position` — elles vivent dans un `VBoxContainer` qui les repositionne à chaque passe de
layout, l'animation aurait été un **no-op silencieux** ; (2) `set_anchors_preset` est appelé
**APRÈS** `add_child` (piège §8.121 : sur un Control détaché, il double la taille).

> ⚠️ **NON VÉRIFIÉ** : aucune partie Battle Royale réelle jouée de bout en bout (2 humains + bots).

### 8. Correctifs après le premier essai (§8.125 — 2ᵉ passe)

Trois défauts signalés en jouant, tous corrigés et revérifiés en capture :

**a) « Impossible de choisir le 2v2 dans le menu Battle Royale ».** `squad_screen._render()`
réécrivait `_selected_playlist` depuis l'escouade à CHAQUE rendu : le chef cliquait « DUO 2v2 »,
`_on_playlist_selected` posait son choix, le rendu suivant le REMPLAÇAIT par l'ancien format, et le
bouton se ré-allumait sur le précédent. Le clic semblait mort et le format était **figé dès la
création de l'escouade**.

Correctif en deux temps, parce que le bug en cachait un second :
- côté client, **le choix local du chef fait autorité** tant qu'il n'a pas lancé la recherche (un
  MEMBRE, lui, reflète toujours l'escouade — il n'édite rien) ; le rendu est en outre **différé**
  (`call_deferred`), la reconstruction de la rangée libérant le bouton qui émet `pressed` ;
- côté serveur, **nouvelle route `POST /squad/playlist`** (CHEF seul, shape `SquadStateResponse`).
  Sans elle, le format ne partait qu'avec `POST /squad/queue` : **les coéquipiers continuaient de
  lire l'ANCIEN format**, ils attendaient un 3v3 pendant que le chef cherchait un 2v2. Le format est
  une donnée de GROUPE, il doit vivre côté serveur comme le code et les membres. Refusée si
  l'escouade est EN FILE (le matchmaker planifierait sur des tailles périmées) ou si l'escouade ne
  tient pas dans le nouveau format (`full`, dit AVANT la file où le chef peut encore agir).

**b) « Je ne vois pas les membres de mon équipe ».** Exact : le Roster de Guerre listait tout le
monde dans l'ordre du TOUR, qui **alterne les camps par construction**. La seule différence entre un
coéquipier et un ennemi était une nuance de couleur, à comparer de mémoire d'une ligne à l'autre —
illisible à six. Le roster est désormais **GROUPÉ PAR CAMP, le mien en tête**, avec un en-tête au
liseré de la couleur d'équipe (« ▬ VOTRE ÉQUIPE  2/3 » — vivants / total). ⚠️ L'ordre du TOUR est
préservé À L'INTÉRIEUR de chaque camp : il reste l'information n° 1 du jeu.

**c) « L'alarme doit être transparente et plus alarmiste ».** Le voile plein à 0,40 noyait la carte.
Refonte complète (cf. §7 ci-dessus) : voile résiduel 0,01→0,05, **vignette de bord** qui laisse le
centre libre, plaque **CAUTION/DANGER** à rubans diagonaux défilants.
⚠️ Trois pièges payés : le défilement des bandes passe par un décalage **dans `_draw()`** (elles
vivent dans un `VBoxContainer` qui les repositionnerait → no-op silencieux) ; le centrage passe par
un **conteneur**, pas par `set_anchors_preset` (sur un `PanelContainer` dimensionné par son contenu,
les offsets restent périmés et **la plaque sortait par la gauche de l'écran** — constaté en
capture) ; et l'ancrage se fait après `add_child` (§8.121).

> **Validation de la 2ᵉ passe.** `test_squad_flow.py` **77 ✅** (section [7] « changement de
> format » ajoutée : bascule par le chef, persistance vue par le membre, refus membre / playlist
> fermée / escouade trop grande / en file). Suite backend COMPLÈTE verte hors `test_missions.py` et
> `test_simulation.py` (échecs **PRÉ-EXISTANTS**). Client : `--import` **0 ERROR** ; captures relues
> — bascule 2v2 (le bouton s'allume), actions BR dans le HUD **avec de vraies données** (RÉANIMER
> cible bien le coéquipier mort, REDDITION 0/2), alarme par-dessus l'arène (plateau lisible).
>
> ⛔ **NON VÉRIFIÉ VISUELLEMENT** : le groupement par équipe du Roster de Guerre. Le panneau
> latéral n'était pas déployé dans la capture — le code est en place et l'import passe, mais
> personne n'a vu le rendu.

### 9. Ajustements d'ergonomie (§8.125 — 3ᵉ passe)

**a) Bouton BATTLE ROYALE — pictogramme retiré.** La carte tire déjà son autorité de sa taille, de
son or et de sa position ; le symbole y ajoutait du bruit sans rien dire de plus.

**b) Description du mode → INFOBULLE.** Les règles (30 min, objectif public, traître possible en
3v3) vivaient sous le titre : un pavé de trois lignes se lit UNE fois puis devient du bruit
permanent en tête d'écran. Elles passent derrière une pastille **« i »** accolée au titre —
nouveau helper `WarzoneUI.make_info_badge(tooltip, font, diameter)`, réutilisable partout.
⚠️ La lettre « i » et non un glyphe « ⓘ » : les symboles hors ASCII rendent en TOFU dès que la
police de repli change. Le pavé `SQUAD_CODE_HINT` sous le titre est **supprimé** — il décrivait la
création d'escouade, qui n'est plus la voie principale, et envoyait le joueur seul au mauvais bouton.

**c) ⭐ JOINTURE OUVERTE — `POST /squad/quickjoin`.** Le défaut le plus grave signalé : rejoindre
exigeait un CODE, qu'on n'obtient que d'un ami. Un joueur seul n'avait donc qu'une option — créer
son escouade — et attendait dans un groupe d'UNE personne que **personne ne pouvait rejoindre**.
Résultat observé : multiplication de salons d'un membre, pool pulvérisé, impossibilité de jouer.

- Nouvel **annuaire Redis des escouades OUVERTES** par playlist (`mm:squadopen:{playlist}`, SET de
  codes), réaligné à CHAQUE écriture par `_sync_open_index` → il ne peut pas dériver de l'état réel.
- L'algorithme complète **la plus REMPLIE** (puis la plus ancienne à égalité) : on finit un groupe
  prêt à partir plutôt que d'en amorcer un de plus. `created_at` départage de façon déterministe —
  sans lui, deux escouades également remplies se disputaient les arrivants au hasard de l'ordre du
  SET, et aucune ne finissait de se remplir.
- **Si aucune n'existe, on en FONDE une OUVERTE** : le joueur devient le point de ralliement du
  suivant. C'est CE point qui casse la boucle.
- Champ `open` : « CRÉER UNE ESCOUADE » produit une escouade **FERMÉE** (ce bouton veut dire « je
  joue avec MES amis, je leur donne le code » — voir un inconnu débarquer serait une surprise
  désagréable) ; `quickjoin` fonde des escouades OUVERTES.
- ⚠️ `in_queue` est désormais marqué **SUR l'escouade** et plus seulement dérivé du ticket du
  lecteur : sans ce drapeau, un solo pouvait rejoindre un groupe DÉJÀ parti chercher et rester en
  rade. Levé par `squad_dequeue` / `_destroy_squad` UNIQUEMENT — surtout pas par `_dequeue_squad`,
  qui est appelée en plein milieu de `squad_queue` (idempotence du 2ᵉ clic).
- Client : « **REJOINDRE UNE ÉQUIPE** » devient le CTA principal (le cas le plus fréquent), suivi
  d'un séparateur « — OU, POUR JOUER AVEC VOS AMIS — » puis de « CRÉER UNE ESCOUADE ».

**d) Écran BR élargi** : 680×620 → **820×560**. On gagne en LARGEUR (l'air entre les blocs rend
l'écran lisible d'un coup d'œil) sans forcer la HAUTEUR — `custom_minimum_size` est un plancher, et
un plancher trop haut creusait un grand vide sous les boutons.

**e) + f) Deux ONGLETS dans la barre basse** — `HUD_TAB_ORDER` et `HUD_TAB_TEAM`, construits PAR
CODE (ajouter des nœuds à `main.tscn` pour du contenu 100 % dynamique le ferait grossir sans rien
gagner, et les fusions de `.tscn` sont la source n° 1 de corruption du dépôt).

| onglet | contenu | disponible |
|---|---|---|
| **ORDRE** | la rotation complète dans l'ordre de jeu, chacun à SA couleur de plateau, le joueur courant surligné avec « ❯ », et un état en TEXTE (`EN COURS` / `HORS JEU` / `RETIRÉ`) | **tous les modes** — en FFA aussi, savoir qui joue après soi conditionne chaque attaque |
| **ÉQUIPE** | PV et barre de vie de chaque coéquipier, mention `(VOUS)`, et surtout `RÉANIMABLE` / `PERDU` sur les morts | mode équipe seulement |

Le Roster de Guerre portait déjà ces informations, mais il vit dans le panneau LATÉRAL, souvent
replié — alors que le regard du joueur est en permanence sur la barre BASSE, là où il agit. On amène
l'information là où l'œil est déjà, plutôt que d'espérer qu'il aille la chercher.

⚠️ L'état des morts est dit en TEXTE et pas seulement en couleur (même exigence que les motifs
daltoniens du plateau, E10).

⚠️⚠️ **L'onglet ÉQUIPE est créé PARESSEUSEMENT**, surtout pas dans `_ready()` : à ce moment-là aucun
état de partie n'est encore arrivé (il descend par le WS ensuite), donc `GameState.team_mode` vaut
toujours `""` et **l'onglet n'aurait JAMAIS existé, y compris en Battle Royale**. Bug attrapé en
capture — aucune erreur, juste un onglet manquant.

> **Validation de la 3ᵉ passe.** `test_squad_flow.py` **93 ✅** (section [8] « jointure ouverte » :
> 2ᵉ solo qui rejoint le 1ᵉʳ, escouade pleine → nouvelle, groupe d'amis inviolable, escouade en file
> écartée, annuaires séparés par format, idempotence). `FakeRedis` étendu aux SET
> (`sadd`/`srem`/`smembers`). Suite backend COMPLÈTE verte hors `test_missions.py` /
> `test_simulation.py` (échecs **PRÉ-EXISTANTS**). Client : `--import` **0 ERROR**, boot headless de
> 3 scènes **0 ERROR**, **captures relues** (menu sans pictogramme, écran BR élargi avec « i » et
> nouveau CTA, onglets ORDRE et ÉQUIPE peuplés).

### 10. Corrections d'ergonomie (§8.125 — 4ᵉ passe)

**a) Infobulle → PANNEAU MODAL.** La 1ʳᵉ version posait un `tooltip_text` : il ne se déclenchait pas
de façon fiable et — surtout — ne ressemblait EN RIEN au détail des points du Classement, la
référence maison. Le projet a déjà SON vocabulaire pour « je t'explique une règle » : voile noir à
60 % + panneau gunmetal bordé cyan, fermé par un clic N'IMPORTE OÙ
(`leaderboard._build_rules_overlay`). `WarzoneUI.make_info_badge` le reproduit désormais à
l'identique plutôt que d'inventer un second dialecte. Signature :
`make_info_badge(parent_screen, title, body, font, diameter)` — `parent_screen` reçoit le voile,
qui doit couvrir TOUT l'écran et pas seulement la ligne du titre.

**b) ⭐ « TROUVER UNE PARTIE » — file d'attente SOLO, en un clic.** La 3ᵉ passe avait manqué la
cible : `quickjoin` plaçait bien le joueur dans une escouade, mais il lui restait à cliquer
« METTRE EN FILE » — deux manipulations pour quelqu'un qui veut juste jouer.

La bonne réponse était déjà dans le serveur : `POST /squad/queue` **sans escouade** enfile un ticket
SOLO, et `plan_team_bucket` compose les équipes avec les solos en attente (bots à 60 s, comme
partout). Le bouton appelle donc directement cette route — **aucune escouade n'est créée**, aucun
code, aucune salle vide. Le chrono de recherche démarre au clic (bascule d'affichage immédiate, sans
attendre le poll).

⚠️ **`POST /squad/quickjoin` et tout son annuaire Redis (`mm:squadopen:*`, `_sync_open_index`, champs
`open` / `in_queue` sur l'escouade) ont été SUPPRIMÉS** — avec la file solo directe, ils ne servaient
plus rien. Du code mort testé reste du code mort : il aurait fallu le maintenir à chaque évolution du
matchmaking, pour une route que plus aucun écran n'appelait. Section de test correspondante retirée
également ; `FakeRedis` conserve ses SET (inoffensifs, utiles au prochain besoin).

**c) La FICHE JOUEUR ne se déploie plus toute seule.** `hud.set_player_sheet()` se terminait par
`open_player_sheet()` — or cette fonction est appelée à CHAQUE rafraîchissement d'état, donc à chaque
action de n'importe quel joueur : le panneau se rouvrait en boucle sous les doigts de celui qui
venait de le replier. Le déploiement est désormais conditionné à un paramètre `focus`, passé à `true`
par les SEULS gestes volontaires — clic sur un territoire, clic sur une ligne du roster. Un
rafraîchissement ne décide plus de ce que le joueur regarde. Le repli initial
(`_collapse_player_sheet_initially`) est inchangé.

> **Validation de la 4ᵉ passe.** `test_squad_flow.py` **77 ✅** (après retrait de la section
> `quickjoin`). Suite backend COMPLÈTE verte hors `test_missions.py` / `test_simulation.py` (échecs
> **PRÉ-EXISTANTS**). Client : `--import` **0 ERROR**, boot headless de 3 scènes **0 ERROR**,
> captures relues (écran BR avec « TROUVER UNE PARTIE » en tête, panneau modal d'explication ouvert).
>
> ⛔ **NON VÉRIFIÉ** : le non-déploiement de la fiche joueur ne se constate qu'EN JOUANT (il faut un
> rafraîchissement d'état pour reproduire le défaut). Le code est en place et l'import passe.

---

## §8.126 — COMPAGNIES : clans PERSISTANTS, tag, emblème, classement inter-compagnies (volet RÉSEAU)

> **Une maison, pas un groupe de file.** L'ESCOUADE (§8.124-125) est éphémère : Redis, TTL 24 h,
> elle meurt avec la partie. La **COMPAGNIE** est persistante (SQL) : un tag de 4 lettres qui préfixe
> le pseudo PARTOUT, un nom, un emblème, un roster de 20, un chef, et un **classement
> inter-compagnies saisonnier**. C'est l'anti-churn n° 1 du genre.
>
> **Strictement ADDITIF** (règle §1.5) : aucune clé de payload existante n'est renommée ou supprimée,
> aucune règle de jeu n'est modifiée. Le moteur ne connaît des compagnies QUE le champ d'affichage
> `PlayerState.company_tag`.
>
> ⚠️ **FRONTIÈRE ESCOUADE / COMPAGNIE — l'invariant du chantier.** La compagnie **ne se met JAMAIS
> en file**. Elle FABRIQUE des escouades. Aucun endpoint `/company/*` ne touche à un bucket, un
> ticket ou une salle, et le matchmaker ignore jusqu'à l'existence des compagnies.
>
> ⚠️ **AUCUN AGRÉGAT N'EST STOCKÉ.** Score, victoires, division moyenne et rang se recalculent À LA
> LECTURE depuis les RP des membres → une seule source de vérité (aucune divergence possible avec le
> ladder, piège §8.106) et un reset de saison automatique PAR CONSTRUCTION.
>
> ⚠️ **DÉPLOIEMENT : VPS + CLIENT ENSEMBLE.** Sur un serveur non redéployé, `/company/*` répond 404
> et le client dégrade proprement (carte « SANS COMPAGNIE », onglet COMPAGNIES vide) — mais le
> chantier est alors invisible.

### 1. Tables (`models/models.py` — archive `backend/migration_companies.sql`)

Tables NEUVES : créées intégralement par `Base.metadata.create_all` au boot. **Aucune action humaine
sur la prod** (contrairement à `migration_steam_auth.sql`).

| `companies` | type | rôle |
|---|---|---|
| `id` | PK | |
| `tag` | VARCHAR **UNIQUE** | 4 lettres A-Z, **normalisées en MAJUSCULES** par `companies.validate_tag` avant écriture → « alfa » ne peut pas coexister avec « ALFA ». **IMMUABLE** après création. |
| `name` | VARCHAR | 3-24 caractères alphanumériques + espaces. **NON unique** (c'est le tag qui identifie). |
| `emblem_id` | INT (déf. 0) | Index dans le catalogue **CLIENT** (0..23). Aucune image ne transite. |
| `join_code` | VARCHAR **UNIQUE** | Code 5 caractères, MÊME générateur/alphabet que les salons et escouades (`matchmaking.generate_code`). |
| `leader_user_id` | FK users | Toujours AUSSI membre. |
| `created_at` | TIMESTAMP | |

⚠️ **`join_code` est stocké EN CLAIR — déviation ASSUMÉE du brief**, qui prévoyait un
`join_code_hash`. Le hachage suppose un secret qu'on ne relit jamais ; or `GET /company/mine` DOIT
rendre ce code à ses membres pour qu'ils le partagent. Hacher aurait donc imposé de conserver le
clair ailleurs, c'est-à-dire de ne rien protéger tout en le prétendant. Ce n'est pas un identifiant
de connexion : le pire qu'il permette est de rejoindre un clan, et sa défense réelle est
l'anti-bruteforce PARTAGÉ (table `sanctions`, §8.116).

| `company_members` | type | rôle |
|---|---|---|
| `id` | PK | |
| `company_id` | FK companies **NULLABLE** | Renseigné = adhésion ACTIVE ; **NULL = pierre tombale**. |
| `user_id` | FK users **UNIQUE** | L'invariant « UN joueur = UNE compagnie au plus », porté par le SGBD. |
| `joined_at` | TIMESTAMP | Départage la succession automatique du chef. |
| `left_cooldown_until` | TIMESTAMP NULL | Cooldown de réadhésion (24 h), posé au DÉPART. |

⚠️ **UNE SEULE LIGNE PAR JOUEUR, À VIE.** Quitter est un **UPDATE** (`company_id = NULL`), jamais un
DELETE : supprimer la ligne effacerait le cooldown avec elle, et l'anti « tag-hopping » n'aurait tenu
que le temps d'un DELETE.

### 2. Endpoints `/company/*` (convention zéro-4xx §8.112 — shape UNIQUE `CompanyStateResponse`)

Neuf routes rendent la MÊME enveloppe : `{ company: {...} | null, reason?, rules, until_epoch?,
cooldown_s?, banned_until_epoch?, ban_hours?, failed_attempts?, remaining_attempts? }`.
`company: null` n'est PAS une erreur : c'est l'état de départ de tout le monde.

- `POST /company/create {tag, name, emblem_id}` — refus `banned` · `already_member` · `cooldown` ·
  `invalid_tag` · `invalid_name` · `invalid_emblem` · `tag_taken`. **ORDRE STRICT** (du plus
  structurel au plus corrigeable) : vérifier « tag pris » avant « tag mal formé » répondrait
  « disponible » à une saisie de trois lettres. Compagnie + adhésion du chef écrites dans la MÊME
  transaction (`flush` puis `commit`). Le cooldown bloque AUSSI la création — sans quoi on
  contournerait l'anti tag-hopping en fondant une coquille.
- `POST /company/join {code}` — refus `banned` · `already_member` · `cooldown` (+ `until_epoch`) ·
  **`unavailable`**. ⚠️ **AUCUN ORACLE** : format invalide, compagnie inexistante et roster PLEIN
  rendent une réponse **INDISCERNABLE**. Compteur d'échecs (`mm:fail:{uid}`) et escalade des bans
  (`sanctions`, kind `search_abuse`) **PARTAGÉS** avec la recherche de salons — pas un second
  circuit. Un succès purge le compteur.
- `POST /company/leave` — trois issues : membre simple → départ ; **chef avec des restants →
  SUCCESSION AUTOMATIQUE au plus ancien** (`companies.next_leader`) ; dernier membre → compagnie
  SUPPRIMÉE et tag libéré. Contrairement à l'escouade, on ne DISSOUT pas au départ du chef : punir
  19 personnes parce que le chef arrête de jouer serait absurde.
- `POST /company/kick {user_id}` (chef) — l'exclu reçoit le MÊME cooldown qu'un départ volontaire.
  Le chef ne peut pas s'exclure lui-même (`not_member`).
- `POST /company/transfer {user_id}` (chef) — l'ancien chef RESTE membre.
- `POST /company/regen_code` · `POST /company/rename {name}` · `POST /company/emblem {emblem_id}`
  (chef). ⚠️ **Aucune route ne change le TAG** : il est immuable.
- `GET /company/mine` — fiche + `rules` + cooldown en cours s'il y en a un.
- `GET /company/check_tag?tag=XXXX` → `{tag, available, reason}` — `reason` distingue `invalid_tag`
  de `tag_taken` (deux corrections différentes pour le joueur). **Ne consomme AUCUN quota** : un tag
  est une donnée publique, contrairement à un code.
- `GET /company/{tag}` (authentifié, doctrine §8.107) — fiche **PUBLIQUE**, routée par TAG et non par
  id (aucun identifiant séquentiel énumérable). Compagnie dissoute entre le clic et la réponse →
  `{company: null, reason: "unavailable"}`, pas un 404.

**Fiche (`CompanyResponse`)** : `{tag, name, emblem_id, leader, members[], member_count,
season_score, season_wins, avg_division, avg_division_label, rank}` — plus, **MEMBRES SEULEMENT** :
`join_code`, `is_leader`.
**Membre** : `{user_id, name, division, division_label, season_rp, is_leader, joined_at}`.

⚠️ **FRONTIÈRE DE CONFIDENTIALITÉ** (portée en UN seul endroit, `_company_payload(public=True)`) —
sur la vue publique : `join_code` **ABSENT**, `user_id` à 0, `season_rp` à 0. Les divisions, elles,
restent publiques (le Classement les montre déjà). Assertion de non-fuite dédiée dans
`test_company_flow.py`.

### 3. `GET /leaderboard/companies?limit=50`

`{entries: [{rank, tag, name, emblem_id, season_score, member_count}], mine: {...}|null,
season: {id, ends_at}}`. `mine` suit le patron « VOTRE RANG » du ladder (présent même hors page).

- **Score de saison** = somme des **`score_top_n` (10) meilleurs RP** du roster — surtout pas la
  somme des 20 : recruter n'importe qui serait alors strictement optimal, et 20 débutants
  battraient mécaniquement 8 vétérans. RP lus **BRUTS** (`User.season_points`), exactement comme le
  tri du ladder.
- **SOURCE UNIQUE** : `company._standings` sert le classement ET la fiche `/company/mine` ET la page
  publique. C'est ce qui interdit structurellement qu'une compagnie s'annonce « #3 » sur son écran
  et apparaisse 5ᵉ dans la liste (leçon §8.106 — contre-épreuve `test_rank_never_diverges`).
- **Cache mémoire 60 s** (dict de processus). Purgé immédiatement à chaque mutation d'effectif
  (`invalidate_standings`) : voir « 1/20 » après avoir accueilli quelqu'un passerait pour un bug.
- **COÛT, dit franchement** : trois requêtes SANS join (compagnies, adhésions, joueurs concernés)
  puis le top-N en Python — O(nombre total d'adhésions). Le jour où cela pèsera, la bonne réponse
  sera une fenêtre SQL (`ROW_NUMBER() OVER (PARTITION BY company_id …)`), **pas** un agrégat stocké
  qui rouvrirait la porte à la divergence.

### 4. Champs ADDITIFS ailleurs

- **`PlayerState.company_tag`** (défaut `""`) — champ **PUBLIC** diffusé en partie, posé UNE FOIS par
  `launch_room` depuis la base (`company_tags_for` : 2 requêtes pour toute la salle, jamais une par
  joueur sur le chemin critique). Toujours `""` pour un bot. **C'est la SEULE donnée de compagnie qui
  entre en partie** : ni nom, ni emblème, ni score. Jamais relu ensuite — quitter sa compagnie en
  pleine partie ne change pas l'affichage du match en cours (l'identité d'un match est celle du coup
  d'envoi). Défaut `""` → rétro-compat Redis d'une partie en cours pendant le redéploiement.
- **`company: {tag, name, emblem_id} | null`** dans `GET /profile/stats` **ET** le profil PUBLIC
  (`PublicProfileResponse`). Volontairement pauvre : y mettre le score créerait une DEUXIÈME source.
  L'ajout à la liste blanche publique est DÉLIBÉRÉ (l'appartenance est publique par construction —
  le tag préfixe déjà le pseudo jusque dans le kill feed d'un inconnu) et acté dans
  `test_profile_data.py`.

### 5. Module PUR `api/game/companies.py`

`COMPANY_RULES` = **SOURCE UNIQUE** des plafonds (`roster_cap 20`, `tag_len 4`, `name_min/max 3/24`,
`score_top_n 10`, `rejoin_cooldown_h 24`, `emblem_count 24`), servi tel quel au client via `rules` —
le client n'en code AUCUNE valeur en dur. Fonctions : `validate_tag` / `validate_name` /
`validate_emblem` (charset strict, normalisation majuscules), `season_score`, `avg_division`
(délègue à `seasons.rank_info` — jamais de table de seuils dupliquée), `next_leader`,
`cooldown_until` / `cooldown_active` / `cooldown_remaining_s`, `roster_has_room`, `public_rules`.
Zéro I/O ; seul import : `seasons` (PUR).

### 6. Hors périmètre (v1 assumée)

Guerres de clans · chat de compagnie · trésorerie · récompenses de compagnie · candidatures /
annuaire public · rôles intermédiaires · **filtre de contenu des noms** (backlog modération connu :
la v1 borne la FORME, pas le propos) · historique inter-saisons.

⛔ **RESTE À FAIRE DOCUMENTÉ — push « INVITER LA COMPAGNIE ».** Le brief prévoyait de pousser le code
d'escouade aux membres EN LIGNE. **Vérification faite : le serveur n'a NI canal de notification de
hub** (le seul WebSocket du jeu est `/ws/{room_id}/{player_id}` — il n'existe qu'en partie) **NI
notion de présence hors partie** (rien ne suit qui est connecté au QG). Les inventer aurait été une
infrastructure entière greffée sur un bouton. La v1 livre donc la version AFFICHAGE (cf. §8.126 de
`FRONTEND_INTERFACES.md`), et le champ `online` des membres **n'existe pas** dans les payloads
ci-dessus.

> **Validation.** `test_companies.py` **94 ✅ / 0 ❌** (module PUR : validation exhaustive, collisions
> de casse, top-10 exact sur rosters de 3/10/20, division moyenne via `seasons.rank_info`, succession,
> cooldown). `test_company_flow.py` **136 ✅ / 0 ❌** (endpoints sur faux ORM enforçant les contraintes
> UNIQUE : cycle création→adhésion→exclusion→transfert→dissolution, sanctions partagées, **non-fuite
> du code en public**, **absence d'oracle**, **non-divergence des rangs**, cache 60 s). Non-régression :
> `test_ladder_payload` 32 ✅, `test_profile_data` 85 ✅, `test_squad_flow` 77 ✅, `test_search_sanctions`
> 23 ✅, `test_private_codes` 33 ✅, `test_teams` 60 ✅, `test_team_flow` 100 ✅. **Suite backend
> COMPLÈTE verte hors `test_missions.py` / `test_simulation.py` (échecs PRÉ-EXISTANTS).**

---

## §8.126.1 — COMPAGNIES : PRÉSENCE (« qui est en ligne ») + journal d'activité (volet RÉSEAU)

> **Ce que le §8.126 laissait ouvert.** Il documentait deux manques comme reste-à-faire : le serveur
> ne savait **pas qui était connecté** (le seul WebSocket du jeu, `/ws/{room_id}/{player_id}`,
> n'existe qu'en partie) et n'avait **aucune matière à notification**. Une compagnie dont on ne voit
> ni qui est disponible ni ce qu'on a manqué ne sert à rien : c'est pourtant l'écran qu'on ouvre
> pour savoir avec qui jouer. Ce complément livre les deux — **sans ajouter le moindre WebSocket**.
>
> **Strictement ADDITIF** (règle §1.5). ⚠️ **VPS + CLIENT ENSEMBLE** : sur un serveur non redéployé,
> `/company/badge` répond 404 → la pastille reste muette et tous les membres s'affichent « hors
> ligne ». Dégradation propre.

### 1. PRÉSENCE — deux signaux, parce qu'un seul mentirait

Module PUR `api/game/presence.py` : `should_touch` · `is_online` · `status_of`.

| signal | source | couvre | ne couvre pas |
|---|---|---|---|
| **au QG** | `users.last_seen_at`, rafraîchi par `auth.get_current_user` | tout le hub | les joueurs EN PARTIE (plus aucune requête REST) |
| **en partie** | registre MÉMOIRE du `ConnectionManager` | les joueurs en match | les joueurs au hub |

- `PRESENCE_WINDOW_S = 120` (en ligne si vu depuis moins de 2 min) · `TOUCH_THROTTLE_S = 60`.
  ⚠️ **La fenêtre est DÉLIBÉRÉMENT plus large que le throttle** : à valeurs égales, un joueur bien
  présent clignoterait entre deux rafraîchissements.
- ⚠️ **`status_of` teste « en partie » EN PREMIER.** Un joueur en match ne fait plus une seule
  requête REST : son `last_seen_at` vieillit pendant qu'il joue, et l'ordre inverse l'aurait
  déclaré hors ligne au bout de deux minutes de partie — au pire moment.
- `users.last_seen_at` : colonne ADDITIVE **nullable** → auto-migrée au boot. NULL = jamais vu =
  **hors ligne**, jamais une supposition optimiste.
- `_touch_presence` **ne lève JAMAIS** : c'est une dépendance d'AUTHENTIFICATION, une panne
  d'écriture ne doit pas rendre le jeu entier inaccessible. Pire effet : un joueur affiché absent.
- ⚠️ Le registre WS est un état de **PROCESSUS** (contrainte de worker unique déjà assumée par le
  ConnectionManager §8.31 et le matchmaker §8.116). Limite connue, pas régression silencieuse.

**Exposition** : `CompanyMemberEntry.status` ∈ `"offline"` | `"online"` | `"in_game"` — une CHAÎNE
(trois états) et non un booléen, et **aucun texte affichable** (règle R4). `CompanyResponse.
online_count` compte les présents. **Figés à `offline` / absents sur la vue PUBLIQUE** : les
habitudes de connexion des membres d'un clan tiers ne regardent pas un visiteur.

### 2. JOURNAL D'ACTIVITÉ — la matière des notifications

Table `company_events {id, company_id FK, kind, actor_name, target_name, created_at}`.
`kind` ∈ `created` · `joined` · `left` · `kicked` · `transferred` · `renamed`.

- Les pseudos sont **SNAPSHOTÉS** (pas de FK) : la trace d'une exclusion doit survivre au compte
  exclu, et une jointure sur un compte disparu rendrait la ligne illisible.
- **Croissance bornée** : purge PARESSEUSE à l'écriture (`EVENT_KEEP_DAYS = 30`, aucun cron — même
  discipline que le reset de saison). La dissolution d'une compagnie emporte son journal.
- `company_members.events_seen_at` = **accusé de lecture PAR MEMBRE** ; non-lus =
  `created_at > events_seen_at`. Posé à `now` à l'adhésion (sinon un arrivant hériterait de tout
  l'historique en non lu) ; NULL (ligne pré-migration) = **tout lu**, jamais « tout neuf ».
- ⚠️ **`_log_event(..., at=now)` partage l'INSTANT LOGIQUE du handler** avec l'accusé de lecture
  posé dans la même transaction. Sans ce partage, le fondateur serait notifié de la création de SA
  PROPRE compagnie et chaque arrivant de sa propre arrivée — et le comportement aurait **différé
  entre le poste de dev et la prod** : `datetime.utcnow()` rend plusieurs appels consécutifs
  IDENTIQUES sous Windows, distincts sous Linux.

### 3. Endpoints ADDITIFS

- `GET /company/badge` → `{company: bool, online: int, unread: int}`. Route **volontairement
  minuscule** : appelée par la barre de navigation, donc sur TOUS les écrans du hub, à chaque
  changement d'écran. Ni roster, ni journal, ni score. ⚠️ `online` **EXCLUT l'appelant** — se
  compter soi-même afficherait « 1 » en permanence à un joueur seul, l'exact contraire du signal
  « quelqu'un t'attend ».
- `POST /company/seen` → `{seen: true}`. Accusé de lecture, appelé à l'OUVERTURE de l'écran.
  Réponse minimale : le client vient de recevoir la fiche complète.
- `GET /company/mine` s'enrichit de `online_count`, `events[]` (`{kind, actor, target, at}`, 20 max,
  du plus récent au plus ancien) et `unread_events` — **membres uniquement**.

⚠️ **ORDRE DE DÉCLARATION** : `/badge` et `/seen` sont déclarés AVANT `/{tag}`. `seen` fait quatre
lettres et matcherait le motif de la route paramétrée — c'est l'ordre (et la méthode POST) qui
tranche, comme pour `/mine`.

> **Validation.** `test_company_flow.py` **178 ✅ / 0 ❌** (+42) : trois états de présence dont
> « EN PARTIE prime sur un `last_seen` périmé », vue publique muette, throttle et fenêtre du module
> pur, journal (6 types), non-lus **par membre** avec preuve d'indépendance des accusés, pastille
> qui ne se compte pas soi-même, purge du journal à la dissolution. Suite backend COMPLÈTE verte
> hors `test_missions.py` / `test_simulation.py` (**PRÉ-EXISTANTS**).

---

## §8.129 — TUTORIEL & PREMIÈRE OPÉRATION (FTUE) : volet RÉSEAU

> Volet RÈGLES/CONTENU et rendu client : **§8.129 de [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md).**
> Le backend de ce chantier est **minuscule et strictement ADDITIF** (§1.5) : **une colonne, deux
> routes, une raison de ledger**. Rien d'autre. C'est une décision, pas une économie de moyens — la
> PREMIÈRE OPÉRATION est une **partie NORMALE** (salon privé + LANCER AVEC BOTS, §8.116, API
> inchangée), le moteur ne sait même pas qu'un didacticiel est en cours.

### 1. `users.tutorial_done` — le drapeau de briefing

| Colonne | Type | Défaut | Migration |
|---|---|---|---|
| `users.tutorial_done` | `BOOLEAN NOT NULL` | `FALSE` | **AUTO** (`sync_missing_columns`, elle porte un `server_default`) — archive de parité `migration_tutorial.sql`, **aucune action humaine sur la prod** |

- **SERVEUR et non local**, à dessein : la vérité suit le **COMPTE**, pas la machine. Un joueur qui
  change de PC ne doit pas revoir un didacticiel déjà fait.
- **Impossible à DÉDUIRE** de `stats_parties_jouees == 0` : on peut avoir quitté sa première partie
  sans avoir rien vu du jeu. D'où un drapeau explicite plutôt qu'une heuristique.
- Les comptes EXISTANTS passent à `FALSE` et se verront donc proposer la Première Opération **une**
  fois. Assumé : personne n'a jamais eu la moindre explication, et 150 ¢ n'est pas une somme.

### 2. `GET /auth/me` — champ additif

`UserResponse` gagne **`tutorial_done: bool`** (défaut `false`, validateur `_tutorial_not_null`
identique à celui de `coins`). Aucune clé existante ne bouge.

⚠️ **Additif dans les DEUX sens.** Un serveur ANTÉRIEUR n'émet pas la clé, et un client qui lirait
`false` par défaut proposerait le briefing à **toute la population, vétérans compris**. Le client
porte donc un second drapeau, `AuthManager.tutorial_done_known` : tant que la clé n'a pas été
RÉELLEMENT reçue, le QG **se tait**.

### 3. `POST /profile/tutorial/complete` et `POST /profile/tutorial/skip`

Deux routes authentifiées, sans corps, **même réponse** :

```json
{ "tutorial_done": true, "already": false, "coins_awarded": 150, "coins": 1150 }
```

| Route | Drapeau | Prime | Quand |
|---|---|---|---|
| `/profile/tutorial/complete` | posé | **+150 ¢** (`economy.TUTORIAL_REWARD_COINS`) | Rapport Post-Op de la partie guidée, **victoire OU défaite** — finir suffit |
| `/profile/tutorial/skip` | posé | **aucune** | « JE CONNAIS LA GUERRE » au QG, ou « PASSER LE BRIEFING » en cours de partie |

- **Convention zéro-4xx nominal (§8.112)** : rappeler une route déjà soldée n'est pas une erreur du
  client (double-clic, reprise de session, retour arrière) → **200** + `already: true`,
  `coins_awarded: 0`.
- **IDEMPOTENCE** — les deux routes partagent `_settle_tutorial()`, **seul point d'écriture du
  drapeau du dépôt** : il est LU avant d'être écrit, et un compte déjà soldé ressort sans un seul
  mouvement de ledger. Conséquence voulue et testée : **`skip` PUIS `complete` ne crédite RIEN**.
  L'ordre des clics ne fabrique pas de coins ; qui a dit « je connais la guerre » a renoncé à la
  prime. Le cas inverse est protégé par la même lecture.
- **Un seul `commit`** pour le drapeau ET le mouvement : un crash entre les deux laisserait soit un
  compte payé qu'on repaierait, soit un compte soldé jamais payé.
- La prime passe par `economy.record_coins` — **UNIQUE point de mutation de `User.coins`** (§8.106) ;
  `user.coins` n'est jamais touché à la main, sinon le relevé FINANCES mentirait.

### 4. `tutorial` — 10ᵉ raison canonique du livre de comptes

`economy.REASON_TUTORIAL = "tutorial"`, ajoutée à `ALL_REASONS` **entre `mission_claim` et
`observer_bet`** (c'est un GAIN, il se lit avant les dépenses). Le client en dérive sa clé i18n
`PROFILE_FIN_SRC_TUTORIAL` comme pour les neuf autres ; une raison inconnue d'un client ancien
retombe proprement sur un libellé muet.

Montant : **`TUTORIAL_REWARD_COINS = 150`**, source UNIQUE — ni l'endpoint ni le client ne
l'écrivent en dur (le client affiche le `coins_awarded` que la route lui renvoie).

### 5. Ce que le backend NE fait PAS

- **Aucune route de matchmaking neuve.** La partie guidée est un `POST /private/rooms` +
  `POST /private/rooms/start` ordinaires (§8.116). Le client enchaîne les deux sans montrer l'écran
  salon ; côté serveur, c'est une partie privée comme une autre.
- **Aucune mémoire serveur de la progression du briefing.** Les 13 étapes sont **DÉDUITES** de
  l'état de partie côté client (phase, tour, compteurs) — c'est ce qui les rend tolérantes à une
  reconnexion sans ajouter un octet au contrat.
- **Aucune persistance des bulles contextuelles** : elles vivent dans `user://tutorial_hints.json`
  (local). Un aller-retour réseau par bulle aurait coûté plus cher que le service rendu.

> **Fichiers.** NOUVEAUX : `backend/migration_tutorial.sql`, `backend/test_tutorial.py`.
> MODIFIÉS : `models/models.py` (1 colonne), `models/schemas.py` (1 champ + 1 validateur),
> `api/game/economy.py` (1 raison + 1 constante), `api/v1/endpoints/profile.py` (2 routes + le
> helper partagé), `test_economy.py` (compteur de raisons 9 → 10).
>
> **Validation.** `test_tutorial.py` **48 ✅ / 0 ❌** (dont les trois tests porteurs : crédit UNIQUE,
> `skip`→`complete` sans prime, cohérence `balance_after`). Non-régression : `test_economy.py`
> **82 ✅**, `test_profile_data.py` **85 ✅**, `test_pacts.py` **113 ✅**, `test_teams.py` **60 ✅**,
> `test_battle_royale.py` **74 ✅**, `test_hero_abilities.py` **91 ✅**, `test_companies.py` **94 ✅**,
> `test_team_flow.py` **100 ✅**, `test_company_flow.py` **178 ✅** — **0 ❌**.
> `test_missions.py` / `test_simulation.py` restent en échec **PRÉ-EXISTANT** (`fastapi` absent du
> poste).
>
> ⚠️ **VPS + client ENSEMBLE** : sans le serveur à jour, `/auth/me` n'émet pas `tutorial_done` et le
> client se tait (dégradation propre, mais le chantier est alors invisible).

---

## §8.131 — FINITIONS PRÉ-PLAYTEST : réglages BR diffusés · invitation de compagnie (POLL)

> **2 août 2026** · Backend **strictement additif** — aucune règle de jeu modifiée, aucune migration.
> ⚠️ **VPS + client ENSEMBLE** pour l'invitation ; le reste dégrade proprement sans redéploiement.

### 1. `battle_royale.public_rules()` — les réglages descendent au client

Le bloc d'état `battle_royale` gagne une clé **`rules`** (champ ADDITIF), servie depuis le registre
`BR_RULES` par la fonction PURE `public_rules()` :

```json
"battle_royale": {
  "revives_done": {}, "revived": [], "crates": {}, "surrender": {}, "coup_used": [],
  "rules": {"revive_hp_cost": 100, "revive_min_remaining_hp": 1, "surrender_min_round": 3,
            "coup_min_round": 4, "crate_kill_step": 50, "crate_max_per_team": 4}
}
```

**Pourquoi** : le client recopiait ces six nombres en dur pour ANNONCER un coût (« vous tomberez à
N PV ») et anticiper ses grisages. Un rééquilibrage serveur aurait donc fait **mentir l'interface** —
et une promesse fausse est pire qu'un refus, parce que le joueur a déjà décidé quand il découvre
l'écart. Le client garde ses constantes en **REPLI** (serveur ancien / partie née avant le champ) :
sans `rules`, le comportement est exactement celui d'avant.

- ⚠️ **`traitor_chance` n'est PAS diffusée.** La publier permettrait de calculer la probabilité
  qu'une partie porte des traîtres, ce qui viderait le tirage tout-ou-rien de son sens (§8.125 §4) :
  toute la mécanique tient à ce qu'il n'y ait **rien à calculer**, seulement à se méfier.
- `GameEngine._br()` **RÉÉCRIT** `rules` à chaque passage (et ne se contente pas de le créer) : une
  partie née avant le champ le gagne dès sa première action BR, et un rééquilibrage déployé en cours
  de partie ne laisse jamais un ancien coût en place.

### 2. `POST /company/invite` + champ `invite` sur `GET /company/badge`

**La version POLL recommandée au §5 du rapport COMPAGNIES**, livrée telle quelle.

| | |
|---|---|
| **Dépôt** | `POST /company/invite` → clé Redis `company:invite:{company_id}`, **TTL 300 s** |
| **Charge** | `{squad_code, playlist, from_name, from_id}` |
| **Lecture** | `GET /company/badge` gagne `invite: {squad_code, playlist, from_name}` ou `{}` |
| **Refus** | convention zéro-4xx (§8.112) : `{invited: false, reason: no_company\|no_squad\|not_leader}` |

- **Pas de push WebSocket, et c'est délibéré** : « apparaître » suppose que le serveur parle de sa
  propre initiative, donc un canal permanent vers un joueur qui n'est dans AUCUNE partie. Ce canal
  n'existe pas (`/ws/{room_id}/{player_id}` refuse un non-membre en `4003` ; côté client
  `leave_room()` détruit puis recrée le socket — **un socket = un match**). L'ouvrir voudrait dire un
  second cycle de vie complet (auth, gate de version, reconnexion, nettoyage), un second registre de
  connexions et **un socket permanent par joueur** sur une stack mono-worker. Le poll coûte
  1 requête / 15 s / joueur et réutilise TOUT l'existant (présence, badge, nav, `squad_join`).
- **UNE seule invitation vivante par compagnie** (la clé est écrasée) : deux chefs qui invitent coup
  sur coup ne doivent pas empiler deux toasts contradictoires.
- **Trois filtres de lecture**, aussi importants que le TTL : l'**auteur** ne reçoit pas sa propre
  invitation ; un membre **DÉJÀ dans l'escouade** non plus (sinon le toast reviendrait toutes les
  15 s chez quelqu'un qui a accepté) ; une **escouade dissoute** rend l'invitation muette.
- Une clé illisible ≡ **pas d'invitation** : cette route est appelée depuis TOUS les écrans du hub,
  elle ne doit jamais lever.
- ⚠️ `GET /company/badge` devient **`async`** et prend `redis` (il lit le dépôt). Champ `invite`
  toujours présent, `{}` par défaut — un client antérieur ignore la clé et se comporte comme avant.
- ⚠️ `company.py` importe `squad.py` **PARESSEUSEMENT** (`_squad_reads()`), jamais au chargement :
  `squad.py` référence `models.schemas.Squad*` à l'import, et les suites qui testent les endpoints de
  compagnie sur faux ORM ne stubbent que les schémas `Company*`. Sens de dépendance :
  `company → squad`, **jamais** l'inverse.

> **Validation.** `test_company_flow.py` **189 ✅ / 0 ❌** (dont 11 contre-épreuves d'invitation :
> TTL 5 min, refus `not_leader`, non-retour à l'auteur, acceptée → ne réapparaît pas, escouade
> dissoute, expiration, clé corrompue). **Suite backend COMPLÈTE : 65 suites vertes, 0 rouge** —
> `test_missions.py` et `test_simulation.py` **RESSUSCITÉES** (voir le rapport de session), et
> `test_observer_bets.py` réparé (compteur de raisons du ledger périmé depuis §8.129).

---

## §8.132 — ÉVÉNEMENTS MUTATEURS : calendrier data-driven, mutateurs à la source de lecture

**Ce que c'est.** Des **fenêtres datées** (du vendredi 18:00 UTC au lundi 00:00 UTC exclu) pendant
lesquelles les parties **CASUAL FFA** se jouent avec des règles modifiées. Un événement par mois,
annoncé au QG, **sans une ligne de code** : on édite un registre. Quatre événements de lancement —
`storm` (TEMPÊTE ERRATIQUE), `blitz` (GUERRE ÉCLAIR), `proliferation` (PROLIFÉRATION),
`harvest` (MOISSON).

**Aucun cron.** Activation **LAZY**, calcul PUR `events.active_event(now)` refait à la création de
salle et à la lecture de l'endpoint — exactement le patron des saisons (§8.67) et de la rotation
hebdomadaire (§8.66). Rien n'est planifié, rien n'est stocké.

### Nouveaux champs d'ÉTAT (additifs §1.5)

| Champ | Type | Sens |
|---|---|---|
| `GameState.event_id` | `str` (défaut `""`) | id de l'événement sous lequel la partie a été créée. `""` = partie ordinaire. **PUBLIC**. |
| `GameState.event_rules` | `dict` (défaut `{}`) | **SNAPSHOT** des valeurs mutées, photographié à la création. **PUBLIC**. |

`event_rules` est un **dict PLAT de scalaires** — aucune clé entière, aucun sous-dict (les clés de
dict reviennent en `str` de Redis : « piège JSON float » §5). Clés :

```
event_id · name_key · desc_key
zone_growth_per_player_turn (int) · zone_growth_cap_multiplier (int) · zone_teleport_per_player_turn (bool)
phase_time_multiplier (float) · card_value_multiplier (int) · reinforcement_multiplier (float)
xp_multiplier (int) · hero_coins_multiplier (int)
```

> ⚠️⚠️ **PARAMÈTRES FIGÉS À LA CRÉATION.** La salle photographie les valeurs dans SON état ; le
> moteur ne relit **jamais** le calendrier, seulement `events.rules_of(state)`. Un événement qui
> commence ou finit **pendant** une partie ne la change pas. Aucune exception. C'est la
> contre-épreuve centrale de `test_events_flow.py` (vider `EVENTS_CALENDAR` en pleine partie ne
> modifie rien, dans les deux sens).

### Endpoint — `GET /squad/playlists` ÉTENDU (additif)

Le point de **configuration publique** existant (registre des playlists §8.124) porte désormais
trois clés de plus. Aucun second endpoint : le hub va chercher sa configuration de jeu à **un seul
endroit**.

```jsonc
{
  "playlists": { … },                                  // inchangé
  "active_event": { "id", "name_key", "desc_key", "scope",
                    "starts_at_epoch", "ends_at_epoch", "rules" } | null,
  "next_event":   { …même forme… } | null,
  "upcoming_events": [ …3 prochaines fenêtres NON TERMINÉES, l'active en tête… ]
}
```

- **Epochs ENTIERS**, aucun texte affichable : uniquement des clés i18n (le serveur ne parle
  aucune langue).
- `rules` = le snapshot ci-dessus → le **client n'a AUCUNE constante d'événement en dur** et le
  modal de règles énumère des effets exacts. Patron `battle_royale.public_rules()` (§8.131).
- **Cache processus 60 s** : l'endpoint est appelé par chaque écran du hub, et le cache borne aussi
  la dérive d'affichage (tous les écrans annoncent le même rebours dans la même minute).

### `game_over` (additif)

- Bloc **PUBLIC** : `event_id` (str) et `event_rules` (dict) — l'affiche du match, identique pour
  tous (piège n° 9 : tout champ nouveau doit être classé public ou privé).
- Bloc **PRIVÉ** `match_rewards[<pid>]` : `event_id`, `event_xp_multiplier`,
  `event_hero_coins_multiplier`, et dans `xp_inputs` le surplus réel `xp_event_bonus`. Servis à
  **tous** les joueurs, y compris bots et comptes introuvables (forme uniforme).

### Refus

**AUCUN nouveau.** Un événement ne se refuse pas : il s'applique, ou pas.

### Périmètre — ce qui n'est JAMAIS muté

`events.applies_to(event, is_ranked, is_private, team_mode)` décide, **sur les paramètres du bucket
d'origine** passés à `launch_room` — jamais sur une heuristique lue plus tard dans l'état :

| Contexte | Muté ? | Pourquoi |
|---|---|---|
| File publique casual FFA | ✅ | le périmètre v1 |
| Salon privé | ✅ | même public casual (drapeau registre `applies_to_private`) |
| **CLASSÉE** | ⛔ **jamais** | les RP de deux week-ends doivent vouloir dire la même chose |
| **BATTLE ROYALE / playlist d'équipe** | ⛔ pas en v1 | champ `scope` prévu au registre pour plus tard |

> **Validation.** `test_events.py` **64 ✅ / 0 ❌** (bornes de fenêtre à la seconde, mois à 5
> vendredis, calendrier vide, **sabotage** de la garde de non-chevauchement, snapshot des 4
> événements, périmètre). `test_events_flow.py` **53 ✅ / 0 ❌** (périmètre par le VRAI
> `launch_room`, zone sous TEMPÊTE sur la boucle de tour réelle, **paramètres figés**, budgets
> exacts, ordre des multiplicateurs de renforts et de gains, 1 000 tirages de cartes, ledger).
> **Suite backend COMPLÈTE : 67 suites vertes, 0 rouge.**

---

## §8.134 — HUB ÉVÉNEMENTS V2 : types, priorités, personnage gratuit (ADDITIF strict §1.5)

**Registre `api/game/events.py`.** Chaque événement porte désormais un **`type`** :
`match` (les 4 mutateurs §8.132), `character` (les personnages), `bonus` (tournois et offres —
type et onglet existants, **aucun événement bonus au lancement**). La **`priority`** (bonus 30 >
match 20 > character 10) est **DÉRIVÉE du type** et jamais recopiée dans les entrées : un
`priority` écrit à la main finit toujours par contredire son propre type. Un id inconnu ou une
entrée sans `type` répond `match`/20 — le comportement d'avant ce chantier.

**Événement PERMANENT `free_character`** (`type: "character"`). Il n'est dans AUCUNE entrée
d'`EVENTS_CALENDAR` : sa fenêtre est **calculée** par `events.character_window(now)` sur la semaine
ISO de `rotation.py` (lundi 04:00 UTC → lundi suivant, borne haute **exclusive**). La constante
d'heure de bascule est **importée** de `missions_progress` — pas de 2ᵉ convention (piège transverse
n° 7). Contre-épreuve figée : `character_window(t)[1] == rotation.weekly_resets_at(t)` sur 5
instants, dont 03:59:59 et 04:00:00 pile.

**Garde de non-chevauchement élargie.** Le chevauchement **inter-types** est désormais AUTORISÉ —
c'est le cœur du hub : le personnage gratuit tourne pendant les mutateurs du week-end, et un
tournoi `bonus` doit pouvoir se superposer à une TEMPÊTE. Ce qui reste interdit à l'import, c'est
**deux `match` simultanés** (`active_event()` n'en rend qu'un ; le choix dépendrait de l'ordre
d'itération d'un dict).

**`active_event()` est INCHANGÉ pour le moteur** : il ne rend que du `match`. Un `bonus` ou le
personnage gratuit ne doivent jamais atteindre `snapshot_rules`. `applies_to()` porte la même
ceinture (`type != match` → False). Les autres types se lisent par `active_events()`.

### `GET /squad/playlists` — bloc `events_v2`

Route **toujours PUBLIQUE**, mais **enrichie si connecté** (`get_current_user_optional`, patron du
bloc `me` du classement §9.2). Aucun 401 possible : c'est de la configuration de jeu, lisible avant
l'ouverture du WebSocket. Les clés v1 (`active_event`, `next_event`, `upcoming_events`) **restent
servies à l'identique** — un client §8.132 ne voit même pas ce bloc.

```jsonc
"events_v2": {
  "active":   [ {id, type, priority, name_key, desc_key, scope,
                 starts_at_epoch, ends_at_epoch, rules} ],   // tous types, tri priorité ↓ puis fin ↑
  "upcoming": [ … 3 prochaines fenêtres match/bonus … ],
  "featured_id": "storm",                                     // règle de VEDETTE calculée SERVEUR
  "character": {                                              // part PERSONNELLE, HORS cache 60 s
    "faction_id": "ordre_eclipse",
    "starts_at_epoch": 0, "ends_at_epoch": 0,
    "free_games_max": 5,
    "free_games_left": 3        // null = sans objet (anonyme, ou faction déjà possédée)
  }
}
```

**Règle de VEDETTE (`featured_id`), calculée serveur** — le client ne classe RIEN, sous peine de
montrer autre chose que le hub : (1) parmi les ACTIFS, la plus forte priorité ; (2) à égalité,
celui qui **finit le plus tôt** ; (3) aucun `match`/`bonus` actif → le **prochain** à venir
(« COMMENCE DANS ») ; (4) rien du tout → le personnage gratuit. Il y a donc **toujours** quelque
chose à afficher : une carte de QG vide est interdite.

⚠️ **`free_games_left` est calculé HORS du cache 60 s**, et c'est tout l'intérêt de l'avoir séparé :
il change à chaque partie jouée. Servi depuis le cache, le hub aurait annoncé « 3/5 » pendant une
minute après une partie qui venait d'en consommer une. Le bloc mémoïsé est un dict **partagé entre
requêtes** : il n'est jamais muté sur place — on recompose `events_v2` par-dessus une copie, sinon
le compteur du premier appelant serait servi à tous les suivants.

⚠️ **Zéro logique dupliquée** : le tirage vient de `rotation.current_rotation()`, le décompte de
`access.faction_access_map` (3 requêtes). `free_games_left` n'est renseigné que sous le titre
`rotation` — sous `owned`/`free`/`pass`, `access.py` renvoie le PLAFOND (sémantique « sans objet »),
et l'afficher donnerait un « 5/5 » trompeur sur une faction déjà achetée.

> **Validation.** `test_events.py` **98 ✅ / 0 ❌** (types et priorités dérivées, bornes de la
> fenêtre ISO à la seconde et **égalité avec `weekly_resets_at`**, chevauchement inter-types
> ACCEPTÉ / intra-`match` REFUSÉ — les deux par **sabotage**, `featured` sur toutes les
> combinaisons dont registre vide, non-régression `applies_to`/`snapshot_rules` du type
> `character`). `test_events_flow.py` **53 ✅ / 0 ❌**, intégrale : le moteur des mutateurs ne voit
> aucune différence. **Suite backend COMPLÈTE : 67 suites vertes, 0 rouge.**
>
> ⚠️ Deux harnais stubbaient `api.v1.endpoints.auth` sans `get_current_user_optional`
> (`test_squad_flow`, `test_company_flow` — ce dernier charge `squad.py` à la demande) : stub
> complété, même convention que `test_missions`/`test_ladder_payload`.

---

## §8.135 — MAÎTRISE DE FACTION : rangs infinis, titres persistants, bordures (ADDITIF strict §1.5)

> **Le problème.** Au niveau 50 d'un héros, la progression s'arrêtait net — plus rien à poursuivre
> sur un personnage qu'on jouait depuis des mois. Et les titres honorifiques du Rapport Post-Op
> (`TITLE_BUTCHER`, `TITLE_CONQUEROR`… §8.83) mouraient avec l'écran de fin : aucune trace, aucune
> vitrine. La MAÎTRISE reprend là où le niveau s'arrête.
>
> **Le principe, et c'est TOUT le chantier : la maîtrise SE LIT, ELLE NE SE STOCKE PAS.** Le rang
> est une fonction PURE du total d'XP héros DÉJÀ accumulé par le couple (joueur, faction) au-delà
> du seuil du niveau 50. Aucune table, aucun compteur parallèle, **aucun nouveau tuyau d'accrual** :
> `hero_progression.credit_hero_xp` additionne sans borne depuis l'origine (seul `hero_level_for_xp`
> plafonne, à 50) — **il n'y avait rien à débrider**, contrairement à ce que prévoyait le brief.
> Trois conséquences voulues :
>   • changer la courbe ne demande **aucune migration** — la lecture suivante dit la nouvelle vérité ;
>   • la **PURGE LAZY** des accès temporaires (§8.109) s'applique **GRATUITEMENT** : la ligne d'XP
>     disparaît, donc le rang, les titres et la bordure de cette faction avec elle. Zéro code ;
>   • **rien à stocker donc rien à désynchroniser.** Précédent retenu : les scores de compagnie §8.126.
>
> ⛔ **STRICTEMENT COSMÉTIQUE.** Ni stat, ni récompense (**le rang EST la récompense** : pas un
> coin, pas un XP), ni matchmaking, ni normalisation Classée. Contre-épreuve MÉCANIQUE dans
> `test_mastery.py::test_strictly_cosmetic` : un rang 40 et un rang 0 rendent des `stats` et
> `stats_max` IDENTIQUES sur les 10 factions.

### 1. Registre (module PUR `api/game/mastery.py`)

`MASTERY` est la **SEULE** chose à éditer pour ré-équilibrer :

| Clé | Valeur | Rôle |
|---|---|---|
| `xp_per_rank` | `5000` | coût d'un rang, en XP héros au-delà du seuil du niveau 50 |
| `titles` | `{1: veteran, 5: elite, 10: master, 20: legend, 35: myth, 50: immortal}` | rang d'obtention → clé de titre |
| `borders` | `1 steel · 5 bronze · 10 silver · 20 gold · 35 platinum · 50 prismatic` | tranche de bordure (une CLÉ, jamais une couleur) |
| `summary_cap` | `10` | borne de payload du palmarès des profils |

Le **seuil** est `rewards.hero_total_xp_for_level(HERO_LEVEL_MAX)` — **importé, jamais recopié**
(69 050 XP aujourd'hui). `test_mastery.py::test_no_literal_threshold` le SABOTE et vérifie que la
maîtrise suit : un futur ré-équilibrage de la courbe héros l'emmène avec lui.

⚠️ **`rank > 0` n'est PAS « déverrouillé ».** Un héros qui vient d'atteindre le niveau 50 est
DÉVERROUILLÉ au **rang 0** : il lui reste 5 000 XP pour devenir VÉTÉRAN. D'où le booléen
**`unlocked`** explicite dans le payload — le client ne redéduit pas « niveau ≥ 50 » lui-même.
Au-delà du dernier palier le rang continue (« IMMORTEL · RANG 63 ») : **l'infini est le contrat**.

### 2. `GET /heroes` — bloc `mastery` par personnage (ADDITIF)

```json
"mastery": {
  "rank": 7, "title_key": "elite", "border_tier": "bronze", "unlocked": true,
  "unlocked_titles": ["veteran", "elite"],
  "xp_into_rank": 3120, "xp_per_rank": 5000,
  "next_title": {"rank": 10, "title_key": "master"}
}
```

Bloc **TOUJOURS complet**, y compris pour un héros jamais joué (rang 0, `unlocked: false`,
`title_key: null`) — « aucune maîtrise » est un état affichable, jamais une clé absente. `int` PURS
(piège JSON float §5). **`unlocked_titles` est servi et non déduit du rang côté client** : sans lui,
le sélecteur de titre devrait embarquer la table des paliers, une valeur d'ÉQUILIBRAGE qui doit
pouvoir bouger sans redéploiement de client.

### 3. `/profile/stats` et `/profile/public/{username}` — deux champs (ADDITIFS)

- **`equipped_title: str`** — `"<source>:<key>"` (ex. `"phalanges_acier:veteran"`), `""` = aucun.
  ⚠️ C'est le titre **RÉELLEMENT LÉGITIME AU MOMENT DE LA LECTURE**, pas la valeur brute de la
  colonne (cf. §5 ci-dessous).
- **`masteries_summary: [{faction_id, rank, title_key, border_tier, unlocked_titles}]`** — tri rang
  DÉCROISSANT puis `faction_id` (départage STABLE), **rangs 0 écartés** (c'est un palmarès, pas un
  inventaire), borné à `summary_cap`. `[]` = aucune maîtrise, état affichable.

**Frontière de confidentialité (§8.107) :** le profil PUBLIC expose **ces deux champs et rien
d'autre** de la maîtrise. Un titre est public par construction — il s'affiche déjà au draft devant
cinq adversaires. Restent PRIVÉS la jauge vers le rang suivant, l'XP totale et la carrière par
personnage : ils vivent sur `GET /heroes`, qui ne répond que pour `current_user` et n'accepte aucun
tiers en paramètre. `test_profile_data.py` verrouille la liste blanche.

### 4. `POST /profile/title {title_id}` — équiper / retirer

Réponse **`{ ok: bool, equipped_title: str, reason: str }`**.

**Convention zéro-4xx nominal (§8.112, comme `/company` et `/matchmaking`)** : un refus est un
**200** avec `ok:false` et `reason:"not_unlocked"`, jamais une erreur HTTP. Le sélecteur ne propose
que des titres débloqués — un refus signifie donc un client désynchronisé ou **un droit perdu entre
l'ouverture du panneau et le clic** (purge d'un accès temporaire), deux cas où l'UI doit faire un
rollback propre, pas afficher une panne réseau. `""` = retirer (toujours légal). **IDEMPOTENTE.**

### 5. ⚠️ VALIDATION À LA LECTURE, PAS SEULEMENT À L'ÉQUIPEMENT — « jamais de titre fantôme »

`users.equipped_title` (colonne additive, `server_default ""`, auto-migrée ; archive
`migration_mastery.sql`) n'est **pas un acquis mais une PRÉFÉRENCE D'AFFICHAGE**. Le droit de porter
un titre peut se perdre **sans que le joueur ne touche à rien** : une faction jouée en rotation ou
sous Pass voit sa progression PURGÉE à l'expiration → rang 0 → le titre n'existe plus. La purge
étant LAZY (aucun cron), **aucun événement ne se déclenche à ce moment-là** : la seule occasion de
s'en apercevoir est la lecture suivante.

D'où `hero_progression.resolve_equipped_title()`, appelée à **chaque** lecture de profil ET au
draft : un titre devenu illégitime est renvoyé `""` **et nettoyé en base**. On ne se contente pas de
le taire — il ressusciterait au rechargement suivant.

**Exception assumée :** le profil PUBLIC lit avec `purge=False` (LECTURE SEULE stricte §8.107 —
consulter le palmarès d'un tiers ne doit écrire aucune ligne chez lui). Conséquence bornée : le
profil public d'un joueur dont l'accès vient d'expirer peut montrer un rang d'avance jusqu'à SA
prochaine connexion. Jamais l'inverse, et jamais chez lui.

### 6. Identité en partie — `PlayerState` (3 champs ADDITIFS, publics)

`equipped_title: str` · `mastery_rank: int` · `mastery_border: str`. Posés au **draft**
(`router._load_mastery_identity`, session courte tolérante aux pannes — un ornement ne fait jamais
rater un lancement) ; `""`/`0` pour un bot. **Le rang est celui de la faction JOUÉE**, pas de la
meilleure maîtrise : on porte les couleurs de la faction qu'on a engagée. `mastery_border` voyage
**en plus** du rang pour que le client n'ait aucun seuil de tranche en dur.

⚠️ **Consommés par le DRAFT et le RAPPORT POST-OP uniquement — PAS par l'arène** (chips, HUD, kill
feed) : la lisibilité tactique prime et le HUD est déjà dense. Décision de sobriété, pas un oubli.

### 7. `game_over` — `mastery_rank_up` (ADDITIF)

`{ "from": int, "to": int, "title_key": str|null } | null`. `null` = aucun rang franchi (l'immense
majorité des matchs). Calculé par **deux appels au module PUR**, sans état : le total d'avant se
retrouve exactement par `hero_total_xp − hero_xp_earned`.

`title_key` n'est renseigné que si un **NOUVEAU titre** est débloqué : monter de 12 à 13 est une
montée de rang sans nouveau titre, et annoncer « MAÎTRE » une seconde fois ferait mentir la
célébration. Un multi-franchissement (rang 4 → 6 en une partie) rend **UN seul bloc** et le titre du
rang FINAL — on montre l'aboutissement, pas l'historique.

### 8. Format d'identifiant `"<source>:<key>"` — prévu pour la suite

`source` est un `faction_id` aujourd'hui. Le format accueillera **tel quel** les titres d'ÉVÉNEMENT
et de CHAMPIONNAT (hors périmètre v1) sans toucher ni à la colonne ni à la route.

### Validation

`test_mastery.py` **176 ✅ / 0 ❌** : bornes de rang **au XP près** (un cran sous/au seuil, dernier XP
avant chaque palier, rang 63), réciprocité `rank ∘ total_for` sur 120 rangs, sabotage du seuil,
titres et 6 tranches à toutes leurs bornes, ids malformés, purge → rang 0 + titre déséquipé,
pérennisation à l'achat, profil public sans écriture, refus `not_unlocked` **par sabotage** (4
formes), cycle complet rotation expirée, `mastery_rank_up` (simple / multiple / aucun / saut
extrême), et la **contre-épreuve d'équité**. **Suite backend COMPLÈTE : 69 suites vertes, 0 rouge.**

⚠️ Trois suites existantes ont été mises à jour **délibérément** : `test_heroes_roster` (contrat de
clés STRICT → `mastery` ajouté + 6 contrôles neufs), `test_profile_data` (**liste blanche de
confidentialité** — l'extension est un choix documenté, c'est exactement ce que ce test doit
forcer), `test_tutorial` (stub `pydantic`, `profile.py` déclarant désormais un `BaseModel`).

⚠️ **VPS + client partent ENSEMBLE.** Le client lit `mastery` / `masteries_summary` /
`mastery_rank_up` ; le serveur pose `equipped_title` dans l'état de partie. Chaque lecture a un
défaut sûr, mais un client à jour face à un serveur ancien n'affiche AUCUNE maîtrise.

---

## §8.136 — LA TRANCHÉE : mini-jeu d'événement, duel 1v1 TEMPS RÉEL (onglet BONUS, ADDITIF strict §1.5)

> **Le premier contenu de l'onglet BONUS (§8.134) et la PREMIÈRE boucle temps réel du projet.**
> Deux soldats dans deux tranchées face à face, 5 positions discrètes, DEBOUT pour agir / ACCROUPI
> pour survivre, grenades en cloche, escalade d'armes au mérite — match en 2 manches gagnantes,
> manche de 90 s. Faisable à **20 Hz** (10 Hz jusqu'au §8.141.5) sur le WebSocket existant grâce à UNE règle d'or absolue :
> **tout ce qui traverse le no man's land est un projectile, résolu À L'IMPACT par le serveur**
> — aucune prédiction complexe, aucune compensation de lag, aucun netcode de FPS (détail
> règles/équilibrage : encart `ARCHITECTURE_ET_REGLES.md`).
>
> ⚠️⚠️ **LA RÈGLE D'OR A ÉTÉ AMENDÉE AU §8.141.2, SUR DÉCISION DE HAKIM.** Elle imposait « balles
> >= 3 ticks de vol, esquivables pendant le vol ». Après trois rapprochements de l'arène (35 → 12
> → 9 m) **sans jamais re-dériver le temps de vol**, la balle de départ tombait à 25 m/s et le
> budget clic → touche à **696 ms** : « dès que je clique, il s'est déjà déplacé — c'est
> injouable ». Les balles volent désormais **1 tick (0,1 s)** ; le budget tombe à **346 ms**.
> **CE QUI DISPARAÎT** : l'esquive d'une BALLE par un pas ou un plongeon (0,1 s est sous le temps
> de réaction humain). Se baisser reste une COUVERTURE, ce n'est plus une RÉACTION.
> **CE QUI SURVIT** : la résolution reste À L'IMPACT et côté SERVEUR, dans un tick strictement
> postérieur au tir (plancher structurel de 1 tick — à 0, l'ordre interne du tick deviendrait une
> règle de jeu et le rejeu déterministe perdrait son sens) · la sim reste à **10 Hz sans
> compensation de lag** · la **GRENADE** garde son plancher de **15 ticks** et reste la menace
> lente, annoncée et esquivable · le **CONDOR** garde son laser de 5 ticks et devient le SEUL tir
> télégraphié du jeu.

### 1. Architecture — une salle `mode="trench"`, un aiguillage précoce, AUCUN GameEngine

- **`game_rooms.mode`** (String, `""` = partie classique, `server_default` → auto-migrée ; archive
  `migration_trench.sql`). Un duel = un `GameRoom(mode="trench", max_players=2, is_ranked=False)` +
  ses `GameRoomPlayer` — le gate de membership 4003 est hérité tel quel.
- **Aiguillage PRÉCOCE** (`router._room_mode`, lu UNE fois par connexion WS, après version 4000 /
  auth 4001 / membership 4003) : une salle `trench` est déléguée ENTIÈRE à
  `trench_runner.handle_trench_socket` — **aucun message de duel ne traverse `GameEngine`**, aucun
  verrou/minuterie de salle classique n'est armé. Une salle normale ne voit de ce chantier qu'une
  lecture de colonne (contre-épreuve par SABOTAGE : condition inversée → `test_security_locks`
  tombe, remise en place → 71/71 suites vertes).
- **Runtime IN-MEMORY par process** (`api/sockets/trench_runner.py`, 1 worker — même contrainte que
  ConnectionManager) : état de simulation + tampons d'entrées + task de tick 10 Hz par salle. Un
  redémarrage perd les duels en cours — assumé : la purge des GameRooms au boot (`main.py`) et le
  message `trench_room_gone` (close 1000) couvrent le cas proprement.
- **La RÈGLE vit dans deux modules PURS** : `api/game/trench_sim.py` (registres `TRENCH_RULES` /
  `TRENCH_WEAPONS` / `TRENCH_GRENADE` / `ESCALATION`, état sérialisable, `step(state, inputs, tick,
  rng)` DÉTERMINISTE — rejeu au bit près, contre-épreuve porteuse de `test_trench_sim.py`) et
  `api/game/trench_bot.py` (machine à états lisible : esquive du marqueur si préavis >= 0,8 s ⚙,
  plongeon face au laser, agression/couverture alternées, rng injecté).

### 2. Protocole WS (§1.5 additif — enveloppe de salle existante)

- **client → serveur** (À PLAT, comme le chat) — `{"type": "trench_input", "move": -1|0|1,
  "stance": "up"|"down", "fire": bool, "throw": {"target_x": float} | null,
  "pick_weapon": "chacal"|"condor" | null, "aim": {"yaw": float, "pitch": float} | null,
  "reload": bool, "item": "bandage" | null}`. **<= 10 msg/s par connexion, le serveur JETTE le
  surplus** (anti-flood, `TrenchRuntime.allow_message`) ; le tick serveur COALESCE (dernière
  direction/posture/VISÉE gagnante, un clic de tir n'est jamais perdu, le 11e message d'un tick est
  ignoré — `trench_sim.coalesce_inputs`). `{"type": "trench_forfeit"}` = abandon (ÉCHAP confirmé).
  - ### ⚠️ **`throw` (§8.141) — LE POINT VISÉ REMPLACE LA JAUGE DE CHARGE**
    `{"target_x": float}` : abscisse d'impact **en MÈTRES sur l'axe du front**, 0 = centre,
    quantifiée au décimètre par le client. La profondeur n'est **pas** une variable du jeu — une
    grenade tombe toujours dans la tranchée adverse, et `target_x` est **la seule** coordonnée qui
    voyage.
    - **REPLI ACCEPTÉ** : `{"charge": 0..1}`, la convention d'avant §8.141. Le serveur la traduit
      en `target_x` du **centre de la position correspondante** (`grenade_target_pos`, arrondi
      demi-supérieur). ⚠️ Un client retardataire vise donc EXACTEMENT où il visait — mais il
      encaisse le **modèle de dégâts neuf** comme tout le monde : un duel ne peut pas appliquer
      deux physiques selon la version du client de chacun. `target_x` GAGNE si les deux sont
      présents. Un `throw` illisible (NaN, ±inf, texte) retombe sur le repli plutôt que
      d'empoisonner la simulation.
    - **CLAMP SERVEUR** : `target_x` est borné à `±(front/2 + target_margin_m)`. Il n'est **pas**
      re-quantifié (même raison que pour `aim` : le pas de 0,1 m est une mesure de bande passante
      côté client, pas une règle — et la décroissance des dégâts étant continue, il n'y a aucune
      case à voler).
    - **DÉGÂTS CONTINUS** : `dmg = damage_max × max(0, 1 − d / radius_m)` où `d` est la distance du
      centre de la position occupée par la victime au point d'impact, **quelle que soit la posture**
      (c'est l'arme anti-camping). `radius_m = 2,5 m` ⚙, `damage_max = 40` ⚙. Conversion en entier
      par TRONCATURE : à `d = radius_m` exactement, 0 dégât — jamais −0, jamais un point d'arrondi.
    - **TEMPS DE VOL** : `0,9 s + 0,07 s/m` de distance PARCOURUE (profondeur et travers du front
      compris), plancher `flight_floor_ticks = 15` — c'est ce plancher qui porte la **règle d'or**,
      vérifié au chargement du module comme les temps de vol des armes. Un lancer en travers vole
      donc plus longtemps qu'un lancer droit devant, et s'esquive mieux.
    - **INTERACTION AVEC LE RECHARGEMENT** ⚙ : lancer PENDANT un rechargement est **autorisé**, et
      le rechargement **repart du début** (`reload_start` est ré-émis avec `"restarted": true`).
      L'interdire serait refuser un geste en silence à celui qui en a le plus besoin ; l'autoriser
      gratuitement ferait de la grenade le meilleur moyen de meubler un rechargement.
  - **`aim` (§8.137)** : direction de visée en DEGRÉS dans le repère de l'arène (yaw 0 = droit
    devant, + = vers la droite du tireur ; pitch + = vers le haut). Envoyée **seulement quand elle
    change**, arrondie au dixième de degré. ⚠️ Le serveur ne RE-QUANTIFIE pas : le pas de 0,1° est
    une mesure de bande passante côté client, pas une règle (re-quantifier obligerait Python et
    Godot à s'accorder sur un arrondi de demi-pas pour un gain nul). Valeurs non numériques, NaN
    ou ±inf : l'entrée `aim` est ignorée EN ENTIER.
  - ⚠️⚠️ **LE CLIENT N'ANNONCE JAMAIS UNE TOUCHE** — il envoie une direction. Le serveur résout
    contre SA table angulaire et SON état, à l'instant de l'impact. Un client modifié peut mentir
    sur sa propre présentation, jamais sur les dégâts.
- **serveur → clients** :
  - `trench_init` (PERSONNEL, à la connexion et à la reconnexion) : `{rules:
    trench_sim.public_rules(), your_slot: 1|2, training: bool, opponent: {name, is_bot},
    state | null}` — le client n'a AUCUNE constante du mini-jeu en dur (patron
    `battle_royale.public_rules` §8.131). `rules` porte désormais aussi, par arme,
    `dispersion_deg`/`mag_size`/`reload_ticks`, le bloc `bandage`, et le bloc `geometry` (cotes du
    blockout : `no_mans_land`, `positions`, `position_spacing`, `parapet_y`, `eye_up`, `eye_down`,
    `aim_quantum_deg`).
    ⚠️ **`rules.grenade.radius_m` EST LE CONTRAT VISUEL DU §8.141**, et pas seulement une donnée
    d'équilibrage : c'est CETTE valeur — celle qui décide des dégâts — que le client utilise pour
    ouvrir son décalque de visée, ses marqueurs d'impact et son anneau de choc. Il n'y a pas deux
    rayons à garder d'accord, il n'y en a qu'un, et le cercle ne PEUT donc pas mentir. Le bloc porte
    aussi `damage_max`, `flight_base_s`, `flight_per_metre_s`, `flight_floor_ticks` et
    `target_margin_m` (dont le client dérive sa borne de visée, au lieu de la recalculer).
    ⚠️ L'état joint est REDACTÉ lui aussi — sans quoi il suffirait de se reconnecter pour
    photographier la position d'un accroupi.
  - `trench_state` (**PERSONNEL, un payload PAR JOUEUR**, 10 Hz) : `{tick, phase:
    intermission|playing|over, round_no, round_start_tick, round_ticks, score: [m1, m2],
    winner_slot, players: [{slot, pos, stance, hp, weapon, hits_total, grenades,
    choice_deadline_tick, laser_fire_tick, disconnected, ammo, reload_until_tick, bandages,
    bandage_until_tick, aiming, hidden}], projectiles: [{id, kind, owner_slot, from_pos,
    target_pos, target_x, launch_tick, impact_tick, aim_yaw, aim_pitch}], events: [...]}`.
    ⚠️ **`target_x` (§8.141)** : le point d'impact EXACT d'une grenade, en mètres sur l'axe du front.
    C'est lui que le client dessine des deux côtés et lui qui décide des dégâts. `target_pos` reste
    diffusé — la position adverse la plus PROCHE du point — pour les consommateurs qui raisonnent
    encore en cases (bot, journaux, client retardataire) ; il n'entre plus dans aucun calcul de
    dégât. Les événements `grenade_thrown` et `impact` le portent eux aussi : l'explosion doit
    naître EXACTEMENT là où le décalque l'annonçait depuis le lancer.
    ⚠️ Les projectiles voyagent par INSTANTS (lancement, impact) — le CLIENT interpole la
    trajectoire, le serveur ne calcule que les instants et les dégâts. Depuis §8.137 ils portent
    AUSSI leur visée réelle (`aim_yaw`/`aim_pitch` = visée du tireur + écart de dispersion figé au
    départ) : c'est ce qui permet de tracer la traçante dans la VRAIE direction, y compris quand
    elle rate.
    Événements du tick : `round_start` · `fire {rounds, ammo}` · `impact` · `hit` ·
    `grenade_thrown` (marqueur visible par la cible DÈS le lancer) · `laser {fire_tick, from_pos,
    aim_yaw, aim_pitch}` (CONDOR : 5 ticks avant le TIR) · `laser_cancelled` · `reload_start` ·
    `reload_end` · `bandage_start` · `bandage_end` · `bandage_interrupted` · `escalation` ·
    `weapon_choice` · `weapon_chosen` · `round_end {winner_slot: 0 = nulle-rejouée, reason:
    kill|time|afk|disconnect}` · `match_end {reason: score|disconnect|forfeit}` ;

#### 2 bis. STATE REDACTION du duel (§8.137) — l'état est PAR DESTINATAIRE

> **Ce paragraphe remplace la règle v1 « même état pour les deux, il n'y a aucun secret dans une
> tranchée ».** Le pivot première personne a rendu la position une INFORMATION.

- `trench_sim.redacted_view(state, viewer_slot)` est le **SEUL point de sortie réseau autorisé**.
  `public_state()` (vue complète) sert aux tests et à la construction interne — il ne franchit
  JAMAIS un socket. `trench_runner._broadcast_state` envoie donc DEUX messages personnels par tick.
- **Règle** : la position de l'adversaire part à `pos: null` + `hidden: true` **dès qu'il est
  ACCROUPI**. Elle revient dès qu'il se lève (`is_position_revealed` = `stance == "up"`) — et il
  faut être debout pour tirer, épauler ou lancer, donc « agir » implique « se montrer ».
  Recharger ACCROUPI reste caché : c'est exactement le dilemme du §1.4.
- **Ce qui reste TOUJOURS visible, et pourquoi** : les projectiles en vol et les marqueurs
  d'impact de grenade (la règle d'or exige que toute menace soit lisible et esquivable) ; les PV,
  l'arme, les munitions, le score et le chrono (rien de cela ne localise personne). Un tir trahit
  donc son auteur par le `from_pos` de sa balle — c'est voulu et cohérent.
- **C'est un anti-cheat STRUCTUREL**, pas une politesse d'affichage : le maphack n'existe pas si
  la carte n'est pas envoyée. Le BOT reçoit lui aussi la vue redactée (`trench_runner` lui passe
  `redacted_view`) — il tire sur la dernière position connue et se trompe comme un humain.
- Contre-épreuves : `test_trench_sim.test_redaction` (1 000 ticks, assertion à chaque tick +
  sabotage de `is_position_revealed`) et `test_trench_bot.test_bot_ne_triche_pas` (nourri de la
  vue complète, le bot viserait la vraie position — preuve que c'est la redaction qui l'aveugle).

#### 2 ter. LA TABLE ANGULAIRE (§8.137) — la géométrie est une DONNÉE, en double

- La visée est résolue **à l'impact** contre `AIM_WINDOWS` : `(pose du tireur, position cible,
  posture cible) -> (yaw_min, yaw_max, pitch_min, pitch_max)`, en degrés.
- **L'ABSENCE D'ENTRÉE EST LA RÈGLE MÉTIER** : une cible ACCROUPIE n'a aucune fenêtre, donc aucune
  balle ne peut la toucher. L'invariant « accroupi injouable aux balles » est porté par la DONNÉE,
  pas par un `if` qu'on pourrait oublier.
- Les fenêtres de deux positions voisines sont **DISJOINTES** (~5,4° d'écart pour ~0,96° de large)
  et aucun cône de dispersion d'arme ne les franchit : **un pas de côté est toujours une esquive**,
  et une balle dispersée rate — elle ne se trompe jamais de cible.
- Le fichier `trench_angles.json` est généré par `frontend/tools/gen_trench_angles.tscn` depuis le
  BLOCKOUT 3D et écrit **aux deux emplacements** : `backend/api/game/data/` (résolution serveur) et
  `frontend/resources/trench/` (rendu client). ⛔ **NE JAMAIS L'ÉDITER À LA MAIN.**
  `test_trench_angles.py` compare les checksums — une divergence géométrique client/serveur devient
  une suite ROUGE plutôt qu'un « je vise la tête et ça ne touche pas » introuvable.
- La simulation reste **PURE** : la table est chargée UNE fois à l'import (`trench_angles.py`,
  patron `map_data.py`), aucune trigonométrie dans la boucle, le REJEU AU BIT PRÈS survit intact.
  - `trench_result` (PERSONNEL, à la fin) : `{your_slot, winner_slot, you_won, score, reason,
    vs_bot, training, rewards: {participation_coins, participation_capped, win_coins, win_capped,
    new_titles: [{threshold, title_id, title_key}], progression: {wins, level, level_max,
    next_threshold, thresholds, titles}} | null}`.
- **Client** (§2.4 du brief) : rendu interpolé **150 ms** derrière le dernier état (tampon
  horodaté) ; SEULE exception, la posture/position du joueur LOCAL est appliquée IMMÉDIATEMENT
  (réconciliation silencieuse : 2 états divergents consécutifs → on se cale sur le serveur). Rien
  d'autre n'est prédit.
- **Déconnexion/AFK (décision n° 10)** : socket tombé → la sim reçoit le marqueur `disconnected`
  (soldat FIGÉ ACCROUPI) ; grâce 10 s → manche perdue ; 2e fois → match perdu. 20 s sans le
  moindre message → manche perdue. Jamais connecté au coup d'envoi (20 s ⚙) → forfait immédiat.
  La reconnexion passe par la MÊME URL WS (socle §5) et ré-reçoit `trench_init`.

### 3. REST (préfixe `/trench`, convention zéro-4xx §8.112) — `api/v1/endpoints/trench.py`

- `POST /trench/queue` → `{queued}` ou `{queued: false, reason: event_closed|banned|in_room}` ;
  `event_closed` porte `event_window` (epochs de la PROCHAINE fenêtre — le client affiche un
  rebours exact sans aucune date en dur). `GET /trench/queue/status` (heartbeat 2 s — états
  §8.116 : searching/extending/starting/ready/in_game/idle + `event_closed` si la fenêtre se ferme
  PENDANT l'attente) · `DELETE /trench/queue` (refus doux `assigned`, re-lecture post-ZREM —
  même course fermée que §8.116).
- **File `mm:q:trench`** (FIFO, 2 joueurs, bot-fill 60 s — `matchmaking.plan_bucket`, la MÊME
  décision pure que partout) traitée par le tick du `matchmaker_runner` (branche dédiée →
  `trench_runner.process_trench_bucket`). ⚠️ MÊME clé de ticket `mm:ticket:{uid}` que les files
  solo/équipe : toutes les gardes « déjà en file » du dépôt fonctionnent sans une ligne de plus.
  Hors fenêtre, la file se PURGE à chaque tick (tickets effacés → le client retombe sur idle).
- `POST /trench/training` : salle solo + bot créée DIRECTEMENT sans file (pattern « LANCER AVEC
  BOTS ») — aucune récompense, aucun compteur, gate d'événement identique.
- `GET /trench/leaderboard` (PUBLIC, enrichi si connecté — patron du bloc `me` §9.2) :
  `{entries: [{rank, name, wins, level}] (top 50, cache processus 60 s — pattern compagnies),
  me: {name, rank|null, wins, level, level_max, next_threshold, thresholds, titles} | null,
  event_active}`.

### 4. Récompenses, progression, titres (équité ABSOLUE : rien n'entre jamais dans la simulation)

- **Raison ledger `trench`** (11e — `economy.REASON_TRENCH`), refs `participation`/`win` :
  participation **5 ¢** (max 5/jour), victoire contre un HUMAIN **+15 ¢** (max 5/jour) ⚙ —
  montants dans `trench_progression.TRENCH_REWARDS`, plafonds en compteurs Redis
  `trench:cap:{kind}:{uid}:{jour}` à la convention **04:00 UTC** (`mission_day_key`, TTL 2 j).
- ⚠️ **ANTI-FARM (décision n° 8)** : victoire contre le BOT = participation SEULE, et
  `users.trench_wins` n'est PAS incrémenté. L'ENTRAÎNEMENT ne crédite RIEN.
- **`users.trench_wins`** (compteur additif auto-migré) : total à vie de victoires HUMAINES. Le
  **niveau d'événement** (paliers 5/15/40 → 0..3) et les **titres** s'en DÉRIVENT à la lecture
  (`api/game/trench_progression.py`, PUR — rien d'autre n'est persisté, patron maîtrise §8.135).
- **Titres `"trench:grenadier"` / `"trench:sapeur"` / `"trench:seigneur_des_tranchees"`** : le
  format `"<source>:<key>"` de la maîtrise accueille sa première source d'ÉVÉNEMENT —
  `mastery.EVENT_TITLES["trench"]` (SOURCE UNIQUE des paliers), `is_title_unlocked` valide contre
  la MÉTRIQUE `event_title_metrics(user)` (= `trench_wins`), la MÊME route `POST /profile/title`
  équipe, `resolve_equipped_title` nettoie un titre perdu. ⚠️ `masteries_summary` ÉCARTE les
  sources d'événement : le palmarès de maîtrise reste un palmarès de FACTIONS — la progression
  trench s'affiche et s'équipe dans le hub Événements (onglet BONUS).
- **Télémétrie légère** (décision §4.3, le plus simple documenté) : UNE ligne de log structurée
  par duel (`trench_match room=… ticks=… score=… winner_slot=… reason=… weapons=…`).

### 5. Événement-porte `trench_week` (type `bonus` — le premier réel)

Registre `events.py` : `trench_week` (priorité 30 dérivée, AUCUN mutateur — `applies_to` refuse
déjà tout type ≠ `match`, un bonus ne mute JAMAIS une partie). Calendrier : `(2026, 8)` ordinal 2
(**ven. 14 août 18:00 → lun. 17 août 00:00 UTC — ⚙ PREMIÈRE FENÊTRE À CALER PAR HAKIM**).
Nouveau helper PUR `events.is_event_active(event_id, now)` = LE gate de la file/entraînement.
Pendant sa fenêtre, `featured` le met en VEDETTE du QG (bonus 30 > match 20 — §8.134 inchangé).

> **Fichiers.** NOUVEAUX : `api/game/trench_sim.py`, `api/game/trench_bot.py`,
> `api/game/trench_progression.py`, `api/sockets/trench_runner.py`, `api/v1/endpoints/trench.py`,
> `migration_trench.sql`, `test_trench_sim.py`, `test_trench_bot.py`, `test_trench_flow.py`.
> MODIFIÉS : `models/models.py` (2 colonnes), `api/game/economy.py` (raison), `api/game/events.py`
> (trench_week + is_event_active), `api/game/mastery.py` (EVENT_TITLES additif),
> `api/game/hero_progression.py` + `api/v1/endpoints/profile.py` (métriques d'événement),
> `api/sockets/router.py` (aiguillage), `api/sockets/matchmaker_runner.py` (branche bucket),
> `api/__init__.py`. Client : voir `FRONTEND_INTERFACES.md §8.136`.
>
> **Validation.** `test_trench_sim.py` **86 ✅** (REJEU 1 000 ticks au bit près + sabotage de
> registre qui DOIT diverger) · `test_trench_bot.py` **15 ✅** (2 bots × 1 000 ticks
> déterministes) · `test_trench_flow.py` **56 ✅** (gate, formation, plafonds, anti-farm,
> classement) — **suite backend COMPLÈTE : 71 suites vertes, 0 rouge** (3 suites adaptées :
> compteur 11 raisons ×2, `next_event` sous TEMPÊTE → trench_week). Client : `--import` 0 ERROR,
> boots headless 0 ERROR (events, trench_duel, main_menu, search), 4 captures PNG RELUES
> (2 défauts de layout trouvés et corrigés par ELLES : ancres par méthode + offsets, fond
> viewport). ⛔ Recette manuelle à DEUX COMPTES à faire (annexe de `RAPPORT_MINIJEU_TRANCHEE.md`).
>
> ⚠️ **VPS + client partent ENSEMBLE** (le client appelle `/trench/*` et la scène de duel parle le
> protocole ci-dessus ; le gate de version WS protège la transition).

---

## §8.142 — INTERFACE D'ADMINISTRATION : `blocking_sanction` (volet RÉSEAU — **shape INCHANGÉE**)

> Chantier complet : [`ADMINISTRATION.md`](ADMINISTRATION.md). **Le client Godot n'est PAS touché**
> (à une clé i18n OPTIONNELLE près, cf. plus bas) : aucun gate de version, aucun build nécessaire.

### 1. Un seul point de décision côté serveur

`api/v1/endpoints/matchmaking.py` gagne **`blocking_sanction(db, user_id, now)`**, qui rend la
sanction active **la plus contraignante** (échéance la plus lointaine) parmi
`BLOCKING_SANCTION_KINDS = ("search_abuse", "admin_ban")`.

Les **9 points de contrôle** du dépôt remplacent leur appel
`active_sanction(db, uid, "search_abuse", now)` par `blocking_sanction(db, uid, now)` :

| Fichier | Routes |
|---|---|
| `endpoints/matchmaking.py` | `POST /matchmaking/queue` · `POST /private/rooms` · `POST /private/join` |
| `endpoints/squad.py` | `POST /squad/create` · `POST /squad/join` · `POST /squad/queue` |
| `endpoints/company.py` | `POST /company/create` · `POST /company/join` |
| `endpoints/trench.py` | `POST /trench/queue` |

> ⚠️ Le brief du chantier en annonçait **7** ; il y en a **9** (`company.py` en porte deux de plus).
> **Le code fait foi** — re-grepper `blocking_sanction(` reste la seule liste fiable.

### 2. Ce que le CLIENT voit : RIEN de nouveau

La réponse `banned` est **bit-à-bit** celle d'avant : `{"queued"|"created"|"joined"|"squad"|
"company": False, "reason": "banned", "banned_until_epoch": …}` (+ `"ban_hours"` là où il était
déjà présent). Un client antérieur au chantier ne peut pas distinguer un `admin_ban` d'un
`search_abuse` — **c'est voulu** : la convention zéro-4xx (§8.112) est intacte, et un joueur banni
voit l'écran « banni » qu'il connaît déjà.

**Nouveau motif `kind = "admin_ban"`** dans la table `sanctions` (le champ était String depuis
§8.116, « pour pouvoir ajouter d'autres motifs plus tard sans migration » — c'est ce jour).

### 3. LEVÉE — nouvelle notion, invisible du réseau

Une sanction levée par un opérateur porte `lifted_at`/`lifted_by` : la ligne **reste** (l'historique
est un LEDGER, jamais de DELETE), elle cesse simplement de produire son effet. `active_sanction`
**et** `blocking_sanction` l'excluent — via `getattr(s, "lifted_at", None)`, **défensif** parce que
les doublures de `Sanction` des suites de tests historiques ne portent pas cette colonne (c'est ce
qui fait passer `test_search_sanctions.py` **sans une ligne modifiée**).

### 4. ÉQUITÉ de l'escalade (`_apply_search_ban`)

Le `.count()` devient un `.all()` + comptage Python, ce qui donne deux garanties :

1. un **`admin_ban` n'aggrave JAMAIS** l'escalade anti-bruteforce (seuls les `search_abuse` comptent) ;
2. une sanction **LEVÉE n'y compte plus** — si un opérateur reconnaît une erreur du système, elle ne
   doit pas peser des mois. **Lever rend un cran d'escalade.**

### 5. Économie — une raison canonique de plus

`REASON_ADMIN_ADJUST = "admin_adjust"` (12ᵉ raison), placée dans `ALL_REASONS` entre
`season_reward` et `coin_pack`. Le client en dérive la clé i18n
`PROFILE_FIN_SRC_ADMIN_ADJUST` ; **tant qu'elle n'est pas embarquée, le repli « libellé muet » de
§8.106 fait exactement son travail** — l'ajout d'une raison est SÛR sans build client.

⚙ **Clé à embarquer au PROCHAIN build (optionnel, non bloquant)** : `PROFILE_FIN_SRC_ADMIN_ADJUST`
= FR « AJUSTEMENT DU COMMANDEMENT » · EN « COMMAND ADJUSTMENT » · IT « RETTIFICA DEL COMANDO ».

### 6. Événements — le calendrier devient dynamique, le CONTRAT ne bouge pas

`events.py` reçoit un hook `external_windows_provider` alimenté par la table `event_schedules`.
`active_event` / `active_events` / `is_event_active` / `featured` / `next_event` /
`upcoming_events` gardent **exactement** leur forme publique (epochs `int` purs, clés i18n, aucun
texte affichable). Une fenêtre programmée depuis l'administration est, pour le client,
indiscernable d'une fenêtre du calendrier codé — **c'est tout l'intérêt**.

**Propagation : ≤ 60 s** (cache in-process d'`events_store`, sur le chemin chaud du matchmaking).

---

## §8.143 — ADMINISTRATION V2 : la raison `closed` (volet RÉSEAU — **ADDITIF STRICT §1.5**)

> Chantier complet : [`ADMINISTRATION.md`](ADMINISTRATION.md) **§9 à §15**.
> **Le client Godot n'est PAS touché** : aucune clé renommée, aucune clé retirée, aucun gate de
> version, aucun build nécessaire. Une clé i18n a été ajoutée au CSV (§4 ci-dessous) — elle
> s'embarquera au prochain build, sans couplage de déploiement.

### 1. Nouvelle raison de refus : `closed` (+ `cause`)

Le vocabulaire de refus du matchmaking (`banned` · `in_room` · `queued`/`created`/`joined` faux ·
`not_queued` · `assigned` · `busy` · `unavailable` · `playlist_closed` · `full` · `not_leader`)
**s'AGRANDIT** d'une entrée :

```jsonc
{ "queued": false, "reason": "closed", "cause": "maintenance" }
```

| Route | Clé de succès | Quand |
|---|---|---|
| `POST /matchmaking/queue` | `queued` | maintenance · ou `queue == "ranked"` avec la classée coupée |
| `POST /private/rooms` | `created` | maintenance |
| `POST /private/join` | `joined` | maintenance (**avant** la résolution du code : sans cela, la garde anti-bruteforce serait contournable pendant un gel) |
| `POST /squad/queue` | `squad` | maintenance · ou playlists d'équipe coupées |
| `POST /trench/queue` | `queued` | maintenance |
| `POST /trench/training` | `created` | maintenance |

`cause` ∈ **`"maintenance"`** (tout est gelé, ça va rouvrir) | **`"feature_disabled"`** (CETTE file
est coupée, le reste du jeu tourne). Deux situations qui n'appellent pas la même réaction du joueur.

**Shape par ailleurs INCHANGÉE** : la clé de succès reste `false`, aucun autre champ n'est modifié.

### 2. ORDRE des refus — `banned` AVANT `closed`

Le message le **plus spécifique** gagne. Un joueur banni pendant une maintenance reçoit toujours
`banned` : lui répondre « revenez plus tard » lui ferait croire sa sanction levée.

⚠️ Deux exceptions **cartographiées**, pas des oublis :
- `POST /trench/queue` et `POST /trench/training` évaluent **`event_closed` en premier** (gate
  d'événement, comportement d'avant le chantier) ;
- `POST /trench/training` n'a **aucun** contrôle de sanction (il ne verse aucune récompense) : il
  gèle donc sur `closed`, faute de plus spécifique.

### 3. LA TRANCHÉE coupée par coupe-circuit → **`event_closed`**, raison EXISTANTE

Le drapeau `FLAG_TRENCH_OPEN` s'emboîte dans le gate d'événement : la réponse est **exactement**
celle d'une fenêtre fermée, bloc additif `event_window` compris. **Zéro nouveauté réseau sur ce
chemin**, et le client affiche déjà l'écran adéquat.

### 4. `GET /squad/playlists` gagne `maintenance: true|false` (ADDITIF)

La configuration publique porte désormais l'état du gel, pour qu'un futur hub puisse l'afficher
**sans attendre un refus de mise en file**. Les clients actuels ignorent cette clé. Volontairement
**hors** du bloc mémoïsé 60 s de la route : un gel doit se voir tout de suite.

### 5. ⚠️ CE QUE LE CLIENT ACTUEL FAIT D'UNE RAISON INCONNUE (cartographié 2026-08-08)

| Écran | Comportement | Verdict |
|---|---|---|
| Recherche de partie (`search_screen.gd`) | branche terminale §8.118 → panneau CONFIGURATION + `MM_QUEUE_FAILED`, CTA re-cliquable | ✅ dégradation acceptable |
| File d'équipe (`squad_screen.gd`) | `match` avec défaut `_:` → `SQUAD_ERR_UNAVAILABLE` | ✅ acceptable |
| Créer un salon privé | seul `banned` traité → **écran muet** | ⚠️ à corriger au prochain build |
| Rejoindre un salon privé | `match` sans branche par défaut → **écran muet** | ⚠️ à corriger au prochain build |

**Dégradation ACCEPTÉE et documentée** — la mécanique serveur est définitive, l'écran dédié viendra.

> 🩸 `search_screen.gd` affiche en priorité un champ `message` s'il existe dans la réponse. Il
> serait donc tentant d'en ajouter un côté serveur pour afficher un vrai texte sans build client.
> **On ne le fait pas** : la règle R4 (« le serveur ne renvoie jamais de texte affichable ») existe
> parce que le client est traduit en trois langues et que le serveur ne sait pas laquelle.

### 6. Clé i18n ajoutée au CSV (asynchrone, sans couplage)

`PROFILE_FIN_SRC_ADMIN_ADJUST` = FR « AJUSTEMENT DU COMMANDEMENT » · EN « COMMAND ADJUSTMENT » ·
IT « RETTIFICA DEL COMANDO », dans `frontend/translations/ui_strings.csv` uniquement (⛔ jamais les
`.translation`/`.import` générés). Le client dérive la clé par `"PROFILE_FIN_SRC_" +
reason.to_upper()` (`profile.gd`). D'ici le prochain build, le repli « libellé muet » de §8.106 fait
son travail.

---

## §8.144 — LE COURRIER DU COMMANDEMENT (messagerie descendante avec pièces jointes)

> **ADDITIF STRICT (§1.5).** Quatre routes NEUVES sous `/mail`, aucun champ existant modifié, aucune
> clé renommée ni retirée, **aucun gate de version**. Un client ANTÉRIEUR ne les appelle pas et se
> comporte exactement comme avant ; un client NOUVEAU face à un serveur ancien reçoit 404 et affiche
> une enveloppe muette (`fetch_mail_badge` émet `0, 0` — cf. `network_manager.gd`). Le serveur peut
> donc partir **avant** le build client, et c'est l'ordre recommandé.

### 1. ⚠️⚠️ DÉROGATION À LA RÈGLE R4 — LA PREMIÈRE DE CONTENU, ET ELLE EST BORNÉE

La règle R4 (« le serveur ne renvoie JAMAIS de texte affichable ») existe parce que le client est
traduit en trois langues et que le serveur ne sait pas laquelle. Le **corps** et le **titre** d'un
pli y dérogent : ce sont des textes LIBRES écrits par un opérateur humain, transportés tels quels.

C'est **exactement** le précédent des messages du Chat (§8.20), qui transportent le texte des
joueurs — la nouveauté n'est pas le mécanisme, c'est l'auteur.

**La dérogation porte sur le CONTENU, jamais sur le CHROME ni sur la MISE EN FORME :**

| | Origine | Traduit ? |
|---|---|---|
| `title` / `body` d'un pli | texte libre de l'opérateur | ❌ affiché tel quel |
| libellés, boutons, statuts, refus | clés i18n `MAIL_*` | ✅ FR / EN / IT |
| raisons de refus (`expired`…) | constantes canoniques | ✅ le client choisit la clé |

**Garde côté client, NON NÉGOCIABLE** : `mail_modal.gd` rend le corps dans un `RichTextLabel` avec
**`bbcode_enabled = false`**. Un opérateur ne doit pas pouvoir styler, et un compte d'administration
compromis ne doit pas pouvoir injecter du balisage dans un client. Côté panel, l'échappement Jinja
est actif et **aucun gabarit du courrier ne contient `|safe`** (contre-épreuve structurelle, sur le
gabarit privé de ses commentaires).

**v1 assume que Hakim écrit ses courriers en français.** Les courriers SYSTÈME multilingues (à
`title_key`) viendront avec l'envoi de masse — le champ `kind` leur est déjà réservé.

### 2. Les quatre routes (toutes derrière `get_current_user`)

**Le destinataire ne voit que SON courrier** : chaque requête filtre `user_id == current_user.id`.
C'est la frontière de confidentialité du chantier.

| Route | Réponse |
|---|---|
| `GET /mail` | `{"mails": [{id, kind, title, body, coins_attached, created_at_epoch, expires_at_epoch, read, claimed}]}` — NON EXPIRÉS, plus récent d'abord, **50 max** |
| `GET /mail/badge` | `{"unread": int, "claimable": int}` |
| `POST /mail/{id}/read` | `{"ok": true}` · inexistant / expiré / pas à moi → `{"ok": false}` |
| `POST /mail/{id}/claim` | `{"claimed": true, "coins": int, "balance_after": int}` · sinon `{"claimed": false, "reason": …}` |

⚠️ **Epochs `int` PURS** (piège §5). `read` et `claimed` sont des **booléens**, pas des dates : le
client n'a rien à faire de l'instant de lecture.

### 3. ⚠️ AUCUN ORACLE — `unavailable`

`reason` ∈ `no_attachment` | `already_claimed` | `expired` | `unavailable`.

**`unavailable` = « inexistant » OU « pas à moi », indistinguablement** (patron §8.116/§8.126) : on
ne confirme jamais l'existence d'un id qu'on n'a pas le droit de lire. Les deux cas passent par la
même fonction et rendent le même objet — contre-épreuve qui compare les deux réponses.

**Ordre des refus**, et c'est une décision produit : `no_attachment` → `already_claimed` → `expired`.
Un message simple expiré dit « pas de pièce jointe » (rien n'a été perdu) ; un pli réclamé PUIS
expiré dit « déjà réclamé » (c'est un succès passé, pas une occasion manquée).

### 4. Le claim : idempotent, atomique, SANS multiplicateur

```
_lock_user(joueur)  →  row lock du pli (with_for_update)  →  can_claim  →  record_coins  →  claimed_at  →  UN commit
```

⚠️ **Verrou JOUEUR d'abord, partout dans le dépôt** — l'achat boutique, le claim de mission et
l'ajustement de Coins de l'administration font tous de même. L'ordre inverse serait un interblocage
en embuscade, invisible dans toute trace le jour où il se produirait.

⚠️⚠️ **AUCUN MULTIPLICATEUR DE PASS** sur `mail_reward`, contrairement à `mission_claim`. Une
COMPENSATION n'est pas un gain de jeu : un détenteur de Pass Infinity à qui on rend 200 Coins perdus
dans un incident en reçoit **200**. Sinon l'opérateur ne peut plus annoncer un montant, et deux
joueurs dédommagés du même préjudice recevraient des sommes différentes. Contre-épreuve dédiée, plus
un contrôle STRUCTUREL : `endpoints/mail.py` n'importe même pas `pass_catalog`.

### 5. Raison canonique d'économie

`REASON_MAIL_REWARD = "mail_reward"` — **CRÉDIT UNIQUEMENT** (le courrier ne débite jamais),
`ref = "mail:<id>"` (source unique `mail_rules.mail_ref`). Placée dans `ALL_REASONS` **juste après**
`REASON_ADMIN_ADJUST` : même famille (l'argent du commandement), la différence tient à la forme.
Clé i18n cliente : `PROFILE_FIN_SRC_MAIL_REWARD` = FR « COURRIER DU COMMANDEMENT » · EN « COMMAND
MAIL » · IT « POSTA DEL COMANDO », **embarquée dans CE build**.

### 6. §8.143 SOLDÉ — le tableau des écrans muets n'a plus lieu d'être

Le tableau du §8.143 §5 ci-dessus est **caduc**. Ce build traite `closed` + `cause` sur les quatre
chemins, et **aucun** ne peut plus rester muet :

| Chemin | Face à `closed` | Face à une raison INCONNUE |
|---|---|---|
| Recherche de partie | `MM_CLOSED_MAINTENANCE` / `MM_CLOSED_FEATURE`, en **OR** | `MM_QUEUE_FAILED` |
| Créer un salon privé | idem | `MM_UNKNOWN_REFUSAL` (branche par défaut **AJOUTÉE**) |
| Rejoindre un salon privé | idem | `MM_UNKNOWN_REFUSAL` (branche par défaut **AJOUTÉE**) |
| File d'ÉQUIPE | idem | `SQUAD_ERR_UNAVAILABLE` |

⚠️ Une fermeture s'affiche en **OR** (avertissement) et non en rouge : c'est une info de SERVICE,
pas une panne. Une `cause` inconnue retombe sur « temporairement fermé », jamais sur rien.

> 🩸 **Défaut trouvé en le vérifiant** : la file d'ÉQUIPE était muette elle aussi, alors que la
> cartographie du §8.143 la déclarait « acceptable ». `_on_squad_state` posait le message PUIS
> appelait `_render()`, qui remet `_status_label.visible = false`. Un membre recevant `not_leader`,
> une escouade `full` ou une file fermée ne voyait **rien**. Corrigé en inversant l'ordre.
> Contre-épreuve : `frontend/tools/test_mm_refusals.gd` (77 contrôles, 4 chemins × toutes les
> raisons + une inconnue + une réponse vide, × 3 langues).

---

## ☢️ §8.145 — ZONE LÉTALE : l'évènement structuré `zone_damage` (2026-08-09)

> Règles & moteur : **§8.145 de [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md)**.
> Rendu client : **§8.145 de [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)**.
> **Strictement ADDITIF (règle §1.5)** : aucune clé de payload existante n'est renommée, supprimée ni
> changée de forme. Un client antérieur IGNORE simplement le nouveau code (repli `_` de
> `war_feed._system_event_entry` → entrée `system` brute, aucune perte, aucun crash).
> ⚠️⚠️ **Changement de GAMEPLAY : client et serveur partent ENSEMBLE** (gate de version WS, §9).

### 1. Le nouveau code système (pipeline `system_events` existant, PUBLIC)

```json
{"code": "zone_damage", "territory_id": "<tid>", "owner_id": 42, "amount": 1, "ravaged": false}
```

| Champ | Type | Sens |
|---|---|---|
| `territory_id` | `str` | le territoire réellement frappé |
| `owner_id` | `int \| null` | **propriétaire AVANT le dégât** (`null` = territoire neutre). C'est lui qui porte l'attribution ; **jamais** le joueur dont c'est le tour. |
| `amount` | `int` | pertes **RÉELLES** — bornées par la garnison (`min(registre, garnison)`), donc jamais un chiffre que le plateau ne peut pas montrer. Vient de `zone_settings.ZONE_DAMAGE["per_player_turn"]` : le client n'affiche **aucun « −1 » en dur**. |
| `ravaged` | `bool` | le territoire est tombé à 0 et **redevient NEUTRE**. Servi par le SERVEUR plutôt que réinféré côté client depuis « garnison 0 + owner null » — une inférence de moins. |

**Émis** au début du tour de CHAQUE joueur, **une fois par territoire réellement frappé** :
- ⛔ **jamais** pour un territoire PROTÉGÉ (Culte de l'Isotope / `immune_to_contamination`) — ceux-là
  émettent `zone_protected`, inchangé ;
- ⛔ **jamais** pour un territoire déjà VIDE (neutre sans garnison) : rien à perdre, rien à raconter.

**Aucune ligne `system_messages` LEGACY n'accompagne `zone_damage`** (contrairement à `zone_grew`).
Volontaire : `war_feed.parse` IGNORE les `system_messages` dès qu'un `system_events` est présent, et
la dérivation cliente qui produisait ces lignes est SUPPRIMÉE (cf. FRONTEND §8.145) — une ligne
legacy ne servirait qu'à doubler l'entrée sur les clients à jour.

### 2. Ce qui NE change PAS dans le contrat

- `contamination_zone` (`territories` / `next_territories` / `probability`) : forme INCHANGÉE.
- `zone_protected`, `zone_grew`, `zone_forecast` : INCHANGÉS.
- `GameStatistics.zone_kills_by_player` (Métrique A §8.35) : **même sémantique** (« unités de CE
  joueur détruites par la zone », ventilées par PROPRIÉTAIRE). Seul le MOMENT du comptage change —
  à chaque tour de joueur au lieu du seul tour du propriétaire. Les valeurs montent donc plus vite ;
  aucun consommateur (HUD Intel, Rapport Post-Op, `WARROOM_LBL_ZONE`) n'a besoin d'être touché.
- Les **objectifs** continuent d'ignorer ces kills (`build_context` ne lit que `combat_kills_by_player`).

### 3. Volume de diffusion

À 5 joueurs sur une zone de 6 territoires, un round produit jusqu'à **30** `zone_damage` (6 par tick
× 5 ticks), contre ~6 auparavant. Ils voyagent dans le tampon `pending_system_events` déjà existant,
drainé par les sites qui attachent `system_messages` — **aucun message périodique neuf**, aucune
nouvelle route. Le journal client les catégorise en `zone` (filtrable). À surveiller au playtest :
c'est le seul poste de volume du chantier, et il est CONSTATÉ ici plutôt que découvert plus tard.

---

## 💰 §8.147 — MODÈLE ÉCONOMIQUE : Pass UNIQUE, accès temporaire aux skins, FRAIS D'INSCRIPTION (2026-08-10)

> Règles & barèmes : **§8.147 de [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md)**.
> Exploitation (les 3 réglages, les 2 courbes) : **[`ADMINISTRATION.md`](ADMINISTRATION.md) §33-§35**.
> **Strictement ADDITIF (règle §1.5)** : aucune clé de payload existante n'est renommée, supprimée
> ni changée de FORME. Ce qui change, ce sont des **valeurs** (`pass_tier` vaut désormais `"season"`
> partout) et une **cardinalité** (`pass_tiers()` passe de 3 entrées à 1) — jamais un type.
> ⚠️⚠️ **CLIENT ET SERVEUR PARTENT ENSEMBLE** (gate de version WS §9) : la vitrine du Pass, les prix
> de frais affichés et les états d'accès des skins sont une seule release.
> ⚠️ **DÉPLOIEMENT NEUTRE** : les trois frais sont déployés **à 0** (`fallback: 0`). Le jour J,
> aucun joueur ne ressent autre chose que la vitrine du Pass — pas un bloc `fee` non nul, pas une
> ligne `entry_fee`, pas un refus `insufficient_coins`. L'économie s'allume **au panel**.
> Tous les montants (Coins, prix, frais) sont des **`int` PURS** (piège JSON float §5) ; les
> multiplicateurs ne franchissent le fil qu'en **pourcentages ENTIERS**.

### 1. `pass_tiers()` — 3 entrées → **1**, mais ça RESTE une LISTE

`GET /profile/pass` clé `tiers` : la forme d'un élément est **INCHANGÉE**
(`{ id, name_key, rank, benefits: [ { id, kind, value, desc_key } ] }`), et la valeur reste une
**LISTE JSON**. Un client qui l'itère ne casse pas — il dessine simplement une carte au lieu de
trois. C'est la seule tolérance que §1.5 accorde à une réduction de cardinalité, et elle n'est
acceptable que parce que client et serveur partent ensemble.

L'unique entrée : `id: "season"`, `name_key: "SHOP_ITEM_PASS_SEASON_NAME"`, `rank: 1`.
**`rank` est CONSERVÉ** bien qu'il ne départage plus rien (trois lectures s'y appuient : le tri de
`TIER_IDS`, la couronne de la vitrine, la règle d'octroi de `pass_grant`).

**DIX avantages**, ids **STABLES**, dans cet ordre — les cinq axes CHIFFRÉS d'abord, les déblocages
ensuite. Les deux ids AJOUTÉS (`hero_xp_mult`, `level_coins`) s'**insèrent** sans renommer ni
déplacer les trois d'origine :

| `id` | `kind` | `value` servie | Sens |
|---|---|---|---|
| `xp_mult` | `percent` | `50` | XP de PROFIL ×1.50 |
| `hero_xp_mult` | `percent` | `100` | **NOUVEL AXE** — XP de HÉROS ×2 |
| `mission_mult` | `percent` | `300` | Coins de MISSIONS ×4 |
| `level_coins` | `percent` | `300` | **NOUVEL AXE** — Coins de PALIER de niveau ×4 |
| `hero_coins` | `range` | `[4, 20]` | Coins par niveau de HÉROS (base 1-5 × 4) |
| `faction_grants` | `grant` | `""` | TOUS les personnages payants |
| `skin_access_all` | `grant` | `""` | TOUTES les skins achetables, en PRÊT (§3) |
| `season_skin` | `grant` | `""` | skin exclusif de saison, crédité à l'octroi |
| `season_title` | `grant` | `""` | titre exclusif de saison (§4) |
| `fee_relief` | `grant` | `""` | exonérations de FRAIS (§5) |

⚠️ **Un `×4` s'expose en `+300` `percent`, pas en `×4`** : une seule forme d'affichage sur toute la
carte, jamais un « ×4 » à côté d'un « +50 % » que le joueur devrait convertir de tête. Un `kind`
inconnu d'un client ancien retombe sur le seul `desc_key` (tolérance §8.106).

⛔ **Aucun avantage affiché n'est non câblé** — les dix ont leur point d'application ET leur
contre-épreuve de crédit (leçon `radioactive_damage_multiplier`, §8.145 : une règle écrite mais
jamais implémentée).

**Le collapse est une décision de LECTURE, pas une migration.** `pass_catalog.tier_of` rend
`"season"` pour **TOUT Pass actif**, quel que soit le contenu de `users.pass_tier` (`"plus"`,
`"premium"`, `"infinity"`, `""` du Pass Spécial d'origine, ou déjà `"season"`) : le registre ne
contenant plus qu'une entrée, tout `pass_tier` historique en est absent et retombe sur
`LEGACY_TIER = "season"` — le repli LEGACY d'origine, mécanisme INCHANGÉ. **Aucun UPDATE de masse,
aucun script**, la colonne reste une trace d'achat. Un détenteur de Plus (7,99 €) est donc **promu**
jusqu'à son échéance : plus généreux, jamais moins. ⚠️ Ce que le collapse NE rétroagit PAS : les
personnages **déjà tirés** (`pass_faction_grants`) — un ex-Plus garde son unique personnage offert,
le tirage ayant eu lieu à l'achat. Les skins prêtées et les exonérations de frais, elles,
s'appliquent immédiatement (elles se LISENT, elles ne se tirent pas).

### 2. `GET /profile/pass` — deux compteurs de gains ADDITIFS + le titre de saison

```jsonc
{
  "active": true, "expires_at": "…Z", "tier_id": "season",
  "tiers": [ … 1 entrée … ], "granted_items": [ … ],
  "season_title_id": "pass:s3",          // NOUVEAU — "" si aucun Pass ACTIF
  "gains": {
    "bonus_xp_total": 0,                 // inchangé
    "bonus_mission_coins_total": 0,      // inchangé
    "hero_coins_with_pass_total": 0,     // inchangé (TOTAL assumé, pas un différentiel)
    "bonus_hero_xp_total": 0,            // NOUVEAU — différentiel de l'axe XP héros
    "bonus_level_coins_total": 0,        // NOUVEAU — différentiel de l'axe Coins de palier
    "coins_spent_on_pass": 0             // inchangé
  }
}
```

Colonnes ADDITIVES `users.pass_bonus_hero_xp_total` / `users.pass_bonus_level_coins_total`
(`Integer NOT NULL DEFAULT 0`, auto-migrées au boot ; archive de parité
**`backend/migration_pass_season.sql`**). **MÊME discipline qu'au §8.106** : on n'y stocke que le
**SURPLUS**, mesuré **AU POINT D'APPLICATION** (`state_manager` pour l'XP héros,
`rewards.apply_xp_and_levels` — qui renvoie désormais la clé additive `base_coins_earned` — pour les
paliers), **jamais recalculé après coup**. ⚠️ **Aucune donnée rétroactive** : la mesure démarre à
cette mise à jour, un Pass antérieur affiche 0 sur ces deux lignes (le client l'explicite,
`PASS_GAINS_NOTE`). Sans ces deux clés, l'onglet PASS mentirait **par omission** — trois gains
affichés sur cinq.

`season_title_id` est un champ **DÉRIVÉ, jamais stocké** : `"pass:s<index de saison courante>"` tant
que le Pass est ACTIF, `""` sinon. Il est exposé **ici et non dans `masteries_summary`** — ce n'est
pas un titre de maîtrise de faction, et le palmarès de maîtrise l'écarte explicitement.

### 3. `GET /shop/inventory` — `skin_access`, et la PURGE PARESSEUSE des skins

Champ ADDITIF **`skin_access: { "<skin_id>": "owned" | "pass" }`** (cf. §9.3). Trois titres existent
côté serveur (`access.skin_access` / `skin_access_map` / `catalog_skin_access`, patron EXACT de
`faction_access` §8.109) mais **seuls deux franchissent le réseau : `locked` est OMIS** — l'absence
d'une clé EST le verrou, et la réponse reste courte.

- **`owned`** — ligne d'inventaire, quantité > 0. **DÉFINITIF, indépendant du Pass** : ce qui a été
  acheté pendant un Pass survit à son expiration. C'est la boucle hybride, et c'est elle qu'il faut
  rendre visible en vitrine (« DÉBLOQUÉ AVEC LE PASS » + le prix d'achat permanent à côté).
- **`pass`** — Pass ACTIF, dont le niveau porte `skin_access_all`, ET article de catégorie `skin`
  **encore `purchasable`**. ⚠️ **Cette dernière condition EST la promesse d'exclusivité** : les skins
  exclusifs des saisons PASSÉES (`skin_pass_s*`, seedés `purchasable=false`) ne sont **JAMAIS**
  prêtés à qui ne les a pas gagnés.
- ⚠️ **PÉRIMÈTRE** : les **FINISHERS** (`category == "finisher"`) ne sont pas des skins et le Pass
  ne les prête pas — accessibles POSSÉDÉS seulement.

**FIN D'ACCÈS = PURGE PARESSEUSE, aucun cron, aucune colonne nouvelle** (patron §8.109 pour les
factions, §8.135 pour les titres) : la vérité se **recalcule à la lecture**. Deux sites, et deux
seulement :

| Site | Pourquoi lui |
|---|---|
| `shop._inventory_response` (`GET /shop/inventory`, et donc aussi la réponse de `/shop/equip`) | c'est la lecture que le joueur provoque en ouvrant sa boutique |
| `sockets/router._load_equipped_skin` (draft / lancement de salle) | **le plus important des deux** : c'est lui qui décide de ce que les AUTRES JOUEURS voient en partie |

À l'expiration du Pass, la première de ces lectures constate que la skin équipée est retombée
`locked`, **SUPPRIME la ligne `EquippedSkin`** (on ne l'ignore pas : une ligne fantôme ferait
« remonter » la skin le jour d'un nouveau Pass, sans que le joueur l'ait rééquipée) et le joueur
réapparaît avec son apparence par défaut. Côté contrat : `equipped` (§8.69) et
`PlayerState.equipped_skin` reprennent leur valeur vide — **aucune clé nouvelle, aucun événement**.

### 4. Le titre de saison — source `"pass"` dans `mastery`

Le format `"<source>:<key>"` d'`equipped_title` (§8.135 §8) était prévu pour ça : la source
**`"pass"`** s'ajoute, avec une clé `s<N>` (N = index 1-based de la saison). ⚠️ **Sémantique
d'ÉGALITÉ, pas de palier** — contrairement aux titres d'événement, `s3` n'est portable que **sous la
saison 3**, pas « à partir de ». Le titre est **PORTABLE tant que le Pass est ACTIF** et **expire
avec lui**, re-validé À LA LECTURE comme tous les autres : `resolve_equipped_title` fait retomber le
champ à `""` tout seul (§8.135 §5 — « jamais de titre fantôme »). **Zéro colonne, zéro stockage.**

### 5. FRAIS D'INSCRIPTION — le prix s'affiche **AVANT** l'action

Trois surfaces OPT-IN sont concernées, et **elles seules**. ⛔ **Casual FFA et CLASSÉE : GRATUITES,
TOUJOURS** — `api/v1/endpoints/matchmaking.py` n'importe même pas le module des frais (contrôle AST : ni import, ni appel `charge_fee`). Les playlists
d'équipe **sans traître** (`duo_2v2`) restent gratuites elles aussi.

Le bloc de prix canonique est **`{ "fee": int, "fee_with_pass": int }`** (`fees.fee_block`) :
`fee` = ce que **CE lecteur** doit (remise déjà appliquée s'il a un Pass) ; `fee_with_pass` = ce que
la même action coûterait AVEC un Pass — c'est l'argument de vente, et c'est ce qui permet au client
d'afficher un prix barré **sans connaître la moindre règle de remise**.
**Les deux valent `0` quand le frais est à 0 → le client n'affiche RIEN** (surtout pas « 0 Coins »).

| Route | Ajout ADDITIF | Note |
|---|---|---|
| `GET /squad/playlists` | **par playlist**, dans chaque spec : `fee` + `fee_with_pass` | les playlists gratuites portent `0/0`, comme toutes les autres à frais 0. Le tarif dépend du LECTEUR → **calculé HORS du cache 60 s** de l'endpoint |
| `GET /squad/playlists` | **au niveau racine** : `"event_queue_fee": { fee, fee_with_pass }` | c'est ce hub-là qui construit l'écran ÉVÉNEMENTS (onglet BONUS) — le client doit connaître le prix **en dessinant** le bouton ENTRER, pas en le cliquant. ⚠️ **UN SEUL bloc pour TOUS les événements** : le registre ne distingue pas encore les événements entre eux (une seule activité `event_queue`). La forme est prête pour une entrée par événement le jour venu |
| **TOUTE réponse d'état de compagnie** (`GET /company/mine`, `GET /company/{tag}`, `POST /company/join`, création, départ, exclusion… — tout ce qui passe par le constructeur commun `_state`) | `join_fee` + `join_fee_with_pass` | **HORS** du payload de compagnie, parce qu'ils ne décrivent PAS la compagnie (toutes ont le même tarif) : ils décrivent ce que L'ADHÉSION coûterait AU LECTEUR. Servis **aussi** sur les branches `{"company": null}` — `"unavailable"`, `"no_company"`, `"insufficient_coins"` (zéro-4xx §8.112).<br>⚠️ **POURQUOI SUR TOUTES LES RÉPONSES ET PAS SEULEMENT SUR LA FICHE PUBLIQUE** : le formulaire d'adhésion part d'un **CODE à 5 caractères**, jamais d'un tag. Adossé au seul `GET /company/{tag}`, le tarif serait resté invisible à tout joueur n'ayant pas d'abord ouvert une fiche publique — il aurait découvert le péage **au moment de cliquer**, ce que le §7.3 interdit. L'état « sans compagnie » est précisément celui à partir duquel le formulaire est rendu : c'est donc lui qui doit porter le prix.<br>⚠️ Le tarif est **déjà celui du lecteur** (un détenteur de Pass lit `250 / 250`, pas `500 / 250`). Coût nul tant que le frais dort à 0 : aucune requête n'est faite pour servir deux zéros. |

⚠️ **Aucun bloc `fee` sur les routes `/trench/*`** — décision de conception, pas un oubli : le prix
d'entrée de l'événement vit sur `GET /squad/playlists` (ci-dessus), l'unique point de configuration
publique du hub. Deux endroits auraient signifié deux façons de calculer le même prix.

**Remise du Pass : calculée en UN SEUL point** (`fees.effective_fee`), jamais rejouée par un
endpoint. Politiques : `event_queue` → **`free`** (entrée gratuite, avantage contractuel du Pass) ;
`company_join` et `br_search` → **`discount_50`**, moitié **ARRONDIE AU SUPÉRIEUR** (`ceil`).
⚠️ **L'arrondi haut est délibéré** : avec `floor`, un frais de 1 Coin deviendrait GRATUIT sous Pass
— la remise cesserait d'être « la moitié » pour devenir « la totalité » sur les petits montants, et
le joueur verrait un péage annoncé qui ne se produit jamais. `ceil` garde « -50 % » vrai à tous les
montants (1 → 1, 3 → 2, 100 → 50).

**Périmètre « Battle Royale » = DÉRIVÉ du registre `teams`**, jamais une liste d'ids en dur :
`fees.br_playlists(TEAM_PLAYLISTS)` = les playlists à `traitor: true` (aujourd'hui `squad_3v3`
seule). Un futur format BR ajouté au registre d'équipe devient payant **PAR CONSTRUCTION**.

### 6. Refus **`insufficient_coins`** — raison NOUVELLE, sur trois shapes EXISTANTS

Convention **zéro-4xx nominal (§8.112)** partout : un solde insuffisant est un état NOMINAL, pas une
erreur du client. HTTP **200**, shape inchangée, raison additive (précédent exact : `closed` §8.143).
⚠️ Le refus est prononcé **AVANT** tout `record_coins` — on n'atteint jamais le clamp-à-zéro
d'`economy` (qui journalise un WARNING « l'appelant doit vérifier la solvabilité AVANT » : c'est un
filet comptable, pas un chemin nominal).

| Surface | Réponse |
|---|---|
| `POST /company/join` | shape `CompanyStateResponse` (§8.126 §2) + `{"reason": "insufficient_coins", "fee": N, "balance": M}` |
| `POST /trench/queue` | `{"queued": false, "reason": "insufficient_coins", "fee": N, "balance": M}` |
| `POST /squad/queue` | solo → `{"squad": false, "reason": "insufficient_coins", "who": "<pseudo>", "fee": N}` · escouade → l'état d'escouade habituel PLUS ces trois clés |

⚠️⚠️ **La file d'équipe est la seule à porter `who`, et la seule à NE PAS porter `balance`** — les
deux décisions sont volontaires :
- **`who` est le pseudo du membre BLOQUANT.** Un « solde insuffisant » anonyme dans une escouade de
  trois, c'est trois joueurs qui se regardent : personne ne sait qui doit agir, et le groupe se
  disloque. Le pseudo ne divulgue rien de neuf — l'écran d'escouade affiche déjà la liste des
  membres (§8.124).
- **Le SOLDE d'un tiers n'est PAS exposé.** Savoir que quelqu'un ne peut pas payer suffit ;
  connaître son porte-monnaie ne regarde personne.
- **Chaque membre est évalué selon SON PROPRE Pass** : dans une escouade mixte, l'un paie la moitié
  et l'autre le plein tarif. Le frais n'est donc pas « le prix de la salle » mais la somme de N prix
  individuels, et **un seul insolvable bloque tout le monde** — jamais une salle à moitié débitée.
- **Ordre STABLE** (celui de l'escouade) : deux tentatives successives nomment le même joueur.

Côté client, un `insufficient_coins` s'affiche en **OR** (une info, pas une panne) avec le rappel
« le mode CASUAL reste gratuit » : jamais un cul-de-sac.

### 7. `DELETE /trench/queue` — clé ADDITIVE `refunded`

`{"left": true, "refunded": <int>}` — le montant **réellement rendu**, `0` si rien n'était dû
(frais à 0, ou consigne déjà consommée). Les shapes de refus (`assigned`, etc.) sont **inchangés**.

Le cycle diffère **volontairement** entre les deux surfaces payantes, et il ne faut pas les
mélanger :

| Surface | Débit | Remboursement |
|---|---|---|
| **Événement** (Tranchée, futurs événements bonus) | à la **MISE EN FILE** — c'est le moment de l'engagement, et la Tranchée forme vite | **COMPLET** : annulation, TTL/heartbeat expiré, purge au démarrage de l'API. Chaque chemin de purge rembourse |
| **Battle Royale** (playlists à traître) | à la **FORMATION de la salle** (`matchmaker_runner`) ; à la mise en file, **solvabilité seulement** | **VIDE PAR CONSTRUCTION** : un ticket purgé sans partie n'a jamais rien débité, il n'y a rien à rendre |

⚠️ **L'idempotence du remboursement vit dans une CONSIGNE Redis `mm:fee:<uid>`** (TTL 1 h), **pas**
dans le ticket de file et **surtout pas** dans une somme du livre de comptes (règle §8.106 : on ne
recalcule jamais un montant en sommant des deltas). Motif MESURÉ : le ticket `mm:ticket:<uid>` a un
TTL de 15 s rafraîchi par le heartbeat — un joueur qui **ferme le jeu** en file cesse de battre,
Redis efface le ticket **et avec lui le montant à rembourser**, or c'est précisément le cas qu'il
faut rembourser. La consigne est une clé DISTINCTE qui survit au ticket ; elle se **consomme par un
`DELETE`**, dont Redis renvoie le nombre de clés réellement supprimées → deux remboursements
concurrents, un seul crédite. Elle est consommée sur les DEUX issues (partie formée → on jette, le
frais est acquis ; pas de partie → on rembourse).

⚠️ **Un débit BR qui échoue à la formation N'ANNULE PAS la salle** (décision assumée) : entre la
vérification de solvabilité et la formation, un joueur a pu vider son solde. On journalise un
WARNING, et on continue — **la partie prime sur le péage**. Le `try/except` est PAR JOUEUR : l'échec
de l'un ne prive pas les autres. Aucune trace réseau, aucune raison nouvelle.

### 8. Économie — **14ᵉ raison canonique** `entry_fee`

`REASON_ENTRY_FEE = "entry_fee"`, placée dans `ALL_REASONS` **en tête des DÉPENSES**, après
`REASON_COIN_PACK` et **avant** `REASON_SHOP_PURCHASE` : un frais d'inscription n'est pas un achat —
on n'en repart avec aucun objet. Le placer là groupe les sorties tout en gardant visible qu'il
s'agit d'une autre nature de dépense (onglet FINANCES, ordre canonique §8.106).

⚠️ **DOUBLE SIGNE** — la 2ᵉ raison du dépôt dans ce cas, après `admin_adjust` (§8.142 §5), et pour
un motif différent : le **DÉBIT** part à l'engagement, le **CRÉDIT** revient si l'activité n'a pas
lieu. Rembourser sous la **MÊME** raison plutôt qu'inventer une raison miroir a deux vertus :
`split_earned_spent` sommant **par SIGNE**, un aller-retour s'annule tout seul dans les totaux ; et
le relevé du joueur raconte l'histoire vraie — « −50 » puis « +50 », au lieu de deux lignes qui
n'auraient pas l'air liées.

`ref` = **`"<activity>:<contexte>"`**, et c'est LUI que la télémétrie découpe pour ventiler les
frais par activité (il n'y a **aucune comptabilité parallèle** — le livre de comptes raconte tout) :

| Activité | `ref` réellement écrit |
|---|---|
| `company_join` | `"company_join:<TAG>"` |
| `event_queue` | `"event_queue:trench_week"` (l'id d'ÉVÉNEMENT — les futurs événements bonus réutilisent la même activité, aucun code nouveau par événement) |
| `br_search` | `"br_search:room<id de salle>"` |

Clé i18n cliente : **`PROFILE_FIN_SRC_ENTRY_FEE`** (« FRAIS D'INSCRIPTION »), FR/EN/IT.

⚠️ **Un frais à 0 est un NO-OP TOTAL** : aucune ligne au livre de comptes, aucune écriture, rien
(`record_coins` est déjà no-op à delta 0, et `charge_fee` évite jusqu'à l'appel). C'est ce qui rend
le déploiement à frais 0 rigoureusement **invisible** — à 0, le mécanisme ne laisse aucune trace de
son existence.

### 9. Ce qui NE change PAS

- **`has_active_pass` / `pass_expires_at`** (`/shop/inventory`, `/shop/purchase/*`) : forme et
  sémantique INCHANGÉES. `special_pass_expires_at` reste la colonne d'horloge, `current_season_end_dt()`
  l'échéance d'un achat.
- **Le gate `PAYMENTS_ENABLED`** : `POST /shop/purchase/fiat` rend toujours **501**. Le Pass unique
  est **visible et inachetable** ; l'octroi admin (§8.146) reste LE chemin de test. **Ce chantier ne
  touche pas aux paiements.**
- **Le gate d'ACHAT d'un skin** (possession DÉFINITIVE du personnage exigée, §8.108) : pas un
  caractère.
- **`/matchmaking/*` et les salons privés** : aucun frais, aucune raison nouvelle, aucun champ.
- **`GET /profile/finance`** : shape inchangée — `entry_fee` y apparaît comme n'importe quelle
  source, par le mécanisme générique d'`ALL_REASONS`.
- **L'ordre canonique `base × pass × événement`** de l'XP de profil (§8.132) : le Pass d'abord,
  l'événement ensuite. **NE PAS l'inverser** — le surplus mesuré doit rester le gain PROPRE du Pass.
  ⚠️ Au 2026-08-10, **aucun événement ne multiplie l'XP de HÉROS** (`events.py` ne porte que
  `xp_multiplier` et `hero_coins_multiplier`) : il n'y a donc pas d'ordre à respecter sur l'axe neuf.
  Le jour où un événement le fera, il devra venir **APRÈS** le Pass, comme partout ailleurs.

### 10. Rappel de typage (§5)

Coins, frais, prix, `fee`, `fee_with_pass`, `join_fee`, `refunded`, `balance`, compteurs de gains :
**`int` PURS**, sans exception. Les multiplicateurs du registre sont des **flottants côté serveur**
et ne franchissent JAMAIS le fil tels quels — `pass_tiers()` les convertit en pourcentages ENTIERS
(1.50 → 50, 2.00 → 100, 4.00 → 300), forme qu'attendent aussi les libellés i18n en `%d`.

---

## 🩹 §8.148 — CORRECTIFS ÉCONOMIQUES : `fee_base`, `event_signup`, surplus du Pass (2026-08-11)

> **Tout est ADDITIF (§1.5).** Aucun champ existant ne change de sens ni de nom — c'est ce qui
> permet à un client déployé de continuer à fonctionner, et c'est délibéré : la tentation était de
> faire porter le plein tarif à `fee` (que tous les clients affichent comme « ce que je vais
> payer »), ce qui aurait cassé les trois surfaces à péage d'un coup.

### 1. Blocs de frais — le champ `fee_base`

`fees.fee_block()` rend désormais **trois** entiers, et la sémantique est la MÊME sur les quatre
surfaces (recherche BR, file d'événement, adhésion à une compagnie, inscription à un événement) :

| Champ | Sens |
|---|---|
| `fee` | ce que **CE lecteur** paie réellement (remise du Pass déjà appliquée) — *inchangé* |
| `fee_base` | **NOUVEAU** — le PLEIN TARIF, celui réglé au panel, sans aucune remise |
| `fee_with_pass` | ce que la même action coûterait AVEC un Pass — *inchangé* |

Déclinaisons : `GET /squad/playlists` → `playlists[<id>].fee_base` et `event_queue_fee.fee_base` ;
`/company/*` → `join_fee_base` (même préfixe que ses voisins).

🩸 **Pourquoi le champ existe.** `ceil(n/2)` **n'est pas inversible** : 49 et 50 remisent tous deux
à 25. Un client qui doublerait le prix remisé afficherait un plein tarif faux une fois sur deux.
Sans `fee_base`, aucune surface ne pouvait expliquer « 50 réglé au panel, 25 en jeu ».

**Règle d'affichage du client** (une seule, `WarzoneUI.fee_pass_hint`) : `fee_base <= 0` → rien ·
`fee <= 0 < fee_base` → « OFFERT · PASS » · `fee_base > fee` → « TARIF PASS · AU LIEU DE N » ·
sinon `fee_with_pass < fee` → l'argument de vente. ⛔ Un frais à 0 ne dit **jamais** rien.

### 2. `POST /events/{event_id}/signup` — inscription à l'occurrence courante

Zéro-4xx (§8.112) : **200** dans tous les cas nominaux. Idempotent.

```jsonc
{"enrolled": true,  "fee_paid": 100, "window_start_epoch": 1756000000}   // inscription faite
{"enrolled": true,  "already": true, "window_start_epoch": 1756000000}   // déjà inscrit
{"enrolled": false, "reason": "event_closed"}                            // aucune occurrence
{"enrolled": false, "reason": "insufficient_coins", "fee": 100, "balance": 40}
```

⚠️ **Le client n'envoie AUCUNE fenêtre** : le serveur résout l'occurrence active lui-même
(`events.active_events()`). Il est donc impossible de s'inscrire à la mauvaise occurrence, et
l'identité de l'inscription ne dépend pas de l'horloge du poste du joueur.

**Bloc d'état** joint à `GET /squad/playlists` (le hub qui dessine l'onglet BONUS) :

```jsonc
"event_signup": {"fee": 100, "fee_base": 100, "fee_with_pass": 0,
                 "required": true, "enrolled": false}
```

`required` répond à la seule question du client : « dois-je afficher une étape ? ». Il vaut `false`
à frais nul **et** pour un détenteur de Pass (exonéré) → aucune friction, aucune étape.

**Nouveau refus de `POST /trench/queue`** — le gate d'entrée, entre `in_room` et la file :

```jsonc
{"queued": false, "reason": "signup_required", "fee": 100, "event_id": "trench_week"}
```

Ordre complet des refus : `event_closed` → `banned` → `closed` (maintenance) → `in_room` →
**`signup_required`** → `insufficient_coins` (ticket de file).

### 3. `game_over.match_rewards` — le surplus du Pass, en clair

Trois champs additifs, présents sur **tous** les chemins de sortie (y compris bots et joueurs non
persistés, à 0) — un champ additif qui manque sur un seul chemin oblige chaque lecteur à défendre
les deux cas :

| Champ | Sens |
|---|---|
| `coins_pass_bonus` | surplus de Coins de **PALIER** dû au Pass sur ce match (0 sans Pass) |
| `hero_coins_pass_bonus` | surplus de Coins de **NIVEAU DE HÉROS** (idem) |
| `pass_xp_bonus_pct` | barème du Pass sur l'XP de profil, en **% de bonus ENTIER** (50) |

`pass_xp_bonus_pct` est servi **même sans Pass** : c'est lui qui permet au Rapport Post-Op
d'afficher, pour un non-détenteur *et seulement s'il a laissé le réglage `pass_hints` allumé*, ce
que le Pass lui aurait ajouté — **sans qu'aucun multiplicateur ne vive côté client**. Le client
applique un taux SERVEUR à un montant SERVEUR ; c'est la seule façon d'écrire cet argument de vente
sans rouvrir le trou que ce chantier vient de fermer.

### 4. Missions & carte du Pass

- `GET /missions` → chaque mission gagne **`reward_coins_pass`** = `floor(reward × mission_mult)`,
  calculé par la MÊME expression que le claim. Servi à tout le monde : à un détenteur il dit ce
  qu'il touchera, à un autre ce que le Pass ajouterait.
- `POST /missions/claim` → gagne **`reward_base`**, pour animer « base → payé » au moment exact où
  l'avantage se produit.
- `GET /profile/pass` → l'avantage `hero_coins` (kind `range`) gagne **`base_value`** = `[1, 5]`,
  la fourchette SANS Pass. Le libellé disait « X-Y au lieu de **1-5** » avec le « 1-5 » écrit en dur
  dans les trois traductions : exact aujourd'hui, faux au premier rééquilibrage du barème de base.
  C'était le **dernier** chiffre de gain codé côté client.

### 5. ⚠️ Piège JSON float (§5) — inchangé et re-vérifié

`fee_base`, `reward_coins_pass`, `reward_base`, `coins_pass_bonus`, `hero_coins_pass_bonus`,
`pass_xp_bonus_pct`, `window_start_epoch`, `base_value` : **`int` PURS**, sans exception.
`pass_xp_bonus_pct` est en particulier un **pourcentage entier** et non le multiplicateur flottant
du registre — la conversion se fait côté serveur, comme pour `pass_tiers()`.

---

## ⚙️🤖 §8.149 — RÈGLES EN SOUFFRANCE, BOUCLIER ANTI-RADIATIONS, BOTS V2 (2026-08-11)

> Règles & moteur : **§8.149 de [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md)**.
> Rendu client : **§8.149 de [`FRONTEND_INTERFACES.md`](FRONTEND_INTERFACES.md)**.
>
> **Tout est ADDITIF (§1.5)**, à une exception près, documentée en fin de section : le RETRAIT du
> champ mort `PlayerState.immune_to_contamination`.

### 1. `PlayerState` — deux champs pour la reprise de siège (LOT A)

| Champ | Type | Défaut | Sens |
|---|---|---|---|
| `afk_forced_turns` | `int` | `0` | Tours de CE joueur terminés de force par la minuterie **alors qu'il n'avait rien fait**. **CUMULÉ sur la partie, jamais remis à zéro** (« même NON consécutifs »). Un tour où il a AGI mais laissé filer le chrono n'incrémente rien. |
| `afk_bot_controlled` | `bool` | `false` | Le siège est joué par l'IA. Posé au 2ᵉ tour AFK (`router.AFK_BOT_TAKEOVER_TURNS`), **jamais relevé** (en v1 un joueur qui revient ne reprend pas la main). |

⚠️⚠️ **« bot ⇔ id NÉGATIF » a CESSÉ D'ÊTRE VRAI.** Un siège d'id **positif** peut être joué par
l'IA. Le prédicat unique est `bot_ai.is_ai_controlled(state, pid)` ; `bot_runner._has_active_bot_turn`,
`engine._ai_plays` et `router._ai_seat` y délèguent tous les trois. Côté CLIENT, le préfixe
« [IA] » doit donc tester `is_bot` **OU** `afk_bot_controlled`.
⚠️ En revanche `is_bot` reste **FALSE** sur un siège repris, et c'est essentiel : ce joueur a un
compte, une ligne `users`, un historique — donc une persistance de fin de partie, où sa pénalité
atterrit. Toute décision de **PERSISTANCE** continue de se prendre sur le **signe de l'id**
(`process_match_results` saute les `< 0`), jamais sur ce prédicat.

### 2. `TerritoryState` — le bouclier anti-radiations (LOT B)

| Champ | Type | Défaut | Sens |
|---|---|---|---|
| `radiation_shield_turns_left` | `int` | `0` | Immunité à la **ZONE**, achetée 1 PP par territoire. Décrémenté à chaque `_end_turn` (donc à chaque tour de n'importe qui), **exactement comme `shield_turns_left`**. |

⚠️ **DISTINCT de `shield_turns_left`**, qui reste l'immunité aux **ATTAQUES** (Bastion d'Acier).
Deux menaces, deux protections, deux prix. Les fusionner aurait donné au Bastion une immunité de
zone que nul équilibrage n'a décidée.
⚠️ Durée posée = `hero_abilities.shield_turns_for(state)` (= nombre de joueurs en lice) ⇒ **UN ROUND
COMPLET** (décision Hakim 2026-08-11, et non « un seul tick »).

### 3. `PlayerState` — troisième drapeau de capacité (LOT B)

`ability_shield_used: bool = false`. Les **trois** capacités (RATIONNER, BOUCLIER, pouvoir de
faction) sont **CUMULABLES le même tour** → trois drapeaux distincts, et non un compteur partagé.
Rechargés ensemble dans le bloc de reset de `_end_turn`.

### 4. Action WS `hero_ability` — nouvelle valeur d'`ability`

```json
{"action_type": "hero_ability", "payload": {"ability": "radiation_shield"}}
```
Aucune cible : `needs_target: false`. Le SERVEUR choisit les territoires — (a) ceux du télégraphe
(`contamination_zone.next_territories`), (b) puis les garnisons les plus faibles, (c) puis un
départage déterministe dérivé de l'état. Les territoires **déjà immunisés** sont EXCLUS (passif
Culte, ou bouclier encore actif) : un joueur du **Culte de l'Isotope** n'a donc **aucune cible** et
reçoit `invalid_target` — sans qu'aucun cas particulier ne soit codé pour lui nulle part.

`describe(faction_id)` gagne une clé ADDITIVE `radiation_shield` à côté de `ration` et `power`.
Refus possibles : les codes EXISTANTS (`wrong_phase`, `already_used`, `invalid_target`,
`insufficient_pp`) — **aucun code neuf**, donc aucun client à mettre à jour pour les traduire.
⚠️ `casual_only: false` ⇒ **AUTORISÉ EN CLASSÉE** (comme RATIONNER, contrairement aux 3 pouvoirs de
faction pilotes).

### 5. Évènements système structurés — deux codes NEUFS

```json
{"code": "zone_shielded", "territory_id": "<tid>", "player_id": 42, "turns": 4}
{"code": "afk_bot_takeover", "player_id": 42}
```

`zone_shielded` est émis **DEUX FOIS dans la vie d'un bouclier** : une fois **à la pose** (un par
territoire couvert, dans le lot de l'action `hero_ability`) et une fois **à CHAQUE tick évité**
(dans le lot du tour concerné). Ce n'est pas un doublon : le premier dit « je me suis protégé », le
second « ça vient de servir ». Une protection invisible n'existe pas — la leçon de §8.145.
⚠️ Un territoire bouclé **n'attribue AUCUN kill** (`zone_kills_by_player` intact) et **ne touche
AUCUN objectif** : 0 dégât = 0 statistique, exactement comme les protégés du Culte.
⚠️ `zone_protected` (Culte) est **INCHANGÉ** et garde son propre code : les deux protections se
racontent différemment parce qu'elles ne coûtent pas la même chose.

`afk_bot_takeover` accompagne le `turn_timeout` qui l'a provoqué (chemin minuterie) ou son propre
`action_result` (chemin déconnexion brutale).

### 6. `match_stats` — clé ADDITIVE `afk_forfeit`

`GameEngine.build_match_stats` ajoute `"afk_forfeit": bool` par joueur. C'est le canal — le MÊME que
`team_id` — par lequel un fait d'ÉTAT atteint `process_match_results`, qui ne connaît pas la
`GameState`. Un `match_stats` d'AVANT le chantier se lit « personne n'a abandonné » : tous les
appelants historiques et leurs suites restent valides sans une ligne de changement.

**Effet** : le rang retenu au RELEVÉ de ce joueur est forcé au **dernier** (`len(ranking) - 1`).
⚠️⚠️ C'est une **SURCHARGE de SA ligne**, PAS une réécriture du classement : `ranking` et les rangs
des autres joueurs sont INTOUCHÉS, personne n'est poussé. Il peut donc y avoir deux « derniers » —
le vrai dernier, et le partant. Ce n'est pas un podium, c'est un relevé individuel.

### 7. ⛔ LE SEUL RETRAIT : `PlayerState.immune_to_contamination`

Champ **SUPPRIMÉ**. C'était un modificateur DÉCLARÉ et JAMAIS CÂBLÉ : lu par
`_apply_contamination_damage`, remis à `False` par `_end_turn`, et **posé à `True` par aucun code du
dépôt** (inventaire AST, §8.145 §5.3). Le supprimer ne change donc **aucun comportement observable**.

**Rétro-compat Redis** : un état sérialisé qui porte encore le champ se redésérialise sans erreur
(clé inconnue ignorée) — contre-épreuve dans `test_zone_shield.py` [5]. Aucune action humaine, aucune
migration.

---

## 🎲 §8.150 — PP PROPORTIONNELS AUX DÉS CONTESTÉS (volet RÉSEAU — **ADDITIF STRICT §1.5**)

> **Un champ AJOUTÉ, zéro champ renommé, zéro champ supprimé.** Un client §8.149 non mis à jour
> continue de fonctionner à l'identique : il ignore simplement le nouveau champ.

### 1. `action_result.event.hero_duel` — le champ neuf `pp_counted`

| champ | avant | après §8.150 |
|---|---|---|
| `pp_delta` | `int` — **`dés gagnés − dés perdus`** | `int` — **même clé, même type, NOUVELLE sémantique de valeur** : `+dés gagnés` si au moins un dé gagné, sinon `−dés perdus`. Plage inchangée en pratique : **[−3, +3]** |
| `attacker_pp` | `int`, PP bornés post-delta | **inchangé** |
| `pp_counted` | — | **NOUVEAU**, `int` : part des PP réellement comptée dans les dégâts. **Égale à `attacker_pp`** tant que `PP_DUEL_DAMAGE_CAP` vaut 0 — c'est l'état LIVRÉ |
| `damage` | `max(1, floor((PA + PP)·(1 − PB)))` | `max(1, floor((PA + **pp_counted**)·(1 − PB)))` — la formule est littéralement la même, seule son ENTRÉE peut être plafonnée |

⚠️ **`pp_delta` change de VALEUR, pas de CONTRAT.** C'est le seul point d'attention pour un
relecteur : la clé, le type et le signe se comportent comme avant (un flotteur `"%+d PP"` côté
client fonctionne tel quel), mais un partage 1 gagné / 1 perdu vaut désormais **+1** et non **0** —
le flotteur apparaîtra donc là où il n'apparaissait pas.

⚠️ **`pp_delta` est la valeur QUI A MUTÉ L'ÉTAT**, jamais un second calcul fait pour le réseau.
`pp_delta`, `attacker_pp` et `pp_counted` sortent tous les trois du même passage dans
`engine._resolve_hero_duel` — contre-épreuve de parité dans `test_duel_rules.py` [5].

### 2. Rien d'autre ne bouge

Aucun nouvel évènement, aucune nouvelle raison de refus, aucune nouvelle route. Le tunable
`PP_DUEL_DAMAGE_CAP` est **serveur seul** : il n'est ni diffusé ni lisible par le client — celui-ci
n'en voit que la conséquence, dans `pp_counted` et `damage`. Le HUD actuel ignore `pp_counted` ;
un HUD futur pourra afficher « PP comptés » le jour où un plafond serait allumé.
