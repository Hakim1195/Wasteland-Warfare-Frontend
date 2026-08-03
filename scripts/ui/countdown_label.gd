extends Label

# =========================================================================
# COMPTE À REBOURS — composant réutilisable (§8.134), 100 % code
# =========================================================================
# LE seul afficheur de temps du hub. Avant lui, trois écrans formataient leur propre rebours
# (`events_screen._duration_label`, `main_menu._update_event_countdown`, la carte du QG) : trois
# implémentations, trois façons d'arrondir, trois moments de bascule. Le « rendu professionnel »
# demandé n'est pas un effet graphique — c'est cette COHÉRENCE : partout le même format, la même
# seconde de bascule, la même couleur d'urgence.
#
# TROIS RÉGIMES, du lointain à l'imminent :
#   ≥ 48 h  → « 3J 14H »   : au-delà de deux jours, la seconde n'apprend rien à personne.
#   < 48 h  → « HH:MM:SS » : on entre dans l'échelle où l'on décide de jouer ce soir ou pas.
#   < 1 h   → idem, en OR + pulsation discrète : c'est le régime « dépêche-toi ».
#   = 0     → « TERMINÉ », et le signal `expired` prévient le parent d'aller RECHARGER ses données.
#
# ⚠️ CHIFFRES TABULAIRES. Sans eux, « 1 » étant plus étroit que « 8 », l'heure entière TREMBLE à
# chaque seconde. La charte §2 n'a AUCUNE police monospace — en introduire une casserait l'identité
# typographique de tout le hub. On active donc la fonctionnalité OpenType `tnum` (chasse fixe des
# chiffres) SUR la police de la charte : même dessin, colonnes stables. Si la police système chargée
# ne porte pas `tnum`, la ligne est un no-op silencieux — d'où la largeur minimale réservée en
# ceinture, qui empêche de toute façon la mise en page de bouger.
#
# ⚠️ HORLOGE LOCALE, ASSUMÉE (constat §8.132 reconduit). Le brief demandait « epoch serveur + offset
# d'horloge existant (§8.31) » : cet offset N'EXISTE PAS hors de l'arène — il est porté par le
# message WebSocket `timer_updated`, que les écrans de hub ne reçoivent jamais. Le rebours se calcule
# donc contre l'horloge locale, contre un epoch SERVEUR : la dérive possible se compte en secondes
# sur des fenêtres de 54 h ou 7 jours. Invisible. Les timers de PARTIE, eux, gardent leur offset —
# là, une seconde compte vraiment.

signal expired

const ACCENT := Color(0.211765, 0.772549, 0.85098, 1)
const GOLD := Color(0.878431, 0.698039, 0.286275, 1)

# Seuils de régime (secondes).
const LONG_FORM_S := 172800   # 48 h — au-delà, on n'affiche plus que jours + heures.
const URGENT_S := 3600        # 1 h  — en deçà, passage à l'or + pulsation.

# Largeur réservée (px) pour que la mise en page ne bouge pas d'un régime à l'autre. Ceinture du
# `tnum` : elle vaut même si la police système ne porte pas la fonctionnalité.
const MIN_WIDTH := 210.0

# Cible : epoch UTC (entier, §5) et sens de lecture.
var _target_epoch: int = 0
var _prefix_key: String = "COUNTDOWN_ENDS_IN"
var _base_color: Color = ACCENT
var _last_second: int = -1
var _expired_sent: bool = false
var _pulse: Tween = null


static func make(font_size: int = 18, color: Color = ACCENT):
	"""Fabrique — l'appelant ne construit jamais le Label à la main (une seule définition du style)."""
	var l = new()
	l.add_theme_font_size_override("font_size", font_size)
	l._base_color = color
	l.add_theme_color_override("font_color", color)
	return l


