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
# Réglages de CONFORT (E8 combat_display §8.80 / E10 accessibilité §8.82) : une clé, un défaut,
# un signal de changement (même contrat que get_volume/set_volume). Consommés à la volée par le
# HUD/le plateau (aucun redémarrage requis).
signal comfort_changed(key: String, value)

const _CONFIG_PATH := "user://settings.cfg"

# Défauts des réglages de confort (persistés dans la section [comfort]). Le TYPE du défaut fixe
# la coercition à la relecture (bool/float/String).
const COMFORT_DEFAULTS := {
	"combat_display": "cinematique",   # E8 : cinematique / rapide / bandeau
	"reduced_motion": false,           # E10 : coupe VFX/pulses/particules
	"colorblind_mode": false,          # E10 : palette Okabe-Ito + motifs
	"ui_scale": 1.0,                   # E10 : 0.9 / 1.0 / 1.15 / 1.3
	"damage_numbers": true,            # E10 : flotteurs de dégâts
}
var _comfort := {}

# Clé interne -> nom du bus audio (default_bus_layout.tres). Lecture défensive : si le
# bus n'existe pas (layout absent), on ignore proprement (pas d'erreur « Invalid bus »).
const BUSES := {"master": "Master", "music": "Music", "sfx": "SFX"}

# Résolutions proposées en mode fenêtré (16:9). Index persisté.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const DEFAULT_RESOLUTION_INDEX := 2  # 1920 × 1080

# État courant (valeurs par défaut = ce qui s'applique au tout premier lancement).
var _volumes := {"master": 0.8, "music": 0.7, "sfx": 0.8}
var _fullscreen := true
var _resolution_index := DEFAULT_RESOLUTION_INDEX

# --- Gameplay (§8.92) : personnage choisi dans l'écran Personnages, persisté en [gameplay] ---
# id snake_case de faction, "" = aucun choix explicite (le menu retombe alors sur la dernière
# faction JOUÉE, puis sur le défaut alphabétique). Volontairement HORS de COMFORT_DEFAULTS : ce
# n'est pas un réglage de confort typé/gated, mais une préférence libre → API dédiée.
var _selected_faction: String = ""

func _ready() -> void:
	_load()
	_apply_all()
	_apply_ui_scale()

# --- Lecture publique (la Vue initialise ses contrôles depuis le manager) ---
func get_volume(bus: String) -> float:
	return float(_volumes.get(bus, 0.8))

func is_fullscreen() -> bool:
	return _fullscreen

func get_resolution_index() -> int:
	return _resolution_index

# --- Gameplay (§8.92) : personnage sélectionné ------------------------------
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

# Applique le facteur d'échelle d'interface (E10 §8.82) : content_scale_factor de la fenêtre —
# agrandit TOUTE l'UI (menus + HUD). Ignoré en headless (validation CLI).
func _apply_ui_scale() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w := get_window()
	if w != null:
		w.content_scale_factor = float(get_comfort("ui_scale"))

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
	# Confort (E8/E10) : relecture typée par le défaut de chaque clé.
	for key in COMFORT_DEFAULTS:
		_comfort[key] = cfg.get_value("comfort", key, COMFORT_DEFAULTS[key])
	# Gameplay (§8.92) : id de faction choisi (str() défensif — un ConfigFile relit en Variant).
	_selected_faction = str(cfg.get_value("gameplay", "selected_faction", _selected_faction))

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
	cfg.save(_CONFIG_PATH)
