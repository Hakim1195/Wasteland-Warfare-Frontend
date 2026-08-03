extends Node

# =========================================================================
# SETTINGS MANAGER (Feuille de route R5) — Réglages Audio / Affichage
# =========================================================================
# Autoload jumeau de LocaleManager : APPLIQUE les réglages au démarrage (avant
# l'affichage du premier écran), les PERSISTE sur disque (user://settings.cfg,
# le MÊME fichier que la langue) et les expose à l'UI.
#
# Règle d'Or §6.1 : toute la logique vit ICI (manager). L'écran Options (settings.tscn)
# n'est qu'une Vue : il LIT l'état initial (get_volume / is_fullscreen / …) et ÉMET les
# changements (set_volume / set_fullscreen / …). La langue reste gérée par LocaleManager.
#
# Audio : les volumes ciblent les bus du default_bus_layout.tres (Master / Music / SFX).
# Affichage : plein écran (borderless) vs fenêtré + résolution (appliquée en fenêtré).

signal audio_changed(bus: String, value: float)
signal display_changed()
# Réglages de CONFORT (mécanique posée en E8 §8.80, étendue E10 accessibilité §8.82) : une clé, un défaut,
# un signal de changement (même contrat que get_volume/set_volume). Consommés à la volée par le
# HUD/le plateau (aucun redémarrage requis).
signal comfort_changed(key: String, value)

const _CONFIG_PATH := "user://settings.cfg"

# Défauts des réglages de confort (persistés dans la section [comfort]). Le TYPE du défaut fixe
# la coercition à la relecture (bool/float/String).
# ⚠️ `combat_display` (E8 §8.80) a été RETIRÉ le 2026-07-27 (décision Hakim) : le rythme RAPIDE
# est devenu le comportement UNIQUE des combats, il n'y a donc plus de choix à persister. Une
# valeur résiduelle dans un `user://settings.cfg` existant devient simplement INERTE — `_load`
# n'itère que sur les clés ci-dessous, `_save` ne la réécrit plus, et plus aucun appelant ne lit
# `get_comfort("combat_display")`. Aucune migration nécessaire.
const COMFORT_DEFAULTS := {
	"reduced_motion": false,           # E10 : coupe VFX/pulses/particules
	"colorblind_mode": false,          # E10 : palette Okabe-Ito + motifs
	"ui_scale": 1.0,                   # E10 : 0.9 / 1.0 / 1.15 / 1.3 (cf. UI_SCALE_STEPS)
	"damage_numbers": true,            # E10 : flotteurs de dégâts
	# MODE STREAMER (§8.121, LOT E) — masque l'OBJECTIF SECRET en partie (et le renseignement
	# d'espionnage) derrière un « maintenir pour révéler ». Anti stream-sniping : l'objectif est la
	# SEULE information de l'écran qu'un spectateur puisse exploiter contre le joueur.
	# Défaut OFF : la très grande majorité des joueurs ne diffuse pas, et un masquage par défaut
	# ajouterait un geste à chaque coup d'œil sur son objectif. Rangé dans le CONFORT (et non dans
	# une section neuve) : c'est le même contrat qu'un réglage d'accessibilité — une clé, un défaut,
	# un signal, consommé à la volée par le HUD sans redémarrage.
	"streamer_mode": false,
	# CARTE VIVANTE (§8.122, LOT D) — cendres, fumées de guerre, feux de camp, éclairs de zone,
	# nuées d'oiseaux sur le plateau. Défaut ON (c'est le chantier « faire SENTIR la guerre »), mais
	# FORCÉ À OFF quand `reduced_motion` est actif : la carte vivante n'est QUE du mouvement, il n'y
	# a rien à en garder de statique. La coercition vit dans le consommateur (ambient_layer.gd), pas
	# ici : le réglage doit conserver la valeur choisie par le joueur pour la retrouver s'il coupe
	# `reduced_motion` — un forçage écrit sur disque lui ferait perdre son choix.
	"living_map": true,
	# AIDES CONTEXTUELLES (§8.129) — les bulles « première rencontre » qui expliquent UNE FOIS
	# chaque système avancé (pacte, PP, carte, PROTOCOLE FINAL, ordre secret…). Défaut ON : ce
	# chantier existe précisément parce que rien n'était expliqué nulle part. Couper le réglage
	# n'efface PAS la mémoire des bulles déjà vues — c'est « REVOIR LES AIDES » qui la remet à zéro,
	# et les deux gestes sont distincts à dessein (se taire ≠ tout recommencer).
	"context_hints": true,
}
var _comfort := {}

