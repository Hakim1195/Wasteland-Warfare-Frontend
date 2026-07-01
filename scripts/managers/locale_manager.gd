extends Node

# =========================================================================
# LOCALE MANAGER (Feuille de route R4) — Internationalisation FR / EN / IT
# =========================================================================
# Autoload : applique la langue choisie AU DÉMARRAGE (avant l'affichage du premier
# écran), la PERSISTE sur disque (user://settings.cfg) et l'expose à l'UI via un signal.
#
# Règle d'Or §6.1 : la logique de langue vit ICI (manager). Les écrans ne font qu'émettre
# (set_locale) ou écouter (locale_changed) — ce sont des Vues pures.
#
# Les tables de traduction (translations/ui_strings.*.translation, générées du CSV) sont
# déclarées dans project.godot (internationalization/locale/translations) : TranslationServer
# les charge tout seul. On ne fait ici que SÉLECTIONNER la locale active et la mémoriser.

signal locale_changed(code: String)

# Langues gérées (codes ISO 639-1). DOIT rester aligné sur les colonnes du CSV (fr/en/it).
const SUPPORTED := ["fr", "en", "it"]
# Langue d'auteur du jeu (les .tscn/.gd sont écrits en français) → repli par défaut.
const DEFAULT_LOCALE := "fr"

const _CONFIG_PATH := "user://settings.cfg"
const _SECTION := "locale"
const _KEY := "code"

func _ready() -> void:
	# Appliqué le plus tôt possible : l'autoload est instancié AVANT la scène principale,
	# donc la locale est déjà bonne quand le premier écran lit son texte traduit.
	TranslationServer.set_locale(_load_saved_locale())

# Code de langue actif normalisé (langue seule, ex. "fr"). Repli sur DEFAULT_LOCALE
# si la locale courante n'est pas une des langues gérées.
func current_locale() -> String:
	var code := TranslationServer.get_locale().substr(0, 2).to_lower()
	return code if code in SUPPORTED else DEFAULT_LOCALE

# Change la langue active : applique, persiste, et notifie l'UI (re-traduit les libellés
# construits par code, qui ne se rafraîchissent pas automatiquement comme les nœuds .tscn).
func set_locale(code: String) -> void:
	if not code in SUPPORTED:
		code = DEFAULT_LOCALE
	TranslationServer.set_locale(code)
	_save_locale(code)
	locale_changed.emit(code)

# --- Persistance ------------------------------------------------------------
func _load_saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_CONFIG_PATH) == OK:
		var saved := str(cfg.get_value(_SECTION, _KEY, ""))
		if saved in SUPPORTED:
			return saved
	# Aucune préférence enregistrée : on suit la langue de l'OS si elle est gérée, sinon FR.
	var os_code := OS.get_locale_language()
	return os_code if os_code in SUPPORTED else DEFAULT_LOCALE

func _save_locale(code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_CONFIG_PATH)  # préserve d'éventuels autres réglages (volume, etc. — futur R5)
	cfg.set_value(_SECTION, _KEY, code)
	cfg.save(_CONFIG_PATH)
