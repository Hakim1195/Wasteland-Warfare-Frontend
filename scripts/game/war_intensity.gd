extends RefCounted
class_name WarIntensity

# =============================================================================
# `war_intensity` — LA JAUGE DE TENSION UNIQUE (chantier « Sensoriel & Immersion », LOT A)
# =============================================================================
# Une seule valeur 0..1, calculée CÔTÉ CLIENT à partir de l'ÉTAT PUBLIC déjà diffusé (aucun champ
# serveur neuf, aucun contrat réseau touché), lissée, puis propagée à TOUS les consommateurs :
#   • la musique à couches      (LOT B — AudioManager.set_war_intensity)
#   • le compteur Geiger        (LOT C — même appel, l'ambiance suit la même courbe)
#   • le shader de carte        (LOT E — board.set_war_intensity → uniform `war_intensity`)
#
# ⚠️ INVARIANT DU CHANTIER : il n'existe QU'UNE formule. Si un jour un consommateur veut « sa »
# tension, il ajuste sa RÉPONSE à cette valeur (ses seuils), jamais une 2ᵉ formule — sinon la
# musique, le son et l'image racontent trois guerres différentes.
#
# Règle d'Or §6.1 : module de PRÉSENTATION pur. Fonctions STATIQUES, zéro I/O, zéro accès aux
# autoloads → testable sans scène (cf. `tools/test_war_intensity.tscn`).

# --- Pondérations (somme = 1,10 AVANT clamp : la saturation à 1.0 est VOULUE, une fin de partie
#     désespérée doit taper le plafond). À équilibrer au playtest. ---
const W_ROUND := 0.30            # la partie dure : la pression monte avec les rounds
const W_HEROES_PV := 0.25        # les héros de TOUS les belligérants saignent
const W_MY_PV := 0.15            # MON héros saigne (tension personnelle)
const W_ZONE := 0.15             # la zone radioactive s'étend
const W_FINAL_PROTOCOL := 0.25   # PROTOCOLE FINAL armé (§8.120)

# Rampes : nombre de rounds / de territoires contaminés au-delà duquel le terme sature.
const ROUND_RAMP := 8.0
const ZONE_RAMP := 8.0

# PLANCHER du PROTOCOLE FINAL : quoi qu'en dise le reste de la formule, les 2 dernières minutes
# de partie s'entendent et se voient. Sans ce plancher, un PROTOCOLE FINAL déclenché tôt (partie
# courte, peu de pertes) rendrait ≈ 0,57 — donc PAS de couche musicale « high », pas de vignette
# marquée : l'urgence annoncée à l'écran ne serait relayée par rien.
const FINAL_PROTOCOL_FLOOR := 0.85

# Lissage exponentiel, en « part de l'écart rattrapée par seconde ». Constante de temps = 1/0,4
# = 2,5 s : un saut brutal de l'état (héros qui meurt, PROTOCOLE FINAL) est rattrapé à ≈ 63 % en
# 2,5 s et ≈ 86 % en 5 s. L'intensité ne SAUTE donc jamais — c'est ce qui évite le pompage de la
# musique et le clignotement de la vignette.
const SMOOTH_SPEED := 0.4


# Calcule la tension BRUTE (non lissée) depuis un extrait de l'état public.
#
# `snapshot` (toutes les clés sont FACULTATIVES — un état pré-partie / partiel donne 0.0) :
#   round                  : int   — round courant (GameState.current_turn)
#   rounds_expected        : float — rampe de rounds SUR MESURE ; ≤ 0 / absent → ROUND_RAMP.
#                                    (Le serveur n'expose AUCUN champ de ce genre aujourd'hui :
#                                     main.gd ne le renseigne pas, la rampe reste ROUND_RAMP. La
#                                     clé existe pour qu'un futur « nombre de rounds attendu » se
#                                     branche ICI, et non dans une 2ᵉ formule.)
#   alive_heroes_pv_ratio  : float — moyenne 0..1 des PV% des héros VIVANTS (1.0 = tous intacts)
#   my_hero_pv_ratio       : float — MES PV% 0..1 (1.0 = intact)
#   zone_count             : int   — nb de territoires contaminés
#   final_protocol         : bool  — PROTOCOLE FINAL armé
static func compute(snapshot: Dictionary) -> float:
	var round_no := float(snapshot.get("round", 0))
	var ramp := float(snapshot.get("rounds_expected", 0.0))
	if ramp <= 0.0:
		ramp = ROUND_RAMP
	# Défauts « héros intacts » (1.0) : un état pré-RPG / pré-partie ne doit pas simuler une
	# hécatombe. C'est le repli SÛR — il tire l'intensité vers le BAS, jamais vers le haut.
	var heroes_pv := clampf(float(snapshot.get("alive_heroes_pv_ratio", 1.0)), 0.0, 1.0)
	var my_pv := clampf(float(snapshot.get("my_hero_pv_ratio", 1.0)), 0.0, 1.0)
	var zone := float(snapshot.get("zone_count", 0))
	var final_protocol := bool(snapshot.get("final_protocol", false))

	var v := W_ROUND * minf(maxf(round_no, 0.0) / ramp, 1.0)
	v += W_HEROES_PV * (1.0 - heroes_pv)
	v += W_MY_PV * (1.0 - my_pv)
	v += W_ZONE * minf(maxf(zone, 0.0) / ZONE_RAMP, 1.0)
	if final_protocol:
		v += W_FINAL_PROTOCOL
	v = clampf(v, 0.0, 1.0)
	# Plancher de fin de partie appliqué APRÈS le clamp (il ne peut que remonter la valeur).
	if final_protocol:
		v = maxf(v, FINAL_PROTOCOL_FLOOR)
	return v


# Lissage exponentiel INDÉPENDANT DU FRAMERATE (1 - e^(-k·dt)) : à 30 comme à 144 fps, la montée
# dure le même temps réel. `delta` ≤ 0 (première frame, pause) → aucun mouvement.
static func smooth(current: float, target: float, delta: float) -> float:
	if delta <= 0.0:
		return current
	return lerpf(current, target, 1.0 - exp(-SMOOTH_SPEED * delta))