# Clé interne -> nom du bus audio (default_bus_layout.tres). Lecture défensive : si le
# bus n'existe pas (layout absent), on ignore proprement (pas d'erreur « Invalid bus »).
const BUSES := {"master": "Master", "music": "Music", "sfx": "SFX", "ambience": "Ambience"}

# Résolutions proposées en mode fenêtré (16:9). Index persisté.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const DEFAULT_RESOLUTION_INDEX := 2  # 1920 × 1080

# État courant (valeurs par défaut = ce qui s'applique au tout premier lancement).
# ⚠️ `ambience` (§8.122, LOT C) : 0,25 linéaire = -12,0 dB, le niveau « présent mais discret »
# décidé pour le bus Ambience (cf. default_bus_layout.tres). Il paraît bas à côté des trois autres
# — c'est VOULU : ce sont des boucles permanentes (Geiger, vent, radio), pas des ponctuations ;
# au même niveau que les SFX elles couvriraient la musique en continu.
var _volumes := {"master": 0.8, "music": 0.7, "sfx": 0.8, "ambience": 0.25}
var _fullscreen := true
var _resolution_index := DEFAULT_RESOLUTION_INDEX

# --- Gameplay (§8.93) : personnage choisi dans l'écran Personnages, persisté en [gameplay] ---
# id snake_case de faction, "" = aucun choix explicite (le menu retombe alors sur la dernière
# faction JOUÉE, puis sur le défaut alphabétique). Volontairement HORS de COMFORT_DEFAULTS : ce
# n'est pas un réglage de confort typé/gated, mais une préférence libre → API dédiée.
var _selected_faction: String = ""

# =========================================================
# MÉMOIRES LOCALES DE PROGRESSION (§8.122, LOT F)
# =========================================================
# Deux persistances 100 % LOCALES, sans le moindre appel réseau (exigence du chantier) :
#
#  1. `[progress]` dans settings.cfg — petites valeurs « dernière fois que j'ai vu X » : division
#     de ladder, solde de RP, panoplie équipée au dernier draft. Elles servent à DÉTECTER UN
#     CHANGEMENT entre deux sessions (promotion, skin nouvellement équipé). Toujours des String :
#     le contenu est comparé, jamais calculé.
#  2. `user://seen_items.json` — ids d'articles dont la fiche a déjà été ouverte. Alimente le chip
#     « NOUVEAU » (boutique + écran Personnages). Fichier SÉPARÉ : il grossit avec l'inventaire et
#     n'a rien à faire dans un fichier de réglages.
const SEEN_ITEMS_PATH := "user://seen_items.json"

var _progress := {}
var _seen_items := {}

func get_progress(key: String, default_value: String = "") -> String:
	return str(_progress.get(key, default_value))

func set_progress(key: String, value: String) -> void:
	if str(_progress.get(key, "")) == str(value):
		return   # rien de neuf : on n'écrit pas sur le disque pour rien
	_progress[key] = str(value)
	_save()

# Article déjà consulté ? Un id inconnu est réputé NEUF → chip « NOUVEAU ». C'est le bon défaut :
# au pire on signale une fois de trop un article que le joueur connaissait déjà.
func is_item_seen(item_id) -> bool:
	return _seen_items.has(str(item_id))

func mark_item_seen(item_id) -> void:
	var key := str(item_id)
	if key == "" or _seen_items.has(key):
		return
	_seen_items[key] = true
	_save_seen_items()

func _load_seen_items() -> void:
	_seen_items.clear()
	if not FileAccess.file_exists(SEEN_ITEMS_PATH):
		return
	var f := FileAccess.open(SEEN_ITEMS_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	# Fichier corrompu / d'un format antérieur : on repart d'un ensemble vide plutôt que de crasher.
	# Conséquence maximale : quelques chips « NOUVEAU » de trop. Aucune donnée de jeu n'est en jeu.
	if typeof(data) != TYPE_ARRAY:
		return
	for id in data:
		_seen_items[str(id)] = true

func _save_seen_items() -> void:
	var f := FileAccess.open(SEEN_ITEMS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_seen_items.keys()))
	f.close()


func _ready() -> void:
	_load()
	_load_seen_items()
	_apply_all()
	# ⚠️ ORDRE : `_apply_display()` (dans `_apply_all`) fixe d'abord la taille de la fenêtre —
	# l'assainissement d'échelle qui suit mesure donc la BONNE fenêtre, pas celle du démarrage.
	_apply_ui_scale()
	# §8.133 — l'échelle effective se recalcule à chaque redimensionnement (bascule plein écran,
	# changement de résolution, fenêtre tirée à la souris). Sans ça, un joueur qui rétrécit sa
	# fenêtre après le boot retombait dans l'enfermement que l'assainissement vient d'écarter.
	var w := get_window()
	if w != null:
		w.size_changed.connect(_on_window_resized)