func _ready() -> void:
	# Textes COMPOSÉS et déjà traduits : l'auto-traduction les rechercherait comme des clés.
	auto_translate_mode = Control.AUTO_TRANSLATE_MODE_DISABLED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = maxf(custom_minimum_size.x, MIN_WIDTH)
	add_theme_font_override("font", _make_font())
	_render()


func _make_font() -> Font:
	var base := SystemFont.new()
	base.font_names = PackedStringArray(
		["Bahnschrift", "Oswald", "Saira Condensed", "Arial Narrow", "Arial"])
	base.font_weight = 700
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	if ts != null:
		fv.opentype_features = {ts.name_to_tag("tnum"): 1}
	return fv


# Règle la cible. `prefix_key` : COUNTDOWN_ENDS_IN (« SE TERMINE DANS ») ou COUNTDOWN_STARTS_IN
# (« COMMENCE DANS »). Rappeler cette méthode RÉARME le composant — un parent qui recharge ses
# données après une bascule de fenêtre n'a rien d'autre à faire.
func set_target(epoch: int, prefix_key: String = "COUNTDOWN_ENDS_IN") -> void:
	_target_epoch = int(epoch)
	_prefix_key = str(prefix_key)
	_expired_sent = false
	_last_second = -1
	_render()


# ⚠️ `_process` plutôt qu'un Timer : le corps se réduit à une comparaison d'entiers tant que la
# seconde n'a pas changé, et le texte n'est donc RECOMPOSÉ qu'UNE fois par seconde — l'exigence du
# chantier. Un Timer par instance aurait ajouté un nœud et une connexion pour le même résultat.
func _process(_delta: float) -> void:
	var now := int(Time.get_unix_time_from_system())
	if now == _last_second:
		return
	_last_second = now
	_render()


func _render() -> void:
	if _target_epoch <= 0:
		text = ""
		return
	var remaining := _target_epoch - int(Time.get_unix_time_from_system())
	if remaining <= 0:
		text = _t("COUNTDOWN_OVER")
		add_theme_color_override("font_color", GOLD)
		_set_pulse(false)
		# Émis UNE SEULE FOIS : le parent recharge ses données, il ne doit pas être rappelé à chaque
		# seconde qui passe tant que la nouvelle réponse n'est pas arrivée.
		if not _expired_sent:
			_expired_sent = true
			expired.emit()
		return

	var urgent := remaining < URGENT_S
	add_theme_color_override("font_color", GOLD if urgent else _base_color)
	_set_pulse(urgent)
	text = _t(_prefix_key) % _duration(remaining)


# « 3J 14H » au-delà de 48 h, « HH:MM:SS » en deçà. Les heures ne sont PAS repliées en jours sous
# 48 h : « 47:12:04 » se lit d'un coup d'œil comme « demain soir », là où « 1J 23H » demande un
# calcul mental.
func _duration(seconds: int) -> String:
	if seconds >= LONG_FORM_S:
		@warning_ignore("integer_division")
		var d := seconds / 86400
		@warning_ignore("integer_division")
		var h := (seconds % 86400) / 3600
		return _t("COUNTDOWN_DAYS_HOURS") % [d, h]
	@warning_ignore("integer_division")
	var hh := seconds / 3600
	@warning_ignore("integer_division")
	var mm := (seconds % 3600) / 60
	return "%02d:%02d:%02d" % [hh, mm, seconds % 60]


# Pulsation d'urgence — respect strict de `reduced_motion` (§8.82) : sous ce réglage l'urgence se
# dit par la COULEUR seule. Un rebours qui clignote est précisément ce que ce confort vient couper.
func _set_pulse(on: bool) -> void:
	if on and bool(SettingsManager.get_comfort("reduced_motion")):
		on = false
	if on == (_pulse != null and _pulse.is_valid()):
		return
	if not on:
		if _pulse != null and _pulse.is_valid():
			_pulse.kill()
		_pulse = null
		modulate.a = 1.0
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "modulate:a", 0.55, 0.7)
	_pulse.tween_property(self, "modulate:a", 1.0, 0.7)


func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
