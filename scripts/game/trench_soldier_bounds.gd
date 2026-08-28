extends RefCounted

# =================================================================================================
# §8.152 — LOT 3D-G, ÉTAGE 0 : LA BOÎTE À BORNES DU SOLDAT ANIMÉ
#
# ╔═ POURQUOI CE FICHIER EXISTE, ET POURQUOI IL EST ÉCRIT **AVANT** LE MOINDRE CLIP ═════════════╗
# ║ ⛔ VERROU DU PROJET : « la silhouette de collision et les règles de simulation ne changent     ║
# ║ JAMAIS. La vue s'adapte à la boîte, jamais l'inverse. »                                       ║
# ║                                                                                               ║
# ║ Le soldat de la référence n'a **aucune** borne de ce genre : son squelette vit dans un monde   ║
# ║ volumétrique où un torse qui avance de 40 cm ne ment sur rien, puisque les balles y touchent   ║
# ║ des capsules replacées sur les os à chaque image. Chez nous, la cible est une **PLAQUE PLANE   ║
# ║ à Z constant**, dont la fenêtre angulaire est calculée par le serveur et figée dans une table  ║
# ║ checksumée. Tout ce que la vue déplace au-delà de cette plaque est un **mensonge** : le joueur ║
# ║ vise ce qu'il voit et touche ce que le serveur sait.                                          ║
# ║                                                                                               ║
# ║ Ce fichier est donc écrit EN PREMIER, et les clips passent par lui. Écrit après, il aurait    ║
# ║ fallu revenir sur chaque amplitude — et une amplitude qu'on oublie ne se voit pas.            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ LES SEPT DÉBORDEMENTS MESURÉS DE LA RÉFÉRENCE ══════════════════════════════════════════════╗
# ║ Chiffres obtenus en EXÉCUTANT leur code (balayage de 149 184 poses : 6 clips × 12 cibles de   ║
# ║ visée × 2 niveaux de suppression × 7 régions de touche × franchissement × recul).             ║
# ║                                                                                               ║
# ║   source              amplitude          bornée chez eux ?                                     ║
# ║   ───────────────     ───────────────    ─────────────────────────────────────────────────    ║
# ║   `_aimIk`            ±0,58 m en Z       angle oui (1,25 rad cumulés !), position NON          ║
# ║   `vault`             +0,66 m            NON — et la racine ajoute +0,42 m par-dessus          ║
# ║   `hurtIdle`          +0,40 m            NON                                                   ║
# ║   `crouchIdle`        −0,37 m            NON                                                   ║
# ║   `suppressAdd`       +0,27 m            NON                                                   ║
# ║   `hitAdd('head')`    −0,23 m            enveloppe oui, position NON                           ║
# ║   `hipOff` cumulé     **−0,514 m**       ⛔ AUCUNE BORNE — cinq couches y écrivent sans se voir ║
# ║   IK de pied          −0,32 m            ✅ oui (`animator.js:467`) — mais elle S'AJOUTE au     ║
# ║                                          `hipOff`, d'où **−0,83 m** de total                   ║
# ║                                                                                               ║
# ║ Enveloppe absolue de `HeadTop` sur le balayage complet :                                       ║
# ║   x ∈ [−0,500 ; +0,506]   y ∈ [0,237 ; **1,821**]   z ∈ [−0,638 ; +0,785]                       ║
# ║ À comparer à notre boîte : |x| ≤ 0,44 · y ≤ 1,80 · z = **constant**.                           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

const Geo := preload("res://scripts/game/trench_geometry.gd")


# =================================================================================================
# LES BORNES — TOUTES DÉRIVÉES, AUCUNE INVENTÉE
# =================================================================================================
# ⚠️ Lues dans `trench_geometry.gd`, jamais recopiées : ces cotes sont figées dans
# `trench_angles.json` côté serveur et **le serveur ne voit que des degrés**. Les recopier ici
# créerait une seconde source de vérité — le patron exact du §8.148.

# ── VERTICAL : une borne DURE ─────────────────────────────────────────────────────────────────
# Si la tête RENDUE monte à 1,81 m alors que la boîte serveur s'arrête à 1,80, un joueur qui vise
# le crâne qu'il voit **rate**. Ce n'est pas une approximation, c'est un mensonge.
const HAUT_DEBOUT: float = Geo.SILHOUETTE_TOP
const HAUT_ACCROUPI: float = Geo.SILHOUETTE_TOP_DOWN
const BAS: float = Geo.SILHOUETTE_BOTTOM