# --- Lecture publique (la Vue initialise ses contrôles depuis le manager) ---
func get_volume(bus: String) -> float:
	return float(_volumes.get(bus, 0.8))

func is_fullscreen() -> bool:
	return _fullscreen

func get_resolution_index() -> int:
	return _resolution_index

# --- Gameplay (§8.93) : personnage sélectionné ------------------------------
# Persistance LOCALE à la machine (aucun champ serveur « faction sélectionnée » n'existe : la
# `favorite_faction` du profil est DÉRIVÉE de l'historique — sémantique différente).
func get_selected_faction() -> String:
	return _selected_faction

func set_selected_faction(fid: String) -> void:
	_selected_faction = str(fid)
	_save()

# --- Confort (E8/E10) : lecture / écriture générique typée -------------------
func get_comfort(key: String):
	return _comfort.get(key, COMFORT_DEFAULTS.get(key))

func set_comfort(key: String, value) -> void:
	if not COMFORT_DEFAULTS.has(key):
		return
	# Coercition sur le type du défaut (un ConfigFile relit parfois en Variant élargi).
	var def = COMFORT_DEFAULTS[key]
	if typeof(def) == TYPE_BOOL:
		value = bool(value)
	elif typeof(def) == TYPE_FLOAT:
		value = float(value)
	else:
		value = str(value)
	_comfort[key] = value
	_save()
	# ui_scale (E10 §8.82) : appliqué immédiatement à l'échelle de contenu de la fenêtre.
	if key == "ui_scale":
		_apply_ui_scale()
	comfort_changed.emit(key, value)

# =========================================================
# ÉCHELLE D'INTERFACE — assainissement automatique (§8.133)
# =========================================================
# LE BUG D'ORIGINE (mesuré le 2026-08-03, pas deviné) : `content_scale_factor` DIVISE le viewport
# logique. À 1.15 sur un écran 1920, l'UI ne dispose plus que de 1669 px logiques — or la barre de
# navigation en réclame 1801 au minimum (rangée 1721 + marges 40+40). La rangée débordait donc à
# droite et emportait le cluster identité + ⚙ + ⏻ HORS DE L'ÉCRAN : un joueur à 115 % ne pouvait
# plus ni ouvrir les paramètres, ni se déconnecter — donc plus revenir à 100 %. Enfermement.
#
# TROIS DÉFENSES, indépendantes (§8.133) :
#   1. ICI — l'échelle EFFECTIVE est bornée à ce que la fenêtre peut réellement porter ;
#   2. `top_nav._relayout()` — la nav se DÉGRADE (densité, marque, débordement) jusqu'à tenir ;
#   3. `settings.gd` — confirmation à rebours de 10 s sur tout changement d'échelle.
#
# ⚠️ LA PRÉFÉRENCE SAUVEGARDÉE N'EST JAMAIS MODIFIÉE. On ne réécrit pas le choix du joueur parce
# qu'il a réduit sa fenêtre : c'est l'APPLICATION qui est bornée. La fenêtre regrandit → la
# préférence reprend effet toute seule, sans rien re-cliquer.

# Paliers d'échelle proposés — SOURCE UNIQUE (l'écran Paramètres les lit ici, il n'en code aucun).
const UI_SCALE_STEPS: Array[float] = [0.9, 1.0, 1.15, 1.3]

# Largeur logique minimale d'un ÉCRAN DE HUB : les panneaux centraux du dépôt (écran DÉFIS, hub
# ÉVÉNEMENTS) sont posés à `custom_minimum_size.x = 980`, plus les marges latérales de 40 px de
# part et d'autre. En dessous, ce n'est plus la nav qui déborde mais le CONTENU — et aucune
# dégradation de barre ne peut le rattraper. C'est donc le vrai plancher de l'échelle.
const HUB_CONTENT_MIN_WIDTH := 1060.0

# Marge de sécurité (px logiques) ajoutée au plancher mesuré : absorbe les variations de LANGUE
# (un onglet allemand est plus large qu'un onglet français) et les arrondis de rendu de police.
const UI_SCALE_SAFETY_MARGIN := 24.0

# PLANCHER MESURÉ de la barre de navigation entièrement dégradée (logo seul + onglet actif + menu
# « ••• » + cluster droit intouchable). Rapporté par `top_nav` à chaque construction — donc juste,
# quelle que soit la langue et le nombre d'onglets du jour. Vaut 0 avant la première nav : le boot
# retombe alors sur `HUB_CONTENT_MIN_WIDTH` seul, qui est de toute façon le terme dominant.
var _nav_floor_width: float = 0.0

