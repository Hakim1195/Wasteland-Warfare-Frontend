# 🎨 FRONTEND & INTERFACES — Wasteland Warfare

> **Rôle de ce fichier :** Structure des **scènes Godot**, **flux de navigation**, charte graphique **« Warzone Command »** (gunmetal/cyan/or, panneaux angulaires biseautés ; ex-« Modern Warfare » orange/kaki = **legacy éradiqué**, voir §2), **shaders** (`neon_hologram`, `crt_board`, `toxic_pulsation`, `tactical_map`) et **helpers GDScript**. C'est la source de vérité de tout le client Godot (UI, arène, VFX).
>
> **Index / Routeur :** [`CONTEXTE.md`](CONTEXTE.md) — **Voir aussi :** [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md) · [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) · [`PIPELINE_ET_BOOTLOADER.md`](PIPELINE_ET_BOOTLOADER.md)
>
> **DIRECTIVE IA :** La **numérotation d'origine** (`§2`, `§3`, `§8.x`…) est **CONSERVÉE** pour préserver les renvois croisés. Ce fichier contient les sections **§2, §3** et les entrées du journal **§8** frontend : **§8.5, §8.11, §8.13, §8.14, §8.15, §8.16, §8.17, §8.18, §8.19, §8.21, §8.22, §8.23, §8.25, §8.29, §8.30, §8.32, §8.54, §8.55, §8.56, §8.57, §8.58, §8.59, §8.60, §8.62, §8.63, §8.64, §8.65, §8.66, §8.67, §8.68**. Un correctif **frontend est actif dès le relancement du client Godot** (pas de redéploiement). **RÈGLE D'OR :** l'UI ne contient jamais de logique de jeu brute (pattern Signaux). Si tu modifies une **scène**, un **shader**, le **HUD** ou un **helper GDScript**, mets à jour CE fichier.

---

## 🎨 2. CHARTE GRAPHIQUE & UI/UX (FRONTEND) — **DIRECTION « WARZONE COMMAND »**

> ⚠️ **PIVOT DE CHARTE (2026-06-20, décision CTO).** La direction artistique du client bascule sur le **langage visuel de Call of Duty: Warzone** (lobby Saison 2 fourni en référence) : **gunmetal froid + cyan tactique + or**, **panneaux angulaires biseautés (`corner_radius = 0`)**, **typo condensée MAJUSCULE** au rythme *eyebrow → valeur*, **chevrons & badges hexagonaux**. Cette charte **REMPLACE** l'ancienne « Modern Warfare » kaki/anthracite/**Orange Fusion** : l'orange est **retiré du rôle d'accent du HUD**. ✅ **MISE À JOUR (§8.37/§8.38)** : **tous les écrans de menu sont désormais migrés** (`auth_screen`, `main_menu`, `lobby_screen`, `waiting_room`, `faction_selection`) — l'orange ne survit plus que sur le **site vitrine §7** et comme **couleur d'accent de certaines factions** (conservée à dessein). Les §2.1/§2.2 ci-dessous ne documentent plus que l'étape *pilote* « Modern Warfare » (historique). Le HUD in-game, le Combat (Split-Screen VS) et la Fin de partie suivent la charte Warzone Command.
>
> 🚫 **DIRECTIVE D'ÉRADICATION (définitive).** L'ancienne charte « Modern Warfare » (kaki / anthracite + **Orange Fusion** `#d35400`) est **abandonnée DÉFINITIVEMENT** dans le client de jeu. Tout **résidu** découvert ultérieurement — couleur en dur, **nom** de sous-ressource/constante trompeur (`bg_kaki`, `panel_kaki`, `COLOR_KAKI`…), **commentaire** périmé, ou fragment de scène — **DOIT être migré vers « Warzone Command » ou SUPPRIMÉ**, sans exception. **Seules exceptions CONSERVÉES à dessein :** (1) les **couleurs d'accent des factions** (`accent_color` des `.tres` — l'orange y est un choix d'identité), et (2) le **site vitrine** (`website/`, §7) qui garde son thème acier/orange propre. En dehors de ces deux cas, l'orange et le kaki n'ont **plus aucune place** dans l'UI du jeu.

**Palette « Warzone Command » (canonique) :**
- `Fond gunmetal` : `#0f1318` (panneaux quasi-opaques, α ≈ 0.90) — métal froid sombre. Surface secondaire `#1a2028`.
- `ACCENT PRIMAIRE — Cyan tactique` : `#36c5d9` — **rôle interactif** : CTA, onglet actif, sélection, filets 1-2 px, barres de progression, **bordure lumineuse au survol/sélection**. (Remplace l'Orange Fusion comme accent dominant.)
- `ACCENT RÉCOMPENSE — Or` : `#e0b249` — victoire, XP, médaille « plus lourd tribut », pop Time Bank.
- `Texte primaire` : `#eef3f7` (blanc froid) ; `Texte muet` : `#8a97a5` (acier — eyebrows, libellés secondaires).
- `Danger` : `#d6453f` (rouge — abandon, parcimonieux). `Contamination` : `#7fff00` (vert nucléaire — twist post-apo conservé).

**Langage structurel (ADN Warzone) :**
- **Panneaux angulaires** `corner_radius = 0` + **encoche de coin biseautée** (petit `Polygon2D` triangulaire à l'accent cyan) — évoque le biseau CoD sans texture 9-patch.
- **Filets fins cyan** (1-2 px) : séparateurs, soulignement d'onglet actif, bordure de sélection lumineuse, filet haut des panneaux readout.
- **Typo** : `SystemFont` Stencil→Urbanist→Arial gras (`Theme_mil`), **MAJUSCULES**, rythme **eyebrow (petit, acier/cyan) → valeur (gros)**.
- **Iconographie angulaire** : chevrons `❯` comme puces, badges « hexagone » pour les compteurs, **barre chevron couleur-faction** à gauche des lignes joueur/territoire.
- **Boutons CTA** : style « START » Warzone — rectangle **biseauté** (radius 0), bordure cyan + **lueur** au survol, texte MAJ.

**Règles de Composition (héritage, partiellement supersédé) :**
- Écrans UI **legacy** : `CenterContainer` (Full Rect), Logo (`400x250`) « Center Top », boutons `350x60`/`500x60`, Font Size `22`. ⚠️ Sous Warzone Command, on privilégie les **HUD asymétriques à widgets flottants angulaires** (§8.29) et le **`Corner Radius = 0`** (et non plus `4`/`8`).

### 2.1. Direction "Modern Warfare" (écran de connexion `auth_screen` — pilote) — ✅ MIGRÉ « Warzone Command » (§8.37/§8.38) — section conservée comme HISTORIQUE du pilote orange
Refonte esthétique amorcée sur `auth_screen.tscn` (squelette technique destiné à accueillir des assets HD), en **rupture** avec le centrage symétrique historique :
- **Asymétrie gauche/droite :** la colonne UI (logo + panneau) est ancrée à **gauche** (`LeftColumn`, preset `LEFT_WIDE`, marge 50 px, centrée verticalement via `alignment`). `HeroGraphic` (`TextureRect` laissé **vide**) est ancré sur la **moitié droite** pour recevoir un PNG de héros détouré.
- **Profondeur 2.5D (parallaxe) :** `auth_screen.gd._process()` lit la position de la souris relative au centre de l'écran et décale `Background` (lent) et `HeroGraphic` (plus rapide) via `lerp` → profondeur de champ réactive. Un overscan de 60 px sur les calques évite de révéler les bords. `Background` = `GradientTexture2D` sombre (placeholder remplaçable par un asset HD ; PRESET_FULL_RECT).
- **VFX d'ambiance :** `AshParticles` (`GPUParticles2D`) — cendres/étincelles chaudes flottant lentement (alpha faible, fondu via `color_ramp`). L'émetteur est redimensionné au viewport par script (`get_viewport_rect().size`) car c'est un `Node2D` (positionnement absolu, pas d'ancrage Control).
- **Panneau "Glassmorphism" sombre :** `StyleBoxFlat` translucide `Color(0.05, 0.05, 0.07, 0.8)`, liseré orange `#d35400` à gauche (4 px), coins arrondis (10 px), ombre portée. Champs `LineEdit` épurés (fond quasi transparent, soulignement orange lumineux au focus). Boutons CTA orange ; nouveau **bouton "QUITTER LE JEU"** (style _ghost_) câblé sur `get_tree().quit()`.
- **Logique réseau INCHANGÉE :** toute la couche HTTP/JWT reste dans `AuthManager` (§5) ; `auth_screen.gd` ne gère que la **Vue** + les signaux (~~`_on_login_pressed` / `_on_register_pressed`~~ → **`_on_steam_login_pressed`** depuis §8.113 ; gestion succès-échec intacte). *(Ce §2.1 documente le pilote orange HISTORIQUE : les champs ID/mot de passe qu'il décrit n'existent plus dans la scène.)*
- ⚠️ Cette direction **remplace progressivement** les "Règles de Composition" ci-dessus (`CenterContainer` systématique / Logo "Center Top") pour les écrans refondus ; les autres écrans suivent encore l'ancienne charte tant qu'ils ne sont pas migrés.

### 2.2. Lobby refondu (`lobby_screen`) — alignement Modern Warfare — ✅ MIGRÉ « Warzone Command » (§8.37/§8.38) — section conservée comme HISTORIQUE du pilote orange — ❌ **`lobby_screen` SUPPRIMÉ §8.116, remplacé par `search_screen`** (voir §3 et le journal §8.116 plus bas) : cette section ne décrit plus aucun écran existant, gardée pour la mémoire du pilote
La charte de `auth_screen` est étendue au lobby pour une **transition de fond "seamless"** (illusion de continuité entre la connexion et le lobby), avec une **asymétrie fonctionnelle** : commandes à gauche, liste des batailles à droite.
- **Fond identique répliqué :** mêmes calques `Background` (`GradientTexture2D` sombre, overscan 60 px), `HeroGraphic` (`TextureRect` moitié droite, laissé **vide**) et `AshParticles` (`GPUParticles2D`), avec la **même parallaxe** pilotée souris dans `lobby_screen.gd._process()` (constantes `BG_PARALLAX`/`HERO_PARALLAX`/`OVERSCAN` alignées sur l'auth). `_setup_view_layer()` recadre l'émetteur de cendres au viewport (et à chaque resize).
- **Panneau gauche "Centre de Commandement"** (`LeftColumn`, glassmorphism à liseré orange) : label **pseudo** du joueur (`AuthManager.username`), sélecteur d'effectif (`PlayerCountSpin`, 3-6 — **retiré en §8.57**, désormais effectif hérité du mode en lecture seule), **CTA orange proéminent « CRÉER UNE OPÉRATION »**, actions secondaires _ghost_ (« OPÉRATION PRIVÉE (CODE) », « INFILTRER » par ID, « ACTUALISER LE RADAR »), et bouton bas **« DÉCONNEXION »**.
- **Panneau droit "Radar des Opérations"** (`RightBrowser`, glassmorphism `Color(0.05, 0.05, 0.07, 0.8)`, coins arrondis) : `ScrollContainer` listant les salles publiques. Chaque salle est une ligne épurée (`PanelContainer` + liseré orange gauche) générée par `_build_room_row()` : nom (« OPÉRATION #id ») à gauche, **jauge d'effectif « joueurs/max »** centrée, bouton _ghost_ **« REJOINDRE »** à droite.
- **DÉCONNEXION (nouveau comportement) :** coupe le WebSocket s'il est ouvert, purge `AuthManager.jwt_token`/`user_id`/`username` + `NetworkManager.current_room_id`, puis retour à `auth_screen` (≠ ancien bouton « Retour » qui revenait au `main_menu`).
- ✅ **Jauge « joueurs/max » — RÉSOLU (§8.34) :** `GameRoomResponse` (§5) expose désormais **`current_players: int`** (occupation courante calculée serveur). L'UI lisait déjà ce champ **défensivement** → la jauge affiche le vrai compteur sans modification client (le **repli `—/max`** reste en place comme garde-fou si le champ manque, ex. backend non encore redéployé §1/§8.7). *(Historique : auparavant le backend n'exposait que `id`/`max_players`/`is_private`, d'où le repli `—/max` permanent.)*
- **Logique réseau INCHANGÉE :** `lobby_screen.gd` conserve l'intégralité des requêtes (`fetch_rooms`/`create_room`/`join_room`) et des signaux `NetworkManager` ; seul le **peuplement** de la nouvelle UI a été refondu (`_on_rooms_loaded` → `_build_room_row`). Le polling auto 3 s (`AUTO_REFRESH_INTERVAL`) et la coercition `int()` des ids de salle (piège float JSON §5) sont préservés.

---

## 🎮 3. FLUX DE NAVIGATION ET MENUS

0. **Bootloader (`bootloader.tscn`) :** **PREMIÈRE scène** lancée (`run/main_scene`), réduite à une **amorce minimale** : lit la version gravée du client (`application/config/version`) → la pose dans `GameState.client_version` (pour le gate WS strict) → enchaîne sur le **Splash d'ouverture `title_splash`** §8.44 (qui mène à l'écran de connexion). ⚠️ La **mise à jour** n'est PLUS gérée ici : un **launcher dédié** (app Godot séparée) télécharge l'installateur de build complet AVANT le lancement du jeu. Le jeu est **100% multijoueur — aucun mode hors ligne**. Détails complets en **§9** (voir [`PIPELINE_ET_BOOTLOADER.md`](PIPELINE_ET_BOOTLOADER.md)).
1. **Écran de Connexion (`auth_screen`) — « SIGN IN THROUGH STEAM » (§8.113) :** **un SEUL bouton**, `SteamLoginButton` (`AUTH_STEAM_LOGIN`) — plus aucun champ, plus d'onglet Connexion/Inscription, plus de mot de passe. Le clic délègue à `AuthManager.start_steam_login()` (Règle d'Or §6.1 : la Vue n'annonce qu'une intention) : le manager ouvre une session côté serveur, lance le **navigateur externe** du joueur via `OS.shell_open` (Godot ne peut pas recevoir la redirection de retour) puis **interroge** le backend toutes les 2 s jusqu'à obtenir le JWT (rebours global 180 s). Le bouton se désactive pendant l'attente (`AUTH_STEAM_BROWSER_OPENED` dans le `StatusLabel`) et se réarme sur `auth_failed`. Le JWT obtenu est un JWT ORDINAIRE : stockage dans le Singleton `AuthManager` + `user://session.dat`, donc **reconnexion silencieuse au boot inchangée** (§P1). Conservés : parallaxe 2.5D, cendres, sélecteur de langue FR/EN/IT, `QuitButton`.
2. **Menu Principal (`main_menu`) — tableau de bord asymétrique « Warzone Command » (refonte §8.54) :** lobby AAA plein-cadre (réf. CoD Warzone). **Top Bar : plus AUCUNE barre en dur — le menu monte le composant PARTAGÉ `top_nav` (§8.94, voir « NAVIGATION HUB » ci-dessous).** **Centre** : héros affiché **par priorité (§8.93)** — (1) personnage **CHOISI** dans l'écran Personnages (persistant, `SettingsManager`), (2) sinon **dernière faction JOUÉE** (`GET /profile/history`), (3) sinon défaut alphabétique. **Colonne gauche** : mini-classement **top 3** (`GET /leaderboard`) + carte **« DÉFIS EN COURS »** = les **3 vraies missions** les plus pertinentes (`GET /missions`, réclamables d'abord — §8.92). **Bas** : gros **CTA `START`** + **cartes de mode** `TRIO(3)/QUAD(4)/FIVE(5)/EXA(6)` + **`CLASSÉE`(5, classé, en or)**. Le mode sélectionné est transporté au lobby via l'autoload **`MatchConfig`** (effectif natif via `max_players` ; le gate classé `is_ranked`+`==5` est **câblé côté serveur** depuis §8.88).

### 🧭 NAVIGATION HUB — `top_nav.gd` = SOURCE UNIQUE (§8.94)

**Tous** les écrans hub montent le **MÊME** header, construit 100 % par code : marque ▸ **5 onglets** (`QG / PERSONNAGES / BOUTIQUE / DÉFIS / CLASSEMENT`) avec **pastille défis `●N`** ▸ cadre identité (`JOUEUR` → pseudo) + **jauge XP·Coins CLIQUABLE** → **mini-profil flottant** → `profile` ▸ **⚙** → `settings` ▸ **⏻** → confirmation « Quitter ». Filet cyan sous la bande. Hauteur **`NAV_H = 100`**.

- **Plus aucun bouton `RETOUR` ni double header** : **ÉCHAP** (géré par `top_nav`) ferme le pop-up Quitter, sinon le mini-profil, sinon ramène au **QG**.
- **Le Profil n'a PAS d'onglet** : il s'ouvre par la **jauge XP** (règle posée en §8.58, généralisée à tous les écrans).
- **`active_tab` se règle AVANT `add_child`** (lu au `_ready`). **`""` = écran HORS ONGLETS** → aucun onglet surligné (comportement **nominal**).
- **`top_nav` est le SEUL déclencheur** de `get_profile()`, `fetch_missions()` et `fetch_profile_history(1)` : les écrans hôtes **écoutent** les signaux globaux (évite le double fetch).
- **`top_nav` ne lance JAMAIS l'ambiance sonore** : chaque écran hôte appelle `AudioManager.start_menu_ambient()`.

| Écran | `active_tab` | Titre interne |
|---|---|---|
| `main_menu` | `"lobby"` | — |
| `characters_screen` | `"characters"` | retiré (l'onglet nomme l'écran) |
| `shop` | `"shop"` | retiré (+ `CreditsBox` retirée : le solde est dans la jauge) |
| `missions` (écran **DÉFIS**) | `"missions"` | retiré |
| `leaderboard` | `"leaderboard"` | retiré (l'en-tête héberge `ℹ RÈGLES` ; les ex-onglets SAISON/GÉNÉRAL ont disparu en §8.98 — navigation par division) |
| `profile` | `""` | **conservé** (rien d'autre ne le nomme) |
| `settings` | `""` | **conservé** |
| placeholders (`section_placeholder`) | `tab_id` (débranché → aucun match) | **conservé** (`title_key`) |

> **Hors périmètre (intacts) :** HUD d'arène, `search_screen`, `salon_screen` (ex-`lobby_screen`/`waiting_room`, remplacés §8.116), `faction_selection` (flux pré-partie : leur « retour » a une sémantique de flux).
3. **Écran de Recherche (`search_screen`, REMPLACE `lobby_screen` §8.116) :** plus de liste de salles ni d'ID — le joueur lance une **recherche serveur-autoritaire**. Deux panneaux exclusifs :
   - **Panneau CONFIGURATION (état initial, mode non classé) :** eyebrow du mode hérité de `MatchConfig` (ex. « OPÉRATION QUAD — 4 COMMANDANTS ») ; sélecteur de carte 2 tuiles CLASSIQUE (`classic_42`) / RAPIDE (`skirmish_atlantic`, masquée si l'effectif dépasse ses bornes — reprend `_restrict_map_selector_to_mode` de l'ex-`lobby_screen`) ; CTA « ❯ CHERCHER UNE PARTIE » (`mm_queue_join`) ; bloc SALON PRIVÉ (« CRÉER UN SALON » → `private_create` → `salon_screen` ; champ code 5 caractères + « REJOINDRE » → `private_join`). En mode **classé** : plus aucun choix, seul le CTA classée + rappel « CLASSIC 42 — 5 COMMANDANTS ».
   - **Panneau RECHERCHE (après mise en file) :** libellé d'état (`searching`/`extending`/`starting`), chronomètre `since_s`, bouton ANNULER (masqué dès `starting`/`ready`), poll `mm_queue_status()` toutes les 2 s (`Timer` dédié à l'écran, PAS au manager). Sur `ready` : ouverture WS + attente de `game_started` → `faction_selection`. Échecs `banned`/`in_room`/salon `unavailable`/`banned` affichés avec messages bienveillants (jamais de compteur exact restant).
   - **Bouton RETOUR** (état configuration uniquement) → `main_menu`. Idempotent à l'entrée (un `mm_queue_status()` immédiat resynchronise l'écran, y compris après un retour arrière).
   - ⚠️ **Mise en page NON prouvée par le headless** (0 ERROR ne certifie que la compilation/le boot, pas la disposition visuelle réelle) — à vérifier par une capture humaine.
4. **Salon Privé (`salon_screen`, REMPLACE `waiting_room` §8.116, RÉSERVÉ AU PRIVÉ) :** le code en héros (très grand, espacé, or `#E0B249`) + bouton COPIER ; occupation « COMMANDANTS : N/max » via `salon_state_updated` — **aucun pseudo, aucune liste, aucun id de salle affiché**. Créateur : « ❯ LANCER AVEC BOTS » + « FERMER LE SALON ». Non-créateur : « QUITTER LE SALON ». `salon_closed` (créateur parti) → retour `search_screen` avec message amical ; `game_started_signal` → `faction_selection`. Plus de bouton PRÊT : le lancement est automatique (salon complet) ou volontaire (bots). ⚠️ **Mise en page NON prouvée par le headless** — à vérifier par une capture humaine.
5. **Draft / Sélection de Faction (`faction_selection`) :** Étape intercalée entre la salle d'attente et l'arène. Quand le serveur diffuse `game_started`, les clients basculent vers un **carrousel** (et non plus directement vers `main.tscn`). Chaque joueur fait défiler les 10 factions (Tween de glissement), en confirme une (bouton « CONFIRMER LA FACTION »), ce qui envoie `faction_choice` au serveur. L'arène (`main.tscn`) n'est chargée que lorsque **tous** les joueurs ont verrouillé leur faction (voir §4.3 et §5).

6. **Arène (`game/main.tscn`) — layout REFONDU (§8.117) :** le plateau occupe 100 % de la fenêtre ; le `HUD` (Control plein écran, `mouse_filter IGNORE`) porte **cinq** zones et plus rien d'autre :
   - **Bandeau haut (`TopCenterWidget`) — MINIMAL** : `%TurnLabel` « ◤ TOUR DE {pseudo colorisé} » · `%PhaseLabel` · `%TimerLabel` (urgence rouge < 10 s, pré-alerte AFK, Time Bank « +N s »). L'identité locale, la barre d'infos et le tooltip « Pouvoir de Faction » ont DISPARU (redondants).
   - **`TopRightWidget`** : bouton ABANDONNER (inchangé). À sa gauche, le **chip « ☢ PROCHAINE ZONE »** (ex-ligne du bloc bas, G1 §8.62) — cliquable → ouvre l'onglet JOURNAL filtré ZONE.
   - **`PlayerSheetWidget` (gauche, rétractable, 300 px) — FICHE JOUEUR** : `◀ {pseudo} ▶` (navigation dans l'ordre de tour, vivants d'abord), bloc HÉROS (meneur + faction + pouvoir + 4 barres PV/PA/PB/PP), bloc SITUATION (territoires / troupes / cartes / statut), bloc TERRITOIRE (si ouverte par un clic de territoire). **REMPLACE** les 3 tiroirs INTEL (ZONE / FACTIONS / GUERRE), l'Inspecteur de Territoire, l'inspecteur héros adverse et le War Roster haut-droite — tous supprimés.
   - **`SidePanelWidget` (droite, rétractable, 320 px) — COMMS** : le **chat SEUL** (le Journal a déménagé). Sélecteur de destinataire + UNE conversation affichée + badge de non-lus sur le bouton-tiroir replié.
   - **`BottomCenterWidget` — BARRE BASSE PLEINE LARGEUR** (rétractable, 206 px) : `OBJECTIFS` (28 %) · `JOUEUR` (27 %) · `COMMANDES` (45 %, `TabContainer` ACTIONS / CARTES / JOURNAL avec badge « • » de nouveautés).
   - **Couleurs de stats — SOURCE UNIQUE** (`hud.gd`) : PV = dégradé `war_roster.pv_color` · PA = or `#E0B249` · PB = cyan `#36C5D9` · PP = violet tactique `#8C6BD9`. Chaque barre affiche « valeur / max ».
   - Dialogs modaux (`ConquerDialog` / `EclipseDialog` / `SpyDialog`) : **actions réseau inchangées**.
---

## 🧭 8. ÉTAT D'AVANCEMENT (MVP) & POINT DE REPRISE — *Journal : frontend (scènes, HUD, VFX)*

> **DIRECTIVE IA :** Le journal §8 est **réparti par thème** entre les 4 fichiers (index dans [`CONTEXTE.md`](CONTEXTE.md)) ; **numéros d'origine conservés**. Vue d'ensemble du MVP : voir §8.1 dans [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md).
>

### 8.89 (chantier D + volet frontend du chantier C). Rapport Post-Op — XP JOUEUR, XP HÉROS, TOTAL de coins, mention « PARTIE NON CLASSÉE » — ✅ FRONTEND FAIT (2026-07-17)
> **Design.** Le joueur devait pouvoir lire ses gains **sans les chercher**. Tout le nécessaire arrivait DÉJÀ au client (bloc privé `match_rewards["<mon_id>"]`, §8.47/§8.61) : le chantier est **100 % dans la Vue** [`operation_report.gd`](scripts/game/operation_report.gd) — **aucune retouche `.tscn`** (les onglets sont construits par code) et **aucun changement backend** pour le volet D. Tous les accès restent en `rewards.get("…", 0)` → un serveur non redéployé ne casse rien (§9.2).
> - **`hero_coins_earned` n'était affiché NULLE PART** (les coins des montées de niveau du héros tombent pourtant sur le MÊME porte-monnaie que le profil → le joueur SOUS-ESTIMAIT ses gains). Onglet héros : ligne dorée **`◈ COINS HÉROS : +N`** (`ACCENT_GOLD`, masquée si 0), décomptée par `tween_method` en queue d'`_animate_hero` (même pattern que « XP HÉROS »).
> - **Aucun titre chiffré « XP JOUEUR »** (asymétrie avec l'onglet héros — l'XP profil n'était lisible que via la barre et le total du bloc détail). Onglet joueur : compteur animé **`XP JOUEUR : +N`** (`ACCENT_CYAN`, pattern « POINTS DE MATCH »). Si `pass_bonus_applied`, le bandeau `★ +25 % XP` existant reste : le montant affiché est **DÉJÀ** le montant boosté (le serveur applique ×1,25 AVANT envoi).
> - **Aucune ligne « COINS » ni TOTAL** (les coins profil n'étaient qu'un compteur nu dans la barre). Onglet joueur : ligne dorée **`◈ COINS GAGNÉS : +TOTAL`** avec **`coins_earned + hero_coins_earned`** (masquée si le total est nul), suivie — **uniquement quand les DEUX sources ont contribué** — du détail muet **`profil +X · héros +Y`** (police mono `RosterHelpers._mono_font()` + `TEXT_MUTED` = registre du bloc « détail du barème »).
> - **`hero_levels_gained` / `hero_level_up` ignorés** → ligne MIROIR du bloc joueur : **`⬆ N NIVEAU(X) HÉROS GAGNÉ(S)`**, pilotée par le **flag SERVEUR `hero_level_up`** plutôt que par la déduction `h_new > h_old`.
> - **Volet frontend du mode CLASSÉE (§8.88).** `populate(data)` accepte `data["is_ranked"]` (FACULTATIF, défaut `true` = legacy) et `populate_rewards(rewards, is_ranked := true)` le relaie. En **non classé**, le compteur « POINTS DE MATCH » n'est PAS construit (`points_lbl` reste `null` → `_run_reward_animation` saute son décompte) et cède la place à la mention muette **« PARTIE NON CLASSÉE — AUCUN POINT DE LADDER »** (`TEXT_MUTED`) : le serveur renvoie `match_points = 0`, afficher « +0 » laisserait croire à une contre-performance. **Les lignes XP et coins restent TOUJOURS affichées** (elles sont créditées dans tous les modes). `main.gd` reste le RÉSOLVEUR (`_match_is_ranked()` lit `NetworkManager.last_match_is_ranked`) — la Vue ne lit aucun manager (§6.1).
> - **Validation.** Un boot de `main.tscn` n'atteint JAMAIS `populate_rewards` (il ne s'exécute qu'en fin de partie) : la scène a donc été **réellement instanciée et nourrie** via un harnais temporaire (supprimé après usage) sur **4 payloads** — CLASSÉE, NON CLASSÉE, SPECTATEUR (`{}` → les gardes `is_empty()` tiennent, rien n'est construit), PAYLOAD LEGACY MINIMAL (aucun champ héros/coins → tous les `.get` par défaut tiennent). Libellés effectivement produits en classée : `POINTS DE MATCH`, `XP JOUEUR`, `⬆ 1 NIVEAU(X) GAGNÉ(S) — NIVEAU 20`, **`◈ COINS GAGNÉS : +107`** (= 100 profil + 7 héros) + `profil +100 · héros +7`, `XP HÉROS`, `◈ COINS HÉROS`, `⬆ 2 NIVEAU(X) HÉROS GAGNÉ(S)` ; en non classée, `PARTIE NON CLASSÉE — AUCUN POINT DE LADDER` remplace bien le seul compteur de points. `--import` + boot `main_menu` / `lobby_screen` / `waiting_room` / `game/main` = **0 ERROR**. **AUCUN COMMIT.**

### 8.85-front (chantier A.1). Identités de combat = SERVEUR (fin du « mon personnage attaque mon personnage ») — ✅ FRONTEND FAIT (2026-07-17)
> **Symptôme.** Pendant le tour d'un bot, le Split-Screen VS et le bandeau compact attribuaient l'attaque au pseudo / héros / couleur / skin d'un HUMAIN non impliqué — parfois des deux côtés du duel. Contrat réseau et cause racine détaillés dans [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) §8.85.
> - **En bref** : `main.gd` déduisait les identités du SNAPSHOT `_displayed_owners`, or `_refresh()` est DIFFÉRÉ tant que `_combat_queue` se draine — et un bot attaque très souvent DEPUIS le territoire qu'il vient de conquérir (`conquer_move` « tout sauf 1 ») → le snapshot portait l'ANCIEN propriétaire. Le serveur fait désormais autorité via `attack_result.attacker_player_id` / `defender_player_id` (ADDITIFS).
> - **Helper `_event_pid(event, key, fallback)`** : champ serveur prioritaire, `fallback` = valeur historique **propre à chaque site** (sentinelles différentes : `-1` neutre via `_owner()`, `-9999` inconnu) → repli SILENCIEUX si le VPS n'est pas redéployé. `defender_player_id: null` (neutre) → `-1`, exactement la sentinelle déjà rendue par `_owner()`. Appliqué aux **4** consommateurs : `_do_play_combat` (VS + bandeau via son appelant), `_play_event_feedback` (douleur héros, flash de conquête), `_feed_ctx` (kill feed E4), `_maybe_defense_toast`. [`war_feed.gd`](scripts/ui/war_feed.gd) et `hud.show_combat_banner` consomment les `atk_pid`/`def_pid` déjà résolus par `main.gd` — aucune dérivation indépendante.
> - **`local_is_attacker`** ne se base plus sur `GameState.current_player_id` (PÉRIMÉ quand un combat DÉFILÉ s'anime) mais sur l'attaquant DE CE COMBAT → « ⏱ TIME BANK +10 s » ne s'affiche plus au mauvais camp.

### 8.87-front (chantier B). Salle d'attente — « X / Y joueurs » (effectif réel de la salle) — ✅ FRONTEND FAIT (2026-07-17)
> [`waiting_room.gd`](scripts/ui/waiting_room.gd) affiche l'effectif CIBLE diffusé par le serveur (`lobby_state.max_players`, §8.87) via la propriété `NetworkManager.last_max_players` (le signal `lobby_state_updated` garde sa signature — pattern `last_bot_fill_at`). Nouvelle clé **`WR_LOBBY_STATE_CAP`** (3 args) ; **repli** sur `WR_LOBBY_STATE` si le champ est absent (`-1`, serveur antérieur). ⚠️ L'ancienne clé annonçait « (3 requis pour lancer) » — **faux** dès qu'on choisit Quad/Five/Exa/Classée.

### 8.88-front (chantier C). Lobby — mode CLASSÉE (badge or, effectif 5, carte verrouillée) — ✅ FRONTEND FAIT (2026-07-17)
> [`lobby_screen.gd`](scripts/ui/lobby_screen.gd) lit enfin `MatchConfig.selected_ranked` (jusqu'ici transporté puis JAMAIS lu) : effectif forcé à `RANKED_PLAYER_COUNT = 5` (miroir de `api/game/ranked.py`), **carte verrouillée sur `classic_42`** (le sélecteur est calé dessus puis `disabled` + tooltip `LOBBY_RANKED_MAP_LOCKED` — seule carte supportant 5 joueurs ; garde d'UI, le serveur re-valide et fait autorité), **badge « ◆ CLASSÉE »** or `#E0B249` inséré par code au-dessus de l'effectif (aucune retouche `.tscn`, aucun champ réseau — dérivé de MatchConfig). `network_manager.create_room(…, is_ranked := false)` — paramètre en QUEUE de signature → les appelants historiques restent valides ; passé sur les DEUX créations (publique ~l.221 / privée ~l.226). `requeue()` reste volontairement NON classé (G3 §8.70). 2 clés i18n. Détail du contrat : [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) §8.88.

### 8.84. Améliorations visuelles en partie — roster (héros complets), rapports de force (grille étiquetée), rapport de fin (3 onglets + détail du barème) — ✅ FRONTEND FAIT (2026-07-15)
> **Design.** Passe de LISIBILITÉ sur les 3 surfaces d'info en partie (raffinement de E1/E5/E11) : « plus d'information utile, mais PLUS LISIBLE » — on combat la « soupe d'emojis », on étiquette / groupe / aère. **AUCUN nouveau flux réseau, AUCUN changement backend** (données déjà publiques/locales) ; le contrat `main.gd`↔rapport reste INCHANGÉ (mêmes `populate*/set_*` — vues PURES §6.1).
> - **[`war_roster.gd`](scripts/ui/war_roster.gd) — carte à 2 lignes (Chantier 1)** : `_make_row` → **ligne 1 identité** (`▶/💀/🏳` + `player_chip` + compteurs `🏴/🃏` compacts + `NIV`) ; **ligne 2 vitals ÉTIQUETÉS** (`_make_vitals_line`) — barre PV élargie + `PV n/max` + `🗡 PA n` (or) + `🛡 PB p%` (cyan) + `PP ±n` (muet, poussé à droite), `ABATTU` (DANGER) si le héros est à terre, masquée en état pré-RPG (aucun « 0/0 » fantôme). Compteurs gardés en ligne 1 (déviation assumée du plan : évite le débordement à ~252 px). Helper PUR `_pb_percent` (self-check) ; labels en `mouse_filter=PASS` → le clic de ligne ouvre toujours l'inspecteur. **6 clés `ROSTER_*` neuves.**
> - **[`hud.gd`](scripts/ui/hud.gd) — grille de pastilles (Chantier 2)** : `_make_war_row` remplace la ligne d'emojis compressée `⚔%d ☠%d …` par un en-tête `[chip | 🏴 | barre MENACE étiquetée]` + une **`GridContainer` de pastilles étiquetées** (`_stat_pill(icône, label, valeur, tooltip)` — fond très discret, coins droits) groupées **Combat** (⚔ Kills · ☠ Pertes · 🚩 Conq · 🎯 Élim) puis **Héros/Zone** (💥 Dég.H · 💀 Abattus · ☢ Zone), + ratio **`V/D`** (libellé + barre `pv_color` + pourcentage chiffré). Panneau élargi 252→**300 px**, séparation aérée ; chaque pastille porte son tooltip (la légende globale `WARROOM_LEGEND` reste en repli). **9 labels + 7 tooltips `WARROOM_*` neufs.**
> - **[`operation_report.gd`](scripts/game/operation_report.gd) — 3 ONGLETS (Chantier 3)** : `_build_columns()` → **`_build_tabs()`** — un `TabContainer` (angles droits, liseré cyan sur l'onglet actif via `_style_tabs`, SFX `click` au changement) remplace les 2 colonnes ; 3 pages `ScrollContainer > VBox` : **🎖 XP JOUEUR** (récompenses animées + **détail du barème** + stats perso + missions), **⚔ XP HÉROS** (progression héros animée + **détail**), **🏆 CLASSEMENT** (podium + timeline + récap de zone reparenté). Toujours **100 % par code, `.tscn` intact** ; les conteneurs `populate*/set_*` sont simplement RE-CIBLÉS (contrat préservé) ; `_build_and_animate_rewards` scindé en `_build_player_rewards` (onglet 1) / `_build_hero_progress` (onglet 2). Points de podium masqués → affichés « — » (redaction, `REPORT_POINTS_HIDDEN`) au lieu d'être cachés.
> - **Détail du barème (NOUVEAU, réconcilié)** : helpers PURS statiques `player_points_breakdown` / `player_xp_breakdown` / `hero_xp_breakdown` — **miroir EXACT de `api/game/rewards.py`** (backend) — reconstituent chaque poste `libellé … +valeur` (`compute_match_points` / `compute_match_xp` avec Pass ×1,25 floor / `compute_hero_match_xp`) ; une ligne **« Ajustement serveur %+d »** absorbe tout écart de reconstruction (continents conquis en cours de partie, etc. non tracés client) → le TOTAL affiché est TOUJOURS le total OFFICIEL serveur (`match_points`/`xp_earned`/`hero_xp_earned`), jamais un chiffre inventé. Entrées brutes fournies par **`main.gd::_xp_detail()`** (rang depuis `_match_rankings` sinon vainqueur, continents entièrement possédés carte courante G5, objectif révélé — tout PUBLIC/local, **aucune requête**).
> - **i18n** : ~50 clés neuves `ROSTER_*` / `WARROOM_*` / `REPORT_*` (fr/en/it), CSV réimporté (`.translation` régénérés). Charte §2 respectée partout (angles droits, palette canonique, gunmetal, police mono `RosterHelpers._mono_font`).
> - **Validation** : les harnais dédiés re-passent VERTS après refonte — **[`test_e1_roster`](tools/test_e1_roster.tscn) 11**, **[`test_e5_warroom`](tools/test_e5_warroom.tscn) 17**, **[`test_e11_report`](tools/test_e11_report.tscn) 23** asserts (dont **self-check des barèmes** : `player_points_breakdown(0,5,1,2,250)==57`, XP profil Pass ×1,25 floor, XP héros ; + rendu des onglets/détail) ; `--import` + boot des 3 scènes = **0 ERROR**, 0 référence morte, 0 warning. **AUCUN COMMIT.**

### 8.73 (lot E1 — PLAN_EXPERIENCE). Roster de Guerre permanent & identité unifiée — `player_chip` + `war_roster` — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E1).** Réponse au « qui est qui, qui joue, qui est mort » : panneau PERMANENT du panneau latéral listant TOUS les belligérants (état complet, tri par rotation), et l'identité joueur devient une brique UNIQUE réutilisable (E2/E4/E11 la reprendront). Données 100 % publiques déjà diffusées (`players` §8.28/§8.61 + `territories`) — **AUCUN nouveau flux réseau, AUCUN changement backend**.
> - **NOUVEAU [`scenes/components/player_chip.tscn`](scenes/components/player_chip.tscn) + [`scripts/ui/player_chip.gd`](scripts/ui/player_chip.gd)** — brique « identité » (source UNIQUE de la présentation d'un joueur) : pastille à la couleur PLATEAU (`board.get_player_color` via le groupe **`game_board`** où le board s'enregistre à `_ready` — JAMAIS de 2ᵉ palette) + pseudo (préfixe `[IA]` bots G2 §8.72, repli « Joueur N ») + marque ◆ à l'accent de faction (**NOUVEAU getter `board.get_faction_accent`** — la table des accents `.tres` reste unique). API `setup(pid, compact)` — compact = police 11 + troncature 12 car. (le tooltip garde le pseudo COMPLET). Enfants construits par code (`_ensure_built` idempotent, utilisable avant `_ready`).
> - **NOUVEAU [`scenes/components/war_roster.tscn`](scenes/components/war_roster.tscn) + [`scripts/ui/war_roster.gd`](scripts/ui/war_roster.gd)** — inséré PAR CODE en tête du SideVBox (`hud._build_war_roster`, insertion relative — piège n° 6 PLAN_EXPERIENCE) : **bandeau d'ordre de tour** (chips compactes séparées de `▸`, joueur courant en surbrillance/les autres en sourdine) + **une ligne par joueur triée `turn_order`** (helpers PURS statiques `sorted_pids`/`territory_count`, pids float/clés string normalisés §5) : chip, `NIV n` (SystemFont mono Share Tech Mono→Consolas), mini-barre PV héros (dégradé continu vert→or→rouge `pv_color`, vide si abattu, absente si pré-RPG), compteurs `🏴 territoires`/`🃏 cartes`, icônes `▶` (pulse Tween) / `💀` (ligne grisée) / `🏳` (abandon §8.20). **Clic ligne** → `player_clicked` → `hud.roster_player_clicked` → `main._on_roster_player_clicked` : `set_player_inspector` (réutilisé tel quel, suivi temps réel `_inspected_enemy_id`) + focus caméra sur SON territoire le plus garni (`focus_on_combat(pos, pos)` + retour 2,5 s). Rafraîchi par `hud.update_display()` (aucun flux nouveau).
> - **Unification identité** : l'Inspecteur de Territoire présente le **propriétaire en `player_chip`** (chip lazy insérée après `%InspectorOwner` ; label nu réservé au NEUTRE / appels legacy). ⚠️ **Correctif au passage** : `_push_inspector` testait `owner_id >= 0` → les territoires de **BOTS (ids négatifs)** étaient classés « NEUTRE » ; désormais seul `null` = neutre. **NOUVEAU `main._bb_pseudo(pid)`** (pseudo résolu + échappé `[`→`[lb]` + colorisé couleur plateau — généralisation du pattern de `_on_chat_message`) appliqué à : `_on_spy_result` (description AUSSI échappée — elle peut contenir un pseudo), `_on_player_abandoned`, `turn_timeout`, `game_over`.
> - **i18n** : 8 clés `ROSTER_*` (fr/en/it). ⚠️ Préfixe `WR_` évité — déjà pris par la waiting room (`WR_BOT_FILL_IN`).
> - **Validation** : **NOUVEAU test maison [`tools/test_e1_roster.tscn`](tools/test_e1_roster.tscn)** (boot headless AVEC autoloads réels, état STUB injecté — **11 asserts** : tri `turn_order` avec bot hors rotation, comptes de territoires, bornes du dégradé PV, pseudo/préfixe `[IA]` des chips, 3 lignes construites) + **self-check debug intégré** à `war_roster` (pattern G4) + `--import` + boot headless `main.tscn` = **0 ERROR**. **AUCUN COMMIT.** → **Ligne de belligérant refondue en carte 2 lignes (vitals héros complets étiquetés) en §8.84.**

### 8.82 (lot E10 — PLAN_EXPERIENCE). Accessibilité & confort — réglages + mode daltonien — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E10).** Les réglages passent de « volume + fenêtre » à un vrai panneau de confort. Tout est persisté par `SettingsManager` (mécanisme confort générique posé au lot E8 : une clé, un défaut, un signal). **Frontend uniquement.**
> - **`SettingsManager` (mécanisme confort, §8.80)** : `get_comfort`/`set_comfort` + signal `comfort_changed`, section `[comfort]` de `settings.cfg`, 5 clés `COMFORT_DEFAULTS` : `combat_display` (E8), `reduced_motion`, `colorblind_mode`, `ui_scale` (0.9/1.0/1.15/1.3 → `content_scale_factor`, appliqué immédiatement), `damage_numbers`.
> - **Écran `settings.gd` — section CONFORT construite PAR CODE** (aucune retouche `.tscn`, appendue au `RootVBox`) : segments `combat_display` (3) + `ui_scale` (4) + bascules ON/OFF `reduced_motion`/`colorblind_mode`/`damage_numbers` (styles `_style_segment` réutilisés). 8 clés i18n `SETTINGS_*`.
> - **Mode daltonien (le point dur)** : **palette Okabe-Ito** `#E69F00,#56B4E9,#009E73,#F0E442,#CC79A7,#0072B2` — la bascule vit DANS **`board.get_player_color`** (source UNIQUE E1 → roster/VS/feed/badges suivent AUTOMATIQUEMENT ; la palette par index REMPLACE même les accents de faction). **Motifs de renfort** : le shader `territory_overlay.gdshader` gagne le canal **`territory_pattern[42]`** (1=rayures ⟋, 2=points, 3=croisillons, 4=chevrons, 5=vagues, 6=plein — `pattern_mask` en `SCREEN_UV`) poussé par index de joueur ; ⚠️ **intégré à l'overlay existant** plutôt qu'un `territory_pattern.gdshader` séparé (une seule passe de rendu — déviation assumée du plan). **`territory_badge.set_data(..., initial)`** : initiale du pseudo en pastille de coin (redondance texte). `board._on_comfort_changed` redessine sur `colorblind_mode`/`reduced_motion`.
> - **`reduced_motion`** : uniform **`motion_scale`** de l'overlay (0 fige les pulsations télégraphe/attaque) + coupe les pulses d'UI (objectif E6, phase E7 → état figé mais distinct) + les VFX E9 (`main._vfx_enabled`). **`damage_numbers`** : gate les flotteurs de dégâts (VS `_spawn_floater`, zone `spawn_zone_tick`).
> - **Validation** : **NOUVEAU [`tools/test_e10_comfort.tscn`](tools/test_e10_comfort.tscn)** **10 asserts** (réglages persistables + typés, palette Okabe-Ito par index via `get_player_color` source unique, initiale de badge, index de palette stable) ; `--import` (shader motifs+motion_scale compilé) + boot `main.tscn`/`settings.tscn` + re-run E1 = 0 ERROR. **AUCUN COMMIT.**

### 8.81 (lot E9 — PLAN_EXPERIENCE). Feedback sensoriel — 10 hooks SFX + VFX ponctuels — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E9).** Brancher le son et quelques VFX aux moments qui comptent. `audio_manager` a déjà tout (`play_sfx` + repli synthétisé `_make_blip`/`_make_chord`… — **AUCUN asset requis** pour livrer).
> - **`audio_manager.gd`** : **NOUVEAU helper `_register_sfx(name, synth: Callable)`** (fichier prioritaire `assets/audio/sfx/<name>` sinon repli synthétisé) + **10 SFX** enregistrés (fréquences/durées distinctes documentées) : `your_turn` (quinte triomphale), `dice_lock`, `hit_troops`, `hero_hit` (coup grave), `hero_down` (chute dramatique), `conquest` (fanfare octave), `zone_alarm` (alerte toxique aiguë), `under_attack` (alerte grave), `card_draw` (bruissement), `timer_tick` (tic discret). **Débloque les appels DÉJÀ posés muets** par E2 (`hero_hit`/`hero_down`), E3 (`your_turn`/`timer_tick`), E4 (`under_attack`). Hakim remplace par de vrais WAV en déposant les fichiers (mécanique `_load_override`).
> - **Sites d'appel NEUFS (`main._play_event_feedback`, un par game_event)** : `conquest` + **flash radial** sur conquête ; `card_draw` sur `card_played`/`card_kept` ; `zone_alarm` dans `_push_intel` quand le télégraphe G1 vise AU MOINS un de MES territoires (signature `_last_zone_alarm_sig` → une fois par télégraphe, pas par refresh).
> - **VFX ponctuels (pattern §8.30, confinés au SubViewport plateau)** : **NOUVEAU [`shaders/conquest_flash.gdshader`](shaders/conquest_flash.gdshader)** (halo en cloche `sin(progress·π)`) appliqué transitoirement par **`board.conquest_flash(tid, accent)`** ; **`board.spawn_zone_tick(tid)`** (flotteur `-1` vert toxique par territoire contaminé, ticks dérivés E4) ; **`hud.pulse_hero_pain()`** (liseré rouge 0,3 s de la fiche héros quand NOTRE héros encaisse). **TOUS gérés par `reduced_motion` (E10)** via `main._vfx_enabled()` — désactivés si actif (les SFX, eux, passent par le bus SFX).
> - **Validation** : **NOUVEAU [`tools/test_e9_feedback.tscn`](tools/test_e9_feedback.tscn)** **14 asserts** (10 hooks enregistrés, `play_sfx` sans crash sur bus muet + nom inconnu, VFX board/héros appelables, `reduced_motion` coupe `_vfx_enabled`) ; `--import` (shader compilé) = 0 ERROR. **AUCUN COMMIT.**

### 8.80 (lot E8 — PLAN_EXPERIENCE). Rythme des combats — skip/accéléré, 3 modes d'affichage, bandeau spectateur — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E8).** Le Split-Screen VS doit respecter le temps du joueur : accélérable, skippable, discret quand on n'est pas concerné. **Frontend uniquement** (la Time Bank §8.33 amortit déjà côté serveur). ⚠️ **`Engine.time_scale` INTERDIT (piège n° 7)** : accélération LOCALE (attentes `_wait` scalées + Tweens `/ _speed_scale`) — le chrono E3 et les timers réseau ne sont jamais affectés.
> - **`split_screen_vs.gd` — contrôles universels** (participant ou non) : `_unhandled_input` → **1ᵉʳ clic/Espace = ×2,5** (`_speed_scale`), **2ᵉ = saut au tableau final** (`_skip`). Chorégraphie refondue skip-aware : **`_wait(seconds)`** (frame-based, scalé, interruptible) remplace les `create_timer().timeout` ; **`_lock_all_dice`** + phases **IDEMPOTENTES** (`_result_marked`, `_damage_shown`) → le tableau final (dés verrouillés + pertes + PV héros) est GARANTI identique, qu'on skippe ou non. La permadeath (E2) reste montrée même au skip (juste plus courte). Hint bas-centre « CLIC : ACCÉLÉRER ▸ PASSER ».
> - **Modes par implication** (réglage `SettingsManager` **`combat_display`**, défaut `cinematique` — voir mécanisme confort générique §8.82) : `cinematique` = plein écran pour TOUS ; `rapide` = plein écran pré-accéléré (`meta.speed = 2.5`) ; **`bandeau`** = combats où JE ne suis NI attaquant NI défenseur → **PAS de plein écran**, `hud.show_combat_banner` compact haut-centre 2,2 s (chips E1 des deux camps + dés figés + pertes + `♥−N`/💀/🏴) ; mes propres combats restent plein écran. Le kill feed E4 complète.
> - **Chaîne de ré-assaut (E7)** : à partir du 2ᵉ assaut consécutif sur la MÊME paire (source→cible), **version condensée** (`meta.condensed` → verrouillage direct des dés, ~1,2 s), même en `cinematique` (`main._last_combat_pair`).
> - **File de synchro** : le bandeau passe par le MÊME mécanisme `_combat_animating`/`_refresh_pending` (durée plus courte) — AUCUN état ne se peint pendant une résolution (piège n° 4).
> - **i18n** : 1 clé `VS_SKIP_HINT`.
> - **Validation** : **NOUVEAU [`tools/test_e8_combat_rhythm.tscn`](tools/test_e8_combat_rhythm.tscn)** **6 asserts** (mode condensé, chemin SKIP complet jusqu'au tableau final sans erreur, 3 modes `combat_display` persistables, bandeau compact HUD) ; `--import` + boot `main.tscn` + re-run E2 = 0 ERROR. **AUCUN COMMIT.**

### 8.79 (lot E7 — PLAN_EXPERIENCE). Commandement fluide — surlignage des cibles, flèche d'intention, ré-assaut, quantités rapides — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E7).** Réduire les frictions du tour : montrer ce qui est jouable, répéter un assaut d'un clic, accélérer les déploiements. **Frontend uniquement** (le serveur re-valide tout, §8.48).
> - **Surlignage des cibles valides (Phase 3)** — `territory_overlay.gdshader` gagne le canal **`territory_attack[42]`** (liseré CRAMOISI pulsant le long des vraies côtes, même mécanique que le télégraphe G1) + uniform **`attack_dim`** (désaturation douce des territoires NI cibles NI à moi pendant la sélection). `board.gd` : `set_attack_context(source, valid_targets)` / `clear_attack_context()` poussent `ov_attack` + `attack_dim`. `main.gd::_valid_attack_targets` = voisins (carte courante G5) appartenant à un AUTRE joueur, calculé à `_select_source` (Phase 3 seulement).
> - **Flèche d'intention** — `board.set_intent_arrow(target)` / `clear_intent_arrow()` : deux `Line2D` (trait + tête de flèche cramoisie) source → territoire survolé, posés dans `_on_territory_hovered` (complète la prévision G4), effacés au unhover / à la désélection.
> - **Annulation** — `main._unhandled_input` : **ESC** (`ui_cancel`) désélectionne la source (réutilise `_clear_source`).
> - **Ré-assaut en un clic** — `main._last_attack {source, target}` mémorisé à chaque attaque ; `hud.set_reassault(active, S, C)` affiche « ⚔ RÉ-ASSAUT (S ➜ C) » près de « Fin de Phase » (signal `reassault_pressed`) tant que `_reassault_legal()` (source ≥ 2, cible toujours ennemie + adjacente, Phase 3, notre tour) — re-testé à CHAQUE état (`_refresh_reassault`). Renvoie la MÊME action `attack` (dés auto `clampi`).
> - **Quantités rapides** — `hud._build_amount_shortcuts` : boutons `+1/+5/MAX` accolés à `%AmountSpin` (signal `amount_quick(delta)`, delta -1=MAX) ; **raccourcis clic-territoire** en déploiement : **Shift = +5**, **Ctrl = MAX** (câblés dans `_on_territory_clicked` via `Input.is_key_pressed`) ; `_buffer_add` accepte un delta borné au stock restant.
> - **Coup de pouce de phase** — `main._no_action_possible()` (aucune attaque légale en 3 / aucun mouvement en 4, calcul LOCAL) → `hud.pulse_next_phase(true)` : `%NextPhaseButton` pulse OR + tooltip « Aucune action possible — passer ».
> - **i18n** : 1 clé `CMD_NO_ACTION`. Pièges respectés : couleur unique (E1), le shader borné aux 42 territoires overlay.
> - **Validation** : **NOUVEAU [`tools/test_e7_command.tscn`](tools/test_e7_command.tscn)** **10 asserts** (cibles valides = adjacence + propriété, ré-assaut re-testé source/cible/garnison, `no_action_possible` détecte l'impasse, `+N` borné au stock) ; `--import` + boot `main.tscn` = 0 ERROR. **AUCUN COMMIT.**

### 8.78 (lot E6 — PLAN_EXPERIENCE). Tracker d'objectif vivant — jauge de progression sous l'objectif secret — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E6).** L'objectif secret (visible par son seul porteur — redaction §8.6) devient une jauge temps réel. **Frontend uniquement** : notre propre `GameState.objectives[me]` porte type/params/description (§4.4), l'état public suffit à calculer la progression.
> - **NOUVEAU [`scripts/ui/objective_tracker.gd`](scripts/ui/objective_tracker.gd)** — module PUR (RefCounted, testé) : `leg_progress(objective, ctx)` → `{label, ratio 0..1, done}` par volet (`conquer_territories` = mes territoires / `params.n` ; `control_continents` = continents entiers / `params.n` ; `eliminate_player` = `VIVANT` 0.0 / `ABATTU ✔` 1.0) ; `progress(objective, ctx)` → `{lines, best_ratio, done}` — pour un objectif **`double`** (§8.61) DEUX mini-lignes triées **plus avancée en tête** (sémantique OU). `ctx` (résolu par main, le module ne lit pas l'état) : `{owned_count, continents_owned, target_alive, target_name}`.
> - **`hud.gd`** : `set_objective_progress(data, tooltip)` — conteneur créé sous `%ObjectiveLabel` (pattern `_ensure_forecast_label`, ancrage relatif) : une `ProgressBar` (vert accompli / or sinon, dégradé E1 `_tint_progress`) + libellé par ligne, séparateur `— OU —` entre les deux volets d'un objectif double. **≥ 80 % (ou accompli) → pulse OR** dans `_process` (proche de la victoire) ; tooltip = description complète + rappel « dernier survivant gagne toujours ». Vide → tracker masqué.
> - **`main.gd::_push_objective_tracker`** (dans `_refresh`) : résout le ctx public — territoires (`WarRoom.territory_count`, ajouté à war_room.gd comme miroir), **continents entièrement possédés** (carte courante G5), statut de la cible d'élimination (`params.target_id`, §8.61). Le nom de la cible est DÉJÀ dans notre description → aucune fuite nouvelle.
> - **i18n** : 2 clés (`OBJ_OR`, `OBJ_LAST_SURVIVOR_HINT`).
> - **Validation** : **NOUVEAU [`tools/test_e6_objective.tscn`](tools/test_e6_objective.tscn)** **14 asserts** (chaque type, objectif double 2 volets + tri + OU + cible déjà tombée par un tiers, jauge HUD construite/masquable) ; `--import` + boot `main.tscn` = 0 ERROR. **AUCUN COMMIT.**

### 8.83-front (lot E11 — PLAN_EXPERIENCE). Rapport Post-Opération 2 colonnes — podium, titres, timeline, inspection — ✅ FAIT (2026-07-15)
> **Contrat réseau complet : CONTRAT_RESEAU §8.83** (`game_over` PAR destinataire, `objectives_reveal` public, `territory_history` — volet backend actif après redéploiement VPS, MÊME que E3 ; d'ici là le rapport fonctionne en repli legacy, §9.2).
> - **`operation_report.gd` refonte 2 COLONNES (100 % par code, `.tscn` intact)** : `_build_columns()` insère une `HBoxContainer` dans `ReportVBox` et **MIGRE** le récap de zone existant (`AttritionEyebrow` + `%StagnationReport` + `%AttritionList`) en colonne gauche via **`reparent()`** — ⚠️ le reparentage invalide la résolution `%Nom` (`unique_name_in_owner`) → poignées directes `_stagnation_ref`/`_attrition_ref` mémorisées AVANT. **Gauche = LA PARTIE** : `populate_podium(rows)` (une ligne/joueur : médaille `medal_for` 🥇🥈🥉/rang, `player_chip` E1, **titres honorifiques** `honor_titles` — helper PUR, formules exactes `💀 BOUCHER`/`⚔ CONQUÉRANT`/`🎯 FOSSOYEUR`/`🛡 INDESTRUCTIBLE`/`☢ IRRADIÉ`, **départage pid croissant**, cumul possible ; objectif révélé ✔ vert/✘ gris ; points affichés SEULEMENT sur MA ligne — redaction ; 3 stats publiques), `set_timeline(series)` (**classe interne `TimelineChart extends Control` `_draw()`** — une polyligne/joueur couleur plateau, X=rounds, Y=territoires, grille charte ; section masquée si `territory_history` vide §9.2). **Droite = MA PERFORMANCE** : bloc récompenses animé CONSERVÉ (déplacé de l'attrition vers `_my_perf_box`) + `set_my_stats` (kills/pertes/ratio, conquêtes, éliminations, cartes, dégâts héros, morts zone, **état final héros** `PV/PP/NIV` ou `💀 ABATTU`) + `set_missions_summary` (pont M2).
> - **`main.gd` — résolveurs (View pure §6.1)** : `_on_match_over` consomme ENFIN `rankings` (`_match_rankings`) → `_podium_rows()` (fusionne rankings + `NetworkManager.last_objectives_reveal` + `honor_titles` + `WarRoom.stat_of` + MES points seuls) ; `_timeline_series()` (depuis `statistics.territory_history`, couleurs `board.get_player_color`) ; `_my_match_stats()` (compteurs + `GameState.hero_of`) ; `_fetch_missions_for_report()` (un `fetch_missions` UNIQUE post-`game_over` → `set_missions_summary`). Podium poussé au victory ET/OU au `game_over` (course réseau — `populate_podium` retrait immédiat = idempotent).
> - **Inspection du champ de bataille** : signal `battlefield_inspect(on)` → `camera.set_free_navigation(on)` ; `_set_inspecting` masque `Center`+`BlurRect` (plateau final visible), bouton flottant `◀ RAPPORT`. Zéro réseau (état final déjà local).
> - **i18n** : 22 clés `REPORT_*`/`TITLE_*` (fr/en/it).
> - **Validation** : **NOUVEAU [`tools/test_e11_report.tscn`](tools/test_e11_report.tscn)** **16 asserts** (titres+départage pid+cumul, médailles, rapport complet podium 3/timeline vmax/stats/inspection, rapport LEGACY sections masquées) + backend `test_game_over_redaction.py` 19 ✅ ; `--import` + boot `main.tscn` = 0 ERROR. **AUCUN COMMIT.** → **Disposition 2 colonnes refondue en 3 ONGLETS (XP joueur / XP héros / classement) + détail du barème réconcilié ; test porté à 23 asserts, en §8.84.**

### 8.77 (lot E5 — PLAN_EXPERIENCE). War Room — 3ᵉ tiroir « INTEL : GUERRE » (rapports de force complets) — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E5).** Les 8 compteurs publics de `GameState.statistics` (§8.35/§8.47 — déjà stockés côté client) ont enfin leur écran. **Frontend uniquement.**
> - **NOUVEAU [`scripts/ui/war_room.gd`](scripts/ui/war_room.gd)** — module de calcul PUR (testé par asserts) : `player_rows(players, territories, statistics)` → une ligne par joueur TRIÉE par territoires desc (kills/pertes/**ratio** kills∕(kills+pertes)/conquêtes/éliminations/dégâts héros/héros abattus/morts zone — clés `statistics` en STRING, accès `str(int(pid))` §5) + **indice de menace DOCUMENTÉ** `territoires×2 + kills − pertes + éliminations×5` (aucun effet gameplay) ; `continent_rows(territories, continents)` → « CONTRÔLÉ » (un joueur possède TOUT) vs « CONTESTÉ x/y » + leader.
> - **`hud.gd` — 3ᵉ tiroir** construit PAR CODE et inséré dans `IntelWidget` APRÈS le tiroir Factions (pièges n° 5/6 : aucun nouveau nœud `%`, insertion relative) : bouton ghost `🛰 INTEL : GUERRE ▸/▾` (styles répliqués), panneau min 252 px, mêmes anims Tween que les 2 tiroirs existants. `set_war_intel(rows, continents)` : **cartes joueur 2 lignes** (le « tableau » du plan, ADAPTÉ à la largeur du tiroir — toutes les colonnes présentes, légende en tooltip `WARROOM_LEGEND`) — ligne 1 : `player_chip` + `🏴 n` + **barre de menace** (normalisée au max de la table, or) ; ligne 2 : compteurs compacts `⚔ ☠ 🚩 🎯 💥(💀) ☢` + **barre de ratio** vert→rouge (dégradé E1 `pv_color`). Synthèse **CONTINENTS** dessous (chip du propriétaire / leader atténué).
> - **`main.gd::_push_war_intel`** (dans `_refresh`) : continents de la **carte COURANTE** via `MapData.get_map(GameState.map_id).continent_territories` (G5 — jamais les 6 continents sur une sous-carte) + noms `MapData.CONTINENTS`.
> - **i18n** : 9 clés `INTEL_WAR_*`/`WARROOM_*` (fr/en/it).
> - **Validation** : **NOUVEAU [`tools/test_e5_warroom.tscn`](tools/test_e5_warroom.tscn)** — **17 asserts verts** (agrégats exacts sur stub 2 joueurs à compteurs connus, tri, ratio, formule de menace, continent contrôlé vs contesté, tiroir HUD construit/peuplé/togglable) ; `--import` = 0 ERROR. **AUCUN COMMIT.** → **Cartes joueur refondues en grille de pastilles ÉTIQUETÉES (fin de la ligne d'emojis `⚔☠🚩…`), panneau 300 px, en §8.84.**

### 8.76 (lot E4 — PLAN_EXPERIENCE). Journal de Guerre 2.0 — `war_feed`, filtres, kill feed, focus caméra, toasts — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E4).** Le journal passe de « texte qui défile » à un OUTIL : flux structuré, filtrable, cliquable, kill feed en surimpression, toasts quand on est attaqué hors de son tour. **Frontend uniquement** (les évènements diffusés suffisent).
> - **NOUVEAU [`scripts/ui/war_feed.gd`](scripts/ui/war_feed.gd)** — module de parsing PUR (RefCounted, aucun nœud) : `parse(event, ctx)` → entrées `{category: combat|zone|cards|system, icon, rich_text, tid, major}`. Résolutions injectées par `ctx` (testable par stubs) : `bb` (=`main._bb_pseudo` E1, échappement `[lb]` inclus), `tname`, `fallback` (texte legacy `_format_event` — **tout type INCONNU devient une entrée system brute, AUCUNE perte**), `atk_pid/def_pid` (propriétaires PRÉ-combat, résolus par main depuis `_displayed_owners`). `attack_result` → jusqu'à 3 entrées (ligne de combat + **conquête MAJEURE** « ⚔ X ➜ Ontario (−3) » + **permadeath MAJEURE** « 💀 X abattu par Y ») ; `system_messages` embarqués (« ☢ »/protection Culte → catégorie zone). **`zone_entries(ticks)`** : tics de contamination **DÉRIVÉS par main** (`_derive_zone_ticks` — comparaison snapshot `_displayed_garrisons` vs état reçu sur les évènements de TOUR, le serveur n'itemise pas les −1 ; territoire rasé → « ☢ X ravagé (−1) » MAJEUR).
> - **`hud.gd` — flux structuré** : `add_feed_entries` (numérotation à l'AJOUT, plafond 200, rendu incrémental) ; **`add_log` legacy → entrée `system`** (tous les appels existants passent au nouveau modèle sans retouche) ; **chips de filtre** `TOUS/⚔/☢/🃏/⚙` (ButtonGroup pattern `%ChatIconBar`, insérées au-dessus de `%LogText`) → `_rerender_feed()` ; entrées avec `tid` rendues **`[url=<tid>]`** → `meta_clicked` → signal `log_territory_clicked` → **main : focus caméra + `board.flash_territory`** (NOUVEAU — flash accent 0,4 s via le Polygon2D de remplissage legacy `_ensure_fill`, inutilisé depuis l'overlay §8.51).
> - **NOUVEAU [`scenes/components/kill_feed.tscn`](scenes/components/kill_feed.tscn) + [`scripts/ui/kill_feed.gd`](scripts/ui/kill_feed.gd)** : coin haut-droit HORS panneaux (à gauche du panneau latéral de 320 px), 4 entrées majeures max (récente en tête), fondu 6 s, IGNORE partout. Alimenté par main (`entry.major`).
> - **Toasts défensifs** : `attack_result` sur un territoire à NOUS pendant le tour d'un AUTRE → `hud.show_defense_toast` (« ⚠ ONTARIO ATTAQUÉ PAR X — pertes : 2 », variante « PERDU — conquis par X ») + `play_sfx("under_attack")` — pure mise en scène (données déjà diffusées à tous). Le plus récent remplace l'ancien (aucun empilement).
> - **i18n** : 3 clés (`FEED_FILTER_TOOLTIP`, `TOAST_*`). Piège n° 4 respecté : rien ne repeint le plateau (les entrées s'ajoutent au journal ; le VS garde sa file).
> - **Validation** : **NOUVEAU [`tools/test_e4_feed.tscn`](tools/test_e4_feed.tscn)** — **18 asserts verts** (attack_result complet → 5 entrées ordonnées, catégories/majors exacts ; repli type inconnu sans perte ; zone_entries ; rendu HUD réel : `[url]`, filtre, kill feed, toast) ; `--import` = 0 ERROR. **AUCUN COMMIT.**

### 8.75-front (lot E3 — PLAN_EXPERIENCE). Chrono serveur au HUD + bandeaux de tour/phase `phase_banner` — ✅ FAIT (2026-07-15)
> **Contrat réseau complet : CONTRAT_RESEAU §8.75** (`turn_timer`/`server_time` dans l'état, message léger `timer_update` — SEUL lot backend du plan avec E11 → actif après redéploiement VPS ; d'ici là le client fonctionne en repli legacy, §9.2).
> - **`hud.gd`** : `%TimerLabel` piloté par l'ÉCHÉANCE SERVEUR (`apply_server_timer`/`apply_timer_update` — offset `server_time − horloge locale`, immunisé horloge fausse) ; l'estimation locale historique (`_phase_turn_limit`/`add_time_to_timer`) devient le REPLI legacy (état sans `server_time`) ; `turn_timer` null (tour de bot) → « --:-- ». `reason == "time_bank"` → **flotteur « +N s » or** près du chrono. **Pré-alerte AFK** (`_render_remaining`, partagé serveur/legacy) : sous 15 s sur NOTRE tour → rouge + pulse sinus + `play_sfx("timer_tick")` à chaque seconde. Alias public `phase_name()`.
> - **NOUVEAU [`scenes/components/phase_banner.tscn`](scenes/components/phase_banner.tscn) + [`scripts/ui/phase_banner.gd`](scripts/ui/phase_banner.gd)** : CanvasLayer (calque 2) haut-centre NON bloquant (IGNORE partout) — stinger ~1,1 s (slide + fondu, panneau angulaire gunmetal à flancs d'accent §2). Déclencheurs dans `main._maybe_show_banner()` (appelé par `_refresh` → jamais pendant un combat, piège n° 4) : **nouveau tour** → « TOUR DE <PSEUDO> » (couleur plateau) ; **NOTRE tour** → **« À VOUS DE JOUER, COMMANDANT »** (or) + `play_sfx("your_turn")` + `DisplayServer.window_request_attention()` si fenêtre non focus ; **nouvelle phase** (même tour) → « PHASE : ATTAQUE » (cyan, libellés `hud.phase_name`). Priorité tour > phase, un seul stinger à la fois (le nouveau remplace l'ancien).
> - **i18n** : 3 clés `BANNER_*` (fr/en/it). SFX `your_turn`/`timer_tick` silencieux tant que E9 n'a pas posé les blips (`play_sfx` ignore les noms inconnus).
> - **Validation** : `tools/test_e3_timer.tscn` **9 ✅** (repli legacy intact, « 00:42 » serveur, bot « --:-- », time_bank) + `--import` 0 ERROR. **AUCUN COMMIT.**

### 8.74 (lot E2 — PLAN_EXPERIENCE). Le combat raconte les héros — Split-Screen VS enrichi — ✅ FRONTEND FAIT (2026-07-15)
> **Design (E2).** Le VS montre QUI se bat et CE QUE LE DUEL COÛTE. **AUCUN changement backend** : tout vient de `attack_result.hero_duel` (§8.61 : `pp_delta`, `attacker_pp`, `damage`, `defender_pv`, `defender_pv_max`, `hero_died`) + `GameState.players`.
> - **Transport (`main.gd::_play_combat_resolution`)** — le Dictionary d'options du VS est enrichi (RÉTRO-COMPATIBLE) : `attacker/defender_pid|name|color|hero` (pseudo transmis SEULEMENT si le joueur existe — un owner « neutre » -1 afficherait sinon `[IA] Bot 1` ; couleur = `board.get_player_color`), `hero_duel` (null si héros non initialisés), `attacker/defender_garrison_before|after`. **NOUVEAU snapshot `_displayed_garrisons`** (à côté de `_displayed_owners` dans `_refresh`) : l'« avant » exact des garnisons — le reconstruire par après+pertes serait FAUX en cas de conquête (troupes déplacées en plus des pertes). ⚠️ `hero_of` reflète l'état POST-combat : PV pré-duel du défenseur = `defender_pv + damage` (jamais d'état antérieur).
> - **Affichage (`split_screen_vs.gd`, tout par CODE — insertion relative, `.tscn` intact)** : rôles → **`⚔ ASSAILLANT — <PSEUDO>` / `🛡 DÉFENSEUR — <PSEUDO>`** (couleur joueur, libellés historiques conservés si pseudo absent — §9.2) + chip `NIV n` sous chaque rôle ; **barres PV héros** sous les portraits (attaquant statique + **jauge PP** bornée `[pp_min, pp_max]`, tooltip `HUD_HERO_PP` ; défenseur part des PV PRÉ-duel et **encaisse en Tween 0,6 s** via `tween_method` — valeur + teinte `war_roster.pv_color` + libellé animés ensemble) ; **garnisons `🪖 12 ➜ 9`** sous les dés par camp ; **flotteurs héros** via le nouveau **`_spawn_floater` générique** (refactor de `_spawn_damage_number`) : `-N PV` cramoisi 130 px côté défenseur (PLUS GROS que les pertes de troupes, plus haut pour ne pas se chevaucher) + `±N PP` cyan/orange côté attaquant + SFX `hero_hit` (silencieux tant que E9 n'a pas posé le blip).
> - **Permadeath (`hero_duel.hero_died`)** : gel 0,4 s → vignette rouge plein écran → **tampon diagonal « HÉROS ABATTU — <PSEUDO> ÉLIMINÉ »** (SystemFont Black Ops One→Impact, punch TRANS_BACK, rotation −8°) + `play_sfx("hero_down")` + **prolongation +1,2 s** de la surcouche (`MAX_LIFETIME` 12→14 s, marge du garde-fou préservée).
> - **`hero_duel == null`** (héros non initialisés / défenseur déjà mort / serveur ancien) : AUCUNE UI héros montée (pas de barres, flotteurs ni « 0 » fantômes).
> - **Helpers PURS statiques** (critères d'acceptation) : `duel_pre_pv(duel)` (PV avant = `defender_pv + damage`, borné `pv_max` en overkill) et `pp_gauge_value(duel, hero)` (bornage PP) + `_self_check()` debug (pattern G4).
> - **i18n** : 4 clés `VS_*` (fr/en/it) ; `ROSTER_LEVEL`/`HUD_HERO_PV`/`HUD_HERO_PP` réutilisées.
> - **Validation** : **NOUVEAU test maison [`tools/test_e2_vs.tscn`](tools/test_e2_vs.tscn)** — 2 résolutions headless complètes (stub intégral avec permadeath + stub `hero_duel=null`), **7 asserts verts** ; `--import` + boot `main.tscn` + re-run test E1 = **0 ERROR**. **AUCUN COMMIT.**

### 8.72 bis (lot G2 — PLAN_EVOLUTIONS). DURCISSEMENT bots/draft — resync `draft_state`, rebours d'auto-verrouillage, filets anti-gel — ✅ FRONTEND + BACKEND FAIT (2026-07-14)
> **Contrat complet + les 5 causes racines corrigées : CONTRAT_RESEAU §8.72 (encart « DURCISSEMENT G2 »).** Symptômes traités : le lobby ne démarrait pas tout seul à l'échéance du remplissage IA ; les bots « ne choisissaient pas de faction » (écran de draft figé à 1/3) ; gels en chaîne (deadlock serveur de fin de draft, handoff bot → humain sans minuterie).
> - **`network_manager.gd`** : signal **`draft_state_received(locked)`** + message serveur **`draft_state`** (photographie des verrouillages — réponse PRIVÉE à la nouvelle action **`get_draft`**, helper `request_draft_state()`) ; propriété **`last_draft_deadline_at`** (échéance UNIX d'auto-verrouillage, posée par `game_started` ET `draft_state` — même pattern que `last_bot_fill_at`, signaux inchangés).
> - **`faction_selection.gd`** : à `_ready`, **resynchronisation `get_draft`** (les `faction_locked` des bots partaient PENDANT la transition de scène → perdus, compteur figé) ; attendus = joueurs **ACTIFS** (`is_active`, lecteur défensif `_is_player_active`) + écoute de **`player_abandoned`** (un partant ne verrouillera jamais) ; **filet `game_state_updated`** : `stage == "playing"` → bascule inconditionnelle vers l'arène ; garde anti double `change_scene` (`_left`) ; **compte à rebours « ⏳ VERROUILLAGE AUTO DANS %d s »** (30 dernières secondes, or §2) — 1 clé i18n `FS_AUTO_LOCK_IN`.
> - **Backend (rappel — détail CONTRAT_RESEAU §8.72)** : fill auto-démarre (fin du self-cancel) ; `submit_bot_blind_deploys(room_id, state)` SOUS le verrou de l'appelant (fin du deadlock) ; rebours `DRAFT_TIMEOUT_S` 60 s + auto-verrouillage faction provisoire ; `_draft_complete` sur actifs ; watchdog de tour bot + `_post_action_timer` après chaque action bot ; `spy_objective` résolu par le runner.
> - **Validation** : backend **NOUVEAU `test_bot_flow.py` 36 ✅ / 0 ❌** + 6 suites affectées re-vertes ; frontend `--import` + boot headless `faction_selection`, `waiting_room` = **0 ERROR**. **AUCUN COMMIT.**

### 8.70 (lot G3 — PLAN_EVOLUTIONS). Mode OBSERVATEUR pour les éliminés + re-queue en 1 clic — ✅ FRONTEND (+ test backend) FAIT (2026-07-14)
> **Design (G3).** Le permadeath héros (§8.61) rend l'élimination précoce fréquente : l'éliminé reste désormais connecté en **observateur** (caméra libre + Intel + chat) avec un bouton **REJOUER** qui le remet en file immédiatement. Aucune info secrète supplémentaire (les objectifs adverses restent masqués — anti-collusion).
> - **NOUVEAU [`scenes/ui/spectator_overlay.tscn`](scenes/ui/spectator_overlay.tscn) + [`scripts/ui/spectator_overlay.gd`](scripts/ui/spectator_overlay.gd)** : bandeau HAUT-CENTRE « ★ K.I.A. — MODE OBSERVATEUR » (panneau gunmetal, titre or, encoches §2), boutons **⟳ REJOUER** (or, anti double-clic) et **✕ QUITTER** (rouge). **Non bloquant** : `mouse_filter = IGNORE` sur le plein-cadre — le plateau reste navigable, le chat ouvert. View pure : 2 signaux (`requeue_pressed`/`quit_pressed`), main.gd décide.
> - **`main.gd`** : `_maybe_show_spectator()` (à chaque refresh — overlay UNE fois quand `PlayerState.status == "eliminated"` ou `is_dead`, jamais après un `winner_id`) + **`_input_blocked()` DURCI** : un éliminé ne peut JAMAIS émettre d'action de jeu (le serveur refuse déjà ; l'UI ne propose plus rien). QUITTER = socket coupé + retour `main_menu` ; échec de re-queue → retour `lobby_screen`.
> - **`tactical_camera.gd` — navigation LIBRE** (`set_free_navigation(true)` pour l'observateur) : **pan au drag droit/molette-enfoncée + zoom molette** (borné : min = vue plein plateau, max ×4, position clampée au cadre 2720×1530). Désactivée = comportement historique intact (vue pilotée).
> - **`network_manager.gd::requeue()`** (helper PARTAGÉ) : ferme le WS → `DELETE /lobby/rooms/{id}/leave` (échec toléré) → `GET /lobby/rooms` → **rejoint la 1ʳᵉ salle `waiting` publique non pleine** (salle remplie entre-temps → nouveau cycle) **sinon crée** une salle (publique, 6 places) → socket NEUF + `waiting_room.tscn`. Signal **`requeue_failed(message)`** en cas d'erreur.
> - **`operation_report.gd`** : bouton **« ⟳ REJOUER »** construit par code à côté du retour lobby (signal `requeue_requested` → même `requeue()`) — bénéficie à TOUS les joueurs en fin de partie.
> - **`hud.gd`** : main de cartes **toujours inspectable** hors de son tour, désormais EXPLICITE — vignettes visibles mais **désactivées** (lecture seule, tooltip adapté) quand ce n'est pas son tour de jeu (ou éliminé).
> - **Backend (vérification, aucune refonte)** : un éliminé garde son socket et reçoit les états redactés (le broadcast couvre tous les sockets) ; `_maybe_abandon_on_disconnect` ignore les non-`alive` (AUCUN forfait posthume, aucune minuterie). **Prouvé par test** : `test_turn_loop_fixes.py` section [8] — **37 ✅ / 0 ❌**.
> - **Validation** : `--import` + boot headless `main`, `spectator_overlay`, `operation_report`, `waiting_room` = **0 ERROR**. 5 clés i18n. **AUCUN COMMIT.**

### 8.69 (lot M5 — PLAN_EVOLUTIONS). Skins équipables et VISIBLES — registre SkinData + résolution VS/draft/boutique — ✅ FRONTEND FAIT (2026-07-14)
> **Contrat complet : CONTRAT_RESEAU §8.69 (lot M5).** Le skin équipé est un champ PUBLIC de l'état (`PlayerState.equipped_skin`) — **les deux joueurs voient le skin de l'autre** dans le Split-Screen VS (moment vitrine du cosmétique).
> - **NOUVEAU registre data-driven [`resources/skins/`](resources/skins/)** (pattern factions §4.3) : `skin_data.gd` (`class_name SkinData` — id = ShopItem.id du catalogue serveur, faction_id, name_key, portrait_path, model_path, accent_override) + **5 `.tres`** (4 skins du catalogue + `skin_pass_s1`) en **placeholders teintés** (chemins vides → l'affichage retombe sur le ColorRect `accent_override`, convention §4.3). Déposer de vrais assets = remplir portrait_path/model_path, aucun code à toucher.
> - **`split_screen_vs.gd`** : `_load_faction(faction_id, fallback_accent, equipped_skin := "")` — un SkinData (id + faction cohérents, `_find_skin` scan DirAccess export-safe) surcharge `hero_path`/`hero_model_path` (si les chemins EXISTENT) et l'accent. Les skins des deux camps arrivent par `meta.attacker_skin/defender_skin`, lus des PlayerState PUBLICS par `main.gd::_equipped_skin_of` dans `_play_combat_resolution`.
> - **`faction_selection.gd`** : `_set_portrait` applique la MÊME résolution pour SON skin équipé (bloc `equipped` de `GET /shop/inventory`, déjà chargé depuis M3) — le carrousel montre le héros habillé. ⚠️ Le panneau héros du HUD in-game (§8.60) n'affiche AUCUN portrait (barres de stats seules) → rien à skinner là.
> - **`shop.gd`** : bouton **ÉQUIPER (or) / ÉQUIPÉ ✓** sur chaque skin possédé (onglets Boutique ET Inventaire) → `NetworkManager.equip_skin(skin_id)` / `unequip_skin(faction_id)` + signaux `skin_equipped(data)` (réponse = inventaire complet → handler d'inventaire réutilisé) / `skin_equip_failed(message)`. 3 clés i18n.
> - **Validation** : `--import` + boot headless `shop`, `faction_selection`, `main`, `split_screen_vs` = **0 ERROR**. **AUCUN COMMIT.**

### 8.63 (lot G4 — PLAN_EVOLUTIONS). Prévision de combat au survol — module pur `CombatOdds` + ligne HUD — ✅ FRONTEND FAIT (2026-07-14)
> ⚠️ **Numérotation :** ce fichier possédait DÉJÀ des entrées §8.62-§8.68 (logo, audio…) AVANT que `PLAN_EVOLUTIONS.md` ne réserve §8.62-§8.72 pour ses lots. Pour ne pas casser les renvois du plan, les entrées issues du plan sont suffixées « (lot XX — PLAN_EVOLUTIONS) » — à désambiguïser des homonymes historiques de CE fichier.
> **Design (G4).** Pendant la **Phase 3**, source sélectionnée + **survol** d'un territoire ennemi adjacent → le HUD affiche `PRÉVISION : victoire NN % · pertes est. N,N (hors pouvoirs à états)`. **Client-only, calcul EXACT** (pas de Monte-Carlo), **AUCUN appel réseau ni modification serveur**.
> - **NOUVEAU [`scripts/game/combat_odds.gd`](scripts/game/combat_odds.gd)** (`class_name CombatOdds`, statique, pur) : réplique EXACTE de `engine.py::_handle_attack` — tri décroissant, comparaison des `min(a,d)` paires, **égalité au défenseur**, et les **5 flags de dés** du registre factions (`attack_reroll_low_dice` Phalanges, `attack_reroll_all_low_dice` Razzia/Pillards, `first_strike_bonus_die` Chasseurs, `terror_extra_kill` Écorcheurs plafonné garnison, `defense_double_extra_kill` Aegis plafonné « la source garde ≥ 2 après pertes + départ minimum »). Implémentation par **distributions par camp** (≤ 6⁴ tirages + branches de relance, agrégés en multiensembles triés) croisées ensuite → exact ET rapide. `conquest_probability(att, def, atk_flags, def_flags)` = **DP mémoïsée** sur (att, def) avec dés client réels (`clampi(att-1,1,3)`), arrêt sous 2 unités, garnisons plafonnées à 60. **Auto-vérification debug** (3v2 sans flags = 2890/2611/2275 / 7776, tolérance 1e-9) au premier appel.
> - **Câblage.** `board.gd` : signaux `territory_hovered/territory_unhovered` (Area2D `mouse_entered/exited`, relais pur §6.1). `main.gd` : `_on_territory_hovered` (garde phase 3 / mon tour / source / cible ennemie adjacente / non bloqué) → `CombatOdds.conquest_probability` avec les **modificateurs lus des `.tres`** (`_faction_modifiers`, cache) → `hud.show_forecast` ; unhover/désélection → `hide_forecast`. **Préchauffage différé** de la DP au chargement de l'arène (`_warm_combat_odds`, ~100 ms invisibles) → premier survol < 1 ms (0,004 ms/survol mémoïsé mesuré).
> - **HUD (`hud.gd`).** Ligne `CombatOddsLabel` créée par code SOUS `%InstructionLabel` : **cyan si ≥ 65 %**, **or si 40-65 %**, **rouge si < 40 %** ; pertes attendues au format « N,N » ; mention discrète « (hors pouvoirs à états) » (cartes/boucliers/duel héros non simulés).
> - **Validation.** Cross-check headless contre une énumération brute-force Python EXACTE (fractions) de la logique moteur : **58/58 issues identiques à 1e-9** (12 cas d'échange dont Aegis+terreur croisés et plafonds serrés, 4 conquêtes DP). `--import` + boot `main.tscn` = 0 ERROR. **AUCUN COMMIT.**

### 8.65 (lot M2 — PLAN_EVOLUTIONS). Écran OPÉRATIONS branché + onglet menu à pastille or — ✅ FRONTEND FAIT (2026-07-14)
> **Missions quotidiennes & hebdomadaires (robinet de Coins, contrat complet : CONTRAT_RESEAU §8.65 lot M2).** L'ex-maquette `missions.tscn`/`missions.gd` (mock §8.55, orpheline depuis le retrait de l'ancienne top-nav) est **réécrite et BRANCHÉE au backend réel**.
> - **`scripts/ui/missions.gd`** (écran construit par code, charte §2) : sections **QUOTIDIENNES / HEBDOMADAIRES** avec par mission — nom + description i18n (`tr(name_key/desc_key)` du serveur), **ProgressBar cyan** (or quand complétée), compteur `cur/goal`, **badge hexagonal or** (récompense Coins), bouton **RÉCLAMER** (or, anti double-clic via `_claim_in_flight`) / **✔ RÉCLAMÉE** (désactivé) / **EN COURS** ; **comptes à rebours de reset** (04:00 UTC / lundi — epoch dérivé des ISO serveur, suffixe `Z` retiré avant `Time.get_unix_time_from_datetime_string`) ; statut or « +N Coins » (+ mention bonus Pass) ou rouge en échec ; **re-fetch systématique après claim** (source de vérité serveur). Retour → `main_menu` via `TransitionManager`.
> - **`network_manager.gd`** : `fetch_missions()` / `claim_mission(mission_id)` + signaux `missions_loaded(data)` / `mission_claimed(data)` / `mission_claim_failed(message)` (pattern des signaux shop).
> - **`main_menu`** : nouvel onglet **« OPÉRATIONS »** (`@export var missions_tab`, nœud `MissionsTab` entre BOUTIQUE et CLASSEMENT) ; **pastille or « ●N »** = `claimable_count` (fetch au `_ready`, re-rendue au changement de langue via `_update_missions_badge`).
> - **i18n (R4)** : **44 clés** ajoutées à `translations/ui_strings.csv` (fr/en/it) — `MENU_TAB_MISSIONS`, `MISSIONS_*` (UI) et `MISSION_<X>_NAME/_DESC` (14 missions).
> - **Validation** : `--import` + boot headless `main_menu.tscn` ET `missions.tscn` = **0 ERROR**. **AUCUN COMMIT.**

### 8.68. Musique de menu — « BASE RAP » sale/street DISTORDUE (vibe « Flash Bling », sans copyright) — ✅ FRONTEND FAIT
> **⚠️ MAJ (itérations utilisateur) — DIRECTION FINALE = INSTRUMENTAL, plus de voix.** Parcours : (1) demande initiale « musique de menu **chantée par un trappeur** » style *Tyga, Travis Scott – Flash Bling* ; cadrage honnête : on **ne peut PAS** synthétiser une vraie voix humaine rappée, on **n'utilise PAS** le titre protégé. (2) 1ʳᵉ livraison = beat + **hook vocal par synthèse de formants** (autotune sans paroles). (3) Retour utilisateur « **plus de hip-hop / plus de basses** » → 808 + sub renforcés, groove kick/clap+snare, swing. (4) Retour utilisateur « **plus sale/distordu, une VRAIE base rap, pas ce son robotique** » → **la voix de synthèse est RETIRÉE** (jugée robotique — limite assumée) et remplacée par un **lead mélodique « sample » dark**, avec **saturation de bus** et **craquement de vinyle** pour la grana street. La piste est désormais un **INSTRUMENTAL** (une « base » sur laquelle un rappeur poserait sa voix). **Remplace** §8.67 dans le menu. **Frontend exclusif.** **AUCUN COMMIT.**
> - **Génération (`tools/gen_menu_vocal_trap.gd`, `extends SceneTree`).** Boucle **27,4 s @ 140 BPM, 16 mesures (4 cycles), stéréo 44,1 kHz**, vamp ré mineur **i–i–VI–V** (Dm–Dm–Bb–A), cohérence dark/post-apo. **Basses en avant** : **808 DISTORDUE** (growl : 2e+3e harmoniques + `tanh` drive `EOE_DRIVE`) **+ sinus de SUB une octave en dessous** (poids « ressenti »). **Drums hip-hop** : kick à bounce (frappe 1 + « and of 2 » + syncope + ghost), backbeat demi-temps = **clap + snare/rullante superposé** (crack), hi-hats avec **léger swing** + rolls ; kick en léger overdrive.
> - **Hook mélodique = lead « sample » DARK (remplace la voix).** Mélodie `HOOK` (4 mes., transposée −12 = registre médian chaud), portée par des **nappes de dent-de-scie désaccordées** + **wobble vinyle** (micro-dérive de hauteur) + **passe-bas poussiéreux** (2400 Hz) + **saturation** (`tanh`) → sonne comme un échantillon chopé, **rien de robotique**. Joue sur les cycles 0/1/3 ; **cycle 2 = « beat seul »** (basse + drums respirent = creux de couplet).
> - **Grana « sporco » street.** **Saturation de BUS** (pré-gain `BUS_PREGAIN` → `tanh` `BUS_DRIVE` → **high-cut chaud** `BUS_HICUT` ≈ 11 kHz = enlève le digital brillant, rapproche du son cassette/vinyle) + couche de **vinyle** (`_add_vinyl` : souffle filtré bas + craquements/pops aléatoires, niveau `VINYL`). Pad sombre **poussiéreux** (cutoff 1500) discret sous le beat.
> - **Légal & original.** Aucune voix, aucun sample tiers — **style/vibe** seuls repris (non protégeables). → **aucun risque de copyright**. *(Pour une VRAIE voix de rappeur, seule voie : un enregistrement réel ou une génération IA externe — Suno/Udio — déposé en drop-in dans `assets/audio/music/menu_ambient.*`.)*
> - **Zéro code.** L'`AudioManager` joue déjà `menu_ambient.wav` via `start_menu_ambient()` (override §8.64). **Propriété d'asset (règle anti-footgun §8.66) :** `menu_ambient.wav` a **TROIS** générateurs → `gen_menu_vocal_trap.gd` = **ACTIF**, `gen_menu_trap.gd` (§8.67) **et** `gen_menu_music.gd` (§8.65) = **archivés** ; en-têtes marqués « n'en lancer qu'un ». `.import` inchangé (**PCM** `compress/mode=0` + boucle).
> - **Validation (Godot 4.7-stable headless).** Génération **0 ERROR** (`menu_ambient.wav`, 1 209 600 images, 27,4 s) ; `--import` **0 ERROR** (resté PCM+loop) ; boot `main_menu.tscn` (`start_menu_ambient`) **0 ERROR**. ⚠️ **Rendu sonore non écouté** (headless = « Dummy ») → à valider à l'oreille ; réglages « sporco » en tête de fichier (`EOE_DRIVE`, `BUS_DRIVE`, `BUS_HICUT`, `VINYL`) + mélodie `HOOK`, niveaux, dans `tools/gen_menu_vocal_trap.gd`. ⚠️ **Aucun commit.**

### 8.67. Musique de menu — bascule vers un brano « dark melodic trap » ORIGINAL (vibe Travis Scott/Tyga, sans copyright) — ✅ FRONTEND FAIT
> Demande utilisateur : une musique de menu **dans le style** d'un titre trap/hip-hop existant, mais **légalement** et **sans copyright**. Cadrage validé avec l'utilisateur : on **n'utilise PAS** le titre protégé (mélodie/paroles/enregistrement) ; on **compose un brano ORIGINAL** dans le même *genre/vibe* (genre & ambiance non protégeables) — synthétisé en Godot comme les autres pistes — et il **remplace** le thème « Interstellar » (§8.65) dans le menu. **Frontend exclusif.** **AUCUN COMMIT.**
> - **Génération (`tools/gen_menu_trap.gd`, `extends SceneTree` sans `--path`).** Rendu événementiel, boucle **27,4 s @ 140 BPM (ressenti demi-temps), 16 mesures, stéréo 44,1 kHz**, ré mineur harmonique, vamp **i–i–VI–V** (Dm–Dm–Bb–A, le V/sensible DO# = tension « menaçante »). Couches caractéristiques du **trap** : **808** sub-basse **glissée** (glide d'attaque + glide vers l'accord suivant) **saturée** (`tanh`) = pièce maîtresse ; **kick** claquant (1 + syncope) ; **clap** en **demi-temps** (temps 3, 3 bursts de bruit passe-haut = « flam ») ; **hi-hats** croches + **rolls** (16ᵉ/triolets en fin de mesure, crescendo) ; **cloche** inharmonique lugubre (mélodie sparse, ping-pong stéréo) ; **pad** sombre (saw désaccordé filtré). Boucle **sans jointure** (808/pad/reverb continus + repli de la queue).
> - **Légal & original.** Le fichier est une **création 100 % originale** : seuls le *style* (808, hats roulés, demi-temps, mineur sombre) et la *vibe* sont repris — **aucune** mélodie, suite d'accords signature, parole ou sample d'un titre existant. → **aucun risque de copyright**.
> - **Zéro code.** L'`AudioManager` joue déjà `menu_ambient.wav` via `start_menu_ambient()` (override §8.64) → il suffit que le fichier change. **Propriété d'asset (règle anti-footgun §8.66) :** `menu_ambient.wav` a maintenant **DEUX** générateurs possibles (`gen_menu_trap.gd` = ACTIF, `gen_menu_music.gd` = Interstellar **archivé**) qui visent le **même fichier** → en-têtes des deux scripts marqués « n'en lancer qu'un ». `.import` inchangé (déjà **PCM** `compress/mode=0` + boucle, §8.65).
> - **Validation (Godot 4.7-stable headless).** Génération **0 ERROR** (`menu_ambient.wav`, 1 209 600 images, 27,4 s) ; `.import` resté PCM+loop ; `--import` **0 ERROR** ; boot `main_menu.tscn` (`start_menu_ambient`) **0 ERROR**. ⚠️ **Rendu sonore non écouté** (headless = « Dummy ») → à valider à l'oreille ; réglages (tempo, drive 808, densité des rolls, niveaux, mélodie `MEL`) dans `tools/gen_menu_trap.gd`. ⚠️ **Aucun commit.**

### 8.66. Audio de COMBAT — musique tendue de l'arène (`battle_ambient`) + SFX de dés (`die_lock`/`impact`) — ✅ FRONTEND FAIT
> Suite directe de §8.64/§8.65 : l'**arène était SILENCIEUSE** (`main.gd` coupait l'ambiance des menus à l'entrée, `stop_ambient()`) et le **Split-Screen VS** (résolution visuelle d'un combat aux dés) n'avait **aucun son**. On comble les deux trous **dans le même cadre drop-in** (override par vrais assets + repli synthétisé, API appelants intacte). **Frontend exclusif** (actif au relancement du client). **AUCUN COMMIT** (working tree laissée à l'utilisateur).
> - **Musique de combat (`tools/gen_battle_music.gd` → `assets/audio/music/battle_ambient.wav`).** Générateur `extends SceneTree` (sans `--path`, méthode média §CLAUDE), même boîte à outils de synthèse que §8.65 mais arrangement **plus sombre et martial** : boucle **38,4 s @ 100 BPM, 16 mesures, stéréo 44,1 kHz**, ré mineur cadence **i–VI–iv–V** (Dm–Bb–Gm–**A majeur** = dominante de tension non résolue → moteur d'angoisse). Couches : **tambours de guerre** (toms graves accordés, motif militaire, doublés en 2ᵉ phrase), **pédale-sub de dread**, **kick martial** (1 & 3) + charley off-beat, **nappe de cordes dissonante** (saw désaccordé filtré, swell lent), **ostinato grave menaçant** (croches racine/quinte, ping-pong stéréo), **stabs de power-chord** heavy rock épars (saw→`tanh`→passe-bas, double-track L/R), **booms** de phrase et **risers de bruit** (filtre qui s'ouvre) aux jointures. **Boucle sans jointure** (repli de la queue sur la tête, idem §8.65).
> - **SFX de combat (extension de `tools/gen_audio_assets.gd`).** Deux nouveaux mono : **`die_lock`** = claque sèche (transitoire mat de bruit lissé + corps grave bref) jouée à **chaque dé qui se verrouille** sur sa valeur ; **`impact`** = coup encaissé (sub-boom à pitch descendant + claquement métallique inharmonique + souffle) joué à la **révélation des pertes** (un seul impact, même si les deux camps perdent). Mêmes traitements que les autres SFX (passe-bas + échos discrets).
> - **`AudioManager` (lecteur de musique UNIQUE + bascule).** `start_menu_ambient()`/`start_battle_ambient()` délèguent à un nouveau **`_play_music(base_name)`** : charge (override `assets/audio/music/<nom>.{ogg,wav,mp3}` > synthèse) **et met en cache** la piste, puis **bascule** le `_music_player` dessus si différente (le menu et le combat ne jouent **jamais en même temps**), sans relancer une piste déjà en cours. SFX `die_lock`/`impact` ajoutés à la banque (override > synthèse `_make_die_lock`/`_make_impact`). Repli synthétisé de la musique de combat `_make_battle_pad` (drone de dread + pouls de tom) si le `.wav` manque / headless. `SFX_NAMES` étendu ; `_music_cache` libéré dans `_exit_tree`.
> - **Câblage.** [`scripts/game/main.gd`](scripts/game/main.gd) `_ready` : `stop_ambient()` → **`start_battle_ambient()`** (transition propre, plus de silence). [`scripts/game/split_screen_vs.gd`](scripts/game/split_screen_vs.gd) : `play_sfx("die_lock")` dans `_lock_die`, `play_sfx("impact")` dans `_show_damage_and_bank` (si pertes). Retour aux menus → `lobby_screen.gd` rappelle `start_menu_ambient()` → rebascule sur la musique de menu.
> - **Import (piège §8.65 réappliqué).** `battle_ambient.wav.import` forcé en **PCM** (`compress/mode=0`, l'importeur 4.7 met QOA *lossy* par défaut sur 38 s de nappe soutenue) + **boucle** (`edit/loop_mode=1`) ; les SFX restent en QOA comme les autres (sons courts). Bouclage aussi forcé à runtime par `_ensure_looped`.
> - **Validation (Godot 4.7-stable headless).** `--import` **0 ERROR** (générateurs + 3 WAV neufs) ; boot `main_menu.tscn` (`start_menu_ambient`) **0 ERROR** ; boot `game/main.tscn` (`start_battle_ambient`) **0 ERROR**. ⚠️ **Rendu sonore non écouté** (headless = pilote « Dummy ») → à valider à l'oreille ; réglages dans les deux `tools/gen_*.gd`. ⚠️ **Aucun commit.**

### 8.65. Musique de menu — thème « Interstellar » (orgue Zimmer + ostinato) avec accents HEAVY ROCK — ✅ FRONTEND FAIT
> Demande utilisateur : une **vraie musique** dans le menu, style **Interstellar** (orgue, pulsation montante) avec des **intonations heavy rock**, en restant sur le thème dark/post-apo du jeu. Synthétisée en Godot et déposée comme `menu_ambient.wav` → l'`AudioManager` la joue déjà via `start_menu_ambient()` (override §8.64, **aucun code appelant touché**). **Frontend exclusif.** **AUCUN COMMIT** (working tree laissée à l'utilisateur).
- **Génération (`tools/gen_menu_music.gd`, `extends SceneTree` sans `--path`).** Rendu **événementiel** (chaque note synthétisée dans le buffer), boucle de **43,6 s @ 88 BPM, 16 mesures**, **stéréo 44,1 kHz**. **Progression épique en ré mineur** `i–VI–III–VII` (Dm–Bb–F–C ×4). Couches : **arpège d'orgue** brillant (16 doubles-croches, **ping-pong stéréo**, accent sur les temps = la « pulsation Interstellar »), **pad d'orgue** (drawbars additifs + quinte + chorus, swell lent), **sub/pédale grave** cinématique, **basse** (noires, filtrée), **batterie** (kick 1&3 + **caisse claire backbeat** 2&4 + charley de croches), et — 2ᵉ moitié (mesures 9-16) — **power chords de guitare DISTORDUE** (saw `racine+quinte+octave` → saturation `tanh` → passe-bas de baffle, palm-mute, **double-tracking L/R désaccordé** = largeur rock). **Booms** cinématiques sur les départs de phrase. Montée d'intensité progressive (la guitare entre à mi-boucle).
- **Boucle SANS jointure.** Fréquences et LFO laissés libres mais **basse/kick/pad/arpège continus** à la couture (seule la guitare entre/sort = respiration musicale) + **repli de la queue** (réverbe/sustain qui dépasse le point de boucle est ré-additionné sur la tête). Le bouclage est **forcé à runtime** par `AudioManager._ensure_looped` (corrigé ici, cf. ci-dessous).
- **Import & bouclage — pièges résolus.** (1) L'importeur WAV de Godot 4.7 compresse par défaut en **QOA** (`compress/mode=2`, *lossy*) → forcé en **PCM 16 bits** (`compress/mode=0`) dans le `.import` pour une qualité prévisible. (2) `AudioManager._ensure_looped` calculait `loop_end = data.size()/2` — **faux** en stéréo et en compressé ; corrigé en **`int(get_length() * mix_rate)`** (nombre d'images réel, valable tout format) → la boucle est désormais exacte (`loop_end = 1 924 363` images, 43,64 s).
- **Validation (Godot 4.7-stable headless).** `--import` **0 ERROR** ; ressource = `format=16 bits, stéréo, 44,1 kHz, 43,64 s` ; simulation de `_ensure_looped` → `LOOP_FORWARD`, `loop_end` exact ; boot `main_menu.tscn` (`--quit-after`, appelle `start_menu_ambient`) **0 ligne `ERROR`**. ⚠️ **Rendu sonore non écouté** (headless = pilote « Dummy ») → à valider à l'oreille au lancement du client ; réglages dans `tools/gen_menu_music.gd` (tempo, progression, niveaux de couches, drive guitare). ⚠️ **Aucun commit.**

### 8.64. Audio — système d'OVERRIDE par vrais assets (drop-in) + montée en qualité des placeholders — ✅ FRONTEND FAIT
> Réalisation de l'item **R6 « Audio — RESTE »** : l'infrastructure jouait des **placeholders 100 % procéduraux** (§8.44). On ajoute le **chaînon manquant** pour les *vrais* assets : `AudioManager` charge en priorité des **fichiers déposés** dans `assets/audio/`, **sans aucune retouche de code côté appelants**, et retombe sur la synthèse à défaut. En complément, les placeholders sont **nettement améliorés** (44,1 kHz, sons stratifiés). **Frontend exclusif** (actif au relancement du client). **AUCUN COMMIT** (working tree laissée à l'utilisateur).
- **Override par assets réels (`scripts/managers/audio_manager.gd`).** Nouveau `_load_override(category, name)` : pour chaque SFX (`hover`/`click`/`confirm`/`back`/`sting`) et la musique (`menu_ambient`), tente `res://assets/audio/<sfx|music>/<nom>.{ogg,wav,mp3}` (1ʳᵉ extension trouvée gagne) via **`ResourceLoader.exists` + `load`** (export-safe : résout `.import`/`.remap`, **aucun `class_name`** — même esprit que le scan factions/héros). Si un fichier existe → il **remplace** le placeholder ; sinon → synthèse. La musique chargée d'un fichier est **forcée en boucle** (`_ensure_looped` : `loop=true` pour ogg/mp3, `loop_mode` pour wav). **API publique INCHANGÉE** (`play_sfx` / `start_menu_ambient` / `stop_ambient`) → **aucun des 40+ appelants** (menus, draft, shop, HUD arène, rapport) n'est touché.
- **Dossier drop-in + mode d'emploi.** Nouveaux `assets/audio/sfx/` & `assets/audio/music/` (avec `.gitkeep`) + **[`assets/audio/README.md`](assets/audio/README.md)** (FR) : arborescence, **noms exacts attendus**, extensions acceptées, routage bus `SFX`/`Music` (volumes pilotés par `SettingsManager`), procédure « déposer → `--import` → relancer ». **Zéro ligne de code à écrire** pour brancher de vrais sons.
- **Montée en qualité des placeholders (à défaut d'assets).** `MIX_RATE` **22 050 → 44 100 Hz** (Nyquist 22 kHz → bien plus brillant). `click` = **transitoire de bruit filtré** (« tac ») + corps tonal bref ; `confirm`/`back` = **accords 2 notes** (quinte montante / descente) à queue synthétique ; `sting` = **sub-impact** + corps grave montant + **accord scintillant** (tierce/quinte) + riser de bruit ; nappe d'ambiance = boucle **6 s** avec **LFO de filtre lent**, couche d'« air » bruitée et **fondu de raccord** masquant la jointure. Garde headless (pas de lecture sous le pilote « Dummy ») conservée.
- **Assets WAV « produits » générés (placeholders soignés, à défaut d'assets définitifs).** Nouvel outil rigiocabile [`tools/gen_audio_assets.gd`](tools/gen_audio_assets.gd) (`extends SceneTree`, lancé **sans `--path`** — méthode média §CLAUDE) : synthétise puis **écrit sur disque** les 6 fichiers (`AudioStreamWAV.save_to_wav`) → `sfx/{hover,click,confirm,back,sting}.wav` + `music/menu_ambient.wav`. Plus aboutis que la synthèse runtime : **réverbe à échos** (3 taps discrets non récursifs + passe-bas), **filtrage passe-bas** un pôle, `confirm`/`back` = **accords 2 notes** (quinte ↑ / descente ↓ avec vibrato et harmoniques), `sting` = sub-impact + corps montant + accord scintillant + **riser de bruit** + queue, **ambiance STÉRÉO 8 s en boucle SANS jointure** (partiels à **cycles entiers** sur la durée + LFO à cycles entiers + désaccord stéréo → raccord parfait ; bouclage aussi **forcé à runtime** par `_ensure_looped`). Niveaux relatifs gérés (hover discret → sting fort).
- **Validation (Godot 4.7-stable headless).** `--import` **0 ERROR** (script + 6 WAV) ; boot `main_menu.tscn` (`--quit-after`, appelle `start_menu_ambient`) **0 ligne `ERROR`**. **Override prouvé end-to-end** : les **6 fichiers** résolvent `ResourceLoader.exists=true` et `load` → `AudioStreamWAV`. ⚠️ **Reste (facultatif)** : remplacer ces placeholders WAV par de **vrais assets artistiques** (musique/SFX HD) — il suffit de réécrire les fichiers de même nom (aucun code à toucher).

### 8.63. Logo — nouvelle marque BIOHAZARD tactique (remplace les hex-nœuds) + icône app régénérée — ✅ FRONTEND FAIT
> Demande utilisateur : **changer le symbole du jeu** à partir d'une référence (biohazard néon cyan à nœuds hexagonaux). Choix validés avec l'utilisateur : marque **vectorielle SVG** (pas raster) qui **remplace le glyphe** dans le logo (le wordmark « WASTELAND / WARFARE » reste inchangé). **Frontend exclusif** (actif au relancement du client). **AUCUN COMMIT** (working tree laissée à l'utilisateur).
- **Refonte de [`assets/images/logo_mark.svg`](assets/images/logo_mark.svg).** L'ancien glyphe « 3 hex-nœuds reliés » (§8.57) est remplacé par un **biohazard tactique** : **3 lobes/crescents** cyan `#36C5D9` aux **cornes affûtées** (arcs externe/interne à ouverture différente → corne effilée), **3 nœuds hexagonaux** (territoires / Risk — gunmetal `#0F1318` + liseré cyan) logés dans les lobes, **anneau-triquetra interne** (3 arcs fins) autour d'un **noyau central**. **Symétrie 3×** par `transform="rotate(120/240 60 60)"`. **100 % formes** (`path`/`polygon`/`circle` + `rotate`) — **aucun `<text>`** → rendu **ThorVG OK** (cf. [[godot-env-validation]] : ThorVG ne rend pas `<text>`). `viewBox` `0 0 120 120` (était `120 116`).
- **Propagation automatique.** Le mark est consommé par `ww_logo` (instancié dans **auth, bootloader, lobby, waiting_room, main_menu, top_nav, title_splash**) **et** comme **`config/icon`** du projet (`project.godot`) → le nouveau symbole apparaît partout sans toucher aux écrans.
- **Halo néon cyan (in-engine, `ww_logo.gd`).** Pour coller au look « néon » de la référence : nouvel asset [`assets/images/logo_mark_glow.png`](assets/images/logo_mark_glow.png) = silhouette du biohazard **floutée** teintée cyan (générée en Godot : `load_svg_from_string` → recoloration cyan de l'alpha → flou par décimation/agrandissement 2 niveaux, renforcé ×2). Posé **DERRIÈRE** la marque via une `TextureRect` enfant avec **`show_behind_parent = true`** + ancres centre + box fixe `mark_size × GLOW_SCALE(1.7)` → **déborde visuellement SANS toucher au layout** du VBox (la marque garde sa taille ; aucune régression de mise en page sur les 7 écrans). Nouveaux `@export` : `show_glow` (def. `true`) et `glow_strength` (def. `1.0`, alpha du halo via `modulate`). **Logique mutualisée** dans **`WarzoneUI.attach_mark_glow(mark, mark_px, strength, scale)`** (idempotent, garde par méta) → appelée par `ww_logo` (auth/bootloader/lobby/waiting_room/title_splash) **ET** sur la **petite marque** de la top-bar (`main_menu.gd` `LogoSmall` + `top_nav.gd`, halo plus contenu — `scale 1.5`, `strength 0.85` — pour ne pas baver sur le titre). → le halo est désormais **partout** où la marque apparaît.
- **Valorisation du symbole (demande utilisateur : « trop petit / pas mis en valeur, surtout au menu »).** **(A) Marques agrandies** dans tous les lockups : `auth` `mark_size 42→60`, `bootloader` `42→58`, `lobby` `34→46`, `waiting_room` `32→44` ; petite marque de top-bar `54→72` (`main_menu` `LogoSmall`) et `54→64` (`top_nav`), avec halos recalés. **(B) Splash — biohazard HÉROS (`title_splash.gd`).** L'emblème devient le **protagoniste** de l'ouverture : nouvel **emblème biohazard GÉANT** (`min(340, vp.y*0.36)` px, marque SVG nette + halo `GLOW_TEX` derrière) centré au-dessus, **révélé** (fondu + dézoom élastique `TRANS_BACK`, `sting` audio) puis **halo pulsé en boucle** (alpha 0.5↔1.0 + souffle d'échelle 1.0↔1.07, `TRANS_SINE`). Le composant `ww_logo` du splash passe en **wordmark SEUL** (`show_mark=false`, `show_glow=false`) et glisse SOUS l'emblème ; chevrons repositionnés pour encadrer le wordmark.
- **Icône Windows régénérée — [`assets/images/logo.ico`](assets/images/logo.ico).** Reconstruite **depuis le SVG** (script Godot `extends SceneTree` lancé sans `--path`, `Image.load_svg_from_string` = **le MÊME moteur ThorVG** que l'importeur), **multi-tailles** (16/24/32/48/64/128/256), **PNG-in-ICO**, **fond transparent** (intérieurs d'hexagones gunmetal conservés). En-tête ICO vérifié (`type=1`, 7 entrées).
- **QA visuelle (méthode [[godot-env-validation]]).** Itérations de géométrie **rasterisées via ThorVG** (`load_svg_from_string` → PNG sur fond sombre) pour voir le rendu *réel* du moteur, pas une approximation navigateur. Tous fichiers de travail temporaires supprimés.
- **Validation (Godot 4.7-stable headless).** `--import` **0 ERROR** (SVG + PNG halo réimportés, scripts compilés) ; boot **0 ligne `ERROR`** sur `main_menu`, les 5 écrans à composant `ww_logo` (`title_splash`, `auth_screen`, `bootloader`, `lobby_screen`, `waiting_room`) ET les écrans à `top_nav` (`shop`, `characters_screen`). ⚠️ **Rendu live du halo non photographié** (headless = renderer dummy ; MCP `editor_screenshot`/`project_run` indisponibles cette session) → QA du halo faite sur le **PNG rasterisé** (`load_svg_from_string` + flou, composité marque+halo sur fond gunmetal). ⚠️ **Aucun commit.**

### 8.62. Écran PERSONNAGES — enrichissement du détail héros (XP dans le niveau + descriptions de stats) + i18n — ✅ FRONTEND FAIT
> Demande utilisateur : l'écran §8.59 affichait des infos **périmées** (cap) et **trop succinctes**. Détail enrichi pour que le joueur comprenne chaque statistique et voie sa progression fine. **Frontend exclusif** (`characters_screen.gd` + `ui_strings.csv`) ; **AUCUN COMMIT**.
- **Bloc XP « PROGRESSION » (`_make_xp_block`).** Affiche désormais les **points d'XP possédés dans le niveau en cours** (`X / Y XP DANS LE NIVEAU`, en cyan — la demande explicite) + le **total cumulé à vie** (`TOTAL : Z XP CUMULÉS`), en plus de la barre et du « X XP AVANT LE NIVEAU SUIVANT » / « NIVEAU MAX » conservés. Nouvel eyebrow de section.
- **Bloc Statistiques (`_make_stats_grid` → `_make_stats_block`).** Chaque stat montre maintenant **abréviation + NOM COMPLET** (PV → POINTS DE VIE, PA → POINTS D'ATTAQUE, PB → POINTS DE BOUCLIER, PP → POINTS DE PERFORMANCE, RÉGÉN → RÉGÉNÉRATION) et, en dessous, une **description joueur** (à quoi sert la stat, ex. « PV : santé du héros ; à 0 → élimination définitive »). Colonnes **ACTUEL / NIV. 50** alignées (cellules de valeur à largeur fixe `_value_col`). Helper `_grid_cell` supprimé (devenu mort).
- **i18n (FR/EN/IT).** **13 clés neuves** dans `translations/ui_strings.csv` : `CHAR_XP_HEADER`, `CHAR_XP_IN_LEVEL`, `CHAR_XP_TOTAL`, `CHAR_STAT_{PV,PA,PB,PP,REGEN}_NAME`, `CHAR_STAT_{PV,PA,PB,PP,REGEN}_DESC` (descriptions multi-mots traduites dans les 3 langues). **Correction d'une clé existante devenue fausse : `CHAR_COL_MAX` « NIV. 100 » → « NIV. 50 »** (en-tête de colonne, cap réaligné §8.60). `.translation` régénérées (`--import`).
- **Validation (Godot 4.7-stable headless).** `--import` 0 erreur (script compilé, traductions régénérées) ; **harnais i18n** = les 13 clés **résolvent et se formatent** en FR/EN/IT (descriptions à virgules **NON tronquées** par l'import CSV) ; boot `characters_screen.tscn` (`--quit-after 60`) = **0 ligne `ERROR`**. ⚠️ Rendu peuplé en jeu réel (roster chargé) à confirmer visuellement. ⚠️ **Aucun commit.**

### 8.60. Couche RPG Héros **in-game** (panneau + inspecteur adverse) + réalignement au cahier des charges — ✅ FRONTEND + BACKEND FAIT
> Double objet. **(A)** Journalisation — **jamais faite jusqu'ici** — du **HUD héros en partie** (panneau du héros local + inspecteur du héros adverse), construit **100 % par code** dans `hud.gd`. **(B)** **Réalignement** du réglage RPG sur le cahier des charges (spec re-soumise + décisions verrouillées avec l'utilisateur) : **cap 50**, courbe d'XP figée, paliers 10/20/30/40/50, plafond de PP, coins par niveau, niveau chargé sur la voie WebSocket, + une **barre d'XP** et un **indicateur de tendance PP** neufs dans le panneau. **TDD** (16 suites backend vertes ~882 checks ; Godot `--import` + boot `main.tscn` = 0 ERROR). **AUCUN COMMIT** (working tree laissée à l'utilisateur ; `frontend/` est un dépôt isolé).
- **Panneau Héros local (`hud.gd` : `_build_hero_panel` / `set_hero_panel`).** Widget flottant **toujours visible** (haut-gauche, `MOUSE_FILTER_STOP`), masqué seulement si le héros n'est pas initialisé (`pv_max<=0`, rétro-compat pré-RPG). Affiche : eyebrow **`❯ HÉROS — NIV n`** (rouge + `☠ MORT` si `is_dead`), **barre de PV** + label `PV cur/max` (teinte **rouge danger sous 30 %**, cyan sinon), `PA` + `PB %`, **PP** `%+d (min..max)` + barre, **et NEUFS :** une **flèche de tendance ▲/▼** à côté du PP (compare au dernier PP affiché — ▲ cyan si montée, ▼ rouge si baisse ; mémorisée dans `_hero_pp_last`) et une **barre de progression d'XP or** (`XP in/for` ; libellé **`NIVEAU MAX`** + barre masquée quand `xp_for_level<=0`). Rafraîchi à **chaque mise à jour d'état** via `main._refresh()` → `hud.set_hero_panel(GameState.hero_of(_my_id()))` (la jauge de PP/PV suit le combat ; rafraîchissement **différé après l'animation Split-Screen VS**, cf. `_combat_animating`).
- **Inspecteur Héros adverse (`hud.gd` : `_build_player_inspector` / `set_player_inspector`).** Widget flottant (bas-gauche), ouvert au **clic sur un territoire d'un AUTRE joueur doté d'un héros** (`main._push_inspector` → si `owner != moi` et `GameState.has_hero(owner)`), fermé au clic dans le vide (`board.board_cleared` → `main._on_board_cleared_inspector`). Affiche pseudo coloré (+ `☠`) et la ligne de stats — **désormais préfixée du `NIV n`** (le niveau, exigé par le cahier, était omis) — `NIV n • PV cur/max • PA • PB % • PP %+d`. **NEUF — rafraîchissement temps réel :** la cible inspectée est mémorisée (`main._inspected_enemy_id`) et **re-poussée à chaque `_refresh()`** (`main._refresh_enemy_inspector`), si bien que les PV/PP d'un adversaire **chutent à l'écran après un duel** au lieu de rester figés à l'instant du clic. Stats **PUBLIQUES** (la State Redaction ne masque QUE les objectifs secrets — aucune fuite).
- **Helpers d'état (`game_state.gd`).** `hero_of(pid)` renvoie un dict normalisé (`int`/`float`, piège JSON float §5) `{pv_current, pv_max, pa, pb, pp_current, pp_min, pp_max, level, regen, is_dead, faction, + NEUFS xp_in_level, xp_for_level}` ; `has_hero(pid)` = `pv_max>0`. Champs lus de `players[pid]` (PlayerState).
- **Contrat réseau (champs héros dans le state diffusé).** `PlayerState` porte déjà les stats vivantes (`hero_pv_current/max`, `hero_pa`, `hero_pb` réduction 0..0.30, `hero_pp_current/min/max`, `hero_level`, `hero_regen`, `is_dead`) — **PUBLIQUES**. **NEUFS pour la barre d'XP :** `hero_xp_in_level` / `hero_xp_for_level` = **instantané méta-jeu pris au DÉMARRAGE** (statique pendant le match : les montées de niveau s'appliquent en FIN de partie ; `0/0` = niveau max → barre masquée), peuplés par `hero_progression.get_hero_progress` côté REST (`game.start_game`) **et** WS draft (`router._handle_faction_choice` via `_load_hero_progress`). Le combat diffuse `attack_result.hero_duel {attacker_id, defender_id, pp_delta, attacker_pp, damage, defender_pv, defender_pv_max, hero_died}`. La fin de partie (`game_over.match_rewards`) porte `hero_xp_earned / hero_level / hero_new_level / hero_levels_gained / hero_total_xp / hero_level_up` + **NEUF `hero_coins_earned`**. Tout en **entiers purs**. *(CONTRAT_RESEAU.md n'avait aucune section héros — voir le récap contrat dans son journal.)*
- **Réalignement cahier des charges (Backend — dépôt serveur).** **Cap héros = 50** (`rewards.HERO_LEVEL_MAX` + `factions.HERO_LEVEL_MAX`, à garder synchro). **Courbe d'XP FIGÉE** générée au boot : `step(N→N+1)=round(348·1.05^(N-1))`, N=1..49, **total 69050 @50** (`rewards._HERO_CUM_XP`). **Paliers de stats = exactement 10/20/30/40/50** pour les 10 héros (étaient 6-8 irréguliers), re-tunés en **préservant les totaux max** (mêmes PV/PA/PB qu'au niveau 100 d'avant, atteints au niveau 50). **`pp_max` forcé dans [15,20]** (tanks 15, agressifs 16-18). **Coins par niveau de héros** : `rewards.hero_levelup_coins` (1-5 aléatoire/niveau, **sans gating Pass** pour l'instant — palier « avec Pass » 10-20 différé), crédités sur `User.coins` dans `process_match_results`. **Niveau chargé sur la voie WS** (corrige « héros bloqué niveau 1 » en multi live ; la voie REST le faisait déjà). **Dégâts INCHANGÉS** : `max(1, floor((PA+PP)(1−PB)))`.
- **Fichiers.** Frontend MODIFIÉS : `scripts/ui/hud.gd` (barre XP + tendance PP + niveau dans l'inspecteur), `scripts/game/main.gd` (`_inspected_enemy_id`, `_refresh_enemy_inspector`, `_on_board_cleared_inspector`), `scripts/managers/game_state.gd` (`hero_of` + `xp_in_level/for_level`), `scripts/ui/characters_screen.gd` (commentaires « niveau 100 » → « niveau 50 = cap »), `translations/ui_strings.csv` (clés HUD héros). Backend MODIFIÉS : `api/game/rewards.py`, `api/game/factions.py`, `api/game/hero_progression.py`, `api/game/state_manager.py`, `api/game/state_schemas.py`, `api/game/engine.py`, `api/sockets/router.py`, `api/v1/endpoints/game.py` (+ tests `test_hero_xp/_stats/_heroes_roster/_hero_layer/_hero_faction_draft`).
- **i18n (FR/EN/IT).** Le panneau héros et l'inspecteur adverse étaient **en français EN DUR** → externalisés dans `translations/ui_strings.csv` via `tr()`. Clés NEUVES : `HUD_HERO_EYEBROW` (`❯ HÉROS — NIV %d` / `❯ HERO — LV %d` / `❯ EROE — LIV %d`), `HUD_HERO_DEAD` (`☠ MORT/DEAD/MORTO`), `HUD_HERO_PV`, `HUD_HERO_ATK_DEF`, `HUD_HERO_PP`, `HUD_HERO_XP`, `HUD_ENEMY_HERO_EYEBROW`, `HUD_ENEMY_HERO_STATS` — abréviations localisées des stats (PV→`HP`/`PV`, PA→`ATK`/`PA`, PB→`DEF`/`PB`, PP→`PWR`/`PP`, cohérentes avec les `CHAR_STAT_*` de l'écran Personnages). Réutilise `CHAR_LEVEL_MAX` (« NIVEAU MAX »). **Correction d'une clé existante devenue fausse : `CHAR_COL_MAX` « NIV. 100 » → « NIV. 50 »** (colonne de réf. de l'écran Personnages, cap réaligné). `.translation` régénérées (`--import`). **Vérifié** par harnais headless : les 8 clés résolvent + se formatent correctement en **FR / EN / IT** (`%d`, `%+d`, `%%`).
- **Validation.** Backend : **16 suites vertes** (`test_hero_xp` 35, `test_hero_stats` 188, `test_heroes_roster` 247, `test_hero_layer` 32, `test_hero_combat` 28, `test_hero_faction_draft` 17, `test_objectives_double` 25, `test_repro_roundtrip` 16, + suites moteur/redaction/rewards non régressées — 0 ❌). Frontend (Godot 4.7-stable headless) : `--import` 0 erreur + boot `main_menu.tscn` ET `main.tscn` (`--quit-after 40`) = **0 ligne `ERROR`** (le boot a instancié le HUD réel et `_build_hero_panel` avec les nœuds XP). ⚠️ **Rendu visuel en partie réelle (panneau peuplé) non capturé** (headless) — à confirmer en jeu. ⚠️ Backend → **redéploiement VPS** requis pour être actif en prod. ⚠️ **Aucun commit.**

### 8.59. Écran PERSONNAGES (héros par faction) — écran neuf « Warzone Command » + endpoint `GET /api/v1/heroes` — ✅ FRONTEND + BACKEND FAIT
> Sprint RPG & Survie : le joueur voit **ses héros (1 par faction, 10 factions)** et sélectionne un personnage pour afficher **toutes ses stats détaillées** (niveau, XP, PV/PA/PB/PP/Régén au niveau courant ET au niveau 50 = cap, pouvoir, paliers). Écran accessible depuis la **navbar du menu principal** (onglet `PERSONNAGES`). **AUCUN COMMIT** (le frontend est un dépôt isolé géré par l'utilisateur). ⚠️ **Cap réaligné à 50** (était 100) — voir §8.60.
- **Backend — `GET /api/v1/heroes` (authentifié, `get_current_user`).** NEUF `api/v1/endpoints/heroes.py` (couche fine : lecture SEULE de `HeroProgression` → `{faction_id: xp_total}`) déléguant au module PUR NEUF `api/game/hero_roster.py` (`build_hero_roster`). Réutilise STRICTEMENT l'existant : `factions.resolve_hero_stats`/`get_faction`/`get_faction_hero`/`FACTION_IDS`/`HERO_LEVEL_MAX` + `rewards.hero_level_for_xp`/`hero_total_xp_for_level`/`hero_xp_to_next_level`. Le **niveau est dérivé de l'XP totale** (source unique, comme `HeroProgression`) → `xp_in_level`/`xp_for_level` toujours cohérents. Aucune ligne n'est créée pour afficher (défaut **niveau 1 / 0 XP**). Tri selon `FACTION_IDS`. Réponse (⚠️ entiers PURS, piège float §5) : `{ "heroes": [ { faction_id, faction_name, hero_power, level, xp_total, xp_in_level, xp_for_level, xp_to_next, stats{pv_max,pa,pb,pp_min,pp_max,regen}, stats_max{…}, milestones[{level,bonus,unlocked}], owned } ] }` (`owned` = `true` partout tant que le déblocage boutique n'est pas câblé). Enregistré dans `api/__init__.py`.
- **Frontend — réseau.** `NetworkManager.fetch_heroes()` + signal **`heroes_loaded(heroes: Array)`** (mêmes en-tête `Authorization`/parse JSON/`int()` que `fetch_profile_stats`/`fetch_leaderboard`, via `_send_api_request` + URL de l'autoload `ApiConfig`).
- **Frontend — écran (`scenes/ui/characters_screen.tscn` + `scripts/ui/characters_screen.gd`).** VUE pure (Règle d'Or §6.1), nœuds câblés par **`@export` + NodePath** (aucun `$chemin`). **GAUCHE** : liste des 10 héros (carte par faction = pastille couleur faction + nom + niveau ; cadenas si `owned=false`), sélection au clic (surbrillance liseré cyan). **DROITE** : panneau détail — **emplacement 3D réutilisant `scenes/components/hero_viewport_3d.tscn`** (repli portrait 2D `hero_path` puis carte colorée, logique reprise de `main_menu.gd:_apply_hero`) ; **niveau + barre d'XP** (remplie à `xp_in_level/xp_for_level`) + « XP avant niveau suivant » (ou « NIVEAU MAX ») ; **stats** au niveau courant (PV, PA, PB en %, PP `[min..max]`, Régén en %) avec **colonne « NIV. MAX » (= niveau 50)** en référence ; **pouvoir de héros** ; **paliers** (franchis ✓ vs à venir, bonus formaté ex. « +50 PV, +1 PA »). **Bouton RETOUR** (CTA ghost) → `main_menu`. Résolution `faction_id → couleur/portrait/modèle` via `resources/factions/*.tres` (l'`id` du `.tres` = clé backend snake_case).
- **Frontend — navbar.** Onglet `PERSONNAGES` ajouté à `main_menu.tscn`/`main_menu.gd` (entre `QG` et `BOUTIQUE` : nœud `CharactersTab`, `@export var characters_tab`, `_style_tab`/`pressed.connect`/`wire_buttons_sfx`, `_on_characters_pressed`) **et** à `top_nav.gd` (`TABS`, navbar réutilisable des écrans secondaires). Clés i18n **`MENU_TAB_CHARACTERS`** + **`CHAR_*`** ajoutées à `translations/ui_strings.csv` (FR/EN/IT ; `.translation` régénérées).
- **Fichiers.** NEUFS : `backend/api/v1/endpoints/heroes.py`, `backend/api/game/hero_roster.py`, `backend/test_heroes_roster.py`, `frontend/scenes/ui/characters_screen.tscn`, `frontend/scripts/ui/characters_screen.gd`. MODIFIÉS : `backend/api/__init__.py` ; `frontend/scripts/managers/network_manager.gd`, `frontend/scripts/ui/main_menu.gd`, `frontend/scenes/ui/main_menu.tscn`, `frontend/scripts/ui/top_nav.gd`, `frontend/translations/ui_strings.csv`.
- **Validation.** Backend : `PYTHONUTF8=1 py test_heroes_roster.py` = **239 ✅ / 0 ❌** (forme, défaut niveau 1, bornes, cohérence XP, paliers `unlocked`). Frontend (Godot 4.7-stable headless) : `--import` propre (0 Parse/SCRIPT ERROR) puis **boot de `characters_screen.tscn` ET `main_menu.tscn` `--quit-after` = 0 ERROR** (exit 0). ⚠️ Rendu visuel en jeu réel non capturé (headless) ; structure + logique validées. ⚠️ Endpoint nécessitera un **redéploiement VPS** pour être actif en prod (sinon 404 → l'écran affiche un roster vide sans planter).

### 8.58. Menu — accès au profil refondu : onglet « JOUEUR » retiré + jauge XP/Coins cliquable → mini-profil flottant — ✅ FRONTEND FAIT
> Demande CTO (UX) : **moderniser l'accès au profil**. L'onglet de nav « JOUEUR » est **supprimé** ; à la place, la **jauge XP/Coins** (cadre identité, haut-droite) devient **cliquable** et ouvre un **mini-profil flottant** (résumé express + CTA « VOIR LE PROFIL COMPLET » → `profile.tscn`). **Frontend exclusif** (actif au relancement du client) ; **AUCUN COMMIT** (working tree laissée à l'utilisateur).
- **Nav allégée (`main_menu.tscn` / `main_menu.gd`).** Nœud `ProfileTab` **retiré** du `NavTabs` (+ `node_path` et `@export var profile_tab` supprimés, retrait des `_style_tab`/`pressed.connect`/`wire_buttons_sfx` associés). Onglets restants : `QG / BOUTIQUE / CLASSEMENT`. `_on_profile_pressed()` est **CONSERVÉ** — il est désormais déclenché par le CTA du mini-profil.
- **Jauge cliquable (`scripts/ui/xp_coins_bar.gd`).** Nouveau **signal `profile_widget_clicked`** + **`set_interactive(enabled)`** (opt-in). Actif : un **Button transparent plein-cadre** superposé (même pattern « bouton superposé » que les cartes de mode), curseur en **main**, **survol qui éclaircit le liseré cyan** (variante de stylebox + légère lueur). NON activé par défaut → en HUD / Rapport Post-Op la jauge reste une **Vue passive** (aucune régression). Composant toujours **100 % par code**.
- **Mini-profil flottant (`main_menu.gd`, construit À LA DEMANDE comme le pop-up « Quitter »).** Un calque plein-cadre `ProfileFlyout` posé **au-dessus du HUD** = **capteur transparent** (tout clic extérieur referme — `gui_input`) + **panneau « intel »** (gunmetal α0.98 + liseré cyan + encoches `WarzoneUI` + ombre portée) **ancré sous la jauge**, bord droit aligné, **borné à l'écran**. Contenu (rythme *eyebrow → valeur* §2, **données DÉJÀ chargées — zéro appel réseau**) : eyebrow `JOUEUR` + pseudo, filet, `NIVEAU` (`LV n`, cyan), `CRÉDITS` (or), **dernière faction jouée** (de `GET /profile/history`, à la couleur d'accent de la faction) si connue, filet, **CTA ghost `❯ VOIR LE PROFIL COMPLET`** → `TransitionManager` vers `profile.tscn`. Fermeture : **clic extérieur**, **ÉCHAP** (`_unhandled_input`/`ui_cancel`), ou **re-clic** sur la jauge (toggle). SFX d'interface (survol/clic) câblés.
- **Règle d'Or §6.1 respectée.** `xp_coins_bar` ne fait qu'**émettre** un signal (il ne navigue jamais) ; `main_menu` (Vue) délègue la navigation au `TransitionManager`. Aucune logique de jeu brute.
- **i18n (R4).** **Une seule** nouvelle clé `MENU_PROFILE_VIEW_FULL` (« ❯ VOIR LE PROFIL COMPLET » / « ❯ VIEW FULL PROFILE » / « ❯ VEDI PROFILO COMPLETO », `ui_strings.csv` + `.translation` recompilées). Le reste **réutilise des clés existantes** (`COMMON_PLAYER`, `COMMON_LEVEL`, `SHOP_CREDITS`, `PROFILE_FAVORITE_FACTION`, `COMMON_PLAYER`). Libellés à clé brute = auto-traduits.
- **Fichiers (`frontend/`).** MODIFIÉS : `scenes/ui/main_menu.tscn` (`ProfileTab` retiré), `scripts/ui/main_menu.gd` (mini-profil + jauge cliquable + nettoyage onglet), `scripts/ui/xp_coins_bar.gd` (signal + `set_interactive`), `translations/ui_strings.csv` (+ `.translation` régénérées). ⚠️ **`top_nav.gd` (barre des écrans secondaires) NON touché** — il conserve son onglet `profile` (choix de périmètre : la directive cible le **menu principal** ; à harmoniser ultérieurement si voulu). **Backend INCHANGÉ.**
- **Validation (Godot 4.7-stable headless).** `--import` **0 erreur** (scripts compilés, scène validée, traductions recompilées) ; boot `main_menu.tscn --quit-after 40` = **0 ligne `ERROR`**. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.57. Lobby — effectif HÉRITÉ du mode (SpinBox retiré) + Radar filtré par capacité — ✅ FRONTEND FAIT
> Demande CTO : la **sélection du mode au Menu Principal doit DICTER le lobby**. Le joueur ne doit plus **rechoisir** l'effectif dans le lobby, et le **Radar des Opérations** ne doit afficher **que** les salles correspondant au mode. **Frontend exclusif** (actif au relancement du client). **Aucun commit** (working tree laissée à l'utilisateur).
- **Transmission menu → lobby DÉJÀ en place (§8.54)** : `main_menu.gd._on_play_pressed()` pose `MatchConfig.set_mode(id, count, ranked)` au clic `START` (chaîne cartes de mode → `_select_mode` → `MatchConfig`). **Aucune modification de `main_menu.tscn`/`.gd` n'était requise** pour ce sprint — seul le lobby devait cesser de redemander l'effectif.
- **`SpinBox` « EFFECTIF (3-6) » SUPPRIMÉ** (`lobby_screen.tscn`) : nœud `PlayerCountSpin` retiré du `ConfigRow` (+ `node_path` et `@export var max_players_spin` retirés). À sa place, un **indicateur LECTURE SEULE** `HeadcountValue` (label cyan condensé, rythme *eyebrow → valeur* §2) qui **reflète** l'effectif/mode hérité.
- **Effectif unique `_required_players` (`lobby_screen.gd`)** : lu de `MatchConfig.selected_player_count` au `_ready()` via `clampi(..., 3, 6)` (une absence de sélection — ex. boot direct du lobby en debug — retombe sur **3**). Pilote **À LA FOIS** (a) la **création** de salle (`_on_create_public_pressed`/`_on_create_private_pressed` envoient `_required_players` à `create_room(...)`, plus aucune saisie manuelle) **et** (b) le **filtrage du Radar**.
- **Radar filtré par capacité** : `_on_rooms_loaded` masque toute salle dont `int(max_players) != _required_players` (en plus du masquage déjà existant des salles privées). Piège JSON float §5 respecté (`int()` avant comparaison). `_refresh_headcount_display()` met l'indicateur à jour.
- **Affichage i18n SANS nouvelle clé** : on réutilise la clé **existante** du menu `MENU_MODE_PLAYERS` (« %d JOUEURS »). Seule retouche i18n : `LOBBY_HEADCOUNT` passe de « EFFECTIF (3-6) » à « **EFFECTIF** » (FR/EN/IT, `ui_strings.csv` + `.translation` recompilées) — la mention « (3-6) » n'a plus de sens (readout, plus un sélecteur).
- **Filtrage CÔTÉ CLIENT (choix assumé)** : `GET /lobby/rooms` n'expose **aucun** paramètre de capacité (`CONTRAT_RESEAU.md` §5 / schéma §A) et la règle « **interdiction de deviner** » du contrat proscrit d'inventer une query string spéculative. On filtre donc la réponse localement. *(Piste backend optionnelle notée dans `CONTRAT_RESEAU.md` §5 : un `GET /lobby/rooms?max_players=N` réduirait le trafic — différé, Backend-first + redéploiement VPS requis.)*
- **⚠️ Mode « Classée » HORS PÉRIMÈTRE (décision CTO)** : le classé est une **modalité à part**, traitée **plus tard** dans son propre flux. Le lobby n'hérite ici **que de l'effectif** (un éventuel choix classé retombe sur son effectif, ex. 5) — **aucune logique ni affichage classé** n'est ajouté côté lobby pour l'instant (`MatchConfig.selected_ranked` reste disponible pour le futur flux dédié).
- **Fichiers (`frontend/`).** MODIFIÉS : `scenes/ui/lobby_screen.tscn` (`ConfigRow` : `PlayerCountSpin` → `HeadcountValue`), `scripts/ui/lobby_screen.gd` (`_required_players`/`_match_ranked`, `_refresh_headcount_display`, création + filtre), `translations/ui_strings.csv` (+ `.translation` régénérées). **`main_menu.tscn`/`.gd` INCHANGÉS. Backend INCHANGÉ.**
- **Validation (Godot 4.7-stable headless).** `--import` **0 erreur** (scripts compilés, scènes validées, traductions recompilées) ; boot runtime `lobby_screen.tscn --quit-after 40` = **0 ligne ERROR** (autoloads instanciés, `HeadcountValue` câblé, ex-`max_players_spin` proprement retiré).

### 8.56. Nav — choix de la langue retiré de la barre (centralisé dans Paramètres) + cluster identité/⚙ décalé à droite — ✅ FRONTEND FAIT
> Demande utilisateur : le **sélecteur de langue** ne doit plus apparaître dans la **barre de navigation** (menu principal + écrans secondaires) ; il reste **uniquement dans l'écran Paramètres** (⚙). En contrepartie, le **cadre identité (pseudo + jauge XP/niveau)** et le bouton **⚙ Paramètres** glissent d'autant vers la **droite**. **Frontend exclusif.** **Aucun commit** (working tree laissée à l'utilisateur).
> - **`main_menu.tscn` / `main_menu.gd`** : nœud `LanguageSlot` **supprimé** du `UtilityCluster` (+ retrait du `node_path`/`@export var language_slot` et de `_mount_language_selector()`). Le cluster aligné à droite se referme → `IdentityFrame` + `⚙` se décalent vers la marge droite. On **reste abonné** à `LocaleManager.locale_changed` (re-traduction des textes formatés au retour des réglages).
> - **`top_nav.gd`** (barre mutualisée boutique/profil/classement) : appel à `WarzoneUI.build_language_selector()` **retiré** du cluster de droite → même décalage `IdentITY ▸ ⚙ ▸ ⏻`.
> - **Conservé tel quel** : le sélecteur de langue de l'**écran de connexion** (`auth_screen.gd`, pré-login — les Paramètres n'y sont pas accessibles) et celui de l'**écran Paramètres** (`settings.gd`). `WarzoneUI.build_language_selector()` inchangé.
> - **Validation (Godot 4.7-stable)** : `--import` **0 erreur** ; boot `main_menu.tscn` **et** `shop.tscn` `--quit-after 40` = **0 erreur** ; **capture framebuffer réelle** (MCP godot-ai) → top-bar = `JOUEUR ▸ ⚙ ▸ ⏻`, plus aucun `🌐 FR/EN/IT`.

### 8.55. Menu — top-bar recentrée + cadre identité à droite, nav UNIFIÉE partout, sections placeholder débranchées + fix patch corrompu — ✅ FRONTEND FAIT
> Suite §8.54 : alignement fidèle sur la réf. CoD Warzone (onglets **centrés**, profil **encadré à droite**) + **cohérence** de la barre de nav entre le menu et les écrans secondaires (boutique, réglages). **Frontend exclusif.** **Aucun commit** (working tree laissée à l'utilisateur).
- **Top-bar de `main_menu.tscn` recomposée en 3 zones** : marque (logo + `WASTELAND WARFARE`) à **gauche** · **onglets centrés** `QG/BOUTIQUE/JOUEUR/CLASSEMENT` dans une **pastille opaque** `NavPanel` (gunmetal α0.95 + filet cyan, sub-resource `nav_bar_panel`) · **cluster droite** = **cadre identité** `IdentityFrame` (`PanelContainer` bordé cyan, sub-resource `card_panel` : eyebrow `JOUEUR` + pseudo + jauge XP/Coins) + **⚙ Paramètres** + **sélecteur de langue** + **⏻ Quitter**. (Avant : tout aligné à gauche, identité dans la marque.) NodePaths `welcome_label`/`xp_coins_slot` repointés sous `IdentityFrame`.
- **Cartes de mode centrées** : `CardsRow` `alignment=center` + cartes en `SIZE_SHRINK_CENTER` (largeur fixe) au lieu de `EXPAND_FILL` → ruban de modes **groupé au centre** du bas, `START` à gauche (réf. « SELECT TEAM SIZE »).
- **Barre de nav partagée `top_nav.gd` UNIFIÉE** (réécrite) : **traitement identique** à la top-bar du menu (barre **transparente**, **pastille opaque** d'onglets centrés, **cadre identité** à droite, ⚙/langue/⏻, **filet cyan** sous la barre). **Onglets alignés** sur le menu : `lobby/shop/profile/leaderboard` (clés `MENU_TAB_*`, navigation via `TransitionManager`). `shop.gd` : `active_tab` `"store"`→`"shop"`. → tous les écrans hôtes (boutique, réglages…) affichent désormais **la même barre** que le menu. Les hôtes centrent leur contenu (`CenterContainer`) → aucun chevauchement.
- **Sections placeholder DÉBRANCHÉES** (non abouties) : `weapons` / `battle_pass` / `events` / `missions` / `skins` **retirées du tableau `TABS` de `top_nav.gd`** → **inaccessibles** via la nav. **Scènes/scripts CONSERVÉS sur disque** (réactivation = remettre l'entrée). Réglages s'atteint via ⚙ ; Skins n'a plus d'onglet.
- **🩹 FIX BLOQUANT (cause racine de « F5 reste bloqué » ET « le login ne marche pas »).** Le patch local `user://latest_patch.pck` (monté par `bootloader.gd` avec `replace=true`, qui **écrase les `res://`**) contenait un **`main_menu.tscn` CORROMPU** (`Parse Error :33` + `err 19`) → après auth, `change_scene_to_file("main_menu")` **échouait** → blocage sur l'écran d'auth (l'auth elle-même réussissait). Les **sources étaient saines** (boot direct = 0 erreur) ; seul le `.pck` packagé (issu d'un mauvais commit) était cassé. Côté dev : **patch local retiré** (→ F5 relance les **sources**). Patch **régénéré propre** : `Godot…_console.exe --headless --path . --export-pack "wasteland_warfare_setup" patch_v1.1.5.pck` (≈23 Mo) → **vérifié** (remonté via bootloader, le menu charge sans erreur). ⚠️ **À uploader sur le VPS** ; pour forcer la MAJ de **tous** les clients, **bumper la version serveur** (un client déjà en 1.1.5 ne re-télécharge pas).
- **Fichiers (`frontend/`).** MODIFIÉS : `scenes/ui/main_menu.tscn` (top-bar 3 zones + sub-resource `nav_bar_panel`), `scripts/ui/main_menu.gd` (cartes `SHRINK_CENTER`), `scripts/ui/top_nav.gd` (**réécriture** : barre transparente + pastille + cadre identité + `TABS` réduits), `scripts/ui/shop.gd` (`active_tab`). `scripts/managers/auth_manager.gd` : renommage paramètre `username`→`p_username` (bénin). **Backend inchangé.**
- **Validation (Godot 4.7-stable, live via MCP godot-ai).** `--import` **0 erreur** ; **F5 (`mode=main`) → bootloader → splash → auth → auto-login → menu = 0 erreur** ; navigation **menu ↔ boutique** vérifiée (onglet actif souligné, aller-retour QG↔Boutique) ; cadre identité peuplé (pseudo/LV/XP/coins). Patch régénéré monté & validé.

### 8.54. Menu Principal — refonte « tableau de bord asymétrique » (lobby Warzone) — ✅ FRONTEND FAIT
> Décision CTO : faire évoluer `main_menu` d'une **liste verticale de boutons** vers un **lobby AAA** calqué sur *Call of Duty: Warzone* (réf. fournie). Mise en page **asymétrique plein-cadre**, charte « Warzone Command » §2. **Frontend exclusif** (actif au relancement du client) — sauf le mode classé (dépendance backend, ci-dessous).
- **Mise en page (`main_menu.tscn`)** : `Background` → `HeroLayer` (héros centré, **derrière** l'UI) → `Hud` (`MarginContainer`) → `Shell` (`VBoxContainer`) à 3 bandes — **TopBar** (shrink) / **MidRow** (expand) / **BottomRow** (shrink). 17 nœuds câblés via `@export` + `node_paths` (drag-drop éditeur, convention CLAUDE.md).
  - **Top Bar** (`HBoxContainer`) : marque (logo réduit + eyebrow `JOUEUR` → pseudo) · **onglets** `QG / BOUTIQUE / JOUEUR / CLASSEMENT` (style **souligné cyan**, QG actif) · `TopSpacer` · cluster utilitaire (**jauge XP·Coins** montée par code dans `XpCoinsSlot`, **⚙ Paramètres**, **sélecteur de langue** R4 dans `LanguageSlot`, **⏻ bouton système** rouge). **⚠️ Recomposée en §8.55** : onglets désormais **centrés** (pastille opaque `NavPanel`), identité déplacée dans un **cadre `IdentityFrame` à droite**, cartes de mode **centrées** en bas.
  - **MidRow** : **colonne gauche** (`LeftColumn`, 340 px) = carte mini-classement **TOP JOUEURS** (top 3) + carte **DÉFIS** (placeholder) ; **centre** `CenterSpacer` vide laissant transparaître le héros.
  - **BottomRow** : **CTA `START`** (gros bouton cyan + lueur au survol) à gauche + **cartes de mode** à droite (`CardsRow`).
- **Cartes de mode** (construites par code, `_make_mode_card`) : `TRIO`(3) / `QUAD`(4) / `FIVE`(5) / `HEXA`(6 — libellé renommé §8.103, la clé i18n `MENU_MODE_EXA` et l'id interne `exa` sont INCHANGÉS) casual + **`CLASSÉE`(5, classé)** distinguée en **or** `#E0B249`. **Sélection unique** (surbrillance cyan/or, défaut `TRIO`) ; `START` lance le mode retenu. Encoches d'angle (`WarzoneUI.add_corner_notches`), bouton transparent superposé pour la capture du clic.
- **Héros central = dernière faction jouée** : `NetworkManager.fetch_profile_history(1)` → `entries[0].faction_id` → résolution `.tres` (scan `DirAccess` + `FALLBACK_PATHS` + duck-typing, comme `faction_selection`/`profile`) → `hero_path` dans un `TextureRect` (`KEEP_ASPECT_CENTERED`) + placeholder `ColorRect` teinté `accent_color`. **Repli** faction par défaut (1re triée) si historique vide → centre jamais vide. ⚠️ `FactionData` n'a qu'**un** héros par faction (pas de roster) → « dernier personnage » = **héros de la dernière faction**.
- **Mini-classement** : `NetworkManager.fetch_leaderboard(3)` + signal `leaderboard_loaded` — **réutilise l'endpoint public §9.2 sans aucun changement backend** ; lecture défensive (`username`/`wins` + alias `niveau`/`stats_victoires`), garde `is_inside_tree()` (signal global partagé avec l'écran Classement). Bouton `❯ VOIR TOUT` → `leaderboard.tscn`.
- **Carte Défis** : placeholder **inerte** (titre + sous-titre + barres « verrouillées » + badge `PROCHAINEMENT`) — les défis (gains XP / montée de niveau) restent **à configurer** côté serveur.
- **« Quitter » amélioré** : `⏻` discret → **pop-up de confirmation à la charte** (gunmetal + liseré **rouge danger** + encoches), boutons `ANNULER` (ghost) / `❯ QUITTER`.
- **Porteur de mode `MatchConfig` (NOUVEL autoload)** : `scripts/managers/match_config.gd` (enregistré dans `project.godot`). Le menu y pose `set_mode(id, count, ranked)` au clic `START` ; `lobby_screen.gd` le **lit** pour pré-régler le `PlayerCountSpin` (effectif 3-6, natif via `max_players`). ⚠️ **MAJ §8.57** : le `PlayerCountSpin` est désormais **retiré** — l'effectif hérité est en **lecture seule** (`HeadcountValue`), impose la capacité à la création **et filtre le Radar**. **⚠️ DÉPENDANCE BACKEND** : le mode **« Classée »** (`is_ranked` + contrainte **exactement 5** + ladder) **n'est pas encore appliqué côté serveur** (`GameRoom`/`engine.py` acceptent tout 3-6) — l'intention `selected_ranked` est transportée mais **inerte** tant que le backend ne gère pas le gate.
- **i18n (R4)** : nouvelles clés `MENU_TAB_*`, `MENU_MODE_*`, `MENU_SELECT_MODE`, `MENU_CHALLENGES_*`, `MENU_TOP_PLAYERS`, `MENU_VIEW_ALL`, `MENU_WIDGET_*`, `MENU_WINS_ABBR`, `MENU_QUIT_*` en **FR/EN/IT** (`ui_strings.csv`). Libellés à **clé brute** = auto-traduits ; textes **formatés** (`%d JOUEURS`, victoires `%d V`, statut) ré-appliqués sur `locale_changed`.
- **Logique réseau/navigation INCHANGÉE** : `TransitionManager` (fondu), `AuthManager` (pseudo/niveau/XP/coins → jauge `xp_coins_bar`), `AudioManager` (ambiance + SFX). Écran = **Vue pure** (Règle d'Or §6.1) ; **aucun commit**.
- **Validation** : `--import` **0 erreur** + boot `main_menu.tscn` **0 ligne ERROR** ; capture viewport (windowed) → mise en page conforme à la référence, **top 3 réel chargé** depuis la prod (endpoint public), profil en erreur **attendue** (boot direct hors login). Revue charte : verdict **ship** (`corner_radius 0`, couleurs canoniques, encoches/chevrons), 2 nits corrigés (police des icônes ⚙/⏻ + alpha gunmetal 0.9).
> **Entrées présentes dans CE fichier :** §8.5 (arène frontend), §8.11 (crash contamination_zone), §8.13/§8.14 (Draft carrousel + correctifs), §8.15→§8.18 (carte monde, SubViewport, HUD, board_bg), §8.19 (Split-Screen VS), §8.21 (board.tscn), §8.22 (cartes UI + visibilité tactique), §8.23 (UX confort + conquête), §8.25 (3 bugs playtest), §8.29 (HUD RTS moderne), §8.30 (VFX shaders), §8.32 (Phase 0 aveugle côté client + hologramme), §8.36 (HUD charte glassmorphism §2 + Tiroir Intel), §8.37 (Architecture UI Finale — bascule « Warzone Command » + 4 modules), §8.38 (polish ADN menus + recolor fond + helper partagé), §8.39 (Boutique & Inventaire R1), §8.40 (Profil utilisateur R2), §8.41 (Classement mondial R3), §8.44 (nouvelle ouverture Splash + fondations R6 + purge legacy), §8.45 (propagation transitions + SFX/ambiance à tous les écrans), §8.46 (portraits de héros procéduraux), §8.55 (top-bar recentrée + nav unifiée `top_nav` + sections débranchées + fix patch corrompu).

### 8.5. Arène frontend — responsabilités (Règle d'Or §6.1)
- `board.gd` : RELIE les nœuds-territoires posés à la main (export `territories_container: Node2D`) aux données `MapData` par le NOM du nœud (= id string du territoire), puis assure la **Visibilité Tactique** (§8.22) : **remplissage `Polygon2D` semi-transparent** de chaque territoire à la **couleur de faction du propriétaire** (`accent_color` chargée depuis `resources/factions/*.tres`, repli sur la PALETTE par index, **gris si neutre**) + **badge de troupes** (`territory_badge`) au centre via `get_territory_position(tid)` ; ☢ + vert = zone, surbrillance = sélection. Câble le clic → `territory_clicked(id: String)` (`_wire_click` : Area2D signal `input_event` filtré clic gauche — cas nominal — ou BaseButton `pressed`, fallback). Aucune logique de jeu.
- `hud.gd` : barre (étape/phase/joueur/stock), objectif secret du joueur local, sélecteur de quantité (`get_amount()`), instruction (`set_instruction`), journal (`add_log`), **main de cartes affichée en boutons « +N »** (signal `card_played(card_index: int)`), bouton "Fin de Phase" (signal `pass_pressed`). Contrôles créés par code (pas de surcharge `.tscn`). Le panneau de description de carte (`%CardDescription`) est **supprimé** (cartes devenues de simples valeurs).
- `main.gd` : LE CERVEAU. Reçoit clics plateau + signaux HUD, valide localement (UX), envoie les actions et gère l'overlay de victoire. Le clic d'une carte envoie directement `play_card {"card_index": …}` (plus de ciblage Bouclier). `game_state.gd` ne touche plus l'UI (refresh piloté par `main.gd` via `game_state_updated`).
- Simplifications MVP : l'attaque envoie le **max de dés** possibles (1-3). L'adjacence est désormais pré-validée côté client (UX) via `MapData.are_adjacent(source, cible)` dans `_do_attack_click`/`_do_move_click` ; le serveur reste l'autorité et re-valide. Au point exact de validation du combat dans `_do_attack_click`, un `TODO: Lancer la scène Split-Screen VS` marque l'accroche du futur système d'affrontement des héros de factions.

### 8.11. Correctif crash au lancement 3 joueurs (race condition `contamination_zone`)
> Symptôme : 2 joueurs affichaient l'arène, le 3ᵉ restait bloqué sur écran gris.
> Erreur : `Invalid access to property or key 'contamination_zone' on a base object of type 'Node (game_state.gd)'` (board.gd:35 → generate_board → main.gd `_refresh`/`_ready`).

1. **Cause racine :** `game_state.gd` ne **déclarait jamais** la propriété `contamination_zone` et `update_from_json()` ne la parsait pas, alors que `board.gd:_contaminated_territory()` fait `GameState.contamination_zone`. En GDScript, lire une propriété non déclarée sur un `Node` lève « Invalid access » → le client plante au 1ᵉʳ rendu du plateau si `_ready()` s'exécute avant que l'état soit peuplé/aligné (race au lancement).
   - *Fix :* déclaration `var contamination_zone: Dictionary = {}` (défaut → la propriété existe **toujours**, même avant synchro réseau) + parsing `state_data.get("contamination_zone", {})` dans `update_from_json()`. La garde existante (`typeof == TYPE_DICTIONARY and zone.has("position")`) retombe alors proprement sur `-1`. **Aucune modification de `main.gd` nécessaire.**
2. **Nettoyage syntaxe `SHADOWED_VARIABLE_BASE_CLASS` :**
   - `waiting_room.gd:_on_lobby_state` : paramètre `ready` (masquait `Node.ready`) renommé `ready_ids` (et non `is_ready`, déjà utilisé comme membre).
   - `board.gd:generate_board` : variable locale `owner` (masquait `Node.owner`) renommée `territory_owner`.

### 8.13. Draft de Faction — Carrousel de sélection (Frontend)
> Étape de sélection asymétrique intercalée entre la salle d'attente et l'arène (§3 étape 5, §4.3).

- **Données (data-driven §6.3) :** `frontend/resources/factions/faction_data.gd` (`class_name FactionData`) + 3 ressources `.tres` d'exemple. Le carrousel charge les `.tres` du dossier (scan `DirAccess` export-safe **+ repli sur des chemins explicites** `FALLBACK_PATHS` + **duck-typing** sans dépendre du type global, cf. §8.14 bug 2), triés par `id` (ordre identique sur chaque client). L'`id` de chaque ressource est aligné sur le registre backend `factions.py` (`phalanges_acier`, `pillards_poussiere`, `culte_isotope`) pour que `faction_choice` soit exploitable côté moteur.
- **Vue (`scenes/faction_selection/faction_selection.tscn` + `scripts/ui/faction_selection.gd`) :** `HBoxContainer` carrousel (boutons ◄/► Orange Fusion, `CenterSlot` en `clip_contents` contenant la `Card` glissée). Animation par `Tween` (fondu + glissement horizontal). Centre : nom (teinté `accent_color`), portrait `TextureRect` (ou `ColorRect` placeholder si pas d'image), modificateurs en `RichTextLabel` BBCode. Bas : « CONFIRMER LA FACTION ». Charte respectée : panneau Kaki `#2b331f`, boutons actifs Orange Fusion `#d35400`.
- **Robustesse :** impossible de confirmer sans sélection (la faction centrée est toujours la sélection ; bouton désactivé si aucune ressource). Après confirmation, navigation + bouton verrouillés. Garde anti-spam pendant le Tween.
- **Réseau (frontend) :** `NetworkManager.send_faction_choice(faction_id)` (action `faction_choice`) + signal `faction_locked(player_id, faction_id)` (route le message serveur `{"type":"faction_locked",...}`). Transition vers `main.tscn` quand `_locked.size() >= GameState.players.size()`. Auto-enregistrement optimiste du choix local (évite tout blocage en solo).
- **Backend (FAIT) :** `sockets/router.py` route l'action `faction_choice` (entre les actions de lobby et celles de jeu) vers `_handle_faction_choice` qui (1) valide l'`id` contre `FACTIONS`, (2) applique la faction au `PlayerState` dans l'état Redis (lu par le moteur pour les modificateurs de tour), (3) mémorise le verrouillage (`ConnectionManager.lock_faction` / `get_locked_factions`, `locked_factions: room_id -> {pid: faction_id}`, nettoyé à la destruction de salle) et (4) **rediffuse** `faction_locked` à toute la salle. **Simplification MVP :** pas d'unicité imposée (deux joueurs peuvent prendre la même faction) pour éviter un soft-lock du client (qui verrouille son UI dès la confirmation, avant la réponse serveur). Les factions choisies ne sont pas re-broadcastées dans l'état avant l'arène : le client garde brièvement les factions par défaut (cosmétique) jusqu'au 1ᵉʳ `action_result` qui rafraîchit l'état complet ; le **moteur reste autoritatif** (modificateurs lus depuis Redis). ⚠️ **Backend → nécessite push + redéploiement VPS** pour être actif (§1). *(Contrat réseau du draft : voir [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) §5.)*

### 8.14. Correctifs du Draft (3 bugs — Frontend exclusif)
> Bugs remontés après la 1ʳᵉ intégration du carrousel. Les 3 correctifs sont **frontend** (actifs au relancement du client Godot, sans redéploiement backend).

1. **Texte des factions tronqué (cadre trop petit).** *Cause :* le `CenterSlot` (`clip_contents`) était trop court pour le lore + la liste des modificateurs → texte coupé. *Fix (`faction_selection.tscn`) :* agrandissement du `PanelContainer` (1180×820) et du `CenterSlot` (840×680), `RichTextLabel` description en `autowrap_mode = 3` + `scroll_active` (filet de sécurité) + `normal_font_size = 20`.
2. **Carrousel vide pour certains joueurs (« factions vides »).** *Cause :* `_load_factions` dépendait du listage `DirAccess` **et** du type global `FactionData` ; or, avec plusieurs instances Godot partageant le même cache d'import (`.godot/`), ou en build exporté (un `.tres` peut être listé en `.tres.remap`), certains clients voyaient un dossier « vide » → carrousel sans factions. *Fix (`faction_selection.gd`) :* scan rendu **export-safe** (retrait du suffixe `.remap`), **repli** sur `FALLBACK_PATHS` (chemins explicites) si le scan ne renvoie rien, et **duck-typing** (`res.get("id") != null`) au lieu de `is FactionData` — le chargement ne dépend plus de l'enregistrement du nom de classe global. Tri par `id`.
3. **Numéro de joueur #2 systématiquement « oublié » (#1, #3, #4…).** *Investigation :* le libellé affiché était l'`User.id` **brut de la base**, à la fois en salle d'attente (`waiting_room.gd`) et dans le HUD (`hud.gd`). Les `id` auto-incrémentés (PostgreSQL `SERIAL`) présentent des **trous** (une inscription échouée / un compte supprimé consomme quand même un id), d'où des numéros non contigus sans jamais de #2. **Ce n'était donc pas un bug d'attribution mais d'affichage.** *Fix :* nouveau `GameState.player_number(pid)` → numéro **séquentiel 1..N** par rang croissant des `player_id` (même ordre que la palette `board.gd`, donc « Joueur N » et sa couleur restent cohérents). `waiting_room.gd` calcule l'index 1..N sur une copie triée localement (robuste même si le serveur ne garantit pas l'ordre) ; le HUD utilise `player_number`. L'**identité réseau reste l'`User.id`** (URL WS, clés d'état) — seul l'affichage change.

### 8.15. Carte monde (Risk classique) & Level Design MANUEL
> La carte passe d'une grille abstraite de boutons à une vraie **carte monde type Risk (42 territoires, 6 continents)**, dont le Level Design 2D est dessiné **à la main** dans l'éditeur Godot.

- **Source de vérité = le graphe, pas la scène.** `frontend/map_data.gd` (autoload `MapData`) et son miroir Python `backend/api/game/map_data.py` définissent `CONTINENTS` (bonus : Amérique du Nord 5, Amérique du Sud 2, Europe 5, Afrique 3, Asie 7, Océanie 2) et `TERRITORIES` (42 entrées : `name`, `continent`, `neighbors`). Graphe non orienté, symétrique, entièrement connexe — **auto-vérifié au chargement** (42 territoires, 83 frontières ; assertions Python + `assert` GDScript en build debug). **Les deux fichiers doivent rester identiques.**
- **IDs = noms de nœuds.** Chaque territoire a un id `snake_case` ASCII stable (ex. `alaska`, `north_africa`, `western_australia`) qui sert AUSSI de **nom de nœud** dans la scène.
- **Level Design manuel.** Les 42 territoires sont placés à la main dans l'éditeur 2D, dans un nœud conteneur. Le développeur **glisse ce conteneur** dans l'export `territories_container` de `board.gd`. Au `_ready`, `board.gd` parcourt les enfants, fait correspondre `node.name.to_lower()` à `MapData.TERRITORIES`, câble le clic (`pressed` → `territory_clicked(id)`) et applique la couleur (teinte du continent par défaut, couleur du propriétaire sinon, ☢ + vert pour la zone). Un nœud sans correspondance émet un `push_warning` et est ignoré. **`main.tscn`/`board.tscn` ne sont PAS édités par script** (montage manuel, pour éviter toute corruption) — seul `board.gd` change ; il `extends Node` (compatible avec n'importe quel type de nœud que le dev choisira pour le plateau).
- **✅ SCAFFOLD DÉJÀ EN PLACE dans `main.tscn`.** L'arbre des 42 territoires existe, désormais **encadré dans une fenêtre de jeu SubViewport** (voir §8.16) : `Main` → `MapFrame` → `MapViewportContainer` → `MapContent` (SubViewport) → `Board` (Node2D + `board.gd`, `territories_container = NodePath("TerritoriesContainer")` — chemin **relatif** inchangé) → `TerritoriesContainer` (Node2D) → **42 `Area2D`** nommés EXACTEMENT par l'id snake_case (= ids réseau), chacun avec un `CollisionPolygon2D` enfant portant un **triangle placeholder** `PackedVector2Array(0, 0, 8, 0, 0, 8)`. Tous empilés à l'origine (0,0) : le dev les **positionne et redessine** les polygones manuellement dans l'éditeur 2D. Correspondance 42/42 exacte avec `map_data.gd` vérifiée (aucun manquant/doublon/intrus) ; scène instanciée sans erreur en validation headless (l'attribut non-standard `unique_id=` issu de l'outillage MCP est ignoré par Godot, inoffensif).
- **✅ FOND DE CARTE INTÉGRÉ (`BoardBackground`).** Un nœud `TextureRect` nommé `BoardBackground` est le **1ᵉʳ enfant de `MapContent`** (index 0, depuis §8.16 — était auparavant 1ᵉʳ enfant de `Main`) → dessiné en premier, donc **au fond**, garanti derrière `Board/TerritoriesContainer` (index 1, rendu par-dessus). `texture = res://assets/images/board_bg.png` (⚠️ la racine `res://` = le dossier `frontend/` ; le chemin disque réel est `frontend/assets/images/board_bg.png`, taille **2200×1530** depuis le rognage §8.18). `position = (0,0)`. **`mouse_filter = 2` (`MOUSE_FILTER_IGNORE`)** → les clics traversent l'image et atteignent les `Area2D` (picking physique). Vérif de sécurité OK : ni `MapContent` (SubViewport), ni `Board`/`TerritoriesContainer` (Node2D) ne sont des `Control` bloquants → aucun `mouse_filter` à `STOP` n'intercepte les clics. (Les `Area2D` doivent rester `input_pickable=true` + avoir leur `CollisionPolygon2D` — vérifié par `board._warn_if_area_not_clickable` ; **et** `MapContent.physics_object_picking = true`, sinon aucun clic Area2D dans un SubViewport — voir §8.16.)
- **✅ MIGRATION BACKEND FAITE (ids string de bout en bout).** Frontend ET serveur partagent désormais les **ids string** :
  - `state_schemas.py` : `TerritoryState.territory_id: str`, `GameState.territories: Dict[str, TerritoryState]`, `contamination_zone: Dict[str, Any]` (la position est un id string, plus un entier).
  - `engine.py` : importe `map_data` (plus `map_constants`, **supprimé**). Distribution initiale sur `list(TERRITORIES.keys())`, position de zone via `_random_territory_id()`, contrôle de continent via `CONTINENT_TERRITORIES`, adjacence attaque/mouvement via `are_adjacent()`.
  - `objectives.py` : `TOTAL_TERRITORIES = 42`.
  - `test_simulation.py` : réécrit avec des ids Risk (`alaska` → `kamchatka`, `japan` en survie).
  - `GameState.territories` est donc indexé par `alaska`, `north_africa`… → les nœuds posés à la main se mappent directement sur l'état réel.
- **🐞 Bug annexe corrigé (renforts doublés).** `engine._advance_phase` recalculait les renforts (`if state.phase == 1: _calculate_reinforcements`) APRÈS que `_end_turn` les ait déjà crédités au joueur entrant → **chaque changement de tour donnait 2× les renforts**. Le bloc redondant a été retiré (les renforts sont calculés une seule fois, par `_end_turn` / `_start_playing`).
- **⚠️ À déployer.** Comme tout changement serveur (§8.7), il faut **push + CI/CD VPS** : le live tourne l'ancien code (grille 43 entiers) tant que le backend n'est pas redéployé. Validation locale faite : `py_compile` OK sur tous les fichiers modifiés + assertions `map_data.py` (42 territoires, 83 frontières, connexe). Le runtime complet (Redis/pydantic/fastapi absents en local) se teste sur le VPS.

### 8.16. Fenêtre de jeu encadrée (architecture SubViewport)
> Le `board_bg.png` (2200×1530 depuis §8.18) est trop grand pour la fenêtre. La carte + les territoires sont désormais **confinés dans un cadre UI** (`MapFrame`) à bord épais, via un **SubViewport** pour préserver le picking des `Area2D` malgré le redimensionnement. **Frontend exclusif** (actif au relancement du client Godot, aucun redéploiement backend).

- **Hiérarchie dans `main.tscn`** (les nœuds hors-cadre — `Button` debug, `HUD` CanvasLayer — restent enfants directs de `Main`) :
  - `Main` (Node)
	- `MapFrame` (`PanelContainer`) — **cadre centré** : ancres `center` (0.5 sur les 4 côtés), taille `1036×583` ≈ **90 %** du viewport de conception **1152×648** (et non 1920×1080 : c'est la vraie résolution de base du projet, cf. `display/window/size`). `theme_override_styles/panel` = `StyleBoxFlat` (fond `#1f2615`, **bordure `#d35400` « métal rouillé », `border_width` 30 px sur les 4 côtés**, `content_margin` 30 px, `corner_radius` 6).
	  - `MapViewportContainer` (`SubViewportContainer`) — ancres `full_rect` (le `PanelContainer` l'insère de toute façon dans la zone de contenu, soit après les 30 px de bordure). **`stretch = true`** → transmet et met l'input à l'échelle vers le SubViewport.
		- `MapContent` (`SubViewport`) — `size = 2200×1530` (espace de conception = taille du `board_bg`, rogné en §8.18), **`handle_input_locally = true`**, **`physics_object_picking = true`**.
		  - `BoardBackground` (`TextureRect`, index 0, au fond)
		  - `Board` (`Node2D` + `board.gd`, index 1) → `TerritoriesContainer` → 42 `Area2D`
- **⚠️ Picking Area2D dans un SubViewport.** Un `SubViewport` a `physics_object_picking = false` **par défaut** → les signaux `input_event` des `Area2D` ne se déclenchent JAMAIS à l'intérieur. La directive d'origine l'omettait ; **`physics_object_picking = true` est donc OBLIGATOIRE** (avec `handle_input_locally = true` et le `SubViewportContainer.stretch = true` qui relaie/échelonne l'input). C'est précisément ce qui « garantit que les Area2D fonctionnent ».
- **⚠️ `stretch` vs `size` du SubViewport.** Avec `SubViewportContainer.stretch = true`, Godot **redimensionne le SubViewport à la taille du conteneur** (≈ zone interne du cadre) à chaque frame → le `size = 2200×1530` posé sur `MapContent` est **écrasé au runtime** (il documente l'espace de conception, mais n'est pas la taille effective). Conséquence : le `board_bg` natif (2200×1530) n'est **pas** mis à l'échelle pour rentrer, il est **rogné** à la taille du viewport. **Le Level Design manuel des 42 territoires (§8.15) doit donc se faire dans l'espace effectif du SubViewport** (≈ taille interne du cadre). Pour cadrer tout le `board_bg` en le réduisant, ajouter ultérieurement un `Camera2D` dans `MapContent` (zoom ajusté) ou mettre `BoardBackground`/`Board` à l'échelle — non fait ici (territoires encore non positionnés).
- **Impact code.** `board.gd` **inchangé** (l'export `territories_container` est un `NodePath` *relatif* à `Board`, qui a été déplacé entier avec son `TerritoriesContainer`). Seul `main.gd` a changé : `@onready var board = $MapFrame/MapViewportContainer/MapContent/Board` (au lieu de `$Board`). `$Button` et `$HUD` inchangés.
- **Note HUD.** ~~Le `HUD` (CanvasLayer) se dessine en overlay plein écran~~ — **OBSOLÈTE depuis §8.17** : le HUD n'est plus un CanvasLayer overlay mais le conteneur racine de la mise en page (le `MapFrame` est désormais SON enfant). De même, la caméra anticipée au point précédent existe : `TacticalCamera` (§8.17).

### 8.17. HUD Militaire (3 blocs) & Caméra Tactique
> L'arène devient un **centre de commandement** : mise en page plein écran en conteneurs (TopBar / carte 90 % + colonne comms 10 % / inventaire ~70 % de hauteur pour le bloc central), **caméra tactique** dans le SubViewport (vue 100 % plateau + travelling de combat), et **système d'abandon**. **Frontend exclusif** à la livraison (l'action `abandon` est depuis implémentée côté serveur — voir §8.20).

> ⚠️ **MISE EN PAGE OBSOLÈTE depuis §8.29** : la disposition « 3 blocs en conteneurs pleins » (TopBar / MiddleBlock / BottomBar) est remplacée par un design **« RTS moderne »** (plateau **100 % écran** + **widgets flottants** en glassmorphism). Restent valides et inchangés : la **caméra tactique** (`tactical_camera.gd`), le **timer MM:SS**, l'**abandon en 2 clics**, les **canaux de chat** et le **journal militaire**. Lire §8.29 pour la hiérarchie réelle de `main.tscn` et l'API `hud.gd`.

- **Hiérarchie dans `main.tscn`** (l'ancien `hud.tscn`/CanvasLayer est **SUPPRIMÉ** ; la mise en page vit dans `main.tscn`, stylée par `StyleBoxFlat` + `Theme` embarqués — sombre `#121212`, kaki `#2b331f`, orange `#d35400`, police `SystemFont` Stencil→Urbanist→Arial gras) :
  - `Main` (Node, `main.gd`)
	- `HUD` (`VBoxContainer` racine plein écran, **`hud.gd` y est attaché** — il `extends VBoxContainer` désormais)
	  - `TopBar` (`PanelContainer`) → `TopVBox` → `TopRow` (`%PhaseLabel`, `%InfoLabel` tour/joueur/stock, `%TimerLabel` **MM:SS**, `%NextPhaseButton` « FIN DE PHASE ▶ », `%AbandonButton` rouge « ☠ ABANDONNER ») + `%InstructionLabel` (2ᵉ ligne).
	  - `MiddleBlock` (`HBoxContainer`, `stretch_ratio 7` ≈ 70 % de la hauteur)
		- `MapFrame` (`PanelContainer`, **`stretch_ratio 9` = 90 % de largeur**, bordure **30 px `#2b331f`**) → `MapViewportContainer` → `MapContent` (SubViewport, **`transparent_bg = true`** pour laisser le fond sombre du cadre derrière le plateau) → `BoardBackground` + **`TacticalCamera`** (Camera2D + `tactical_camera.gd`) + `Board` → `TerritoriesContainer` → 42 Area2D (intacts).
		- `SidePanel` (`VBoxContainer`, `stretch_ratio 1` = 10 %) : `%ChatTabs` (`TabContainer`, 3 onglets **GÉNÉRAL / ALLIÉS / PRIVÉ**, `RichTextLabel` défilants, `clip_tabs`) + `MilitaryLog` (`PanelContainer` → `%LogText` `RichTextLabel`, historique numéroté des conquêtes/évènements — remplace l'ancien journal 7 lignes).
	  - `BottomBar` (`HBoxContainer`, inventaire) : `CardsPanel` → `%CardsBox` (cartes affichées en **boutons « +N »** générés par code, valeur en gros ; clic = `card_played(card_index)` → `play_card`, §8.22) + `DescPanel` (`%ObjectiveLabel`, `%AmountSpin` quantité ; l'ancien `%CardDescription` a été **retiré**).
	- `Button` (debug init, déclaré APRÈS le HUD pour rester cliquable au-dessus).
- **`hud.gd` réécrit** (même API pour `main.gd` : `pass_pressed`, `card_selected`, `get_amount`, `set_instruction`, `add_log`, `update_display`). Nouveautés : signal **`abandon_pressed`** (armement **2 clics** : « ⚠ CONFIRMER ? » se désarme après 3 s), **timer MM:SS** (compte le temps du tour courant, remis à zéro au changement étape/tour/joueur dans `update_display`), `add_chat_message(channel, text)` avec `channel ∈ {general, allies, prive}` (BBCode accepté — **local pour l'instant**, TODO backend : action `chat`).
- **Caméra tactique (`tactical_camera.gd`).** Par défaut : centrée sur le plateau, **zoom calculé pour voir 100 % du `board_bg` (`BOARD_SIZE`, 2200×1530 depuis §8.18)** (recalculé sur `size_changed` du SubViewport — résout le rognage décrit en §8.16, qui est donc **obsolète sur ce point**). `focus_on_combat(pos_a, pos_b)` : Tween parallèle (0.8 s, `TRANS_SINE`/`EASE_OUT`) vers le **point médian** + zoom **1.5×** (relatif à la vue plein plateau). `reset_view()` : retour fluide. Câblage dans `main.gd` : sur l'évènement `attack_result`, focus sur attaquant/défenseur via `board.get_territory_position(tid)` (nouveau helper : centroïde du `CollisionPolygon2D`, `Vector2.INF` si inconnu), puis `reset_view()` après 2,5 s. **⚠️ Le Level Design manuel (§8.15) se fait donc désormais dans l'espace 2200×1530 du `board_bg`** (plus dans la « taille interne du cadre » de §8.16).
- **Abandon (Fallen Empire).** `%AbandonButton` → `hud.abandon_pressed` → `main._on_abandon_pressed()` → `NetworkManager.send_action("abandon", {})` (enveloppe standard `{"action": "abandon", "payload": {}}`). ~~TODO BACKEND~~ → **FAIT (§8.20)** : le serveur passe `is_active=false`, saute les tours du joueur et laisse ses troupes en défense automatique.
- **🐞 Correctif au passage.** Le header du nœud `Board` ne portait pas `node_paths=PackedStringArray("territories_container")` → l'export `Node2D` restait **null** au runtime (warning « territories_container non assigné », territoires jamais câblés au clic). Ajouté ; le boot headless est désormais sans warning.
- **Validation.** Compilation headless éditeur : 0 erreur. Boot runtime de `main.tscn` : 0 erreur / 0 warning. Vérif visuelle (screenshot du jeu lancé) : 3 blocs en place, carte 100 % visible dans son cadre, onglets chat et journal fonctionnels. ⚠️ Cosmétique : `board_bg.png` contenait des **marges blanches intégrées à l'image** (révélées par la vue plein plateau) — **rognées depuis, voir §8.18**.

### 8.18. Rognage du `board_bg.png` (marges blanches)
> Les marges blanches et le cadre noir **intégrés à l'image** `board_bg.png`, rendus visibles par la vue plein plateau de la `TacticalCamera` (§8.17), dégradaient le rendu du cadre kaki. L'asset est **rogné à la zone utile** (fond olive + carte monde). **Frontend exclusif** (un seul asset + 2 constantes).

- **Découverte au passage :** le PNG faisait en réalité **2588×1664** — et non 2752×1536 comme documenté en §8.15–§8.17 et posé dans la scène. Le `TextureRect` (2752×1536) **étirait donc légèrement la texture** (déformation ≈ +6 % en largeur / −8 % en hauteur), en plus d'afficher les marges.
- **Rognage (PIL/Pillow, analyse pixel) :** zone utile détectée aux frontières nettes du cadre noir intérieur → crop `(297, 69) → (2496, 1598)` inclus. Supprimés : marge blanche gauche ~237 px, marge blanche droite ~32 px, cadre noir ~59-69 px sur les 4 côtés. **Nouvelle taille native : 2200×1530.**
- **Constantes mises à jour** (l'espace de conception du Level Design §8.15 devient **2200×1530**) :
  - `tactical_camera.gd` : `BOARD_SIZE = Vector2(2200, 1530)`.
  - `main.tscn` : `BoardBackground.offset_right/bottom = 2200/1530` (désormais = taille native → **plus aucune déformation**), `MapContent.size = 2200×1530` (documentaire, écrasé au runtime par `stretch`), `TacticalCamera.position = (1100, 765)` (= `BOARD_SIZE/2`, recalculé de toute façon au `_ready`).
- **Aucun repositionnement de territoire** : les 42 `Area2D` sont encore des placeholders empilés à l'origine (§8.15) — le Level Design manuel n'a pas commencé.
- **Validation.** Réimport éditeur headless (`--import`) puis boot runtime de `main.tscn` : 0 erreur.

### 8.19. Résolution visuelle des combats — Split-Screen VS
> Mise en scène d'un duel : à chaque `attack_result` du serveur, une surcouche plein écran scinde l'affichage en deux (héros des factions attaquante/défenseuse), anime les dés façon **machine à sous**, puis verrouille sur les vraies valeurs et désigne les perdants. **Frontend exclusif** (aucune logique de jeu, aucun accès réseau — VUE pure, Règle d'Or §6.1). Actif au relancement du client Godot.

- **Fichiers :** `frontend/scenes/game/split_screen_vs.tscn` (Control Full Rect) + `frontend/scripts/game/split_screen_vs.gd`. Police épaisse `SystemFont` Stencil→Urbanist→Arial gras (charte §8.17). Toute la mise en page est en conteneurs ; les dés et leurs styles sont **générés par code** (`_spawn_dice`).
- **Hiérarchie de la scène :** `SplitScreenVS` (Control, `mouse_filter=STOP` → bloque les clics sur le plateau pendant l'animation) → `Dim` (ColorRect noir 80 %) + `Halves` (HBoxContainer Full Rect, séparation 0) → `LeftHalf`/`RightHalf` (Control `size_flags_horizontal=Expand|Fill`), chacun avec `*Background` (TextureRect gradient de faction) + un VBox (`*Role`, `*Name`, `*PortraitFrame`→`*Portrait`/`*Placeholder`, `*Dice` HBox) → et `VSLabel` (« VS » central, taille 110). Tous les nœuds pilotés portent `unique_name_in_owner` (accès `%Nom`).
- **API (appelée par `main.gd`) :** `signal animation_finished` + `start_combat_resolution(attacker_faction_id: String, defender_faction_id: String, attack_rolls: Array, defense_rolls: Array) -> void`. La fonction charge les `FactionData` (nom, `accent_color`, `hero_path`) via le **même pattern robuste que le carrousel** (`§8.13/§8.14` : scan export-safe + `FALLBACK_PATHS` + duck-typing `res.get("id")`), peuple les deux moitiés, instancie `attack_rolls.size()`/`defense_rolls.size()` dés, joue la chorégraphie, émet `animation_finished` et `queue_free()`. **Repli si la faction n'a pas de `.tres`** (7/10 au stade MVP) : libellé dérivé de l'id (`capitalize`) + accent de la charte → l'écran reste fonctionnel.
- **Chorégraphie (Tween dynamiques) :** (1) **Impact** — les deux moitiés glissent depuis l'extérieur vers le centre en 0,3 s (`TRANS_EXPO`/`EASE_OUT`), le « VS » claque (`TRANS_BACK`). (2) **Roulement** — coroutine `_spin_loop` : chaque dé non verrouillé affiche `randi_range(1,6)` toutes les 0,05 s pendant 1,5 s. (3) **Verrouillage** — arrêt **un par un** en alternant attaque/défense (délai 0,2 s), chaque dé « punche » sur sa valeur réelle. (4) **Résultat** — règles Risk : comparaison paire à paire des plus hauts dés (jets **déjà triés desc.** par `engine.py`), **égalité = avantage défenseur** ; le perdant de chaque duel est assombri + croix rouge `✗`. (5) **Sortie** — lecture 2 s puis fondu global 0,5 s. ⚠️ Les valeurs de dés du JSON sont des **floats** (piège Godot §5) → `int(...)` systématique.
- **Intégration `main.gd` :** l'ancien `TODO` de `_do_attack_click` est levé — le combat ne se déclenche **pas** à l'envoi mais à la **réception** (`_on_game_event` → `attack_result` → `_play_combat_resolution`), car les jets de dés n'existent que dans la réponse serveur. La scène est instanciée comme **dernier enfant de `Main`** (donc au-dessus du HUD), puis `await vs_screen.animation_finished`.
  - **Gel du plateau pendant l'animation.** `_on_state_updated` ne rafraîchit plus directement : il appelle `_deferred_refresh` (via `call_deferred`, car le serveur émet `game_state_updated` **puis** `game_event` dans le même message — voir `network_manager.gd`). Si `_play_combat_resolution` a posé `_combat_animating=true` entre-temps, le refresh est mis en attente (`_refresh_pending`) et **rejoué à la fin** du duel → les troupes/propriétaires ne changent à l'écran qu'une fois l'animation lue.
  - **Propriétaire pré-combat.** L'état reçu avec `attack_result` est **déjà post-combat** (en cas de conquête, l'`owner_id` du territoire défenseur a déjà basculé). `main.gd` lit donc un **snapshot `_displayed_owners`** (rempli à chaque `_refresh`) pour retrouver la faction du défenseur d'origine. `_faction_of_player(pid)` lit `GameState.players[str(int(pid))].faction` (clés JSON = strings, pid potentiellement float).
- **Robustesse (audit post-livraison).** (1) **Garde-fou anti-gel `MAX_LIFETIME` (12 s)** : armé au `_ready`, il émet `animation_finished` + `queue_free` si la chorégraphie n'a pas abouti — une coroutine GDScript qui plante avorte SANS exception rattrapable, et `main.gd` resterait sinon suspendu sur l'`await` (plateau figé définitivement). En flux nominal (~5,5 s) la scène est déjà libérée : Godot nettoie la connexion du timer vers l'objet détruit, le garde-fou ne s'exécute jamais. (2) **Coercitions défensives dans `_load_faction`** : un `.tres` duck-typé sans `accent_color` (null) ferait crasher l'assignation typée `Color`, un `hero_path` null ferait crasher `ResourceLoader.exists()` → repli sur l'accent par défaut / chaîne vide.
- **Validation.** Compilation éditeur headless : 0 erreur. Boot runtime de `split_screen_vs.tscn` et `main.tscn` : 0 erreur. **Test de bout en bout headless** (script `SceneTree` temporaire, supprimé après run) : chorégraphie complète exécutée avec jets floats façon JSON — signal émis par le chemin nominal, dés verrouillés sur les vraies valeurs, croix sur les bons perdants (6>5 → défense ; égalité 4=4 → attaque), dés gagnants/non appariés intacts, nom de faction chargé du `.tres` → **TEST_OK**. ⚠️ Piège harnais : en mode `--script`, `_initialize` tourne avant le démarrage de l'arbre (add_child sans `_ready` ni `get_tree()`) — différer le setup à la 1ʳᵉ `process_frame`. ⚠️ **Rendu visuel non encore vérifié en partie réelle** (nécessite un combat multi-joueurs déployé, §8.7) ; les portraits restent des placeholders colorés tant qu'aucun `hero_path` n'est fourni dans les `.tres`.

### 8.21. Level Design isolé dans `board.tscn` (réalité de l'arborescence)
> Le plateau n'est **plus monté en dur dans `main.tscn`** : le Level Design se fait désormais dans une **scène isolée `frontend/scenes/game/board.tscn`**, instanciée par l'arène. (Les passages de §8.15/§8.16/§8.17 décrivant `BoardBackground` comme enfant direct de `MapContent` sont **obsolètes sur ce point**.)

- **Contenu de `board.tscn` :** racine `Board` (`Node2D` + `board.gd`, `territories_container = NodePath("TerritoriesContainer")` relatif, header avec `node_paths` — §8.17) → `BoardBackground` (`TextureRect`, `board_bg.png` 2200×1530, `mouse_filter = IGNORE`) **puis** `TerritoriesContainer` (`Node2D`) → **42 `Area2D`** nommés par id snake_case, chacun avec son `CollisionPolygon2D`. Les polygones ne sont **plus des triangles placeholder** (§8.15) : ils sont **dessinés à la main** (position + scale + polygone réel par territoire) — le Level Design manuel est en cours dans cette scène.
- **Instanciation dans `main.tscn` :** `MapContent` (SubViewport) contient `TacticalCamera` + `Board` (`instance=ExtResource` → `board.tscn`). L'ordre de rendu interne à `board.tscn` (fond d'abord, territoires ensuite) reste garanti ; le picking physique (`physics_object_picking`, §8.16) et le chemin `@onready` de `main.gd` (`.../MapContent/Board`) sont inchangés.

### 8.22. Refonte des cartes (troupes brutes) & Visibilité Tactique du plateau
> Double mission. **(1)** Le Game Design est recadré pour **sacraliser les factions** : les cartes « spéciales » (Bouclier, Aéroporté) sont supprimées, une carte ne donne plus qu'un **nombre brut de troupes (1 à 12)**. **(2)** La carte du monde était illisible → chaque territoire affiche désormais son **nombre de troupes** et la **couleur de son propriétaire**. **Backend (cartes) → push + redéploiement VPS requis ; Frontend → actif au relancement du client.**

**Partie 1 — Économie des cartes.**
- **Backend `engine.py` / `state_schemas.py` :** `PlayerState.cards_in_hand` passe en **`List[int]`**. `_draw_card_for_current_player` (phase 5) **annule** la pioche si la main a déjà **5 cartes** ; sinon tire une valeur via `CARD_VALUE_BANDS` (tranche pondérée 50/30/15/4/1 % puis valeur équiréparti dans la tranche → distribution exacte vérifiée sur 200 k tirages). `_handle_play_card` reçoit `card_index`, **retire** la carte et **ajoute sa valeur** à `units_in_stock` (stock à déployer). Les 3 anciens handlers de cartes + le routage `card_handlers` + `target_territory_id` + le plafond 2 cartes/tour sont **supprimés** (import `Any` retiré). `test_simulation.py` mis à jour (cartes `[3, 7]`, jeu par index). *(Voir aussi §8.4 dans [`ARCHITECTURE_ET_REGLES.md`](ARCHITECTURE_ET_REGLES.md).)*
- **Frontend HUD (`hud.gd` / `main.tscn` / `main.gd`) :** la main s'affiche en **boutons stylisés « +N »** (valeur en gros, `StyleBoxFlat` militaire, survol Orange Fusion). Le clic émet **`card_played(card_index: int)`** → `main.gd` envoie `{"action":"play_card","payload":{"card_index": index}}` (plus aucun ciblage). Le `%CardDescription` (panneau de description) est **retiré** de `BottomBar/DescPanel` ; `%ObjectiveLabel` et `%AmountSpin` conservés. Catalogue `CARD_INFO` et `_make_card`/`_handle_card_target`/`_pending_card` supprimés.

**Partie 2 — Visibilité Tactique du plateau.**
- **Nouvelle scène `territory_badge.tscn` (+ `territory_badge.gd`, `scenes/game/`) :** `Node2D` dessinant (`_draw`) un **disque anthracite** (`BG_COLOR`, ⌀ 60) cerclé d'un **anneau à la couleur de faction** (`draw_arc`, `BORDER_WIDTH` 5) + un `Label` **Stencil** (SystemFont gras, outline noir) centré. API : `set_data(troops: int, accent: Color)`.
- **`board.gd` :** `_load_faction_accents()` (au `_ready`) charge `faction_id → accent_color` depuis `resources/factions/*.tres` (scan robuste, duck-typing, export-safe — même pattern que `faction_selection.gd`). `_build_owner_colors()` mappe `owner_id → accent` (faction si .tres, sinon **PALETTE** par index). `generate_board()` boucle chaque territoire : **remplissage `Polygon2D` semi-transparent** (`FILL_ALPHA` 0.42, points repris du `CollisionPolygon2D` via `cpoly.transform * p`, enfant de l'Area2D → rendu par-dessus le fond mais sans intercepter le picking) coloré à l'accent du propriétaire (**gris `NEUTRAL_COLOR` si neutre**, teinte verte si zone, éclairci si sélectionné) + **badge** instancié/maj et positionné par `get_territory_position(tid)` dans un `BadgeLayer` (Node2D) rendu au-dessus des territoires. Caches `_fills` / `_badges`. L'ancien `CONTINENT_COLORS` (teinte de fond par continent) devient inutile et est retiré.
- **Validation :** compilation headless éditeur + boot runtime `main.tscn` = 0 erreur / 0 warning. Rendu hors-ligne (état factice 3 joueurs × 42 territoires) : **42 remplissages + 42 badges** générés, chiffres lisibles, couleurs de faction distinctes, carte de fond visible par transparence.
- **Pourquoi :** dessiner les 42 polygones dans une scène dédiée évite d'ouvrir/risquer l'arène complète (HUD, thèmes, SubViewport) à chaque session de Level Design, et permet de tester le plateau seul. **Toute modification du plateau (fond, polygones, ajout de territoires) se fait dans `board.tscn`**, jamais dans `main.tscn`.

### 8.23. Confort UX (identité, abandon, lisibilité) & Déplacement post-conquête
> Quadruple mission issue des playtests. **(1)** Le joueur est clairement identifié (vrai pseudo + couleur de faction). **(2)** Abandonner **sort de l'arène**. **(3)** Les textes du HUD sont agrandis (lisibilité). **(4)** Après une conquête, le joueur **choisit combien de troupes** déplacer sur le territoire pris (curseur), le jeu restant figé jusqu'à validation. **Frontend → actif au relancement du client ; Backend (conquer_move) → push + redéploiement VPS requis (§1/§8.7).**

**Partie 1 — Identité & couleur du joueur (`auth_manager.gd`, `hud.gd`, `board.gd`, `main.gd`, `main.tscn`).**
- `AuthManager.username` : renseigné dès le login en décodant le claim `sub` du JWT (`_username_from_jwt` : base64url → base64 standard + padding, sans vérif de signature), puis **confirmé** par `/auth/me` (`UserResponse.username`). Le JWT ne porte que le username (§5) ; l'id numérique reste récupéré via `/auth/me` (`user_id`).
- TopBar : nouveau `%IdentityLabel` (« 👤 <pseudo> ») dont la **couleur** est l'accent de faction du joueur LOCAL. Pour rester **cohérente avec le plateau**, la couleur vient de `board.get_player_color(pid)` (nouveau getter public : accent du `.tres`, sinon `PALETTE` par index, gris si inconnu) ; `main.gd._refresh()` pousse `hud.set_local_identity(_display_name(my_id), color)`. `%InfoLabel` affiche le **vrai pseudo** quand c'est NOTRE tour (sinon « JOUEUR N » séquentiel — on ne connaît pas le pseudo des autres, le serveur ne diffusant que `player_id`+`faction`). Helper `main._display_name(pid)` (pseudo si local, sinon « Joueur N ») réutilisé dans les instructions et l'écran de victoire/défaite (fin des « Joueur #<id brut> »).

**Partie 2 — Abandon = sortie de l'arène (`main.gd`).** `_on_abandon_pressed()` : envoie l'action `abandon` (le serveur fige nos troupes en défense auto, §8.20), **vide le tampon du socket** (`socket.poll()`) pour garantir le départ du message, coupe proprement la connexion (`connected=false`, `set_process(false)`, `socket.close()` — évite qu'un socket resté ouvert bloque une future reconnexion, `connect_to_server` court-circuitant si l'état est OPEN), puis `get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")`.

**Partie 3 — Lisibilité du HUD (`main.tscn`).** Polices agrandies : TopBar `%PhaseLabel`/`%TimerLabel` 18 → **22**, `%InfoLabel`/`%InstructionLabel` → **18** ; SidePanel `ChatTabs` 12 → **16**, les 3 onglets de chat + `%LogText` (`normal_font_size`) 12 → **16**, `LogTitle` 13 → **16**. Le `SidePanel` est élargi : ratio d'étirement `MapFrame` 9.0 → **8.0** et `SidePanel` (nouveau) **2.0** → comms/journal passent de ~10 % à ~20 % de la largeur du bloc central.

**Partie 4 — Déplacement post-conquête (full-stack, `state_schemas.py`, `engine.py`, `router.py`, `main.tscn`, `main.gd`).**
- **Schéma :** `PlayerState.pending_conquer: Optional[Dict[str, Any]] = None`. `None` = aucune conquête à résoudre ; sinon `{from_tid, to_tid, min, max, moved}`. Défaut `None` → rétro-compatible avec les états Redis existants.
- **Moteur (`_handle_attack`) :** sur une conquête, on ne déplace plus « tout » ni « 3 troupes » d'office — on déplace le **minimum obligatoire** (= nombre de dés de l'attaque, règle classique) puis, **s'il reste un vrai choix** (`max > min`), on pose `pending_conquer` et l'évènement `attack_result` porte `conquer_pending/_from/_to/_min/_max`. Bornes : `min = attacker_dice`, `max = garnison_attaquant_avant_déplacement − 1` (≥ 1 doit rester). Propriété clé exploitée : **sur une conquête les pertes attaquantes sont toujours nulles** (la garde « garnison ≤ dés » l'assure), donc `min ≤ max` est garanti dès que `max > min`.
- **Nouveau handler `_handle_conquer_move(state, payload)` :** vérifie la cohérence avec `pending_conquer` (même couple de territoires), borne `troops ∈ [min, max]`, ne transfère que le **surplus** `delta = troops − moved` (le minimum a déjà été déplacé), puis efface `pending_conquer`. Évènement `conquer_move_resolved`.
- **Gel des autres actions :** `process_action` refuse toute action ≠ `conquer_move` tant que `pending_conquer` est posé (« Vous devez d'abord répartir vos troupes sur le territoire conquis ») et refuse `conquer_move` s'il n'y a rien à résoudre. Filets de sécurité : `_end_turn` remet `pending_conquer = None` (le joueur ne peut de toute façon pas passer la main pendant l'attente) et `_handle_abandon` l'efface (l'état reste cohérent, le minimum est déjà déplacé).
- **Frontend (`main.tscn` + `main.gd`) :** fenêtre `%ConquerDialog` (overlay `Control` plein écran masqué par défaut : fond assombri `Dim` + `CenterContainer`/`Panel` avec `%ConquerInfo`, `%ConquerSlider` (HSlider), `%ConquerValue`, `%ConquerConfirm`). À la réception d'un `attack_result` `conquered`+`conquer_pending` **par l'attaquant local** (après l'animation Split-Screen VS, et pas si la conquête a gagné la partie), `_show_conquer_dialog` cale le curseur sur `[min, max]` et **fige le jeu** (`_awaiting_conquer_move` → clics plateau / `Fin de Phase` / cartes neutralisés, + l'overlay intercepte l'input). La validation envoie `{"action":"conquer_move","payload":{from_tid,to_tid,troops}}` et referme la fenêtre. Nœuds accédés par **noms uniques `%`** (évite le piège des `node_paths` d'export typé, §wasteland-stack).
- **Validation :** `py_compile` OK (`engine.py`/`state_schemas.py`/`router.py`/`test_simulation.py`) ; **test ciblé du moteur réel** (handlers `_handle_attack`/`_handle_conquer_move` avec dépendances lourdes stubbées) : conquête → minimum déplacé + bornes (min=3, max=4), `conquer_move` déplace le surplus, bornes hors `[min,max]` et mauvais couple refusés, `max==min` → pas de fenêtre. Frontend : boot runtime headless `main.tscn` = 0 erreur (les noms `%` de la fenêtre résolus dans `_ready`). `test_simulation.py` mis à jour (résout la conquête avant de passer le tour).

### 8.25. Correctifs de 3 bugs de playtest (Draft 10 factions, Placement 0-stock, Zone radioactive)
> Trois bugs remontés en playtest sur un jeu pourtant « feature complete ». **Bug 1 (Draft) & Bug 3 (Zone radioactive) → Frontend, actifs au relancement du client. Bug 2 (Placement) → déjà corrigé dans le code, mais le live tourne l'ancien backend : push + redéploiement VPS requis (§1/§8.7).**

**Bug 1 — Le Draft n'affichait que 3 factions sur 10.** *Cause racine :* le carrousel (`faction_selection.gd`) était **déjà data-driven** (scan dynamique de `resources/factions/*.tres`, §8.13/§8.14) — ce n'était PAS une liste codée en dur. Le vrai manque était les **données** : seules **3** ressources `.tres` existaient (`phalanges_acier`, `pillards_poussiere`, `culte_isotope`) alors que le registre backend `factions.py` en compte **10**. *Fix :* création des **7 `.tres` manquants** (`barons_ferraille`, `gardiens_eden`, `corporation_aegis`, `ecorcheurs_cendres`, `eveilles_ruche`, `ordre_eclipse`, `chasseurs_ombres`) — id aligné sur `factions.py`, modificateurs miroir, `accent_color` propre à chaque faction. `FALLBACK_PATHS` (repli si le scan échoue) **étendu aux 10** chemins. **Bonus :** `board.gd._load_faction_accents()` scanne le même dossier → les **10/10** factions ont désormais leur couleur d'accent sur le plateau (était 3/10, §8.22). **L'UI reste un CARROUSEL** (carte plein cadre + ◄/►, statut « Faction X/10 »), pas une grille : il accueille N factions sans re-layout — aucun code de vue à toucher, seules les données manquaient. Validé : boot headless du scan → `FACTION_COUNT=10`, ids identiques au backend.

**Bug 2 — Un joueur à 0 stock pouvait recevoir un tour / placer pendant le Setup.** *Constat :* dans le **code actuel** (`engine.py`), les trois gardes demandées **existent déjà et sont correctes** : (a) `_handle_place_initial` lève si `units_in_stock <= 0` ; (b) `_advance_setup_index` **saute** les joueurs à 0 troupe **et** inactifs (abandon) ; (c) `_all_stocks_empty` (qui ignore les inactifs) → `_start_playing` **clôt** la phase dès que tous les stocks actifs sont vides. Le bug observé en playtest vient du **backend non redéployé** (le VPS tourne l'ancien code, §8.7). *Action :* **aucune modification moteur** (ne pas « corriger » du code déjà correct) ; ajout d'un **test de régression `backend/test_setup_phase.py`** (21 assertions, moteur réel sans Redis) qui verrouille les 3 garanties + refus hors-tour + refus au-delà de la fournée de 3 + simulation complète (clôture auto, invariant « jamais de tour à un stock vide ») + cas Fallen Empire (joueur inactif ne bloque pas la clôture). **21 ✅ / 0 ❌.** ⚠️ Le correctif est donc **un déploiement**, pas un patch de code. NB : à la clôture, `_start_playing` crédite immédiatement les **renforts** du 1ᵉʳ joueur (entrée en phase 1) → son `units_in_stock` est volontairement > 0, les autres sont à 0.

**Bug 3 — La zone radioactive n'était pas visible sur le plateau.** *Cause racine :* `board.gd` teintait bien le remplissage en vert (`lerp` vers `#7fff00`) et préfixait « ☢ » **uniquement** sur `node.text` — or les 42 territoires sont des `Area2D` dessinés à la main **sans propriété `text`** (le préfixe ne servait qu'au fallback `BaseButton`). Sur le vrai plateau, le seul indice était une teinte verte discrète sur un remplissage semi-transparent. *Fix (`territory_badge.tscn` + `.gd`, `board.gd`) :* le **badge** de troupes affiche désormais une **icône ☢ verte** (nouveau `RadLabel`, SystemFont « Segoe UI Symbol », masqué par défaut) au-dessus du chiffre **+ un anneau vert nucléaire** (`_draw`) autour de la pastille quand le territoire est contaminé. `board.gd` calcule `is_contaminated = (tid == zone)` et le pousse via `set_data(troops, accent, contaminated)` ; le remplissage du polygone contaminé est **renforcé** (`lerp` 0.55→0.70 + `FILL_ALPHA` 0.42→0.62). **Réinitialisation automatique :** l'état de contamination est repassé à **chaque** `generate_board()` → un territoire qui sort de la zone redevient propre (☢ masqué, anneau retiré, remplissage normal) sans code dédié. `set_data` garde un 3ᵉ paramètre **optionnel** (rétro-compatible).

**Validation globale.** `py_compile api/game/engine.py` OK. `test_setup_phase.py` **21 ✅**, `test_factions.py` **38 ✅** (aucune régression). Godot 4.6.3 **headless** : `--import` = **0 SCRIPT ERROR** (un bug d'inférence `:=` sur `is_contaminated` — la clé de Dictionary `tid` est un Variant — corrigé en type explicite `: bool`), boot `faction_selection.tscn` & `main.tscn` = 0 erreur, scan des factions = **10/10**.

### 8.29. Refonte HUD « RTS moderne » — plateau plein écran + widgets flottants (Frontend)
> L'arène passe d'un layout « fenêtré » (3 blocs en conteneurs pleins, §8.17) à un design **RTS moderne** : le **plateau occupe 100 % de l'écran** et le HUD devient un **Control transparent aux clics** sur lequel **flottent des widgets** en glassmorphism militaire (kaki sombre translucide). **Frontend exclusif** (actif au relancement du client Godot, aucun redéploiement backend). **API publique `hud.gd` intégralement préservée** (aucun changement de contrat pour `main.gd`).

- **Libération du plateau.** `MapViewportContainer` (→ `MapContent` SubViewport → `TacticalCamera` + `Board`) est désormais le **1ᵉʳ enfant de `Main`** en `PRESET_FULL_RECT` (`stretch = true`). L'ancien cadre `MapFrame` (`PanelContainer` à bordure 30 px) et les conteneurs de mise en page `MiddleBlock`/`SidePanel`/`TopBar`/`BottomBar` sont **supprimés**. La `TacticalCamera` recadre 100 % du `board_bg` sur tout le viewport (`size_changed`, §8.17) → la carte remplit la fenêtre.
- **HUD flottant.** Le nœud `HUD` n'est plus un `VBoxContainer` plein écran mais un **`Control`** (`PRESET_FULL_RECT`, **`mouse_filter = 2` (IGNORE)**) → les clics **traversent** les zones vides du HUD pour atteindre le plateau (picking Area2D). `hud.gd` **`extends Control`** (et non plus `VBoxContainer`).
- **Hiérarchie réelle de `main.tscn`** :
  - `Main` (Node, `main.gd`)
	- `MapViewportContainer` (`SubViewportContainer`, FULL_RECT, `stretch`) → `MapContent` (SubViewport, `transparent_bg`, `physics_object_picking`) → `TacticalCamera` + `Board` (instance `board.tscn`).
	- `HUD` (`Control`, FULL_RECT, `mouse_filter = IGNORE`, `hud.gd`)
	  - `TopCenterWidget` (`PanelContainer` ancré **haut-centre**, style glass) → `%IdentityLabel`, `%PhaseLabel`, `%InfoLabel`, `%TimerLabel` (MM:SS) + `%InstructionLabel`.
	  - `TopRightWidget` (`PanelContainer` ancré **haut-droite**) → `%AbandonButton` (rouge).
	  - `SidePanelWidget` (`Control` ancré **droite, pleine hauteur**, `mouse_filter = IGNORE`) → `GlassBody` (`PanelContainer` glass) → `SideVBox` [ `ChatIconBar` (3 boutons-icônes `%TabBtnGeneral/Allies/Prive` en `ButtonGroup`) + `%ChatTabs` (`TabContainer`, **`tabs_visible = false`**, pages `GÉNÉRAL`/`ALLIÉS`/`PRIVÉ`) + `MilitaryLog` → `%LogText` ] ; **`%ToggleSidePanelButton`** protubère à gauche du panneau (bascule rétractable).
	  - `BottomCenterWidget` (`PanelContainer` ancré **bas-centre**) → `CardsTitle` + `%CardsBox` (cartes « +N ») + `%ObjectiveLabel` + `ActionRow` [ `%AmountSpin` + `%NextPhaseButton` ] (+ le bouton « CONFIRMER LE DÉPLOIEMENT » inséré **par code** avant `%NextPhaseButton`).
	- `Button` (debug init), puis **`%ConquerDialog`/`%EclipseDialog`/`%SpyDialog`** (overlays inchangés, derniers enfants → dessinés au-dessus).
- **Règle `mouse_filter` (passe-clic).** Racine `HUD` = **IGNORE** ; `SidePanelWidget` (wrapper) = **IGNORE** ; tous les **PanelContainer-widgets** (Top/Bottom/GlassBody) + boutons = **STOP** (défaut) → ils captent le clic sur leur surface (on ne clique pas le plateau « au travers » d'un widget) mais l'**espace vide** laisse passer vers `MapViewportContainer`. L'ordre de dessin garantit le passe-clic : le viewport est 1ᵉʳ enfant (dessous), le HUD au-dessus mais IGNORE.
- **Nouveautés `hud.gd` (API publique inchangée — `pass_pressed`/`card_played`/`abandon_pressed`/`deploy_confirmed`, `update_display`/`set_deploy_confirm`/`set_local_identity`/`add_log`/`add_chat_message`/`set_instruction`/`get_amount`/`lock_abandon_button`)** :
  1. **Panneau latéral rétractable** : `%ToggleSidePanelButton` → `_toggle_side_panel()` anime `position.x` de `SidePanelWidget` (Tween natif `TRANS_SINE`/`EASE_OUT`, slide in/out). Métriques (x déployé + largeur) mémorisées au 1ᵉʳ clic (`_cache_side_metrics`, après résolution du layout). Le bouton protubère → reste cliquable au bord de l'écran une fois replié (libellé ▶/◀).
  2. **Onglets par icônes** : la barre native du `TabContainer` est masquée (`tabs_visible=false`) ; une rangée de 3 boutons-icônes (📢/🤝/🔒, `ButtonGroup`) pilote `%ChatTabs.current_tab` via `_select_chat(channel)`. `_chat_channels` mappe toujours les 3 `RichTextLabel` (`get_node`) → `add_chat_message` inchangé.
  3. **Journal ergonomique** : `add_log(text, icon_path := "")` accepte une **icône** optionnelle (`[img=18]…[/img]`) ; helper `color_pseudo(pseudo, accent) -> String` (BBCode `[color=#rrggbb]`) pour colorer un pseudo à l'`accent_color` du joueur. Rétro-compatible (les appels mono-argument existants marchent tels quels).
  4. **Masquage UI pour le Split-Screen VS** : `fade_ui_for_combat(is_hidden: bool)` Tween `modulate.a` du HUD racine (1↔0 sur 0,5 s). `main.gd._play_combat_resolution` appelle `fade_ui_for_combat(true)` avant le duel et `(false)` après `animation_finished`. La scène VS étant enfant de `Main` (hors HUD), seul le HUD s'efface.
- **Impact `main.gd`.** Le SubViewport ayant quitté le HUD, les `@onready` de plateau changent : `board = $MapViewportContainer/MapContent/Board`, `camera = $MapViewportContainer/MapContent/TacticalCamera` (au lieu de `$HUD/MiddleBlock/MapFrame/MapViewportContainer/...`). `hud = $HUD` inchangé. `board.gd` (NodePath relatif `TerritoriesContainer`) et `tactical_camera.gd` **inchangés**. Ajout des 2 appels `hud.fade_ui_for_combat(...)` autour du duel.
- **Conservé.** Timer MM:SS, abandon 2 clics + `lock_abandon_button`, identité locale colorée (`%IdentityLabel`), tampon de déploiement + bouton « Confirmer » (§8.26), overlays `%ConquerDialog`/`%EclipseDialog`/`%SpyDialog` (§8.23/§8.24), styles `StyleBoxFlat` militaires (orange fusion au survol). Nouveau style `StyleBoxFlat_glass` (kaki `Color(0.12,0.15,0.08,0.7)`, bordure discrète).

### 8.30. Sublimation visuelle — VFX du plateau (CRT, zone toxique, cendres) (Frontend)
> Premier lot de l'**Objectif 2** (esthétique, §8.10). Trois effets visuels **strictement confinés au plateau** (SubViewport `MapContent`) pour préserver la **netteté de l'UI flottante** (§8.29) : un post-processing **CRT / scanlines** « vieil écran de bunker », une **pulsation toxique** sur les territoires contaminés, et une pluie de **cendres post-apo**. **Frontend exclusif** (actif au relancement du client Godot, aucun redéploiement backend). Monté via le **MCP Godot** sur la scène live (pas d'édition texte de `main.tscn`, cf. §8.15).

- **Nouveau dossier `frontend/shaders/`** : `crt_board.gdshader`, `toxic_pulsation.gdshader`, et `crt_board_material.tres` (le `ShaderMaterial` du CRT assigné à `CRTEffect`).
- **Arborescence ajoutée dans `main.tscn` → `MapContent`** (l'**ordre des enfants = ordre de rendu** : cendres AVANT le CRT pour qu'elles subissent les scanlines ; CRT en dernier, par-dessus tout) :
  - `MapContent` (SubViewport, `transparent_bg`, `physics_object_picking`, `render_target_update_mode = ALWAYS` — indispensable : les shaders à base de `TIME` n'animent que si le viewport se redessine en continu)
	- `TacticalCamera` (Camera2D) · `Board` (instance `board.tscn`) — **inchangés**
	- **`AshParticles`** (`GPUParticles2D`) — émetteur des cendres, espace MONDE (layer 0 → suit le zoom/pan de la `TacticalCamera`).
	- **`PostFX`** (`CanvasLayer`) → **`CRTEffect`** (`ColorRect`, `anchors_preset = FULL_RECT`, **`mouse_filter = IGNORE`**, `material = crt_board_material.tres`).
- **⚠️ Pourquoi un `CanvasLayer` pour le CRT (et NON un `ColorRect` enfant direct de `MapContent`, comme demandé initialement).** `MapContent` contient une `TacticalCamera` (§8.17). Or un `Control` en layer 0 est rendu **à travers la transformée de la caméra** → un `ColorRect` plein-cadre enfant direct serait **déplacé et mis à l'échelle** par la caméra (zoom ≈ 0,42 en vue plein plateau) et **ne couvrirait pas l'écran**. Le `CanvasLayer` (transformée identité, insensible à la Camera2D) corrige cela : le `ColorRect` couvre tout le viewport. Le `screen_texture` du CRT capture quand même le board + les cendres car le `CanvasLayer` est rendu **après** le layer 0.
- **Shader 1 — `crt_board.gdshader`** (`canvas_item`). Lit `screen_texture : hint_screen_texture, filter_linear_mipmap`. Uniforms **recalibrés « glassmorphism militaire »** (rappel matériel subtil, lisibilité de la carte préservée ; les valeurs vives sont celles de `crt_board_material.tres`, et les `defaults` du shader sont désormais alignés dessus) : `scanline_intensity` (**0.08** — lignes à peine perceptibles), `scanline_count` (650), `scanline_scroll` (**2.0** — défilement quasi figé : le mouvement était la 1ʳᵉ cause de fatigue), `vignette_strength` (**0.18** — bordure discrète, bords non écrasés), `aberration` (**0.0006** — décalage R/B ~1px @1080p, presque imperceptible), `curvature` (**0.02** — barrel réduit : plateau quasi plat, coins à peine arrondis). **Préserve l'alpha de l'écran** (`g.a`) et l'annule hors-cadre → les **bandes latérales transparentes** (la caméra plein plateau ne remplit que la hauteur, des marges restent à gauche/droite) gardent le fond sombre derrière le SubViewport, et la courbure donne des coins arrondis. Si on forçait `alpha = 1`, ces bandes deviendraient noires.
- **Shader 2 — `toxic_pulsation.gdshader`** (`canvas_item`). Uniforms : `base_color` (accent du propriétaire, poussé par `board.gd`), `rad_color` (#7fff00), `pulse_speed` (3.0), `pulse_min`/`pulse_max` (0.25/0.85), `fill_alpha` (0.62). `sin(TIME * pulse_speed)` fait pulser le remplissage entre l'accent de la faction et le vert nucléaire. Le shader **écrase la couleur du vertex** (`COLOR = vec4(col, fill_alpha)`) → `board.gd` n'a pas à teinter le `Polygon2D` quand le matériau est actif.
- **`board.gd` — intégration dynamique (data-driven, pas d'id en dur).** Dans `generate_board()`, pour un territoire **contaminé** (`is_contaminated`, modèle cluster §8.27), le nouvel helper `_apply_toxic_material(fill, base_accent)` crée/**réutilise** un `ShaderMaterial` (`ToxicShader` preloadé) sur le `Polygon2D` de remplissage et lui passe `base_color = accent` (éclairci si sélectionné), `rad_color`, `fill_alpha`. Hors zone → `fill.material = null` (retour au remplissage statique, qui reste calculé comme **repli** si le shader échoue). Réinitialisation **automatique** à chaque `generate_board()` (un territoire qui quitte la zone redevient propre, cohérent avec §8.25/§8.27). Constantes ajoutées : `ToxicShader`, `RAD_COLOR`, `CONTAMINATED_ALPHA`. ⚠️ Effet **visible uniquement en jeu** (nécessite une zone radioactive dans l'état).
- **`AshParticles` — config (`ParticleProcessMaterial`).** Émission **Box** `emission_box_extents = (1100, 8)` (largeur 2200 = plateau), émetteur en haut (`position = (1100, -100)`), `gravity (0,16)` + `initial_velocity 10–25` (chute douce), `direction (0,1)` / `spread 18`, **turbulence** activée (`strength 3`, `scale 1.8`, `influence 0.05–0.18`) pour faire flotter les cendres au lieu de tomber droit, `scale 1–3` (petits carrés — pas de texture → carré blanc par défaut de Godot), `color (0.82, 0.82, 0.85, a = 0.4)`, `amount 220`, `lifetime 13`, **`preprocess 10`** (écran déjà rempli au lancement), `randomness 1`. Tunables si on veut des cendres plus denses/visibles (`amount`, `color.a`, `scale`).
- **Netteté de l'UI garantie.** Le `HUD` (§8.29) est **hors** du SubViewport → jamais lu par `screen_texture` ni cendré : seul le plateau subit les VFX. `CRTEffect` en `mouse_filter = IGNORE` ne bloque pas le picking des `Area2D` (clics territoires).
- **Validation (run réel `main.tscn`, capture du framebuffer).** Shaders réimportés sans erreur ; nodes créés + scène sauvegardée via MCP ; `board.gd` recompile (preload du shader résolu, 0 erreur) ; boot runtime **0 erreur**. **Screenshot 1920×1080 :** scanlines + aberration chromatique + vignette + courbure **bien visibles sur le plateau**, **UI flottante parfaitement nette** (aucune scanline), bandes latérales transparentes préservées (pas de noir). `game_eval` runtime : `AshParticles.emitting = true` (220, ProcessMaterial OK), `CRTEffect.material` assigné, `mouse_filter = 2`.

### 8.32. Adaptation frontend Phase 0 aveugle + Hologramme Tactique + ergonomie UI (Frontend)
> Volet **client** du sprint §8.31 (les « Suites frontend ») **plus** 2ᵉ lot de l'**Objectif 2** : (1) déverrouillage de la Phase 0 aveugle & simultanée côté UI ; (2) compte à rebours HUD aligné 90 s / 60 s ; (3) **Concept A « Hologramme Tactique »** (contour néon + hachures défilantes, fin du remplissage opaque illisible) ; (4) ergonomie — **panneau inférieur rétractable** + **tooltip Pouvoir de Faction**. **Frontend exclusif** (actif au relancement du client Godot, aucun redéploiement). Validé via **MCP Godot** (reparse scène + scripts, boot runtime 0 erreur).

**1. Phase 0 — déploiement aveugle & simultané côté client (`main.gd`).**
- **Levée du gating `setup_index`.** `_is_my_setup_turn()` / `_setup_current_player()` **supprimés** au profit de `_can_blind_deploy()` (= `stage == "placement"` ET pas encore soumis ET stock à poser). `_in_deploy_mode()` autorise donc **tous** les joueurs actifs à remplir leur tampon **en parallèle** pendant le placement (plus aucun ordre de tour).
- **Verrou local de soumission.** Le serveur **masquant** `pending_blind_deploy` dans l'état diffusé (§8.31), le client ne peut pas relire sa propre soumission → nouveau flag **`_blind_submitted`** : passé à `true` dans `_on_deploy_confirmed()` (en `placement`), il **gèle** toute modification (clics tampon ignorés, bouton « Confirmer » masqué) et bascule l'instruction. Remis à `false` dans `_refresh()` dès qu'on quitte le placement.
- **Message d'attente persistant.** `_update_instruction()` (branche `placement`) affiche, une fois soumis, **« ⏳ Déploiement validé — en attente des autres joueurs… (X/Y) »** ; X/Y = `ready_count`/`expected_count` lus de l'évènement `blind_deploy_submitted` (mémorisés dans `_blind_ready`/`_blind_expected` par `_on_game_event`). Les troupes pré-déployées des adversaires **ne sont jamais affichées** (masquées serveur).
- **Journal.** `_format_event()` gère désormais `blind_deploy_submitted` (compteur), `blind_deploy_resolved` (`forced` ⇒ « délai écoulé ») et `turn_timeout`.

**2. Timer HUD — compte à rebours local PAR PHASE (`hud.gd`).** ⚠️ **Révisé (CONTRAT_RESEAU §8.62, 2026-07-01) : rebours PAR PHASE** (avant : 60 s pour tout le tour, qui coupait le tour en phase tardive).
- Le serveur **ne diffuse PAS d'échéance** dans l'état (sa minuterie est purement serveur, autorité §8.31). Le HUD affiche un **rebours LOCAL indicatif** qui **repart à chaque « Fin de Phase »** : `_process()` décompte depuis **`_turn_limit`**, posé par `update_display()` et **remis à zéro** quand la signature **`étape|tour|joueur|phase`** change (`_turn_key` — la **phase** est NEUVE dans la clé). Budget via `_phase_turn_limit()` : **`PHASE0_TIME = 90`** en `placement` ; en `playing`, **`ATTACK_PHASE_TIME = 90`** en phase d'Attaque (3) — extensible jusqu'à **`ATTACK_PHASE_TIME_MAX = 180`** par la Time Bank — et **`TURN_TIME = 60`** pour les autres phases ; `0` ⇒ `--:--` hors tour minuté. `add_time_to_timer` (Time Bank) plafonne à **180 s** (miroir du hard_cap serveur en Attaque). Le label passe en **rouge** sous 10 s. Léger décalage possible vs. l'échéance serveur (toléré).

**3. Concept A « Hologramme Tactique » (`neon_hologram.gdshader`, `board.gd`).**
- **Nouveau shader `frontend/shaders/neon_hologram.gdshader`** (`canvas_item`). Uniforms : `accent_color` (faction propriétaire), `edge_points[64]` + `point_count` (sommets du polygone, espace local), `neon_width`/`glow_width`/`glow_strength`/`neon_boost`, `hatch_frequency`/`hatch_speed`/`hatch_width`/`hatch_alpha`. Le `vertex()` transmet `VERTEX` en varying ; le `fragment()` calcule la **distance au bord le plus proche (SDF)** à partir de `edge_points` → **contour néon** épousant le bord intérieur (marche pour les polygones concaves) + **halo diffus**, et des **hachures diagonales fines** qui défilent via `TIME`. Le shader **écrase `COLOR`** ⇒ plus de remplissage opaque uni (lisibilité).
- **`board.gd` — intégration.** Nouvel helper `_apply_hologram_material(fill, accent)` (réutilise le matériau s'il porte déjà ce shader ; pousse `accent_color` + `fill.polygon` clampé à `MAX_HOLO_POINTS = 64`). Dans `generate_board()`, priorité **zone d'abord** : contaminé → `_apply_toxic_material` (pulsation toxique §8.30, **inchangée** — garde de type ajouté pour ne pas écraser un hologramme) ; possédé **hors** zone → `_apply_hologram_material` ; **neutre** → `material = null` + remplissage gris **très sombre** (`NEUTRAL_FILL_COLOR`/`_ALPHA`, « vide »). Le `fill.color` statique n'est plus qu'un **repli** (accent quasi transparent `HOLO_FALLBACK_ALPHA`). Constantes ajoutées : `HologramShader`, `MAX_HOLO_POINTS`, `HOLO_FALLBACK_ALPHA`, `NEUTRAL_FILL_COLOR`, `NEUTRAL_FILL_ALPHA`.

**4. Ergonomie UI (`main.tscn`, `hud.gd`).**
- **Panneau inférieur rétractable (vers le bas).** `BottomCenterWidget` passe de `PanelContainer` à **`VBoxContainer` wrapper** = `ToggleBottomPanelButton` (slim, `SHRINK_CENTER`, ▼/▲) **+** `GlassBody` (`PanelContainer` vitré reparenté avec tout l'inventaire). `hud._toggle_bottom_panel()` **Tween** `position:y` du wrapper de la hauteur du `GlassBody` (mémorisée juste avant le repli) → le panneau se cache sous l'écran, seul le bouton reste visible (miroir du `SidePanelWidget` §8.29). Les nœuds uniques (`%CardsBox`, `%ObjectiveLabel`, `%AmountSpin`, `%NextPhaseButton`) sont conservés (% inchangé).
- **Tooltip « Pouvoir de Faction ».** Icône **`%FactionInfoButton`** (« ⓘ ») ajoutée dans le `TopRow` à côté de `%IdentityLabel`. Au survol (`mouse_entered`/`mouse_exited`), `hud._show/_hide_faction_tooltip()` affiche un `PanelContainer` flottant **`%FactionTooltip`** (`%FactionTooltipTitle` + `%FactionTooltipDesc` BBCode), positionné sous l'icône et **clampé** à l'écran. Données poussées par `main._local_faction_info()` (scan robuste de `resources/factions/*.tres` gérant le `.remap`, cache par id) → `hud.set_faction_info(name, description)` (icône masquée si faction inconnue).

**Fichiers touchés (`frontend/`).** `shaders/neon_hologram.gdshader` (NOUVEAU) ; `scripts/game/board.gd`, `scripts/game/main.gd`, `scripts/ui/hud.gd`, `scenes/game/main.tscn` (modifiés). **Backend inchangé** (contrat §8.31 respecté tel quel).

**Validation (MCP Godot, 4.6.3).** Reparse de `main.tscn` depuis le disque → scène OK (nouveaux nœuds acceptés) ; `main.gd`/`hud.gd`/`board.gd` recompilent **0 erreur** (preload du shader résolu ⇒ shader parsé) ; **run runtime `main.tscn` 0 erreur** (`_ready` du HUD résout les nouveaux nœuds uniques). Seuls avertissements restants : `SHADOWED_VARIABLE` **préexistants** dans `auth_manager.gd` (hors périmètre).

### 8.36. HUD in-game « Modern Warfare » — alignement charte glassmorphism §2 + Tiroir « INTEL : ZONE » (Frontend)
> 3ᵉ lot de l'**Objectif 2** (sublimation visuelle). Deux volets : (1) le HUD flottant de l'arène (§8.29), jusqu'ici en **glassmorphism KAKI** (`Color(0.12,0.15,0.08,0.7)`), est **réaligné sur la charte canonique « Modern Warfare » §2** (verre **anthracite** `Color(0.05,0.05,0.07,0.8)` + accent Orange Fusion `#d35400`, déjà en place sur `auth_screen`/`lobby` §2.1/§2.2) ; (2) implémentation des **« Tiroirs Tactiques »** : un tiroir **INTEL** exploitant la **Mémoire Tactique** du serveur (`GameState.statistics`, §8.35 [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md)). **Frontend exclusif** (actif au relancement du client, aucun redéploiement backend ; le champ `statistics` est déjà diffusé). **API publique `hud.gd` préservée** (ajout pur : `set_intel()`), **Règle d'Or §6.1 respectée** (le HUD reste une View, le contrôleur résout les données).

**1. Charte glassmorphism unifiée (`main.tscn` — `StyleBoxFlat` embarqués).**
- **`StyleBoxFlat_glass` reteinté** (kaki → anthracite `Color(0.05,0.05,0.07,0.8)`, liseré orange discret `Color(#d35400, 0.35)`, coins 8, **ombre portée**). Propagé d'un coup à `TopRightWidget`, `SidePanelWidget/GlassBody` (comms/journal — fini le kaki), `BottomCenterWidget/GlassBody` et aux boutons de bascule.
- **`StyleBoxFlat_panel` rendu translucide** (`Color(0.07,0.07,0.07,1)` opaque → `Color(0.05,0.05,0.07,0.72)`) → les panneaux INTÉRIEURS jadis « opaques » (`ChatTabs`, `MilitaryLog`, pop-ups `%ConquerDialog`/`%EclipseDialog`/`%SpyDialog`, `%FactionTooltip`) passent en verre.
- **Nouveau `StyleBoxFlat_topbar`** (assigné à `TopCenterWidget`) : bandeau panoramique **très fin** (marges verticales 5/6 px), verre anthracite, **liseré orange bas 2 px** (lecture « readout de commandement »).
- **Nouveau `StyleBoxFlat_intel`** (panneau du tiroir Intel) : verre anthracite + **liseré orange GAUCHE 4 px** (calque exact de l'accent latéral §2, le tiroir étant ancré à gauche).
- **Nouveaux `StyleBoxFlat_ghost` / `StyleBoxFlat_ghost_hover`** (boutons « ghost » §2) : fond quasi transparent, fin liseré orange ; au survol le fond s'orange légèrement, le liseré passe plein `#d35400`. Assignés à **`%NextPhaseButton`** (« FIN DE PHASE ») et **`%ConquerConfirm`** (« DÉPLOYER LES TROUPES »), + `font_hover_color`/`font_pressed_color = #d35400` → **le texte s'illumine en orange au survol**. Le gros bouton **« CONFIRMER LE DÉPLOIEMENT »** (construit par code, `hud._build_confirm_button`) bascule du vert kaki au **même style ghost** (`ACCENT_ORANGE` + `font_hover_color`). *(Le `%AbandonButton` rouge — CTA de danger — et les `StyleBoxFlat_btn` des onglets/icônes restent inchangés à dessein.)*
- **Typographie militaire :** inchangée car déjà fournie par le `Theme_mil` embarqué (`SystemFont` Stencil→Urbanist→Arial, gras §8.17) hérité par tous les Labels du HUD, **y compris les nouveaux nœuds Intel**.

**2. Tiroir « INTEL : ZONE » — Mémoire Tactique (`main.tscn` + `hud.gd` + `main.gd` + `game_state.gd`).**
- **UI (`main.tscn`).** Nouveau **`IntelWidget`** (`VBoxContainer`) ancré **bord gauche, milieu** (`anchors_preset = 4`, `alignment = 1`, `mouse_filter = IGNORE` → l'espace vide laisse passer les clics au plateau, règle §8.29) : bouton ghost **`%IntelToggleButton`** (« 🛰 INTEL : ZONE ▸/▾ ») **+** **`%IntelPanel`** (`PanelContainer` `StyleBoxFlat_intel`, **masqué par défaut**) → `IntelVBox` [ titre « ☢ MÉMOIRE TACTIQUE » + **`%StagnationLabel`** + `HSeparator` + titre « ☠ PERTES INFLIGÉES PAR LA ZONE » + **`%ZoneKillsList`** (`VBoxContainer` peuplé par code) ].
- **Flux de données (Règle d'Or §6.1).** `GameState.update_from_json` parse le champ public **`statistics`** (nouveau `var statistics: Dictionary = {}`, défaut garanti). `main.gd._refresh()` appelle **`_push_intel()`** : lit `statistics.zone_stagnation_turns` (int) + `statistics.zone_kills_by_player` (`{"<pid>": kills}` — **clés STR / valeurs float en JSON, §5 → `int()`**), **résout** pseudo (`_display_name`) + **couleur de faction** (`board.get_player_color`) par joueur (tri par id croissant, kills > 0), puis pousse une liste prête à afficher via **`hud.set_intel(stagnation, entries)`**. Le HUD ne touche jamais au réseau/état.
- **Vue (`hud.gd`).** `set_intel()` écrit le libellé de stagnation et reconstruit `%ZoneKillsList` (un `Label` coloré à l'`accent_color` du joueur par perte ; repli « — Aucune perte enregistrée — » si vide). **`_toggle_intel()`** déploie/replie `%IntelPanel` par **fondu Tween** (`modulate:a`, cohérent avec les panneaux rétractables §8.29) et bascule la flèche ▸/▾. Constante `ACCENT_ORANGE := Color("d35400")` ajoutée (source de vérité unique côté code).

**Fichiers touchés (`frontend/`).** `scenes/game/main.tscn` (StyleBox reteintés + 4 nouveaux + nœuds `IntelWidget`), `scripts/ui/hud.gd` (`set_intel`/`_toggle_intel`/ghost confirm/`ACCENT_ORANGE`), `scripts/game/main.gd` (`_push_intel`), `scripts/managers/game_state.gd` (parse `statistics`). **Backend inchangé** (champ `statistics` déjà diffusé, §8.35).

**Validation (MCP Godot, 4.6.3).** **Run runtime `main.tscn` (chargé du disque, `autosave=false`) → 0 erreur** ; arbre runtime confirme `IntelWidget` + ses 9 descendants instanciés (nœuds uniques résolus). **Test fonctionnel `game_eval` :** `hud.set_intel(4, [ALPHA-OP:15, BRAVO-OP:3])` → `%StagnationLabel` = « STAGNATION : 4 round(s)… », `%ZoneKillsList` peuplé (2 lignes, format « ☠ <pseudo> — <n> unité(s) », couleurs de faction) ; `_toggle_intel()` → transition propre fermé(`▸`,masqué) ↔ ouvert(`▾`,visible). **Capture framebuffer 1920×1080** : bandeau haut fin anthracite, panneau comms en verre sombre, tiroir Intel à liseré orange gauche déployé, bouton « FIN DE PHASE » ghost — charte §2 cohérente sur tout le HUD. ⚠️ Avertissements `SHADOWED_VARIABLE` **préexistants** (`auth_manager.gd`) hors périmètre.

### 8.37. Architecture UI Finale — bascule « Warzone Command » + 4 modules (Frontend)
> Mega-sprint de clôture du HUD in-game et des interfaces annexes. **(A)** PIVOT DE CHARTE complet vers le langage **Call of Duty: Warzone** (« Warzone Command », §2) ; **(B)** quatre modules neufs. **Frontend exclusif** (actif au relancement du client ; `statistics` §8.35 et `time_bank_bonus_seconds` §8.33 déjà diffusés). **Aucun commit** (directive CTO). Validé via **MCP Godot 4.6.3** (boot runtime + screenshots framebuffer).

**A. Bascule de charte (tout le client).** Reteinte des `StyleBoxFlat` de chaque scène : orange `#d35400` → **cyan `#36c5d9`** (accent interactif dominant), kaki/anthracite → **gunmetal `#0f1318`** (surface `#1a2028`), **`corner_radius` → 0** (angulaire) ; police → SystemFont **condensé** (`Bahnschrift`→`Oswald`→`Saira Condensed`→`Arial Narrow`→`Arial`, 700) ; **or `#e0b249`** = récompense (XP, victoire, Time Bank, « plus lourd tribut »), **rouge `#d6453f`** = danger (abandon/déconnexion), **vert `#7fff00`** = contamination. **Boutons primaires en style « START »** (bordure cyan + lueur au survol). Rythme **eyebrow→valeur** MAJUSCULE, puces **chevron `❯`**. Écrans traités : `auth_screen`, `main_menu`, `lobby_screen`, `waiting_room`, `faction_selection`, **HUD arène `main.tscn`** (reteinte des StyleBox PARTAGÉS → bascule globale instantanée de tous les widgets, méthode §8.36), `split_screen_vs`, `territory_badge`/`board.gd` (PALETTE 6 couleurs refroidie, neutre gunmetal), `intro_video` (barre de chargement cyan). Cendres d'ambiance auth/lobby refroidies. **Couleurs de FACTION** (identité joueur) **conservées distinctes**. **Logo `logo_ww.png` recolorisé** (script Pillow, validé en moteur) : recolor **SÉLECTIF** orange→cyan **conservant le métal d'origine** — seul l'orange vif (lueur, monogramme WWW, texte « WASTELAND WARFARE / DOOMSDAY RISK ») passe en cyan, le métal acier patiné reste naturel (rendu réaliste, pas un duotone mono). 3 emblèmes alternatifs explorés via **ComfyUI/FLUX.1 dev** (`:8188`, `generate_ww.ps1`) mais non retenus (l'original recoloré garde le texte complet + le détail des armes). ⚠️ Restent *legacy* orange : **fonds raster** `bg_wasteland.png`/`intro.jpeg` (recolor d'asset à part) ; `splash_screen` non stylé. *(NB : le cache d'import `.godot/imported/*.ctex` ne se régénère PAS via `filesystem_manage reimport` du MCP — il a fallu un `Godot_v4.6.3 --headless --path frontend --import` en CLI pour que la texture recolorisée soit prise en compte.)* (aucun widget ; script non rattaché + `$ProgressBar` absent — bug préexistant hors périmètre). La charte canonique est dans **§2** ; les anciens §2.1/§2.2 (auth/lobby orange) sont marqués **LEGACY**.

**B1. Inspecteur Tactique de Territoire (`main.tscn` + `hud.gd` + `main.gd` + `board.gd`).** Panneau readout flottant **bas-droite** (`%TerritoryInspector`, `StyleBoxFlat_intel` cyan, masqué), ouvert au **clic d'un territoire** : nom (cyan) + eyebrow→valeur PROPRIÉTAIRE (pseudo coloré faction, « NEUTRE » gris si vide) / GARNISON / statut « ☢ CONTAMINÉ » (vert). `hud.set_territory_inspector(data)` & `hide_territory_inspector()` (fondu Tween). `main._push_inspector(tid)` résout les données (View pure). Fermeture : **clic dans le vide** (nouveau signal **`board.board_cleared`**, émis par `board._unhandled_input` avec garde **même-frame** contre le picking Area2D ; nouveau helper public **`board.is_contaminated(tid)`**) ou bouton ✕.

**B2. Tiroir « INTEL : FACTIONS » (`main.tscn` + `hud.gd` + `main.gd`).** 2ᵉ tiroir indépendant **sous** « INTEL : ZONE » (§8.36) : `%IntelFactionsToggleButton` (ghost) + `%IntelFactionsPanel` (`%FactionsList` peuplé par code). Une « player card » par joueur : chevron à la couleur de faction + pseudo, nom de faction coloré, **résumé du pouvoir passif** lu du `.tres`. `hud.set_factions_intel(entries)` + `_toggle_factions_intel()` (fondu). `main._push_factions_intel()` + **généralisation `main._faction_info(fid)`** (cache enrichi nom+description+pouvoir ; `_extract_power` extrait la portion après « Pouvoir : »).

**B3. Refonte Split-Screen VS + Time Bank (`split_screen_vs.tscn`/`.gd` + `main.gd`).** Accents Warzone (VS cyan, dés repli cyan/acier, fond dé gunmetal, croix rouge), **dés agrandis (96) + contour lumineux**. Signature étendue **`start_combat_resolution(..., meta)`** (`meta = {attacker_losses, defender_losses, time_bank_bonus, local_is_attacker}`). En phase résultat : **gros « −N » de dégâts** (punch + envol) par camp + **notification « ⏱ TIME BANK +10s » (or)** qui s'envole — **uniquement à l'attaquant LOCAL** (le serveur n'étend QUE son timer §8.33 ; `time_bank_bonus_seconds` lu de `attack_result`). **MAJ sync timer (§8.33) :** le rebours du HUD applique maintenant la Time Bank — `hud.add_time_to_timer(seconds)` (constante `TURN_TIME_MAX = 90`, accumulateur `_turn_bonus` recalculé dans `update_display` pour SURVIVRE aux refresh), appelée par `main._on_game_event` à réception d'`attack_result` **sur tous les clients**, **avant** `_play_combat_resolution`. Corrige la désync « UI à 00:00 alors que le serveur attend encore » pendant l'animation de combat.

**B4. Rapport Post-Opération — NOUVEAU (`scenes/game/operation_report.tscn` + `scripts/game/operation_report.gd` + `shaders/report_blur.gdshader` + `main.gd`).** Remplace l'ancien overlay victoire minimal. **Flou gaussien** de l'arène gelée (`report_blur.gdshader` : noyau 5×5 sur `hint_screen_texture` + assombrissement gunmetal ; HUD fondu avant via `fade_ui_for_combat`) + grand panneau central angulaire : titre massif « VICTOIRE DE <Pseudo> » (or) / « OPÉRATION TERMINÉE — <Pseudo> L'EMPORTE » (rouge), sous-section **« RAPPORT D'ATTRITION »** (depuis `GameState.statistics` : `zone_stagnation_turns` + `zone_kills_by_player` triés desc., **médaille dorée « 🥇 PLUS LOURD TRIBUT »**), CTA « START » **« ❮ RETOURNER AU LOBBY »**. `main._show_operation_report()` résout les données ; **`main._on_back_to_lobby()`** nettoie la session (close socket, `NetworkManager.current_room_id=""`) puis `change_scene_to_file("res://scenes/ui/lobby_screen.tscn")` (≠ ancien retour `main_menu`).

**Fichiers (`frontend/`).** NEUFS : `scenes/game/operation_report.tscn`, `scripts/game/operation_report.gd`, `shaders/report_blur.gdshader`. MODIFIÉS : `scenes/game/main.tscn` (reteinte + nœuds Inspecteur/Intel Factions), `scripts/ui/hud.gd`, `scripts/game/main.gd`, `scripts/game/board.gd`, `scenes/game/split_screen_vs.tscn`/`.gd`, `scenes/game/territory_badge.tscn` & `scripts/game/territory_badge.gd`, reskin `scenes/ui/{auth_screen,main_menu,lobby_screen,waiting_room,intro_video}.tscn` & `scenes/faction_selection/faction_selection.tscn` (+ `.gd` pour les styles construits en code : `lobby_screen.gd`, `waiting_room.gd`, `faction_selection.gd`). Charte : `FRONTEND_INTERFACES.md` §2, `CONTEXTE.md`.

**Validation.** Boot runtime **0 erreur** : `auth_screen`, `lobby_screen`, `main.tscn` (HUD + 2 tiroirs Intel empilés), `split_screen_vs` (compile), `operation_report` (shader compilé). **Screenshots framebuffer 1920×1080** : charte Warzone cohérente (gunmetal/cyan/or, angulaire, condensé) sur auth, HUD arène, lobby, rapport. ⚠️ **Vérif visuelle complète en partie réelle requise** pour : Inspecteur (clic territoire), combat VS + Time Bank (combat multi-joueurs), rapport peuplé (fin de partie déployée). Avertissements `SHADOWED_VARIABLE` **préexistants** (`auth_manager.gd`) hors périmètre.

### 8.38. Polish ADN « Warzone Command » des écrans de menu + recoloration du fond + helper partagé (Frontend)
> Finition de la bascule §8.37 sur les écrans de menu : ajout des ornements **structurels** de l'ADN Warzone (§2) encore absents (encoches de coin, chevrons, filets, rythme eyebrow→valeur), **recoloration du fond raster legacy** `bg_wasteland.png` (résidu orange explicitement laissé en suspens par §8.37) et **mutualisation** du code d'ornement dans un helper partagé. **Frontend exclusif** (actif au relancement du client). **AUCUN COMMIT** (directive utilisateur). Validé via **Godot 4.7 headless** (boot runtime 0 erreur sur les 4 écrans).

**A. `main_menu` — détails ADN angulaires (`main_menu.tscn` + `main_menu.gd`).**
- **Rythme eyebrow → valeur** : la TopBar passe de labels plats à des paires `JOUEUR` (eyebrow cyan 13 px) / pseudo (valeur 24 px) et `NIVEAU` (eyebrow) / numéro (valeur or). `main_menu.gd` ne pousse plus que la VALEUR (`username.to_upper()`, niveau brut) — l'intitulé statique vit dans la scène.
- **Chevrons `❯`** : les 4 boutons préfixés `❯  …` + alignés à gauche (`alignment = 0`) → style « liste de commandement » Warzone.
- **Filet cyan** : `HSeparator` + `StyleBoxLine` cyan (α 0.5, 2 px) entre la TopBar et les boutons.
- **Encoches de coin** : 2 triangles cyan (haut-gauche / bas-droite) sur le panneau central (helper §D).
- Messages d'état alignés sur le readout Warzone (préfixe `// `, MAJUSCULES).

**B. Recoloration `bg_wasteland.png` (orange legacy → gunmetal/cyan).**
- Le fond raster (2760×1504), dont la dominante **ambre/orange** jurait avec la charte froide, est recoloré par **rotation de teinte HSV** (`h += 0.45` ≈ +162° : orange → cyan) + **désaturation** (`s ×= 0.72`) + **assombrissement** (`v ×= 0.85`). Le ciel orange devient un teal gunmetal, les champignons atomiques une énergie cyan « toxique », le terrain un gris-teal froid — détail de la scène **préservé** (pas un duotone, cf. recolor du logo §8.37).
- **Outil** : pas de Python/Pillow sur la machine → script **Godot** `extends SceneTree` lancé en `--script` **sans `--path`** (donc sans autoload), via `Image.load_from_file()` / `Image.save_png()` (chemins OS absolus). Asset écrasé en place (UID conservé) puis **réimporté** (`--import` régénère le `.ctex`). L'original reste dans l'historique git.
- **Portée** : `bg_wasteland.png` est le fond **partagé** de `main_menu`, `waiting_room` ET `faction_selection` → un seul asset refroidit les trois écrans. (`lobby_screen` utilise un `GradientTexture2D` froid, déjà conforme.) **Résout** le résidu legacy noté en §8.37. Reste *legacy* : `intro.jpeg` (autre raster, non traité — cf. Feuille de route R6).

**C. Polish ADN sur `lobby_screen`, `waiting_room`, `faction_selection`.**
- **Encoches de coin** : sur les panneaux principaux (lobby : panneau de commande + radar ; waiting_room : panneau central ; faction_selection : panneau principal), câblées par `@export var panel`/`command_panel`/`browser_panel`.
- **Chevrons `❯`** : sur les boutons d'action (lobby : `CRÉER` / `OPÉRATION PRIVÉE` / `INFILTRER` / `ACTUALISER` / `DÉCONNEXION` + lignes « REJOINDRE » dynamiques de `_build_room_row` ; waiting_room : `PRÊT` / `DÉSERTER`, **y compris** le libellé de bascule de `_on_ready_pressed` ; faction_selection : `CONFIRMER LA FACTION`).
- **Filets cyan** : ajoutés à `waiting_room` (sous le sous-titre) et `faction_selection` (entre le carrousel et le CTA). `lobby_screen` en avait déjà un (`Divider`).

**D. Helper partagé `scripts/ui/warzone_ui.gd` (NOUVEAU, anti-duplication).**
- Au lieu de dupliquer le code d'encoches dans 4 scripts, un helper `extends RefCounted` expose `static func add_corner_notches(panel, notch_size, color)` : crée 2 `Polygon2D` triangulaires cyan enfants du panneau (un Node2D est ignoré par le layout du Container mais dessiné par-dessus le fond) et les repositionne à chaque `resized` (un panneau dimensionné par un conteneur n'a sa taille réelle qu'après la passe de layout). **Idempotent** (méta `ww_notched`). **Chargé par `preload`** (PAS via `class_name`) côté écrans → robuste au cache d'import (même prudence que `faction_selection.gd`/`board.gd`). `main_menu.gd` a été **refactoré** pour l'utiliser → implémentation d'encoches **unique**.

**Fichiers (`frontend/`).** NEUF : `scripts/ui/warzone_ui.gd`. MODIFIÉS : `assets/images/bg_wasteland.png` (recoloré), `scenes/ui/main_menu.tscn`/`.gd`, `scenes/ui/waiting_room.tscn`/`.gd`, `scenes/ui/lobby_screen.tscn`/`.gd`, `scenes/faction_selection/faction_selection.tscn`/`.gd`. **Backend inchangé.**

**Validation (Godot 4.7-stable headless).** `--import` propre, puis **boot runtime `--quit-after` = 0 erreur** sur `main_menu`, `waiting_room`, `lobby_screen`, `faction_selection` (helper preloadé résolu ; encoches/chevrons/filets/exports `panel` OK). Rendu du fond recoloré vérifié hors-ligne. ⚠️ **Aucun commit** (directive utilisateur : la working tree reste telle quelle, à la main de l'utilisateur).

### 8.39. Boutique & Inventaire (R1) — écran neuf en charte « Warzone Command » (Frontend)
> Réalisation de l'item **R1** de la feuille de route : le bouton `main_menu` « ❯ BOUTIQUE & INVENTAIRE » n'est plus un STUB mais ouvre un **écran neuf** `scenes/ui/shop.tscn`. **Frontend exclusif** (actif au relancement du client). **L'économie serveur n'est pas encore spécifiée** (monnaie, catalogue, endpoints achat/inventaire — cf. R1 « À définir (backend) » + `CONTRAT_RESEAU.md`) : l'écran est donc une **PRÉVISUALISATION fonctionnelle** (catalogue mock + inventaire local simulé). **AUCUN COMMIT** (directive utilisateur).

- **Fichiers.** NEUFS : `scenes/ui/shop.tscn` + `scripts/ui/shop.gd`. MODIFIÉS : `scripts/ui/main_menu.gd` (`_on_inventory_pressed` → `change_scene_to_file("res://scenes/ui/shop.tscn")`, fin du STUB), `scripts/ui/warzone_ui.gd` (helper §D ci-dessous). **Backend inchangé.**
- **Structure (`shop.tscn`).** Fond partagé `bg_wasteland.png` (déjà refroidi §8.38) → `CenterContainer` → `MainPanel` (`PanelContainer` gunmetal, bordure cyan, encoches d'angle). En-tête au rythme **eyebrow→valeur** : `DÉPÔT TACTIQUE / BOUTIQUE & INVENTAIRE` à gauche, `CRÉDITS / <solde>` **en or** à droite, bouton `❮ RETOUR` (ghost). Deux **onglets** (`❯ BOUTIQUE` / `❯ INVENTAIRE`) basculant la visibilité de deux `GridContainer` (3 colonnes) dans un `ScrollContainer`. Filets cyan haut/bas, `StatusLabel` readout (`// …`).
- **Cartes générées par code (Règle d'Or §6.1, VUE pure).** `_build_shop_card` / `_build_inventory_card` : surface `#1a2028` + liseré cyan gauche + encoches ; ligne haute = catégorie (eyebrow) + **badge hexagonal** (prix en **or** côté boutique, quantité en **cyan** côté inventaire) ; nom (valeur MAJ), description (texte muet, `autowrap`), CTA `❯ ACQUÉRIR` (boutique) ou statut `EN DÉPÔT` (inventaire). Styles construits en code (cohérent avec `lobby_screen._build_room_row`).
- **Données & économie (mock).** Catalogue `_CATALOG` (6 articles post-apo : renforts, bonus tactiques, cosmétiques), solde `_credits` (2500 par défaut, **lu défensivement** du profil si le backend expose un jour un champ `credits`/`solde`/`monnaie`/`currency`), inventaire `_owned` (id→quantité). **Achat SIMULÉ côté client** : débit du solde + ajout à l'inventaire + statut « (APERÇU LOCAL) » (ou « CRÉDITS INSUFFISANTS »). Quand les endpoints existeront, **seul le peuplement changera** (même découplage Vue/réseau que le lobby). IDs `snake_case` prêts pour le futur réseau.
- **Helper partagé étendu (`warzone_ui.gd`).** NOUVEAU `static func make_hex_badge(text, font, font_size, fill, text_color, diameter)` → `Control` à taille fixe contenant un `Polygon2D` **hexagonal** (pointe en haut) surmonté d'un `Label` centré (`mouse_filter = IGNORE`). Mutualise les **badges hexagonaux** de l'ADN Warzone (§2), réutilisable par R2 (profil) / R3 (podium classement). Constantes de charte exposées (`ACCENT`/`GOLD`/`GUNMETAL`).
- **Validation (Godot 4.7-stable headless).** `--import` propre (0 Parse/SCRIPT ERROR), puis **boot runtime de `shop.tscn` `--quit-after 30` = 0 erreur / 0 warning** (exit 0). ⚠️ Rendu visuel en jeu réel non capturé (headless sans rendu) ; structure et logique validées. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.40. Profil utilisateur (R2) — écran neuf en charte « Warzone Command » (Frontend)
> Réalisation de l'item **R2** de la feuille de route : le bouton `main_menu` « ❯ MON PROFIL » n'est plus un STUB mais ouvre un **écran neuf** `scenes/ui/profile.tscn`. **Frontend exclusif** (actif au relancement du client). **L'endpoint de statistiques joueur n'est pas encore spécifié** (le backend n'expose que `/auth/me` : username, niveau, id, email — cf. R2 « À définir (backend) » + `CONTRAT_RESEAU.md`) : l'écran est donc une **PRÉVISUALISATION fonctionnelle** (valeurs réelles lues défensivement du profil, sinon valeurs mock). **AUCUN COMMIT** (directive utilisateur).

- **Fichiers.** NEUFS : `scenes/ui/profile.tscn` + `scripts/ui/profile.gd`. MODIFIÉS : `scripts/ui/main_menu.gd` (`_on_profile_pressed` → `change_scene_to_file("res://scenes/ui/profile.tscn")`, fin du STUB). **Backend inchangé.**
- **Structure (`profile.tscn`).** Fond partagé `bg_wasteland.png` → `CenterContainer` → `MainPanel` (`PanelContainer` gunmetal, bordure cyan, encoches d'angle). En-tête eyebrow→valeur : `DOSSIER JOUEUR / MON PROFIL`, bouton `❮ RETOUR` (ghost). **Barre d'identité** : `JOUEUR / <pseudo>` à gauche, `FACTION DE PRÉDILECTION / ❯ <faction>` à droite (le **chevron** prend la **couleur d'accent de la faction**). **Niveau & XP** : `NIVEAU <n>` + libellé `<xp>/<xp_max> XP` + `ProgressBar` cyan angulaire. Filets cyan, `StatusLabel` readout (`// …`).
- **Cartes readout générées par code (Règle d'Or §6.1, VUE pure).** `_make_stat_card(label, value, color)` : surface `#1a2028` + liseré cyan gauche + encoches ; eyebrow (libellé) + **valeur en gros** colorée sémantiquement (PARTIES JOUÉES = blanc, VICTOIRES = **or**, DÉFAITES = **rouge**, RATIO V/D = **cyan**, PLUS LOURD TRIBUT = acier). Grille 5 colonnes. **Historique** (`DERNIERS ENGAGEMENTS`) : lignes générées (`_make_history_row`) — chevron + résultat (VICTOIRE en or / DÉFAITE en rouge), faction utilisée, détail muet aligné à droite, dans un `ScrollContainer`.
- **Données & statistiques (mock).** Stats (`_games_played`, `_wins`, `_losses`, `_heaviest_toll`), niveau/XP et `_favorite_faction_id` **lus défensivement** du profil (`_read_int` sur plusieurs clés candidates FR/EN ; `int(...)` systématique → piège float JSON §5) ; sinon **valeurs mock**. Ratio V/D calculé côté client. La faction favorite est résolue (id→nom + `accent_color`) via le **chargement data-driven des `.tres`** (scan `DirAccess` export-safe + `FALLBACK_PATHS` + duck-typing — mêmes garde-fous que `faction_selection.gd`). Quand l'endpoint statistiques existera, **seul le peuplement changera** (découplage Vue/réseau).
- **Validation (Godot 4.7-stable headless).** `--import` propre (0 Parse/SCRIPT ERROR), puis **boot runtime de `profile.tscn` `--quit-after` = 0 erreur / 0 warning** (exit 0). ⚠️ Rendu visuel en jeu réel non capturé (headless sans rendu) ; structure et logique validées. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.41. Classement mondial (R3) — écran neuf en charte « Warzone Command » (Frontend)
> Réalisation de l'item **R3** de la feuille de route : le menu principal annonçait un « Classement mondial » sans écran ni bouton d'accès (§3). C'est désormais un **écran neuf** `scenes/ui/leaderboard.tscn`, ouvert par un **nouveau bouton** `main_menu` « ❯ CLASSEMENT MONDIAL ». **Frontend exclusif** (actif au relancement du client). **Aucun endpoint de classement n'est encore spécifié** (tri serveur, pagination — cf. R3 « À définir (backend) » + `CONTRAT_RESEAU.md`) : l'écran est donc une **PRÉVISUALISATION fonctionnelle** (classement mock + joueur local inséré/surligné, valeurs réelles lues défensivement de `/auth/me`). **AUCUN COMMIT** (directive utilisateur).

- **Fichiers.** NEUFS : `scenes/ui/leaderboard.tscn` + `scripts/ui/leaderboard.gd`. MODIFIÉS : `scenes/ui/main_menu.tscn` + `scripts/ui/main_menu.gd` (nouveau bouton `LeaderboardButton` entre « MON PROFIL » et « QUITTER », `@export var leaderboard_button` + `_on_leaderboard_pressed` → `change_scene_to_file("res://scenes/ui/leaderboard.tscn")`). **Backend inchangé.**
- **Structure (`leaderboard.tscn`).** Fond partagé `bg_wasteland.png` (refroidi §8.38) → `CenterContainer` → `MainPanel` (`PanelContainer` gunmetal, bordure cyan, encoches d'angle). En-tête eyebrow→valeur : `RÉSEAU MONDIAL / CLASSEMENT MONDIAL`, bouton `❮ RETOUR` (ghost). **Podium top 3** (`PodiumBox` HBox) + en-tête de colonnes **fixe** (`ColumnsHeader`, hors scroll → reste aligné) RANG / JOUEUR / NIVEAU / VICTOIRES + **liste défilante** (`RankingScroll` → `RankingBox`). Filets cyan haut/bas, `StatusLabel` readout (`// …`).
- **Podium & lignes générés en code (Règle d'Or §6.1, VUE pure).** `_make_podium_card` : carte par rang 1-3, **#1 en or** (bordure or, badge plus grand, carte plus haute), #2/#3 en cyan ; le rang est un **badge hexagonal** réutilisant `WarzoneUI.make_hex_badge` (§8.39), victoires en **or**. `_make_ranking_row` : chevron + rang (or pour le top 3), pseudo, niveau, victoires (or) ; **largeurs de colonnes partagées** (constantes `COL_RANK/COL_LEVEL/COL_WINS`) entre l'en-tête fixe et les lignes → alignement garanti. **Ligne du joueur LOCAL surlignée** : fond cyan léger + liseré gauche épaissi (5 px), pseudo en cyan + suffixe « (VOUS) ».
- **Données & classement (mock).** `_mock_board` (12 joueurs fictifs, déjà triés desc. par victoires). L'**joueur local** (`AuthManager.username` ; niveau/victoires **lus défensivement** de `/auth/me` via `_read_int` sur clés FR/EN, `int(...)` pour le piège float JSON §5, sinon valeurs mock) est **fusionné** dans la liste (mis à jour s'il y figure déjà sous le même pseudo, sinon ajouté), l'ensemble est **re-trié** (victoires desc., départage niveau) et les **rangs réattribués** côté client. Quand l'endpoint classement existera, **seul le peuplement changera** (même découplage Vue/réseau que lobby / shop / profile).
- **Validation (Godot 4.7-stable headless).** `--import` propre (0 Parse/SCRIPT ERROR), puis **boot runtime de `leaderboard.tscn` ET `main_menu.tscn` `--quit-after` = 0 erreur / 0 warning** (exit 0, bouton + navigation câblés). ⚠️ Rendu visuel en jeu réel non capturé (headless sans rendu) ; structure et logique validées. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.42. Chat de salle CÂBLÉ au réseau + retrait de l'onglet « Alliés » (Frontend)
> Consommation côté client du **Chat de salle** déjà livré et déployé par le backend ([`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) §8.33). L'UI de chat (onglets-icônes §8.29) existait mais **n'envoyait/recevait rien** (placeholder « En attente du réseau… »). Désormais elle est **branchée aux WebSockets** : envoi via `send_chat_message` (forme à plat du contrat), réception via le message `chat_message`. Conformément au contrat, le jeu étant **chacun-pour-soi**, l'onglet **« Alliés » 🤝 est SUPPRIMÉ** → **2 canaux** : Général / Privé. **Frontend exclusif** (actif au relancement du client ; le backend était déjà en place). **AUCUN COMMIT** (directive utilisateur).

- **Fichiers.** MODIFIÉS : `scripts/managers/network_manager.gd`, `scripts/ui/hud.gd`, `scripts/game/main.gd`, `scenes/game/main.tscn`. **Backend inchangé** (contrat §8.33 déjà déployé).
- **Réseau (`network_manager.gd`).** Nouveau signal **`chat_message_received(tab, sender_id, sender_name, text, target_id)`** ; nouveau case **`"chat_message"`** dans `_handle_server_message` (ids JSON coercés `int()`, piège §5) ; nouvelle méthode **`send_chat_message(tab, text, target_id=-1)`** qui émet la **forme à plat** du contrat `{"type":"send_chat_message","tab","text","target_id"}` (`tab` ∈ `{"general","private"}`, `target_id` joint **uniquement en privé**). On **n'affiche jamais nos propres messages localement** : le serveur renvoie un **écho** (§8.33) qui les affichera.
- **Vue (`hud.gd`, Règle d'Or §6.1).** `CHAT_INDEX` réduit à `{"general":0,"prive":1}` ; `_setup_chat_tabs`/`_select_chat` purgés du canal « allies ». Nouveau signal **`chat_send_requested(channel, text, target_id)`**. **Zone de saisie construite PAR CODE** (`_build_chat_input`, même pattern que « CONFIRMER LE DÉPLOIEMENT ») insérée dans `SideVBox` sous `%ChatTabs` : `LineEdit` (placeholder selon canal, `max_length = CHAT_MAX_LENGTH = 500` aligné serveur) + **`OptionButton` de destinataire** (visible **uniquement** en canal Privé) + bouton d'envoi `➤`. `_on_chat_submit` valide (texte non vide, destinataire requis en privé) et émet le signal ; **`set_chat_targets(entries)`** peuple le sélecteur (conserve la sélection courante). Le HUD ne touche jamais au réseau.
- **Contrôleur (`main.gd`).** Branche `NetworkManager.chat_message_received → _on_chat_message` et `hud.chat_send_requested → _on_chat_send`. **Traduction de canal** HUD↔contrat (`"prive"`↔`"private"`). **`_on_chat_message`** colore le pseudo à la **couleur de faction** de l'expéditeur (`board.get_player_color`) et **ÉCHAPPE le texte ET le pseudo** (`replace("[","[lb]")`) → **anti-injection BBCode** (un message d'un autre joueur ne peut pas interpréter de balises) ; en privé, l'**écho** de nos propres messages (`sender_id == _my_id()`) affiche le **destinataire** (`→ pseudo`) plutôt que l'expéditeur. **`_push_chat_targets`** (appelé dans `_refresh`) pousse les **autres** joueurs (id + pseudo résolu) au sélecteur privé.
- **Scène (`main.tscn`).** Suppression du bouton **`TabBtnAllies`** (`ChatIconBar`) et de la page **`ALLIÉS`** (`ChatTabs`) ; `metadata/_tab_index` de `PRIVÉ` passé **2 → 1**. Le `ButtonGroup_chat` reste référencé par les 2 boutons restants.
- **Périmètre — DÉCISION PRODUIT : chat UNIQUEMENT dans l'arène.** L'UI de chat n'existe **que dans l'arène** (`main.tscn`) ; **aucun chat en lobby / `waiting_room`** (choix délibéré, **pas une limitation à lever**). Le serveur accepte techniquement le chat indépendamment du `stage` ([`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) §8.33), mais le client **n'expose volontairement aucune UI de chat hors arène** → cette capacité « lobby » reste inutilisée par design. La **Time Bank cosmétique** (§8.33, autre volet frontend) reste limitée à l'étiquette « ⏱ TIME BANK +10 s » du Split-Screen VS (le rebours HUD ne s'étend pas) — non traitée ici.
- **Validation (Godot 4.7-stable headless).** `--import` propre (0 Parse/SCRIPT ERROR) ; **boot runtime de `main.tscn` `--quit-after 30` = 0 erreur** (HUD `_ready` : construction de la zone de saisie + connexions de signaux OK). ⚠️ Échange réseau réel non testable en headless (pas de salle/serveur) ; structure et logique validées. ⚠️ **Aucun commit**.

### 8.43. Écran Options / Paramètres (R5) — écran neuf en charte « Warzone Command » (Frontend)
> Réalisation de l'item **R5** de la feuille de route : nouvel **écran neuf** `scenes/ui/settings.tscn`, ouvert par un **nouveau bouton** `main_menu` « ❯ PARAMÈTRES » (entre « CLASSEMENT MONDIAL » et « QUITTER »). Regroupe **volume (Master / Musique / SFX)**, **affichage (plein écran ⇆ fenêtré + résolution)** et **langue** (réutilise le sélecteur R4). Toute la logique de réglage vit dans un **nouvel autoload `SettingsManager`** (jumeau de `LocaleManager`), l'écran reste une **Vue pure** (Règle d'Or §6.1). **Frontend exclusif** (actif au relancement du client). **AUCUN COMMIT** (directive utilisateur).

- **Fichiers.** NEUFS : `scenes/ui/settings.tscn` + `scripts/ui/settings.gd`, `scripts/managers/settings_manager.gd` (autoload), `default_bus_layout.tres` (disposition de bus audio). MODIFIÉS : `project.godot` (autoload `SettingsManager`), `scripts/ui/main_menu.tscn` + `scripts/ui/main_menu.gd` (bouton `SettingsButton` + `@export var settings_button` + `_on_settings_pressed`), `translations/ui_strings.csv` (+15 clés `MENU_SETTINGS` / `SETTINGS_*`, régénère les 3 `.translation`). **Backend inchangé.**
- **Manager (`settings_manager.gd`, Règle d'Or §6.1).** Autoload **jumeau de `LocaleManager`** : `_ready()` **charge** les réglages (`user://settings.cfg`, le **MÊME fichier** que la langue) puis les **applique au moteur** AVANT le premier écran. **Audio** : `set_volume(bus, v)` → `AudioServer.set_bus_volume_db(linear_to_db(v))` (mute si v≈0) sur les bus `Master`/`Music`/`SFX` ; **lecture défensive** `get_bus_index == -1` → ignore proprement (jamais d'« Invalid bus »). **Affichage** : `set_fullscreen(bool)` (plein écran borderless ⇆ fenêtré bordé) + `set_resolution_index(i)` (4 résolutions 16:9, appliquée+recentrée en fenêtré) ; **garde headless** `DisplayServer.get_name() == "headless"` → n'applique rien en validation CLI. Chaque setter **persiste** (`_save` préserve la section `[locale]`) et émet un signal. La langue reste 100 % à `LocaleManager`.
- **Disposition audio (`default_bus_layout.tres`).** NOUVEAU layout `Master` + `Music` + `SFX` (les 2 derniers routés vers Master) — chargé automatiquement par Godot (chemin par défaut `res://default_bus_layout.tres`). Rend les 3 sliders **signifiants** dès maintenant ; **prêt pour R6** (toute source audio future n'aura qu'à viser le bus `Music` ou `SFX`). Aucune source audio n'existe encore (R6).
- **Vue (`settings.tscn` + `settings.gd`).** Fond partagé `bg_wasteland.png` → `CenterContainer` → `MainPanel` (gunmetal, bordure cyan, encoches d'angle). En-tête eyebrow→valeur `CONFIGURATION TACTIQUE / PARAMÈTRES`, bouton `❮ RETOUR` (ghost). 3 sections séparées par filets cyan : **AUDIO** (3 lignes intitulé + `HSlider` + valeur `%`), **AFFICHAGE** (segments `PLEIN ÉCRAN`/`FENÊTRÉ` + segments de résolution numériques), **LANGUE** (sélecteur mutualisé `WarzoneUI.build_language_selector`). **Sliders restylés en code** (`_style_slider` : piste gunmetal + liseré cyan, portion remplie cyan, **poignée = carré cyan plein** généré via `Image`/`ImageTexture` → ADN angulaire §2) ; **segments** (`_style_segment`) actif = rempli cyan / inactif = ghost acier (même langage que le sélecteur de langue). Les intitulés statiques vivent en **clés de traduction** dans la `.tscn` (re-traduits par Godot au changement de langue) ; le code ne génère que du numérique (`%`, `L × H`, `auto_translate` désactivé). Application **live** + auto-sauvegarde (pas de bouton « Appliquer »), cohérent avec le sélecteur de langue.
- **Validation (Godot 4.7-stable headless).** `--import` propre (0 Parse/SCRIPT ERROR, `.translation` régénérées du CSV — horodatage postérieur vérifié), puis **boot runtime de `settings.tscn` ET `main_menu.tscn` `--quit-after 40` = 0 erreur** (autoload `SettingsManager` instancié, sliders/segments/sélecteur câblés, bouton + navigation OK). ⚠️ Rendu visuel en jeu réel non capturé (headless sans rendu) ; structure et logique validées. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.44. Nouvelle ouverture spectaculaire (Splash Eroïque) + fondations R6 + purge des scènes legacy (Frontend)
> Refonte de la **chaîne de lancement** pour un effet d'ouverture « AAA » + premières **fondations R6** (transitions, audio, mutualisation) + **suppression des scènes/assets hors-charte orphelins**. Direction d'ouverture **option C** (« Splash Eroïque animé », choisie par l'utilisateur). **Frontend exclusif** (actif au relancement du client). **AUCUN COMMIT** (directive utilisateur). Validé en **Godot 4.7-stable headless** (boot 0 erreur) **+ capture framebuffer réelle** (éditeur MCP 4.7 attaché).

- **A. Purge legacy (scènes/scripts/assets ne respectant pas la charte §2, orphelins confirmés par recherche d'`uid`).** Supprimés : `scenes/ui/hud.tscn` (orphelin — le HUD vit dans `main.tscn` depuis §8.17), `scripts/ui/menu.gd` (+`.uid`, vieux auth/menu remplacé par `auth_screen.gd`/`main_menu.gd`), `assets/images/intro.jpeg` (+`.import`, `uid` non référencé), `move_files.ps1` (script de migration une-tantum, référençait le splash déjà retiré), **`scenes/ui/intro_video.tscn` + `scripts/ui/intro_video.gd`** (+`.uid`, lecteur vidéo spartiate, remplacé par le Splash). *(L'asset brut `assets/video/video_intro.ogv` est CONSERVÉ sur disque mais désormais inutilisé.)*
- **B. Splash Eroïque (`scenes/ui/title_splash.tscn` + `scripts/ui/title_splash.gd` + `shaders/title_hexgrid.gdshader`).** Scène **one-shot** lancée par le bootloader (le version-check a déjà eu lieu → **Vue pure**, aucun réseau, Règle d'Or §6.1). 100 % **code + shader** (aucun nouvel asset raster) : fond **hex-grid gunmetal/cyan ravivé par un balayage RADAR** (`title_hexgrid`, canvas_item, `SCREEN_UV`/`SCREEN_PIXEL_SIZE`, vignette radiale), **cendres cyan** (`GPUParticles2D` + texture « point doux » générée en `Image`), **reveal du logo** `logo_ww.png` (fondu + dézoom élastique `TRANS_BACK`, pivot centré) **flanqué de 2 chevrons** qui glissent, **balayage lumineux** descendant, **ligne de statut tactique dactylographiée** (`tween_method`, clé i18n `SPLASH_STATUS`) puis **invite clignotante** (`SPLASH_PRESS_KEY`). Enchaînement : **toute entrée** (après garde 0,35 s) **ou** auto-avance 9 s → `auth_screen` via fondu. Tous les timings sont des **Tweens/Timers liés à la scène** (auto-tués à la libération → aucun callback tardif).
- **C. `TransitionManager` (NOUVEL autoload `scripts/managers/transition_manager.gd`).** `extends CanvasLayer` (layer 128, survit au changement de scène) : `change_scene(path)` = fondu **gunmetal** sortant → `change_scene_to_file` → fondu entrant (garde anti-spam + blocage des clics pendant la bascule) ; `fade_in_only()` pour un dévoilé d'ouverture. Remplace les `change_scene_to_file` « secs » (R6 transitions). **Câblé** : `bootloader._go_to_next_scene`, `title_splash._advance`, et les **6 navigations de `main_menu`** (helper `_go`).
- **D. `AudioManager` (NOUVEL autoload `scripts/managers/audio_manager.gd`) — SFX/ambiance PLACEHOLDER procéduraux.** Aucun fichier audio : les sons sont **synthétisés** au démarrage (`AudioStreamWAV` PCM 16 bits → `PackedByteArray.encode_s16`) sur les bus `SFX`/`Music` du `default_bus_layout.tres` (§8.43, volumes déjà pilotés par `SettingsManager`). Banque : `hover`/`click`/`confirm`/`back` (bips & balayages) + `sting` (reveal du logo) + `start_menu_ambient()` (nappe grave bouclée). **Garde headless** (`DisplayServer.get_name() == "headless"`) qui **désactive la LECTURE** en validation CLI (la **synthèse** reste exécutée/validée) → évite des fuites `AudioStreamWAV`/`AudioStreamPlaybackWAV` du pilote audio « Dummy » au force-quit. `_exit_tree()` libère les ressources. **Câblé** : `title_splash` (sting/confirm) + `main_menu` (ambiance + survol/clic sur les 6 boutons).
- **E. Reskin charte du bootloader (`bootloader.tscn`).** L'écran de boot était resté en **legacy « Modern Warfare » kaki/anthracite** (jamais migré en §8.37). Reteint « Warzone Command » §2 : panneau **gunmetal** + liseré **cyan** (3 px à gauche), `corner_radius 0`, boutons **ghost** cyan, `ProgressBar` cyan, police **condensée** (SystemFont Bahnschrift→…), texte blanc froid. Le fond `bg_wasteland.png` (déjà refroidi §8.38) et la logique d'updater (§9) sont **inchangés**. `bootloader.gd` : `next_scene_path` par défaut **`intro_video` → `title_splash`**.
- **F. Helper partagé étendu (`warzone_ui.gd`, R6 mutualisation).** NOUVEAUX `static func apply_ghost_button(btn)` (style ghost cyan complet : normal/hover/pressed/focus + texte illuminé) et `add_filet(parent, thickness, color)` (filet fin cyan `HSeparator`/`StyleBoxLine`). Réduisent la duplication des styles construits en code.
- **i18n (R4).** +2 clés `SPLASH_STATUS` / `SPLASH_PRESS_KEY` dans `translations/ui_strings.csv` (FR/EN/IT) → 3 `.translation` régénérées au `--import`.
- **Fichiers (`frontend/`).** NEUFS : `scenes/ui/title_splash.tscn`, `scripts/ui/title_splash.gd`, `shaders/title_hexgrid.gdshader`, `scripts/managers/transition_manager.gd`, `scripts/managers/audio_manager.gd`. MODIFIÉS : `project.godot` (autoloads `TransitionManager`+`AudioManager` ; `run/main_scene` inchangé = bootloader), `scenes/ui/bootloader.tscn` (reskin), `scripts/ui/bootloader.gd` (routage), `scripts/ui/main_menu.gd` (audio + transitions), `scripts/ui/warzone_ui.gd` (helpers), `translations/ui_strings.csv`. SUPPRIMÉS : voir **A**. **Backend inchangé.**
- **Validation.** `--import` propre (0 Parse/SCRIPT ERROR) ; **boot runtime `--quit-after` = 0 erreur / 0 fuite** sur `title_splash`, `bootloader`, `main_menu`, `auth_screen`. **Capture framebuffer réelle 1920×1080** (projet lancé via MCP) : hex-grid + radar, logo révélé entre chevrons, « // RETE TATTICA — ONLINE » (locale IT), invite, cendres cyan — charte §2 cohérente ; transition splash→auth vérifiée (auth en charte). ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.45. Centrage du logo sur l'écran d'authentification (Frontend)
> Correctif cosmétique : le logo de `auth_screen` était calé **à gauche** au-dessus du `LoginPanel` au lieu d'être centré. **Frontend exclusif** (une seule propriété de layout, actif au relancement du client). **AUCUN COMMIT** (directive utilisateur).

- **Cause (piège Container).** `Logo` (`TextureRect`, largeur 300 px) et `LoginPanel` (`PanelContainer`, ~424 px) sont **frères** dans le `VBoxContainer` `LeftColumn` — le logo n'est **pas** un enfant du panneau. Un `Container` **impose** le placement de ses enfants via leurs **size flags** (position/ancres manuelles ignorées) → impossible de recentrer le logo en le glissant dans l'éditeur (« bloqué par le parent »). Il était en `size_flags_horizontal = 0` (**Shrink Begin** = aligné à gauche).
- **Correctif.** `LeftColumn/Logo.size_flags_horizontal` : **0 (Shrink Begin) → 4 (Shrink Center)**. Le logo conserve ses 300 px et se centre dans la largeur de la colonne → **centré au-dessus du `LoginPanel`** (qui, lui, remplit toute la largeur). Appliqué en direct via **MCP Godot 4.7** puis scène sauvegardée.
- **Fichiers (`frontend/`).** MODIFIÉ : `scenes/ui/auth_screen.tscn` (1 propriété). **Backend inchangé.**
- **Validation (Godot 4.7-stable headless).** Boot runtime de `auth_screen.tscn` `--quit-after 40` = **0 erreur** (exit 0) ; valeur `size_flags_horizontal = 4` confirmée sur disque. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.48. Jauge XP + Coins (HUD/Menu) & Rapport Post-Op animé (Économie globale, Frontend)
> Pendant frontend du sprint **Économie globale** (Backend [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) **§8.47**) : affichage du **niveau + barre d'XP (cyan) + compteur de Coins (or)** dans le Menu Principal, et **animation de récompenses** dans le Rapport Post-Opération (décompte des Points de Match → remplissage de la barre d'XP → lueur dorée aux paliers de 10 niveaux = 100 Coins). **Frontend exclusif** (actif au relancement du client) ; lecture **défensive** des nouveaux champs serveur (repli tant que le VPS n'est pas redéployé). **AUCUN COMMIT** (directive utilisateur).

- **Composant réutilisable `scripts/ui/xp_coins_bar.gd` (NOUVEAU, `extends PanelContainer`).** Construit **100 % par code** (aucun nœud de scène requis — même pattern que le bouton « CONFIRMER » du HUD) → s'`add_child()` partout. Charte « Warzone Command » §2 : panneau gunmetal à liseré cyan, **badge `LV n`** (cyan `#36C5D9`), **`ProgressBar` d'XP à remplissage cyan** (texte `xp / xp_max` superposé), **compteur de Coins en or `#E0B249`** précédé d'une **icône hexagonale stylisée** (classe interne `CoinIcon`, `_draw()` : hexagone or + liseré cyan + chevron gravé). Deux usages : **`set_profile(level, current_xp, xp_to_next, coins)`** (affichage direct) et **`play_match_result(rewards)`** (coroutine `await` : remplit la barre niveau par niveau depuis l'état d'AVANT le match — rembobiné depuis `rewards` —, pulse de niveau, **lueur « rim-light » dorée** + incrément de Coins à chaque palier de 10). ⚠️ Constantes de courbe (`200×niveau` / `4000`) en **MIROIR du backend** `rewards.py` — `_xp_required_for_level()` à garder synchronisé.
- **Menu Principal (`scripts/ui/main_menu.gd`).** La jauge est montée par code (`_mount_xp_bar`, ancrée haut-gauche, masquée jusqu'au profil) et alimentée dans `_on_profile_loaded` : lecture des **clés canoniques** `player_level` / `current_xp` / `xp_to_next_level` / `coins_balance` avec **repli défensif** sur `niveau` / `experience` (et la courbe locale si `xp_to_next_level` manque) → reste fonctionnelle tant que le VPS n'expose pas encore les nouveaux champs. Piège JSON §5 : `int()` partout. ⚠️ **MAJ §8.58** : la jauge est désormais **CLIQUABLE** (ouvre un **mini-profil flottant** → CTA vers `profile.tscn`) et l'onglet « JOUEUR » a été retiré de la nav — voir §8.58 (cette fois `main_menu.tscn` **EST** modifiée : nœud `ProfileTab` retiré).
- **Rapport Post-Opération (`scripts/game/operation_report.gd`).** `populate()` accepte une clé **`rewards`** (facultative) ; nouveau **`populate_rewards(rewards)`** (idempotent, garde `_rewards_built`) construit en TÊTE du débriefing un bloc **« RÉCOMPENSES DE FIN D'OPÉRATION »** : label **Points de Match** (décompte animé `0 → match_points` via `tween_method`), la **jauge `xp_coins_bar`** (remplissage + lueurs Coins), et une ligne « N NIVEAU(X) GAGNÉ(S) » si `level_up_triggered`. La séquence est temporisée (points PUIS XP).
- **Réseau (`scripts/managers/network_manager.gd`).** Le message `game_over` (jusque-là réduit à un log) expose désormais **`match_rewards`** : nouveau signal **`match_over(winner_id, match_type, rankings, match_rewards)`** + cache **`last_match_rewards`**. Clés `match_rewards` = `str(player_id)` (piège §5) ; valeurs entières.
- **Contrôleur (`scripts/game/main.gd`).** Connecte `match_over` → `_on_match_over` : mémorise les gains et, **si le Rapport Post-Op est déjà affiché** (course : l'état `winner_id` et le `game_over` sont 2 messages distincts), lui **pousse** les récompenses du joueur local via `populate_rewards`. `_show_operation_report` passe `rewards = _local_rewards()` (cache, repli `NetworkManager.last_match_rewards`). Si les gains sont absents, le rapport s'affiche **sans** bloc Récompenses (jamais de blocage du débriefing).
- **Fichiers (`frontend/`).** **NOUVEAU** `scripts/ui/xp_coins_bar.gd`. MODIFIÉ : `scripts/ui/main_menu.gd`, `scripts/game/operation_report.gd`, `scripts/managers/network_manager.gd`, `scripts/game/main.gd`. **Aucune scène `.tscn` modifiée** (tout construit par code). **Backend : cf. §8.47.**
- **Validation (Godot 4.7-stable headless).** `--import` (compile tous les scripts) = **0 erreur** (warnings-as-errors corrigés : `maxi()` au lieu du `max()` Variant, suppression d'une variable inutilisée). Boot runtime `main_menu.tscn` ET `main.tscn` `--quit-after 40` = **0 erreur** (exit 0). ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.49. Reskin tactique du fond de plateau — shader `tactical_map` (Frontend)
> Le fond de carte `board_bg.png` (mappemonde « Risk » **cartoon multicolore sur fond olive**) était le **dernier élément hors charte** du jeu : il jurait avec le langage « Warzone Command » §2 (gunmetal/cyan) déjà appliqué partout (HUD, hologrammes, badges, menus). On l'aligne **sans retoucher l'asset ni l'arborescence** : un `ShaderMaterial` posé sur le `TextureRect` **existant** `BoardBackground` retraite l'image en **carte de commandement désaturée** au rendu. **Frontend exclusif** (actif au relancement du client) ; **AUCUN COMMIT** (directive utilisateur).

- **Pourquoi un shader plutôt qu'un nouvel asset.** Les 42 territoires (`Area2D`/`CollisionPolygon2D`) sont **calibrés au pixel** sur les **2200×1530** du fond (§8.18) : toucher l'image ou la géométrie risquait de **désaligner** les polygones. Un `material` sur le nœud déjà présent = **zéro nœud ajouté** (arborescence inchangée), **zéro coordonnée modifiée** (mêmes proportions), **entièrement réversible** (retirer le `material` rend l'aspect d'origine). Pas de Pillow requis (cf. CLAUDE.md) : tout est calculé par le GPU.
- **Shader `shaders/tactical_map.gdshader` (`canvas_item`, NEUF).** Pipeline : **luminance + contraste** → **rampe duotone** 4 paliers (gunmetal profond `#0B0F14` → surface `#1A2028` → terres acier → hautes lumières acier-cyan) ; **réinjection d'un soupçon de chrominance d'origine** (`chroma_keep ≈ 0.07`, différenciation « intel » très muette) ; **côtes gravées** par détection de bord sur la luminance (4 voisins via `TEXTURE_PIXEL_SIZE` → creux sombre + **liseré cyan** `#36C5D9`) ; **graticule blueprint** cyan très discret (`grid_alpha ≈ 0.045`). Tout est piloté par **uniformes** (réglable dans l'éditeur) ; l'**alpha de la texture est préservé** (bordure transparente du fond intacte). Matériau accompagnant : `shaders/tactical_map_material.tres`.
- **Câblage (`scenes/game/board.tscn`).** Ajout d'un `ext_resource` Material + `BoardBackground.material = tactical_map_material.tres`. **Aucun autre changement** : `TerritoriesContainer` + 42 territoires, `board.gd`, `main.tscn` (CRT/cendres/caméra), hologrammes/toxique/badges → **tous inchangés**. Le CRT (`crt_board`, §8.30) s'applique toujours **par-dessus** (scanlines/vignette) et se marie au nouveau fond.
- **Validation (Godot 4.7-stable, éditeur live + MCP).** Réimport des 3 fichiers = **0 erreur de compilation shader** (logs éditeur vides). Boot runtime de `main.tscn` (`project_run` custom) = **0 erreur** (logs game propres). **Vérification visuelle** (capture du jeu lancé) : océans gunmetal, terres acier désaturées, côtes + rotes pointillées en cyan, graticule discret, libellés océans en cyan muet — la carte **s'harmonise** désormais avec les panneaux cyan du HUD au lieu de jurer. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.50. Plateau au format 16:9 — prolongement océanique des bandes latérales (Frontend)
> La carte utile (2200×1530 ≈ 1.44) étant moins large qu'un écran 16:9 (≈1.78), la caméra « plein plateau » (`minf`, fit-contain) laissait **deux bandes latérales vides** (fond transparent du SubViewport → noir). À la demande de l'utilisateur, on **prolonge la mer** dans ces bandes pour obtenir une **image unique et uniforme au format 16:9**, **sans rien rogner**. **Aucun asset modifié, aucun territoire déplacé.** Frontend exclusif ; **AUCUN COMMIT**.

- **Principe (zéro retouche d'asset, zéro décalage des territoires).** Le `BoardBackground` est élargi à **2720×1530** (= 16/9 exact) avec la carte utile **recentrée** (offsets `-252 → 2468` ; la zone centrale reste exactement à sa position d'origine `8 → 2208`). Le shader `tactical_map` mappe la texture sur cette **zone centrale** (`pad_frac ≈ 0.0956`) et **prolonge la mer** dans les bandes (clamp du bord, avec **mer de repli** si le bord échantillonné est une terre → jamais de bavure de continent). Le graticule cyan court sur tout le cadre → **continuité parfaite**. Les 42 territoires (et leurs polygones) **ne bougent pas** : la zone centrale leur reste superposée à l'identique.
- **Caméra (`tactical_camera.gd`).** `BOARD_SIZE = (2720, 1530)` (zoom de remplissage) + nouveau `BOARD_CENTER = (1108, 757)` (centre réel du cadre élargi) utilisé par `_fit_full_board` / `reset_view`. Comme `2720/1530 = 16/9`, le fit-contain **remplit exactement** l'écran 16:9 : plus de bande, aucun rognage. `focus_on_combat` (travelling de combat) inchangé.
- **Détails.** `tactical_map.gdshader` : nouveaux uniformes `pad_frac` / `ocean_fallback` / `ocean_sat_max` (par défaut `pad_frac = 0` → comportement d'origine ; valeurs réelles dans `tactical_map_material.tres`). Cendres (`main.tscn`) élargies à la nouvelle largeur (`emission_box_extents.x = 1360`, `AshParticles.position.x = 1108`). CRT (§8.30) inchangé, s'applique par-dessus.
- **Validation (Godot 4.7-stable, éditeur live + MCP).** Réimport = **0 erreur shader/script** (logs éditeur : seuls des warnings GDScript préexistants). Boot `main.tscn` (`project_run` custom) = **0 erreur** (logs game propres). **Vérification visuelle** (capture du jeu) : la mer remplit les anciennes bandes, **image 16:9 unique et uniforme**, carte entière visible (aucune pointe de territoire rognée), territoires alignés. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.51. Mise à l'échelle globale du client — `canvas_items` + base 1920×1080 (Frontend)
> **Cause du bug signalé par l'utilisateur** : en plein écran (`window/size/mode=3` + `borderless`) le mode d'étirement du projet était **`disabled`** (défaut), donc chaque écran se disposait à la **résolution native** du moniteur **sans aucune référence** → carte « trop zoomée » et **HUD (chat…) débordant hors écran**. On corrige par un **content-scaling** : tout le client (menus, HUD, arène) se met désormais à l'échelle à partir d'une **résolution de référence 16:9 unique = 1920×1080**, quelle que soit la taille réelle de la fenêtre. **Frontend exclusif** (réglages `project.godot` uniquement) ; **AUCUN COMMIT**.

- **Changements (`project.godot`, `[display]`).** Trois clés : `window/stretch/mode="canvas_items"`, `window/size/viewport_width=1920`, `window/size/viewport_height=1080`. La **base 1920×1080** = la résolution à laquelle les écrans ont été **dessinés** (tailles de police, offsets, marges) → sur un écran 1080p le rendu est **1:1** (look d'origine retrouvé) et **mis à l'échelle uniformément** ailleurs. ⚠️ La base par défaut (1152×648) faisait au contraire apparaître toute l'UI à dimension fixe ≈ **1.67× trop grande** (panneaux HUD envahissants) — c'était le défaut résiduel à corriger. `window/stretch/aspect` est laissé au défaut **`keep`** (non écrit dans le fichier) → sur l'écran **16:9** cible le rendu remplit **exactement** la fenêtre (aucune bande), et sur un ratio différent l'image se *letterbox* **uniformément** sans jamais déformer l'UI ni rogner le plateau. `window/size/mode=3` + `borderless` **inchangés**.
- **Pourquoi `canvas_items` et pas `viewport`.** `canvas_items` met à l'échelle le **rendu 2D** tout en laissant les `Control` se redisposer via leurs ancres/conteneurs → l'UI reste nette et responsive. Le `MapViewportContainer` (`SubViewportContainer.stretch = true`, §8.17) dimensionne son `SubViewport` sur le cadre logique ; combiné à la caméra fit-contain 16:9 (§8.50), le plateau **remplit** l'écran. **Aucune scène, aucun script, aucune coordonnée modifiés** : réglage de projet **entièrement réversible**.
- **Validation (Godot 4.7-stable, headless + éditeur live MCP).** `--import` headless = **0 erreur** ; boot `main_menu.tscn` et `main.tscn` (`--quit-after`) = **0 ligne `ERROR`**. **Vérification visuelle** (captures du jeu relancé après le changement de base) : **menu** au panneau **correctement proportionné** (logo de nouveau visible au-dessus, sélecteur de langue ancré, fond `bg_wasteland` plein cadre, aucune distorsion ni bande) ; **arène** carte tactique pleine largeur (océans étendus §8.50), HUD (Communications / Intel / inventaire / phase) **compact et ancré aux bords** (plus de débordement). ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.52. Lisibilité « mes territoires vs ceux des autres » — hologramme renforcé + relief (Frontend)
> Demande utilisateur : pouvoir **distinguer d'un coup d'œil** ses propres territoires de ceux des adversaires, et les voir **légèrement en relief**. Jusqu'ici tous les territoires possédés recevaient le **même** Hologramme Tactique (§8.44/Concept A) à l'accent de leur faction — sans relief, distinguer les SIENS demandait de mémoriser sa couleur de faction. On ajoute une **mise en avant du point de vue du joueur LOCAL** sans toucher aux couleurs de faction (préservées à dessein, charte §2). **`board.gd` exclusif** (aucune scène ni shader modifié) ; **AUCUN COMMIT**.
- **Perspective locale (`board.gd`).** Nouvel helper `_local_pid()` = `AuthManager.user_id` (même source que `main._my_id()` / le HUD) ; `generate_board()` calcule `is_mine` par territoire. `board` reste une **Vue** : il ne fait que **refléter** la perspective, aucune logique de jeu (Règle d'Or §6.1). Repli sûr si l'id n'est pas chargé (`-1`) → aucun territoire « à moi ».
- **Levier 1 — hologramme à intensité variable.** `_apply_hologram_material(fill, accent, emphasized)` pousse au shader `neon_hologram` des **paramètres existants** (aucun changement de shader) selon l'appartenance : **MOI** = contour/halo/hachures **vifs** (`neon_width 10`, `glow_strength 0.5`, `neon_boost 2.4`, `hatch_alpha 0.24`) ; **adversaires** = **atténués** (`neon_width 5`, `glow_strength 0.16`, `neon_boost 1.5`, `hatch_alpha 0.09`). La **couleur de faction reste inchangée** (on ne joue que sur l'intensité → identité des factions préservée, cohérente avec le pseudo coloré du HUD).
- **Levier 2 — relief (ombre portée).** Pour MES territoires uniquement : un `Polygon2D` jumeau du remplissage (`_apply_own_relief`), décalé de `OWN_RELIEF_OFFSET (5,8)` px et **dessiné DERRIÈRE** le remplissage (déplacé en 1er enfant de l'`Area2D`), teinte `OWN_RELIEF_COLOR (noir α0.5)` → le territoire paraît **soulevé** au-dessus de la carte. Masqué (`_clear_own_relief`, réutilisable) dès qu'il n'est plus à moi. Le repli statique du remplissage est aussi un peu plus dense pour les miens (`OWN_FALLBACK_ALPHA 0.18` vs `0.10`).
- **Validation (Godot 4.7-stable, headless).** `--import` = **0 erreur de compilation** ; boot `main.tscn` (`--quit-after 40`) = **0 ligne `ERROR`**. Les paramètres poussés correspondent tous à des uniformes **existants** de `neon_hologram.gdshader`. ⚠️ **Aucun commit** (working tree laissée à l'utilisateur).

### 8.53. Économie réelle de la Boutique — catalogue serveur 4 catégories + achat virtual/fiat (Backend + Frontend)
> Item **R1** complété côté serveur : la boutique n'est plus une prévisualisation mock mais une **économie réelle**. Le modèle est refondu (remplacement **complet** de l'ancien catalogue de consommables par **faction / skin / pass / currency**), côté backend ET client. **AUCUN COMMIT** (directive utilisateur).
- **Backend (dépôt serveur).** Table `shop_items` (catalogue persistant, **seedé au démarrage** depuis `api/game/shop_catalog.py`, upsert idempotent ; contenu : **4 factions payantes + 4 skins + Pass + 4 paliers de packs Coins**) ; colonne `users.special_pass_expires_at` (Pass Spécial, **nullable** → auto-migrée par `sync_missing_columns`) ; la table de liaison `inventory_items` (= « UserInventory ») est **réutilisée**. Routes : `GET /shop/catalog`, `GET /shop/inventory` (+`has_active_pass` / `pass_expires_at` ISO), `POST /shop/purchase/virtual` (Coins — faction/skin **définitif**, Pass = **+90 j**), `POST /shop/purchase/fiat` (**stub** paiement → crédite des Coins), `/shop/purchase` conservé en **alias déprécié**. Contrat : [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) §9.3. Script de secours : `backend/migration_shop_economy.sql`.
- **Frontend (`shop.gd`) — visuels charte « Warzone » §2.** Liseré + eyebrow de carte à la **COULEUR SIGNATURE de faction** (faction par son id, skin par `hero_key` ; **or** pour pass/currency), via le chargement `.tres` (`_load_factions`, repli cyan). **Garde-fou de contraste** (`_readable_accent`) : un accent de faction trop sombre (ex. chasseurs_ombres, ordre_eclipse) est **éclairci vers le blanc froid** pour le TEXTE de l'eyebrow/héros (le liseré, lui, garde l'accent brut). `_build_shop_card` : prix en **€** (`4,99 €`) pour les packs fiat + ligne « +N COINS » (or) ; **skin** → eyebrow « HÉROS : <faction> » ; **Pass** → « PASS ACTIF · N J » (jours dérivés de `pass_expires_at`) ; bouton remplacé par « EN DÉPÔT » pour une faction/skin possédé. `_on_buy_pressed` route vers `purchase_item_virtual` (Coins) ou `purchase_item_fiat` (argent réel) selon `currency_type` (pas de pré-contrôle de solde en fiat). Badge quantité inventaire gardé **cyan** (contraste sûr quelle que soit la couleur de faction).
- **`network_manager.gd`.** `purchase_item_virtual` (`POST /shop/purchase/virtual`) + `purchase_item_fiat` (`POST /shop/purchase/fiat`) ; `purchase_item` conservé en **alias** → virtual. Signaux `shop_*` inchangés (réponses enrichies de `has_active_pass` / `pass_expires_at`).
- **i18n (`translations/ui_strings.csv`).** **Remplacement complet** des clés boutique : catégories `SHOP_CAT_{FACTION,SKIN,PASS,CURRENCY}`, items factions/skins/pass/packs, helpers `SHOP_GET` (CTA fiat), `SHOP_PACK_GRANT`, `SHOP_PASS_ACTIVE`, `SHOP_PASS_ACTIVE_DAYS`, `SHOP_SKIN_HERO` ; libellés de statut périmés rafraîchis (fin de l'« APERÇU LOCAL »). Recompilées en `.translation` par l'éditeur.
- **Validation (RENDU RÉEL).** Backend `py_compile` OK (SQLAlchemy/FastAPI ne vivent qu'en Docker). GDScript : parse OK + **0 erreur/warning éditeur** sur `shop.gd`/`network_manager.gd` (via MCP `godot-ai`). **Rendu visuel CAPTURÉ** : la scène a été jouée dans l'éditeur (MCP `project_run` custom + harnais d'injection de données d'exemple, supprimé ensuite) et **les 2 onglets screenshotés** (framebuffer jeu) — couleurs de faction, €, « +N COINS », « PASS ATTIVO · 60 G », « IN DEPOSITO », « COMPRA » tous corrects ; **0 erreur runtime**. ⚠️ Binaire Godot CLI absent de cette machine (pas de boot `--import` headless). ⚠️ **Aucun commit**.

### 8.54. Coloriage/contour des territoires sur les VRAIES frontières peintes — carte-ID (Frontend)
> **Demande utilisateur** : le remplissage coloré et le contour surbrillant des territoires possédés suivaient la **mappatura** (le polygone-hitbox blocky), pas les **vraies frontières** peintes sur le fond. On découple le rendu du polygone : un **overlay** colore/contoure les territoires d'après une **carte-ID** par pixel, donc le long des côtes réelles. **AUCUN COMMIT.**
- **Carte-ID (outil hors-jeu `tools/gen_territory_idmap.gd`, rejouable).** Script Godot `extends SceneTree` (Image API, **sans Python**) : parse `board.tscn` (texte) pour les 42 polygones, construit le **masque** de chaque polygone par remplissage **scanline**, prend la **couleur dominante** (mode) de l'intérieur = couleur peinte du territoire, puis **classe** les pixels du polygone proches de cette couleur → région réelle (s'arrête aux contours sombres, sans fuite océan/voisins). Sortie : **`assets/images/territory_id_map.png`** (canal R = index 1..42, **import lossless** → indices exacts) + **`territory_id_order.json`** (ordre des index). Vérifié visuellement via une image debug palettisée (régions = continents peints).
- **Rendu (`shaders/territory_overlay.gdshader` NEUF + `board.gd`).** Un `Sprite2D` `TerritoryOverlay` portant la carte-ID recouvre **exactement** le `board_bg` (centre `(1108,757)`, §8.50), au-dessus du fond et **sous** les badges. Le shader lit l'index dans le canal rouge (échantillonné via une **uniform `sampler2D id_map : filter_nearest`** — pas le built-in `TEXTURE`, inaccessible en fonction), colore avec `territory_colors[idx]` et **contoure** les pixels-frontière (changement d'index) avec `territory_edge[idx]`. `board.gd.generate_board()` pousse ces deux tableaux (couleur+alpha de remplissage **réutilisés** de la logique existante ; alpha de contour = **MOI vif 0.95 / adverse atténué 0.55 / contaminé 0.9 / sélection 1.0**) → l'emphase « mes territoires vs les autres » (§8.52) est **préservée**, mais portée par l'overlay.
- **Remplace** les `Polygon2D` de remplissage + l'hologramme `neon_hologram` + l'ombre de relief (qui suivaient le **polygone**) : ces helpers (`_ensure_fill`, `_apply_hologram_material`, `_apply_toxic_material`, `_apply_own_relief`) restent dans `board.gd` mais ne sont **plus appelés** (le picking des `Area2D`/`CollisionPolygon2D` est, lui, **inchangé** — clic = polygone, rendu = carte-ID). Territoires neutres = overlay transparent (la carte transparaît).
- **Relief (ombre portée) ré-introduit sur les vraies côtes (à la demande utilisateur).** L'effet « mes territoires soulevés » (§8.52) est reporté DANS l'overlay : le shader décale la silhouette de MES territoires (flag `territory_mine[]` poussé par `board.gd`) de `shadow_offset (5,8)` px et assombrit (`shadow_alpha 0.5`) la zone derrière → l'ombre épouse désormais les **vraies côtes** (et non plus le polygone). Réglable par uniformes.
- **Validation (Godot 4.7-stable, headless CLI).** `--import` = **0 erreur** (carte-ID importée lossless) ; boot `main.tscn` (`--quit-after 90`) = **0 ligne `ERROR`** (shader overlay + relief compilés, overlay instancié). ⚠️ **Rendu visuel NON confirmé de mon côté** : le lien éditeur-live (MCP, captures temps réel) s'est **déconnecté en cours de session** → l'aspect en jeu (alignement, intensités d'alpha/contour, ombre) est à **confirmer/ajuster en lançant la partie**. Tout est piloté par uniformes (réglable). ⚠️ **Aucun commit**.

---

## 🗺️ FEUILLE DE ROUTE FRONTEND (BACKLOG PLANIFIÉ)

> Travaux **planifiés, non encore réalisés** — suivi d'avancement (directive « tracer parfaitement l'état »).
> Priorité indicative. Chaque item suivra la **charte « Warzone Command » §2** et la **Règle d'Or §6.1**
> (UI = Vue pure, logique via signaux/managers). **Rappel : aucun commit sans demande explicite de l'utilisateur.**

### R1. Boutique & Inventaire (écran neuf) — bouton `main_menu` « ❯ BOUTIQUE & INVENTAIRE »
- ✅ **FRONTEND FAIT (§8.39).** `main_menu.gd._on_inventory_pressed()` ouvre désormais `scenes/ui/shop.tscn` (fin du STUB). Écran en charte Warzone : panneaux gunmetal + encoches, en-tête eyebrow→valeur (solde **CRÉDITS** en or), 2 onglets BOUTIQUE/INVENTAIRE, grille d'articles 3 colonnes, **badges hexagonaux** (prix en **or** `#e0b249`, quantités en cyan via `warzone_ui.make_hex_badge`), CTA `❯ ACQUÉRIR`. Navigation `main_menu` ⇆ `shop` (bouton `❮ RETOUR`).
- ✅ **ÉCONOMIE SERVEUR FAITE (§8.53).** Plus de mock : catalogue lu via `GET /shop/catalog` (table `shop_items`, **4 catégories** faction/skin/pass/currency), solde + inventaire + `has_active_pass` via `GET /shop/inventory`, achats réels `POST /shop/purchase/virtual` (Coins) et `/fiat` (argent réel, **stub** serveur). Le client choisit la route selon `currency_type`, affiche « EN DÉPÔT » / « PASS ACTIF » / prix €, et gère « Crédits insuffisants » (message serveur, en rouge).
- **Backend (dépôt serveur)** : modèles `ShopItem` + `User.special_pass_expires_at`, routeur `shop.py`, seed au boot (`shop_catalog.py`). Contrat → [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) **§9.3**.

### R2. Profil joueur — HUB À ONGLETS ✅ LIVRÉ (refonte §8.106)
Accessible par l'onglet de nav **JOUEUR** et par la jauge d'XP cliquable. Écran en charte Warzone : panneau gunmetal **1360×900** + encoches, rythme eyebrow→valeur, `corner_radius = 0`, **aucun emoji** (badges hexagonaux et chevrons `❯` uniquement).

**Structure : un EN-TÊTE D'IDENTITÉ permanent + 5 onglets.**
- **En-tête (toujours visible)** — *gauche* : pseudo, niveau, barre d'XP cyan, solde Coins en **badge hexagonal or** (même convention que la boutique : le nombre seul dans l'hexagone, aucun symbole monétaire → zéro risque de glyphe manquant). *Droite* : **carte DIVISION précise** — badge hexagonal à la couleur de division, libellé composé « **OR II** » (`DIVISION_TIER_FMT`), RP en or, **mini-barre d'échelon** (`rp_in_tier / tier_span`), **rang mondial** « #37 », **fin de saison « J-N »**.
- **APERÇU** — cartes de campagne (parties, victoires, défaites, ratio, tribut, faction favorite teintée) + **bande de FORME** : 10 derniers résultats en carrés 18×18 (or = victoire, rouge = défaite, **liseré cyan = partie classée**), le plus récent à **droite**.
- **STATISTIQUES** — chips exclusives **PAR PERSONNAGE** (défaut) / **PAR MODE**. Par personnage : une rangée-carte par faction jouée (pastille + nom + niv. héros, volume, **barre de winrate**, colonnes PLACE MOY. / XP / RP NET signé). Par mode : deux cartes CLASSÉES (or) / NORMALES (cyan). En pied : **courbe des RP cumulés** sur les 20 dernières classées (`draw_polyline` natif, **aucune lib externe**), masquée sous 2 points.
- **HISTORIQUE** — chips **VICTOIRES** (défaut, demande produit) / TOUTES / CLASSÉES ; ligne enrichie (issue + place « 2ᵉ / 5 », faction + badge CLASSÉE, détail + date relative, gains XP / ±RP / Coins) ; pagination « AFFICHER PLUS ».
- **FINANCES** — 3 cartes (solde / total gagné / total dépensé), **répartition par source** avec barres proportionnelles, **transactions récentes** paginées, **potentiel de gain par personnage** (fourchettes sans Pass / avec Pass).
- **PASS** — bandeau d'état (actif « expire dans J-N » / inactif + un seul bouton ghost vers la boutique), **avantages DATA-DRIVEN** (le rendu itère `tiers[]` : ajouter un tier côté serveur suffit), **gain réel mesuré** (4 cartes + BILAN NET), **objets obtenus** (rendu générique par catégorie).

**Chargement LAZY.** `/profile/stats` + `/profile/history` au `_ready` (l'écran s'ouvre sur **un seul aller-retour**) ; `/profile/finance` et `/profile/pass` seulement à la **première** ouverture de leur onglet (`_loaded_tabs`).

**Dégradation (règle §5 — VPS pas forcément redéployé).** Sans bloc `season`, l'en-tête retombe sur la division LEGACY de `/auth/me`. Sur 404 de `/profile/finance` ou `/profile/pass`, l'onglet affiche `PROFILE_TAB_UNAVAILABLE`. Une ligne d'historique legacy affiche « — » aux emplacements place/XP/RP — **aucune donnée inventée**. L'écran n'est **jamais** vide.

- **Backend** → [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) **§9.1** (4 endpoints, tous ADDITIFS).

### R3. Classement mondial (écran neuf) — déjà annoncé en §3 (cible du menu principal)
- ✅ **FRONTEND FAIT (§8.41).** Nouveau bouton `main_menu` « ❯ CLASSEMENT MONDIAL » → `scenes/ui/leaderboard.tscn`. Écran en charte Warzone : panneau gunmetal + encoches, en-tête eyebrow→valeur, **podium top 3** (#1 en **or** avec badge hexagonal `make_hex_badge`, #2/#3 cyan), **tableau classé** (rang, pseudo, niveau, victoires en or) à colonnes alignées (en-tête fixe hors scroll), **ligne du joueur local surlignée** (fond cyan + liseré épaissi + « (VOUS) »), scroll. Navigation `main_menu` ⇆ `leaderboard` (bouton `❮ RETOUR`).
- ⏳ **Reste mock tant que l'endpoint classement n'existe pas** : `_mock_board` (12 entrées) + joueur local **fusionné/re-trié/re-rangé** côté client, niveau/victoires locaux **lus défensivement** de `/auth/me`. Quand l'endpoint arrivera, seul le peuplement change (découplage Vue/réseau, comme lobby / shop / profile).
- **À définir (backend)** : endpoint classement (tri serveur, pagination). ✅ **Demande FORMALISÉE** → [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md) **§9.2** (`GET /leaderboard?limit&offset` : `entries[{rank,username,level,wins}]` triées desc. + bloc `me` facultatif), ancrée sur `leaderboard.gd`.

### R4. 🌐 Internationalisation FR / EN / IT (transversal) — ✅ **NOYAU EN PLACE**
- **Objectif** : le jeu doit exister en **au moins 3 langues — français, anglais, italien**.
- ✅ **FAIT (noyau).** Infrastructure i18n opérationnelle : autoload **`LocaleManager`** (sélectionne/persiste la locale, repli langue OS, applique au démarrage via `TranslationServer.set_locale`), table **`translations/ui_strings.csv` → 3 `.translation`** déclarées dans `project.godot` (`internationalization/locale/translations`), chaînes des écrans externalisées en **clés `tr("CLE")`**, et **sélecteur de langue mutualisé** `WarzoneUI.build_language_selector()` (3 boutons FR/EN/IT câblés sur `LocaleManager`, surbrillance vive sur `locale_changed`). Présent dans l'**écran de connexion** (`auth_screen`, pré-login) et l'**écran Paramètres** (R5). **⚠️ Retiré de la barre de navigation** (menu principal + écrans secondaires) en **§8.56** — le choix de la langue est désormais centralisé dans les Paramètres.
- ⏳ **Reste à faire (couverture)** : auditer les **chaînes encore en dur** (certains `.gd`/`.tscn` plus anciens — ex. arène/HUD `main.tscn`) non encore migrées en clés, et vérifier la couverture des **glyphes FR/IT** (é, è, à, ù, ì, ò…) par la police condensée (Bahnschrift/Oswald). Le noyau étant en place, c'est désormais du **rattrapage écran par écran**, pas un chantier fondateur.

### R5. Écran Options / Paramètres (écran neuf) — bouton `main_menu` « ❯ PARAMÈTRES »
- ✅ **FRONTEND FAIT (§8.43).** Nouvel écran `scenes/ui/settings.tscn` ouvert depuis `main_menu` : **volume** Master/Musique/SFX (sliders cyan → bus audio `default_bus_layout.tres`), **affichage** plein écran ⇆ fenêtré + résolution (segments), **langue** (sélecteur R4 réutilisé). Logique dans l'autoload **`SettingsManager`** (jumeau de `LocaleManager` : applique au démarrage + persiste dans `user://settings.cfg`), écran = Vue pure. Application live + auto-sauvegarde.
- ✅ **DÉCONNEXION rapatriée ici (§8.52).** Bouton **« ❯ DÉCONNEXION »** (texte rouge danger `#D6453F`, charte §2) **tout en bas** de l'écran, sous les blocs Audio/Affichage/Langue : coupe le WebSocket s'il est ouvert, purge la session (`AuthManager.clear_session()` — mémoire + disque §P1) puis renvoie vers `auth_screen` via `TransitionManager`. C'était auparavant dans le lobby (qui ne garde qu'un **« ❮ RETOUR »** vers `main_menu`).
- ⏳ **Pistes futures** : accès **aussi depuis le HUD** in-game (aujourd'hui uniquement `main_menu`) ; réglages audio sans effet audible tant qu'aucune source (musique/SFX) n'existe (cf. R6).

### R6. Améliorations visuelles & confort (divers) — 🟢 **CŒUR FAIT (§8.44→§8.46)** ; ne restent que les vrais ASSETS (audio + portraits HD)
- ✅ **Ouverture spectaculaire (FAIT, §8.44)** : nouvelle chaîne de lancement `bootloader → title_splash → auth` ; **Splash Eroïque animé** (option C : hex-grid + radar shader, reveal du logo entre chevrons, cendres, dactylographie, audio sting). L'ancienne `intro_video` est **retirée**.
- ✅ **Transitions de scène (FAIT, §8.44 + propagé §8.45)** : fondu gunmetal via l'autoload **`TransitionManager`** (`change_scene`/`fade_in_only`), câblé sur **TOUTES** les navigations inter-écrans (menus, lobby, waiting_room, draft, arène, retours). Seuls bootloader/splash gardent un repli brut.
- ✅ **Audio — infrastructure + propagation (FAIT, §8.44 + §8.45)** : autoload **`AudioManager`** (SFX `hover`/`click`/`confirm`/`back`/`sting` + nappe d'ambiance, **placeholders procéduraux** sur bus `SFX`/`Music`). SFX câblés sur **tous** les écrans (menus, draft, shop, HUD arène, rapport) via `WarzoneUI.wire_button_sfx`; ambiance continue dans les menus (reprise au retour de l'arène) ; l'arène **bascule sur sa propre musique de combat** (§8.66, plus de silence).
- ✅ **Audio — override drop-in par vrais assets (FAIT, §8.64)** : `AudioManager` charge en priorité des fichiers `assets/audio/{sfx,music}/<nom>.{ogg,wav,mp3}` (export-safe, **API appelants inchangée**) et retombe sur la synthèse à défaut ; placeholders montés en qualité (44,1 kHz, sons stratifiés). Mode d'emploi : [`assets/audio/README.md`](assets/audio/README.md).
- ✅ **Mutualisation (FAIT, §8.44)** : `warzone_ui.apply_ghost_button(btn)` + `add_filet(parent)` ajoutés. ⏳ Reste à refactorer les écrans existants pour les utiliser.
- ✅ **Portraits de héros — placeholders procéduraux (FAIT, §8.46)** : 10 PNG `assets/images/heroes/*.png` (emblèmes hexagonaux teintés faction, générés en Godot) câblés via `hero_path` dans les `.tres` → affichés dans le Draft ET le Split-Screen VS. ⏳ Reste : **vrais portraits HD** (art/IA) — à déposer en écrasant les PNG de même nom (aucun code à toucher).
- 🟢 **Audio — assets en place (§8.64→§8.67)** : **7 SFX** `.wav` « produits » (`hover`/`click`/`confirm`/`back`/`sting` + **`die_lock`/`impact`** de combat, via [`tools/gen_audio_assets.gd`](tools/gen_audio_assets.gd)) **+ DEUX musiques actives** : **menu** = brano **melodic trap avec REFRAIN VOCAL synthétique** (autotune par formants, vibe « Flash Bling », 27,4 s, via [`tools/gen_menu_vocal_trap.gd`](tools/gen_menu_vocal_trap.gd), §8.68 — l'instrumental **dark trap** [`tools/gen_menu_trap.gd`](tools/gen_menu_trap.gd) §8.67 et le thème « Interstellar » [`tools/gen_menu_music.gd`](tools/gen_menu_music.gd) §8.65 restent en **alternatives archivées**) **et arène/combat** martiale tendue (38,4 s, via [`tools/gen_battle_music.gd`](tools/gen_battle_music.gd), §8.66) — stéréo, boucle. Le menu **ET** l'arène ont une **bande-son** (bascule via `AudioManager`), et le combat aux dés a ses **SFX** (claque + impact). ⚠️ **Propriété d'asset** : `menu_ambient.wav` a 2 générateurs visant le même fichier → n'en lancer qu'un (règle §8.66). ⏳ **Reste (facultatif, aucun code)** : remplacer par des assets **artistiques HD** en réécrivant les fichiers de même nom. *(`intro.jpeg` : résolu — supprimé car orphelin §8.44 ; `video_intro.ogv` conservé mais inutilisé.)*

### 8.92 (chantier E). Carte « DÉFIS EN COURS » branchée aux vraies missions + renommage OPÉRATIONS → DÉFIS (Frontend, 2026-07-17)
> **But.** La « petite fenêtre défis » du menu était **100 % décorative** (2 barres factices + « BIENTÔT DISPONIBLE ») alors que les VRAIES missions transitaient **DÉJÀ** par le menu : `_ready` appelait `fetch_missions()` et `_on_missions_badge_data(data)` recevait le dict complet — mais n'en consommait QUE `claimable_count` (la pastille `●N`). On consomme désormais le reste. **Frontend exclusif, aucun appel réseau nouveau.**
>
> - **Renommage (i18n SEULE, aucun code).** `MENU_TAB_MISSIONS` et `MISSIONS_TITLE` → **« DÉFIS » / « CHALLENGES » / « SFIDE »**. L'eyebrow `MISSIONS_EYEBROW` reste « CENTRE DE COMMANDEMENT ». Pour éviter le doublon avec l'onglet, la carte du menu (`MENU_CHALLENGES_TITLE`) devient **« DÉFIS EN COURS »** et son sous-titre un appel court (« Réclamez vos récompenses. »). `MENU_CHALLENGES_SOON` n'est plus affichée mais **la clé reste dans le CSV** (on ne supprime jamais une clé). Les ids, noms de scène et endpoints `/missions` sont **INCHANGÉS**.
> - **Câblage (`main_menu.gd`).** `_on_missions_badge_data` appelle en plus `_populate_challenges_widget(data)`. Sélection : fusionne `daily + weekly`, **EXCLUT les `claimed`**, ordonne **(1) réclamables (`completed && !claimed`) d'abord, (2) puis en cours par ratio `progress/target` DÉCROISSANT, (3) départage stable par `mission_id`**, et garde les **`MENU_CHALLENGES_MAX = 3`** premières. `_make_challenge_placeholder` (code mort) **retiré**.
> - **Rendu d'une ligne** (Vue pure, compact, inspiré de `missions.gd::_make_row`) : `❯ tr(name_key)` + chip récompense `◈ N` (or) / mini `ProgressBar` cyan (**or si réclamable**) + compteur `progress/target`, remplacé par **« À RÉCLAMER »** (`MENU_CHALLENGES_CLAIMABLE`) sur une ligne réclamable. Textes COMPOSÉS → `auto_translate_mode = DISABLED` + re-rendu manuel sur `locale_changed`.
> - **États.** Avant la 1re réponse : ligne discrète **`❯ SYNCHRONISATION…`** (`MENU_CHALLENGES_LOADING`) ; serveur muet/échec → la carte **RESTE** sur cet état passif (aucun mock, aucune erreur bruyante). Tout réclamé → `MENU_CHALLENGES_EMPTY`. Pied de carte **« VOIR TOUT ❯ »** (`MENU_CHALLENGES_VIEW_ALL`) → `missions.tscn` (même cible que l'onglet ; même patron que le « VOIR TOUT » du mini-classement). Les données sont re-fetchées à chaque retour au menu → l'état après un claim est correct sans travail en plus.
> - **Validation.** `--import` **0 ERROR** ; boot `main_menu.tscn` **0 ERROR** (état « SYNCHRONISATION… », serveur muet). **Tri prouvé** par une scène de test jetable (le tri est pur → script instancié HORS arbre) : réclamable en tête malgré un ratio égal, `weekly_high` (0.8) devant `daily_low` (0.25), réclamée exclue, cap 3 respecté, dict vide → 0 défi. ⚠️ `--script` **impossible** ici (les autoloads ne sont pas enregistrés → `Identifier not found: AudioManager`) : la vérification passe par une **scène bootée**.

### 8.93 (chantier F). Personnage sélectionné PERSISTANT (Personnages → menu) (Frontend, 2026-07-17)
> **But.** Le choix fait dans l'écran Personnages était **éphémère** (surbrillance locale, jamais relue) et le menu affichait la **dernière faction JOUÉE**. Le personnage choisi devient LE héros du menu, y compris après redémarrage. **Persistance LOCALE** (zéro backend : aucun champ serveur « faction sélectionnée » n'existe — la `favorite_faction` du profil est DÉRIVÉE de l'historique, sémantique différente).
>
> - **`settings_manager.gd`** : nouvelle section **`[gameplay]`** + API dédiée `get_selected_faction() -> String` (défaut `""`) / `set_selected_faction(fid)` (écrit + `_save()`). Volontairement **HORS de `COMFORT_DEFAULTS`** (ce n'est pas un réglage de confort typé/gated). `_save()` **préserve** les autres sections (vérifié).
> - **`characters_screen.gd`** : `_select(index, persist := false)`. ⚠️ **Écart ASSUMÉ vs la spec**, qui demandait de persister à la fin de `_select` : `_select` est AUSSI appelé par l'auto-sélection d'ouverture → un joueur n'ayant JAMAIS choisi aurait vu le simple fait de **consulter** l'écran figer le héros du menu sur le 1er du roster, en contradiction avec le critère d'acceptation « aucun choix jamais fait → comportement inchangé ». Seul `_on_card_pressed` (clic UTILISATEUR = choix EXPLICITE) passe `persist = true`. À l'ouverture, `_initial_index()` sélectionne le personnage persisté s'il est encore au roster, sinon 0. Chip **or « SÉLECTIONNÉ »** (`CHAR_SELECTED_BADGE`, encoches) porté par la seule carte choisie (indexé par index de HÉROS → insensible à une entrée de roster non-Dictionary).
> - **`main_menu.gd` — priorité du héros affiché** : **(1)** `SettingsManager.get_selected_faction()` si non vide **ET** `_factions.has(fid)` ; **(2)** sinon dernière faction JOUÉE (`_on_history_loaded`) ; **(3)** sinon défaut alphabétique. ⚠️ **Point critique** : `_on_history_loaded` est ASYNCHRONE et arrive APRÈS le `_ready` → il n'applique l'historique **QUE si aucune sélection explicite n'existe** (sinon le choix « clignoterait » avant d'être écrasé). `_last_faction_id` est mémorisé **dans tous les cas** : la ligne « faction de prédilection » du mini-profil garde la sémantique « dernière jouée ».
> - **Robustesse.** Id persisté inconnu du catalogue (`.tres` retiré, sauvegarde antérieure) → ignoré, repli (2)/(3). Note en commentaire : si les factions deviennent VERROUILLÉES côté serveur (rotation/possession, M3), la revalidation se branche dans `_explicit_faction()`.
> - ⚠️ **Piège confirmé** : le **nom de fichier `.tres` n'est PAS l'id** (`nomades.tres` → id `pillards_poussiere`, `phalangistes.tres` → `phalanges_acier`, `rad_hunters.tres` → `culte_isotope`). Un premier test utilisant le nom de fichier a échoué — **le code était juste, le test faux**.
> - **Validation.** Scène de test jetable : `set/get` immédiat OK ; **persistance RÉELLE sur disque** relue dans `user://settings.cfg` (`[gameplay] selected_faction`) ; sections `[audio]`/`[display]` **survivent** au `_save()` ; choix explicite valide → pris ; id inconnu → `""` (repli) ; aucun choix → `""`. Boots `main_menu.tscn` + `characters_screen.tscn` **0 ERROR**.

### 8.94 (chantier G). Barre de navigation UNIQUE — `top_nav` devient le header CANONIQUE des écrans hub (Frontend, 2026-07-17)
> **But.** **Trois familles de headers** coexistaient : (a) barre en DUR dans `main_menu.tscn` (seule à avoir la jauge cliquable + mini-profil + pastille + confirmation de sortie), (b) le composant `top_nav.gd` (onglets **divergents** : `profile` au lieu de `missions`, jauge NON cliquable), (c) headers maison + bouton **RETOUR** (profil, classement, défis, personnages) — avec en prime un **double header** sur boutique/réglages (la boutique affichait même les coins **deux fois**). `top_nav.gd` devient la **SOURCE UNIQUE**.
>
> - **Onglets canoniques** : `lobby / characters / shop / missions / leaderboard` (clés `MENU_TAB_*` existantes). **`profile` disparaît des onglets** : le Profil s'ouvre par la **jauge XP CLIQUABLE** (comme au menu depuis §8.58).
> - **Porté du menu vers `top_nav`** : jauge `xp_coins_bar` **interactive** (`set_interactive(true)` + `profile_widget_clicked`) → **mini-profil flottant** (§8.58) ; **pastille défis `●N`** (désormais visible sur TOUS les écrans hub) ; **confirmation « QUITTER »** — le ⏻ de l'ex-`top_nav` tuait le jeu **sans demander** : la porter évite une régression et généralise la garde. Le mini-profil a besoin du catalogue de factions (ligne « faction de prédilection ») → `_load_factions()` porté avec ses garde-fous (scan export-safe + `FALLBACK_PATHS` + duck-typing).
> - **Un seul déclencheur de fetch.** `top_nav` est montée PARTOUT → c'est ELLE qui appelle `get_profile()`, `fetch_missions()` et `fetch_profile_history(1)` ; les écrans hôtes se contentent d'**ÉCOUTER** les signaux globaux (le menu écoute `missions_loaded` pour sa carte Défis §8.92 et `profile_history_loaded` pour son héros §8.93). **Évite le double fetch.** Le menu s'abonne AVANT de monter la nav.
> - **Overlays `top_level = true`.** Le mini-profil et le pop-up « Quitter » sont enfants de la nav, dont la hauteur est `NAV_H` : sans `top_level` (+ position/size posées sur le viewport), leur capteur plein-cadre aurait été **borné à la bande**.
> - **Retour uniforme.** `ui_cancel` (ÉCHAP) dans `top_nav` : (1) ferme le pop-up Quitter, sinon (2) ferme le mini-profil, sinon (3) si `active_tab != "lobby"` → retour au QG. **Remplace tous les boutons RETOUR** (supprimés partout, avec leurs `_style_ghost_button`/`_on_back_pressed` devenus morts).
> - **Écrans migrés** (`active_tab` réglé **AVANT `add_child`** — lu au `_ready`) : `characters` / `shop` / `missions` / `leaderboard` **avec onglet**, contenu décalé de **`NAV_H = 100`** (`CenterContainer.offset_top` en scène, `TopNav.NAV_H` en code). `section_placeholder` : **`BAR_H := TopNav.NAV_H`** (l'ancien `56` **sous-estimait** la bande → le panneau passait dessous).
> - **Titre interne : retiré pour les écrans À ONGLET, CONSERVÉ pour les écrans HORS onglets.** Sur `characters`/`shop`/`missions`/`leaderboard`, c'est l'**onglet ACTIF** qui nomme la section → l'en-tête maison (titre + RETOUR) est supprimé, conformément à la spec. Sur **`profile` / `settings` / placeholders**, `active_tab = ""` → **AUCUN onglet surligné** : leur titre est alors la SEULE chose qui les nomme, il est donc **gardé** (la spec ne demandait de leur régler que `active_tab`). Vérifié à l'écran. `settings` passait `"options"`, un id absent de `TABS` : même résultat mais **par accident** — c'est désormais explicite.
> - **Boutique.** `HeaderBar` interne **ET** `CreditsBox` redondante retirées (le solde vit dans la jauge de la nav) ; `_credits` reste lu pour griser les articles trop chers. **Classement** : `HeaderBar` vidée de son titre/RETOUR mais **CONSERVÉE** — elle héberge les onglets SAISON/GÉNÉRAL et le bouton `ℹ RÈGLES` (§8.95) ; `_build_scope_tabs` s'appuyait sur `back_button.get_index()` → il **APPEND** désormais (nouvel `@export header_bar`).
> - **Ambiance/SFX.** `top_nav` **ne lance JAMAIS** `start_menu_ambient()` : chaque écran hôte l'appelle (ajouté sur `characters`/`shop`/`missions`/`leaderboard`/`profile`/`settings`). **Hors périmètre, intact** : HUD d'arène, `lobby_screen`, `waiting_room`, `faction_selection`.
> - ⚠️ **DÉFAUT HÉRITÉ constaté, NON corrigé.** Le glyphe **`⏻` (U+23FB) s'affiche en « tofu »** (carré de glyphe manquant) : la chaîne condensée de la charte porte `⚙` (U+2699) mais **pas** `⏻`. **Ce n'est PAS une régression** (l'ex-top-bar du menu utilisait la même chaîne via `_style_icon_button`) — mais §8.94 la rend visible sur **8 écrans** au lieu de 3. Ajouter « Segoe UI Symbol » en tête **ne corrige rien** (cette police n'a pas non plus U+23FB) **et dégrade le rendu du `⚙`** → tentative **revertée**. Correctif à trancher : remplacer le glyphe par un symbole couvert, ou embarquer une police d'icônes (**nouvel asset → Annexe C**).
> - **Validation.** `--import` **0 ERROR** ; boot des **7 écrans hub** `main_menu` / `characters_screen` / `shop` / `missions` / `leaderboard` / `profile` / `settings` → **0 ERROR chacun**. **Vérification VISUELLE** (captures viewport→PNG, boot **fenêtré** — le pilote headless « Dummy » ne rend rien) : barre identique partout, onglet actif correct, « DÉFIS » renommé, aucun double header ni RETOUR, contenu jamais sous la bande, `profile` sans onglet surligné (d'où son titre conservé).

### 8.95 (chantier H, partie FRONTEND). Écran Classement refondu — carte « VOTRE RANG », bande des divisions, panneau RÈGLES, pagination (Frontend, 2026-07-17)
> **But.** Rendre le ladder LISIBLE. Constat : le tri saisonnier se faisait sur `season_points` mais la colonne mise en avant (or) était **VICTOIRES** → l'ordre paraissait **arbitraire** ; le podium affichait toujours les victoires, même en SAISON ; la division n'était qu'une étiquette de ligne (aucun seuil, aucune règle nulle part) et « VOTRE DIVISION » était reléguée dans la **ligne de statut grise du bas** ; la pagination était figée à 20/0. **Barème et payloads : voir `CONTRAT_RESEAU.md` §8.95.**
>
> - **Carte « VOTRE RANG » en tête** (remplace la ligne de statut du bas) : badge hexagonal à la couleur de division + gros `label` (« OR II »), **barre `rp_in_tier / tier_span`** (« 47/100 RP ») — en **ÉLITE** (`tier_span == 0`) : **total RP, SANS barre** —, rang mondial `#N`, compte à rebours de fin de saison, et chip **« DERNIER MATCH : +25 RP »**.
> - **ΔRP du dernier match** : lu du cache d'autoload `NetworkManager.last_match_rewards` (survit au changement de scène). Il est **REDACTÉ par destinataire** (E11 §8.83) → il ne contient QUE notre entrée, d'où la lecture par **clé unique**. **Garde défensive** : si un serveur ANTÉRIEUR à la redaction renvoie toutes les entrées, l'id local n'étant pas connu de cet écran, on n'affiche **RIEN** plutôt que le ΔRP d'un autre joueur.
> - **Bande des divisions** : 5 badges (seuil `floor` + effectif `players`), celui du joueur **surligné** (encoche or). Repli : `season` sans `divisions` → bande masquée.
> - **Liste & podium** : en **SAISON**, l'emphase or passe des VICTOIRES aux **RP** (la clé de TRI) et la colonne DIVISION affiche **division + échelon** (« OR II ») ; le podium affiche RP + badge de division. L'onglet **GÉNÉRAL** (trié par victoires) garde **VICTOIRES en or** — inchangé.
> - **Panneau `ℹ RÈGLES`** (entête) : rendu **DEPUIS `season.rules`** — barème par place, bonus d'élims, protection BRONZE, plancher de division, RP par échelon, récompenses de fin de saison. **Aucun barème en dur côté client.** Repli : pas de `rules` → bouton **masqué**.
> - **Pagination** « AFFICHER PLUS » (`offset += limit`, **append**) : l'API supportait déjà `limit/offset`, seul le client figeait 20/0. Fin de liste = page incomplète ; changement de scope → **repart de la page 0** (sinon l'offset du scope précédent contaminerait la requête).
> - **Rapport Post-Op** (`operation_report.gd`) : bloc **ladder** en partie classée — ligne « **+25 RP — OR II** » (or si positif, **rouge danger si négatif**), bannière **PROMOTION** / RÉTROGRADATION, mention discrète si le **plancher** a amorti la perte. Partie NON classée → **rien** (cohérent §8.88). Lecture défensive : pas de `rp_label` → aucun bloc (jamais de « +0 RP »).
> - **Cohérence des libellés.** Les ids réseau sont ASCII (`"ELITE"`) mais le serveur compose `rp_label` = « **ÉLITE** » (accentué) : sans mapping, le Rapport disait « ÉLITE » et le Classement « ELITE ». `DIVISION_LABELS` côté client **reflète** `seasons.DIVISION_LABELS`.
> - ⚠️ **BUG TROUVÉ ET CORRIGÉ à la capture** : le panneau RÈGLES s'affichait **VIDE**. Cause : un nœud ajouté par code **sans `name` explicite** reçoit un nom **AUTO-GÉNÉRÉ** (`@CenterContainer@2`) → `get_node_or_null("CenterContainer/RulesPanel/Body")` renvoyait `null` **silencieusement**. Remplacé par une **référence directe** (`_rules_body`). **Un boot « 0 ERROR » ne l'aurait JAMAIS révélé.**
> - **Replis défensifs** (backend pas encore redéployé) : pas de `division_tier` dans `me` → **pas de carte VOTRE RANG** (division + fin de saison retombent dans la ligne de statut) ; pas de `rules` → pas de bouton ; pas de `divisions` → pas de bande ; `_has_division_data` conservé.
> - **Validation.** `--import` **0 ERROR** ; boots `leaderboard.tscn`, `main_menu.tscn`, `game/main.tscn` **0 ERROR**. **Vérifié À L'ÉCRAN sur payload RÉALISTE injecté** (carte VOTRE RANG « OR II » 47/100, rang #5, « DERNIER MATCH : +25 RP » ; bande BRONZE→ÉLITE avec OR surligné ; podium 1830/1240/1150 RP + badges ; panneau RÈGLES complet rendu depuis `rules`). **Repli legacy prouvé EN CONDITIONS RÉELLES** : le VPS de prod (backend **pas encore redéployé**) a répondu pendant le test → l'écran a affiché correctement RP + DIVISION **sans** carte, **sans** bande, **sans** bouton RÈGLES, **aucun crash**.

### 8.96 (chantier I). Polish transverse des écrans hub — entrée, feedback, états d'attente (Frontend, 2026-07-17)
> **But.** Élever la cohérence perçue des écrans hub **SANS nouvel asset** (Annexe C) ni refonte. HUD d'arène, écran VS et Rapport Post-Op **hors périmètre**.
>
> - ⛔ **I.1 (fond animé commun) NON FAIT — décision produit (Hakim, 2026-07-17).** La spec supposait des « **aplats disparates** » ; **audit contraire** : les **7** écrans hub portent **DÉJÀ le MÊME fond opaque `bg_wasteland.png`** (`main_menu`, `characters_screen`, `shop`, **`missions`**, `leaderboard`, `profile`, `settings` — vérifié fichier par fichier ; seuls les 4 placeholders, **débranchés de la nav**, n'en ont pas). Un `hub_backdrop.tscn` monté **SOUS** une image opaque serait **invisible partout** → fichier + montages **morts**. La cohérence de fond visée **existe déjà** (prouvée par les captures). Option restante si l'intention était autre : **REMPLACER** `bg_wasteland.png` par l'hexgrid animé sur les écrans secondaires (le menu gardant sa photo) — **changement de direction artistique**, à valider.
> - **Entrée d'écran UNIFORME** — `warzone_ui.gd::animate_screen_enter(root)` : fondu alpha 0→1 + glissement vertical de 12 px, **0,18 s**, `Tween` local au nœud (**jamais `Engine.time_scale`**, qui affecterait tout le jeu ; tween lié au Control → tué avec lui, aucune fuite). Appelé au `_ready()` des **8** écrans hub. Les transitions ENTRE scènes restent gérées par `TransitionManager` (non touché).
> - **Feedback interactif** — `warzone_ui.gd::wire_button_feedback(btn)` : SFX survol/clic + **lueur cyan** au survol via `modulate` (multiplicatif) → **n'écrase AUCUN StyleBox** (ghost/CTA/or préservés) ; **idempotent** (garde par méta). ⚠️ **Constat** : l'inventaire (grep `play_sfx`) montre qu'**aucun écran hub n'est muet** — le gap visé par la spec est **résorbé par §8.94** (la nav, présente partout, apporte ses propres SFX, et les boutons restants en avaient déjà). Le helper est donc **fourni** et **utilisé sur les boutons neufs** (onglets SAISON/GÉNÉRAL, `ℹ RÈGLES`, « AFFICHER PLUS ») ; les `wire_button_sfx` existants sont **laissés tels quels** (les re-câbler doublerait les connexions SFX).
> - **États d'attente / vides NORMALISÉS** (`COMMON_SYNCING` = « ❯ SYNCHRONISATION… », `COMMON_OFFLINE_LOCAL`). **Classement** : le mock s'affichait **D'EMBLÉE** (un classement fictif « flashait » avant d'être remplacé par le vrai — trompeur). Désormais : `❯ SYNCHRONISATION…` tant qu'aucune réponse ; le **mock n'apparaît qu'après un ÉCHEC AVÉRÉ** (`lobby_error`), explicitement étiqueté « **HORS LIGNE — DONNÉES LOCALES** ». `lobby_error` étant un signal **GLOBAL** partagé par d'autres appels REST, l'échec est **ignoré si le classement a déjà répondu** (sinon l'erreur d'un autre écran effacerait la liste). La liste vide distingue « on attend » (cyan) de « le serveur a répondu, personne n'est classé » (muet) — les deux affichaient le même message. Même patron déjà appliqué à la carte Défis (§8.92).
> - **Validation.** `--import` **0 ERROR** ; boot des 7 écrans hub **0 ERROR**. **L'animation d'entrée est PROUVÉE terminée** (un tween cassé laisserait les écrans invisibles **sans lever la moindre erreur**) : scène de test jetable → sur les 7 écrans, `modulate.a` **0.0 → 1.0** et `position` **restaurée à (0,0)** (aucune dérive).

### 8.98 (ladder v2, partie FRONTEND). Classement PAR DIVISION — bande cliquable, onglets de sous-division, podium contextuel (Frontend, 2026-07-17)
> **But (retours produit de Hakim sur §8.95).** (1) L'onglet GÉNÉRAL « n'est d'aucune utilité » → retiré ; (2) le classement ne doit plus être « tous mélangés » → **navigation PAR DIVISION** ; (3) les sous-divisions doivent être explicites → **3 onglets d'échelon** par division ; (4) le podium affiché = celui de la **sous-division I** de la division cliquée ; (5) échelons élargis à **200 RP** ; (6) la **chute de division** doit être possible ; (7) récompenses de fin de saison **aux podiums de chaque sous-division**. Les points 5-7 sont serveur — voir `CONTRAT_RESEAU.md` §8.98 ; ici la partie écran.
>
> - **Onglet GÉNÉRAL retiré** (`_build_scope_tabs`/`_switch_scope`/`_update_scope_tabs_visibility` supprimés, `SCOPE := "season"`) : l'écran est tout entier en scope SAISON. **L'API `scope=lifetime` reste servie** (réseau additif) — seul l'accès client disparaît ; les clés i18n `LEADERBOARD_TAB_*` restent au CSV (jamais supprimer une clé).
> - **Bande des divisions = LA navigation.** Chaque badge (seuil + effectif) est désormais **cliquable** (bouton transparent superposé, patron des cartes de mode du menu) : badge **sélectionné** = fond teinté + liseré plein ; badge du **joueur** = encoches or (cumulables). Clic → `_select_division(div)` : liste de la division + podium de sa sous-division I.
> - **Onglets d'échelon** : rangée « OR I / OR II / OR III » (style pastille des ex-onglets de scope, libellés composés via `DIVISION_TIER_FMT`) insérée À LA PLACE de l'eyebrow « CLASSEMENT GÉNÉRAL » (masqué en navigation). Chaque onglet ouvre le classement de SA sous-division. **ÉLITE = ladder ouvert : aucun onglet.** À l'ouverture de l'écran : division ET échelon du JOUEUR présélectionnés (il se voit d'emblée) ; joueur inconnu → ÉLITE (vitrine).
> - **Podium contextuel** : eyebrow dynamique « PODIUM — OR I » (`LEADERBOARD_PODIUM_DIV`) ; le podium reste celui de la **sous-division I** de la division sélectionnée — il ne suit PAS l'onglet actif (spec explicite) ; ÉLITE → podium de son ladder. Repli plat → clé historique `LEADERBOARD_PODIUM`.
> - **Réseau** : `NetworkManager.fetch_leaderboard` gagne deux paramètres ADDITIFS `division`/`tier` (omis quand vides ; un backend antérieur ignore ces query params inconnus). ⚠️ Le signal `leaderboard_loaded` étant GLOBAL et muet sur ses paramètres, l'écran sérialise ses requêtes : **FILE à une seule requête en vol** (`_queue_fetch`/`_pump_fetch_queue`) + **CACHE par tranche** `"DIVISION|TIER"` (`_tier_cache`) — sans ça, deux réponses croisées se rangeraient dans la mauvaise tranche. La requête d'amorçage reste GLOBALE (elle rapporte `me` + `divisions` + `rules` et nourrit le repli plat).
> - **« AFFICHER PLUS » par tranche** : l'offset est la taille déjà chargée de la tranche affichée (le legacy plat garde sa pagination globale). **Rang affiché = position DANS la sous-division** (le serveur numérote la tranche filtrée) — cohérent avec le podium #1-#3 de tranche. Le bloc `me` n'est PLUS ajouté artificiellement en bas d'une tranche : son rang GLOBAL n'aurait aucun sens dans un classement de sous-division (le joueur est surligné quand il est dans la tranche ; la carte VOTRE RANG porte déjà son rang mondial).
> - **Colonne DIVISION masquée en navigation** (toutes les lignes d'une tranche portent le même badge — l'info vit dans l'onglet actif et l'eyebrow du podium) ; conservée en repli plat M6. Emphase or : RP dès que le serveur publie le ladder (`_gold_is_rp()`), VICTOIRES en repli mock/pré-M6.
> - **Panneau RÈGLES enrichi** (rendu DEPUIS `season.rules`, rien en dur) : la section récompenses affiche désormais « Primes réservées aux podiums de chaque sous-division. », les répartitions `reward_splits` (« PART PAR SOUS-DIVISION : I 50 % · II 30 % · III 20 % », « PART DU PODIUM : 1ᵉʳ 50 % · 2ᵉ 30 % · 3ᵉ 20 % ») et les ENVELOPPES par division (500/1000/2000/4000/10000). La ligne « plancher de division » disparaît d'elle-même (`division_floor_lock: false` — le repli conditionnel de §8.95 joue). `REPORT_RP_PROTECTED` retexte en « PLANCHER APPLIQUÉ » (générique : seul le plancher 0 subsiste).
> - **Replis** : backend sans `divisions` (VPS de prod actuel) → liste plate historique intacte (vérifiée en conditions réelles pendant le test : la vraie réponse du VPS arrive AVANT l'injection du payload v2) ; échec réseau → mock étiqueté HORS LIGNE (§8.96) ; la ligne de statut en navigation ne parle plus de la liste plate globale (l'attente/le vide de la tranche vivent dans la liste).
> - **i18n** : `LEADERBOARD_PODIUM_DIV`, `LEADERBOARD_RULES_REWARDS_PODIUM`, `LEADERBOARD_RULES_SPLIT_TIERS`, `LEADERBOARD_RULES_SPLIT_PODIUM` (fr/en/it) ; valeur de `REPORT_RP_PROTECTED` génériquée.
> - **Validation.** `--import` + boot `leaderboard.tscn` **0 ERROR** ; CSV 3 langues audité. **Piloté À L'ÉCRAN sur payload v2 injecté** (tranches PRÉ-CACHÉES — hermétique, aucune requête réelle vers le VPS antérieur au filtre) : sélection auto OR II (ma division/mon échelon, rang de tranche #1 surligné), bascule d'onglet OR III, clic division ÉLITE (podium « PODIUM — ÉLITE », onglets masqués), panneau RÈGLES complet (barème, échelon 200 RP, AUCUNE ligne de plancher, répartitions podiums, enveloppes). États internes vérifiés (`_selected_division/_selected_tier/_browse_mode`, file vide).

### 8.99 (rattrapage doc). Rapport Post-Op — 4ᵉ onglet BILAN (tableau comparatif) + robustesse récompenses (Frontend, 2026-07-17)
> **Entrée écrite a posteriori (§8.100)** : le code du §8.99 a été commité (`5531caf`/`0fecdc3`/`1a24aa6` « MAJ report parties ») pendant que la session qui le portait travaillait encore — son entrée de journal n'avait jamais été posée. Résumé du LIVRÉ :
>
> - **4ᵉ onglet « BILAN »** dans [`operation_report.gd`](scripts/game/operation_report.gd) : tableau comparatif de TOUS les belligérants (JOUEUR · TERR · CONQ · KILLS · ÉLIM · HÉROS · UNITÉS · ZONE · ÉCHANGE), lignes résolues par le module PUR `WarRoom.debrief_rows` (source unique des compteurs, partagée avec le HUD) ; barre ÉCHANGE = kills/(kills+pertes) cyan sur rouge ; la **timeline de domination MIGRE** de l'onglet CLASSEMENT vers BILAN (statistique, pas verdict).
> - **Robustesse récompenses** : `has_played` (présence dans `rankings`, repli `players`) + verrou `_match_over_received` — un joueur AYANT DISPUTÉ la partie sans récompense reçue voit une **anomalie explicite** (« AUCUNE RÉCOMPENSE REÇUE DU SERVEUR ») au lieu d'un bloc de zéros muet ; un SPECTATEUR ne voit rien ; un simple retard réseau n'est JAMAIS pris pour une anomalie. **Coins TOUJOURS affichés, même à 0** (un compteur masqué à 0 est indiscernable d'un compteur absent).
> - ⚠️ Le commit `1a24aa6` a FIGÉ une contre-épreuve temporaire (`_tabs.remove_child(_tabs.get_child(3))  # A RETIRER` — masquait l'onglet BILAN). **Retirée en working tree au §8.100** ; à embarquer dans le prochain commit.

### 8.100 (refonte RETEX). Rapport Post-Op v3 — classement JAMAIS « en attente », onglet héros JAMAIS vide, zéro emoji, BILAN façon maquette (Frontend, 2026-07-17)
> **But (retours produit de Hakim).** (1) Onglets « trop amateurs » avec emojis partout ; (2) onglet XP HÉROS souvent vide ; (3) coins/progression invisibles ; (4) CLASSEMENT bloqué sur « en attente de classement… » quand on est éliminé ou qu'un autre gagne, partie pourtant finie ; (5) récap de zone inutile dans CLASSEMENT (la colonne ZONE du BILAN suffit) ; (6) s'inspirer de la maquette RETEX fournie. **Aucun changement réseau/backend** — tout est Vue + résolveurs `main.gd`.
>
> - **CLASSEMENT toujours affiché (fix n° 4)** — `main.gd::_effective_rankings()` : rankings du `game_over` si reçus, sinon **repli LOCAL** `_local_rankings_fallback()` (MIROIR du tri serveur `rewards.rank_players` : vainqueur, puis territoires > continents > kills, départage pid ; `_continents_owned()` factorisé, partagé avec `_xp_detail`). Le podium de repli est étiqueté « **Classement provisoire (calcul local)** » (`REPORT_PODIUM_PROVISIONAL`) et **REMPLACÉ par le verdict serveur** dès l'arrivée du `game_over` (`populate_podium(rows, provisional)`). Le BILAN s'ordonne sur le MÊME classement effectif (aucune divergence podium/tableau). **Ordre DÉFENSIF dans `_on_match_over`** : podium et BILAN poussés AVANT le bloc récompenses — une erreur runtime imprévue dans la chaîne d'animation ne peut plus laisser l'écran figé sur « en attente ». `set_xp_detail()` re-résout enfin le détail du barème avec le **rang serveur définitif** (l'ancien rang deviné sous-estimait les postes d'un non-vainqueur).
> - **Onglet XP HÉROS jamais vide (fix n° 2)** — panneau d'**IDENTITÉ du héros** toujours peuplé (`populate_hero_identity`, données 100 % locales via `main.gd::_hero_panel_data()` : portrait du `.tres` (`hero_path`, mis en cache par `_faction_info`), nom de faction, chip « NIV %d », état `PV/PA/PP` mono ou « HÉROS ABATTU — K.I.A. » danger, liseré couleur plateau) + **placeholders honnêtes** « Récompenses en attente de la confirmation du serveur… » dans les 2 onglets XP tant que le `game_over` n'est pas là (les constructeurs VIDENT leur boîte avant de bâtir — idempotents, la note disparaît d'elle-même).
> - **Coins & progression (fix n° 3)** — rangée Coins à **icône hexagonale de charte** (`CoinIcon` réutilisée de `xp_coins_bar`) + total & répartition profil/héros (§8.99) ; **barre d'XP héros habillée charte** (remplissage cyan sur gunmetal, liseré, angles droits — le gris Godot par défaut détonnait) ; jauge `XpCoinsBar` (niveau + XP + solde animés) conservée.
> - **Récap de zone RETIRÉ de CLASSEMENT (fix n° 5)** — les nœuds `.tscn` (`AttritionEyebrow`/`%StagnationReport`/`%AttritionList`) ne sont **plus reparentés : MASQUÉS** (aucune retouche `.tscn`, piège n° 6) ; `populate()` accepte toujours les clés `stagnation`/`attrition` (contrat/tests intacts) mais ne les rend plus — l'info vit dans la colonne ZONE du BILAN.
> - **Dé-émojification TOTALE + restylage maquette (fix n° 1/6)** — onglets « XP JOUEUR / XP HÉROS / CLASSEMENT / BILAN » nus (i18n fr/en/it) ; `medal_for` → **indicatifs mono « 01 »…« 06 »** (or pour le 1ᵉʳ) ; podium en **panneaux à liseré gauche** (or vainqueur / cyan discret), **badges-puces or bordés** pour les titres honorifiques (BOUCHER, CONQUÉRANT, FOSSOYEUR, INDESTRUCTIBLE, IRRADIÉ — sans emoji), objectifs ✓ vert / ✕ acier, compteurs « K · C · E » mono (légende au survol) ; **BILAN re-rendu en RANGÉES HBox à colonnes FIXES** (`DBF_*_W`, en-têtes **GROUPÉS « GAINS » / « PERTES » soulignés** cyan/rouge — impossible avec l'ancien `GridContainer`), pastille couleur plateau par joueur, **ligne du vainqueur lavée OR à liseré**, zébrage discret, ✕ rouge pour les éliminés, en-tête « ❯ BILAN TACTIQUE — N BELLIGÉRANTS » ; glyphes conservés = géométrie de charte (❯ ▸ ◆ ▲ ✓ ✕ ★), pictogrammes bannis. Couplage fragile supprimé : la couleur de la ligne héros de MA PERFORMANCE lit un flag `hero_dead` explicite (plus le préfixe emoji du libellé i18n).
> - **i18n** : clés retouchées sans emoji (onglets, `TITLE_*`, `REPORT_MS_*`, `REPORT_STATS_LEGEND`, `REPORT_INSPECT`, `REPORT_REQUEUE`, `REPORT_HERO_DOWN`, légende BILAN ✖→✕) + nouvelles `REPORT_DEBRIEF_COUNT`/`_GAINS`/`_LOSSES`, `REPORT_PODIUM_PROVISIONAL`, `REPORT_REWARDS_PENDING`, `REPORT_HERO_LEVEL` (fr/en/it).
> - **Outillage** : [`tools/preview_report.gd`](tools/preview_report.gd)/`.tscn` — capture fenêtrée PNG des 4 onglets sur données de démonstration (validation visuelle reproductible) ; [`tools/test_e11_report.gd`](tools/test_e11_report.gd) étendu à **35 asserts** (BILAN en rangées, identité héros, zone masquée, placeholders, podium provisoire remplacé par le verdict serveur).
> - **Validation.** `--import` **0 ERROR** (traductions régénérées) ; `test_e11_report` **35 asserts verts** ; boot `main_menu` **0 ERROR** ; **4 captures PNG** des onglets conformes à la maquette. **AUCUN COMMIT** (règle absolue) — la working tree contient aussi le retrait de la contre-épreuve figée par `1a24aa6` (cf. §8.99).

### 8.102. Boutique à 4 onglets (inventaire fusionné) + Profil Joueur + renommage JOUEUR→JOUEUR + purge emoji GLOBALE (Frontend + Backend, 2026-07-18)
> **But (demande de Hakim).** (1) Boutique optimisée : un onglet **par catégorie** (skins, personnages, pass, coins), textes localisés ; (2) style « propre et professionnel, pas d'emoji » ; (3) profil « révolutionné », la notion d'« Joueur » remplacée par un terme professionnel. Décisions verrouillées : terme = **JOUEUR** (écran « PROFIL »), portée **partout**, inventaire **fusionné** dans les catégories, onglet Coins « propre » (indicateur backend). **⚠️ Volet backend → REDÉPLOIEMENT VPS REQUIS** (le client reste rétro-compatible avec l'ancien serveur en attendant).
>
> - **Boutique ([`shop.tscn`](scenes/ui/shop.tscn)/[`shop.gd`](scripts/ui/shop.gd)) — 4 onglets de catégorie** `PERSONNAGES / SKINS / PASS SPÉCIAL / COINS` (`TAB_DEFS` data-driven, boutons construits en code dans la `TabsBar` de la scène ; libellés = clés brutes auto-traduites). L'ancien couple Boutique/Inventaire disparaît : **inventaire FUSIONNÉ** — un article possédé s'affiche dans sa catégorie (badge « EN DÉPÔT », ÉQUIPER/ÉQUIPÉ ✓ pour les skins, M5 conservé) + compteur discret « N EN DÉPÔT » (`SHOP_OWNED_COUNT`) au-dessus de la grille. Bannière de **rotation** (M3) désormais visible sur le SEUL onglet PERSONNAGES. **Skins de saison possédés enfin visibles** : le client appelle `GET /shop/catalog?include_all=1` et filtre lui-même (`purchasable=false` → affiché SEULEMENT si possédé, badge quantité à la place du prix, jamais de CTA d'achat). Re-render complet sur `locale_changed`. Panneau élargi 1120×760.
> - **Gate paiements (onglet COINS)** — `GET /shop/inventory` expose `payments_enabled` (miroir de `PAYMENTS_ENABLED`, gate C3 fail-closed). Paiements fermés (cas actuel) → les packs de Coins montrent un CTA **désactivé « BIENTÔT DISPONIBLE »** (`SHOP_COINS_SOON`) + note de statut (`SHOP_COINS_DISABLED_NOTE`) au lieu d'un achat voué au 501. Champ ABSENT (serveur antérieur / snapshots post-achat) → on conserve la dernière valeur connue (défaut false).
> - **Backend (⚠️ à redéployer)** — `schemas.py` : `ShopItem.purchasable` + `InventoryResponse.payments_enabled` ; `shop.py` : paramètre `?include_all=1` du catalogue (sans lui : comportement historique, rétro-compat des clients déployés) ; **CORRECTIF SÉCURITÉ** : `_apply_virtual_purchase` (et la route fiat, défense en profondeur) **refuse `purchasable=False`** — un POST direct sur `/purchase/virtual` permettait d'acquérir GRATUITEMENT les skins exclusifs de saison (prix 0, l'exclusivité du Pass était contournable). Tests : [`test_shop_v2.py`](../backend/test_shop_v2.py) **13 OK** + non-régression `test_security_locks.py` **38 OK**.
> - **Profil ([`profile.tscn`](scenes/ui/profile.tscn)/[`profile.gd`](scripts/ui/profile.gd)) — « PROFIL JOUEUR »** : en-tête refondu (eyebrow `PROFILE_EYEBROW` + **pseudo en TITRE 36 px** — plus de doublon « MON PROFIL »/« JOUEUR » ; faction de prédilection à droite, teintée) ; l'ex-`IdentityBar` redondante disparaît. Cartes **DIVISION + POINTS DE SAISON promues en TÊTE** de la grille de stats ; le **liseré de chaque carte prend la couleur sémantique** de sa valeur (or victoires, rouge défaites, couleur de division…). Re-render sur `locale_changed`.
> - **Renommage JOUEUR→JOUEUR (partout, i18n fr/en/it)** — `COMMON_PLAYER` (« JOUEUR »), `MENU_TAB_PROFILE` (« PROFIL »), `PROFILE_EYEBROW`/`PROFILE_STATUS_LOADED` (« PROFIL JOUEUR »), `MENU_TOP_PLAYERS` (« TOP JOUEURS »), `LEADERBOARD_STATUS_LOCATED`/`LEADERBOARD_EMPTY`/`LEADERBOARD_DIVISION_PLAYERS`, `SPECT_EYEBROW`. **Replis de pseudo corrigés** (leaderboard/lobby/profile) : `COMMON_PLAYER` (« Joueur ») — COMMON_PLAYER est un libellé, pas un nom.
> - **Purge emoji GLOBALE (style pro)** — pictogrammes cartoon (🟢🟡🚀✅⏳🔒🗡🛡🛰🏆🏳️🎯💥💀🚩📦⏰📍🪖➡️⏭️🃏🌑🕵🌍🏁📡📢👤🤖🌐…) remplacés par les **glyphes typographiques de charte** (`❯ ▸ ✓ ★ ⚔ ☠ ⚑ ⚐ ◎ ✸ ⚰ ❖ ◆ ⚠ ☢`) dans : `ui_strings.csv` (WR_*/FS_*/ROSTER_*/VS_*/INTEL_WAR_BTN/WARROOM_LEGEND — légende alignée sur les nouvelles pilules), `main.gd` (journal de guerre, instructions), `hud.gd` (pilules war room, chips de filtre ❖, INTEL, identité ❯), `war_feed.gd`/`war_roster.gd` (⚑ territoires, ❖ cartes, ⚐ abandon, ☠ permadeath), `split_screen_vs.gd`/`.tscn` (rôles « ❯ ASSAILLANT/DÉFENSEUR »), `main.tscn` (COMMUNICATIONS, chips chat GÉN/PRIV, ◎ OBJECTIF, ⚑ conquis, ⚔ forces), `characters_screen.gd` (✕ verrouillé), `waiting_room.gd` (préfixe [IA] nu), `warzone_ui.gd` (sélecteur de langue ❯), logs console des managers. Glyphes retenus = couverts par Segoe UI Symbol (monochromes).
> - **Correctif ⏻ « tofu » (§8.94 soldé)** — le bouton Quitter de [`top_nav.gd`](scripts/ui/top_nav.gd) reçoit un **glyphe power IEC DESSINÉ par code** (`PowerGlyph`, arc ouvert + trait, couleur DANGER → blanc au survol) : U+23FB n'existe dans aucune police système de la chaîne. Aucun nouvel asset.
> - **Outillage** : [`tools/preview_shop_v2.gd`](tools/preview_shop_v2.gd)/`.tscn` (pattern §8.100) — capture fenêtrée PNG des 4 onglets boutique + profil sur données de démonstration hors ligne.
> - **Validation.** `--import` **0 ERROR** (traductions régénérées) ; boots headless `shop`/`profile`/`main_menu`/`waiting_room`/`characters_screen`/`leaderboard`/`split_screen_vs` **0 ERROR** ; backend **13 + 38 asserts verts** ; **5 captures PNG** conformes (onglets, gate Coins, EN DÉPÔT/ÉQUIPÉ, profil refondu, glyphe power rendu). Prime rétro-compat CONSTATÉE : le serveur de production ACTUEL (antérieur) répond proprement à `?include_all=1` (paramètre ignoré). **AUCUN COMMIT** (règle absolue).

### 8.103. Modes × cartes : fin du clamp d'effectif SILENCIEUX (« EXA à 4 ») + étanchéité Radar CLASSÉE↔casual (Frontend, 2026-07-18)
> **Bug rapporté par Hakim.** « Le mode EXA (6 joueurs) ne remplit que 4 joueurs. » **Cause racine** : sur la carte « THÉÂTRE ATLANTIQUE » (bornée 3-4), `_create_headcount()` CLAMPAIT en silence l'effectif du mode (EXA 6 / FIVE 5 → 4) à la création de salle — le serveur re-clampe à l'identique (`ranked_room_bounds`, comportement G5 §8.71 conservé) puis le remplissage IA complète, CORRECTEMENT, à l'effectif de la SALLE (§8.87) : 4. Pendant ce temps le Centre de Commandement continuait d'afficher « 6 JOUEURS » (l'effectif du MODE). Le remplissage IA est donc HORS DE CAUSE (`test_bot_flow.py` re-passé : 57 ✅).
> - **[`lobby_screen.gd`](scripts/ui/lobby_screen.gd) — le MODE fait foi (miroir du principe classé §8.88)** : nouvelle garde `_restrict_map_selector_to_mode()` (branche casual du `_ready` ; le mode classé garde son verrouillage total). Toute carte dont les bornes ne couvrent pas l'effectif du mode est **DÉSACTIVÉE dans le sélecteur**, avec **infobulle d'item** « MAX N JOUEURS » (nouvelle clé i18n **`LOBBY_MAP_MAX_PLAYERS`** fr/en/it). Garde d'avenir : si la carte déjà retenue devenait incompatible, retour à la carte par défaut (`classic_42`, couvre 3-6). Les clamps de `_create_headcount()` et du serveur RESTENT en défense en profondeur (aucun contrat réseau modifié).
> - **Radar : étanchéité CLASSÉE ↔ casual** : le filtre ne comparait QUE `max_players` — à capacité égale (5), le mode FIVE listait aussi les salles CLASSÉE (et réciproquement : une salle casual 5 apparaissait en mode CLASSÉE, faussant l'attente de ladder). Il exige désormais AUSSI `is_ranked == intention du mode` (`room.get("is_ranked", false)` DÉFENSIF : backend antérieur à §8.88 → traité casual, aucune régression d'affichage).
> - **Validation.** Éditeur OUVERT → réimport via MCP `op=scan` (jamais la CLI `--import` en parallèle de l'éditeur) : 0 erreur, `.translation` fr/en/it régénérés ; clé vérifiée par `get_message()` (script jetable supprimé) ; boots headless `main_menu` + `lobby_screen` **0 ERROR** ; backend INCHANGÉ. ⚠️ Correctif **100 % client** → invisible en jeu packagé tant que le build/patch n'est pas ré-exporté (piège `latest_patch.pck`). **AUCUN COMMIT** (règle absolue).
> - **Retouche même jour (retour Hakim : « interface déréglée en FIVE/EXA »)** — la V1 suffixait le LIBELLÉ de l'item désactivé ; or l'`OptionButton` se dimensionne sur l'item le plus LONG (`fit_to_longest_item`) → le **Centre de Commandement** s'élargissait dans les seuls modes FIVE/HEXA. Correctif : libellés d'items INTACTS, l'explication passe en **infobulle** (`get_popup().set_item_tooltip`) — le panneau garde une taille IDENTIQUE dans tous les modes (boots re-validés 0 ERROR, clés re-vérifiées par `get_message()`). Au passage, le mode 6 joueurs est **renommé « HEXA »** (valeurs fr/en/it de la clé `MENU_MODE_EXA` — la CLÉ i18n et l'id interne `exa` restent INCHANGÉS : zéro retouche code/télémétrie/`match_config`).

### 8.104. Refonte des identités de factions + i18n INTÉGRALE du contenu statique (Frontend, 2026-07-18)
> **Demande Hakim : tout le contenu statique multilingue + factions à nom propre stylé (EN) menées par un héros nommé (Général/Capitaine).** Volet réseau : §8.104 de `CONTRAT_RESEAU.md`. **AUCUN COMMIT** (working tree).
> - **Identités.** `FactionData` += `desc_key`, `power_key`, `hero_name`, `hero_callsign`, `hero_rank` (`"general"`|`"captain"`). `name` = **nom propre EN invariant** (identique dans les 3 langues) ; les 10 `.tres` sont à jour (fichiers NON renommés — `FALLBACK_PATHS` intactes) : Steel Phalanx (Général Viktor « Ironline » Stahl), Dust Reavers (Capitaine Malik « Duststorm » Sarran), Aegis Corporation (Général Adrian « Aegis-One » Cross), Isotope Covenant (Capitaine Ezra « Halflife » Voss), Hive Ascendant (Capitaine Nyx « Synapse » Vireo), Scrap Barons (Général Kord « Rustlord » Maddox), Ash Flayers (Capitaine Diego « Cinder » Vasquez), Eden Wardens (Générale Lyra « Verdant » Thorn), Shadow Hunters (Capitaine Sable « Ghost » Renko), Eclipse Order (Général Kael « Omen » Draven). Helper partagé `WarzoneUI.faction_leader_title(f)` (rang via `TranslationServer`, nom/callsign invariants) — affiché au **draft** (ligne sous le nom, pattern `_ensure_access_banner`), à l'écran **Personnages** (sous l'en-tête), au **Rapport Post-Op** (panneau identité héros, via `main._faction_info().leader`).
> - **i18n intégrale (~330 clés NEUVES dans `ui_strings.csv`, fr/en/it).** (1) **Arène** : `main.tscn` + `hud.gd` + `main.gd` (instructions, journal `_format_event` → clés `EVT_*`, popups Éclipse/espion, conquête, phases `PHASE_*`/étapes `STAGE_*`, barre d'info — le nom de faction AFFICHÉ vient de `hud.faction_name_by_pid`, poussé par `_push_factions_intel`, plus d'id brut) ; War Feed `war_feed.gd` → `FEED_*` + traitement des `system_events` (traduction locale, legacy en repli). (2) **Territoires/continents/cartes** : clés `TERR_<ID>` (42), `CONT_<ID>` (6), `MAP_*_LABEL` — helpers **`MapData.t_name()/c_name()/map_label()`** (tr + repli sur le `name` FR historique) ; tous les affichages passent par eux (plateau `board.gd`, toasts, war room, télégraphe). (3) **Rapport Post-Op** (`REPORT_*`), **managers** (`NET_*`/`AUTHM_*` — messages d'erreur traduits AU POINT D'ÉMISSION), **composants** (`OBJ_*`, `CHIP_*`, `DIVISION_ELITE`, `SHOP_PRICE_EUR_FMT`, gap `SECTION_SOON_*`/`NAV_*` comblé). (4) **Options** : segments combat `SETTINGS_COMBAT_*` (ex-« CINÉMATIQUE/RAPIDE/BANDEAU » en dur) + **reconstruction à chaud** de la section confort sur `locale_changed` (`_on_locale_changed_rebuild`). (5) **Objectif local** composé en langue courante par `objective_tracker.describe(type/params)` (HUD + tooltip tracker), clés `OBJ_DESC_*`.
> - **Écrans héros.** `characters_screen.gd` : nom de faction depuis le **.tres local** (source unique — l'écran affichait le nom backend, divergent pour 3 factions) ; pouvoir héros via `HERO_POWER_NAME/DESC_<ID>` (repli backend) ; ligne d'identité du meneur. `hero_stats_view.gd` : encadré « POUVOIR » via les mêmes clés (`_power_text`). `split_screen_vs` : rôles via `VS_ROLE_*_SHORT`.
> - **Boutique** : articles de déblocage de faction et skins re-libellés sur les noms EN invariants (valeurs `SHOP_ITEM_*` du CSV).
> - **Validation.** `--import` **0 ERROR** (les 3 `.translation` régénérés) ; boots headless `main_menu` / `settings` / `faction_selection` / `game/main` **0 ERROR** ; audit de clés : **0 manquante, 0 doublon** (821 lignes CSV). Backend : `test_factions`, `test_hero_stats`, `test_hero_faction_draft`, `test_state_redaction`, `test_heroes_roster` (contrat +3 clés), `test_deploy_contamination` + `test_objectives_double` (assertions alignées EN), `test_bot_ai`, `test_hero_combat`, `test_attack_event_identity`, `test_turn_loop_fixes`, `test_telemetry`, repro ×3, `test_victory_reason`, `test_game_over_redaction`, `test_setup_phase`, `test_map_registry` → **tous verts** (`test_simulation` : échec d'environnement préexistant, `fastapi` absent de l'interpréteur local).
> - ⚠️ **Pièges.** Les libellés construits PAR CODE ne se re-traduisent pas seuls au changement de langue (contrairement aux nœuds `.tscn`) → l'écran Options reconstruit sa section confort ; les écrans transitoires (arène) sont recréés à chaque partie. `war_feed`/`objective_tracker`/`hero_stats_view` sont des modules **statiques** → `TranslationServer.translate()` (pas `tr()`).

### 8.105. Objectifs révélés traduits + identité du meneur au Split-Screen VS (Frontend, 2026-07-18)
> **Les 2 finitions de §8.104** (demandées après recette). Volet réseau : §8.105 de `CONTRAT_RESEAU.md`. **AUCUN COMMIT**.
> - **Objectifs révélés/espionnés dans la langue du joueur.** `NetworkManager.spy_result` passe à **3 arguments** `(target_player_id, description, objective)` — `objective` = forme structurée serveur, `{}` si serveur antérieur (**seul consommateur : `main._on_spy_result`**). NEUF `main._objective_text(objective, fallback)` : compose via `ObjectiveTracker.describe()` en résolvant le **pseudo** de la cible du volet « tuer » (`params.target_id` → `_display_name`, sinon « #id »), et **retombe sur la description serveur** si la forme est absente ou d'un type inconnu. Branché aux **deux** sites : espionnage (chat privé + journal) et **podium du Rapport Post-Op** (`_podium_rows`, ex-`str(rev.description)`).
> - **Identité du meneur au VS.** `_load_faction` expose `leader` (`WarzoneUI.faction_leader_title`) ; NEUF `_apply_leader_line(is_left, name_label, leader, accent)` insère « GÉNÉRAL VIKTOR "IRONLINE" STAHL » **sous le nom de faction**, aligné à droite côté défenseur (comme la chip de niveau). **Idempotent** (nœud réutilisé par `get_node_or_null` → aucun doublon si l'écran est re-peuplé), **masqué** si `leader` vide (.tres legacy → layout strictement inchangé), position recalculée **à l'insertion** (robuste à la chip insérée avant le nom), `auto_translate_mode = DISABLED` (contenu dynamique : rang déjà traduit + nom propre invariant). Repli faction inconnue : `GAME_FACTION_UNKNOWN` (ex-« Faction Inconnue » en dur).
> - **Validation RUNTIME (pas seulement la compilation).** Scène de test headless temporaire (créée, exécutée, **supprimée dans le même bloc**) : **17/17 ✅, 0 ERROR**. (1) Objectif composé depuis le payload EXACT de `public_shape` en **fr/en/it** — « Tuer le héros de RAIDER-7 — OU — Contrôler au moins 24 territoires. » / « Kill RAIDER-7's hero — OR — … » / « Uccidi l'eroe di RAIDER-7 — O — … » —, pseudo de la cible injecté, repli forme vide, volet simple traduit. (2) VS : lignes meneur présentes des 2 côtés en fr **et** en, **rang traduit** (GÉNÉRAL↔GENERAL, CAPITAINE↔CAPTAIN) avec **nom/callsign invariants** (VIKTOR "IRONLINE" STAHL, SABLE "GHOST" RENKO), **nom de faction invariant** (STEEL PHALANX), **aucun doublon** après re-peuplement. `--import` **0 ERROR**.
> - ⚠️ **Piège.** `ObjectiveTracker.describe` rend `""` sur un type inconnu : TOUJOURS l'appeler via `_objective_text` (qui gère le repli), jamais directement sur un objectif venu du réseau.

### 8.106. Refonte PROFIL — hub à onglets (identité + division précise + 5 onglets) (Frontend, 2026-07-19)
> **Chantiers K→O de `PROMPT_PROFIL_REFONTE.md`.** L'écran Profil passe d'un flux vertical unique à un **hub à onglets**. Volet réseau : §8.106 + §9.1 réécrit de `CONTRAT_RESEAU.md`. Description d'écran : **§R2** ci-dessus. **AUCUN COMMIT**.
> - **Cadre & en-tête.** `MainPanel` 1040×760 → **1360×900**. L'ex-`HeaderBar`/`LevelBox`/`StatsGrid`/`HistoryScroll` sont remplacés par un **en-tête d'identité PERMANENT** (joueur à gauche, **carte DIVISION** à droite) + un `TabContainer`. La faction favorite **quitte l'en-tête** pour devenir une carte de l'onglet APERÇU (l'en-tête est réservé à l'identité et au rang).
> - **Carte DIVISION** : badge hexagonal (`WarzoneUI.make_hex_badge`), libellé « OR II » via `DIVISION_TIER_FMT`, RP, barre d'échelon **masquée si `tier_span == 0`** (ÉLITE *ou* repli — aucune distinction à faire côté rendu), rang mondial, « J-N ». Repli legacy complet sur `/auth/me`.
> - **Onglets** : `TabContainer` stylé en **miroir de `operation_report._style_tabs`** (même langage sur les deux écrans à onglets du jeu). **Chargement LAZY** par onglet (`_loaded_tabs`) — FINANCES et PASS ne sont demandés qu'à leur première ouverture.
> - **Courbe RP** : `Control` + `draw_polyline`/`draw_circle` **natifs**, dessin branché sur le **signal `draw`** (émis pendant la notification de dessin → les appels `draw_*` y sont valides) plutôt qu'un script dédié pour un seul graphique. Quadrillage discret, axe réduit aux bornes min/max.
> - **NetworkManager** : `fetch_profile_finance` / `fetch_profile_pass` NEUFS ; `fetch_profile_history` gagne `offset` / `wins_only` / `ranked_only` **à défaut neutre** (l'appel `fetch_profile_history(5)` de `main_menu` et `top_nav` produit exactement la requête d'avant).
> - ⚠️ **PIÈGE MAJEUR — signal d'historique partagé.** `profile_history_loaded` est aussi écouté par **`top_nav`, monté sur TOUS les écrans, Profil COMPRIS**. Servir à ces écouteurs la liste FILTRÉE demandée par l'onglet HISTORIQUE ou la courbe RP leur ferait afficher un héros/récap FAUX. Solution : le signal legacy n'est émis **QUE pour une requête non filtrée** (`offset == 0`, aucun filtre), et un signal NEUF `profile_history_page_loaded(entries, request)` **échoie la requête** — l'écran route ses réponses en comparant la requête reçue à celle qu'il a émise (`_pending_history_req` / `_pending_rp_req`), jamais par ordre d'arrivée.
> - ⚠️ **PIÈGE — `Callable.bind()` s'empile À L'ENVERS.** `_send_api_request` fait `callback.bind(http)` sur un callable **déjà** lié par `.bind(request)` : un second bind **insère ses arguments AVANT** ceux du premier (`f.bind(a).bind(b)` → `f(args…, b, a)`). La signature correcte est donc `(…, http_node, request)`. Inversée, la **toute première ligne** (`http_node.queue_free()` sur un `Dictionary`) échouait : la réponse n'était jamais relayée **et** le nœud `HTTPRequest` fuyait à chaque appel. **Trouvé uniquement par le test runtime** — la compilation et le boot à vide passaient tous les deux.
> - ⚠️ **PIÈGE — `DIVISION_LABELS`.** Seule ÉLITE a une clé i18n (`DIVISION_ELITE`) ; BRONZE/ARGENT/OR/PLATINE s'affichent **tels quels**. Leur inventer des clés faisait afficher « DIVISION_BRONZE » à l'écran (`tr()` sur une clé absente renvoie la clé). Constante **copiée à l'identique** de `leaderboard.gd`.
> - **Coins : aucun glyphe.** Le prompt proposait « ◈ » ; on a retenu la convention **réelle du jeu** (boutique) — le nombre seul dans un **badge hexagonal or** — pour éliminer tout risque de « tofu » sur une police condensée. Idem pour la pastille de faction : **carré** (ADN angulaire), jamais un rond ni une puce emoji.
> - **i18n : 74 clés NEUVES** en fr/en/it (`ui_strings.csv`, LF/UTF-8 sans BOM — le fichier n'est **pas** en CRLF). Ordinaux `ᵉ`/`ʳ` conservés : déjà utilisés sans problème par `LEADERBOARD_RULES_PLACE`. `PROFILE_DATE_SHORT_FMT` utilise des **placeholders nommés** `{day}`/`{month}` pour que l'anglais puisse inverser l'ordre.
> - **VALIDATION RUNTIME (pas seulement la compilation).** Scène de test headless temporaire (créée, exécutée, **supprimée dans le même bloc**) injectant des payloads complets : parcours des 5 onglets, 3 filtres d'historique, 2 vues de statistiques, Pass actif **et** inactif, `kind` d'avantage inconnu, raison de ledger inconnue, faction inconnue du client, ligne d'historique legacy, puis **repli TOTAL** (bloc `season` absent + les 2 endpoints en 404) et re-parcours des 5 onglets. **0 ERROR.** `--import` **0 ERROR** ; boot de `profile.tscn` **et** `main_menu.tscn` **0 ERROR**.
### 8.107. Stats PAR CARTE + écran PROFIL PUBLIC (Frontend, 2026-07-19)
> **Options 1 et 2 du §9, validées par Hakim.** Consigne : **strictement ADDITIF — l'écran Profil livré en §8.106 n'est pas modifié**. Volet réseau : §8.107 + §9.1 de `CONTRAT_RESEAU.md`. **AUCUN COMMIT**.
> - **Onglet STATISTIQUES : 3ᵉ chip « PAR CARTE »** (§8.107). Les deux vues existantes (PAR PERSONNAGE / PAR MODE) sont **inchangées** — la commutation passe d'un `if/else` à un `match`, seul ajout. Rangée par carte : nom résolu localement (`MAP_LABELS` → `MAP_CLASSIC_LABEL` / `MAP_ATLANTIC_LABEL`, déjà présentes), volume, barre de winrate, place moyenne. Note d'honnêteté **inconditionnelle** (`PROFILE_MAP_LEGACY_NOTE`) : le serveur exclut les matchs sans carte connue et le client ne peut pas savoir combien — le dire simplement vaut mieux que de laisser croire à un total.
> - **ÉCRAN NEUF `public_profile.tscn` + `public_profile.gd`** — profil PUBLIC d'un autre joueur. **Écran séparé, PAS un mode de `profile.tscn`** : l'écran personnel est validé et ne doit pas être touché. Les fabriques de style y sont donc dupliquées, ce qui est la **convention du dépôt** (profile.gd, shop.gd, leaderboard.gd ont chacune les leurs).
>   - Contenu : identité + carte division, palmarès (parties/V/D/ratio/tribut/faction favorite), bande de forme, par mode, par personnage, par carte. **Ni finances, ni Pass** — et le serveur ne les renvoie même pas pour un tiers.
>   - ⚠️ Commentaire de garde en tête du script : **ne JAMAIS y appeler `/profile/finance` ou `/profile/pass` « pour compléter l'écran »** — ces routes ne lisent que l'utilisateur AUTHENTIFIÉ, elles afficheraient donc VOS données sous le nom de quelqu'un d'autre.
> - **Accès UNIQUE : une ligne du Classement.** `_make_ranking_row` gagne curseur main + infobulle + `gui_input` — **le rendu de la ligne n'est pas touché**, c'est un pur ajout en fin de fabrique. ⚠️ **Corrigé en §8.118 :** le pseudo se lit sur la clé **`"name"`** (celle que produit `_map_entry`), et **pas** `"username"` — la version livrée ici lisait une clé inexistante, donc la ligne n'a JAMAIS été cliquable et cet écran est resté **inatteignable** jusqu'au §8.118. La ligne est en outre **inerte en repli mock « HORS LIGNE »** (§8.96) : on ne route pas vers le profil public d'un pseudo fictif.
> - **Transport du pseudo :** `static var target_username` sur le script de l'écran cible. `TransitionManager.change_scene` ne transporte aucun paramètre, et cette voie évite d'ajouter un champ étranger à un autoload existant (**aucune modification de l'existant**).
> - **Anti-réponse croisée :** `public_profile_loaded` échoie le pseudo demandé ; l'écran **ignore** une réponse dont le pseudo ne correspond pas (le joueur peut cliquer deux lignes de suite). Même principe que `profile_history_page_loaded` (§8.106).
> - **i18n : 6 clés NEUVES** en fr/en/it.
> - **VALIDATION RUNTIME.** Sonde headless temporaire (créée, exécutée, **supprimée dans le même bloc**) : vue PAR CARTE (données réelles, **carte inconnue du client** → id brut sans crash, état vide) ; profil public **nominal**, **réponse d'un AUTRE pseudo ignorée**, **introuvable (404)**, **accès direct sans pseudo** ; ligne de classement **cliquable** (curseur + signal branché). **0 ERROR.** `--import` **0 ERROR** ; boot de `profile`, `public_profile`, `leaderboard`, `main_menu`, `shop` → **0 ERROR**.

### 8.110. BOUTIQUE — vitrine des 3 Pass, gate des skins, états d'accès (draft / personnages / profil) (Frontend, 2026-07-19)
> **Chantiers S, T, U de `PROMPT_BOUTIQUE_REFONTE.md`.** Volet réseau : **§8.108 / §8.109 / §9.3** de `CONTRAT_RESEAU.md`. **AUCUN COMMIT**.
>
> ⚠️ **CHANTIER S.1 SAUTÉ — décision de Hakim.** Le prompt décrivait `shop.gd` comme ayant « DEUX onglets (BOUTIQUE/INVENTAIRE) » et une « grille plate sans sections », et demandait d'y ajouter une rangée de chips de filtre. **Ce constat était périmé** : §8.102 a déjà livré **QUATRE onglets de catégorie** (PERSONNAGES / SKINS / PASS / COINS) qui filtrent sur `item.category` — le but fonctionnel de S.1 était donc déjà atteint. On ne réécrit pas une UI livrée et documentée : seuls **S.2 à S.6** ont été implémentés.
>
> - **`shop.gd` — vitrine des 3 Pass.** Les avantages proviennent des **`perk_keys` SERVEUR** (`pass_catalog`) : le `for i in range(1, 5)` codé en dur a disparu, et le client n'écrit plus **aucun chiffre du barème** — rééquilibrer un Pass ne touche pas une ligne de GDScript. Repli sur les 4 clés historiques si le serveur ne les fournit pas.
>   - **Hiérarchie visuelle** : badge « ★ POPULAIRE » sur le niveau intermédiaire (constante `POPULAR_PASS_TIER` — c'est un choix de MERCHANDISING, pas une donnée dérivable, donc isolé pour se changer en une ligne) ; **liseré or COMPLET** sur le niveau de rang le plus élevé, là où toutes les autres cartes n'ont qu'une arête gauche.
>   - **États par carte**, dérivés de `rank` (serveur) comparé au `pass_tier` détenu : niveau détenu → badge « PASS ACTIF · J-N », **aucun bouton** ; rang INFÉRIEUR → « INCLUS DANS VOTRE PASS » (grisé) ; rang SUPÉRIEUR → « AMÉLIORER ❯ ». ⚠️ Le badge « actif » ne s'affiche **que** sur la carte du niveau réellement détenu — l'afficher sur les trois (comportement de l'ancien code à un seul Pass) laisserait croire qu'elles sont toutes acquises.
> - **Gate des SKINS (S.3).** Un skin dont le personnage n'est possédé que **temporairement** (rotation, Pass) affiche « ✕ Nécessite le personnage : X » à la place du CTA. Les factions payantes sont **dérivées du catalogue** (`category == "faction"`), jamais listées en dur. Le serveur refuse de toute façon (`400`) : ce verrou explique **pourquoi** au lieu de laisser l'achat échouer.
> - **Rotation (S.4).** Bannière et badge affichent le **crédit restant** dès que le serveur le fournit (« ★ GRATUITE — 3/5 PARTIES ») ; à 0 crédit, le badge passe en **muet** (« PARTIES GRATUITES ÉPUISÉES »). Compteur absent (visiteur anonyme / serveur antérieur) → libellé historique, jamais un faux « 0/5 ».
> - **Gate 501 (S.5).** `network_manager` expose **`last_purchase_http_code`** ; on n'a **PAS** ajouté de paramètre au signal `shop_purchase_failed`, ce qui aurait cassé toute callable déjà connectée. Un 501 devient « Paiements réels bientôt disponibles. » au lieu du message technique du serveur.
> - **`characters_screen.gd` (T.2)** — 4 états au lieu du seul cadenas : `free`/`owned` → rien ; `rotation` → chip **or** « ★ n/m » ; `pass` → chip **cyan** « PASS » ; `locked` → cadenas ✕ + **prix en infobulle**. Le chip réutilise la fabrique de la charte (encoches, filet 1 px). Dans le **panneau de détail**, un accès temporaire affiche une **ligne d'avertissement** : la progression sera perdue à la fin de l'accès (honnêteté indispensable vu la purge §8.109 — le joueur doit le savoir AVANT d'investir des heures).
> - **`faction_selection.gd` (T.3)** — bannières d'accès enrichies, **du cas le plus spécifique au plus général** : crédits épuisés (verrouillé + prix) → rotation avec compteur → **débloquée par le Pass** (cyan : jouable mais TEMPORAIRE) → verrouillée → rien. `_is_locked` intègre désormais les grants de Pass et l'épuisement du crédit.
> - **`profile.gd` (U)** — carte **« PERSONNAGE GRATUIT DE LA SEMAINE »** dans l'onglet **APERÇU** : pastille à la couleur signature + nom, **jauge à 5 pips** (◆ or = partie disponible, ◇ muet = consommée), « n/m PARTIES RESTANTES », « NOUVEAU PERSONNAGE DANS J-n ». Masquée si la rotation est inconnue ou le joueur non authentifié (aucune jauge inventée). ⚠️ Placée **AVANT** la bande de forme : celle-ci sort de la fonction par un `return` quand l'historique est vide, ce qui masquait le widget pour un **nouveau** joueur — précisément sa cible.
> - **GLYPHES — mesure avant décision.** Le prompt demandait 🔒 et ✦. Comptage sur `ui_strings.csv` : emoji cadenas **0** (purge §8.102), ✦ **0**, mais ★ **36**, ⚠ **15**, ✕ **6**, ❯ **216**. On s'en tient donc aux glyphes **éprouvés** (✕ verrou, ★ rotation, ⚠ avertissement) et le chip PASS se distingue par la **couleur** (cyan) : un dingbat inconnu de la police condensée produit du tofu (cf. « ⏻ » hérité).
> - **Doublon repéré EN CAPTURE et corrigé.** Le prompt demandait à la fois un perk « déblocage personnages » **et** une mention « nombre de personnages débloqués » : à l'écran, la même phrase apparaissait deux fois sur chaque carte. On garde la version SERVEUR (data-driven) et on supprime la ligne cliente (+ ses 3 clés i18n). Libellés « PASS SPÉCIAL » → **« PASS »** (il y a 3 niveaux ; l'ancien article est retiré de la vente).
> - **Outil `tools/preview_shop_v2.gd` remis à niveau** (catalogue miroir du seed, 3 Pass, compteurs de rotation, scénario Pass PLUS actif) et **2 bugs préexistants corrigés** : appel à `_on_history_loaded`, **renommé `_on_history_page_loaded` en §8.106** (SCRIPT ERROR à chaque exécution), et chemin de sortie absolu figé sur une session morte → variable d'environnement **`WW_PREVIEW_OUT`** avec repli `user://`.
> - ⚠️ **DEUX PIÈGES DE VALIDATION VISUELLE, rencontrés l'un après l'autre.** (1) Éditer un `.gd` **après** un `--import` ne suffit pas : sans **ré-import**, c'est le script du cache qui s'exécute. (2) Le `_ready()` de `shop.tscn` lance de **vrais fetchs** : quand un backend est joignable, sa réponse **écrase** les données de démonstration ~1 s plus tard — on capture alors le catalogue du serveur **DÉPLOYÉ** (donc périmé tant que le VPS n'est pas redéployé) en croyant valider le code local. L'outil injecte désormais **après** que le réseau ait parlé. C'est aussi ce qui a **confirmé** que le VPS sert encore l'ancien catalogue.
> - ⚠️ **`Array` = RÉFÉRENCE en GDScript (trouvé en revue).** Le repli des `perk_keys` faisait `var perks := item.get("perk_keys", [])` puis `perks.append(...)` : il écrivait donc les clés de repli **dans l'entrée de `_catalog`**, faisant diverger silencieusement l'état client de ce que le serveur avait envoyé. Corrigé par `.duplicate()`.
> - **i18n : 28 clés** ajoutées/mises à jour en fr/en/it (954 au total), 3 supprimées (doublon ci-dessus).
> - **VALIDATION.** `--import` **0 ERROR** ; boot headless **0 ERROR** sur `shop`, `characters_screen`, `profile`, `main_menu`, `faction_selection` ; **captures PNG** des 4 onglets boutique + Profil conformes aux critères d'acceptation (gate skin visible sur Eclipse, « ★ GRATUITE — 3/5 PARTIES », **3 pips pleins sur 5** avec « 3/5 PARTIES RESTANTES »).
### 8.111. Refonte PERSONNAGES — roster en cartes + fiche à 4 onglets (Frontend, 2026-07-20)
> **But.** L'écran Personnages était une **liste verticale + un panneau de détail** : le titre affiché
> était le nom de la FACTION (les personnages n'avaient pas d'identité à l'écran), et toute
> l'information tenait dans une seule colonne défilante. Il devient un **ROSTER en grille de cartes**
> (chantier W) ouvrant une **FICHE à 4 onglets** (chantiers X/Y), personnage en grand à gauche.
> Chantiers V (backend) et W (roster) livrés dans une passe antérieure ; **X/Y/Z ici**.
>
> - **Identité enfin affichée.** Les cartes et l'en-tête de fiche portent le **nom du personnage**
>   (`identity.display_name` de `GET /api/v1/heroes`, chantier V) et non plus le nom de faction —
>   les deux vues désignaient jusqu'ici la même entité par deux noms différents. En-tête de fiche :
>   `PRÉNOM NOM` (34 px) + indicatif entre guillemets.
> - **Le code dossier `CHAR-NNN` n'est PAS affiché** (arbitrage produit, après capture) : c'est une
>   référence de PRODUCTION (registre `factions.py`, `TEMPLATE_PERSONNAGES.md`), pas une information
>   de jeu — elle encombrait la ligne de titre sans rien apprendre au joueur. `identity.char_code`
>   reste servi par `/heroes` : rien à changer côté serveur, et la ligne est réaffichable en une fois.
> - **i18n — `CHAR_ACCESS_OWNED` désambiguïsé** (arbitrage produit) : FR « POSSÉDÉ » → **« ACQUIS »**,
>   IT « POSSEDUTO » → **« IN POSSESSO »**, EN « OWNED » inchangé (déjà sans ambiguïté).
>   « POSSÉDÉ » se lisait aussi au sens *démoniaque*, et « POSSEDUTO/POSSEDUTA » imposait un accord
>   de genre. **« ACQUIS » est le participe du verbe déjà employé par la Boutique** (`SHOP_BUY`
>   « ❯ ACQUÉRIR », `SHOP_ACQUIRED` « // ACQUIS : %s ») — vocabulaire cohérent, pas un néologisme.
>   ⚠️ **« DÉBLOQUÉ » a été écarté** : le terme désigne déjà l'accès **temporaire** par Pass
>   (`CHAR_ACCESS_PASS`, `FS_PASS_UNLOCKED`) — l'employer pour la possession DÉFINITIVE aurait
>   recréé l'ambiguïté qu'on supprimait. ⚠️ Volontairement NON touchés : `CHAR_ROSTER_COUNT`
>   (« PERSONNAGES POSSÉDÉS » / « PERSONAGGI POSSEDUTI », pluriel) et `CHAR_SKIN_OWNED`
>   (« POSSEDUTA », féminin car il qualifie une *skin*).
> - ⚠️ **Valider une chaîne FR sur cette machine exige de FORCER la locale** (`TranslationServer.
>   set_locale("fr")` dans le harnais de capture) : le poste rend en **italien** par défaut, on
>   validerait donc une autre langue que celle qu'on vient d'éditer.
> - **Pouvoir expliqué au joueur (onglet INFORMATIONS).** L'encadré POUVOIR ne montrait que le
>   libellé technique (« Frappe d'Acier — PA élevé et plafond de PP maximal ») : parlant pour qui
>   connaît déjà les sigles, opaque pour un nouveau venu. Ajout de **10 clés `HERO_POWER_HINT_<FID>`**
>   (fr/en/it) — une phrase par personnage qui dit l'AVANTAGE EN PARTIE **sans nommer une seule
>   statistique**, rendue sous le libellé en muet 13 px : l'habitué lit la 1ʳᵉ ligne et s'arrête, le
>   débutant lit la 2ᵉ. `_make_power_panel(power, accent, hint := "")` — le défaut vide fait que
>   **l'onglet STATISTIQUES, déjà dense, garde l'encadré court** sans condition à écrire.
>   `_hero_power_hint()` renvoie `""` si la clé manque : une faction non rédigée n'affiche jamais sa
>   clé brute. ⚠️ **Textes ADOSSÉS aux stats réelles du registre**, pas au libellé existant — celui-ci
>   contient deux approximations relevées au passage (`PHALANGES_ACIER` annonce un « plafond de PP
>   maximal » à 16 quand pillards/chasseurs sont à 18 ; `PILLARDS_POUSSIERE` annonce un « PA maximal »
>   à 37 quand chasseurs est à 40). Les nouvelles phrases ne les reprennent pas ; les anciens
>   libellés n'ont pas été touchés (hors périmètre).
> - **POUVOIR DE FACTION dans l'onglet STATISTIQUES.** L'écran ne montrait que le pouvoir du HÉROS
>   (son profil de combat) ; la **mécanique de plateau** — relance de dé, double en défense, unité
>   bonus de renfort… — n'était visible qu'au draft et en partie. Elle est ajoutée SOUS les
>   caractéristiques chiffrées (c'est une donnée de comparaison, on la lit avec les stats), avec un
>   en-tête distinct `CHAR_FACTION_POWER_HEADER` « POUVOIR DE FACTION » pour qu'aucune confusion ne
>   soit possible avec « POUVOIR DE HÉROS » juste au-dessus. **Aucune chaîne créée** : `_faction_power_text()`
>   lit le `power_key` du `.tres` local, **MÊME source et MÊME repli que le draft**
>   (`faction_selection._dossier_text`) et que la partie (`main.gd`) — le texte est donc mot pour mot
>   celui du draft, et il n'y a pas de 3ᵉ chemin à maintenir. ⚠️ `/heroes` ne sert PAS ce champ (il ne
>   porte que le pouvoir du héros), d'où la lecture locale. Clé vide / `.tres` legacy / clé absente du
>   CSV → chaîne vide → **section entière omise**, jamais une clé brute à l'écran. Vérifié : les 10
>   factions résolvent leur pouvoir.
> - **Hiérarchie typographique de la carte (demande produit).** Nom du personnage **22 px** (blanc
>   froid, 2 lignes max) contre **11 px** pour la faction, cette dernière passée du gris muet à la
>   **couleur d'accent de sa faction** — même signal que le liseré gauche et les encoches de la
>   carte, donc trois rappels cohérents. `CARD_SIZE` porté de `(200, 260)` à `(200, 286)` : sans ça
>   les cartes à nom long dépassaient leur taille minimale et déformaient leur rangée.
> - **Fiche en deux colonnes (`SheetBody` passé de `VBoxContainer` à `HBoxContainer`).** Personnage
>   à **gauche, 42 %** de largeur et pleine hauteur (~517×660 px au lieu d'une bande de 300 px) :
>   `hero_viewport_3d` est un `SubViewportContainer` plein-cadre `stretch = true`, il remplit donc le
>   nouvel emplacement sans réglage. Ajout d'un **présentoir** (`_stage_frame`) — fond gunmetal +
>   liseré à la couleur effective (faction, ou skin prévisualisé) + encoches : sans lui le héros
>   « flottait » dans le panneau. Identité + onglets à **droite, 58 %**.
> - **4 onglets** (`TabContainer`, pattern et `_style_tabs` repris VERBATIM du Profil §8.106) :
>   **INFORMATIONS** (progression XP, palmarès `record`, pouvoir encadré, état d'accès détaillé),
>   **STATISTIQUES** (PV/PA/PB/PP/Régén en **ACTUEL / RESTANT / NIV. 50**), **ÉVOLUTION** (frise des
>   5 paliers en pastilles hexagonales, XP totale, Coins gagnés, comparatif des 3 Pass),
>   **SKINS**. Aucun chargement différé par onglet : tout vient de données déjà en mémoire.
> - **Colonne DELTA** (`_make_stats_block(hero, show_delta := false)`) : « +228 », « +9 % »,
>   limitée à PV/PA/PB (PP est une fourchette, Régén un taux → « — »). **Le défaut `false` est ce
>   qui garantit que le draft ne bouge pas** — `faction_selection` passe d'ailleurs par
>   `HeroStatsView.build_compact_row`, intouché.
> - **Comparatif des Pass sans aucune constante recopiée.** Les taux par niveau (1-5 / 2-10 / 4-20 /
>   5-25) sont **dérivés** de `evolution.coins_potential ÷ levels_left` — le potentiel étant par
>   construction `niveaux restants × barème`, la division est exacte. Ligne omise au niveau 50
>   (division par zéro) plutôt que remplie de zéros. La colonne du Pass ACTIF (`pass_tier` de
>   `/shop/inventory`) est surlignée en or.
> - **SKINS avec prévisualisation.** Le clic sur une vignette applique le skin au **grand viewer sans
>   l'équiper** (`_preview_skin`, remis à `""` au changement de personnage et à l'équipement réel) —
>   liseré cyan « APERÇU ». Le mécanisme visuel est celui du **Split-Screen VS** (`SkinData` de
>   `resources/skins/`, duck-typing `id`+`faction_id`, surcharge `portrait_path`/`model_path`/
>   `accent_override`) : aucun 2ᵉ mécanisme à maintenir. Skin catalogué mais sans ressource → teinte
>   déterministe dérivée du hash de l'id (jamais d'image inventée). ÉQUIPER/RETIRER via
>   `equip_skin`/`unequip_skin` ; l'ACHAT reste en Boutique (CTA de redirection).
> - ✅ **Aucun paramètre serveur à ajouter.** Le prompt demandait `?include_exclusive=true` sur
>   `/shop/catalog` pour voir les skins exclusifs Pass : **`?include_all=1` existe déjà** (§8.102) et
>   `NetworkManager.fetch_shop_catalog()` le passe déjà. Réutilisé tel quel.
> - **Navigation.** Flèches `❮`/`❯` (personnage précédent/suivant, **boucle** via `posmod` — un
>   modulo brut donnait `-1` au premier « précédent ») **en conservant l'onglet actif**. `_unhandled_input` :
>   **ÉCHAP ferme d'abord la FICHE** (`set_input_as_handled()` empêche `top_nav` de voir l'évènement) —
>   avant, ÉCHAP depuis une fiche quittait l'écran entier ; ←/→ changent de personnage.
> - **★ FAVORI** devient un bouton explicite de la fiche (remplace la persistance « au clic sur la
>   carte », chantier F §8.93) ; re-cliquer le favori courant le RETIRE.
> - **Chemin d'erreur du roster (préexistant, corrigé).** `NetworkManager.lobby_error` n'était pas
>   connecté : un `/heroes` en échec laissait l'écran bloqué **indéfiniment** sur « SYNCHRONISATION… ».
>   Message + bouton `COMMON_RETRY` désormais. Une erreur tardive n'efface pas un roster déjà affiché.
> - **Code mort supprimé** après migration : `_populate_detail`, `_make_milestone_row`, l'export
>   `detail_box` et les nœuds `DetailScroll`/`DetailBox`, plus l'entrée `back_button` **fantôme** du
>   `node_paths` de la scène (déclarée, jamais assignée, aucun `@export` correspondant).
> - **i18n : 12 clés** ajoutées en fr/en/it (`CHAR_SECTION_PROGRESSION`, `CHAR_RECORD_WINS/LOSSES`,
>   `CHAR_ACCESS_LOCKED`, `CHAR_EVO_XP_TOTAL`, `CHAR_EVO_NO_PASS`, `CHAR_SHOP_CTA`, et les 5
>   `FACTION_CATEGORY_*`). Les blocs `CHAR_TAB_*`/`CHAR_EVO_*`/`CHAR_SKIN_*` étaient déjà provisionnés.
> - ⚠️ **DEUX DÉFAUTS TROUVÉS EN CAPTURE, pas à la lecture.** (1) Le titre « PROGRESSION » sortait
>   **en double** dans l'onglet INFORMATIONS : `_make_xp_block` pose déjà son propre en-tête de
>   section. (2) Le chip « PROCHAIN — dans N niveaux », posé en FRÈRE de droite d'une colonne en
>   `EXPAND_FILL`, était **poussé contre le bord et rogné** dès que la traduction s'allongeait
>   (visible en italien : « PROSSIMO — tra 8 livelli ») → déplacé DANS la colonne. Un boot headless
>   à 0 ERROR ne dit rien de la mise en page : seule la capture les a montrés.
> - **VALIDATION.** `--import` **0 ERROR** ; boot headless **0 ERROR** sur `characters_screen`,
>   `faction_selection` (draft intact), `main_menu`, `shop` ; backend `test_heroes_roster.py`
>   **483 ✅ / 0 ❌** ; **6 captures** (roster, les 4 onglets, bas de l'onglet ÉVOLUTION) relues une
>   à une, dont la contre-vérification que les taux dérivés du comparatif donnent bien 1-5 / 2-10 /
>   4-20 / 5-25 et que la colonne PREMIUM se surligne pour un joueur de ce tier.

---

> **§8.112 — Nettoyage « points de match » + zéro 4xx client + REJOUER fidèle (chantiers AA/AB/AC, `PROMPT_NETTOYAGE_SECURITE.md`).**
> - **Rapport Post-Op sans « points de match » (AA).** Le bloc RÉCOMPENSES ne montre plus AUCUN « point de match » (podium, compteur, détail du barème) — XP joueur, XP héros, Coins et bloc RP inchangés. `main.gd::_podium_rows` ne calcule plus la clé morte `points` (le serveur ne diffuse plus `match_points`). `grep match_points frontend/scripts/` = **0**.
> - **REJOUER = même modalité (AB).** `NetworkManager.requeue()` capture la modalité de la partie TERMINÉE (`GameState.map_id` / `GameState.players.size()` / `NetworkManager.last_match_is_ranked`, replis `MatchConfig`), re-pose l'intention (`MatchConfig.set_mode`), filtre le scan sur carte + effectif + classé, et crée une salle FIDÈLE en dernier recours. Anti-boucle (borne d'essais + salles déjà tentées + chien de garde) CONSERVÉ ; l'épuisement crée désormais une salle au lieu d'échouer au lobby.
> - **Zéro 4xx client (AC).** (1) **Session** : signal `session_expired` + helper central `_check_session` + drapeau `_session_valid` → sur 401/403, UNE redirection vers `auth_screen` (message `AUTH_SESSION_EXPIRED`, token purgé), zéro rafale, aucun retry auto. (2) **Plus de Bearer vide** : l'en-tête `Authorization` n'est ajouté que si un token existe ; une requête AUTHENTIFIÉE sans token (ou après expiration) n'est PAS émise — les endpoints PUBLICS (leaderboard, liste des salles) passent `authenticated=false`. (3) **Polling lobby** : sur échec d'un fetch de salles (signal dédié `rooms_fetch_failed`), le rafraîchissement auto s'ARRÊTE (statut `LOBBY_OFFLINE`), reprise au seul refresh MANUEL réussi ; un échec de join → UN refresh, sans retry. (4) **Contrat join/leave** : lecture défensive `joined`/`reason` (cf. §8.112 de `CONTRAT_RESEAU.md`). (5) **TLS** : certificat VÉRIFIÉ par DÉFAUT (prod, Let's Encrypt) — `client_unsafe()` réservé au dev LOCAL (loopback/plaintext), piloté par `ApiConfig.tls_options()`.
> - **i18n** : 2 clés fr/en/it (`AUTH_SESSION_EXPIRED`, `LOBBY_OFFLINE`).
> - **VALIDATION.** `--import` **0 ERROR** ; boot headless **0 ERROR** sur `auth_screen`, `main_menu`, `lobby_screen`, `waiting_room`, `game/main`. **AUCUN COMMIT.**

---

> **§8.113 — Écran de connexion refondu : « SIGN IN THROUGH STEAM » (`PROMPT_STEAM_AUTH.md`).** Contrat réseau complet et détail backend : **§5 + §8.113 de `CONTRAT_RESEAU.md`**.
> - **`auth_screen.tscn`.** Tout le sous-arbre `TabContainer` (onglets Connexion/Inscription, `EmailInput`/`PasswordInput`/`UsernameInput`, `LoginButton`, `RegisterButton`) est **RETIRÉ** au profit d'un unique **`SteamLoginButton`** (`Button`, `text = "AUTH_STEAM_LOGIN"`) reprenant les overrides de l'ancien `LoginButton` (charte §2 : bordure cyan, lueur au survol) + un état `disabled` grisé. Les `node_paths` de la racine et les 6 `SubResource` devenus orphelins (styles d'onglet et de champ) sont nettoyés en conséquence. **CONSERVÉS** : `Logo`, `TitleLabel`, `StatusLabel`, `QuitButton`, `Background`, `HeroGraphic`, `AshParticles`.
> - **`auth_screen.gd`.** Exports de formulaire → `@export var steam_login_button: Button` ; `_on_login_pressed`/`_on_register_pressed` → **`_on_steam_login_pressed()`** (désactive le bouton, affiche `AUTH_STEAM_BROWSER_OPENED`, appelle `AuthManager.start_steam_login()`). `_on_auth_failed` **réarme** le bouton. `_exit_tree()` coupe toute interrogation en cours. **INTACTS** : parallaxe 2.5D, sélecteur de langue, `wire_buttons_sfx` (le nouveau bouton y est câblé), ambiance audio, et TOUTE la reconnexion auto (`_try_auto_login`/`_on_auto_login_ok`/purge silencieuse).
> - **`auth_manager.gd`.** `register()`/`login()` **supprimés**. Ajout de `start_steam_login()` / `cancel_steam_login()` avec un **`HTTPRequest` et un `Timer` DÉDIÉS** (2 s) — un `HTTPRequest` ne traite qu'UNE requête à la fois, mutualiser avec `http_request`/`_id_http` produirait des `ERR_BUSY` ; garde `_steam_poll_in_flight` (le tic est SAUTÉ si le précédent poll est encore en vol, la vérification serveur→Steam pouvant durer plusieurs secondes) ; rebours global **180 s** ; `404` → échec immédiat. TLS via `_tls_options()` (§8.112 : certificat VÉRIFIÉ par défaut). ⚠️ **Correctif de détection** : la réponse `/auth/me` est reconnue par `data.has("username") and data.has("id")` — plus par `has("email")`, devenu trompeur (le champ existe mais vaut `null` depuis que les comptes n'ont plus d'email). **INCHANGÉS** : signaux, `get_profile()`, `_username_from_jwt()`, `ensure_user_id()`, persistance `user://session.dat`, `try_restore_session()`.
> - **i18n** : +4 clés fr/en/it (`AUTH_STEAM_LOGIN`, `AUTH_STEAM_BROWSER_OPENED`, `AUTHM_STEAM_SESSION_FAILED`, `AUTHM_STEAM_TIMEOUT`) ; −10 clés devenues orphelines (`AUTH_LOGIN`, `AUTH_REGISTER`, `AUTH_REGISTERING`, `AUTH_FILL_FIELDS`, les 4 `*_PLACEHOLDER`, `AUTHM_REGISTER_SEND_FAILED`, `AUTHM_LOGIN_SEND_FAILED`) — vérifiées orphelines par grep AVANT retrait.
> - **VALIDATION.** `--import` **0 ERROR** ; boot headless `auth_screen` **0 ERROR** ; **capture PNG 1920×1080** de l'écran refondu (le boot headless ne prouve rien sur la MISE EN PAGE) : logo, « ACCÈS TACTIQUE », bouton cyan unique, statut, « QUITTER LE JEU », sélecteur FR/EN/IT — charte §2 respectée. Les 4 clés résolues dans les **3 locales** (`Translation.get_message()` — ne jamais grep un `.translation` compilé). Reconnexion silencieuse vérifiée EN RÉEL contre la prod avec un JWT antérieur à la migration. **AUCUN COMMIT.**

---

> **§8.114 — Avatar Steam dans le header canonique.** Contrat et détail backend : **§8.114 de `CONTRAT_RESEAU.md`**.
> - **`top_nav.gd` (SOURCE UNIQUE §8.94 → un seul point de modification pour TOUS les écrans hub).** Le cadre identité gagne un avatar **44 px** en tête de ligne, AVANT l'eyebrow `JOUEUR` : c'est le premier repère que l'œil accroche au retour du navigateur, là où le joueur se demande « suis-je bien sur MON compte ? ». `PanelContainer` bordé cyan à `corner_radius = 0` (ADN angulaire §2), `STRETCH_KEEP_ASPECT_COVERED` (mieux vaut rogner que déformer un visage). **Masqué tant qu'aucune texture n'existe** — compte sans avatar, API Steam muette, hors ligne : la mise en page se referme, jamais de gabarit vide ni de trou. `AVATAR_SIZE = 44` est calé sur la hauteur du bloc eyebrow+pseudo pour que `NAV_H` reste rigoureusement identique.
> - **`auth_manager.gd`.** `avatar_url` / `avatar_texture` / signal `avatar_loaded` / `ensure_avatar()`. L'URL est captée dans les DEUX points d'entrée de `/auth/me` (`_on_request_completed` et `_on_id_request_completed` — ce dernier arrive le plus tôt après un login). `HTTPRequest` dédié, **TLS vérifié EN DUR** (`TLSOptions.client()`) : la cible est un CDN Steam, pas notre backend, la tolérance `client_unsafe()` du dev local (§8.112) n'a pas à s'y appliquer. Décodage JPEG avec repli PNG, échec **silencieux**. `clear_session()` purge l'avatar — sur un poste partagé, le visage du joueur précédent ne doit pas survivre à une déconnexion.
> - **Pourquoi un cache MÉMOIRE et pas disque.** `top_nav` est reconstruit à CHAQUE changement d'écran ; sans cache, l'avatar serait retéléchargé cinq fois en dix secondes de navigation. Le cache vit donc dans l'autoload (un seul téléchargement par session). Le disque n'aurait économisé qu'un téléchargement **par lancement**, au prix d'une invalidation à gérer quand le joueur change d'avatar — mauvais rapport.
> - **Le Profil n'a rien nécessité** : `profile.gd` monte déjà `TopNav`, l'avatar y apparaît donc automatiquement. Un second avatar dans son bloc identité n'aurait été que du bruit.
> - **VALIDATION.** `--import` **0 ERROR / 0 WARNING** ; **capture 1920×1080** du menu principal avec une texture injectée (le backend de prod n'expose pas encore le champ) : cadre correct, aligné, barre de navigation à hauteur inchangée. **AUCUN COMMIT.**

---

### 8.116. MATCHMAKING — écrans RECHERCHE (`search_screen`) et SALON PRIVÉ (`salon_screen`) (Frontend, 2026-07-25)

> Remplacement de `lobby_screen`/`waiting_room` par deux écrans neufs, consommant le matchmaking serveur-autoritaire (files d'attente + salons privés à code). Volet réseau et détail backend complet : **§8.116 de `CONTRAT_RESEAU.md`**. **AUCUN COMMIT.**
>
> - **Nouveau flux de navigation :** `main_menu → search_screen → [salon_screen, UNIQUEMENT en privé] → faction_selection → game`. Description mise à jour en **§3** ci-dessus (items 3-4).
> - **`search_screen.tscn`/`.gd` (REMPLACE `lobby_screen`).** Deux panneaux exclusifs, charte Warzone Command intacte (panneaux biseautés, chevrons, rythme eyebrow→valeur). **CONFIGURATION** : sélecteur de carte 2 tuiles (réutilise `_restrict_map_selector_to_mode` de l'ex-`lobby_screen` avant sa suppression), CTA « ❯ CHERCHER UNE PARTIE », bloc SALON PRIVÉ (créer/rejoindre par code 5 caractères, `LineEdit` `max_length=5` forcé MAJUSCULES à la saisie). Mode classé : panneau réduit au seul CTA classée. **RECHERCHE** : libellé d'état animé (`MM_SEARCHING`/`MM_EXTENDING`/`MM_STARTING`), chronomètre `mm:ss` depuis `since_s`, ANNULER (masqué dès `starting`), `Timer` de poll **2 s dédié à l'écran** (pas au manager — un `HTTPRequest` ne traite qu'une requête à la fois). Idempotent à l'entrée : `mm_queue_status()` immédiat reprend un ticket en cours ou propose REPRENDRE LA PARTIE si `in_game`.
> - **`salon_screen.tscn`/`.gd` (REMPLACE `waiting_room`, réservé au privé).** Code en héros (grand, espacé, or `#E0B249`) + COPIER (`DisplayServer.clipboard_set`) ; occupation « COMMANDANTS : N/max » (`salon_state_updated`) — **aucun pseudo, aucune liste, aucun id de salle** (décision produit n°2, cohérent avec l'absence totale de liste dans tout le chantier). Créateur : « ❯ LANCER AVEC BOTS » / « FERMER LE SALON ». Non-créateur : « QUITTER LE SALON ». `salon_closed` → retour `search_screen` + message amical ; `game_started_signal` → `faction_selection`.
> - **`network_manager.gd`.** SUPPRIMÉS : `fetch_rooms`/`create_room`/`join_room`/`_on_rooms_fetched`/`_on_room_created`/`_on_room_joined`/`_join_ok`/`_requeue_scan`/`_requeue_create`/`_on_requeue_rooms`/`send_init_game` (backdoor debug) + signaux `rooms_loaded`/`rooms_fetch_failed`. AJOUTÉS : `mm_queue_join`/`mm_queue_status`/`mm_queue_leave`/`private_create`/`private_join`/`private_leave`/`private_start_bots`/`leave_room` — tous authentifiés, réponses propagées **intégralement** (`reason`/`remaining_attempts`/`banned_until_epoch`… — plus jamais de `reason` jeté, leçon de l'ex-`_join_ok`). **`leave_room()`** corrige le bug historique du QUITTER (fermeture propre du peer, calqué sur `_requeue_enter`, piège `STATE_CLOSING` déjà documenté). **`requeue()` réécrit** : capture la modalité de la partie terminée, `leave_room()`, puis `mm_queue_join(...)` + retour à `search_screen` — ou `requeue_unavailable` (nouveau signal) si `GameState.is_private` (REJOUER masqué après une privée, §8.116 réseau). WS : `salon_state` → signal `salon_state_updated(count, max_players, is_creator)` ; `salon_closed` → signal `salon_closed(reason)` ; nouvelle `request_salon_state()` (action `get_salon`).
> - **`match_config.gd`.** `selected_map_id: String = "classic_42"` + setter. `MatchConfig.clear()` désormais appelé dans `main_menu._ready()` au retour au QG (n'était appelé nulle part avant).
> - **`operation_report.gd` / `spectator_overlay.gd` (REJOUER).** Si `GameState.is_private` : REJOUER devient « RETOUR AU QG ». Sinon : appelle le nouveau `requeue()`.
> - **Fichiers.** NEUFS : `scenes/ui/search_screen.tscn` + `scripts/ui/search_screen.gd`, `scenes/ui/salon_screen.tscn` + `scripts/ui/salon_screen.gd`. SUPPRIMÉS : `scenes/ui/lobby_screen.tscn` + `scripts/ui/lobby_screen.gd`, `scenes/ui/waiting_room.tscn` + `scripts/ui/waiting_room.gd` (`.uid` orphelins laissés — jamais touchés directement, nettoyés par l'éditeur). MODIFIÉS : `network_manager.gd`, `match_config.gd`, `main_menu.gd` (`_on_play_pressed` → `search_screen.tscn`), `operation_report.gd`, `spectator_overlay.gd`, et les références résiduelles à `lobby_screen`/`waiting_room` dans `main.gd`, `leaderboard.gd`, `player_chip.gd`, `profile.gd`, `shop.gd`, `ww_logo.gd` (chemins de retour repointés vers `search_screen`/`main_menu` selon le contexte).
> - **i18n.** Nouvelles clés `MM_*`/`SALON_*` (recherche, salon, cartes) fr/en/it ; aucune clé existante supprimée (orphelines `LOBBY_*` conservées, règle §1.7 de `PROMPT_NETTOYAGE_SECURITE.md`).
> - ⚠️ **Mise en page NON prouvée par le headless.** `--headless --import` **0 ERROR** et le boot des 2 nouvelles scènes **0 ERROR** attestent la compilation et l'absence de crash au `_ready()` — **pas** la disposition visuelle réelle (recadrage, chevauchements, alignement). À vérifier par une capture humaine avant de considérer l'écran définitif visuellement.
> - **VALIDATION.** `--import` **0 ERROR** ; boot headless `main_menu`/`search_screen`/`salon_screen` **0 ERROR** chacun. Détail des suites backend consommées par ces écrans : **§8.116 de `CONTRAT_RESEAU.md`**. **AUCUN COMMIT.**
> - **Lisibilité des modalités (retour Hakim, ajout post-livraison).** « CLASSIQUE » / « RAPIDE » ne disaient pas CE QUI CHANGE, et rien n'expliquait l'enjeu en points. Ajouts **purement visuels** dans `search_screen.gd` (aucun contrat réseau touché) : (a) **sous-titre muet sur chaque tuile de carte** — « 42 TERRITOIRES — 6 CONTINENTS » / « 20 TERRITOIRES — 3 CONTINENTS » (miroir de `MapData.MAP_DEFS` et du backend `map_data.MAPS` : classic_42 = 42 territoires/6 continents/3-6 · skirmish_atlantic = 20/3/3-4 — **à mettre à jour si une carte est rééquilibrée**) ; (b) **infobulle par carte** (`MM_MAP_*_HINT`) décrivant durée et échelle de partie, **cumulée** au motif d'indisponibilité `LOBBY_MAP_MAX_PLAYERS` quand l'effectif du mode dépasse les bornes — posée sur le Button ET sur le PanelContainer (⚠️ un Button `disabled` n'affiche pas forcément d'infobulle : sans le repli sur le panneau, l'explication manquerait justement dans le cas « pourquoi cette tuile est-elle grisée ? ») ; (c) **ligne d'aide « points » avec infobulle** (pattern du Classement, `leaderboard.gd::row.tooltip_text`) — en CLASSÉE « COMMENT SONT ATTRIBUÉS LES POINTS ? » détaillant le barème RP **repris de la source de vérité `backend/api/game/rewards.py`** (1er +30, 2e +15, 3e +5, 4e -10, 5e -20 ; +1 RP/élimination plafonné à +5 ; pertes ÷2 en BRONZE ; plancher 0), en NON CLASSÉE « PARTIE NON CLASSÉE — SANS EFFET SUR LE CLASSEMENT » (XP/XP héros/Coins gagnés quand même). ⚠️ Un `Label` naît en `MOUSE_FILTER_IGNORE` → `MOUSE_FILTER_STOP` obligatoire, sinon l'infobulle ne s'affiche JAMAIS. 10 clés i18n neuves FR/EN/IT ; infobulles re-résolues dans `_on_locale_changed`. Validation : CSV **1033 clés, 0 ligne malformée, LF préservé** ; les 10 clés vérifiées **résolues à l'exécution dans les 3 langues** (scène jetable créée/exécutée/**supprimée dans le même bloc**) ; `--import` + boot des 3 écrans **0 ERROR**.
> - **Revue adversariale finale — 3 correctifs FRONTEND (détail complet côté réseau : §8.116 de `CONTRAT_RESEAU.md`).** (a) Le bug `STATE_CLOSING` survivait sur 3 chemins qui fermaient encore `NetworkManager.socket` à la main : `main.gd::_on_abandon_pressed`, `main.gd::_on_spectator_quit`, `settings.gd::_on_logout_pressed` → tous passent par **`leave_room()`** désormais (peer recréé) ; ceinture-bretelles ajoutée dans `connect_to_server` (peer **NEUF** systématique si ni OPEN ni CONNECTING — couvre tout chemin oublié). (b) Cul-de-sac `search_screen` : un échec de connexion WS à l'état `ready` (close 4000/4003, serveur redéployé entre la file et l'affectation) laissait l'écran sans issue (poll stoppé, ANNULER masqué, RETOUR invisible) → sur `lobby_error` en panneau RECHERCHE, RETOUR est ré-affiché et le poll relancé (le prochain `/status` re-propose la partie ou retombe sur `idle` → panneau de configuration). (c) Côté serveur, la salle passe `"finished"` dès la victoire — c'est CE correctif qui rend REJOUER fonctionnel quand d'autres joueurs lisent encore leur rapport (sans lui : `in_room` + « REPRENDRE » sur une partie terminée). Revalidation : `--import` + boot `main_menu`/`search_screen`/`salon_screen`/`settings` **0 ERROR** chacun.

### 8.117. REFONTE UI DE L'ARÈNE — layout, chat, rythme, animations de combat, pouvoirs, audio, finishers (Frontend + backend additif, 2026-07-27)

> **Design.** Exécution intégrale de `PROMPT_REFONTE_UI_ARENE.md` (décisions verrouillées par Hakim le 2026-07-26). Constat de départ : l'arène empilait 3 tiroirs INTEL à gauche, un War Roster en haut-droite et un bloc central bas étroit → **écran illisible, infos redondantes, pouvoirs de faction imperceptibles, combats des autres joueurs en plein écran**. Les **7 lots A→G** sont livrés dans le même chantier ; un SEUL numéro de journal (§8.117) les couvre, chaque lot ayant sa sous-section ci-dessous — c'était le choix le plus sûr vis-à-vis des sessions parallèles (7 numéros réservés d'un coup se seraient télescopés). **AUCUN COMMIT.**
>
> ⚠️ **REDÉPLOIEMENT VPS REQUIS** pour les lots **C** (`BOT_ACTION_DELAY_SECONDS`), **E** (évènement `reinforcements_granted`) et **G** (catégorie `finisher`, `PlayerState.equipped_finisher`). Le client fonctionne **SANS** (replis silencieux §9.2) : rythme des bots à 1 s, renforts sans détail, finisher basique gratuit pour tout le monde.
>
> **LOT A — layout.** `BottomCenterWidget` devient une **barre basse PLEINE LARGEUR** (ancres left 0 / right 1 / bottom 1, `GlassBody` 206 px, style `StyleBoxFlat_bottombar` à liseré cyan supérieur) découpée en `BottomRow` : **OBJECTIFS** (`%ObjectiveLabel` + tracker E6 refondu — un libellé COMPLET par volet, sa barre dessous, « OU » entre les deux, rappel « dernier survivant » en clair) · **JOUEUR** (`%PlayerZone`, construit par code : `player_chip` + meneur/faction + pouvoir + 4 barres PV/PA/PB/PP) · **COMMANDES** (`%CommandsTabs`, 3 onglets — ACTIONS : instruction + carte POUVOIR + quantité + CONFIRMER/RÉ-ASSAUT/FIN DE PHASE ; CARTES : `%CardsBox` ; JOURNAL : filtres + `%LogText` déplacés depuis le panneau droit, badge « • » quand l'onglet n'est pas ouvert). NOUVEAU `PlayerSheetWidget` à gauche (rétractable, **replié au démarrage**). SUPPRIMÉS de la scène ET du code : `IntelWidget` + ses 3 tiroirs (`set_intel` / `set_factions_intel` / `set_war_intel` / `_build_war_intel`), `FactionInfoButton` + `FactionTooltip` (`set_faction_info`), `TerritoryInspector` (`set_territory_inspector`), panneau héros local (`set_hero_panel`), inspecteur héros adverse (`set_player_inspector`), War Roster (`_build_war_roster`), `IdentityLabel`/`InfoLabel`. ⚠️ **`war_roster.gd` RESTE** : ses helpers statiques (`sorted_pids`, `pv_color`, `_tint_progress`, `_mono_font`) sont la source unique réutilisée par la fiche joueur, le VS et le Rapport Post-Op. `war_room.gd` reste lui aussi (compteurs du podium/BILAN). Nouvelle API HUD : `set_turn_identity`, `set_player_panel`, `set_sheet_players`, `set_player_sheet`, `current_sheet_pid`, `open_journal_tab`, `set_power_card`. `roster_player_clicked` est **ré-émis par les flèches ◀ ▶** (même sémantique qu'avant).
>
> **LOT B — chat par destinataire.** Le `TabContainer` 2 onglets (GÉNÉRAL/PRIVÉ) disparaît au profit d'un `%ChatTargetOption` (« ◆ TOUS » + un item par joueur **humain** vivant, pastille à sa couleur plateau via une `ImageTexture` unie — un `PopupMenu` ne rend PAS le BBCode) et d'un `%ChatLog` unique. Stockage client `conv_key → Array` (`"general"` ou `str(pid)`, cap 200) : **une seule conversation affichée**, changer de destinataire re-rend UNIQUEMENT celle-ci. L'expéditeur est TOUJOURS visible (« MOI » traduit pour ses propres messages). Notifications : compteur par item (« VULTURE (2) »), **badge rouge total** sur le bouton-tiroir COMMS replié, **toast cliquable** « ◈ {pseudo} » (3 s) qui ouvre la bonne conversation, SFX `chat_ping` — jamais pendant le Split-Screen VS (le HUD y est fondu à 0). **Contrat réseau INCHANGÉ** : « TOUS » → `("general", texte, -1)`, joueur X → `("prive", texte, X)`. Clés `HUD_CHAT_*` legacy conservées (orphelines).
>
> **LOT C — rythme des tours adverses.** Le pattern `_combat_queue` est généralisé en **file d'actions adverses** (`_pace_queue`, `PACE_EVENT_KEYS`) : pendant le tour d'un AUTRE joueur, `units_deployed` / `initial_units_placed` / `units_moved` / `card_played` / `card_kept` / `conquer_move_resolved` sont mis en file et **racontés un par un** (~0,9 s, 0,4 s si plus de 8 en attente, cap 24) — toast d'action `{pseudo} ❯ {action}` à la couleur du joueur + flash du territoire. **Verrou d'animation UNIQUE** partagé avec les combats (`_combat_animating`) : aucune superposition possible, le plateau ne se repeint qu'à la fin (`_refresh_pending`). **Aucun pacing pendant MON tour.** Backend : `settings.BOT_ACTION_DELAY_SECONDS` (défaut **2,0 s**, `.env`) consommé par `bot_runner.bot_action_delay()` — import **paresseux** de `core.config` (un import de module déclencherait `Settings()` au chargement et casserait les suites qui ne le stubbent pas).
>
> **LOT D — animations de combat.** Routage dans `_do_play_combat` : **mes** combats → Split-Screen VS plein écran (inchangé) ; combats **entre les autres** → NOUVELLE `scenes/game/attack_arrow.tscn` (`scripts/game/attack_arrow.gd`) — flèche de guerre épaisse (14 px, arc, chevrons défilants, tête triangulaire, liseré sombre) tracée en 0,45 s DANS le plateau (`top_level = true`, coordonnées monde), **mini-explosion** (flash radial + 3 anneaux + `GPUParticles2D` one-shot + micro-shake caméra **sur `offset`**, jamais `position` — le travelling y tween déjà), chiffres flottants `-N` / `-N PV` et marqueurs de pouvoirs, SFX `explosion` ; **~1,3 s** (0,7 s condensé). Repli SILENCIEUX sur le bandeau compact E8 si une position de territoire manque. **Mort d'un héros** → `scenes/game/hero_down_cinematic.tscn` **plein écran pour TOUS**, quel que soit le réglage — variante = **finisher du TUEUR** (registre data-driven `scripts/game/finishers.gd`, id inconnu → basique gratuit). Réglage `combat_display` re-mappé **`cinematique→standard`, `bandeau→minimal`** dans `SettingsManager._load` (clé conservée, `remap_combat_display` PURE) ; libellés de `settings.gd` mis à jour. La **fanfare + le flash de conquête** migrent de `_play_event_feedback` vers `_after_combat_animation` — déclenchés à la réception de l'évènement, ils « spoilaient » l'issue AVANT l'animation.
>
> **LOT E — pouvoirs de faction visibles ET exploitables.** (1) **Fix bloquant Ruche** : `_do_move_click` refusait toute destination non adjacente AVANT l'envoi → `long_range_movement` était **injouable** alors que le serveur l'acceptait. `_valid_move_targets` fait désormais un **BFS sur la chaîne alliée** (miroir de `engine._has_friendly_path`), `_move_destination_legal` arbitre, message dédié `GAME_DEST_NO_CHAIN`, et `set_attack_context` **surligne les destinations légales en phase 4** (indispensable : la chaîne n'est pas devinable). `_no_action_possible` est laissé tel quel — une chaîne commence forcément par un voisin allié, la condition est donc déjà équivalente (commenté sur place). (2) **Compteur de mouvements** dans l'onglet ACTIONS (`strategic_moves_left`, déjà diffusé mais affiché nulle part) + mention « Razzia : N déplacements ». (3) **Toasts d'activation** (`show_power_toast`, file, ~2 s) sur les 5 flags de combat — **`razzia_reroll` et `first_strike` n'étaient rendus NULLE PART** — plus `zone_protected` (Isotope) ; marqueurs de Journal manquants ajoutés (`EVT_MARK_RAZZIA`/`EVT_MARK_AMBUSH`, `FEED_MARK_RAZZIA`/`FEED_MARK_AMBUSH`). (4) **Carte POUVOIR vivante** (zone JOUEUR + onglet ACTIONS), avec boutons de ré-ouverture d'`EclipseDialog`/`SpyDialog` quand un choix est EN ATTENTE. (5) **`.tres` resynchronisés** : `nomades.tres` += `attack_reroll_all_low_dice`, `chasseurs_ombres.tres` += `first_strike_bonus_die` → la **Prévision de combat** (G4) devient juste pour ces 2 factions. (6) Backend : `reinforcements_granted` (détail base/continents/pouvoir) — la part Éden est désormais comptée à part et **attribuée au pouvoir**, à total RIGOUREUSEMENT identique.
>
> **LOT F — audio.** **Diagnostic mesuré** (et non supposé) : la piste `battle_ambient.wav` JOUAIT et bouclait déjà (38,4 s, `loop_mode=1`), mais la chaîne empilait Master 0,7 × Music 0,46 × lecteur −6 dB ≈ **−16 dB** → quasi inaudible. Le niveau du lecteur passe donc à **`MUSIC_TARGET_DB = −4 dB`** (et **non** le −10 dB suggéré par le cahier des charges, qui aurait aggravé le symptôme) + **fondu d'entrée de 2 s** (`_fade_music_in`). Repli synthétique `_make_battle_pad` enrichi : boucle **9,6 s**, drone à battement lent, **percussions lointaines** à graine fixe (bouclage sans discontinuité). Nouveaux SFX (override fichier + synthèse) : `explosion`, `chat_ping`, `finisher_steel` / `finisher_orbital` / `finisher_ash` (générateur paramétré unique `_make_finisher_sting`). `assets/audio/README.md` mis à jour.
>
> **LOT G — finishers en boutique.** Nouvel onglet **FINISHERS** dans `shop.gd` (miroir exact des skins : carte → achat Coins → « EN DÉPÔT » → ÉQUIPER/ÉQUIPÉ ✓) avec **préversion animée** procédurale aux couleurs du finisher (registre `finishers.gd` partagé avec la cinématique — aucune valeur dupliquée). Backend : catégorie `finisher` + 3 articles (2000 / 2500 / 2200 Coins), `PlayerState.equipped_finisher` (PUBLIC par design — la cinématique est vue par tous), `_load_equipped_finisher` au draft. ⚠️ **AUCUNE nouvelle table** : le finisher occupe le **slot réservé `shop.FINISHER_SLOT = "__finisher__"`** de `equipped_skins` (aucun id de faction ne porte ce nom — vérifié par un assert de `test_equip.py`).
>
> **Fichiers.** NEUFS : `scenes/game/attack_arrow.tscn` + `scripts/game/attack_arrow.gd`, `scenes/game/hero_down_cinematic.tscn` + `scripts/game/hero_down_cinematic.gd`, `scripts/game/finishers.gd`. MODIFIÉS : `scenes/game/main.tscn` (refonte du HUD), `scripts/ui/hud.gd` (réécrit), `scripts/game/main.gd`, `scripts/ui/war_feed.gd`, `scripts/ui/shop.gd`, `scripts/ui/settings.gd`, `scripts/managers/settings_manager.gd`, `scripts/managers/audio_manager.gd`, `scripts/managers/game_state.gd` (commentaire), `scripts/ui/war_roster.gd` (commentaire), `resources/factions/nomades.tres`, `resources/factions/chasseurs_ombres.tres`, `assets/audio/README.md`, `tools/test_e5_warroom.gd` (le smoke du tiroir supprimé devient un smoke de la FICHE JOUEUR), `translations/ui_strings.csv`.
>
> **i18n.** ~90 clés neuves FR/EN/IT (`HUD_TAB_*`, `HUD_SHEET_*`, `HUD_STAT_*`, `HUD_TURN_OF_FMT`, `HUD_SPECTATE_TURN_FMT`, `CHAT_*`, `PACE_*`, `POWER_*`, `FINISHER_*`, `CINE_*`, `SHOP_ITEM_FINISHER_*`, `SETTINGS_COMBAT_STANDARD/MINIMAL`, `EVT_MARK_RAZZIA/AMBUSH`, `FEED_MARK_RAZZIA/AMBUSH`, `FEED_REINFORCE_*`). **AUCUNE clé supprimée** (les orphelines `HUD_INTEL_*`, `WARROOM_*`, `HUD_CHAT_TAB_*`, `SETTINGS_COMBAT_CINEMATIC/BANNER` restent). ⚠️ **Emoji rejetés après capture** : `📢`, `✉`, `🎯` sortaient en **tofu** avec la police condensée de la charte → remplacés par `◆`, `◈`, `◎` (`⚡ ☢ ☠ ⚔ ⚑ ❖ ⚙ ◆` sont, eux, rendus).
>
> **VALIDATION.** `--import` **0 ERROR** ; boot headless `main.tscn` / `main_menu.tscn` / `settings.tscn` / `shop.tscn` **0 ERROR** chacun. Backend : suite complète verte sauf `test_missions.py` et `test_simulation.py`, **déjà KO sur HEAD avant ce chantier** (dépendances absentes du poste). Suites étendues : `test_equip.py` (28 ✅), `test_shop_v2.py` (27 ✅), `test_factions.py` (54 ✅, dont 12 asserts `reinforcements_granted`), `test_bot_flow.py` (57 ✅, dont le délai config-driven).
>
> ⚠️ **Mise en page PROUVÉE PAR CAPTURE** (3 PNG 1920×1080, scène jetable créée/exécutée/**supprimée dans le même bloc**) : layout complet, flèche + explosion + chiffres, cinématique de mise à mort. **Trois défauts n'ont été vus QUE là** et ont été corrigés : (a) le marqueur de pouvoir flottant reprenait la **phrase entière** du toast (illisible + doublon) → il utilise désormais le marqueur COURT du Journal ; (b) le flotteur `-N PV` chevauchait le `-N` des pertes → déplacé SOUS la cible ; (c) le chip « PROCHAINE ZONE » passait sous le bandeau de tour/phase → déplacé en haut-DROITE. Restent non prouvés : le rendu en **1440p** et sous `ui_scale` 0,9-1,25 (à vérifier par une capture humaine).>
> **Optimisation post-livraison (retour Hakim, même jour) — 2 simplifications.**
> - **Plus AUCUN recadrage caméra sur les combats qui ne me concernent pas.** `_maybe_focus_combat` ne déclenche le travelling (0,8 s) + le retour à la vue d'ensemble (0,8 s) que si je suis **attaquant ou défenseur**. Sur les combats des autres — désormais racontés par la flèche de guerre en ~0,7 s — le recadrage durait **plus longtemps que l'animation qu'il accompagnait** : pendant un tour de bots, la caméra passait son temps en allers-retours sur des combats déjà terminés. La flèche se lit parfaitement en vue d'ensemble. Les identités sont résolues **exactement comme dans `_do_play_combat`** (champs serveur §8.85 en priorité, repli sur le snapshot pré-combat) pour que les deux prennent la même décision. La **micro-secousse** de l'explosion est conservée : elle joue sur `offset`, ne déplace pas la vue et ne coûte rien.
> - **Réglage « AFFICHAGE DES COMBATS » (`combat_display`) SUPPRIMÉ.** Le rythme **RAPIDE** devient le comportement unique : VS toujours pré-accéléré (`main.COMBAT_VS_SPEED = 2.5`), flèche toujours condensée (~0,7 s). Retirés : la rangée de segments dans `settings.gd` (+ son entrée dans `_comfort_nodes`, sans quoi le rebuild au changement de langue plante — **erreur attrapée au boot de `settings.tscn`, pas à l'`--import`**), la clé de `COMFORT_DEFAULTS` et le helper `remap_combat_display` de `SettingsManager`, et la branche `mode` de `_do_play_combat`. Le **ROUTAGE reste intact** (mes combats → VS plein écran ; les autres → flèche ; mort de héros → cinématique pour tous), tout comme la condensation de la **chaîne de ré-assaut** (E7), qui est un raccourci de narration indépendant de la vitesse. Une valeur `combat_display` résiduelle dans un `user://settings.cfg` existant devient **inerte** (`_load` n'itère que sur `COMFORT_DEFAULTS`, `_save` ne la réécrit plus) — aucune migration. Clés i18n `SETTINGS_COMBAT_*` **conservées** (orphelines). `tools/test_e8_combat_rhythm.gd` mis à jour : il vérifie désormais l'**absence** de la clé (et que les réglages de confort E10 restent persistables) au lieu de ses 3 modes — sans quoi son `assert` aurait **bloqué Godot** au lieu d'échouer.
> - **Validation.** `--import` **0 ERROR** ; boot `main` / `settings` / `main_menu` / `shop` **0 ERROR** ; `test_e8_combat_rhythm` **6 asserts verts**. Contrôle PROGRAMMATIQUE du recadrage (scène jetable) : combat adverse → `zoom` et `position` de la caméra **strictement inchangés** ; contre-épreuve « je suis défenseur » → recadrage **toujours déclenché**. Captures : écran Réglages sans la rangée (aucun trou dans la mise en page) et flèche jouée en vue plein plateau.>
> **Passe LISIBILITÉ & ESTHÉTIQUE (retour Hakim, même jour).** Le nouveau layout libère beaucoup de place, mais tout le texte était resté calibré pour l'ancien HUD compact (10-13 px) → illisible à distance de jeu.
> - **Échelle typographique explicite** (`hud.gd`, source UNIQUE — plus une seule taille en dur dans le corps du fichier) : `FS_EYEBROW 13` · `FS_SMALL 14` · `FS_BODY 16` · `FS_VALUE 17` · `FS_SECTION 17` · `FS_TITLE 21` · `FS_DISPLAY 26`. Rapport ≈ 1,25 entre deux crans : c'est l'**écart** entre l'eyebrow muet et la valeur qui structure la lecture, conformément au rythme de la charte (§2), pas la taille absolue. `default_font_size` du thème de la scène : 15 → **17**. Bandeau haut à **27-29 px** avec contour noir (lisible par-dessus n'importe quelle zone de la carte).
> - **Place rendue au texte** : barre basse 206 → **272 px**, fiche joueur 300 → **362 px**, COMMS 320 → **382 px**, marges internes élargies, `AmountSpin` et raccourcis +1/+5/MAX passés en 42 px de haut, cartes 74×56 → **96×76** (valeur en 32 px).
> - **Ornements de charte enfin posés sur l'arène** (`_apply_charter_ornaments`) : **encoches de coin biseautées** cyan (`WarzoneUI.add_corner_notches`, 24 px) sur les 3 panneaux vitrés + **filet cyan sous chaque titre de bloc** (OBJECTIFS / JOUEUR / COMMS / FICHE JOUEUR) — le titre COIFFE son contenu au lieu de flotter. Ces ornements étaient la signature des écrans hub ; leur absence est ce qui faisait paraître l'arène « générique » à côté du reste du jeu. **Séparateurs verticaux** entre les 3 zones de la barre basse (structure = information : trois domaines distincts).
> - **Jauges lisibles** (`_style_bar`) : PV/PA/PB/PP passent de 9 à **14 px** de haut et reçoivent une **piste sombre** + liseré cyan discret. `RosterHelpers._tint_progress` ne posait que le remplissage : sans piste, la portion vide se confondait avec le fond et on ne lisait pas « 48 sur 60 », seulement « une barre ». Valeurs chiffrées alignées à droite sur une colonne fixe.
> - ⚠️ **Trois défauts vus EN CAPTURE seulement**, corrigés : (a) le kill feed passait **sous** le panneau COMMS — ses offsets étaient calés en dur sur l'ancienne largeur de 320 px ; ils dérivent désormais de constantes nommées (`COMMS_WIDTH`, `KILL_FEED_WIDTH`, `KILL_FEED_GAP`) ; (b) le chip « PROCHAINE ZONE », à largeur libre, grandissait vers la gauche jusqu'à toucher le bouton ABANDONNER dès 4 territoires annoncés → **fenêtre de largeur fixe + `clip_text`** ; (c) `var parent := title.get_parent()` ne compilait pas (type non inférable) — **erreur d'`--import`, pas de boot**.
> - **Validation.** `--import` **0 ERROR** ; boot `main` / `settings` / `main_menu` / `shop` **0 ERROR** ; `test_e8_combat_rhythm` vert. Contrôles PROGRAMMATIQUES (scène jetable) : 2 encoches par panneau, kill feed à gauche de COMMS, chip à gauche d'ABANDONNER. **Cas limites enfin couverts** — **1440p** et **`ui_scale` 130 %** vérifiés en capture ET par assertions (aucun chevauchement fiche/COMMS ↔ barre basse ; la fiche joueur passe en défilement, comportement attendu).

### 8.118. Correctifs rapides — Classement cliquable, échec de file visible, coupure réseau visible, i18n oubliées (Frontend, 2026-07-30)

> Exécution intégrale de `PROMPT_CORRECTIONS_RAPIDES.md` (décisions verrouillées par Hakim). **100 % client : zéro changement de contrat réseau, zéro changement backend, AUCUN redéploiement VPS** — les 4 lots sont actifs au prochain build frontend. **AUCUN COMMIT.**
>
> **LOT A — le Classement redevient cliquable (`leaderboard.gd`).** **Cause racine** : divergence de clé entre le producteur et le consommateur. `_map_entry` renomme le `username` du serveur en **`"name"`** (et les données mock / le repli local emploient déjà `"name"`), mais le bloc §8.107 lisait `entry.get("username", "")` → toujours `""` → le `if uname != ""` ne passait **jamais** : ni curseur, ni infobulle, ni `gui_input`. Conséquence : `public_profile.tscn` — livré, testé et documenté en §8.107, dont le Classement est le **SEUL** accès par décision produit — était **inatteignable depuis le jeu**. Un caractère de clé, un écran entier hors ligne. Correctif : lecture de `"name"` + **garde mock**. La garde n'est PAS le simple `_offline_fallback` (jamais remis à `false` : un fetch réussi APRÈS un échec — clic sur une division — rendrait de VRAIES données que le seul drapeau ferait passer pour du mock) mais un prédicat **miroir de la sélection de source** de `_build_ranked_locally` : `_showing_mock() = _offline_fallback and _server_board.is_empty() and not _browse_mode`. `_open_public_profile` et le routage par `static var target_username` sont **inchangés**.
>
> **LOT B — un échec de mise en file ne peut plus être muet (`search_screen.gd`).** `_on_mm_queue_result` ne traitait que `banned` et `in_room` : **tout autre échec** (HTTP non-200 → `data` vide, `reason` inconnue d'un backend plus récent, `queued=false` inattendu) ne produisait **RIEN** — le joueur cliquait « RECHERCHER » et le CTA paraissait mort. **Branche terminale** ajoutée : `_show_config(false)` (retour à un panneau CONFIGURATION utilisable, poll coupé, CTA de nouveau visible et jamais `disabled`) + `_set_config_status(…, DANGER)` avec le **message serveur prioritaire** s'il en fournit un, sinon `MM_QUEUE_FAILED`. Plus aucun chemin muet dans ce handler. *(Le cas « requête non émise » — `err != OK` — était déjà couvert par `lobby_error` → `_on_lobby_error`.)*
>
> **LOT C — « CONNEXION PERDUE » visible en partie (`network_manager.gd` + `main.gd`).** La branche `STATE_CLOSED` du `_process` ne traitait que les codes **applicatifs** 4000 / 4001 / 4003 ; **toute autre fermeture** (1006 crash serveur / coupure réseau / VPN, 1001, code 0…) se contentait de `connected = false; set_process(false)` : **aucun signal, aucun retry**. En arène, le client devenait silencieusement inerte et le joueur ne découvrait la panne qu'en cliquant (« NET_NOT_CONNECTED »).
> - **`network_manager.gd`** — nouveau `signal server_connection_lost(code: int)`, émis **une seule fois par connexion** (garde `_connection_lost_emitted`, **ré-armée dans `connect_to_server`**). Cette ré-arme est ce qui donne son sens à une **2ᵉ** émission : « la tentative de reconnexion a elle aussi échoué ». Nouvelle méthode **`retry_connection()`** — pure ACTION, aucune politique : elle rappelle `connect_to_server(current_room_id)` (peer NEUF, JWT + `user_id` déjà en mémoire), no-op si plus aucune salle. Le serveur accepte le remplacement de socket d'un joueur déjà en salle et lui renvoie un **`game_started` PERSONNEL** (`_send_current_state`, état redacté §8.6) → l'état se resynchronise seul, le client ne recharge rien. Aucun `game_error` sur ce chemin : les écrans le traitent comme un refus d'action, pas comme une panne de lien.
> - **`main.gd`** — machine à états `_net_state` (`""` / `"lost"` / `"final"`) + jeton `_net_cycle` invalidant les minuteries en vol (pattern `_requeue_cycle`). Coupure → **bandeau plein-largeur rouge** `⚠ CONNEXION PERDUE — RECONNEXION…` ; **UNE** tentative à **2 s** (`retry_connection`) ; succès (`server_connected` ré-émis) → **bandeau vert** `CONNEXION RÉTABLIE` 2 s ; échec (2ᵉ `server_connection_lost` **ou** garde-fou 8 s, indispensable si le socket reste bloqué en CONNECTING) → **dialogue modal** `MOUSE_FILTER_STOP` + bouton **RETOUR AU QG** (clé `MM_BACK_TO_HQ` **réutilisée**) qui passe par `leave_room()` (fix `STATE_CLOSING` §8.116). La **POLITIQUE de reconnexion vit dans l'écran**, pas dans le manager : `salon_screen` ne doit pas se reconnecter tout seul. Overlay sur `CanvasLayer` **layer 3** (au-dessus du HUD 0 et du stinger de tour 2). **Aucun bandeau si la partie est finie** (`_victory_shown`) : pas d'alarme par-dessus le Rapport Post-Op.
> - ⛔ **Périmètre :** on rend la panne **visible**, on ne change PAS ses conséquences. La règle serveur reste l'abandon sur déconnexion (`_maybe_abandon_on_disconnect`) — chantier séparé du backlog. Le dialogue final **le dit** (« La partie a pu être marquée abandonnée ») au lieu de promettre une reprise qui n'existe pas.
>
> **LOT D — deux chaînes en dur passent en i18n.** (1) `missions.gd _fmt_delta` : `"%dj %02d:%02d:%02d"` → `"%d%s …" % [d, tr("TIME_DAYS_SHORT"), …]`. Le format reste composé **dans le code** : une clé à 4 substitutions ordonnées est un piège à traduction alors que seul le suffixe est localisable. (2) `war_room.gd` : `"JOUEUR %d" % pid` → **`TranslationServer.translate("WR_PLAYER_FALLBACK") % pid`**. ⚠️ Deux points : la clé **existait déjà** (servie par `war_feed.gd` et `player_chip.gd`) — on ne crée pas une seconde clé pour la même phrase ; et c'est `TranslationServer.translate` et **non** `tr()`, ce module étant PUR (`extends RefCounted`, méthodes statiques) où `tr()` — méthode de `Node` — n'existe pas (même piège que les modules statiques du §8.104).
>
> **Fichiers.** MODIFIÉS uniquement : `scripts/ui/leaderboard.gd`, `scripts/ui/search_screen.gd`, `scripts/managers/network_manager.gd`, `scripts/game/main.gd`, `scripts/ui/missions.gd`, `scripts/ui/war_room.gd`, `translations/ui_strings.csv`. **Aucun fichier neuf, aucune scène touchée.**
>
> **i18n.** **5 clés NEUVES** FR/EN/IT ajoutées en fin de CSV : `MM_QUEUE_FAILED`, `NET_CONNECTION_LOST`, `NET_CONNECTION_RESTORED`, `NET_CONNECTION_LOST_FINAL`, `TIME_DAYS_SHORT`. **Aucune clé supprimée ni renommée** ; `MM_BACK_TO_HQ` et `WR_PLAYER_FALLBACK` sont **réutilisées** plutôt que dupliquées. Le glyphe `⚠` du bandeau est **rendu correctement** par la police condensée de la charte (vérifié en capture — cf. la liste des dingbats éprouvés du §8.110).
>
> **VALIDATION.** `--import` **0 ERROR** ; boot headless `leaderboard` / `search_screen` / `missions` / `game/main` → **0 ERROR** chacun. **Sonde runtime temporaire** (créée, exécutée et **supprimée dans le même bloc**, pattern §8.107 — sans `assert()`, qui **bloquerait** Godot en headless au lieu d'échouer) : **40 vérifications, 0 échec** — `_map_entry` produit bien `"name"` et pas `"username"` ; ligne serveur cliquable (curseur + infobulle + handler) ; ligne mock **inerte** ; ligne cliquable en navigation par division **malgré** `_offline_fallback` ; échec de file → `MM_QUEUE_FAILED` visible, panneau CONFIGURATION rendu, CTA re-cliquable, message serveur prioritaire, branches `banned`/succès **non régressées** ; machine à états réseau complète (coupure → rétablie → 2ᵉ coupure → échec → dialogue modal bloquant → émission surnuméraire ignorée) et **silence total si la partie est finie** ; `_fmt_delta` et le repli de pseudo vérifiés dans les **3 locales** (`1j/1d/1g`, `Joueur/Player/Giocatore 3`) + format < 24 h inchangé.
>
> ⚠️ **Mise en page PROUVÉE PAR CAPTURE** (3 PNG 1600×900, scène jetable créée/exécutée/**supprimée dans le même bloc**) : bandeau rouge, bandeau vert, dialogue final. **Un défaut n'a été vu QUE là** : posé à `y = 0`, le bandeau plein-largeur **masquait la pastille tour/phase/chrono ET le bouton ABANDONNER** — exactement ce qu'il ne faut pas voler au joueur pendant une panne. Il est descendu à **`NET_BANNER_TOP = 64`**, la ligne d'ancrage déjà documentée « sous la TopBar du HUD » par `phase_banner.gd` ; la collision avec le stinger de tour est théorique (aucun changement de tour/phase ne peut arriver pendant que le socket est mort, et le bandeau est de toute façon sur un calque supérieur). Reste un **chevauchement assumé** du bandeau avec l'en-tête « COMMS » du panneau droit : le plein-largeur est demandé, et il ne dure que le temps de la panne. ⚠️ **Non prouvé** : le comportement réel face à un backend tué en pleine partie (test manuel à faire par Hakim — la sonde simule les signaux, elle ne coupe pas un vrai socket).

### 8.119. CAPACITÉS DE HÉROS — lecture claire des PP, onglet ACTIONS, ciblage plateau (Frontend, 2026-07-30)

> **Périmètre.** Volet client de `PROMPT_PP_DOUBLE_EMPLOI.md` (contrat réseau : **§8.119 de `CONTRAT_RESEAU.md`** ; règles et valeurs : **§4.5 de `ARCHITECTURE_ET_REGLES.md`**). **VUE PURE (§6.1) de bout en bout** : le client n'applique AUCUNE règle — il envoie `hero_ability`, le serveur décide, l'état redescend. ⚠️ **Client et serveur doivent partir ENSEMBLE** (gate de version WS) : ces boutons n'obtiennent une réponse utile que d'un backend redéployé.
>
> **1) LECTURE CLAIRE DES PP (lot D) — le problème de fond.** Les PP s'affichaient partout (fiche joueur, zone joueur, VS, écran Personnages) sans qu'**aucun texte n'explique** ce qu'ils font ni pourquoi ils bougent.
> - **Tooltip UNIFIÉ `PP_TOOLTIP`** posé dans `hud._fill_hero_stats` — **source UNIQUE** des 4 barres PV/PA/PB/PP : une seule ligne modifiée met le tooltip à jour sur TOUS les écrans qui l'utilisent. Remplace `CHAR_STAT_PP_DESC`, qui décrivait des PP purement passifs (clé **conservée**, règle §1.5 — elle sert encore à l'écran Personnages).
> - **Fluctuation VISIBLE hors VS** (`hud._track_pp_fluctuation` / `_spawn_pp_arrow`) : flèche **▲/▼ + delta chiffré** flottant 0,9 s sur la zone joueur dès que `hero_pp_current` change entre deux états. Auparavant la jauge sautait sans cause visible en dehors du Split-Screen VS (donc jamais pour les combats des AUTRES, ni après un rationnement). `INF` en sentinelle du « jamais reçu » → **aucune flèche au premier état** (sinon toute prise de contrôle afficherait un faux gain depuis 0). `reduced_motion` (E10 §8.82) **fige** l'affichage 1,2 s au lieu de l'animer — on n'a pas le droit de SUPPRIMER une donnée de jeu, seulement de la calmer.
>
> **2) ONGLET ACTIONS (lot E) — deux boutons dans la carte POUVOIR existante.** Réutilise `hud.set_power_card(lines, buttons)` + le signal `power_action_requested` (§8.117) — **aucun nouveau nœud de scène**. Le dict de bouton gagne 3 clés OPTIONNELLES (rétro-compatibles) : `subtitle`, `tooltip`, `disabled`.
> - **RATIONNER** — affiché pour les **10 héros** pendant son tour, avec un sous-titre **DYNAMIQUE** « −N PP → +M PV » calculé par `main._ration_preview()` (miroir de `hero_abilities.ration_plan`) : le joueur voit **la vraie affaire avant de cliquer**, y compris quand le plafond de PV rogne la conversion (« −5 PP → +2 PV » se lit, ne se découvre pas).
> - **Pouvoir de faction** — affiché **uniquement** pour les 3 pilotes ET `not GameState.is_ranked` ; nom + coût en PP. Les 7 autres factions n'ont **rien** (pas de « bientôt »).
> - ⚠️ **JAMAIS de bouton mort silencieux.** Un bouton indisponible est **grisé AVEC sa raison en infobulle** (`main._ability_block_reason`, ordre calqué sur `hero_abilities.can_use` → l'infobulle annonce la MÊME raison que le refus serveur). `mouse_filter = STOP` est forcé sur un bouton désactivé : sans ça Godot ignore le survol et l'infobulle ne s'afficherait jamais — le bouton redeviendrait muet.
> - Le grisage est un **CONFORT, jamais une autorité** : un état limite passé au travers est refusé par le serveur, proprement.
>
> **3) CIBLAGE PLATEAU.** `board.set_ability_targets(tids)` **délègue à `set_attack_context`** — une seule mécanique de « cibles légales » dans le plateau (liseré pulsant de l'overlay §8.51), donc aucune divergence visuelle possible entre un ciblage d'attaque et un ciblage de pouvoir. Cibles calculées par `main._ability_targets()`, **miroir de `hero_abilities.target_is_valid`** : mes territoires non protégés (BASTION) ou la zone **COURANTE** (ABSOLUTION — jamais `next_territories`, on ne purge pas le télégraphe).
> - **ESC** annule (priorité au ciblage de capacité sur la désélection d'attaque, dans `_unhandled_input`) ; un clic sur une cible **illégale** annule aussi, avec une ligne de journal — le joueur comprend que son clic a été pris en compte et refusé, au lieu d'être ignoré en silence.
> - **FRAPPE FANTÔME** (sans cible) part **directement** ; tant que `airborne_attacks_left > 0`, un **bandeau** « PROCHAINE ATTAQUE : PORTÉE ILLIMITÉE » (`hud.set_ability_banner`, chip en tête de la zone joueur sur le modèle du télégraphe G1 §8.62) reste affiché. Piloté par l'**ÉTAT SERVEUR**, jamais par une mémoire locale : il disparaît seul dès que l'attaque a consommé le crédit ou que le tour s'achève.
> - Un ciblage armé est **annulé automatiquement** à tout changement de tour/phase (`_refresh`) : sans ça le plateau restait surligné et le joueur coincé en mode ciblage.
>
> **4) FEEDBACK PUBLIC (tout le monde voit).**
> - **Toast + journal** par capacité, composés dans `main._push_ability_toast` depuis l'évènement système **`ability_used`** — le serveur n'émet qu'**UN code paramétré**, la phrase est choisie ici dans la langue du joueur. `power_id` inconnu (serveur plus récent) → phrase générique `SYSEV_ABILITY_GENERIC`, jamais d'écran muet.
> - **BOUCLIER** (`territory_badge.gd`) : liseré **cyan** EXTÉRIEUR aux anneaux de zone (un territoire peut être contaminé **ET** annoncé **ET** protégé — les trois marquages cohabitent) + **écusson**. ⚠️ **L'écusson est DESSINÉ** (`draw_colored_polygon`, 5 points) **et non un glyphe** : les pictogrammes de bouclier Unicode (⛨ et voisins) ne sont couverts par aucune police embarquée → ils s'afficheraient en **tofu** (constaté sur 📢 ✉ 🎯 lors de chantiers précédents). Aucune dépendance de police, et l'angulaire colle mieux à la charte (§2). État piloté par `shield_turns_left` → le marquage s'efface de lui-même à l'expiration.
> - **RATIONNER** : flotteur **vert « +N PV »** sur la zone joueur (`hud.float_hero_heal`) — pendant exact de `pulse_hero_pain` (E9 §8.81) : le soin doit être aussi lisible que les dégâts.
> - **ABSOLUTION** : **aucun VFX neuf** — le rafraîchissement de zone existant fait disparaître la pulsation verte tout seul.
>
> **5) Refus TRADUITS.** `NetworkManager.last_error_reason` mémorise la clé **ADDITIVE `reason`** du message `{"type":"error"}` (§8.119 réseau). **Propriété et non argument de signal** : `game_error(message)` est écouté par plusieurs écrans, en changer la signature les casserait tous (même patron que `last_bot_fill_at` / `last_objectives_reveal`). `main._on_game_error` la lit **immédiatement** (elle est écrasée au refus suivant) et journalise la phrase traduite via `ABILITY_ERROR_KEYS` ; code inconnu → repli sur le `message` serveur.
>
> **6) `GameState.is_ranked` (NOUVEAU miroir).** Champ PUBLIC de l'état diffusé **depuis §8.88** mais jamais miroité côté client : `NetworkManager.last_match_is_ranked` ne le connaît qu'**au game_over** (bilan économique), ce qui ne sert à rien EN PARTIE. Défaut `false` (serveur/état antérieur) = non classée : au pire on affiche un bouton que le serveur refusera proprement.
>
> **Fichiers.** MODIFIÉS : `scripts/game/main.gd` (registre MIROIR `FACTION_POWERS`/`ABILITY_ERROR_KEYS`, boutons, ciblage, ESC, toasts, refus traduits), `scripts/ui/hud.gd` (tooltip PP unifié, flèches ▲/▼, flotteur de soin, boutons grisables, bandeau), `scripts/game/board.gd` (`set_ability_targets`, propagation du bouclier au badge), `scripts/game/territory_badge.gd` (liseré cyan + écusson dessiné), `scripts/managers/game_state.gd` (`is_ranked`), `scripts/managers/network_manager.gd` (`last_error_reason`), `translations/ui_strings.csv` (**+30 clés FR/EN/IT**).
>
> ⚠️ **Registre MIROIR.** `main.FACTION_POWERS` duplique volontairement coûts/phases/cibles de `backend/api/game/hero_abilities.py` (même discipline que `map_data.gd` face à `map_data.py`) — **uniquement pour AFFICHER**. Si un coût change côté serveur, le mettre à jour ici aussi : au pire l'affichage est périmé, jamais la règle.
>
> **VALIDATION.** `--import` **0 ERROR** ; boot headless `game/main.tscn` et `ui/main_menu.tscn` → **0 ERROR**. Deux contre-épreuves exécutées puis **supprimées dans le même chantier** (scripts jetables `verify_8119_i18n.gd` / `verify_8119_logic.gd`) :
> - **i18n : 114 OK / 0 échec** — les 30 clés sont réellement résolues par le `.translation` COMPILÉ dans les **3 langues** (une clé absente est renvoyée à l'identique → détectable), et l'**ARITÉ** de chaque chaîne de format correspond aux appels du code (un `%d` de trop plante à l'exécution — ni `--import` ni un boot ne le révèlent).
> - **Logique : 29 OK / 0 échec** — `main.gd` instancié SEUL (hors arbre) avec des états serveur fictifs : `_ration_preview` (plancher PP, plafond PV), `_ability_block_reason` (ordre des 8 refus, RATIONNER autorisé en classée, BASTION au plancher exact, **FRAPPE FANTÔME jamais grisée à tort faute de cible**), `_ability_targets` (bouclier/ennemi exclus, télégraphe non ciblable), gardes de tour.
>
> ⚠️⚠️ **MISE EN PAGE NON PROUVÉE.** Un boot headless « 0 ERROR » ne prouve **RIEN** sur le rendu : la position du sous-titre des boutons, la lisibilité de l'écusson de bouclier sur le plateau, la trajectoire des flèches ▲/▼ et du flotteur de soin, et le bandeau de portée illimitée n'ont **PAS** été vus. À contrôler en **CAPTURE** (recette §8.111/§8.118) ou en partie locale.

---

## §8.120 — TENSION & FIN DE PARTIE (volet FRONTEND)

> Contrat réseau : **§8.120 de `CONTRAT_RESEAU.md`** · règles et valeurs : **§4.6-§4.10 de
> `ARCHITECTURE_ET_REGLES.md`** (dépôt backend). **Client défensif §9.2** : tous les champs consommés
> ici sont ADDITIFS — absents d'un serveur non redéployé, chaque bloc se masque simplement.
> ⚠️ **Client et serveur partent ENSEMBLE** (gate de version WS §9).

### 1. Rebours GLOBAL de partie (`hud.gd`)

- **Chip `⏱ MM:SS`** créé par code **juste sous `%TimerLabel`** (les deux rebours se lisent empilés :
  tour au-dessus, partie en dessous). Calé sur `GameState.match_deadline_epoch` avec le **MÊME offset
  d'horloge** que le chrono de tour (`_srv_offset`, §8.31) — une horloge PC fausse n'y change rien.
  `match_deadline_epoch == 0.0` (serveur antérieur / limite désactivée) → chip **masqué**.
- Sous **`FINAL_PROTOCOL_SECONDS = 120`** : couleur danger + **pulse** (coupé par `reduced_motion`,
  E10 §8.82). **Tic sonore** (`timer_tick`, le même que la pré-alerte AFK — on ne crée pas un 2ᵉ son
  pour un 2ᵉ rebours) uniquement dans la **dernière minute** : à 2 min il serait interminable.
- Il tourne **indépendamment** du chrono de tour, donc **aussi pendant un tour de bot** (où
  `turn_timer` est nul).

### 2. Bandeau « ⚠ PROTOCOLE FINAL » + mini-classement de DÉPARTAGE

- `main._push_match_countdown()` annonce le protocole **une seule fois** (garde
  `_final_protocol_announced`) : `phase_banner` rouge + SFX `zone_alarm` + entrée ☢ au Journal.
- **Mini-classement** (`hud.set_tiebreak_board`) : panneau compact ancré **HAUT-GAUCHE** (la colonne
  droite porte le chip de zone et ABANDONNER, le centre le bandeau de tour), visible **uniquement**
  pendant le PROTOCOLE FINAL, retiré à la sortie.
- ⚠️ **Calculé CÔTÉ CLIENT, à dessein** : `final_scores` n'arrive qu'au `game_over` — trop tard pour
  une course. PV de héros et kills de combat sont **publics** dans l'état ; le **% d'objectif des
  autres est SECRET** → affiché **« ??? »** pour autrui et en vrai pour soi. Choix assumé : la tension
  vient de ne pas savoir où en sont les adversaires. Le tri local ne porte donc que sur PV puis kills
  (il **montre les critères**, il ne prétend pas être le classement final).

### 3. Zone croissante — évènement `zone_grew`

Le passage au shader `toxic_pulsation` est **déjà** assuré par `board.gd` (le territoire est entré
dans `contamination_zone.territories`). `main._on_zone_grew()` ajoute ce que l'état seul ne dit pas —
**quand** et **où** : `board.flash_territory` (soumis à `reduced_motion`), entrée ☢ **cliquable** au
Journal (le clic recentre la caméra, E4 §8.76) et SFX. Le télégraphe de téléportation est **inchangé**.

### 4. Tracker d'objectif — 3 nouveaux types (`scripts/ui/objective_tracker.gd`)

- `leg_progress` gagne `control_specific_continents`, `destroy_units`, `fortified_hold` : formules
  **MIROIR EXACT** d'`api/game/objectives.progress` (toute divergence ferait mentir la jauge).
- `describe` compose les libellés depuis `type`/`params` (i18n §8.104) et **réutilise les clés
  `CONT_*`** déjà traduites pour les noms de continents — on ne duplique jamais un nom de continent
  dans une nouvelle clé. Clé absente → id « humanisé », jamais un `CONT_XXX` brut à l'écran.
- **Auto-vérification par asserts** (pattern G4 §8.63) : `_self_check()` couvre les six ratios,
  la paire vide (aucune division par zéro) et la sémantique OU du double objectif.
- Le **contexte** est construit **une seule fois** par `main._objective_ctx()` — extrait de
  `_push_objective_tracker` parce qu'il a désormais deux consommateurs (la jauge et le mini-classement) ;
  deux constructions locales auraient fini par afficher deux pourcentages différents du même objectif.

### 5. Rapport Post-Op (`operation_report.gd`)

- **Verdict TIMEOUT** : quand `GameState.victory_reason == "timeout"`, le titre est préfixé de
  `VERDICT_TIMEOUT` (« TEMPS ÉCOULÉ — VICTOIRE AU SCORE ») **sans perdre le nom du vainqueur** —
  sans ce sur-titre, un joueur qui menait aux territoires ne comprendrait pas l'arrêt de la partie.
  (`GameState.victory_reason` est désormais **miroité** côté client ; "" = serveur antérieur → aucun
  sur-titre, comportement d'avant le chantier.)
- **Tableau de DÉPARTAGE** (`populate_final_scores`) dans l'onglet **BILAN**, sous le tableau
  comparatif : JOUEUR · OBJECTIF · PV HÉROS · KILLS, **dans l'ordre exact du barème** (lire de
  gauche à droite = lire le départage). Rendu **TEL QUEL** (le serveur a déjà trié) ; ma ligne en
  cyan, les non-contenders en muet. Section **masquée** si `final_scores` est vide.
- **Ligne PARIS** (`populate_bet_results`) : « PARIS D'OBSERVATEUR : 2/3 corrects · +25 XP +15 ¢ »
  puis le détail par pari. Rien du tout si le joueur n'a pas parié.
- **Lignes PLACEMENT** dans les onglets XP JOUEUR et XP HÉROS : le montant vient du **SERVEUR**
  (`xp_inputs.xp_placement` / `xp_inputs.hero_xp_placement`) — c'est une valeur d'équilibrage, elle
  bougera au playtest **sans redéploiement de client** (règle §6). Repli local (override `-1`,
  serveur antérieur) = ancien barème (+150 au seul 1ᵉʳ, conditionné à l'objectif). Le libellé dépend
  du rang (`PLACEMENT_LINE_1ST` / `_2ND` / `_OTHER`) : « PLACEMENT (1ᵉʳ) » se lit d'un coup d'œil.
- `_self_check()` étendu : **repli local ET barème serveur** vérifiés, dont la **non-cumulativité**
  héros (2ᵉ = 60, jamais 150 + 60).

### 6. Overlay spectateur — panneau « PARIS » (`spectator_overlay.gd`)

**Seul ajout** à cet overlay, volontairement compact et **non bloquant** (le plateau reste navigable) :
panneau ancré HAUT-DROITE (la gauche est prise par le mini-classement pendant le PROTOCOLE FINAL),
3 lignes = 3 types de pari, chacune `libellé + liste déroulante + MISER + état`.

- **View PURE §6.1** : l'overlay ne connaît ni le réseau ni les règles — il émet `bet_placed`,
  `main.gd` envoie, et lui repousse le verdict serveur.
- Cibles = joueurs **encore en lice**, ni éliminés ni soi-même (résolues par `main._refresh_bet_panel`,
  re-testées à **chaque** état : une cible peut tomber entre-temps).
- Guichet fermé selon la **MÊME règle que le serveur** (`observer_bets.open_for`) : dès le PROTOCOLE
  FINAL, les lignes non misées affichent `BET_LOCKED`.
- Pari accepté → ligne **verrouillée** avec la mise et la **prime potentielle annoncée par le serveur**
  (aucune valeur en dur côté client). Refus → code `reason` traduit (clés `BET_ERR_*`).
- Au `game_over`, `show_bet_results` passe chaque ligne en **GAGNÉ / PERDU** : le parieur voit son
  résultat sans avoir à le chercher (le Rapport Post-Op le redit, c'est voulu).

### 7. i18n (41 clés ajoutées en fin de `translations/ui_strings.csv`, FR/EN/IT)

`MATCH_TIMER_FMT` · `MATCH_TIMER_TOOLTIP` · `FINAL_PROTOCOL_BANNER` · `FINAL_PROTOCOL_LOG` ·
`VERDICT_TIMEOUT` · `SCOREBOARD_TITLE` · `SCOREBOARD_UNKNOWN` · `SCOREBOARD_ROW_FMT` ·
`SCOREBOARD_COL_OBJECTIVE` · `SCOREBOARD_COL_HP` · `SCOREBOARD_COL_KILLS` · `ZONE_GREW_LOG` ·
`OBJ_DESC_CONTROL_SPECIFIC` · `OBJ_DESC_DESTROY_UNITS` · `OBJ_DESC_FORTIFIED_HOLD` ·
`OBJ_SPECIFIC_FMT` · `OBJ_DESTROY_FMT` · `OBJ_FORTIFIED_FMT` · `PLACEMENT_LINE_1ST/_2ND/_OTHER` ·
`BETS_TITLE` · `BETS_HINT` · `BETS_SUMMARY_FMT` · `BET_WINNER` · `BET_NEXT_HERO` · `BET_END_REASON` ·
`BET_END_OBJECTIVE/_ELIMINATION/_TIMEOUT` · `BET_PLACE` · `BET_PLACED_FMT` · `BET_LOCKED` ·
`BET_WON` · `BET_LOST` · `BET_UNKNOWN` · `BET_ACCEPTED_LOG` · `BET_ERR_*` (4 refus).

Aucune clé supprimée. CSV **LF / UTF-8 sans BOM** (1 200 clés, aucun doublon), `.translation`
régénérés par `--import`.


### 8. CORRECTIF « REJOUER coince sur l'écran de création de partie » (bug §8.116/§8.70)

> Signalé pendant la recette de §8.120, mais **antérieur** à ce chantier. Détail serveur et
> contre-épreuves : **§8.120 §10 de `CONTRAT_RESEAU.md`**. Vaut pour les DEUX boutons REJOUER (rapport
> post-op ET overlay observateur), qui passent tous deux par `NetworkManager.requeue()`.

**Cause côté client — une course de requête.** `requeue()` appelait `mm_queue_join()` juste **avant**
`TransitionManager.change_scene("search_screen.tscn")`. La réponse arrivait donc alors que
`search_screen` n'était pas encore dans l'arbre : sa garde `if not is_inside_tree(): return`
**jetait** `mm_queue_result`, et rien ne basculait sur le panneau RECHERCHE. Le
`mm_queue_status()` du `_ready` pouvait ensuite répondre `idle` → `_on_mm_status_updated` faisait
`_poll_timer.stop()` + `_show_config(false)` → **écran figé sur CONFIGURATION, plus aucun poll**.

**Correctif — c'est l'ÉCRAN qui met en file.** `requeue()` mémorise seulement la modalité
(`_pending_requeue`, lue une seule fois par `consume_pending_requeue()` — lecture DESTRUCTIVE, sinon
un simple ÉCHAP → RETOUR relancerait une recherche fantôme) et change de scène.
`search_screen._ready()` appelle `_start_requeue(pending)` : panneau RECHERCHE **optimiste** (le
joueur a cliqué, il doit voir tout de suite qu'il se passe quelque chose), **ANNULER masqué** jusqu'à
la confirmation serveur (un bouton qui annulerait un ticket inexistant serait un mensonge), puis
`mm_queue_join(...)`. Émetteur et écouteur du signal sont désormais le **même nœud, déjà dans
l'arbre** : la course disparaît par construction. Un refus (`banned`, `in_room`, HTTP ≠ 200) rebascule
sur CONFIGURATION avec son message via `_on_mm_queue_result` — l'optimisme n'avale aucune erreur.

Entrée normale dans l'écran (depuis le Menu Principal) : `consume_pending_requeue()` renvoie `{}` et
l'écran interroge `/status` comme avant — comportement §8.116 **inchangé**.

> **Fichiers.** MODIFIÉS : `scripts/managers/network_manager.gd` (`requeue`, `_pending_requeue`,
> `consume_pending_requeue`), `scripts/ui/search_screen.gd` (`_ready`, `_start_requeue`).
>
> **Validation.** `--import` **0 ERROR** ; boots `search_screen.tscn`, `game/main.tscn`,
> `spectator_overlay.tscn`, `main_menu.tscn` **0 ERROR**.
> ⚠️ **Enchaînement bout en bout NON rejoué** (mourir → REJOUER → file → nouvelle partie) : il exige
> une vraie salle multijoueur. Les deux causes sont couvertes par des tests côté serveur.

> **Fichiers.** MODIFIÉS : `scripts/ui/hud.gd`, `scripts/ui/objective_tracker.gd`,
> `scripts/ui/spectator_overlay.gd`, `scripts/game/main.gd`, `scripts/game/operation_report.gd`,
> `scripts/managers/game_state.gd`, `scripts/managers/network_manager.gd`,
> `translations/ui_strings.csv`. **Aucun `.tscn` retouché** (tout est construit par code).
>
> **Validation.** `--import` **exit 0, 0 ERROR** · boots headless **0 ERROR** :
> `main_menu.tscn`, `game/main.tscn`, `game/operation_report.tscn`, `ui/spectator_overlay.tscn`,
> `ui/search_screen.tscn` · auto-vérification du tracker exécutée **hors jeu** (`--script`) :
> **OK** · **contre-épreuve de l'outillage** : un assert du Rapport saboté à 999 fait bien remonter
> `SCRIPT ERROR: Assertion failed.` au boot de `operation_report.tscn` (donc `_self_check` tourne
> réellement), source **restaurée dans le même bloc**, aucun marqueur `A RETIRER` résiduel.
>
> ⚠️⚠️ **MISE EN PAGE NON PROUVÉE.** Un boot headless « 0 ERROR » ne prouve **RIEN** sur le rendu.
> N'ont **PAS** été vus : le chip de rebours global sous le chrono (chevauchement possible du bandeau
> haut), le mini-classement HAUT-GAUCHE pendant le PROTOCOLE FINAL, le panneau PARIS HAUT-DROITE
> (largeur des listes déroulantes, collision avec le chip de zone), le tableau de départage dans
> l'onglet BILAN, et les lignes PLACEMENT/PARIS du Rapport. À contrôler en **CAPTURE** (recette
> §8.111/§8.118) ou en partie locale avec `MATCH_TIME_LIMIT_S=180` dans le `.env`.

---

## §8.121 — STREAMABILITÉ & PARTAGE : rapport de trahison, révélation théâtrale, carte de partage, mode streamer (volet FRONTEND)

> Contrat réseau (unique ajout backend — le journal d'attaques) : **§8.121 de `CONTRAT_RESEAU.md`**.
> **Client défensif §9.2** : le seul champ consommé (`game_over.attack_log`) est ADDITIF — absent
> d'un serveur non redéployé, le 5ᵉ onglet se masque et la carte de partage s'exporte sans sa ligne
> de trahison. ⚠️ **Client et serveur partent ENSEMBLE** (gate de version WS §9).
>
> **Principe directeur (décision n° 1).** *Le serveur fournit les FAITS, le client raconte
> l'HISTOIRE.* Toute l'analyse narrative est calculée côté client dans un module **PUR** testable ;
> le backend n'a gagné qu'une trace brute.

### 1. `scripts/game/betrayal_report.gd` — module PUR d'ANALYSE (`class_name BetrayalReport`)

Quatre analyses, zéro nœud, zéro `tr()` (il renvoie des **clés i18n et des nombres**, la Vue
compose — même contrainte que `war_feed` / `objective_tracker`, §8.104) :

- **`aggression_matrix(attack_log, pids)`** → `{cells, attacks, max, total, pids}`. Grille N×N des
  unités détruites par couple, **toutes les cases présentes** (0 compris) pour que la grille se
  rende entière, + la case **maximale** (départage attaquant puis défenseur croissants : deux
  joueurs de la même partie voient le même « pire agresseur »). Les attaques sur du **NEUTRE** sont
  exclues — sinon un joueur qui ramasse des territoires ravagés par la zone passerait pour
  l'agresseur n° 1 de la partie.
- **`find_backstab(attack_log, config)`** → le **COUP DE POIGNARD**. `calm_rounds` = round de
  l'attaque − round du dernier affrontement du couple (0 = jamais affrontés). Qualifié si
  `calm_rounds ≥ 2` **et** `kills ≥ 1` ; ordre de mérite : kills, puis calme, puis le plus tôt, puis
  le plus petit id. **Repli** (`confirmed: false`) : le **premier contact au plus long voisinage
  pacifique** — la Vue affiche alors « GUERRE FRONTALE » et garde la ligne en muet.
- **`find_turning_point(territory_history, config)`** → le **MOMENT DÉCISIF** : plus forte variation
  du nombre de territoires d'un joueur sur **3 snapshots** consécutifs. ⚠️ Le critère est
  l'**AMPLITUDE**, pas le signe : le plus grand basculement peut être la **poussée décisive du
  vainqueur** (+16) plutôt qu'un effondrement (−10) — d'où **deux** libellés
  (`BETRAYAL_TURNING_POINT` / `BETRAYAL_TURNING_POINT_UP`), écrire « L'EMPIRE DE X BASCULE » sur un
  gain de territoires se lisait comme une défaite. À amplitude égale,
  l'**effondrement** passe avant la conquête (un empire qui tombe est le récit ; le gagnant est déjà
  au podium), puis la fenêtre la plus précoce. Partie strictement statique → `{}` (on n'affirme rien).
- **`elimination_chain(statistics, attack_log)`** → **LA CHAÎNE DES CHUTES**. L'**attribution** fait
  autorité depuis `statistics.eliminated_by_player` (la reconstruire depuis le journal se tromperait
  quand perte du dernier territoire **et** permadeath tombent sur le même assaut) ; le journal ne
  sert qu'à **dater**. Élimination non datable (journal tronqué par le plafond 300) → `round = 0`,
  entrée repoussée en fin de chaîne, la Vue écrit « round inconnu » plutôt qu'un round inventé.
- **`timeline_window(series, from, to)`** → tranche des séries **déjà** construites pour la courbe du
  BILAN : la mini-vue du moment décisif ne peut pas raconter une autre histoire que la grande courbe.
- **`self_check()`** (pattern G4 §8.63) — enchaîné dans `operation_report._self_check()` : un seul
  boot du Rapport en build debug couvre les deux modules.

> ⚠️⚠️ **ÉCART ASSUMÉ AVEC LA DÉFINITION PRODUIT.** La clause « … alors qu'ils étaient **VOISINS
> depuis ≥ 2 rounds** » n'est **PAS calculable** : `territory_history` ne stocke que des **COMPTES**
> de territoires (jamais la propriété), et le journal d'attaques ne porte pas d'id de territoire
> (§8.121.5 du contrat réseau). Reconstituer un voisinage par round exigerait un champ backend plus
> lourd que le journal lui-même. La notion est donc portée **entièrement** par la durée de **CALME**
> (`calm_rounds`), qui en capture l'intention (« ils se laissaient tranquilles, et soudain… »).
> **Documenté plutôt que deviné** (règle « interdiction de deviner »).

### 2. 5ᵉ onglet « TRAHISONS » (`operation_report.gd`)

`populate_betrayals(data)` — Vue **PURE** : `main._betrayal_data()` résout tout (module + pseudos
avec préfixe `[IA]` + couleurs **PLATEAU** via `board.get_player_color`). Quatre sections dans
l'ordre du récit : **coup de poignard** (RichTextLabel, les deux pseudos teintés — seul moyen de
colorer deux fragments d'une phrase traduite dont l'ordre des mots varie ; pseudos **échappés**,
piège n° 1) · **moment décisif** + mini-courbe · **matrice** (cellules teintées par intensité,
liseré **or** sur la case max, en-têtes tronqués à **5 car. après retrait du préfixe `[IA]`** —
à 4 car. **tous les bots s'affichaient « [IA] »** et devenaient indistinguables, défaut vu en
capture ; l'infobulle porte le nom complet) · **chaîne des chutes**
(`☠`, `◆` pour une mise à mort de héros).

- **Onglet MASQUÉ** (`set_tab_hidden`) tant qu'aucune unité n'est tombée entre joueurs — le nœud
  reste dans l'arbre (aucune retouche `.tscn`, piège n° 6). Une partie **sans trahison mais avec des
  combats** reste VISIBLE : « GUERRE FRONTALE » est une information, pas un trou.
- Peuplé **uniquement** depuis `_on_match_over` : le journal n'arrive **qu'avec** le `game_over`.
- Bots **inclus** dans l'analyse (ils font partie de l'histoire) mais étiquetés `[IA]` comme partout.
- Glyphes de charte (`✸ ☠ ◆ ❯`), **aucun emoji** (purge globale §8.102) — le `⚡` du cahier des
  charges aurait rendu en « tofu » sur la police condensée.

### 3. Révélation THÉÂTRALE des objectifs (LOT C)

Les objectifs secrets apparaissent **un par un**, du **DERNIER** du classement au **VAINQUEUR**,
`REVEAL_STEP_S = 1,2 s`, chaque carte « se retournant » (fondu + écrasement vertical
`REVEAL_FLIP_S = 0,35 s`) avec un sting ; le vainqueur a le sting **appuyé** (`conquest`, déjà au
catalogue — on ne crée pas un 11ᵉ son) et une **pulsation** de sa ligne.

- **Ce n'est pas un flux de données neuf** : mise en scène de l'`objectives_reveal` déjà reçu (§8.83).
- **Cadencé dans `_process`** et non par `await create_timer` : le rapport peut être libéré en cours
  de séquence (retour au QG / re-file) — une coroutine se réveillerait sur un objet détruit.
- **Skippable** : `_input` déclenche `skip_reveal()` **sans consommer l'évènement** → le clic atteint
  aussi le bouton visé, donc la mise en scène n'« avale » jamais un clic sur **REJOUER**. Idempotent.
- `reduced_motion` (E10 §8.82) → pose **instantanée**, aucun son, aucune attente.
- Joué **uniquement sur le podium DÉFINITIF** (`provisional == false`) et **une seule fois**
  (`_reveal_played`) : le podium provisoire (§8.100) ne porte aucun objectif révélé, et un re-push
  doublerait la séquence.
- État caché = `modulate.a = 0` (jamais `visible = false`) → **aucun saut de layout** pendant la
  séquence.
- ⚠️ L'indice `REVEAL_SKIP_HINT` est posé dans l'**ONGLET**, jamais dans `_podium_list` : cette
  boîte est « **UN enfant par belligérant** », invariant vérifié par `tools/test_e11_report.gd` et
  cassé par une première version de ce bloc.
- ⚠️ **Écart assumé** : la séquence **force l'onglet CLASSEMENT** (une mise en scène jouée sur un
  onglet masqué n'existe pas) — seul endroit du rapport où le programme choisit l'onglet.
- ⚠️ **Écart assumé** : le volet REMPLI reste `✓` **vert** (et non « ✔ or » comme proposé) — c'est le
  code couleur validé en §8.100 (`✓` vert / `✕` acier) ; l'or reste réservé au vainqueur.

### 4. CARTE DE PARTAGE (LOT D) — `scripts/game/share_card.gd`

Compositeur **offscreen** : `SubViewport` → `get_texture().get_image().save_png()`, composition
**100 % code**, aucun asset nouveau (la MARQUE existante + `wasteland-warfare.com` en filigrane
— décision n° 4 : c'est un objet marketing, il ramène vers le jeu).
- **Filigrane = `assets/images/logo_mark.svg`** (emblème biohazard carré, la marque CANONIQUE du
  jeu, déjà utilisée par `title_splash`, `top_nav`, `warzone_ui`, `ww_logo`). ⚠️ **Ne PAS reprendre
  `logo_ww.png`** : ce lockup large (2400×1308) porte du lettrage fin qui devient illisible en
  filigrane — défaut **vu en capture** et écarté par Hakim. Un SEUL filigrane, au pied de la carte
  (une seconde occurrence en en-tête se disputait l'attention avec le verdict).

- **`FORMATS`** : `1920×1080` (**deux colonnes** — héros à gauche, courbe + podium à droite) et
  `1080×1920` (**empilé** — l'ordre de lecture change, ce n'est **pas** une mise à l'échelle).
- Bouton **`❯ CARTE DE PARTAGE`** dans l'**EN-TÊTE** du rapport (rangée alignée à droite sous le
  titre) et non dans la pile de CTA : celle-ci est déjà à 3 boutons pleine largeur, un 4ᵉ aurait
  poussé les onglets hors du panneau.
- Export → `user://captures/ww_<AAAAMMJJ_HHMMSS>_<format>.png`, puis **toast** `SHARE_CARD_SAVED`,
  bouton **`OUVRIR LE DOSSIER`** (`OS.shell_open`, n'apparaît qu'**après** un export réussi) et
  **résumé TEXTE** dans le presse-papiers.
- ⚠️ **Aucune copie d'image dans le presse-papiers** (décision n° 3) : Godot 4 n'a pas d'API
  portable. `SHARE_CLIPBOARD_SUMMARY` utilise des **placeholders nommés** (`{verdict}`, `{faction}`,
  `{duration}`, `{kills}`, `{conquests}`, `{betrayals}`, `{site}`) pour que chaque langue réordonne.
  Repli en dur si la clé manque — on n'écrit jamais « SHARE_CLIPBOARD_SUMMARY » dans le
  presse-papiers du joueur.
- **Échec honnête** : disque/droits refusés → `SHARE_CARD_FAILED` (un « 2 images enregistrées »
  mensonger enverrait le joueur chercher des fichiers inexistants).
- **Performance** : rien n'est construit avant le clic ; chaque `SubViewport` est **libéré** dès son
  PNG écrit. Anti double-clic (`_share_busy`) : deux exports concurrents créeraient deux viewports
  1920×1080 simultanés et deux horodatages pour la même partie.
- **Thème posé sur la racine de la composition** : le SubViewport n'hérite pas du thème de
  `operation_report.tscn` — sans lui, la carte serait rendue dans la police par défaut de Godot.
- **Deux frames** avant la capture : la 1ʳᵉ laisse les conteneurs résoudre leur mise en page (sinon
  tout est empilé en (0,0) sur l'image), la 2ᵉ dessine.
- ⚠️⚠️ **PIÈGE MAJEUR — carte rendue au DOUBLE de sa taille.** `compose()` bâtit un arbre
  **DÉTACHÉ**. `set_anchors_preset(PRESET_FULL_RECT)` (sans les offsets) recalcule les offsets pour
  « conserver le rect courant » **contre un parent de taille 0** → `offset_right` reste à 1920, et
  une fois greffé dans le viewport la taille devient `ancre(1920) + offset(1920) = 3840`. Le
  contenu se mettait en page sur **2× la largeur** et le PNG était un cadrage tronqué (titre coupé
  en 9:16). Correctif : **`set_anchors_and_offsets_preset`**, et surtout **ne jamais écrire
  `root.size` avant**. Trouvé uniquement par une sonde qui imprimait `rect` vs `get_combined_minimum_size`
  de chaque bloc — invisible au boot « 0 ERROR ».
- **Marges MESURÉES, pas choisies** : en 16:9, 72 px de marge + la hauteur minimale du contenu
  (942 px) dépassaient les 1080 px du cadre et **éjectaient les deux derniers blocs** (ligne de
  trahison + filigrane) hors de l'image. Marge portée à **56 px** et graphique à 300 px de haut →
  ~26 px de jeu. En 9:16, les tuiles de chiffres passent de 300 à **280 px** (3 × 300 + 32 = 932 sur
  952 utiles ne laissait que 20 px).
- **Durée annoncée** : mesurée CÔTÉ CLIENT depuis l'entrée dans l'arène (`main._arena_entered_at`).
  Le serveur n'expose que l'**échéance** (`match_deadline_epoch`, §8.120), jamais l'instant de
  création de l'état → l'écart avec la durée serveur est le draft (≤ 60 s) + le placement (≤ 90 s),
  assumé pour un objet marketing.

### 5. `scripts/ui/timeline_chart.gd` — courbe de domination EXTRAITE

La `TimelineChart` était une **classe interne** d'`operation_report.gd`. Elle est désormais un
fichier autonome : la carte de partage et la mini-vue du moment décisif dessinent la **même** courbe,
et un `preload` croisé `share_card` ↔ `operation_report` aurait créé une **inclusion cyclique de
ressources**. `setup()`/`_draw()` repris **à l'identique** ; `line_width` et `grid_alpha` deviennent
paramétrables (défauts = valeurs historiques du Rapport). `operation_report` la reprend via
`const TimelineChart := preload(...)`, utilisable comme **type** — le reste du fichier est intouché.

### 6. MODE STREAMER (LOT E)

Réglage **`streamer_mode`** (défaut **OFF**) dans `SettingsManager.COMFORT_DEFAULTS` (même contrat
qu'un réglage d'accessibilité : une clé, un défaut, un signal, appliqué **à chaud** sans
redémarrage) + bascule dans **Paramètres › CONFORT**, avec une ligne d'explication muette.

- En partie, la zone **OBJECTIFS** et le **tracker** sont couverts par une plaque
  **`⬛ INTEL CLASSIFIÉ — MAINTENIR POUR RÉVÉLER`** : **maintien du clic** (`button_down`/`button_up`)
  **ou survol > 0,6 s** (`INTEL_HOVER_DELAY`) révèle, et la sortie du curseur **referme aussitôt**.
- Un vrai `Button` (et non un `gui_input` sur le conteneur) : il expose le maintien nativement et
  **n'exige aucune retouche des `mouse_filter`** de la barre basse — un `STOP` posé là casserait le
  clic des widgets voisins (piège connu).
- Posé **en dernier** dans `hud._ready` : `_apply_charter_ornaments` a déjà glissé son filet de titre
  dans la zone OBJECTIFS en comptant sur l'ordre des enfants.
- `_objective_has_lines` : démasquer ne rend **pas** visible un tracker vide (objectif non résolu /
  spectateur).
- **Espionnage** (Chasseurs d'Ombres §8.24) : en mode streamer, le renseignement passe par la **MÊME
  plaque** (`hud.set_spy_intel`) et le chat/Journal ne reçoivent qu'une ligne **neutre**
  (`INTEL_CLASSIFIED_SHORT`). Une ligne de journal ne peut pas se « maintenir pour révéler » — la
  laisser en clair aurait rouvert exactement la fuite que ce mode ferme.
- La révélation de **FIN** de partie (LOT C) reste normale : la partie est finie.
- ⚠️ **Le draft n'affiche AUCUN objectif** (vérifié : `faction_selection.gd` n'en parle pas — les
  objectifs sont attribués par le serveur *après* le draft). Le point « objectif affiché au draft »
  du cahier des charges est donc **sans objet**, rien à masquer.
- Rien d'autre ne change : pas de délai de flux, pas de masquage des PP/stats — l'objectif est la
  seule information exploitable par un stream-sniper.

### 7. i18n (42 clés ajoutées en fin de `translations/ui_strings.csv`, FR/EN/IT)

`TAB_BETRAYALS` · `BETRAYAL_STAB_TITLE` · `BETRAYAL_BACKSTAB` · `BETRAYAL_NONE` ·
`BETRAYAL_UNITS_FMT` · `BETRAYAL_CALM_FMT` · `BETRAYAL_STAB_HERO` · `BETRAYAL_STAB_CONQUEST` ·
`BETRAYAL_TURN_TITLE` · `BETRAYAL_TURNING_POINT` · `BETRAYAL_TURNING_POINT_UP` ·
`BETRAYAL_SWING_FMT` · `BETRAYAL_MATRIX_TITLE` ·
`BETRAYAL_MATRIX_ROWS` · `BETRAYAL_MATRIX_LEGEND` · `BETRAYAL_CHAIN_TITLE` ·
`BETRAYAL_CHAIN_ROUND_FMT` · `BETRAYAL_CHAIN_ROUND_UNKNOWN` · `BETRAYAL_CHAIN_LEGEND` ·
`REVEAL_SKIP_HINT` · `SHARE_CARD_BUTTON` · `SHARE_CARD_WORKING` · `SHARE_CARD_SAVED` ·
`SHARE_CARD_FAILED` · `SHARE_OPEN_FOLDER` · `SHARE_CLIPBOARD_SUMMARY` · `SHARE_CARD_TIMELINE` ·
`SHARE_CARD_PODIUM` · `SHARE_VERDICT_WIN` · `SHARE_VERDICT_LOSS` · `SHARE_REASON_OBJECTIVE` ·
`SHARE_REASON_ELIMINATION` · `SHARE_REASON_ABANDON` · `SHARE_STAT_KILLS` · `SHARE_STAT_CONQUESTS` ·
`SHARE_STAT_DURATION` · `STREAMER_MODE_LABEL` · `STREAMER_MODE_HINT` · `INTEL_CLASSIFIED` ·
`INTEL_CLASSIFIED_SHORT` · `INTEL_REVEALED` · `INTEL_SPY_LINE`.

Aucune clé supprimée. CSV **LF / UTF-8 sans BOM** (**1 242 clés**, **0 doublon**, 4 colonnes
partout), `.translation` régénérés par `--import`.

### 8. HORS PÉRIMÈTRE (non fait, à dessein)

Marqueurs **Steam Timelines** / succès / Rich Presence (chantier Steamworks) — les points d'ancrage
naturels sont commentés dans le code aux trois sites concernés (élimination, coup de poignard,
victoire) · replays vidéo · partage réseau direct (API Twitter & co) · overlay de spectateur externe
· pactes de diplomatie (le Rapport de Trahison les intégrera plus tard).

> **Fichiers.** NOUVEAUX : `scripts/game/betrayal_report.gd`, `scripts/game/share_card.gd`,
> `scripts/ui/timeline_chart.gd`, `tools/test_betrayal_report.gd`/`.tscn`,
> `tools/preview_betrayals.gd`/`.tscn`, `tools/preview_share_card.gd`/`.tscn`.
> MODIFIÉS : `scripts/game/operation_report.gd`, `scripts/game/main.gd`, `scripts/ui/hud.gd`,
> `scripts/ui/settings.gd`, `scripts/managers/settings_manager.gd`,
> `scripts/managers/network_manager.gd`, `translations/ui_strings.csv`,
> `tools/test_e11_report.gd` (l'assert « 4 onglets » devient « 5 onglets, le 5ᵉ masqué sur payload
> legacy » — changement de contrat ASSUMÉ de ce chantier).
> **Aucun `.tscn` de jeu retouché** (tout est construit par code).
>
> **Validation.**
> - `--import` **exit 0, 0 ERROR** (les 3 `.translation` régénérés) ;
> - **boots headless 0 ERROR** : `main_menu`, `game/main`, `game/operation_report`, `ui/settings`,
>   `ui/spectator_overlay`, `ui/search_screen`, `faction_selection` ;
> - `tools/test_betrayal_report.tscn` — **51 asserts OK / 0 KO** (module pur : matrice avec bots en
>   ids négatifs, coup de poignard qualifié + départages, moment décisif, chaîne des chutes,
>   journal vide/pourri ; rapport COMPLET → 5 onglets + onglet TRAHISONS visible + 4 sections ;
>   rapport LEGACY → onglet masqué ; « guerre frontale » → onglet quand même visible ; analyse
>   entièrement vide → masqué ; révélation : ordre `[5, -2, 1]` dernier→vainqueur, `reduced_motion`
>   instantané, SKIP idempotent, REJOUER jamais bloqué, podium provisoire sans séquence ; carte de
>   partage : 2 compositions dimensionnées et peuplées, payload minimal dégradé, résumé texte) ;
> - **non-régression** `test_e11_report` **34 asserts verts**, `test_e10_comfort` 16,
>   `test_e5_warroom` 36, `test_e1_roster` 11, `test_e2_vs` 7, `test_e3_timer` 9,
>   `test_e7_command` 10, `test_e8_combat_rhythm` 6, `test_e9_feedback` 14,
>   `test_hero_stats_view` 31 ;
> - **contre-épreuve de l'outillage** : un assert de `BetrayalReport.self_check()` saboté à 999 fait
>   bien remonter `SCRIPT ERROR: Assertion failed.` au boot d'`operation_report.tscn` (donc
>   l'auto-vérification tourne RÉELLEMENT) ; source **restaurée dans le même bloc**, vérifiée
>   identique à la sauvegarde, aucun marqueur résiduel ;
> - **PREUVE VISUELLE** (`tools/preview_betrayals.tscn` + `tools/preview_share_card.tscn`, lancement
>   FENÊTRÉ) : 3 captures du Rapport (révélation à mi-course, après SKIP, onglet TRAHISONS) et les
>   **2 PNG réellement écrits sur disque** en `1920×1080` et `1080×1920`, **0 WARNING / 0 ERROR**.
>   C'est cette recette — et non les boots — qui a débusqué les quatre défauts de mise en page
>   corrigés ci-dessus (doublement de la carte, blocs éjectés, logo illisible, en-têtes « [IA] »).
>
> ⚠️ **3 tests de tooling en échec PRÉ-EXISTANT** (fichiers testés **intacts**, vérifié par
> `git diff`) : `test_e6_objective` et `test_e4_feed` codent des libellés **français en dur**
> (« 14/24 territoires », « ravagé ») alors que la machine tourne en **`locale=it`**
> (`user://settings.cfg`) ; `test_w_roster` accède à `characters_screen.detail_box`, propriété qui
> **n'existe plus** (dérive d'API). Aucun lien avec ce chantier — à traiter séparément.
>
> ⚠️⚠️ **CE QUI N'A PAS ÉTÉ VU** (aucune partie réelle n'a pu être jouée : le serveur de prod n'a
> pas le journal d'attaques tant que le VPS n'est pas redéployé) : l'onglet TRAHISONS **peuplé par
> de vraies données de partie**, la plaque « INTEL CLASSIFIÉ » **en jeu** (maintien du clic, survol
> 0,6 s, cohabitation avec le filet de titre de la zone OBJECTIFS), le renseignement d'espionnage
> masqué, et le bouton « OUVRIR LE DOSSIER » après un export **depuis l'arène**.

---

## §8.122 — SENSORIEL & IMMERSION : intensité de guerre, musique dynamique, ambiances, carte vivante, célébrations

> **Chantier 100 % FRONTEND.** Aucun endpoint, aucun message WebSocket, **aucune modification de
> `CONTRAT_RESEAU.md`** : tout se dérive de l'**état public déjà diffusé**. Sept lots (A→G).
> Objectif : faire **sentir** la guerre — l'écran disait ce qui se passait, il ne le faisait pas
> ressentir.

### §8.122.1 — LOT A : `war_intensity`, la jauge de tension UNIQUE

`scripts/game/war_intensity.gd` (`class_name WarIntensity`) — **fonctions STATIQUES pures**, zéro
I/O, zéro autoload : testable sans scène.

**Formule** (constantes nommées en tête du fichier, à équilibrer au playtest) :

| Terme | Poids | Source (état public) |
|---|---|---|
| Durée de partie | `0,30 × min(round / 8, 1)` | `current_turn` |
| Héros qui saignent | `0,25 × (1 − moyenne des PV% VIVANTS)` | `players[*].hero_pv_*` |
| MES PV | `0,15 × (1 − mes PV%)` | `GameState.hero_of(moi)` |
| Zone radioactive | `0,15 × min(zone_count / 8, 1)` | `contamination_zone.territories` |
| PROTOCOLE FINAL | `+0,25` | `final_protocol_active` |

Le tout **clampé [0,1]**, puis **plancher `FINAL_PROTOCOL_FLOOR = 0,85`** si le PROTOCOLE FINAL est
armé. Ce plancher n'est pas cosmétique : sans lui, un protocole déclenché tôt sur une partie propre
rendait ≈ 0,38 — donc aucune couche musicale « high », aucune vignette — alors que l'écran, lui,
annonçait l'urgence.

**Lissage** `smooth(current, target, delta)` : exponentiel `1 − e^(−0,4·dt)`, **indépendant du
framerate** (τ = 2,5 s). Un `lerp` naïf aurait fait monter la musique 5× plus vite sur un PC rapide.

**Propagation — UN SEUL chemin** (`main.gd`) : `_refresh()` recalcule la **cible**, `_process()`
lisse et pousse. Aucun consommateur ne lit `GameState` :

```
état serveur → main._update_war_intensity_target()   (à chaque état reçu)
             → main._process()  → AudioManager.set_war_intensity(v)   (LOT B)
                                → board.set_war_intensity(v)          (LOT E)
```

Un **epsilon de 0,005** évite de repousser une valeur qui ne change rien d'audible ni de visible.

> ⚠️ **INVARIANT** : il n'existe **qu'une** formule de tension. Un consommateur qui veut « sa »
> tension ajuste **ses seuils**, jamais une 2ᵉ formule — sinon la musique, le son et l'image
> racontent trois guerres différentes.

Harnais : `tools/test_war_intensity.tscn` (**18 asserts**) — fourchettes de recette (début
0,05-0,15 · fin serrée 0,70-1,00), monotonie, plancher, indépendance au framerate.

### §8.122.2 — LOT B : musique dynamique à couches

`audio_manager.gd` — à côté du `_music_player` historique (**conservé**, c'est le chemin des menus
ET le repli), un trio `_battle_layers` sur le bus `Music` :

- **Mode couches activé UNIQUEMENT si les TROIS stems existent** (`music/battle_base|mid|high`).
  Un seul manquant → `battle_ambient`, comportement **strictement inchangé**, **aucun log d'erreur**
  (le cas « fichiers absents » est le cas nominal tant que la production audio n'a pas livré).
- Les trois `play()` partent dans la **même frame** (boucles alignées à l'échantillon).
- Bandes avec **hystérésis 0,05** : `mid` entre à `v > 0,35` / sort à `v < 0,30` ; `high` entre à
  `v > 0,65` / sort à `v < 0,60`. Fondus de 1,5 s.
- **Resynchronisation défensive** toutes les 60 s : dérive > 50 ms → `seek` sur la base, `print`
  silencieux.
- **`duck_music(amount_db, duration)`** : la musique s'efface sous un sting puis revient. Appelée
  sur **4 moments** — sting de finisher (`hero_down_cinematic`), mise à mort (`split_screen_vs`),
  PROTOCOLE FINAL (`main.gd`), révélation du **vainqueur** (`operation_report`, §8.121).

> 🔧 **Refactor de `_fade_music_in`** : le fondu pilote désormais le niveau **nominal**
> (`_music_base_db`) et non `volume_db` en direct. Volume réel = `nominal + offset de ducking`.
> Sans ça, un ducking déclenché **pendant** le fondu d'entrée était écrasé à la frame suivante.

### §8.122.3 — LOT C : ambiances diégétiques (bus `Ambience`)

Nouveau bus **`Ambience`** dans `default_bus_layout.tres` (routé Master, −12 dB au repos) + slider
« AMBIANCE » dans Paramètres (défaut **0,25 linéaire = −12 dB**). Nouvelle catégorie d'override :
`assets/audio/amb/` (`_load_override("amb", nom)`).

| Ambiance | Où | Niveau |
|---|---|---|
| `geiger` | Arène | **−6 / −14 / −22 dB** selon la distance (0/1/2 sauts), coupé au-delà — fondu 1 s |
| `wind` | Arène | −18 dB fixe |
| `radio_hub` | **QG uniquement** | −20 dB fixe |

**Geiger proportionnel à la menace** — `main._zone_distance_to_me()` : **BFS multi-source** depuis
la zone contaminée vers mes territoires, **borné** à la profondeur du dernier palier audible.
Recalculé **à chaque état reçu**, jamais en `_process`. On part de la zone (1 à 8 nœuds) plutôt que
de mes territoires (jusqu'à 42) : c'est le plus petit des deux fronts.

> ⚠️ **Le Geiger n'est PAS piloté par `war_intensity`** — et c'est délibéré. Il ne mesure pas la
> tension globale, il mesure « la radioactivité est à N territoires de chez moi ». Le brancher sur
> l'intensité le ferait crépiter en fin de partie même à l'autre bout de la carte : il **mentirait**
> sur ce qu'il indique. C'est le seul écart au principe « une seule source de tension », et il est
> assumé.

**Cycle de vie sans bookkeeping de scène** : `start_menu_ambient()` coupe couches + vent + Geiger +
radio ; `start_battle_ambient()` coupe la radio ; le menu principal **rallume** la radio juste après.
Un `_exit_tree` d'arène n'aurait couvert qu'un chemin de sortie sur quatre (victoire, abandon,
élimination, coupure réseau).

**Talkie chat** (`hud.gd`) : `radio_crackle` **puis** `chat_ping` 60 ms plus tard — le message cesse
d'être un « bip d'appli ».

### §8.122.4 — LOT D : carte vivante (`AmbientLayer`)

Deux nœuds neufs dans `board.tscn` + `scripts/game/ambient_layer.gd` (orchestrateur, **VUE PURE** :
il ne lit **jamais** `GameState` — `board.generate_board()` lui passe un contexte résolu).

**⚠️ ORDRE DE RENDU (documenté, car l'ordre d'arbre ne suffit pas)** — `TerritoryOverlay` et
`BadgeLayer` sont ajoutés **par code**, donc *après* les nœuds de la scène :

| Nœud | z_index | Origine |
|---|---|---|
| `BoardBackground` · `AmbientBack` · `TerritoriesContainer` · `TerritoryOverlay` | 0 | .tscn / code |
| **`AmbientFront`** | **1** | .tscn |
| **`BadgeLayer`** | **2** | code (`board.gd`) |
| `attack_arrow` · flèche d'intention | 40 · 50 | code |

Cinq effets : **cendres** (40, calque arrière) · **fumées de guerre** (pool de 10 émetteurs
recyclés, 24 particules au round courant → 12 au round−1 → extinction au round−2) · **feux de camp**
(la « capitale » = plus grosse garnison, égalité tranchée **alphabétiquement** pour que le feu ne
saute pas d'un refresh à l'autre) · **éclairs de zone** (8-15 s, flash blanc-vert α 0,30 +
`thunder_far`) · **nuée d'oiseaux** (60-90 s, Bézier en 6-8 s, **un seul Tween**, sautée pendant un
combat via `board.set_ambient_busy`).

**Budget : 40 + 10×24 + 6×8 = 328 particules ≤ 500** (vérifié par assert). Tous les émetteurs en
`local_coords = false`. Aucune allocation en `_process`. **Un seul** appel de refresh, en fin de
`generate_board()`.

> 🔧 Le flash d'éclair passe par **`board.flash_territory_color()`**, extrait de `flash_territory` :
> depuis l'overlay « vraies frontières » (§8.51) il n'existe plus de matériau `toxic_pulsation` par
> territoire à faire pulser — c'est le repli prévu au cahier des charges, et il épouse la vraie côte.

### §8.122.5 — LOT E : cycle de tension visuel

`shaders/tactical_map.gdshader` — uniforme `war_intensity` (défaut 0 = rendu historique **à
l'identique**). Trois effets, **tous plafonnés** (constantes commentées dans le shader) :

| Effet | Plafond (à intensité 1,0) |
|---|---|
| Désaturation du fond de carte | **15 %** |
| Vignette périphérique | **0,25** d'opacité |
| Virage des **coins** vers le rouge sombre | **8 %** |

La vignette démarre au rayon normalisé **0,55** : sous ce seuil la **zone centrale de jeu conserve
exactement sa luminosité d'origine**, à toute intensité. Le shader **ne touche pas** aux
remplissages ni aux liserés de territoires — ils vivent dans `territory_overlay.gdshader`, un
Sprite2D distinct dessiné par-dessus. C'est ce qui garantit que la tension ne peut **pas** dégrader
le contraste des couleurs de joueur, du télégraphe ou des cibles.

`board.set_war_intensity(v)` pousse l'uniforme (valeur déjà lissée en amont) ; `board._ready()` la
remet à 0 — `tactical_map_material.tres` est une ressource **partagée mise en cache**, une partie
quittée à 0,9 aurait rouvert la suivante avec la vignette déjà en place.

En `reduced_motion` l'uniforme **reste appliqué** (c'est statique, pas du mouvement).

### §8.122.6 — LOT F : célébrations du hub

1. **Confirmation d'achat SYSTÉMATIQUE** (`shop.gd`) — nom + prix + **« SOLDE APRÈS ACHAT : N ¢ »**
   + CONFIRMER/ANNULER. Pas d'option « ne plus demander » (décision produit). Les packs **fiat** en
   sont exclus : le flux d'argent réel a sa propre confirmation, hors du jeu.
2. **Compteur de Coins animé** — `xp_coins_bar.animate_coins_to()` (décompte 0,6 s + flash or), qui
   **réutilise** `_flash_coins()` du Rapport Post-Op. `shop.gd` capture le solde **avant** que
   l'inventaire ne l'écrase, sinon on tweenerait de la valeur finale vers elle-même.
3. **Chip « NOUVEAU »** — `user://seen_items.json` via `SettingsManager.is_item_seen/mark_item_seen`.
   Article possédé jamais consulté → chip or (boutique + écran Personnages). Ouvrir la fiche
   l'enregistre. **Aucun appel réseau** : le serveur ne sait pas ce que le joueur a « déjà regardé ».
4. **Séquence d'unlock** — `scenes/ui/unlock_celebration.tscn` (100 % code, générique) :
   assombrissement 0,25 s → **silhouette** noire 0,40 s → révélation (`TRANS_BACK` 1,15→1,0) + sting
   + ~30 particules or. **1,15 s animés** (contrat ≤ 2,5 s), clic = skip, `reduced_motion` =
   affichage direct. Déclenchée pour personnage / skin / finisher (un Pass n'a pas d'objet à révéler).
5. **Pulse d'équipement au draft** (`faction_selection.gd`) — signature **triée** de la panoplie
   (le finisher voyage dans le même bloc `equipped`, slot `__finisher__`) comparée à celle du dernier
   draft ; si elle a changé → pulse unique du présentoir (1,06 · 0,4 s). Le tri est indispensable :
   l'ordre des clés JSON n'est pas garanti, une signature instable ferait pulser à chaque draft.
6. **Toast de promotion** (`top_nav.gd`) — au retour du profil **déjà fetché**. Règle :
   **division changée ET points en hausse**. Points en baisse ⇒ relégation **ou** reset de saison :
   dans les deux cas **RIEN** (on ne célèbre pas la douleur, on ne la souligne pas non plus).
   Première lecture ⇒ on mémorise sans célébrer.
   > ⚠️ `/auth/me` expose `division` et `season_points`, **pas l'échelon**. Le toast affiche donc
   > « ▲ PROMOTION : OR » et non « OR II » ; l'échelon s'affichera **automatiquement** si le champ
   > arrive un jour dans le payload. Le **dériver** côté client imposerait de recopier les seuils du
   > ladder — exactement le genre de duplication qui finit par diverger du serveur.

Mémoires locales : section **`[progress]`** de `settings.cfg` (`get_progress`/`set_progress`).

### §8.122.7 — LOT G : réglages, i18n, validation

- **Paramètres** : 4ᵉ slider **AMBIANCE** (bloc AUDIO, construit par code — zéro retouche de
  `.tscn`, donc zéro risque sur les NodePath `@export`) · toggle **CARTE VIVANTE** (section CONFORT,
  défaut ON, **grisé + mention** quand `reduced_motion` est actif). Basculer `reduced_motion`
  **reconstruit** la section pour que le joueur voie la conséquence de son propre clic.
  > Le forçage vit dans le **consommateur** (`ambient_layer`), pas dans `SettingsManager` : le
  > joueur retrouve son choix intact s'il décoche `reduced_motion`.
- **i18n (FR/EN/IT)** — 11 clés : `SETTINGS_AMBIENCE` · `SETTINGS_LIVING_MAP` (+ `_HINT`) ·
  `SHOP_CONFIRM_TITLE` · `SHOP_CONFIRM_BALANCE` · `SHOP_CONFIRM_OK` · `SHOP_CONFIRM_CANCEL` ·
  `SHOP_NEW_BADGE` · `UNLOCK_EYEBROW` · `UNLOCK_CONTINUE` · `TOAST_PROMOTION`.
- **README audio enrichi** (`assets/audio/README.md`) : tables « MUSIQUE DYNAMIQUE » (durées/BPM
  identiques obligatoires, seuils, repli) et « AMBIANCES » (dossier `amb/`, rôles, volumes cibles).
  C'est le **bon de commande** de la production audio.

**Validation exécutée :**

| Contrôle | Résultat |
|---|---|
| `--import` headless | **0 ERROR** |
| Boot `main` · `main_menu` · `shop` · `settings` · `faction_selection` · `characters_screen` | **0 ERROR** chacun |
| `tools/test_war_intensity.tscn` | **18 asserts verts** |
| `tools/test_ambient_layer.tscn` (LOTS C/D/E) | **33 asserts verts** |
| `tools/test_hub_celebrations.tscn` (LOT F) | **24 asserts verts** |
| `CONTRAT_RESEAU.md` | **inchangé** (critère de recette) |

> ⚠️⚠️ **CE QUI N'A PAS ÉTÉ VU.** La validation ci-dessus est **fonctionnelle**, pas visuelle ni
> sonore. N'ont **pas** été vérifiés à l'œil / à l'oreille : le rendu de la vignette et de la
> désaturation **en partie réelle** (et donc la recette « mode daltonien parfaitement lisible à
> intensité 1,0 », qui reste À FAIRE) ; la mise en page des deux nouvelles rangées de Paramètres ;
> le dialogue de confirmation d'achat et la séquence d'unlock **à l'écran** ; le toast de promotion
> (il exige une vraie montée de division) ; le framerate en partie **6 joueurs** carte vivante ON.
> Les placeholders audio (Geiger, vent, radio, tonnerre, promotion) n'ont **jamais été écoutés** :
> ils sont synthétisés et validés par le code, pas par l'oreille.

---

## §8.123 — PACTES DE NON-AGRESSION : proposer, répondre, voir, trahir (volet FRONTEND)

> Contrat réseau : **§8.123 de [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md)**. Règle de jeu : **§4.11 de
> `ARCHITECTURE_ET_REGLES.md`**. **Client et serveur partent ENSEMBLE** (gate de version WS §9) :
> face à un serveur non redéployé, tout ce qui suit se masque de soi-même (`GameState.pacts` vide).
>
> ⛔ **Le client ne DÉCIDE rien** (Règle d'Or §6.1). Il grise des boutons et raconte des évènements ;
> le serveur reste seul juge. Un désaccord entre le grisage local et le serveur ne produit qu'un
> refus propre et traduit, jamais un état incohérent.

### 1. `scripts/game/pact_state.gd` — lectures pures (`class_name PactState`)

Miroir client de `api/game/pacts.py`, réduit à ce dont une Vue a besoin : `active_partners`,
`find_active_between`, `my_active`, `incoming_offer`, `outgoing_offer`, `has_pending_between`,
`is_traitor`, `find_by_id`, `is_still_pending`.

⚠️ **`GameState.pacts` est DÉJÀ REDACTÉE POUR NOUS** par le serveur : les négociations d'autrui n'y
figurent tout simplement pas. Il n'y a donc **rien à filtrer** côté client — et surtout aucune
tentation de « masquer à l'affichage » une donnée qu'on n'aurait pas dû recevoir.

### 2. Les DEUX marques, posées dans `player_chip.gd` (donc PARTOUT d'un coup)

| Marque | Sens | Couleur |
|---|---|---|
| **`↔`** | ce joueur est lié par ≥ 1 pacte ACTIF ; tooltip « PACTE X ↔ Y — EXPIRE AU ROUND N » (les deux, s'il en tient deux) | cyan tactique |
| **`⚡`** | ce joueur a rompu un pacte **ce match** — reste jusqu'à la fin de la partie | rouge danger |

Posées dans la **brique partagée** et non dans chaque écran : elles apparaissent donc du même coup
dans l'ordre de tour, la fiche joueur, le kill feed et la zone joueur. Les deux sont relues à
chaque `setup()` (donc à chaque état) — la brique ne mémorise rien, un pacte qui expire fait
disparaître sa marque tout seul.

⚠️⚠️ **GLYPHE `↔` ET NON L'EMOJI 🤝 DU CAHIER DES CHARGES.** Les emoji hors BMP (> U+FFFF) rendent
en **TOFU** avec la police condensée de la charte — constat §8.117 (`📢 ✉ 🎯`), et 🤝 (U+1F91D) est
du même bloc que 🎯. `↔` vit dans le bloc *Arrows* (voisin de `→`, déjà employé), dit exactement la
même chose (un accord à **double sens**) et figurait déjà dans le libellé du tooltip spécifié.
Même règle que les flèches ▲/▼ des PP (§8.119). `⚡` (U+26A1), lui, est déjà utilisé 21 fois dans
`ui_strings.csv` : conservé tel quel.

### 3. PROPOSER — bloc PACTE de la fiche joueur (`hud.gd`)

Bouton « ↔ PROPOSER UN PACTE (2 ROUNDS) », sous les blocs HÉROS et SITUATION. **Jamais de bouton
mort et muet** : quand la proposition est impossible, il reste **visible mais grisé** et son
**tooltip dit POURQUOI** (plafond, trêve **avec le nombre de rounds restants**, offre déjà pendante,
PROTOCOLE FINAL, cible hors jeu). Les raisons sont évaluées dans le **MÊME ORDRE que le serveur**
(`pacts.can_offer`) : le joueur lit toujours la raison que le serveur lui opposerait.

- Après le clic : « OFFRE ENVOYÉE… » **immédiatement** (optimiste — le joueur doit voir qu'il s'est
  passé quelque chose), la vérité serveur reprenant la main à l'état suivant.
- Pacte déjà actif avec ce joueur → le bloc affiche l'échéance **et rappelle explicitement que le
  pacte ne bloque rien**. Sans cette phrase, un joueur peut croire que le jeu empêchera son
  attaque, et se sentir trahi par l'interface plutôt que par l'adversaire.
- Zone JOUEUR : rappel compact de MES engagements (« ↔ NOM (R5) · ↔ NOM (R6) »), masqué si aucun
  — c'est l'information qu'il faut avoir sous les yeux au moment de choisir une cible.

### 4. RÉPONDRE — le seul toast PERSISTANT du jeu

`hud.show_pact_offer()` : panneau à deux boutons **ACCEPTER / REFUSER**, `mouse_filter = STOP`
(contrairement aux autres toasts, il doit capter ses clics). Il ne s'efface **pas** tout seul : il
porte une **décision**, pas une information.

**Piloté par l'ÉTAT et non par le message** (`main._sync_pact_toast`, appelé à chaque rafraîchissement) :
il **survit donc à une reconnexion** — l'offre vit dans l'état, pas dans un message fugace — et
disparaît dès qu'elle cesse d'exister côté serveur (proposant éliminé, offre soldée, course perdue).
Ancré à 196 px, sous le toast d'action adverse (142 px) : les deux coexistent sans se recouvrir (un
bot joue pendant qu'une offre attend). Répondre est possible **hors tour** — c'est tout l'intérêt.

### 5. LA TRAHISON — le moment que la mécanique existe pour produire

À réception du `system_event` `pact_broken` (porté par l'`attack_result` qui l'a provoquée, donc
**synchrone avec le combat**) :

1. **bandeau pleine largeur** « ⚡ TRAHISON — X A ROMPU SON PACTE AVEC Y » (rouge, brique
   `phase_banner`, celle du PROTOCOLE FINAL) ;
2. **sting `betrayal`** — nouveau SFX : un **triton** (fa♯→do), l'intervalle le plus instable de la
   gamme, grave et sans résolution. Il tranche volontairement avec `pact_sealed` (quinte juste,
   montante) : l'oreille comprend AVANT que l'œil ne lise le bandeau ;
3. **`duck_music()`** — appel DÉFENSIF (`has_method`), le ducking date de §8.122 ;
4. **kill feed + Journal** (catégorie combat, entrée majeure) ;
5. **marque ⚡** sur la chip du traître, pour le reste de la partie (posée par l'état, cf. §2).

L'**expiration**, elle, est volontairement **DISCRÈTE** : une ligne de Journal, aucun bandeau, aucun
son. Un pacte qui s'éteint n'est pas un drame — mais il ne doit pas non plus disparaître en silence
total, sinon les deux signataires continueraient de se croire couverts. Une **offre ignorée** ne
produit **rien du tout** : l'annoncer reviendrait à dire à toute la table « X a été ignoré ».

### 6. RYTHME des bots

Le serveur répond **instantanément** à la place d'un bot (dans le traitement de l'offre). Le client
ne montre jamais cette réponse en même temps que l'envoi : elle passe par la **file de narration des
actions adverses** déjà en place (toast de pouvoir / journal), au même rythme que le reste du tour.

### 7. Rapport Post-Op — section « LES PACTES » (onglet TRAHISONS)

`betrayal_report.gd` gagne `pact_timeline(pacts)` et `pacts_broken_by(pacts, pid)`.

- **Une ligne par pacte**, dans l'ordre de leur FIN : `X ↔ Y — TENU` · `ROMPU PAR X AU ROUND N`
  (rouge — la seule des quatre issues qui soit un manquement) · `EXPIRÉ AU ROUND N` ·
  `OFFRE DÉCLINÉE`. Les offres restées **pendantes** à la fin sont écartées (une question sans
  réponse n'est pas une histoire) ; les **refus** sont gardés — « il a demandé, on lui a dit non »
  fait partie du récit, et c'est la seule trace publique de ce qui s'est joué au chat.
- **PRIORITÉ ABSOLUE du pacte rompu sur LE COUP DE POIGNARD** (`CONFIG.pact_breaks_win`) : une
  attaque flaggée `pact_broken` devient automatiquement le coup de poignard, **au-dessus** de toute
  l'heuristique de calme et de kills — *le calme n'est qu'une présomption de confiance ; un pacte
  rompu en est la preuve, publiquement signée puis publiquement brisée*. Le détail de la section
  affiche alors « PACTE ROMPU » avant la durée de calme.
- La section est **omise** si aucun pacte n'a jamais été proposé ; inversement, une partie **sans un
  seul combat mais AVEC des pactes** ouvre désormais l'onglet (elle a une histoire).
- **Carte de partage** : si le coup de poignard partagé a rompu un pacte, la ligne trahison le dit.

### 8. Profils — « PACTES ROMPUS : N »

Profil **public** (carte du palmarès, teinte muette) et profil **personnel** (onglet STATISTIQUES).
**Masquée à 0** dans les deux cas : ne rien afficher vaut mieux qu'un compteur à zéro dont on ne
saurait pas dire s'il signifie « loyal » ou « serveur pas à jour ».

### 9. Refus traduits — et le seul refus CHIFFRÉ du jeu

`PACT_ERROR_KEYS` (miroir des 8 `reason` serveur) → clés `PACT_ERR_*`. `cooldown` est le seul refus
qui porte un nombre (`NetworkManager.last_error_remaining_rounds`) : sans lui, « trop tôt »
n'apprend rien au joueur.

⚠️ **Les deux familles de codes SE CHEVAUCHENT** (`not_your_turn`, `invalid_target`,
`ranked_disabled` existent pour les capacités de héros §8.119 comme pour les pactes) et le message
`{"type":"error"}` ne dit pas quelle action il refuse. `main.gd` mémorise donc la **dernière famille
émettrice** (`_last_coded_action`) au moment de l'envoi et la **CONSOMME** dans `_on_game_error` — un
marqueur périmé est impossible à conserver.

### 10. i18n

**38 clés** ajoutées en fin de `translations/ui_strings.csv` (FR/EN/IT) : `PACT_*` (bouton, toast,
tooltips, journal, bandeau), `PACT_ERR_*` (**8** raisons — le cahier des charges en annonçait 6 ;
les 8 sont livrées pour qu'aucun code ne puisse s'afficher en brut), `HUD_SHEET_PACT`,
`REPORT_PACT*`, `PROFILE_PACTS_BROKEN`, `SHARE_PACT_BROKEN`. Vérifiées **114/114** résolues par
`TranslationServer.translate` dans les trois locales.

### 11. Fichiers & validation

> **NOUVEAU** : `scripts/game/pact_state.gd`. **MODIFIÉS** : `scripts/game/main.gd`,
> `scripts/game/betrayal_report.gd`, `scripts/game/operation_report.gd`, `scripts/ui/hud.gd`,
> `scripts/ui/player_chip.gd`, `scripts/ui/profile.gd`, `scripts/ui/public_profile.gd`,
> `scripts/managers/network_manager.gd`, `scripts/managers/game_state.gd`,
> `scripts/managers/audio_manager.gd`, `translations/ui_strings.csv`.
>
> **Validation.** `--import` **0 ERROR** ; boots headless **0 ERROR** : `game/main.tscn`,
> `game/operation_report.tscn`, `ui/profile.tscn`, `ui/public_profile.tscn`, `ui/main_menu.tscn`.
> `BetrayalReport.self_check()` forcé hors scène : **OK**. i18n **114/114**.
> **Contre-épreuve de mutation** (3 régressions client injectées à chaud : priorité du pacte rompu
> supprimée, offres pendantes gardées dans la chronologie, sens de la proposition inversé) →
> **3/3 détectées**, avec témoin négatif sur sources saines, restauration vérifiée par hash.
> ⚠️ **Le critère de détection d'un assert Godot est le marqueur `Assertion failed` en sortie, PAS
> le code de retour** : un `assert` faux N'INTERROMPT PAS le script en `--headless --script` (il
> journalise et poursuit) — une contre-épreuve qui se fierait au code de sortie conclurait à tort.
>
> ⚠️⚠️ **MISE EN PAGE NON VÉRIFIÉE À L'ŒIL.** Un boot headless à 0 ERROR ne prouve RIEN sur le rendu :
> ni le glyphe `↔` réellement dessiné, ni la position du toast persistant (196 px) face au toast
> d'action adverse, ni la largeur du bloc PACTE dans la fiche joueur, ni le bandeau de trahison.
> Recette de capture PNG : cf. §8.111.

---

## §8.124 — MODE ÉQUIPES (client) : écran ESCOUADE, identité de camp, arène d'équipe

> Toute l'UI de ce chantier est **conditionnée à `GameState.team_mode != ""`** et se masque
> d'elle-même en FFA. Un serveur non redéployé rend un registre de playlists VIDE → aucune carte de
> mode d'équipe, et le hub est rigoureusement celui d'avant (§9.2). Aucun écran n'a de garde à
> écrire : c'est `GameState.is_friendly` / `teammates_of` / `teams_map` qui portent la neutralité,
> et `is_friendly` vaut **exactement `a == b`** en FFA.

### Hub

- **`main_menu.gd`** : les cartes DUO 2v2 / ESCOUADE 3v3 rejoignent la rangée, **construites depuis
  le registre SERVEUR** (`GET /squad/playlists`) — aucune carte, aucun effectif, aucun id de mode
  n'est codé en dur côté client. Une playlist fermée est **ABSENTE** (pas grisée : une carte grisée
  est une promesse, une carte absente n'est rien). Le clic n'ouvre pas la recherche solo mais
  l'écran ESCOUADE — le format est porté par la playlist, pas par un effectif.
- **`scenes/ui/squad_screen.tscn` + `scripts/ui/squad_screen.gd` (NOUVEAU)** — cousin de
  `salon_screen` : code en héros 72 px + COPIER, écran 100 % code-driven, VUE pure. **DEUX
  différences assumées avec le salon privé** : (1) les **PSEUDOS sont affichés** (une escouade se
  rejoint parce qu'un ami vous a passé le code) ; (2) l'escouade **SURVIT à la partie**. Revenir au
  QG ne la quitte pas — seul le bouton QUITTER la dissout.
  L'écran a DEUX visages (aucune escouade / escouade formée), construits une fois chacun et
  montrés/cachés : rebâtir la hiérarchie à chaque poll ferait clignoter les champs de saisie sous
  les doigts du joueur.
  ⚠️ **Défaut CONSTATÉ EN CAPTURE et corrigé** : avec `toggle_mode` + le style ghost, la playlist
  SÉLECTIONNÉE était rigoureusement identique à l'autre — le joueur ne pouvait pas savoir pour quel
  format il cherchait. Elle porte désormais le style « choisi » des cartes de mode du QG (fond cyan
  + bordure pleine + halo).
- **`match_config.gd`** : `selected_team_playlist` — ne transporte que l'**ID**. Carte et effectif
  viennent du registre serveur et de nulle part ailleurs. SOLO et ÉQUIPE sont exclusifs (choisir
  l'un efface l'autre).
- **`network_manager.gd`** : 6 routes `/squad/*` + `fetch_team_playlists`, **UN seul callback**
  (`_on_squad_response`) — elles partagent la même shape, six handlers auraient été six occasions
  d'oublier de propager `reason`. Signaux `squad_state_received`, `team_playlists_loaded`,
  `team_victory`. Blocs d'équipe du `game_over` mémorisés en PROPRIÉTÉS (`last_team_podium`…),
  patron `last_objectives_reveal` : le signal `match_over` reste INCHANGÉ.

### Arène

- **`game_state.gd`** : `team_mode`, `team_objectives` (déjà REDACTÉ par le serveur — aucun
  filtrage de confidentialité à faire ici, comme pour `pacts`), `winning_team_id`, plus les
  lectures partagées `team_of` / `is_friendly` / `teammates_of` / `teams_map` (le piège JSON float
  §5 ne se paie ainsi qu'une fois).
- **`board.gd` — identité de camp.** `PALETTE_TEAMS` : familles de teintes à ~18° d'écart
  INTRA-équipe, ≥ 90° INTER-équipes. En mode **DALTONIEN** le principe s'INVERSE (`PALETTE_TEAMS_
  COLORBLIND` + `_player_palette_index` rendant l'index d'ÉQUIPE) : le **MOTIF** devient commun au
  camp, la nuance ne distingue plus que les individus — en deutan/protan, deux teintes voisines
  d'une même famille sont précisément ce qui se confond le mieux. L'information la plus importante
  va au canal le plus fiable. Un joueur SANS équipe dans une partie d'équipe (état incohérent) →
  gris neutre : mieux vaut « je ne sais pas » que « il est avec toi ».
- **`hud.gd` — chat ÉQUIPE.** Entrée « ◆ ÉQUIPE » en TÊTE du sélecteur (juste après « Tous ») :
  c'est le canal le plus utilisé en équipe, il ne doit pas se perdre au milieu des privés. Id
  réservé `-2`. `_conv_key_for_target` centralise les trois cas (tous / équipe / privé). Aucun id
  n'est transmis au serveur — il résout les destinataires sur l'état.
- **`objective_tracker.gd`** : trois formules `team_*`, MIROIR EXACT du serveur, lues sur le
  contexte COMBINÉ résolu par `main._team_objective_ctx`. Vérifiées par l'auto-contrôle debug
  (`_self_check`) au même titre que les six autres.
- **`main.gd`** : c'est l'objectif d'ÉQUIPE qui pilote la jauge en mode équipe — afficher
  l'individuel enverrait les joueurs courir après une victoire impossible (il ne fait plus gagner).
  Titre de fin de partie : « VICTOIRE DE L'ÉQUIPE n » — sans quoi le coéquipier du `winner_id`
  lirait « DÉFAITE » alors qu'il vient de gagner.
- **`faction_selection.gd`** : bandeau « ÉQUIPE n » + picks des coéquipiers EN DIRECT ; une faction
  prise par un coéquipier est grisée « PRIS PAR *pseudo* » (cas placé AVANT tous les autres verrous
  d'accès : c'est le plus spécifique ET le plus actionnable, il nomme la personne). Les adversaires
  restent un compteur anonyme.
- **`spectator_overlay.gd`** : bandeau « VOTRE ÉQUIPE SE BAT ENCORE — X EST EN VIE » tant qu'un
  coéquipier vit — « K.I.A. » ne dit pas la vérité quand la partie continue sans vous, et c'est ce
  qui transforme une élimination en attente intéressée plutôt qu'en sortie. Le pari « vainqueur »
  retire MON CAMP du sélecteur (le serveur le refuse déjà, autant ne pas le proposer : ce pari
  serait gratuit et systématique, alors que l'intérêt du dispositif est de faire LIRE la table).
- **`operation_report.gd`** : le **CLASSEMENT PAR ÉQUIPE** ouvre l'onglet CLASSEMENT, avant les
  lignes individuelles — dans ce mode, un joueur veut d'abord savoir si SON CAMP a gagné. Objectif
  d'équipe révélé sous chaque ligne (✓/✕). No-op intégral en FFA.

### i18n

41 clés FR/EN/IT ajoutées : `MODE_DUO_2V2` / `MODE_SQUAD_3V3` / `MODE_TRIO_2V2V2` (dérivées de l'id
de playlist — une playlist ajoutée côté serveur n'a besoin QUE de sa clé), `MENU_MODE_TEAM_SUB`,
`SQUAD_*` (16), `TEAM_*` (7), `CHAT_TEAM`, `ERR_FRIENDLY_FIRE`, `BET_ERR_OWN_TEAM`,
`OBJ_TEAM_*_FMT` (3), `OBJ_DESC_TEAM_*` (3). ⚠️ Aucune clé `FACTION_<ID>` n'existe : les noms de
factions vivent dans les `.tres` (`_faction_display_name` les y lit).

> **Validation.** `--import` **0 ERROR** · boot headless `main_menu` / `squad_screen` /
> `search_screen` / `salon_screen` **0 ERROR** · **capture PNG relue** de l'écran ESCOUADE dans ses
> trois états (vide / formée / en file) — c'est elle qui a révélé le défaut de sélection de
> playlist. ⚠️ Les autres écrans touchés (draft, HUD, Post-Op, overlay spectateur) n'ont PAS été
> capturés en situation d'équipe : leur mise en page en mode équipe reste **non vérifiée
> visuellement**.

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
> ⚠️ **NON VÉRIFIÉ** : aucune partie Battle Royale réelle jouée de bout en bout. Les boutons
> RÉANIMER / SE RENDRE / COUP D'ÉTAT ne sont pas encore posés dans le HUD — les actions existent et
> sont testées côté serveur, mais **rien ne les déclenche depuis l'interface**. C'est le premier
> reste à faire.

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

### 11. Tiroir « Fiche Joueur » — n'obéit QU'À SON BOUTON (§8.125, corrigé DEUX fois)

Le panneau de gauche se dépliait tout seul. Deux tentatives ont été nécessaires, et la 1ʳᵉ
correction était incomplète :

1. **Cause initiale** — `hud.set_player_sheet()` se terminait par un `open_player_sheet()`
   inconditionnel. Or cette fonction est appelée à CHAQUE rafraîchissement d'état, donc à chaque
   action de n'importe quel joueur : le panneau se rouvrait en boucle sous les doigts de celui qui
   venait de le replier.
2. **Correction n° 1, insuffisante** — l'ouverture a été conditionnée à un paramètre `focus`, posé à
   `true` sur les « gestes volontaires » (clic territoire, clic roster). **Mauvaise lecture du
   besoin** : cliquer un territoire, c'est vouloir voir LE TERRITOIRE, pas déplier un panneau qu'on
   a rangé exprès. Un joueur qui replie son tiroir le fait pour dégager la carte — le lui rouvrir au
   premier clic annule sa décision.
3. **Règle FINALE** : le tiroir n'obéit qu'à **son propre bouton ◀/▶**. `set_player_sheet()` ne fait
   plus que PRÉPARER le contenu ; il sera là, à jour, le jour où le joueur décidera d'ouvrir.
   Le paramètre `focus` et la fonction `open_player_sheet()` sont **supprimés** (plus aucun
   appelant), et `main._open_player_sheet_for_territory` est **renommée
   `_update_sheet_for_territory`** — garder le mot « open » dans le nom aurait conduit le prochain
   lecteur à y rebrancher une ouverture, c'est-à-dire à recréer le défaut une troisième fois.

Seuls DEUX sites touchent encore la visibilité du tiroir : `_toggle_player_sheet` (le bouton) et
`_collapse_player_sheet_initially` (repli au démarrage).

> **Validation — CONTRE-ÉPREUVE COMPORTEMENTALE, pas seulement `--import`.** Les deux corrections
> précédentes compilaient parfaitement et étaient pourtant fausses : la compilation ne dit rien du
> comportement. Un script mesure donc la position X du panneau après chaque déclencheur :
>
> | déclencheur | position | attendu |
> |---|---|---|
> | état initial | −352 | replié |
> | rafraîchissement d'état | −352 | **inchangé** ✅ |
> | **clic sur un territoire** | −352 | **inchangé** ✅ |
> | clic sur une ligne du roster | −352 | **inchangé** ✅ |
> | bouton ◀/▶ | +10 | **déployé** ✅ |
>
> `--import` **0 ERROR**, boot headless de 2 scènes **0 ERROR**.

### 12. Annulation d'une recherche SOLO + respiration de l'écran (§8.125 — 5ᵉ passe)

**a) ⭐ Un joueur en file SEUL ne pouvait pas annuler.** Le bouton ANNULER vivait dans `_squad_box`,
**masqué tant qu'on n'a pas d'escouade** : le visage « aucune escouade » n'avait tout simplement pas
d'état « en recherche ». Un joueur parti en file seul se retrouvait donc **sans aucune sortie**,
coincé jusqu'à ce qu'une partie se forme.

Ajout d'un **visage RECHERCHE SOLO** (`_solo_queue_box`) : titre, chrono en 52 px, rappel « vous
serez associé à des coéquipiers », et **ANNULER LA RECHERCHE**. Il est EXCLUSIF des actions
d'accueil (`_no_squad_actions` masqué) — on ne crée pas d'escouade pendant qu'on cherche. Les deux
bascules sont IMMÉDIATES (`_render()` au clic, sans attendre le poll de 2 s) : un bouton qui laisse
l'écran inchangé pendant deux secondes donne l'impression de n'avoir rien fait, et le joueur le
reclique. L'annulation emprunte la route existante `POST /squad/dequeue`, qui distingue déjà
elle-même le ticket solo du groupe.

⚠️ **Chrono resynchronisé** : la branche « sans escouade » de `_on_squad_state` ne lisait jamais
`queued_since_s`. Le solo ne comptait donc QUE ses tics locaux — revenir sur l'écran repartait de
`00:00` alors que le ticket attendait depuis plusieurs minutes. La branche « escouade » faisait déjà
cette resynchronisation ; celle-ci l'avait oubliée.

⚠️ Le bandeau de statut redisait mot pour mot ce que le visage RECHERCHE affiche déjà (doublon
constaté en capture) : il est tu tant que ce visage est à l'écran.

**b) Respiration de l'écran** : panneau **820×560 → 1080×730** (+32 %), marge intérieure 36 → 48,
et surtout **interligne 16 → 22 → 32**. Agrandir le cadre sans écarter les lignes ne fait que
déplacer la densité, il ne la réduit pas. Seuls les axes VERTICAUX sont écartés — les rangées
horizontales (boutons côte à côte) gardent leur écart serré, qui EST ce qui les fait lire comme un
groupe. Le panneau modal d'explication suit (560 → 730, marge 24 → 32, interligne 10 → 16).

⚠️ **Centrage vertical du contenu** (`_root.alignment = CENTER`) : sans lui, le contenu restait collé
en haut du panneau agrandi et les 200 px gagnés devenaient un TROU sous les boutons au lieu d'une
respiration. C'est le centrage qui transforme la hauteur en air — et il tient quel que soit le visage
affiché (accueil, escouade, recherche), qui n'ont pas du tout la même hauteur de contenu.

> **Validation — CONTRE-ÉPREUVE COMPORTEMENTALE.** Un script pilote les quatre états et vérifie la
> présence du bouton d'annulation :
>
> | étape | `_solo_queue_box` | bouton ANNULER | chrono |
> |---|---|---|---|
> | accueil | masqué | absent ✅ | — |
> | après « TROUVER UNE PARTIE » | visible | **présent** ✅ | 00:00 |
> | après poll serveur (37 s) | visible | présent | **00:38** ✅ (resynchronisé) |
> | après annulation | masqué | absent ✅ | — |
>
> `--import` **0 ERROR**, boot headless de 3 scènes **0 ERROR**, captures relues (accueil, escouade,
> recherche, modal) — l'écran respire et le contenu est centré dans le cadre agrandi.

---

## §8.126 — COMPAGNIES : écran de clan, [TAG] partout, onglet du Classement (volet FRONTEND)

> **Périmètre.** Volet client de `PROMPT_COMPAGNIES.md` (contrat réseau : **§8.126 de
> `CONTRAT_RESEAU.md`**). Un écran neuf, une carte dans le Profil, un onglet dans le Classement, un
> préfixe d'identité diffusé partout, et une section d'affichage sur l'écran Escouade.
>
> ⚠️ **FRONTIÈRE ESCOUADE / COMPAGNIE.** L'ESCOUADE (`squad_screen`, §8.124-125) est l'objet de MISE
> EN FILE : éphémère, elle meurt avec la partie. La COMPAGNIE est une IDENTITÉ persistante et **ne se
> met JAMAIS en file**. Aucun bouton de l'écran Compagnie ne parle de matchmaking.
>
> ⚠️ **DÉPLOIEMENT : VPS + CLIENT ENSEMBLE.** Sans serveur redéployé, `/company/*` répond 404 : la
> carte du Profil affiche « SANS COMPAGNIE », l'onglet COMPAGNIES reste vide, et aucun tag
> n'apparaît. Dégradation propre, mais chantier invisible.

### 1. `company_screen.tscn` / `company_screen.gd` — UN écran, DEUX modes

Écran **100 % CODE-DRIVEN** (patron `squad_screen` / `salon_screen`) : la scène est un `Control`
racine nu, toute la hiérarchie est bâtie dans `_build_shell()` + `_render()`.

- `CompanyScreen.target_tag == ""` → **MA compagnie** (`GET /company/mine`) : code d'adhésion,
  actions de chef, QUITTER.
- `CompanyScreen.target_tag != ""` → **fiche PUBLIQUE** d'une autre (`GET /company/{tag}`) : ni code,
  ni actions, ni RP exacts.

`static var target_tag` posé par l'écran appelant juste avant `TransitionManager.change_scene`
(MÊME mécanique que `public_profile.target_username`, §8.107 — `change_scene` ne transporte aucun
paramètre) puis **remis à `""` dès sa lecture** dans `_ready`, sinon revenir sur SA compagnie
rouvrirait la fiche publique consultée juste avant.

**Deux scènes auraient dupliqué** l'en-tête, le panneau d'honneur et le roster — donc trois
occasions de les laisser diverger. Le mode public RETIRE des éléments, il n'en réinvente aucun.

Trois visages selon l'état (`_view`) :
1. **SANS COMPAGNIE** — « SANS COMPAGNIE » + badge d'explication + CRÉER / REJOINDRE, plus le
   cooldown de réadhésion s'il court (**dit AVANT** le clic sur un bouton qui refuserait).
2. **CRÉATION** — champ TAG (4 lettres, vérification LIVE de disponibilité, **débounce 0,5 s**),
   champ NOM, grille de 24 emblèmes, FONDER / ANNULER.
3. **FICHE** — emblème + `[TAG]` + nom + rang inter-compagnies ; code d'adhésion + COPIER
   (+ RÉGÉNÉRER pour le chef) ; panneau d'honneur (score de saison TOP 10 · victoires de saison ·
   division moyenne) ; roster défilant ; QUITTER.

**Roster** : pseudo · libellé `CHEF` · division (+ RP en vue membre) · ancienneté · actions du chef
(TRANSFÉRER / EXCLURE) **avec confirmation modale à chaque fois**. « CHEF » est un **LIBELLÉ, pas un
pictogramme** — préférence produit actée §8.125 (aucun emoji décoratif dans l'UI de ce chantier).

**Contre-épreuves comportementales (§8.125) intégrées au code :**
- un **refus serveur NE VIDE PAS** le formulaire (`_draft_tag` / `_draft_name` / `_draft_emblem`
  survivent au rendu) — un formulaire qui se vide fait recommencer, donc fait abandonner ;
- le bouton REJOINDRE reste **toujours cliquable** après un échec (aucune désactivation locale : le
  serveur répond en 200, c'est lui qui décide) ;
- la ligne de statut **se tait sur succès** — elle est réservée aux refus et à l'attente réseau.

⚠️⚠️ **PIÈGE D'ORDRE DE CONSTRUCTION (défaut vu en CAPTURE, invisible au boot headless).** Sur un
écran code-driven, le fond plein écran est un enfant ajouté par le script : une `TopNav` ajoutée
AVANT lui disparaît **DERRIÈRE** (les Control se dessinent dans l'ordre de l'arbre). La nav était
totalement absente alors que le boot annonçait 0 ERROR. **`_build_shell()` d'abord, `TopNav`
ensuite.** Les écrans à `.tscn` (profile, leaderboard) n'ont pas ce souci : leur fond vit dans la
scène.

### 2. `company_emblems.gd` — catalogue avec remplacement AUTOMATIQUE

Registre statique des 24 emblèmes. `make_badge(id, size, font)` rend :
- `res://resources/companies/emblem_NN.png` **s'il existe** (test par `ResourceLoader.exists`, et
  **surtout pas** `FileAccess.file_exists` : en build exporté le PNG devient une ressource importée
  et le fichier source n'existe plus) ;
- sinon un **PLACEHOLDER procédural** : monogramme sur fond gunmetal, liseré teinté.

**Déposer les fichiers SUFFIT** — aucune ligne de code à toucher (mécanique éprouvée de l'audio
§8.122). ⚠️ Monogrammes **ASCII A..X uniquement** : la police condensée rend en TOFU tout glyphe hors
BMP (constat §8.117 sur 📢 ✉ 🎯, puis §8.123 où 🤝 est devenu `↔`).

### 3. Le `[TAG]` PARTOUT — une source, huit sites

`GameState.company_tag_of(pid)` et `GameState.tagged_name(pid, base)` sont le **SEUL endroit du
client** qui décide de la forme du préfixe. Le serveur diffuse `company_tag` dans chaque
`PlayerState` ; le champ est ADDITIF, donc `tagged_name` rend le pseudo **INCHANGÉ** quand il est
absent — aucun écran n'a de garde à écrire.

Sites couverts : `player_chip` (chips, roster, inspecteur, feed) · `main._display_name` (journal,
toasts, Split-Screen VS, kill feed, Post-Op) · `hud._player_label` + bandeau de tour ·
`faction_selection` (draft, bandeau d'équipe) · `operation_report` (podium, débriefing, lignes) ·
`spectator_overlay`.

- Dans `player_chip`, le tag est un **Label DÉDIÉ** (et non un préfixe de chaîne) pour deux raisons :
  la charte le veut en **teinte atténuée et jamais colorée faction** (une String n'a qu'une couleur),
  et la troncature compacte ne doit ronger que le pseudo — un tag coupé (« [ALF… ») n'identifie plus
  rien.
- ⛔ **PAS de tag sur l'initiale du badge daltonien** (`board._owner_initial`) : ce champ est une
  LETTRE, pas un nom.

### 4. Carte COMPAGNIE du Profil (onglet APERÇU)

Deux états — et le premier compte autant que le second : « SANS COMPAGNIE » n'est pas un trou, c'est
l'invitation (le seul endroit du jeu qui la propose). Avec compagnie : emblème + `[TAG]` + nom +
bouton OUVRIR. Les trois boutons mènent au MÊME écran.

Placée **AVANT la bande de forme**, qui sort de la fonction par un `return` quand l'historique est
vide : la reléguer après la masquerait pour un joueur neuf — précisément celui qu'une compagnie
retient le mieux.

⚠️ La carte ne montre **NI score NI roster** : les y amener obligerait `/profile/stats` à recalculer
un agrégat de compagnie à chaque ouverture, et surtout créerait une DEUXIÈME source du score (la
divergence que le §8.106 a coûté cher à corriger).

Le **panneau explicatif** « qu'est-ce qu'une compagnie » est un **modal calqué sur le Classement**
(`WarzoneUI.make_info_badge` → voile plein écran + panneau gunmetal, fermeture au clic n'importe
où) — référence maison actée §8.125.

### 5. Classement — onglet COMPAGNIES

Bascule **JOUEURS / COMPAGNIES** en tête du panneau, avec la MÊME fabrique de pastilles que les
onglets d'échelon (`_make_pill_tab`) : un troisième langage visuel pour un troisième sélecteur aurait
fait de cet écran un patchwork.

En mode COMPAGNIES, l'appareillage du ladder de joueurs est **MASQUÉ** (carte VOTRE RANG, bande des
divisions, onglets d'échelon, podium) : aucun de ces objets ne décrit un clan, les laisser suggérerait
qu'ils s'y rapportent. À leur place : carte **VOTRE COMPAGNIE** (patron « VOTRE RANG », présente même
si la compagnie est 300ᵉ) puis les lignes `rang · emblème · [TAG] nom · effectif · score`.

- Ligne **CLIQUABLE** → fiche publique de la compagnie, routée par **TAG** (doctrine §8.107 : aucun
  identifiant séquentiel énumérable).
- Le classement est demandé **une fois à l'ouverture de l'écran** (cache serveur 60 s → coût nul), pas
  au premier clic sur l'onglet : il est peuplé à l'instant où on le touche.
- Pas de bouton « AFFICHER PLUS » : le serveur sert le top 50 d'un bloc. Le laisser visible
  promettrait une suite qui n'existe pas.

⚠️ **Deux défauts vus en CAPTURE, pas au boot** : l'eyebrow réutilisait `LEADERBOARD_GLOBAL_RANK`
(« RANG MONDIAL » sur un rang de clan — deux classements différents), et la ligne de statut
retombait sur `_season_status_line()`, dont le repli « AUCUN JOUEUR CLASSÉ » se lit comme un bug
sous une liste de compagnies bien peuplée. D'où `COMPANY_RANK_EYEBROW`, `COMPANY_COL_SCORE` et
`_company_status_line()`.

### 6. Profil public — ligne compagnie

Ligne cliquable (emblème + `[TAG]` + nom) sous le niveau, ouvrant la fiche publique. **Absente** si le
serveur ne renvoie pas le bloc — jamais un « COMPAGNIE : AUCUNE » qui affirmerait à tort.

### 7. Pont ESCOUADE — section COMPAGNIE

Sur `squad_screen`, sous la liste des membres : `COMPAGNIE — [TAG] NOM`, un rappel « partagez le code
ci-dessus », et le roster. **Bloc d'AFFICHAGE, aucun couplage au matchmaking.** Demandé une seule
fois à l'ouverture (une compagnie ne change pas toutes les 2 s, contrairement à une file).

⛔ **RESTE À FAIRE ASSUMÉ — bouton « INVITER LA COMPAGNIE »** (push du code aux membres EN LIGNE) et
**statut « en ligne »**. Vérification faite : le serveur n'a **NI canal WebSocket de hub** (le seul WS
du jeu est `/ws/{room_id}/{player_id}`, il n'existe qu'en partie) **NI notion de présence hors
partie**. Les inventer aurait été une infrastructure entière greffée sur un bouton. Afficher une
pastille verte devinée côté client aurait été pire : c'est le genre de mensonge qui fait attendre un
joueur devant un ami absent.

### 8. i18n (57 clés, FR/EN/IT — AUCUN emoji)

`COMMON_CONFIRM` · `COMMON_CANCEL` · `COMMON_HOURS_SHORT` · `COMMON_MINUTES_SHORT` ·
`LEADERBOARD_TAB_PLAYERS` · `COMPANY_*` (titre, états, formulaires, roster, actions, les 4
confirmations, panneau d'honneur, classement, pont escouade, et les 9 `COMPANY_ERR_*`).
Le serveur n'envoie **jamais de texte affichable** : il rend une `reason`, le client choisit les mots
(règle R4) — c'est `_reason_text()` qui fait la table.

> **Validation.** `--import` **0 ERROR** ; boot headless **0 ERROR** sur `main_menu`, `profile`,
> `leaderboard`, `company_screen`, `squad_screen`, `public_profile`. **Captures PNG relues** (fiche,
> sans-compagnie, création, onglet COMPAGNIES, carte du Profil) — elles ont révélé les **3 défauts**
> corrigés ci-dessus (§1 nav absente, §5 eyebrow et statut), qu'aucun boot n'aurait signalés.
>
> ⛔ **NON VÉRIFIÉ EN JEU** : le `[TAG]` en partie (chips, kill feed, Post-Op) n'est pas observable
> sans un serveur redéployé ET deux comptes membres d'une même compagnie. Le code est en place et
> `tagged_name` est couvert côté données, mais le rendu réel reste à constater.

---

## §8.126.1 — COMPAGNIES : l'onglet de nav, la pastille et le panneau latéral (volet FRONTEND)

> **Le défaut corrigé.** Le §8.126 livrait l'écran Compagnie sans **aucune porte d'entrée** : on n'y
> arrivait que par une carte de l'onglet APERÇU du Profil. Une section entière du jeu, invisible.
> Ce complément lui donne son onglet, sa pastille, et la colonne qui répond à la vraie question
> quotidienne : *qui est là, et qu'est-ce que j'ai manqué ?*

### 1. Onglet COMPAGNIE dans `top_nav` (§8.94)

Ajouté à `TABS` **après CLASSEMENT**, dans la continuité : les deux répondent à « où est-ce que je
me situe ? », l'un seul, l'autre avec les siens.

⚠️ `_on_tab_pressed` **purge `CompanyScreen.target_tag`** avant de naviguer. Sans cela, un joueur qui
vient de consulter la fiche publique d'un autre clan (Classement, profil public) rouvrirait
CELLE-LÀ en cliquant sur son propre onglet. L'écran remet déjà le porteur statique à `""` à la
lecture — cette ligne est la ceinture qui rend le raisonnement inutile.

⚠️ `company_screen` passe son `active_tab` de `"profile"` à `"company"`. Tant que l'onglet n'existait
pas, l'écran empruntait celui du Profil ; le laisser aurait surligné « PROFIL » alors qu'on est sur
COMPAGNIE (**défaut vu en capture**, invisible au boot).

### 2. Pastille — deux signaux, un emplacement

| priorité | condition | rendu |
|---|---|---|
| 1 | `unread > 0` | `COMPAGNIE ●N` en **or** |
| 2 | `online > 0` | `COMPAGNIE ◦N` en **cyan** |
| 3 | sinon | clé BRUTE, l'onglet redevient un onglet |

Les non-lus priment parce qu'**une notification se traite, une présence s'observe**. Glyphes
`●` / `◦` **ASCII-safe** : tout pictogramme hors BMP rend en TOFU avec la police condensée de la
charte (constat §8.117 sur 📢 ✉ 🎯, puis §8.123 où 🤝 est devenu `↔`).

Alimentée par `GET /company/badge`, demandée par la nav elle-même — donc **une fois par écran hub**,
comme les missions (§8.94 : la nav est le seul déclencheur, les écrans écoutent).

⚠️ À l'ouverture de l'écran Compagnie, le client **ré-émet `company_badge_loaded` LOCALEMENT**
(`unread: 0`, `online: online_count − 1`) plutôt que de redemander la route. Deux requêtes
concurrentes (`POST /seen` puis `GET /badge`) n'ont **aucun ordre garanti** : la pastille aurait pu
répondre avant l'enregistrement de l'accusé et rester allumée. On connaît déjà les deux nombres.

### 3. Panneau latéral droit de `company_screen`

Le corps de l'écran passe en **deux colonnes** (`HBoxContainer`) : gestion à gauche (expand), résumé
vivant à droite (`SIDE_PANEL_W = 340`). Les deux répondent à des questions différentes — « comment
j'administre » vs « qui est là » — et les mélanger aurait noyé la seconde, qui est pourtant celle
qu'on vient consulter tous les jours. Panneau **masqué** sans compagnie, en vue publique et pendant
les formulaires (il n'y aurait rien à résumer).

Trois cartes, dans l'ordre de lecture :
1. **RÉSUMÉ** — emblème, `[TAG]` nom, rang inter-compagnies, score, effectif `n/20`, division moyenne.
2. **EN LIGNE `n/N`** — les présents seulement, pastille pleine or = `EN PARTIE`, creuse cyan =
   `AU QG`. Vide → « Personne en ligne pour le moment. » Bordure **or dès qu'il y a quelqu'un**.
3. **ACTIVITÉ ●N** — les 6 dernières activités ; les `unread` premières en **texte clair**, le reste
   en muet : le joueur voit d'un coup d'œil ce qu'il a manqué.

Le **roster principal** porte lui aussi la pastille de présence, avec une **gouttière réservée même
hors ligne** — sans elle, les pseudos danseraient horizontalement à chaque rafraîchissement au gré
des connexions. Tri : chef, puis **les présents**, puis les RP.

⚠️ Les phrases d'activité sont **composées CÔTÉ CLIENT** depuis `kind` + les deux pseudos
(`COMPANY_EV_*`). Le serveur n'envoie jamais de texte affichable (règle R4) : c'est ce qui permet à
la même ligne de journal de se lire en trois langues sans qu'aucune ne transite par le réseau.

### 4. i18n (+14 clés)

`MENU_TAB_COMPANY` · `COMPANY_SIDE_SUMMARY` · `COMPANY_ONLINE_TITLE` / `_NONE` ·
`COMPANY_STATUS_ONLINE` / `_IN_GAME` · `COMPANY_ACTIVITY_TITLE` / `_NONE` · `COMPANY_EV_*` (6).

> **Validation.** `--import` **0 ERROR** ; boot headless **0 ERROR** sur 8 écrans hub. **Captures PNG
> relues** : panneau latéral peuplé (résumé + 4 présents dont 2 en partie + activité à ●2), onglet
> « COMPAGNIE ●2 » en or dans la nav du menu principal, onglet correctement surligné sur l'écran
> Compagnie (le défaut du §1 a été vu et corrigé là).
>
> ⛔ **NON VÉRIFIÉ EN CONDITIONS RÉELLES** : la présence repose sur deux comptes joués en parallèle
> contre un serveur redéployé. Les trois états sont couverts côté données
> (`test_company_flow.py`, 178 ✅) et rendus en capture avec des données injectées, mais la bascule
> « au QG → en partie » d'un vrai joueur reste à constater.

---

## §8.126.2 — « OPÉRATEUR » → « JOUEUR » : suppression d'une notion parasite

> **Décision produit de Hakim (2026-08-01).** Le mot « opérateur » désignait le joueur dans toute
> l'UI — héritage de la direction artistique militaire. Jugé **non pertinent** : le jeu s'adresse à
> des joueurs, pas à des opérateurs. La notion est retirée du client, du backend et de la
> documentation vivante.

**Ce qui a changé — 208 occurrences, 27 fichiers.**

| Domaine | Avant | Après |
|---|---|---|
| Libellés FR | OPÉRATEUR · PROFIL D'OPÉRATEUR · %d OPÉRATEURS | JOUEUR · PROFIL DE JOUEUR · %d JOUEURS |
| Libellés EN | OPERATOR · OPERATOR PROFILE | PLAYER · PLAYER PROFILE |
| Libellés IT | OPERATORE · PROFILO OPERATORE | GIOCATORE · PROFILO GIOCATORE |
| Clés i18n | `COMMON_OPERATOR` · `MENU_TOP_OPERATORS` · `HUD_OPERATOR_TITLE` · `HUD_OPERATOR_POWER_FMT` · `PACT_OPERATOR_ENTRY_FMT` · `LEADERBOARD_TAB_OPERATORS` | `COMMON_PLAYER_LABEL` · `MENU_TOP_PLAYERS` · `HUD_PLAYER_TITLE` · `HUD_PLAYER_POWER_FMT` · `PACT_PLAYER_ENTRY_FMT` · `LEADERBOARD_TAB_PLAYERS` |
| Identifiants | `_build_operator_zone` · `set_operator_panel` · `_push_operator_panel` · `_hide_operator_widgets` · `_operator_name` · `_op_power_title` | même chose en `player` |
| Nœuds de scène | `OperatorZone` · `OperatorTitle` · `OperatorSep` (main.tscn) · `OperatorBox` (profile.tscn) | `PlayerZone` · `PlayerTitle` · `PlayerSep` · `PlayerBox` |
| Commentaires | ~150 occurrences FR/EN, client **et** backend | idem |

⚠️ **`COMMON_OPERATOR` n'a PAS été fusionné avec `COMMON_PLAYER`**, malgré l'apparence. Ce sont deux
choses différentes : `COMMON_PLAYER_LABEL` = « JOUEUR » en capitales, un **libellé de champ** ;
`COMMON_PLAYER` = « Joueur », un **nom de repli** quand le pseudo est inconnu. Les fusionner aurait
mis des capitales au milieu d'une phrase, ou l'inverse. D'où le suffixe `_LABEL`.

⚠️⚠️ **DEUX PIÈGES rencontrés, à connaître avant tout renommage de masse dans ce dépôt :**

1. **`grep -i` NE PLIE PAS LA CASSE DES ACCENTS** quand `LANG` n'est pas définie (c'est le cas de ce
   poste). `grep -riE "op[ée]rateur"` a renvoyé **0 occurrence** alors qu'il en restait **73** en
   « OPÉRATEUR ». Toujours énumérer les casses accentuées EXPLICITEMENT
   (`OPÉRATEUR|Opérateur|opérateur`), ou vérifier avec un script Python (qui, lui, décode l'UTF-8).
2. **Les ÉLISIONS françaises cassent un remplacement naïf.** `de l'opérateur` → `de le joueur`,
   `à l'opérateur` → `à le joueur` : 29 contractions fautives ont dû être reprises
   (`du joueur`, `au joueur`, `des joueurs`, `aux joueurs`). Traiter les élisions **AVANT** les
   formes simples, puis repasser sur les contractions.

⛔ **NON TOUCHÉ, délibérément** : les briefs de Hakim (`PROMPT_*.md`, `RAPPORT_*.md`). Ce sont ses
documents de commande, pas de la documentation vivante — les réécrire falsifierait ce qui a été
demandé. Ils conservent donc le mot, et ce n'est pas un oubli.

> **Validation.** `--import` **0 ERROR** ; boot headless **0 ERROR** sur 11 écrans hub **+ l'arène
> `main.tscn`** — c'est ce dernier qui compte : il porte les nœuds renommés, et un NodePath qui ne
> résout plus s'y serait vu immédiatement (`%PlayerZone`, exports de `profile.tscn`). Backend :
> `py_compile` OK, suite COMPLÈTE verte hors `test_missions.py` / `test_simulation.py`
> (**PRÉ-EXISTANTS**). Aucune ligne de code fonctionnel n'a été touchée côté serveur — seulement des
> commentaires (vérifié au `git diff`).

## §8.127 — PARAMÈTRES : deux onglets (GÉNÉRAL / CONFORT)

> **Demande de Hakim (2026-08-01).** L'écran Paramètres **ne tenait plus dans l'écran**. Il empilait
> tout dans un `RootVBox` unique, et deux ajouts successifs faits *par code* l'avaient allongé sans
> que personne ne le voie venir : la section CONFORT (§8.82) et le 4ᵉ volume AMBIANCE (§8.122).
> Mesuré avant refonte : **~1174 px de panneau + 100 px d'offset sous la nav**, soit plus haut qu'un
> écran 1080p.

**Le contenu passe sur deux pages exclusives**, sous une barre d'onglets construite en code
(même style que la barre du Shop §8.102, volontairement distinct de `_style_segment` pour ne pas
confondre les deux niveaux de sélection présents à l'écran) :

| Onglet | Contenu |
|---|---|
| **GÉNÉRAL** (`PageMain`) | AUDIO (4 volumes) · AFFICHAGE (mode fenêtre + résolution) · LANGUE · **DÉCONNEXION** |
| **CONFORT** (`PageComfort`) | taille d'interface · mouvement réduit · daltonien · nombres de dégâts · mode streamer · carte vivante |

Nouvelle arborescence de `settings.tscn` : `RootVBox` → `HeaderBar`, `FiletTop`, **`TabsBar`**,
**`Pages`** (→ `PageMain` + `PageComfort`), `FiletBottom`, `StatusLabel`. Les **13 NodePath
`@export`** ont été repointés en conséquence, et 3 exports ajoutés (`tabs_bar`, `page_main`,
`comfort_page`). Nouvelles clés i18n : `SETTINGS_TAB_GENERAL`, `SETTINGS_TAB_COMFORT`.

**Le filet du bas et la ligne de STATUT restent HORS des pages** : ils décrivent l'écran entier
(« réglages appliqués et enregistrés localement »), pas un onglet.

`_build_comfort_section()` visait son parent en **remontant l'arbre**
(`resolution_box.get_parent().get_parent()`), ce qui la collait forcément en queue du `RootVBox` —
c'est-à-dire dans le même empilement que tout le reste. Elle vise désormais un `@export` explicite
(`comfort_page`). `_build_ambience_slider()`, lui, n'a **pas bougé** : il remonte depuis
`sfx_slider` → `SfxRow` → `AudioRows`, et cette sous-arborescence est restée intacte.

⚠️ **Le panneau est centré verticalement** (`CenterContainer`). Sans plancher commun, passer sur la
page la plus courte le faisait **remonter de la moitié de l'écart** : mesuré **503 px (GÉNÉRAL) vs
387 px (CONFORT)**, soit un saut de ~58 px à chaque clic d'onglet. `_measure_pages_floor()` impose à
la zone de pages la hauteur de la plus haute page déjà affichée (plancher **monotone croissant**, ce
qui absorbe aussi les reconstructions de la page CONFORT au changement de langue ou sur MOUVEMENT
RÉDUIT).

⚠️⚠️ **`get_combined_minimum_size()` est INUTILISABLE pour mesurer une page qui contient un Label en
autowrap.** La taille minimale d'un Label enroulé se calcule sur sa **largeur courante** : hors
layout, elle explose. Mesuré sur `PageComfort` (2 mentions muettes en `AUTOWRAP_WORD_SMART`) :
**2543 px annoncés au lieu de 387**, ce qui a produit un panneau de 2543 px de haut au premier essai.
Il faut lire `size` **après une frame**, une fois les enfants triés — d'où le `await
get_tree().process_frame` de `_measure_pages_floor()`.

> **Validation.** `--import` **0 ERROR**. Contre-épreuve par **harnais jetable** qui instancie
> l'écran réel et inspecte l'arbre obtenu (supprimé après usage) : **16/16 nœuds `@export` résolus**,
> 2 onglets traduits **fr/en/it**, `PageMain` = 10 enfants attendus, `PageComfort` = 10 rangées
> construites par code, **`AudioRows` = 4** (le slider AMBIANCE retombe au bon endroit), volumes lus
> depuis `SettingsManager` (0,70 / 0,46 / 0,35), 4 segments de résolution, sélecteur de langue monté,
> bascule d'onglet OK dans les deux sens. Après correctif : **panneau h=771 px et bord haut y=204 sur
> les DEUX onglets — saut de 0 px**. 771 + 100 = **871 px**, l'écran tient désormais même en
> 1600×900.
>
> ⛔ **Non vérifié : le RENDU.** Aucune capture n'a été prise — la validation est structurelle et
> métrique (arbre, tailles, positions), pas visuelle.

---

## §8.128 — BARRE BASSE DE L'ARÈNE : le compartiment « INFOS » (lecture à gauche, action à droite)

> Demande produit (Hakim, 2026-08-01). Le compartiment de GAUCHE était un simple bloc OBJECTIFS
> pendant que celui de DROITE empilait **l'agir** (ACTIONS, CARTES) **et le lire** (JOURNAL, puis
> ORDRE et ÉQUIPE ajoutés en §8.125) : cinq onglets de deux natures différentes dans la même boîte.
> Les onglets de LECTURE migrent donc à gauche, qui devient **INFOS** ; la droite ne garde que ce
> sur quoi on clique pour jouer.

### Avant → après

| | avant | après |
|---|---|---|
| Compartiment GAUCHE | `ObjectivesZone` (VBox) : titre + `%ObjectiveLabel` + tracker | **`InfoZone`** : titre « INFOS » + **`%InfoTabs`** (TabContainer) — **OBJECTIFS · JOURNAL · ORDRE · ÉQUIPE** |
| Compartiment DROIT | `%CommandsTabs` : ACTIONS · CARTES · JOURNAL (+ ORDRE/ÉQUIPE par code) | **`%CommandsTabs` : ACTIONS · CARTES**, rien d'autre |
| Ratios (`size_flags_stretch_ratio`) | 0,28 / 0,27 / 0,45 | **0,40 / 0,24 / 0,36** |

### Méthode : RE-PARENTER, jamais reconstruire

**Aucune logique n'a été réécrite.** Les nœuds de contenu existants ont changé de parent :
`%ObjectiveLabel` et `%LogText` (avec sa rangée de filtres, son numérotage, ses `[url=<tid>]`)
vivent désormais dans deux pages de `%InfoTabs` ; `_build_extra_tabs()` / `_ensure_team_tab()`
ajoutent ORDRE et ÉQUIPE au même TabContainer au lieu de `%CommandsTabs`. Les `%NomUnique` sont
conservés — c'est ce qui rend le déplacement invisible pour le reste de `hud.gd`.

**Points de rupture traités un par un :**
- `_apply_charter_ornaments()` cherchait le titre du bloc par `%ObjectiveLabel.get_parent().get_child(0)`.
  Le label vit maintenant DANS une page d'onglet : le filet cyan part de `%InfoTabs.get_parent()`.
- `custom_minimum_size = (300, 0)` sur `%InfoTabs` : la rangée de filtres du Journal (5 chips de
  52 px) doit tenir dans le compartiment gauche sans rogner.
- **Animations hors-vue** : le pulse OR du tracker d'objectif (≥ 80 %) est **SUSPENDU** dès que la
  page n'est plus `is_visible_in_tree()`, et la teinte remise à blanc — à la réouverture de
  l'onglet, la première frame est déjà correcte (plus d'animation orpheline).
- **Journal hors-vue** : il continue d'accumuler, mais `scroll_following` ne suit pas de façon
  fiable un `RichTextLabel` de taille nulle. `_on_info_tab_changed` **recale le défilement en fin
  de flux** (`call_deferred`, après la frame de layout) — sans quoi on retrouvait le journal figé
  sur une vieille ligne.
- **Badge « • »** du Journal : porté par l'onglet de `%InfoTabs`, effacé à son ouverture (parité).
- **SFX** : les DEUX barres d'onglets jouent le même `click` au changement (parité de ressenti ;
  auparavant aucune des deux n'en jouait, les onglets n'étant pas des `Button`).
- **Mode streamer** : la plaque « INTEL CLASSIFIÉ » est insérée avant `%ObjectiveLabel` — elle a
  donc suivi dans l'onglet OBJECTIFS **sans une ligne de code**, et ne masque QUE cet onglet.

### ⚠️ Conditions d'existence : INCHANGÉES (et le prompt se trompait)

Le brief supposait qu'ORDRE et ÉQUIPE n'existaient qu'en mode équipe. **C'est faux pour ORDRE** :
depuis §8.125 il est construit dans `_ready()` et présent dans **TOUS** les modes, parce que savoir
qui joue après soi conditionne chaque attaque, y compris en FFA. Seul ÉQUIPE dépend de
`GameState.team_mode != ""` (créé paresseusement au 1ᵉʳ état d'équipe reçu).

L'instruction opérante étant « conditions d'existence conservées **À L'IDENTIQUE** », le
comportement réel a été préservé : **FFA → OBJECTIFS · JOURNAL · ORDRE** ; **Battle Royale → +
ÉQUIPE**. Retirer ORDRE en FFA aurait supprimé une information à tous les joueurs solo, ce qu'un
lot d'ergonomie n'a pas à faire.

### Nouvelle API du HUD

- `open_journal_tab(filter_key)` — inchangée d'appelant (le chip de zone), cible désormais `%InfoTabs`.
- **`open_objectives_tab()`** — NOUVEAU. Le coach du tutoriel (§8.129) l'appelle **avant** de
  surligner le tracker : désigner un contrôle rangé derrière un onglet fermé ne montrerait rien.
- **`get_deploy_confirm_button()`** — NOUVEAU. Accesseur du bouton « CONFIRMER LE DÉPLOIEMENT »
  (construit par code, donc sans `%NomUnique`), utilisé comme ancre de surlignage.

### i18n

Une seule clé neuve : **`TAB_INFOS`** (« INFOS » / « INFO » / « INFO »). Les libellés
OBJECTIFS / JOURNAL / ORDRE / ÉQUIPE **réutilisent** `HUD_OBJECTIVES_TITLE`, `HUD_TAB_JOURNAL`,
`HUD_TAB_ORDER`, `HUD_TAB_TEAM` — aucun doublon de clé.

> **Fichiers.** MODIFIÉS : `scenes/game/main.tscn` (re-parentage), `scripts/ui/hud.gd`,
> `translations/ui_strings.csv`.
>
> **Validation.** `--import` **0 ERROR** ; boot headless de `main.tscn` **0 ERROR** ;
> **captures PNG relues** en FFA (3 onglets, badge « • », journal filtrable) **et** en Battle Royale
> (4 onglets, roster ÉQUIPE), plus `ui_scale` **0,9 et 1,3** — aucun débordement des deux
> compartiments, tracker d'objectif entier et lisible aux deux échelles.
>
> ⚠️ **NON VÉRIFIÉ** : aucune partie réelle jouée de bout en bout après le déplacement. Le
> recentrage caméra au clic d'une entrée du Journal et la mise à jour du roster ÉQUIPE après une
> réanimation sont **structurellement intacts** (aucun code touché) mais n'ont pas été rejoués.

### Correctif 🐛 — « le panneau du bas a disparu complètement » (2026-08-01, signalé en jouant)

Défaut **PRÉ-EXISTANT** (il date de la refonte UI arène §8.117), mis au jour par une partie réelle
et corrigé ici : la barre basse pouvait sortir de l'écran **avec son propre bouton de repli**, ce qui
la rendait **irrécupérable jusqu'à la fin de la partie**.

`_toggle_bottom_panel()` MÉMORISAIT la position déployée au moment du repli
(`_bottom_shown_y = wrapper.position.y`) sans regarder si le Tween PRÉCÉDENT tournait encore. En
re-cliquant pendant le glissement, on capturait donc une position **intermédiaire** comme si c'était
la position déployée, puis on lui ré-ajoutait la hauteur du panneau : chaque aller-retour rapide
descendait la barre un peu plus bas. Mesures instrumentées (1920×1080, partie à 5 joueurs) :

| geste | `wrapper.position.y` | bouton ▲ |
|---|---|---|
| 1 clic (sain) | 1037 | 1037 → 1063 : **visible** |
| 3 clics rapides — **avant** | **1109** | 1109 → 1135 : **hors écran, définitif** |
| 3 clics rapides — **après** | 1037 | **visible** |
| 12 clics martelés — **après** | 1037 | **visible**, aucune dérive |

**Correctif de fond** : les deux positions ne sont plus mémorisées, elles sont **CALCULÉES** par une
fonction PURE `_bottom_panel_y()`. La barre est ancrée en bas (`anchor_top = anchor_bottom = 1`,
`grow_vertical = BEGIN`) : sa position déployée vaut donc toujours `hauteur du HUD − hauteur de la
barre`. Le résultat ne dépend plus ni du nombre de clics, ni de l'instant du clic, ni d'un
redimensionnement survenu entre-temps. La variable `_bottom_shown_y` est **supprimée**.
S'y ajoute un **garde-fou** (`minf(..., hud_h − hauteur du bouton)`) : la conséquence d'un
dépassement étant irrécupérable, elle mérite une borne dure et pas seulement un calcul juste.

⚠️ **Les panneaux latéraux (COMMS, FICHE JOUEUR) n'ont JAMAIS eu ce défaut** — vérifié : ils
mettent leur géométrie en cache **une seule fois** (`_side_metrics_ready` / `_sheet_metrics_ready`),
donc un clic en plein glissement ne peut rien y corrompre. Seule la barre basse relisait sa position
à chaque repli.

**2ᵉ passe — la barre est aussi partie VERS LE HAUT.** Second signalement en jouant : « le panneau
part très vite en haut, introuvable en bas ». Le correctif ci-dessus avait changé la DIRECTION de la
panne sans en supprimer la cause profonde, mise au jour par un watchdog frame-par-frame :

> ⚠️⚠️ **LA BARRE BASSE N'A AUCUN PLAFOND DE HAUTEUR.** Sa taille est entièrement pilotée par son
> contenu. Mesures (streamer OFF, partie à 6, italien, `ui_scale` 130 % ⇒ écran LOGIQUE de 831 px) :
>
> | contenu | hauteur de la barre |
> |---|---|
> | au repos | 315 px |
> | + tracker d'objectif à 2 volets + renseignement d'espionnage | 372 px |
> | **+ carte POUVOIR chargée (Battle Royale : 6 boutons + ordre secret)** | **602 px — 72 % de l'écran** |
>
> Le moteur de la croissance est **`HUD_TAB_ACTIONS` (min 489 px)**, dans le compartiment DROIT —
> donc INDÉPENDANT du LOT 0, qui est neutre en hauteur (mesuré). Dès que la barre dépasse la
> hauteur du HUD, `hud_h − wrapper_h` devient NÉGATIF et le glissement emporte tout par le haut.

**Correctif** : `_bottom_panel_y()` borne désormais **des DEUX côtés** —
`shown_y = maxf(0, hud_h − wrapper_h)` (jamais au-dessus du bord haut) et
`minf(shown_y + glass_h, hud_h − toggle_h)` (jamais sous le bord bas). Contre-épreuve sur quatre
cas dont une barre de **900 px sur un écran de 831** et une explosion simulée à **3000 px** :
position toujours dans l'écran, bouton toujours saisissable.

**PLAFOND DE HAUTEUR** (arbitrage Hakim, 2026-08-01 : *hauteur fixe + défilement*). Le garde-fou
empêchait de PERDRE la barre, pas de la voir GROSSIR jusqu'à 72 % de l'écran. La barre redevient
donc la **bande de 272 px** prévue par la scène, et c'est le contenu qui déborde qui DÉFILE :

| zone | traitement | pourquoi |
|---|---|---|
| onglet OBJECTIFS | contenu entier dans un `ScrollContainer` | plaque INTEL + objectif + tracker à 2 volets (autowrap) s'empilent sans borne |
| onglet ACTIONS | **`%PowerBox` SEUL** enveloppé | ⚠️ `ActionRow` porte `size_flags_vertical = SHRINK_END` : c'est lui qui ÉPINGLE « FIN DE PHASE », « RÉ-ASSAUT » et « CONFIRMER LE DÉPLOIEMENT » en bas. Faire défiler la page entière aurait fait sortir le bouton de fin de tour du champ |
| onglets ORDRE / ÉQUIPE | `ScrollContainer` autour du VBox de lignes | une rotation à 6 joueurs empile 6 lignes |

Un `ScrollContainer` annonce une taille minimale quasi nulle : le minimum cesse donc de remonter
jusqu'à la barre, dont la hauteur retombe sur le plancher de la scène.

⚠️⚠️ **PIÈGE PAYÉ EN ROUTE — `remove_child` + `add_child` fait PERDRE son `owner` au nœud, et un
nœud sans owner ne répond PLUS à son `%NomUnique`.** `%ObjectiveLabel` devenait `null` et tout le
HUD s'effondrait (`Cannot call method 'get_parent' on a null value`). Les deux helpers utilisent
donc **`Node.reparent()`**, qui préserve l'owner. Piège déjà consigné au dépôt (PLAN_EXPERIENCE),
re-payé ici : à relire avant tout re-parentage.

⚠️⚠️ **2ᵉ PIÈGE PAYÉ — un `TabContainer` masque ses pages NON COURANTES.** Envelopper une PAGE
dans un ScrollContainer lui fait emporter son `visible = false` À L'INTÉRIEUR du scroll, où plus
personne ne le remet à `true` : le TabContainer affiche désormais le SCROLL, pas le contenu.
Constaté en jouant — **les onglets ORDRE et ÉQUIPE s'ouvraient VIDES** alors que leurs lignes
existaient bel et bien (`HUD_TAB_ORDER min = 167×164`, six lignes construites, `visible = false`).
`_scroll_wrap()` force donc `node.visible = true` après le re-parentage : l'affichage de l'onglet
est porté par le ScrollContainer, le contenu est toujours visible.

**Contre-épreuve du plafond** (partie à 6 en Battle Royale, italien, `ui_scale` 130 % ⇒ écran
logique 831 px, carte POUVOIR à 6 boutons + ordre secret, les 4 onglets INFOS parcourus) :
**315 px dans TOUS les cas**, contre 602 avant. 0 SCRIPT ERROR. Capture relue : barre de défilement
présente dans AZIONI, **« FIN DE PHASE » toujours épinglée en bas**, carte intacte.

**Contre-épreuve des ONGLETS** (même pire cas) : les quatre onglets INFOS ouverts un par un,
contenu mesuré `visible_in_tree = true` et hauteur > 0 — OBJECTIFS 169 px · JOURNAL 32 · **ORDRE
164** · **ÉQUIPE 107**. Captures relues : ORDRE affiche bien ses six lignes à la couleur de plateau
avec la marque « EN COURS », ÉQUIPE ses trois membres avec leurs barres de PV.

⚠️ **Ce que le correctif ne couvre pas** (constaté, jugé cosmétique) : redimensionner la fenêtre
alors que la barre est repliée la fait ré-apparaître (le système d'ancrage reprend la main) tandis
que le bouton affiche encore ▲ — il faut alors un clic de plus. Aucune perte de panneau.

### Ajouts du 2026-08-01 (demande Hakim) — santé dans ORDRE, et onglet PRIMES

**a) `ORDRE` affiche désormais les PV du héros de CHAQUE belligérant** (valeur + mini-barre de 52×5,
dégradé de santé `RosterHelpers.pv_color` — MÊME source que le Roster et la fiche joueur, pour qu'un
héros n'ait jamais deux couleurs selon l'endroit où on le lit ; un mort affiche `—`). L'information
était DÉJÀ publique (Roster de Guerre E1 §8.73, départage du PROTOCOLE FINAL) : on ne dévoile rien de
neuf, on l'amène là où l'œil est déjà. Rendu compact à dessein — six lignes doivent continuer à
tenir dans la bande, et l'ORDRE DU TOUR reste l'information n° 1.

**b) 5ᵉ onglet `PRIMES`** (mode ÉQUIPE uniquement, création paresseuse comme `ÉQUIPE`).

> ⚠️ **RAPPEL DE RÈGLE — une caisse n'est PAS à réclamer, et ne l'a jamais été.**
> `engine._open_pending_crates()` s'exécute juste après l'attaque qui franchit le palier et applique
> le contenu **immédiatement**, réparti entre les membres VIVANTS :
> **caisse PV** → héros soigné sur place (plafonné au max) · **caisse UNITÉS** → versées dans
> `units_in_stock`, à placer à la prochaine phase 2. **Rien ne se perd** : le moteur fait
> `units_in_stock += renforts` (ligne 1908, `+=` et NON une affectation) — la caisse s'ADDITIONNE
> aux renforts du tour suivant.
>
> Le défaut signalé (« on voit le message, on ne sait pas où passent les primes ») n'était donc pas
> une perte mais un **trou de traçabilité** : trois secondes d'animation, puis plus aucune trace, et
> des unités indiscernables des renforts.

L'onglet PRIMES comble exactement ce trou, **sans toucher à la mécanique** :
- **compteur de KILLS D'ÉQUIPE** (somme sur TOUS les membres, **morts compris** — même agrégat que
  le serveur ; les exclure ferait CHUTER le compteur au moment où l'équipe perd quelqu'un) ;
- **jauge vers la prochaine caisse** (`kills % palier`), remplacée par une mention explicite au
  plafond plutôt qu'une jauge qui n'aboutira jamais ;
- **caisses ouvertes N/max** ;
- **historique de ce que le joueur a RÉELLEMENT reçu**, chaque ligne disant **OÙ** la prime est
  passée (« déjà soignés sur votre héros » / « déjà versées dans votre réserve : placez-les à votre
  prochaine phase DÉPLOIEMENT »).

⚠️ Le DÉTAIL d'une caisse (`shares`) ne vit QUE dans l'évènement d'attaque qui la porte — l'état de
partie ne transporte que le compteur. `main.gd` l'ARCHIVE donc (`hud.push_crate_record`) avant de
lancer l'animation, sinon la part du joueur serait perdue au bout de trois secondes. Pastille « • »
sur l'onglet quand une caisse tombe pendant qu'on regarde ailleurs (même contrat que le JOURNAL).

**Contre-épreuves** : Battle Royale → 5 onglets, PRIMES `h = 215 px`, compteur/jauge/historique
justes, barre toujours à **315 px** · **FFA → 3 onglets seulement** (`_bounty_box` et `_team_box`
restent `null`), santé présente dans ORDRE, barre à 315 px · 0 SCRIPT ERROR · captures relues.
### Correctif 🐛 — PARIS D'OBSERVATEUR : le verdict pouvait DISPARAÎTRE, et ne disait pas où va la prime

Signalé en jouant : « on ne voit pas du tout où ça va, et dans le rapport ce n'est cité nulle part ».
Vérification faite dans le code : **le serveur crédite bel et bien**
(`router._settle_observer_bets` → `apply_xp_and_levels` sur la progression du compte +
`record_coins(REASON_OBSERVER_BET)` au livre de comptes, la prime pouvant même faire franchir un
palier de niveau). **DEUX défauts CLIENT** empêchaient de le voir — les deux mesurés :

1. **Le bloc vivait DANS le conteneur du DÉPARTAGE.** `populate_bet_results()` faisait
   `_scores_wrap.add_child(box)`, or `_scores_wrap` est masqué tant que `final_scores` est vide :
   le verdict des paris disparaissait avec un tableau qui n'a rien à voir avec lui.
   Mesuré : `final_scores` vide → `_scores_wrap.visible = false`, bloc construit mais invisible.
   → Conteneur **`_bets_wrap` DÉDIÉ**, frère de `_scores_wrap`, visibilité pilotée par lui seul.
   Après correctif : `final_scores` vide → `_bets_wrap.visible = true`, 6 enfants.
2. **Le bloc se DUPLIQUAIT.** Le rapport est repeuplé plusieurs fois (§8.100 : « BILAN rafraîchi
   INCONDITIONNELLEMENT ») et la fonction se contentait d'AJOUTER. Mesuré : 3 enfants → 4 au 2ᵉ
   appel. → Purge avant reconstruction ; après correctif, le compte reste stable.

**Et surtout, la ligne qui manquait — OÙ va la prime.** Le bloc annonçait « +25 XP +15 ¢ » sans
jamais dire où cela atterrissait, exactement le même trou de traçabilité que les caisses de Battle
Royale. Nouvelle mention `BETS_DEST`, posée **aux DEUX endroits** où le joueur regarde : le panneau
de paris de l'overlay spectateur **et** le BILAN du Rapport Post-Op —
« Réglés à la FIN de la partie : l'XP part dans votre progression de compte, les Coins dans votre
solde — relevé détaillé dans PROFIL, onglet FINANCES (source « PARIS D'OBSERVATEUR ») ».
Le « réglés à la FIN » est important : un pari gagné en cours de partie ne crédite rien tout de
suite, et ce silence-là passait pour une perte. Un palier de niveau franchi grâce aux paris est
annoncé en plus (`BETS_LEVELS_FMT`, depuis `totals.levels_gained` que le serveur renvoyait déjà
sans que personne ne l'affiche).

**Contre-épreuves** : `final_scores` vide → bloc paris toujours visible · double appel → aucun
doublon · captures relues (BILAN du rapport ET panneau de l'overlay spectateur) · boot de
`main`, `operation_report`, `spectator_overlay`, `main_menu` **0 ERROR**.
---

## §8.129 — TUTORIEL & PREMIÈRE OPÉRATION (FTUE) : volet CLIENT

> Volet RÉSEAU (drapeau, 2 routes, raison de ledger) : **§8.129 de
> [`CONTRAT_RESEAU.md`](CONTRAT_RESEAU.md)**. Source de vérité du CONTENU :
> `ARCHITECTURE_ET_REGLES.md` §4 et §8.125 — **chaque phrase du coach et du Manuel s'y vérifie**.
> Un tutoriel qui ment coûte plus cher que pas de tutoriel : si une règle change, c'est ici qu'il
> faut repasser.

### Le problème

Le jeu alignait une douzaine de systèmes simultanés (draft asymétrique, déploiement aveugle,
phases, dés + duel de héros, PP dépensables, zone croissante ET téléportée, objectifs secrets à cinq
types, timer + PROTOCOLE FINAL, pactes, Battle Royale, Coup d'État, paris d'observateur) et
**aucune explication nulle part**. Un compte neuf tombait de l'authentification Steam au QG, puis
dans un carrousel de dix factions, sans un mot.

### Trois étages DÉCOUPLÉS

| Étage | Portée | Persistance | Fichier |
|---|---|---|---|
| **PREMIÈRE OPÉRATION** — 13 étapes de coach sur une VRAIE partie | une fois par COMPTE | `users.tutorial_done` (**serveur**) | `scripts/managers/tutorial_manager.gd` |
| **AIDES CONTEXTUELLES** — 14 bulles « première rencontre » | une fois par MACHINE | `user://tutorial_hints.json` (**local**) | idem |
| **MANUEL DE GUERRE** — 8 sections consultables à froid | toujours | — | `scripts/ui/war_manual.gd` |

Chacun fonctionne si les deux autres n'existaient pas.

### ⛔ AUCUNE modification du moteur

La Première Opération est une **partie NORMALE** : salon privé auto-créé + LANCER AVEC BOTS (§8.116,
API inchangée), **3 joueurs sur `skirmish_atlantic`** (≈ 20 territoires → une partie complète en
moins de dix minutes ; sur `classic_42` le briefing aurait duré une demi-heure avant le premier
enseignement), règles standard, XP et missions crédités comme d'habitude. Le `TutorialManager`
**observe** (il écoute les mêmes signaux que le HUD) et **affiche** ; il ne truque rien, ne bloque
rien, ne désactive rien. **« PASSER LE BRIEFING » est accessible à CHAQUE étape** et la partie
continue normalement.

### `TutorialManager` — autoload `CanvasLayer` (layer 120)

Patron `TransitionManager` : l'autoload **héberge** la vue du coach, parce qu'elle doit SURVIVRE aux
changements de scène (draft → arène → Rapport Post-Op). Layer 120, donc **sous** le fondu de
`TransitionManager` (128) : une bascule de scène le couvre comme le reste.

Points d'entrée : `should_offer_first_operation()` · `start_first_operation()` ·
`decline_first_operation()` · `bind_draft/bind_arena/bind_report` · `notify_faction_locked()` ·
`notify_game_over()` · `register_anchor(id, control)` · `hint_once(id, target)` · `reset_hints()` ·
`open_manual(section_id)`.

### La machine à étapes — pilotée par les ÉVÈNEMENTS RÉELS

**Aucune minuterie nulle part.** Chaque étape attend le fait de jeu qui la rend pertinente :

| # | Étape | Déclencheur RÉEL | Sortie |
|---|---|---|---|
| 1 | BIENVENUE | `bind_draft` | COMPRIS |
| 2 | LE DRAFT | après 1 (ancre : bouton CONFIRMER) | `notify_faction_locked()` |
| 3 | DÉPLOIEMENT AVEUGLE | `stage == "placement"` | évènement `units_deployed` (moi) |
| 4 | RENFORTS | code système **`reinforcements_granted`** (moi) | COMPRIS |
| 5 | DÉPLOYER | phase 2, mon tour | `units_deployed` (moi) |
| 6 | ATTAQUER | phase 3, mon tour | `attack_result` où je suis attaquant |
| 7 | LIRE UN COMBAT | premier `attack_result` (moi attaquant) | COMPRIS |
| 8 | CONQUÉRIR | `attack_result` avec `conquered` | `conquer_move_resolved` (moi) |
| 9 | TON HÉROS | `attack_result` où je suis attaquant **OU** défenseur | COMPRIS |
| 10 | L'OBJECTIF | après 8 | COMPRIS (**force l'onglet OBJECTIFS** puis surligne INFOS) |
| 11 | LA ZONE | code système `zone_forecast` **ou** `zone_grew` | COMPRIS |
| 12 | MOUVEMENT & CARTE | phase 4 ou 5, mon tour | `turn_passed` / `turn_timeout` (moi) |
| 13 | DÉBRIEF | Rapport Post-Op (`bind_report`) | COMPRIS → `POST /profile/tutorial/complete` → « BRIEFING TERMINÉ — 150 COINS » |

⚠️ **Correction de brief** : `reinforcements_granted`, `zone_forecast` et `zone_grew` ne sont **pas**
des `event_type` mais des **codes de `system_events`** imbriqués (cf. `engine._push_system_event`).
La machine inspecte donc les deux niveaux.

**Trois propriétés portées par le code, pas par la chance :**
- **FILE D'ATTENTE** — un seul panneau à l'écran (règle §8.125). Les évènements qui se bousculent
  s'empilent ; `_pump()` en sort un à la fois.
- **SAUT SILENCIEUX** — un joueur plus rapide que le coach (il a déjà attaqué quand l'étape
  s'arme) voit l'étape **soldée sans jamais s'afficher** (`_close_step`).
- **RECONNEXION** — `_sync_from_state()` **DÉDUIT** de l'état courant (stage, tour, phase) les
  étapes forcément dépassées. Rien n'est stocké côté serveur, et `guided` est persisté localement :
  le briefing survit même à une fermeture du client en cours de partie.

### `coach_panel.gd` — Vue PURE (§6.1)

Un seul composant pour les étapes ET les bulles — deux scènes auraient été deux occasions de violer
la règle « jamais deux panneaux ». Panneau bas, largeur 460, gunmetal **quasi-opaque (0,97)** +
liseré cyan porteur à gauche, encoches biseautées, ombre portée. Rythme eyebrow → texte :
**COMMANDEMENT** pour une étape, **AIDE** pour une bulle. Boutons : `COMPRIS` (cyan) ·
`EN SAVOIR PLUS` (or, bulles seulement) · `PASSER LE BRIEFING` (muet, 2ᵉ rangée, étapes seulement).
**Aucun emoji** (§8.125).

**Surlignage** : liseré cyan PULSANT tracé AUTOUR du contrôle cible (jamais par-dessus), avec quatre
équerres de coin, rect relu à chaque frame (un contrôle de la barre basse bouge quand elle se
rétracte). `reduced_motion` → liseré **FIXE** : l'information reste, le mouvement disparaît.

**Marges de sécurité** : `set_safe_margins()`. Menus 32/32 ; **arène 400/316** — la barre basse
(26 + 272) et le panneau COMMS (382) occupent précisément ce coin, et sans ces marges le coach
s'assiérait sur les contrôles qu'il explique.

### Ancres de surlignage

`register_anchor(id, control)` déclaré par les écrans. Un id inconnu ou un contrôle mort ne
surligne **rien** — jamais d'erreur, jamais de rectangle orphelin.
Ancres posées : `draft_recommended` (draft) · `hud_root`, `next_phase`, `player_zone`,
`objective_tracker`, `deploy_confirm` (arène) · `roster_order_band`, `roster_rows` (Roster de Guerre).

⚠️ Les **deux ancres `# TUTO:`** laissées par PLAN_EXPERIENCE dans `war_roster.gd` (l'ordre du tour,
l'état des belligérants) ont été **converties en vraies bulles** — le commentaire a été REMPLACÉ par
l'appel, jamais laissé en double.

### 14 aides contextuelles (registre `TutorialManager.HINTS`)

`first_pact_received` · `first_pact_button` · `first_pp_spend` · `first_power_ready` · `first_card` ·
`first_final_protocol` · `first_spectator` · `first_br_queue` · `first_coup_order` ·
`first_company_tab` · `first_ranked_queue` · `first_shop_visit` · `first_roster_order` ·
`first_roster_enemy`.

Chacune : 2 lignes + « EN SAVOIR PLUS » vers **la** bonne section du Manuel. `hint_once()` est un
**NO-OP** si la bulle a déjà été vue, si les aides sont coupées, **ou si une partie guidée est en
cours** (le coach a la parole — deux voix simultanées seraient illisibles). Marquée vue **à
l'armement** : la promesse est « une fois proposée », pas « une fois lue ».

Deux bulles sont volontairement pauvres : `first_coup_order` **ne nomme jamais la victime** (une
bulle se lit par-dessus l'épaule) et ne dit rien du nombre de traîtres à la table.

### MANUEL DE GUERRE — modal calqué Classement

8 sections, navigation LATÉRALE (huit sections lues d'affilée seraient un mur, alors qu'on vient
toujours pour une) : LES PHASES D'UN TOUR · LE COMBAT · TON HÉROS · LES FACTIONS · LA ZONE
RADIOACTIVE · LES OBJECTIFS SECRETS · PACTES & TRAHISONS · BATTLE ROYALE. Corps en puces « ❯ »
posées à la lecture (le traducteur n'écrit qu'un texte, une ligne par idée ; séparateur `\n`
littéral dans le CSV).

⚠️ **BATTLE ROYALE est volontairement incomplète** : elle ne donne PAS les seuils du Coup d'État
(« la puissance décide » suffit). Le mystère est un ingrédient du mode, pas un oubli.

**Trois chemins d'accès** : PARAMÈTRES → CONFORT → « MANUEL DE GUERRE » · « EN SAVOIR PLUS » d'une
bulle (ouvre à la bonne section) · **ÉCHAP dans l'arène quand rien n'est sélectionné**.
⚠️ Adaptation assumée : l'arène **n'a pas** de menu ÉCHAP (le brief en supposait un) — ESC n'y
faisait strictement rien hors ciblage/sélection. On occupe ce geste mort plutôt que d'ajouter un
bouton dans un HUD déjà dense ; ESC referme aussi le Manuel.

### CTA du QG

Si `tutorial_done_known && !tutorial_done` : panneau OR **« BRIEFING RECOMMANDÉ / PREMIÈRE
OPÉRATION »** inséré au-dessus du CTA START, qui perd sa surbrillance (`modulate.a = 0.55`) sans
jamais cesser d'être cliquable — la hiérarchie visuelle a un seul sommet, pas un verrou.
Deux issues : **LANCER LE BRIEFING**, ou **JE CONNAIS LA GUERRE** → **confirmation modale** qui dit
noir sur blanc ce qu'on perd (la prime de 150 ¢) avant de poser le drapeau.

### Réglages (PARAMÈTRES → CONFORT)

`context_hints` (bascule, défaut **ON**) + mention muette · **REVOIR LES AIDES** (remet la mémoire
locale à zéro) · **MANUEL DE GUERRE** (bouton or). Couper les aides et réarmer leur mémoire sont
**deux gestes distincts** à dessein : se taire n'est pas la même chose que tout recommencer.

### i18n

**66 clés neuves** FR/EN/IT, **aucun emoji** : 5 de châssis, 13 étapes, 14 bulles, 9 de CTA +
confirmation + toast de prime, 19 pour le Manuel (3 + 8 titres + 8 corps), 6 de réglages.

> **Fichiers.** NOUVEAUX : `scripts/managers/tutorial_manager.gd`, `scripts/ui/coach_panel.gd`,
> `scripts/ui/war_manual.gd`. MODIFIÉS : `project.godot` (autoload `TutorialManager`, après
> `MatchConfig`), `scripts/managers/auth_manager.gd` (drapeau + signal), `network_manager.gd`
> (2 routes + `tutorial_settled`), `settings_manager.gd` (`context_hints`), `main_menu.gd` (CTA),
> `faction_selection.gd`, `game/main.gd` (ancres, débrief, ESC, 3 bulles), `hud.gd`
> (2 accesseurs + 2 bulles), `war_roster.gd`, `settings.gd`, `shop.gd`, `company_screen.gd`,
> `search_screen.gd`, `squad_screen.gd`, `translations/ui_strings.csv`.
>
> **Validation.** `--import` **0 ERROR** ; boot headless de `main_menu` / `main` /
> `faction_selection` / `settings` **0 ERROR** ; **captures PNG relues** : CTA du QG, coach au
> DRAFT (avec surlignage du bouton CONFIRMER), coach en ARÈNE (surlignage de FIN DE PHASE, marges
> respectées), bulle contextuelle (eyebrow AIDE + EN SAVOIR PLUS), MANUEL sections PACTES et
> BATTLE ROYALE.
>
> ⚠️ **NON VÉRIFIÉ** : aucune Première Opération jouée de bout en bout contre le serveur. Le
> chaînage `private_create` → `connect_to_server` → `private_start_bots` → `game_started`, les 13
> déclencheurs sur évènements réels, la reprise après reconnexion et le crédit des 150 ¢ sont
> testés **côté serveur** (`test_tutorial.py`) et **structurellement** côté client, mais la boucle
> complète demande une recette manuelle sur un compte neuf.
>
> ⚠️ **VPS + client ENSEMBLE** (le client se tait si `/auth/me` n'émet pas `tutorial_done`).

---

## §8.130 — HYGIÈNE DU DÉBOGUEUR : zéro rouge, zéro jaune au boot et sur les écrans hub

**Pourquoi.** Le débogueur portait 22 entrées permanentes (relevé 2026-08-02) : 2 vraies erreurs
runtime, 1 avertissement runtime, 19 avertissements statiques de l'analyseur. Ce bruit de fond
rend les VRAIES régressions invisibles — objectif du lot : un débogueur qui ne dit plus rien tant
que rien ne va mal. **100 % client, zéro backend, zéro contrat réseau.**

### Les deux erreurs runtime (les seules lignes ROUGES)

1. **`ERR_BUSY` sur `/auth/me`** — `auth_manager.get_profile()` partage UN `HTTPRequest` entre
   quatre appelants (`top_nav`, `profile`, `leaderboard`, restauration de session §P1). Le
   `_ready()` d'un ENFANT s'exécutant avant celui de son parent, la nav (montée par l'écran hôte)
   tire toujours la première → le `get_profile()` de l'écran Profil heurtait un nœud occupé.
   **Correctif : drapeau `_profile_in_flight`** (même idiome que `_steam_poll_in_flight`) —
   l'appel de trop est **SAUTÉ**, jamais heurté ; remis à faux dans `_on_request_completed`,
   SEUL handler du nœud, donc sur tout dénouement. ⚠️ Un garde sur le CODE DE RETOUR ne suffit
   PAS : le moteur logge la ligne rouge (`http_request.cpp`, « Condition "requesting" is true »)
   AVANT de rendre `ERR_BUSY` — vérifié en jeu, le premier correctif tenté (test du retour)
   laissait la ligne rouge. Personne ne perd de données : chaque écran s'abonne à
   `profile_loaded` AVANT d'appeler, la réponse UNIQUE sert tous les auditeurs (pseudo affiché,
   vérifié en jeu). Couvre AUSSI le défaut latent du Classement (même montage nav + écran).

2. **« NETWORK: connexion WebSocket perdue (code -1) » au BOOT** — le `_process` de
   `network_manager` tourne dès la frame 1 (un Node avec `_process` l'active d'office) sur un
   `WebSocketPeer` JAMAIS connecté ; or un peer neuf naît en `STATE_CLOSED` (cf. §8.116) → la
   branche « coupure non applicative » (§8.118) annonçait une perte fictive et CONSOMMAIT
   `_connection_lost_emitted` avant toute partie. **Correctif : `set_process(false)` au
   `_ready`**, symétrique du `set_process(true)` de `connect_to_server`.

### L'avertissement runtime

`top_nav._build_quit_dialog()` forçait `position`/`size` APRÈS `PRESET_FULL_RECT` → le layout les
écrase (« Nodes with non-equal opposite anchors will have their size overridden… »). Deux lignes
de code MORT : avec `top_level = true`, les ancres d'un Control se réfèrent au viewport —
vérifié en jeu après suppression, le dialogue couvre 1920×1080 par les ancres seules.

### Les 19 avertissements statiques

- **Shadowing ×9** — paramètres/locales `name`/`size`/`show`/`panel`/`wrap` masquant des membres
  de `Node`/`Control`/`CanvasItem` (ou une variable de classe) → renommés `company_name`,
  `new_name`, `font_size`, `show_side`, `power_panel`, `block`. Chaque fonction relue EN ENTIER
  avant renommage : ⚠️ un usage raté retomberait SILENCIEUSEMENT sur le membre de la classe de
  base et compilerait quand même.
- **`INTEGER_DIVISION` ×3** — divisions entières VOULUES (échantillons audio, jours pleins,
  coins par niveau) → `@warning_ignore("integer_division")` commenté, idiome déjà en place
  (`shop.gd`, `search_screen.gd`…).
- **`INCOMPATIBLE_TERNARY` ×3** — `PackedStringArray()` au lieu de `[]` (settings_manager) ;
  `String(...)` sur les retours `TranslationServer.translate()`, qui rend un StringName
  (hero_stats_view) ; `float(clampi(...))` vers `Range.value` (characters_screen).
- **`INT_AS_ENUM` ×1** — `_label(..., align: HorizontalAlignment)` (company_screen) ; tous les
  appels passent déjà des constantes `HORIZONTAL_ALIGNMENT_*`, aucun warning déplacé.
- **`UNUSED_SIGNAL`** — `lobby_action_success` SUPPRIMÉ de `network_manager.gd` : dernier
  vestige du système lobby/waiting_room retiré en §8.116 (zéro référence, `.tscn` compris).
- **`UNUSED_PRIVATE_CLASS_VARIABLE`** — `_camera` de `hero_viewport_3d.gd` supprimé (câblage
  `@onready` jamais lu ; le nœud caméra reste dans la scène).

> **Fichiers (10, AUCUN nouveau).** `scripts/managers/auth_manager.gd`, `network_manager.gd`,
> `settings_manager.gd`, `audio_manager.gd`, `scripts/components/hero_viewport_3d.gd`,
> `scripts/ui/top_nav.gd`, `company_screen.gd`, `profile.gd`, `hero_stats_view.gd`,
> `characters_screen.gd`. Les clés JSON `"name"` des routes compagnie sont INCHANGÉES — seuls
> des noms de PARAMÈTRES GDScript bougent.
>
> **Validation (MCP éditeur, EN JEU — pas headless).** Run complet : boot → menu (session
> restaurée) → écran Profil monté (`change_scene` piloté par `game_eval`) → dialogue QUITTER
> ouvert/refermé → **journal du run : 2 lignes info, 0 ERROR, 0 WARNING** (contre 8 lignes dont
> 3 rouges sur le run témoin d'avant correctifs, même parcours). Les 10 scripts rechargés en
> jeu : `can_instantiate()` vrai partout.
>
> ⚠️ **Contre-épreuve restante** : les avertissements statiques sont émis par
> `GDScript::reload()` au rechargement des scripts DANS l'éditeur (regain de focus). Au prochain
> focus de l'éditeur, l'onglet Erreurs du débogueur doit rester vide — s'il reste une ligne,
> c'est un résidu de ce lot.

---

## §8.131 — FINITIONS PRÉ-PLAYTEST : carte POUVOIR, surlignage du coach, invitation, barre basse

> **2 août 2026** · Lots A/B/E **100 % client** · Lot C = **VPS + client ENSEMBLE**.

### 1. ⚠️ Mise au point : les trois boutons Battle Royale EXISTAIENT DÉJÀ

Le reste-à-faire §9 du chantier tutoriel (« boutons RÉANIMER / SE RENDRE / COUP D'ÉTAT toujours
absents du HUD ») était **PÉRIMÉ** : ils ont été livrés par la passe 02 du §8.125 et sont commités
(`main.gd:_append_battle_royale_actions`). Le Battle Royale n'était donc pas injouable. Ce lot
n'ajoute pas les boutons — il **solde les quatre écarts** qui restaient face à la spec.

| écart | avant | après |
|---|---|---|
| Confirmation | le clic ENVOYAIT directement | **modale** à deux temps sur les 3 gestes |
| Coût de réanimation | constante client en dur | lu de `battle_royale.rules` (repli client) |
| Coup d'État | armement du bouton (« ⚠ CONFIRMER ») | **modale + RAPPORT DE FORCE** chiffré |
| Vote de reddition | silencieux chez les coéquipiers | **toast** + compteur |

### 2. `hud.show_confirm(spec)` — confirmation modale d'arène

`{title, body, detail?, detail_color?, confirm, accent?, action}` → signal
**`confirm_accepted(action)`**. Voile plein écran + panneau centré, patron
`warzone_ui._open_info_modal`, **deux boutons** (ANNULER à gauche : la sortie sans conséquence doit
être la plus facile à viser). `hide_confirm()` / `is_confirm_open()`.

- Le grisage protège du geste **ILLÉGAL** ; il ne protège pas du geste **MALHEUREUX**, celui qu'on
  fait en visant le bouton d'à côté. L'idempotence serveur (`action_id`) couvre le double-envoi,
  pas l'erreur de visée — et ici l'erreur tue son auteur.
- **Le voile est `MOUSE_FILTER_STOP`** : la racine du HUD est `IGNORE`, sans quoi un clic « à côté »
  traverserait jusqu'au PLATEAU et sélectionnerait un territoire derrière la question posée.
- ⚠️ **Ancrage APRÈS `add_child`** — sur un Control encore détaché, le preset se compose avec la
  taille courante et **DOUBLE le rect** (piège payé au §8.121).
- Refermée par : ANNULER, clic hors panneau, **ESC** (branche placée EN TÊTE de `_unhandled_input`,
  sinon ESC ouvrirait le Manuel PAR-DESSUS), un refus serveur, et **tout changement de tour** (son
  chiffrage a été calculé dans le tour précédent).
- **RAPPORT DE FORCE** du coup d'État : `main._coup_power(pid)` est le MIROIR EXACT de
  `engine._coup_power` (garnisons de toute la carte + PV de héros, deux termes PUBLICS). Verdict
  **FAVORABLE / DÉFAVORABLE** sur le `>` **strict** — annoncer « FAVORABLE » sur une égalité serait
  le pire mensonge possible de cette interface. Un coup défavorable n'est PAS bloqué : le traître a
  le droit de se sacrifier en connaissance de cause.

### 3. ⚠️ ORDRE DE LA CARTE POUVOIR : le DÉCISIF avant le ROUTINIER

**Défaut vu EN CAPTURE, invisible au boot headless.** `%PowerBox` est plafonné à 315 px et DÉFILE
(§8.128). Les actions BR étant ajoutées EN DERNIER, une partie de traître affichait dans l'ordre :
ligne d'ordre secret (2 lignes) → RATIONNER → RÉANIMER, et repoussait **COUP D'ÉTAT et SE RENDRE
SOUS LE PLI** — le geste le plus décisif du mode caché derrière un défilement que rien n'annonçait.
`_append_battle_royale_actions` est donc appelée **AVANT** le bloc des capacités de héros.

> Règle : ces trois actions sont **uniques dans une partie** et changent son issue ; RATIONNER se
> rejoue à chaque tour et le joueur sait déjà où il vit.

### 4. ⚠️⚠️ Pourquoi un non-traître ne voit AUCUN bouton de coup d'État — pas même grisé

C'est la **seule exception** du HUD à la règle « toujours afficher, griser avec sa raison » (§8.119),
et elle est délibérée. Le tirage est **TOUT-OU-RIEN et GLOBAL** : soit chaque équipe a son traître,
soit aucune. Un bouton grisé « vous n'avez pas d'ordre » apprendrait au joueur que le dispositif est
actif dans SA partie ; comme le tirage est global, il en déduirait aussitôt que **l'équipe adverse a
le sien** — un renseignement que le serveur refuse précisément de donner. L'absence de bouton est
donc **AMBIGUË PAR CONSTRUCTION** : elle ne distingue pas « pas de traître » de « le traître, c'est
quelqu'un d'autre ».

### 5. `board.tutorial_highlight(tid)` / `tutorial_highlight_clear()`

Le reste-à-faire §9 du tutoriel : l'étape ATTAQUER ne désignait aucun territoire. **Aucune
conversion monde→écran n'a été écrite** — elle aurait exigé de suivre zoom, travelling et recadrage
de la caméra tactique à chaque frame. Le surlignage **emprunte le canal EXISTANT du télégraphe de
zone** (`territory_forecast`, liseré or pulsant) : zéro shader neuf, coordonnées de CARTE, et il
suit la caméra gratuitement puisqu'il est dessiné DANS le plateau. `reduced_motion` est déjà géré en
aval par `motion_scale` → liseré FIXE, sans une ligne de plus.

- Cible = **meilleur ratio** via `main.tutorial_attack_hint()`, qui classe des cibles déjà légales
  (`_valid_attack_targets`) avec la prévision déjà calculée pour le survol (`CombatOdds`, G4). Le
  coach ne calcule aucune règle. `{}` → texte générique, jamais un territoire au hasard.
- Le coach ajoute « **Visez X — n % de victoire** » (nom TRADUIT, `TUTO_STEP_ATTACK_TARGET`).
- ⚠️ **QUATRE CHEMINS DE NETTOYAGE**, tous testés : 1ʳᵉ attaque (`_close_step("attack")` — explicite,
  car `_pump()` sort immédiatement quand la file est vide), changement d'étape, « PASSER LE
  BRIEFING », fin de partie (**avant** la garde `guided`, sinon un briefing déjà soldé laisserait un
  liseré). Un liseré or orphelin se lirait comme une **zone radioactive annoncée**.

### 6. Invitation de compagnie — toast de nav + bouton d'escouade

- `top_nav` gagne **son unique `Timer`** (`INVITE_POLL_S = 15`, soit **4 requêtes/min**). Il est
  **enfant de l'instance** et meurt avec l'écran : visiter cinq écrans ne fait donc pas tourner cinq
  sondages. ⚠️ **L'arène ne monte aucune `top_nav`** → aucun poll pendant un match (vérifié sur la
  scène réelle, pas supposé).
- Toast `[TAG] pseudo VOUS INVITE — REJOINDRE` → `squad_join(code)` + bascule sur `squad_screen`.
  `{}` = plus d'invitation → il disparaît **SANS un mot** : une invitation qui expire n'est pas un
  évènement, l'annoncer ferait passer un non-évènement pour une mauvaise nouvelle.
- `squad_screen` : bouton **INVITER LA COMPAGNIE**, réservé au CHEF et seulement une fois l'escouade
  créée. ⚠️ `POST /company/invite` **PARTAGE** le callback d'état de compagnie : sa réponse
  (`{invited, reason}`) ne porte aucune clé `company`, et la traiter comme un état **ferait
  disparaître toute la section compagnie** au moment précis où l'on vient d'inviter — d'où la garde
  `if data.has("invited")`.

### 7. Barre basse : l'état replié survit au redimensionnement

`_apply_bottom_panel_state(animated)` devient le **point unique** qui dérive la position ET le
glyphe ▲/▼ du **BOOLÉEN** `_bottom_hidden` ; `resized` le rappelle sans animation.

⚠️ **Le diagnostic du reste-à-faire §9 était incomplet.** Reproduit pas à pas, le déclencheur n'est
pas le redimensionnement en soi : hors glissement, les ancres replacent la barre correctement seules
(vérifié à 1280×720, 1600×900, 1024×768). Le vrai déclencheur est le **redimensionnement PENDANT LE
GLISSEMENT** : le Tween court vers un `target_y` calculé pour l'ANCIENNE hauteur et l'impose à
l'arrivée. Mesuré sans correctif — repli lancé en 1920×1080 puis passage à 1280×720 → la barre
atterrit à **y = 1037 sur un écran de 720 px**, soit elle ET son bouton sous le bord inférieur. Ce
n'était donc pas cosmétique : c'est la **panne irrécupérable du §3.1 par un autre chemin**.

> **Validation.** 4 contre-épreuves Godot (`tools/test_br_actions` **28** ·
> `test_tutorial_highlight` **16** · `test_company_invite_poll` **6** · `test_bottom_bar_resize`
> **18**), chacune **vérifiée par sabotage** (elle échoue quand on retire le correctif).
> `--import` **0 ERROR** · boot headless de 6 scènes **0 ERROR** · **10 captures PNG relues**.
> ⚠️ Rappel : un `assert` GDScript faux **fait HANGER** Godot (sortie 124 sous `timeout`), il ne
> rend jamais un code non nul — le critère est « exit 0 **ET** ligne `asserts verts` présente ».