# ── LATÉRAL : une borne DURE aussi ────────────────────────────────────────────────────────────
# ⚠️ Mesuré : `HeadTop` sort à ±0,506 m, soit **66 mm de trop de chaque côté**.
# ⚠️ Et le ratio de largeur souvent cité (« leur modèle est 1,86× plus étroit ») est FAUX : leur
# modèle mesure 0,510 m de large (0,500 pour l'`irregular`, 0,521 pour le `breacher`), donc
# 0,88 / 0,510 = **1,725×**. Le 1,86 s'obtient en comparant notre demi-largeur 0,44 au seul côté
# +X du modèle (0,235 m) — or **le modèle est ASYMÉTRIQUE** : arme et deux mains en X négatif,
# `x ∈ [−0,275 ; +0,235]`. Comparer une demi-largeur à une demi-largeur de travers.
const DEMI_LARGEUR: float = Geo.SILHOUETTE_HALF_WIDTH

# ── PROFONDEUR : la borne qui n'existe pas chez eux, et qui est la plus subtile ────────────────
# ╔═ DÉRIVATION, PAS INVENTION ══════════════════════════════════════════════════════════════════╗
# ║ Notre silhouette est une PLAQUE à Z constant, dont la demi-largeur apparente vue de l'œil vaut ║
# ║ `atan(0,44 / D)`. Un morceau de corps déplacé de ΔZ vers l'observateur est vu sous             ║
# ║ `atan(0,44 / (D − ΔZ))` : il **grossit**, alors que la fenêtre de touche du serveur, elle, n'a ║
# ║ pas bougé.                                                                                     ║
# ║                                                                                               ║
# ║ L'unité de tolérance n'est pas choisie : c'est **`AIM_QUANTUM_DEG = 0,1°`**, le quantum de     ║
# ║ visée du projet. On exige que le désaccord reste **sous un quantum**, c'est-à-dire sous la     ║
# ║ résolution que le serveur sait distinguer.                                                     ║
# ║                                                                                               ║
# ║ Distance d'engagement la plus COURTE : du plan des soldats PROCHES (−0,5 m) à celui des        ║
# ║ soldats ADVERSES (`NO_MANS_LAND` + `SOLDIER_SETBACK` = 9,5 m), soit **10,00 m**. C'est là que  ║
# ║ la contrainte mord le plus — un même ΔZ compte d'autant plus qu'on est près.                   ║
# ║ ⚠️ Premier jet du commentaire : « 9,5 m ⇒ ~0,35 m ». Faux — il oubliait le recul du tireur     ║
# ║ lui-même. Le CODE, lui, passe par les accesseurs et donnait 10,00 m depuis le début : c'est le ║
# ║ commentaire qui mentait, pas le calcul. Chiffres relus À L'EXÉCUTION.                          ║
# ║                                                                                               ║
# ║   atan(0,44 / (10 − ΔZ)) − atan(0,44 / 10)  ≤  0,1°     ⇒  ΔZ ≤ **0,3823 m**                  ║
# ║                                                                                               ║
# ║ ⚠️ C'est le même défaut que le billboard du §8.141.7, qui a été DÉSACTIVÉ à dessein pour       ║
# ║ exactement cette raison : la largeur apparente doit suivre `0,88·cos(θ)` et rien d'autre.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func budget_profondeur() -> float:
	# ⚠️ On passe par l'accesseur EXISTANT plutôt que de recomposer la somme : la géométrie
	# l'expose déjà (`far_soldier_z()`), et recomposer aurait créé un troisième endroit où la
	# distance d'engagement est écrite. Le `NO_MANS_LAND` est passé de 35 à 12 puis à 9 m au fil
	# de deux verdicts de partie réelle (§8.140.1, §8.141) : c'est un nombre QUI BOUGE.
	var d: float = Geo.far_soldier_z() - Geo.near_soldier_z()
	var alpha := atan(DEMI_LARGEUR / d)
	var alpha_max := alpha + deg_to_rad(Geo.AIM_QUANTUM_DEG)
	# Inversion : quelle distance donnerait `alpha_max` ?
	var d_min := DEMI_LARGEUR / tan(alpha_max)
	return d - d_min


# ── LE DÉCALAGE DE HANCHE CUMULÉ ──────────────────────────────────────────────────────────────
# 🩸 C'EST LE POINT. Chez eux, **cinq couches écrivent dans `hipOff` sans se voir**, et rien ne
# borne la somme : mesuré **−0,514 m** (le brief d'origine disait −0,47 — il oubliait
# `hitAdd('legR', k=1.4)`). L'IK de pied, elle, EST bornée (`Math.max(-0.32*s, drop)`,
# `animator.js:467`) — mais elle **s'ajoute** au `hipOff`, d'où −0,83 m au total, hanches à 0,15 m.
#
# Chez nous l'accroupi n'est pas une amplitude d'animation : c'est `SILHOUETTE_TOP_DOWN = 1,05`,
# une entrée de la table angulaire serveur. La vue doit descendre **exactement** là, ni plus ni
# moins. Le débattement de hanche disponible est donc ce que la boîte laisse, pas ce que
# l'animation voudrait.
static func budget_hanche() -> float:
	return HAUT_DEBOUT - HAUT_ACCROUPI