# Largeur logique EN DESSOUS DE LAQUELLE l'interface ne fonctionne plus, quoi qu'on dégrade.
func ui_min_logical_width() -> float:
	return maxf(_nav_floor_width, HUB_CONTENT_MIN_WIDTH) + UI_SCALE_SAFETY_MARGIN

# Appelé par `top_nav` avec la largeur minimale de sa rangée LA PLUS DÉGRADÉE. On ne garde que la
# valeur la plus CONTRAIGNANTE de la session : une nav mesurée sur un écran aux onglets nombreux ne
# doit pas être « oubliée » par un écran qui en montre moins.
func report_nav_floor_width(px: float) -> void:
	if px <= 0.0 or px <= _nav_floor_width:
		return
	_nav_floor_width = px
	_apply_ui_scale()

# Largeur PHYSIQUE de la fenêtre (px réels). En headless, le viewport racine fait foi.
func _window_width() -> float:
	var w := get_window()
	if w == null:
		return 0.0
	return float(w.size.x)

# Cette échelle tient-elle dans la fenêtre courante ? `largeur_min_logique × échelle ≤ largeur
# physique` — c'est la même inégalité que `logique = physique / échelle ≥ largeur_min_logique`,
# écrite sans division pour ne pas dépendre d'un `échelle > 0`.
func ui_scale_fits(step: float, window_width: float = -1.0) -> bool:
	var width: float = window_width if window_width > 0.0 else _window_width()
	if width <= 0.0:
		return true   # taille inconnue (headless, fenêtre pas encore créée) → on ne bride rien.
	return ui_min_logical_width() * float(step) <= width

# Plus grande échelle proposée qui tienne. Le plus PETIT palier est le plancher : on ne descend
# jamais en dessous de 0.9, même sur une fenêtre minuscule — c'est alors à la nav de se dégrader.
func max_ui_scale_that_fits(window_width: float = -1.0) -> float:
	var best: float = UI_SCALE_STEPS[0]
	for s in UI_SCALE_STEPS:
		if s > best and ui_scale_fits(s, window_width):
			best = s
	return best

# Échelle réellement APPLIQUÉE = min(préférence, ce que la fenêtre peut porter).
func effective_ui_scale() -> float:
	return minf(float(get_comfort("ui_scale")), max_ui_scale_that_fits())

# Applique le facteur d'échelle d'interface (E10 §8.82, assaini §8.133) : content_scale_factor de
# la fenêtre — agrandit TOUTE l'UI (menus + HUD). Ignoré en headless (validation CLI).
func _apply_ui_scale() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	if w == null:
		return
	var target := effective_ui_scale()
	# Écriture conditionnelle : `content_scale_factor` déclenche un relayout complet, et cette
	# fonction est rappelée à CHAQUE redimensionnement (donc en rafale pendant un drag de fenêtre).
	if not is_equal_approx(w.content_scale_factor, target):
		w.content_scale_factor = target

# Redimensionnement de fenêtre : l'échelle effective peut changer dans les DEUX sens — se brider
# quand la fenêtre rétrécit, et reprendre la préférence complète quand elle regrandit.
func _on_window_resized() -> void:
	_apply_ui_scale()

# Libellés « L × H » pour le sélecteur de résolution (numériques → pas de traduction).
func resolution_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for r in RESOLUTIONS:
		out.append("%d × %d" % [r.x, r.y])
	return out

# --- Audio ------------------------------------------------------------------
func set_volume(bus: String, value: float) -> void:
	if not BUSES.has(bus):
		return
	_volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)
	_save()
	audio_changed.emit(bus, _volumes[bus])

func _apply_volume(bus: String) -> void:
	var bus_name: String = BUSES.get(bus, "")
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return  # bus absent (layout non chargé) → on ignore proprement
	var v: float = _volumes[bus]
	if v <= 0.0005:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(v))

# --- Affichage --------------------------------------------------------------
func set_fullscreen(on: bool) -> void:
	_fullscreen = on
	_apply_display()
	_save()
	display_changed.emit()

func set_resolution_index(index: int) -> void:
	_resolution_index = clampi(index, 0, RESOLUTIONS.size() - 1)
	_apply_display()
	_save()
	display_changed.emit()

