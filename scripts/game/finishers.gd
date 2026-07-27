extends RefCounted

# REGISTRE DATA-DRIVEN DES « FINISHERS » (REFONTE UI ARÈNE, lot D/G).
#
# Un finisher = la CINÉMATIQUE DE MISE À MORT jouée quand un héros tombe (permadeath §8.61).
# Elle est visible par TOUS les joueurs, quel que soit leur réglage de confort — c'est le moment
# le plus fort de la partie. Le finisher joué est celui du TUEUR (`equipped_finisher` de son
# PlayerState PUBLIC, miroir exact du système de skins M5 §8.69).
#
# Règle d'Or §6.3 (data-driven) : la cinématique ne connaît AUCUN id en dur — elle lit ses
# paramètres visuels ici. Un id inconnu (client plus ancien que le catalogue serveur) retombe
# SILENCIEUSEMENT sur le basique gratuit : jamais d'écran vide, jamais d'erreur.
#
# Le basique gratuit porte l'id "" — il n'est PAS au catalogue boutique (c'est le défaut de tout
# le monde). Les 3 autres ids sont ceux de `shop_catalog.py` (catégorie `finisher`).

# id → paramètres visuels. `sting` = nom de SFX (AudioManager : override fichier, sinon synthèse).
const FINISHERS := {
	"": {
		"name_key": "FINISHER_BASIC_NAME",
		"accent": "d6453f",        # rouge danger (charte §2)
		"secondary": "e0b249",     # or
		"sting": "hero_down",
		"streaks": 4,              # traits diagonaux du fond
		"particle_gravity": 240.0,
		"particle_spread": 180.0,
		"particle_amount": 40,
		"shockwave": true,
	},
	"finisher_barrage_acier": {
		"name_key": "FINISHER_STEEL_NAME",
		"accent": "8a97a5",        # acier
		"secondary": "36c5d9",     # cyan tactique
		"sting": "finisher_steel",
		"streaks": 9,
		"particle_gravity": 520.0,
		"particle_spread": 35.0,
		"particle_amount": 90,
		"shockwave": true,
	},
	"finisher_frappe_orbitale": {
		"name_key": "FINISHER_ORBITAL_NAME",
		"accent": "eef3f7",        # blanc froid (colonne de lumière)
		"secondary": "36c5d9",
		"sting": "finisher_orbital",
		"streaks": 1,
		"particle_gravity": -180.0,
		"particle_spread": 12.0,
		"particle_amount": 120,
		"shockwave": true,
	},
	"finisher_nuage_cendres": {
		"name_key": "FINISHER_ASH_NAME",
		"accent": "6a6a60",        # cendre
		"secondary": "8c6bd9",     # violet tactique
		"sting": "finisher_ash",
		"streaks": 6,
		"particle_gravity": -40.0,
		"particle_spread": 180.0,
		"particle_amount": 140,
		"shockwave": false,
	},
}

# Ids ACHETABLES (le basique gratuit est exclu) — sert à la boutique et aux tests.
static func purchasable_ids() -> Array:
	var out: Array = []
	for k in FINISHERS.keys():
		if str(k) != "":
			out.append(str(k))
	out.sort()
	return out

# Paramètres d'un finisher : repli SILENCIEUX sur le basique gratuit si l'id est vide, inconnu
# ou d'un type inattendu (piège JSON §5 : la valeur vient d'un PlayerState réseau).
static func params_for(finisher_id) -> Dictionary:
	var key := str(finisher_id) if finisher_id != null else ""
	if not FINISHERS.has(key):
		key = ""
	var raw: Dictionary = FINISHERS[key]
	# Copie NORMALISÉE (couleurs typées) — la vue n'a plus à convertir quoi que ce soit.
	return {
		"id": key,
		"name_key": str(raw.get("name_key", "FINISHER_BASIC_NAME")),
		"accent": Color(str(raw.get("accent", "d6453f"))),
		"secondary": Color(str(raw.get("secondary", "e0b249"))),
		"sting": str(raw.get("sting", "hero_down")),
		"streaks": int(raw.get("streaks", 4)),
		"particle_gravity": float(raw.get("particle_gravity", 240.0)),
		"particle_spread": float(raw.get("particle_spread", 180.0)),
		"particle_amount": int(raw.get("particle_amount", 40)),
		"shockwave": bool(raw.get("shockwave", true)),
	}