# ── LA FLEXION RACHIDIENNE CUMULÉE ────────────────────────────────────────────────────────────
# ⚠️ Leur `_aimIk` **est** borné en angle (0,9 rad puis 0,35 rad) mais réparti sur `Spine`,
# `Spine1` et `Spine2` avec des poids qui **somment à 1,0** : soit **1,25 rad = 71,6° de flexion
# cumulée**. Ce qui n'est borné, c'est la POSITION résultante, et il n'y a aucune limite
# articulaire absolue. Vérifié : ça ne s'accumule pas d'image en image (la pose est reconstruite
# depuis le clip à chaque `reset()`), donc « en une seule image » est exact — et c'est le vrai
# risque : une cible qui téléporte fait sauter la tête de 58 cm **sans rampe**.
const FLEXION_RACHIS_MAX_DEG := 28.0
# ⚠️ Et une RAMPE, pas seulement un plafond : le pas de 0,9 rad par image doit devenir une vitesse.
const FLEXION_RACHIS_VITESSE_DEG_S := 220.0

# Cône de nuque + tête, en ABSOLU. Leur `_lookAt` n'a **aucune** limite articulaire : le seul
# plafond est un pas par image (« ~29 deg per bone per frame cap »), et mesuré, la tête se pose
# derrière l'épaule **et y reste**.
const REGARD_LACET_MAX_DEG := 70.0
const REGARD_TANGAGE_MAX_DEG := 35.0


# =================================================================================================
# APPLICATION
# =================================================================================================
# ⚠️ On BORNE, on ne met pas à l'échelle : mettre à l'échelle déformerait le geste entier pour un
# seul dépassement, alors que borner ne touche qu'à ce qui sort.

static func borner_hanche(offset: float) -> float:
	return clampf(offset, -budget_hanche(), 0.0)


static func borner_flexion_rachis(deg: float, precedent: float, dt: float) -> float:
	var plafonne := clampf(deg, -FLEXION_RACHIS_MAX_DEG, FLEXION_RACHIS_MAX_DEG)
	var pas := FLEXION_RACHIS_VITESSE_DEG_S * dt
	return clampf(plafonne, precedent - pas, precedent + pas)


static func borner_regard(lacet: float, tangage: float) -> Vector2:
	return Vector2(
		clampf(lacet, -REGARD_LACET_MAX_DEG, REGARD_LACET_MAX_DEG),
		clampf(tangage, -REGARD_TANGAGE_MAX_DEG, REGARD_TANGAGE_MAX_DEG))