func _apply_display() -> void:
	# En headless (validation CLI), DisplayServer est un pilote factice : on n'applique rien.
	if DisplayServer.get_name() == "headless":
		return
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		return
	# --- Mode fenêtré ---------------------------------------------------------
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	var screen := DisplayServer.window_get_current_screen()
	# Zone UTILISABLE de l'écran (exclut la barre des tâches) — et NON screen_get_size(), qui inclut
	# la barre des tâches : une fenêtre dimensionnée dessus déborderait dessous.
	var usable := DisplayServer.screen_get_usable_rect(screen)
	# Surcoût des décorations (barre de titre + bordures dessinées par l'OS). window_set_size() fixe
	# la taille du CONTENU : sans réserver la barre de titre, une fenêtre aussi haute que l'écran
	# déborde de la hauteur de sa barre de titre. (Mesure fiable sur Windows, la cible du projet.)
	var deco := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	var geo := compute_windowed_geometry(usable, deco, RESOLUTIONS[_resolution_index])
	DisplayServer.window_set_size(geo["size"])
	DisplayServer.window_set_position(geo["position"])

# Géométrie de la fenêtre fenêtrée : taille + position pour qu'elle tienne ENTIÈREMENT (décorations
# comprises) dans la zone utilisable `usable`, centrée — quel que soit l'écran (portable 1366×768,
# 16:10, résolution choisie plus grande que l'écran…). Sans ce bornage, une résolution supérieure à
# l'écran plaçait la fenêtre en coordonnées négatives : barre de titre hors écran, fenêtre ni
# déplaçable ni atteignable. Fonction PURE (aucun accès DisplayServer) → testable en headless.
static func compute_windowed_geometry(usable: Rect2i, deco: Vector2i, res: Vector2i) -> Dictionary:
	deco = Vector2i(maxi(deco.x, 0), maxi(deco.y, 0))
	# Taille du CONTENU bornée pour que la fenêtre décorée tienne dans la zone utilisable, avec un
	# plancher de sécurité (pilote renvoyant une zone utilisable dégénérée).
	var avail := usable.size - deco
	var size := Vector2i(maxi(mini(res.x, avail.x), 640), maxi(mini(res.y, avail.y), 360))
	# Espace libre autour de la fenêtre DÉCORÉE (jamais négatif → jamais de position hors écran).
	var free := usable.size - (size + deco)
	free = Vector2i(maxi(free.x, 0), maxi(free.y, 0))
	# La position cible le CONTENU : bordures latérales ≈ deco.x/2, barre de titre = deco.y au-dessus.
	# Division entière VOULUE (pixels entiers) — avertissement tu, inoffensif ici.
	@warning_ignore("integer_division")
	var pos := usable.position + Vector2i(deco.x / 2, deco.y) + free / 2
	return {"size": size, "position": pos}

func _apply_all() -> void:
	for bus in BUSES:
		_apply_volume(bus)
	_apply_display()

# --- Persistance (user://settings.cfg, partagé avec LocaleManager) ----------
func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_CONFIG_PATH) != OK:
		return
	for bus in _volumes:
		_volumes[bus] = clampf(float(cfg.get_value("audio", bus, _volumes[bus])), 0.0, 1.0)
	_fullscreen = bool(cfg.get_value("display", "fullscreen", _fullscreen))
	_resolution_index = clampi(int(cfg.get_value("display", "resolution_index", _resolution_index)), 0, RESOLUTIONS.size() - 1)
	# Confort (E10) : relecture typée par le défaut de chaque clé.
	for key in COMFORT_DEFAULTS:
		_comfort[key] = cfg.get_value("comfort", key, COMFORT_DEFAULTS[key])
	# Gameplay (§8.93) : id de faction choisi (str() défensif — un ConfigFile relit en Variant).
	_selected_faction = str(cfg.get_value("gameplay", "selected_faction", _selected_faction))
	# Mémoires locales de progression (§8.122) : section libre, clés inconnues tolérées (une clé
	# retirée du code devient simplement inerte — même contrat que `combat_display`).
	_progress.clear()
	for key in cfg.get_section_keys("progress") if cfg.has_section("progress") else PackedStringArray():
		_progress[str(key)] = str(cfg.get_value("progress", key, ""))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_CONFIG_PATH)  # préserve la section [locale] gérée par LocaleManager
	for bus in _volumes:
		cfg.set_value("audio", bus, _volumes[bus])
	cfg.set_value("display", "fullscreen", _fullscreen)
	cfg.set_value("display", "resolution_index", _resolution_index)
	for key in COMFORT_DEFAULTS:
		cfg.set_value("comfort", key, _comfort.get(key, COMFORT_DEFAULTS[key]))
	cfg.set_value("gameplay", "selected_faction", _selected_faction)
	for key in _progress:
		cfg.set_value("progress", key, str(_progress[key]))
	cfg.save(_CONFIG_PATH)