# =================================================================================================
# VÉRIFICATION D'ENVELOPPE — ce que la sonde de silhouette §2.1 appelle
# =================================================================================================
# Rend la liste des violations, NOMMÉES. Un booléen dirait « ça sort » sans dire par où, et sur un
# balayage de plusieurs milliers de poses c'est la seule information utile.
#
# ⚠️ `z_reference` est le Z de la PLAQUE, celui que le serveur connaît. Les écarts se mesurent par
# rapport à lui, pas par rapport à l'origine du modèle.
# ╔═ ⚠️⚠️ CE QUE CE CONTRÔLE MESURE, APRÈS DEUX FORMULATIONS FAUSSES ════════════════════════════╗
# ║ **1ᵉʳ jet** : un budget de profondeur scalaire, appliqué uniformément à tous les points. Faux :║
# ║ ce budget a été dérivé pour un point AU BORD de la silhouette, là où un ΔZ produit la plus     ║
# ║ grande erreur. Près de l'axe, le même ΔZ ne déplace presque rien. La pose de REPOS « violait » ║
# ║ le budget, parce que le soldat tient son fusil devant lui.                                     ║
# ║                                                                                               ║
# ║ **2ᵉ jet** : l'erreur angulaire par point, plafonnée à un quantum de visée. Mieux, mais ça     ║
# ║ mesurait encore un DÉPLACEMENT, pas un MENSONGE. La main de soutien, à 43 cm devant le plan du ║
# ║ corps, produit **0,102°** — 2 % au-dessus du quantum — alors que la demi-fenêtre de tir fait   ║
# ║ 2,5° et la fenêtre verticale 3,7°. Ce déplacement-là ne peut faire rater AUCUN tir.            ║
# ║                                                                                               ║
# ║ **La bonne question est celle du §8.141.8**, verdict de partie réelle : « il faut que sa       ║
# ║ silhouette soit attaquable EN ENTIER ». Autrement dit : **tout ce que le joueur VOIT de        ║
# ║ l'ennemi doit tomber dans la fenêtre que le serveur sait toucher.** C'est vérifiable           ║
# ║ exactement, en degrés, et c'est la grandeur que le serveur manipule.                            ║
# ║                                                                                               ║
# ║ Ce qui avait motivé la borne reste vrai : `vault` (+0,66 m) et `_aimIk` (±0,58 m) sortent bel  ║
# ║ et bien de la fenêtre. Ils sont simplement attrapés par la BONNE mesure — celle qui distingue  ║
# ║ « ça bouge » de « ça ment ».                                                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
static func violations(points: Array, accroupi: bool, z_reference := 0.0) -> Array:
	var haut := HAUT_ACCROUPI if accroupi else HAUT_DEBOUT
	var d: float = Geo.far_soldier_z() - Geo.near_soldier_z()
	var oeil: float = Geo.EYE_UP
	# La fenêtre que le SERVEUR sait toucher, calculée depuis la plaque, en degrés. On y ajoute
	# un quantum de tolérance : en deçà, le serveur ne distingue rien de toute façon.
	var q: float = Geo.AIM_QUANTUM_DEG
	var fen_lacet := rad_to_deg(atan(DEMI_LARGEUR / d)) + q
	var fen_haut := rad_to_deg(atan((haut - oeil) / d)) + q
	var out := []
	for i in points.size():
		var p: Vector3 = points[i]
		# ── LE PLAFOND : il vaut pour TOUS les points, sans exception ────────────────────────
		# Accroupi, c'est même tout l'invariant : `SILHOUETTE_TOP_DOWN = 1,05` est **délibérément
		# sous le parapet**, et `crouched_is_covered()` plus un test de sabotage backend le gardent.
		if p.y > haut:
			out.append("point %d : sommet a %.3f m (plafond %.2f)" % [i, p.y, haut])
		# ── LE RESTE NE VAUT QUE DANS LA BANDE EXPOSÉE ──────────────────────────────────────
		# 🩸 Un jet précédent jugeait TOUS les os, orteils compris : 4 032 « violations » sur un
		# `ToeR` à 3 cm du sol, un os **derrière le parapet** dont le serveur n'a aucune fenêtre.
		# La géométrie le dit : « `SILHOUETTE_BOTTOM` = bas du torse (sous le parapet — c'est LUI
		# qui coupe) ». Mentir sur ce que le parapet cache n'est pas mentir.
		if p.y < BAS or p.y > haut:
			continue
		# Position APPARENTE du point, vue de l'œil, à sa profondeur RÉELLE.
		var dp: float = maxf(0.5, d - (p.z - z_reference))
		var vu_lacet := rad_to_deg(atan(p.x / dp))
		var vu_tangage := rad_to_deg(atan((p.y - oeil) / dp))
		if absf(vu_lacet) > fen_lacet:
			out.append("point %d : vu a %.3f deg de lacet, hors fenetre (+/- %.3f)"
				% [i, vu_lacet, fen_lacet])
		# ── ⚠️ LE BORD BAS NE PEUT PAS MENTIR, ET C'EST DÉMONTRABLE ─────────────────────────
		# La géométrie le dit déjà : « `SILHOUETTE_BOTTOM` = bas du torse (sous le parapet —
		# **c'est LUI qui coupe**, pas cette valeur) ». Vérifions-le en degrés, depuis l'œil :
		#   sommet du parapet adverse (y = 1,25) à z = 8,4 m  ->  tangage **−2,897°**
		#   bas de la fenêtre serveur (y = 1,15) à z = 9,5 m   ->  tangage **−3,148°**
		# Le parapet occulte donc **plus haut** que la fenêtre ne coupe : tout ce qui apparaît
		# sous −2,897° est CACHÉ dans l'image, fenêtre ou pas. Un point vu sous le bord bas n'est
		# pas « visible et intouchable » — il n'est pas visible du tout.
		#
		# 🩸 C'est ce qui a fait rougir 1 431 poses sur la main de soutien, vue à −3,258° contre un
		# bord à −3,248° : **1,7 mm à 10 m**, derrière des sacs de sable. Le mensonge ne peut venir
		# que du HAUT et des CÔTÉS, où rien n'occulte. On ne teste donc que ceux-là.
		# ⚠️ L'écart inverse existe et il est réel — entre −2,897° et −3,148° le serveur accepte des
		# touches sur une bande que le joueur ne voit pas. C'est le défaut le MOINS grave des deux
		# (on touche plus qu'on ne voit), il est **antérieur à ce lot**, et il appartient à la table
		# angulaire, pas à la vue. Signalé, pas corrigé ici.
		if vu_tangage > fen_haut:
			out.append("point %d : vu a %.3f deg de tangage, au-DESSUS de la fenetre (%.3f)"
				% [i, vu_tangage, fen_haut])
	return out
