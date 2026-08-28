extends RefCounted

# =================================================================================================
# §8.152 — LOT 3D-G, ÉTAGE 1 : LES 13 POSES DU SOLDAT ADVERSE
#
# Port de `src/ai/clips.js` (354 l.) de Claude-of-Duty.
#
# ╔═ CE QUE C'EST ═══════════════════════════════════════════════════════════════════════════════╗
# ║ Du CONTENU D'ANIMATION PUR. Treize fonctions, aucun état, aucune dépendance : ni squelette,   ║
# ║ ni nœud, ni horloge, ni `preload`. On leur passe un accumulateur (`Poser`) et une phase, elles║
# ║ y ajoutent des degrés. C'est pour ça que ce fichier est la tête de pont du portage : il se    ║
# ║ porte quasiment tel quel, et il est le seul du lot qu'on puisse relire ligne à ligne contre   ║
# ║ la référence.                                                                                 ║
# ║                                                                                               ║
# ║ « Poses are authored as **local euler deltas in degrees** on top of the bind pose. »          ║
# ║ Convention d'axes, identique pour TOUS les os (c'est ce qui rend une marche lisible comme de  ║
# ║ l'anatomie plutôt que « comme de la soupe de quaternions », dixit leur en-tête) :             ║
# ║                                                                                               ║
# ║     x  flexion  — positif fléchit l'os vers l'AVANT (le genou se tend, le rachis s'incurve)   ║
# ║     y  torsion  — roulis autour de la longueur propre de l'os                                 ║
# ║     z  latéral  — positif penche l'os vers la DROITE DU PERSONNAGE                            ║
# ║                                                                                               ║
# ║ ⚠️ « droite du personnage » = **X NÉGATIF** dans leur rig (`rig.js` : ClavicleR à x = −0,038, ║
# ║ épaule droite à −0,172). Les suffixes `R`/`L` des noms d'os sont la seule chose qui dit le    ║
# ║ côté ; le signe de X ne suit pas l'intuition. Ne jamais déduire un côté d'un signe ici.       ║
# ║                                                                                               ║
# ║ Les deltas s'ADDITIONNENT (plusieurs couches écrivent sur le même os), puis sont écrits EN    ║
# ║ UNE SEULE PASSE (cf. `compose_pose()`). Une couche ne lit jamais ce qu'une autre a écrit.     ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ CE QUI N'EST **PAS** ICI, ET NE DOIT PAS Y ENTRER ══════════════════════════════════════════╗
# ║ · les quatre IK (visée, regard, main d'appui, pieds)  → `animator.js`, lot suivant             ║
# ║ · le fondu enchaîné entre clips, les minuteries des coups uniques → idem                      ║
# ║ · le PLAFONNEMENT des amplitudes → `trench_soldier_bounds.gd` (étage 0, écrit AVANT celui-ci) ║
# ║   ⛔ Ce fichier ne borne RIEN, à dessein : des fonctions pures se relisent contre la référence.║
# ║   Il EXPOSE en revanche tout ce qu'il faut pour borner (§B ci-dessous).                        ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ INVENTAIRE VÉRIFIÉ — le brief donnait une table, je l'ai recomptée sur le CODE ═════════════╗
# ║ Colonne « os » = noms distincts écrits par `d()`. Le `hip()` est compté à part : c'est une    ║
# ║ TRANSLATION de la racine, pas une rotation d'os, et les confondre est justement ce qui a fait ║
# ║ perdre de vue le cumul du §B.                                                                 ║
# ║                                                                                               ║
# ║   clip                l. JS   durée / boucle              os        brief   verdict           ║
# ║   ──────────────────  ─────   ─────────────────────────   ───────   ─────   ────────────────  ║
# ║   idle                  33    boucle 0,19 Hz              17 +hip     17    ✅ (hip omis)      ║
# ║   walk                 151    max(0,55 ; v/1,42) Hz       17 +hip     22    ❌ écart de 5      ║
# ║   run                  155    max(1,1 ; v/2,05) Hz        18 +hip     23    ❌ écart de 5      ║
# ║   crouchWalk           161    max(0,4 ; v/0,95) Hz        17 +2×hip   23    ❌ écart de 6      ║
# ║   crouchIdle           168    boucle 0,19 Hz              13 +hip     14    ❌ (hip compté)    ║
# ║   hurtIdle             188    boucle 0,19 Hz              11 +hip     12    ❌ (hip compté)    ║
# ║   aimAdd                68    additif continu             16 +hip     17    ❌ (hip compté)    ║
# ║   suppressAdd          323    additif continu             10 +hip     10    ✅ (hip omis)      ║
# ║   recoilAdd            255    0,26 s, e = exp(−16t)        9           9    ✅                 ║
# ║   hitAdd('head')       278    0,5 s (mais cf. §A)          4           4    ✅                 ║
# ║   hitAdd('torso')      284    idem                         5 +hip      5    ✅                 ║
# ║   hitAdd('armR')       292    idem                         4          —     ⚠️ ABSENT du brief ║
# ║   hitAdd('armL')       298    idem                         4          —     ⚠️ ABSENT du brief ║
# ║   hitAdd('legR'/'legL')304    idem                         3 +hip      3    ✅                 ║
# ║   hitAdd(défaut)       316    idem                         2          —     ⚠️ ABSENT du brief ║
# ║   reloadAdd            343    2,35 s / 2,9 s               7           7    ✅                 ║
# ║   turnStep             209    0,42 s                       6 +hip      6    ✅                 ║
# ║   vault                226    0,80–0,85 s                 16 +hip     15    ❌ écart de 1      ║
# ║                                                                                               ║
# ║ Les six écarts sont sans conséquence sur le portage (aucune amplitude n'en dépend) mais ils   ║
# ║ sont notés parce qu'une table d'inventaire sert précisément à ne pas oublier un os. Détail :  ║
# ║ · `walk`/`run`/`crouchWalk` passent tous par `gait()`, qui écrit **17** os : UpLeg/Leg/Foot/   ║
# ║   Toe × 2 côtés (8) + Hips, Spine, Spine1, Spine2, Neck (5) + Clavicle × 2, UpperArm × 2 (4). ║
# ║   `run` ajoute `Head`, `crouchWalk` réécrit `Spine2` (déjà compté) ET rappelle `hip()`.       ║
# ║ · `vault` en écrit 16 (le brief en annonce 15) : Hips, Spine, Spine1, Spine2, Neck, UpLegR,   ║
# ║   LegR, FootR, UpLegL, LegL, FootL, ClavicleL, UpperArmL, ForearmL, ClavicleR, UpperArmR.     ║
# ║ · Le brief ne mentionne que 3 des **7** branches de `hitAdd`. Les quatre autres sont portées. ║
# ║ · « boucle » pour `crouchIdle`/`hurtIdle` : c'est **0,19 Hz**, comme `idle`. Chez eux ce taux ║
# ║   est le DÉFAUT de tout clip qui n'est pas walk/run/crouchWalk (`animator.js:237`), pas une   ║
# ║   propriété d'`idle`. Deux clips héritaient donc d'un « taux de respiration » sans le dire.   ║
# ║ · `reloadAdd` : 2,35 s / 2,9 s viennent d'`agent.js:758` (2,9 pour la variante `irregular`).  ║
# ║   ⚠️ `animator.js:109` porte un **troisième** chiffre, `reloadDur = 2.4`, qui n'est jamais    ║
# ║   utilisé par l'agent. Chez nous la durée est une DONNÉE SERVEUR (`reload_ticks`) : c'est un  ║
# ║   argument d'appel, sans défaut — même règle qu'au lot 3D-E (`trench_wclips.gd` §D.1).        ║
# ║ · `vault` : 0,8 s vient d'`agent.js:724`, 0,85 s est le défaut d'`animator.js:111`.           ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ §A — L'ENVELOPPE DE `hitAdd` NE VAUT PAS 1, ET SON AMPLITUDE DÉPEND DE LA MACHINE ══════════╗
# ║ `e(t) = exp(−7,5·t) · min(1 ; 22·t)` : une rampe linéaire de 45 ms qui coupe une exponentielle║
# ║ déjà entamée. Les deux ne se croisent pas à 1.                                                ║
# ║                                                                                               ║
# ║   pic ANALYTIQUE = **0,711 123 553**   à t = 1/22 s = 45,45 ms                                ║
# ║   (le brief annonçait 0,7109 : exact à 3 décimales, faux à la 4ᵉ — c'était une valeur         ║
# ║    échantillonnée, pas le maximum de la fonction.)                                            ║
# ║                                                                                               ║
# ║ Ce pic n'est JAMAIS atteint : il tombe entre deux images. Ce qui est réellement joué dépend   ║
# ║ donc de la fréquence d'échantillonnage — mesuré en balayant t = k/f :                         ║
# ║                                                                                               ║
# ║       f        pic échantillonné      écart au pic analytique                                 ║
# ║     144 Hz         0,694 486                 −2,3 %      (le brief disait 0,708 → ❌ FAUX)     ║
# ║     120 Hz         0,687 289                 −3,4 %                                           ║
# ║      90 Hz         0,700 608                 −1,5 %   ← plus haut qu'à 120 Hz : non monotone  ║
# ║      60 Hz         0,687 289                 −3,4 %      (brief 0,687 → ✅)                    ║
# ║      30 Hz         0,606 531                −14,7 %      (brief 0,606 → ✅)                    ║
# ║      20 Hz         0,687 289                 −3,4 %   ← NOUS                                  ║
# ║                                                                                               ║
# ║ ⚠️ La non-monotonie (90 Hz tape plus fort que 120 Hz) montre que ce n'est pas « plus d'images ║
# ║ = plus fidèle » : c'est une LOTERIE sur l'endroit où l'échantillon tombe. Deux joueurs ne     ║
# ║ voient pas la même réaction au coup, et le même joueur n'en voit pas deux identiques si son   ║
# ║ `dt` varie.                                                                                   ║
# ║                                                                                               ║
# ║ ⇒ RÈGLE DE CE FICHIER : toutes les fonctions à coup unique prennent `t` en argument et n'ont  ║
# ║ AUCUNE mémoire. Elles sont donc échantillonnables sur n'importe quelle horloge — et la nôtre  ║
# ║ est **fixe, à 20 Hz** (`SIM_DT`). `t = tick × 0,05` : le pic vaut alors exactement            ║
# ║ exp(−0,375) = 0,687 289 279, sur toutes les machines, pour toujours. Un `dt` d'image accumulé ║
# ║ ferait rentrer la loterie par la fenêtre : `tick_seconds()` existe pour ne pas avoir à y      ║
# ║ penser.                                                                                       ║
# ║                                                                                               ║
# ║ ⚠️ CE QUE LE PAS DE 50 ms COÛTE PAR AILLEURS (mesuré, à traiter par la couche d'au-dessus) :  ║
# ║  1. `turnStep` dure 0,42 s = **8,4 pas**. Le dernier échantillon tombe à t = 0,40/0,42, où    ║
# ║     l'enveloppe sin(π·t) vaut encore **0,149**. Le pas suivant, le clip a disparu : la cuisse ║
# ║     saute de 1,8° et le genou de 5,1° EN UNE IMAGE. C'est le seul claquement visible du lot.  ║
# ║     Correctif (couche animateur, pas ici) : caler la durée sur un nombre ENTIER de pas —      ║
# ║     0,40 s (8 pas) ou 0,45 s (9 pas). Les autres durées tombent juste : 0,8 s = 16 pas,       ║
# ║     0,85 s = 17, 2,35 s = 47, 2,9 s = 58.                                                     ║
# ║  2. `hitAdd` est coupé net à t > 0,5 s alors que e(0,5) = 0,0235 : résidu de 2,4 % tranché    ║
# ║     (soit 0,47° sur `Head`). Négligeable, mais c'est le même défaut, en plus petit.           ║
# ║  3. `recoilAdd` : coupé à t > 0,26 s, e(0,25) = 0,0183 → 1,8 % tranché. Idem.                 ║
# ║  4. 🩸 `recoilAdd` contient `sin(92·t)`, soit **14,64 Hz**. À 20 Hz, Nyquist est à 10 Hz :    ║
# ║     l'oscillation est **REPLIÉE**. Échantillonnée, elle donne 0 / −0,994 / +0,223 / +0,944 /  ║
# ║     −0,435 / −0,846 : un battement apparent à 5,36 Hz, EN SENS INVERSE du ressort voulu.      ║
# ║     Ce n'est pas une perte de qualité, c'est un mouvement DIFFÉRENT. Deux issues, aucune      ║
# ║     gratuite, à trancher à l'étage animateur :                                                ║
# ║       (a) garder 20 Hz : le tremblement de recul devient un flottement lent. Déterministe.    ║
# ║       (b) échantillonner `recoil_add()` sur l'horloge de RENDU (la fonction est pure, c'est   ║
# ║           licite) : le geste est juste, mais on réintroduit une dépendance machine dans ce    ║
# ║           que le joueur voit — exactement ce que §A cherche à éliminer.                        ║
# ║     Le recul n'écarte la tête que de −0,056 m en Z (elle RECULE, elle ne s'approche pas), donc║
# ║     aucune des deux options ne menace le budget de profondeur de l'étage 0.                   ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ §B — `hipOff` N'EST BORNÉ NULLE PART : CINQ COUCHES Y ÉCRIVENT SANS SE VOIR ════════════════╗
# ║ Chez eux `Poser.hipOff` est un simple `Vector3` cumulatif. Aucune couche ne sait ce que les   ║
# ║ autres y ont mis, et rien ne plafonne la somme. Pire cas, reconstruit terme à terme :         ║
# ║                                                                                               ║
# ║     crouchIdle  −0,315 + 0,004·respiration            −0,319 000                              ║
# ║     aimAdd      −0,035 · w            (w = 1)         −0,035 000    cumul −0,354              ║
# ║     suppressAdd −0,100 · w            (w = 1)         −0,100 000    cumul −0,454              ║
# ║     hitAdd('legR') −0,05 · k    (k = 1,4 × pic e)     −0,048 110    cumul −0,502              ║
# ║     turnStep    −0,012 · e            (e = 1)         −0,012 000    cumul **−0,514 110**      ║
# ║                                                                                               ║
# ║ ✅ Le −0,514 du brief est CONFIRMÉ au millimètre — et je peux dire pourquoi : il a été mesuré ║
# ║ sur une horloge à 20 Hz (pic 0,687289). Avec le pic analytique 0,711124 la somme donnerait    ║
# ║ −0,515 8. L'ancien chiffre −0,47 oubliait bien `hitAdd('legR')`, dont la force monte à 1,4    ║
# ║ (`agent.js:835` : `Math.min(1.4, 0.5 + amount / 45)`).                                        ║
# ║                                                                                               ║
# ║ ⚠️ Et l'IK de pied AJOUTE encore −0,32 m par-dessus (elle, bornée : `animator.js:467`) : les  ║
# ║ hanches finissent à 0,15 m du sol. Cf. `trench_soldier_bounds.gd`, qui chiffre −0,83 m.       ║
# ║                                                                                               ║
# ║ ⇒ CE FICHIER NE BORNE RIEN (les fonctions restent pures et relisibles). Il rend le problème   ║
# ║ VISIBLE : **chaque fonction renvoie sa propre contribution de hanche**, en mètres, déjà       ║
# ║ pondérée par `P.w`. Une couche supérieure peut donc attribuer, sommer, puis plafonner avec    ║
# ║ `TrenchSoldierBounds.borner_hanche()`. Les fonctions qui ne touchent pas la hanche renvoient  ║
# ║ `Vector3.ZERO` — un zéro explicite, pas un `null` à tester.                                   ║
# ║ 🩸 Le `Poser` accumule AUSSI dans `hip_off` (il le faut pour le fondu enchaîné). La valeur de ║
# ║ retour n'est donc pas un doublon : c'est la seule qui dise QUI a poussé, et de combien.       ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ §C — ORDRE D'EULER : LEUR 'XYZ' N'EST PAS LE DÉFAUT DE GODOT ═══════════════════════════════╗
# ║ `animator.js:311` écrit la pose avec `e.set(x, y, z, 'XYZ')`, ce qui compose **Rx·Ry·Rz**.   ║
# ║ Godot, lui, compose en **YXZ** par défaut — `Basis.from_euler()`, `Quaternion.from_euler()`,  ║
# ║ `Node3D.rotation`, `Node3D.rotation_order` : tous YXZ, donc **Ry·Rx·Rz**.                     ║
# ║                                                                                               ║
# ║ Sous YXZ la rotation autour de X est préservée, mais Y et Z changent de rôle : les os à un    ║
# ║ SEUL axe non nul (tous les genoux, tous les orteils) sont identiques dans les deux ordres, et ║
# ║ ceux à deux ou trois axes divergent. Mesuré, sur des poses réelles du fichier :               ║
# ║                                                                                               ║
# ║     Head,   hitAdd('head') (−20 ; 14 ; 8)   → **4,85°** d'écart   (≈ 21 mm au sommet du crâne)║
# ║     Spine2, vault          (8 ; −14 ; 0)    →   1,95°                                         ║
# ║     Spine2, reloadAdd      (4 ; −16 ; −3)   →   1,11°                                         ║
# ║     Spine2, aimAdd         (3 ; −5 ; 0)     →   0,26°                                         ║
# ║     Hips,   idle           (−1,5 ; 2,2 ; 1,6) → 0,06°                                         ║
# ║                                                                                               ║
# ║ ⚠️ 4,85° sur la nuque, c'est **48 quanta de visée** (`AIM_QUANTUM_DEG = 0,1°`). Et le défaut  ║
# ║ serait SILENCIEUX : la pose resterait plausible, simplement fausse — le pire cas possible ici.║
# ║ Les petites poses (0,06°) sont le vrai piège : elles laissent croire que « ça se voit pas ».  ║
# ║                                                                                               ║
# ║ ⇒ `quat_xyz()` compose explicitement qx·qy·qz. On l'utilise PARTOUT. On ne laisse jamais le   ║
# ║ défaut de Godot décider — pas même pour un os à un seul axe, où il se trouve avoir raison.    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ §D — `vault` EST PORTÉ MAIS **NON UTILISÉ** ════════════════════════════════════════════════╗
# ║ Notre joueur et notre adversaire sont confinés dans une TRANCHÉE : il n'y a rien à franchir.  ║
# ║ Aucun état serveur ne peut déclencher un franchissement, et aucun ne le fera.                 ║
# ║ Il est porté quand même — il figure à l'inventaire, et un trou dans un port fidèle se paie    ║
# ║ plus tard — mais il est marqué, et le rester.                                                 ║
# ║                                                                                               ║
# ║ ⛔ SI QUELQU'UN LE BRANCHE UN JOUR : le clip lui-même monte `HeadTop` de **+0,662 m** en Z, et ║
# ║ la RACINE ajoute **+0,42 m** en vertical par-dessus (`agent.js:937` :                         ║
# ║ `this.position.y += Math.sin(t * Math.PI) * 0.42`). Ces deux-là ne se voient pas : le clip est ║
# ║ dans `clips.js`, la racine dans `agent.js`, et rien ne les additionne nulle part. Le sommet   ║
# ║ du crâne sort alors de la boîte serveur par le haut ET par la profondeur, simultanément.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝


# =================================================================================================
# 0. HORLOGE FIXE ET CONSTANTES MESURÉES  (cf. §A)
# =================================================================================================

## Notre simulation tourne à 20 Hz. Ce n'est pas un réglage d'affichage : c'est la cadence à
## laquelle le serveur pense, et donc la seule cadence sur laquelle une pose vue par le joueur
## puisse être identique chez lui et chez nous.
const SIM_HZ := 20.0
const SIM_DT := 0.05

## Enveloppe de `hitAdd` : `exp(−TAU_COUP·t) · min(1 ; RAMPE_COUP·t)`.
const HIT_ENV_TAU := 7.5
const HIT_ENV_RAMPE := 22.0

## Pic ANALYTIQUE, atteint à t = 1/22 s. Jamais joué tel quel : il tombe entre deux échantillons.
const HIT_ENV_PIC := 0.7111235529
const HIT_ENV_PIC_T := 0.0454545455

## Pic réellement joué sur NOTRE horloge : e(0,05) = exp(−0,375), à l'échantillon n° 1.
const HIT_ENV_PIC_20HZ := 0.6872892788

## Gain optionnel pour que le pic ÉCHANTILLONNÉ à 20 Hz vaille exactement `force` : exp(+0,375).
## ⚠️ Non appliqué par défaut — ce serait s'écarter de la référence. Et si on l'applique, le pire
## cas de hanche du §B se creuse de 1,5 mm supplémentaire (−0,5156 au lieu de −0,5141).
const HIT_ENV_GAIN_20HZ := 1.4549914146

## Recul : `sin(92·t)`, soit 14,642 Hz — au-dessus de Nyquist (10 Hz) à 20 Hz. Repli à 5,358 Hz,
## en sens inverse. Cf. §A.4.
const RECUL_OSC_RAD_S := 92.0
const RECUL_OSC_HZ := 14.6423
const RECUL_ALIAS_20HZ_HZ := 5.3577

## Fenêtres de vie des coups uniques, en secondes, telles qu'écrites dans la référence.
## ⚠️ `hitAdd` porte TROIS durées contradictoires chez eux : la garde du clip dit 0,5 s
## (`clips.js:273`), son propre commentaire dit « 0.45 s long » (`clips.js:271`), et l'animateur
## retire la minuterie à 0,55 s (`animator.js:267`). C'est la GARDE qui fait foi : au-delà, la
## fonction ne pose rien. Les deux autres chiffres sont du commentaire mort.
const RECUL_DUREE := 0.26
const COUP_DUREE := 0.5
const PAS_TOURNANT_DUREE := 0.42

## Cumul de hanche du §B. `MESURE` = mesuré sur horloge 20 Hz (identique au brief au mm près) ;
## `ANALYTIQUE` = même somme avec le pic exact de l'enveloppe.
const HANCHE_CUMUL_MESURE_M := -0.514110
const HANCHE_CUMUL_ANALYTIQUE_M := -0.515779

## ⛔ LA LISTE DES OS N'EST **PAS** ICI, ET NE DOIT JAMAIS Y REVENIR.
## Elle fait autorité dans `trench_soldier_rig.gd` (`const BONES`, `bone_index()`), qui porte aussi
## les positions de repos et les contrôles de cohérence. Un premier jet de ce fichier en recopiait
## les 25 noms « pour la commodité » : c'est exactement le patron du §8.148 — deux listes qui se
## ressemblent jusqu'au jour où l'une bouge, et le désaccord ne se voit que sur un os immobile.
##
## Le `Poser` reçoit donc le filtre de noms en argument de construction, et c'est l'appelant qui le
## dérive du rig. Utile parce que chez eux un nom d'os inconnu est ignoré EN SILENCE
## (`animator.js:53`) : une faute de frappe y devient un os qui ne bouge jamais, sans un mot.
## Cf. `Poser.refuses`, qui les enregistre au lieu de les avaler.
##
## Ce fichier ne fait AUCUN `preload` : c'est du contenu pur, il se charge et se relit seul.

## Les six clips de locomotion — ceux qui bouclent sur une phase. `CLIPS` chez eux (`clips.js:354`)
## n'en exporte que six : les additifs et les coups uniques ne sont pas des états de base.
const CLIPS_LOCOMOTION := ["idle", "walk", "run", "crouchWalk", "crouchIdle", "hurtIdle"]


# =================================================================================================
# 1. L'ACCUMULATEUR DE POSE
# =================================================================================================
# Port de la classe `Poser` (`animator.js:33-66`).
#
# ⚠️ Elle est volontairement SANS AUCUNE dépendance vers le reste de ce script : une classe interne
# GDScript ne voit ni les constantes, ni les fonctions statiques, ni les `preload` du script qui la
# contient. Plutôt que de dupliquer `quat_xyz()` ici, on ne l'y appelle pas du tout — la conversion
# degrés → quaternion est faite au niveau module par `compose_pose()`. Une duplication de la règle
# du §C serait exactement le genre de seconde source de vérité qui diverge en silence.
class Poser extends RefCounted:

	## Nom d'os → delta d'Euler cumulé, EN DEGRÉS. Convention x = flexion, y = torsion, z = latéral.
	var deltas: Dictionary = {}

	## Translation de la racine (Hips), EN MÈTRES. Cumulée par toutes les couches — cf. §B.
	var hip_off: Vector3 = Vector3.ZERO

	## Poids de la couche en cours d'écriture. La référence le fixe autour de chaque appel de clip
	## pour réaliser le fondu enchaîné (`animator.js:245-253`). Il multiplie AUSSI la hanche.
	var w: float = 1.0

	## Noms refusés parce qu'absents du rig. Vide = tout est accepté (aucun filtre fourni).
	## 🩸 C'est la seule divergence de comportement de cette classe : chez eux un os inconnu
	## disparaît sans trace. Ici il est enregistré, pour qu'une sonde puisse le lire. On ne lève
	## RIEN (pas d'`assert` : un `assert` raté fait BLOQUER Godot en headless, cf. mémoire projet).
	var refuses: Array = []

	var _os_connus: Dictionary = {}

	## `os_connus` vide → aucun filtrage. Sinon, seuls ces noms sont acceptés.
	func _init(os_connus: Array = []) -> void:
		for n in os_connus:
			_os_connus[n] = true

	func reset() -> void:
		deltas.clear()
		hip_off = Vector3.ZERO
		w = 1.0
		refuses.clear()

	## Delta d'Euler ADDITIF, en degrés, pondéré par `w`.
	func d(nom: String, x: float, y: float, z: float) -> void:
		if not _os_connus.is_empty() and not _os_connus.has(nom):
			if not refuses.has(nom):
				refuses.append(nom)
			return
		var courant: Vector3 = deltas.get(nom, Vector3.ZERO)
		deltas[nom] = courant + Vector3(x, y, z) * w

	## Translation de la racine, pondérée par `w`. Renvoie CE QU'ELLE VIENT D'AJOUTER (§B) :
	## c'est cette valeur que les clips propagent vers leur appelant.
	func hip(dx: float, dy: float, dz: float) -> Vector3:
		var apport := Vector3(dx, dy, dz) * w
		hip_off += apport
		return apport

	## Delta cumulé d'un os, en degrés. `Vector3.ZERO` si l'os n'a pas été touché.
	## ⚠️ `Dictionary.get()` rend un Variant : on le retype AVANT de le rendre, sinon la valeur
	## traverse une signature `-> Vector3` sans que rien ne la vérifie à la compilation.
	func delta(nom: String) -> Vector3:
		var v: Vector3 = deltas.get(nom, Vector3.ZERO)
		return v

	## Noms d'os effectivement écrits, triés — pour une sonde ou une capture de non-régression.
	func os_ecrits() -> Array:
		var noms := deltas.keys()
		noms.sort()
		return noms


# =================================================================================================
# 2. L'ÉCRITURE DE LA POSE — ordre 'XYZ' EXPLICITE  (cf. §C)
# =================================================================================================

## Compose Rx·Ry·Rz, comme `THREE.Euler(x, y, z, 'XYZ')`. **JAMAIS** `Quaternion.from_euler()`,
## qui compose Ry·Rx·Rz et se trompe silencieusement de 4,85° sur la nuque d'un soldat touché.
##
## Les axes sont ceux de l'os, pas ceux du monde : on les écrit en dur plutôt que d'utiliser
## `Vector3.RIGHT`/`UP`/`BACK`, dont les noms parlent d'un repère de scène et induiraient en erreur
## (« BACK » vaut (0,0,1), « FORWARD » vaut (0,0,−1) : une chance sur deux de se tromper de signe).
static func quat_xyz(euler_deg: Vector3) -> Quaternion:
	var qx := Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(euler_deg.x))
	var qy := Quaternion(Vector3(0.0, 1.0, 0.0), deg_to_rad(euler_deg.y))
	var qz := Quaternion(Vector3(0.0, 0.0, 1.0), deg_to_rad(euler_deg.z))
	return qx * qy * qz


## Toutes les couches sont empilées : on convertit EN UNE PASSE. Renvoie nom d'os → `Quaternion`
## local additif, à multiplier par la rotation de repos de l'os (`b.quaternion = bind * q`, cf.
## `animator.js:313`). Les os non touchés sont absents : ils gardent leur pose de repos.
static func compose_pose(p: Poser) -> Dictionary:
	var out := {}
	for nom in p.deltas:
		var deg: Vector3 = p.deltas[nom]
		out[nom] = quat_xyz(deg)
	return out


# =================================================================================================
# 3. HORLOGE ET ENVELOPPES  (cf. §A)
# =================================================================================================

## Convertit un numéro de pas de simulation en secondes. Les coups uniques DOIVENT être pilotés
## par un compteur entier de pas, jamais par un `dt` d'image accumulé : c'est ce qui rend la pose
## identique sur toutes les machines.
static func tick_seconds(tick: int) -> float:
	return float(tick) * SIM_DT


## Enveloppe des réactions au coup : montée linéaire de 45 ms, retombée exponentielle.
## Culmine à `HIT_ENV_PIC` (0,711 124) à t = 1/22 s, et à `HIT_ENV_PIC_20HZ` (0,687 289) sur
## notre horloge. Rend 0 au-delà de la garde du clip.
static func hit_envelope(t: float) -> float:
	if t < 0.0 or t > COUP_DUREE:
		return 0.0
	return exp(-HIT_ENV_TAU * t) * minf(1.0, HIT_ENV_RAMPE * t)


## Enveloppe du recul : pointe rapide, retour ressort. `exp(−16·t)`, garde à 0,26 s.
static func recoil_envelope(t: float) -> float:
	if t < 0.0 or t > RECUL_DUREE:
		return 0.0
	return exp(-t * 16.0)


## « smooth positive lobe used for knee/ankle curves » — le lobe positif des courbes de genou et de
## cheville. Négatif → 0 : c'est ce qui donne une flexion QUI NE REPART PAS en arrière.
static func _lobe(x: float, k := 1.4) -> float:
	var s := sin(x)
	if s <= 0.0:
		return 0.0
	return pow(s, k)


# =================================================================================================
# 4. POSTURE DE BASE
# =================================================================================================

## « Weight on the left leg, knees soft, weapon at low ready. »
## Boucle sur `ph` ∈ [0;1[, avancée à 0,19 Hz (une respiration toutes les 5,26 s).
## Renvoie la contribution de hanche (§B).
##
## Trois oscillateurs incommensurables (0,55 / 0,31 / 1,7 et 2,9) : leurs périodes ne retombent
## jamais en phase, ce qui empêche l'œil de repérer la boucle. C'est le seul truc du clip.
static func idle(p: Poser, ph: float) -> Vector3:
	var t := ph * TAU
	var breath := sin(t * 0.55)
	var sway := sin(t * 0.31 + 1.1)
	var micro := sin(t * 1.7 + 0.4) * 0.35 + sin(t * 2.9) * 0.2

	var dh := p.hip(0.012 * sway, -0.008 + 0.004 * breath, 0.0)
	p.d("Hips", -1.5, 2.2 * sway, 1.6)
	p.d("Spine", 1.6 + 0.7 * breath, -1.4 * sway, -0.8)
	p.d("Spine1", 1.2 + 0.9 * breath, -1.0 * sway, -0.6)
	p.d("Spine2", -0.6 + 1.1 * breath, 1.6 * sway, 0.4)
	p.d("Neck", 1.0 - 0.5 * breath, 1.2 * sway + micro, 0.0)
	p.d("Head", -1.2, 1.0 * micro, 0.6 * sway)

	# « stance: right leg carries, left slightly forward »
	# L'asymétrie est le sujet : deux jambes identiques donnent un mannequin, pas un homme debout.
	p.d("UpLegR", -2.0, 1.5, -1.5)
	p.d("LegR", -5.5, 0.0, 0.0)
	p.d("FootR", 4.5, -1.5, 0.0)
	p.d("UpLegL", 5.0, -4.5, 2.5)
	p.d("LegL", -9.0, 0.0, 0.0)
	p.d("FootL", 5.5, 3.0, 0.0)

	# « shoulders settle, weapon rides the breath » — l'arme est tenue par les épaules, donc c'est
	# aux clavicules de porter la respiration ; la faire porter par les bras la ferait flotter.
	p.d("ClavicleR", -1.5 + 0.8 * breath, 0.0, 1.2)
	p.d("ClavicleL", -1.0 + 0.6 * breath, 0.0, -1.0)
	p.d("UpperArmR", -3.0, 0.0, 2.0)
	p.d("UpperArmL", 2.0, 0.0, -2.0)
	p.d("ForearmR", 2.0, 0.0, 0.0)
	return dh


## « Stock in the shoulder, head over the sights, weight forward on bent knees. Additive over any
## base — this is what turns a standing mannequin into a man in a gunfight. »
##
## ADDITIF ET CONTINU : pas de durée, pas de phase. `w` est le poids de visée (0 = arme basse,
## 1 = en joue), et il multiplie TOUT, y compris les −0,035 m de hanche. Renvoie cette hanche (§B).
##
## ⚠️ Chez eux ce poids est réduit de 60 % pendant un rechargement (`animator.js:257`) : la crosse
## quitte l'épaule quand la main gauche part chercher un chargeur. Ce couplage est une décision
## d'ANIMATEUR, pas de contenu : il n'est pas porté ici, il appartient au lot suivant.
static func aim_add(p: Poser, w := 1.0) -> Vector3:
	# « fighting stance: knees soft, hips dropped, feet staggered »
	var dh := p.hip(0.0, -0.035 * w, 0.012 * w)
	p.d("Hips", 4.0 * w, 3.0 * w, 0.0)
	p.d("UpLegR", 8.0 * w, 4.0 * w, -3.0 * w)
	p.d("LegR", -17.0 * w, 0.0, 0.0)
	p.d("FootR", 9.0 * w, -2.0 * w, 0.0)
	p.d("UpLegL", 3.0 * w, -6.0 * w, 4.0 * w)
	p.d("LegL", -13.0 * w, 0.0, 0.0)
	p.d("FootL", 8.0 * w, 3.0 * w, 0.0)
	p.d("Spine1", 2.5 * w, 0.0, 0.0)
	p.d("Spine2", 3.0 * w, -5.0 * w, 0.0)
	p.d("Neck", 5.0 * w, 3.0 * w, 0.0)
	p.d("Head", -3.5 * w, 2.0 * w, -1.5 * w)
	p.d("ClavicleR", -6.0 * w, -2.0 * w, 5.0 * w)
	p.d("ClavicleL", -3.0 * w, 4.0 * w, -3.0 * w)
	p.d("UpperArmR", 10.0 * w, 0.0, 14.0 * w)
	p.d("ForearmR", -12.0 * w, 0.0, 0.0)
	p.d("UpperArmL", 8.0 * w, 0.0, -6.0 * w)
	# ⚠️ 16 os, pas 17 : `Spine` n'est PAS touché par la visée (la flexion part de Spine1). Le
	# brief comptait 17 parce qu'il ajoutait la hanche à la colonne « os ».
	return dh


# =================================================================================================
# 5. LOCOMOTION
# =================================================================================================
# « Locomotion curves are hand-tuned against reference gait: the knee flexes hardest just after
# toe-off, the pelvis drops through mid-stance and rolls toward the stance leg, and the spine
# counter-rotates against the pelvis. »
#
# Les trois allures partagent UNE fonction et ne diffèrent que par 19 nombres. C'est ce qui rend
# la marche et la course cohérentes entre elles : ce sont littéralement la même démarche, jouée
# plus fort. Les tables gardent les noms de clés de la référence (en anglais) pour rester
# diffables ligne à ligne — les renommer aurait rendu toute relecture croisée impossible.

const WALK := {
	"thigh": 21.0, "thighBias": -2.0, "thighTwist": 1.5, "splay": 1.5,
	"kneeBase": 7.0, "knee": 46.0, "kneeStance": 8.0,
	"ankle": 12.0, "ankleBias": 2.0, "toe": 16.0,
	"sway": 0.014, "bob": 0.014, "bobBias": -0.014,
	"pelvisTilt": -1.0, "pelvisYaw": 4.5, "pelvisRoll": 3.2,
	"lean": 4.0, "spineYaw": 3.4, "armSwing": 3.5,
}

const RUN := {
	"thigh": 34.0, "thighBias": 2.0, "thighTwist": 2.0, "splay": 2.0,
	"kneeBase": 14.0, "knee": 86.0, "kneeStance": 22.0,
	"ankle": 20.0, "ankleBias": 4.0, "toe": 26.0,
	"sway": 0.02, "bob": 0.03, "bobBias": -0.03,
	"pelvisTilt": -3.0, "pelvisYaw": 7.0, "pelvisRoll": 5.0,
	"lean": 13.0, "spineYaw": 6.0, "armSwing": 7.0,
}

const CROUCH := {
	"thigh": 13.0, "thighBias": 38.0, "thighTwist": 2.0, "splay": 4.0,
	"kneeBase": 74.0, "knee": 26.0, "kneeStance": 6.0,
	"ankle": 8.0, "ankleBias": 26.0, "toe": 8.0,
	"sway": 0.01, "bob": 0.008, "bobBias": -0.008,
	"pelvisTilt": 6.0, "pelvisYaw": 3.0, "pelvisRoll": 2.0,
	"lean": 16.0, "spineYaw": 2.4, "armSwing": 2.0,
}


## Le cycle de marche commun. `ph` ∈ [0;1[ = une foulée complète (les DEUX jambes).
## Écrit 17 os + la hanche. Renvoie la contribution de hanche (§B).
##
## ⚠️ Les valeurs sont extraites en locaux TYPÉS : `k["thigh"]` est un Variant, et `:=` échoue sur
## un Variant en GDScript strict. Chaque ligne porte donc son type — et, tant qu'à faire, ce que
## le paramètre veut dire.
static func _gait(p: Poser, ph: float, k: Dictionary) -> Vector3:
	var thigh: float = k["thigh"]              # amplitude du balancement de cuisse (deg)
	var thigh_bias: float = k["thighBias"]     # décalage constant : négatif = jambe en arrière
	var thigh_twist: float = k["thighTwist"]   # rotation interne/externe de la cuisse
	var splay: float = k["splay"]              # écartement latéral des jambes
	var knee_base: float = k["kneeBase"]       # flexion de genou permanente (jamais tendu à fond)
	var knee_amp: float = k["knee"]            # pic de flexion juste après le décollement d'orteil
	var knee_stance: float = k["kneeStance"]   # flexion résiduelle pendant l'appui
	var ankle: float = k["ankle"]              # amplitude de la cheville
	var ankle_bias: float = k["ankleBias"]     # cheville au repos (26° accroupi : le pied est plié)
	var toe: float = k["toe"]                  # poussée d'orteil
	var sway: float = k["sway"]                # balancement latéral du bassin (m)
	var bob: float = k["bob"]                  # oscillation verticale du bassin (m)
	var bob_bias: float = k["bobBias"]         # affaissement moyen du bassin (m, toujours ≤ 0)
	var pelvis_tilt: float = k["pelvisTilt"]   # bascule avant/arrière du bassin
	var pelvis_yaw: float = k["pelvisYaw"]     # lacet du bassin (le bassin tourne avec la jambe)
	var pelvis_roll: float = k["pelvisRoll"]   # roulis vers la jambe d'appui
	var lean: float = k["lean"]                # inclinaison avant du buste (13° en course)
	var spine_yaw: float = k["spineYaw"]       # contre-rotation du rachis, opposée au bassin
	var arm_swing: float = k["armSwing"]       # balancement des bras — porté par les clavicules

	var t := ph * TAU
	# ⚠️ `sv` est un Variant (élément de tableau) : on le retype AVANT de s'en servir, sinon chaque
	# `side * …` se propage en Variant jusque dans les arguments `float` de `d()`.
	for sv in [1.0, -1.0]:
		var side: float = sv
		var s := "R" if side > 0.0 else "L"
		# « legs half a cycle apart » : une jambe est toujours à l'opposé de l'autre.
		var o := 0.0 if side > 0.0 else PI
		var a := t + o
		# « thigh: swings forward through the air, back through stance »
		var f_thigh := thigh * sin(a) + thigh_bias
		# « knee: heavy flexion just after toe-off, small at heel strike »
		# Deux lobes désaxés (−0,55 rad et +π+0,4 rad) : le grand pour la phase aérienne, le petit
		# pour l'amorti d'appui. Le tout est NÉGATIF — chez eux, fléchir un genou baisse le X.
		var f_knee := -(knee_base + knee_amp * _lobe(a - 0.55, 1.5) + knee_stance * _lobe(a + PI + 0.4, 2.0))
		# « ankle: toe-off push then dorsiflexion to clear the ground »
		var f_ankle := ankle * sin(a - 1.9) + ankle_bias
		p.d("UpLeg" + s, f_thigh, side * thigh_twist, side * splay)
		p.d("Leg" + s, f_knee, 0.0, 0.0)
		p.d("Foot" + s, f_ankle, -side * 1.5, 0.0)
		# L'orteil ne fléchit que dans UN sens : `max(0, …)` coupe la moitié négative de la
		# sinusoïde. Sans ce plancher, l'orteil se relèverait pendant l'appui — impossible.
		p.d("Toe" + s, maxf(0.0, -toe * sin(a - 2.6)), 0.0, 0.0)

	# « pelvis: two bobs per stride, roll toward the stance leg, counter-yaw »
	# ⚠️ DEUX rebonds par foulée (`cos(2t)`), un par appui. Un seul rebond donnerait un boitement.
	var dh := p.hip(sway * sin(t), bob_bias + bob * cos(2.0 * t), 0.0)
	p.d("Hips", pelvis_tilt, pelvis_yaw * sin(t), pelvis_roll * sin(t + 1.2))
	# La contre-rotation : le rachis annule progressivement le lacet du bassin en montant
	# (0,45 → 0,75 → 1,0), pour que les épaules restent face à la marche. Signes opposés au bassin.
	p.d("Spine", lean * 0.35, -spine_yaw * 0.45 * sin(t), -pelvis_roll * 0.35 * sin(t + 1.2))
	p.d("Spine1", lean * 0.35, -spine_yaw * 0.75 * sin(t), 0.0)
	p.d("Spine2", lean * 0.3, -spine_yaw * sin(t), 0.0)
	p.d("Neck", -lean * 0.5, spine_yaw * 0.6 * sin(t), 0.0)
	# « the rifle rides on the shoulders, so they take the bounce »
	p.d("ClavicleR", -arm_swing * sin(t) - 1.0, 0.0, 1.5)
	p.d("ClavicleL", arm_swing * sin(t) - 1.0, 0.0, -1.5)
	p.d("UpperArmR", -arm_swing * 0.6 * sin(t), 0.0, 2.0)
	p.d("UpperArmL", arm_swing * 0.8 * sin(t), 0.0, -2.0)
	return dh


## Marche. Fréquence de foulée : `max(0,55 ; vitesse / 1,42)` Hz (`animator.js:235`).
## Le diviseur EST la longueur de foulée : c'est lui qui empêche les pieds de patiner.
static func walk(p: Poser, ph: float) -> Vector3:
	return _gait(p, ph, WALK)


## Course. Fréquence : `max(1,1 ; vitesse / 2,05)` Hz. Déclenchée au-dessus de 2,6 m/s
## (`agent.js:948`).
static func run(p: Poser, ph: float) -> Vector3:
	var dh := _gait(p, ph, RUN)
	# « head stabilises against the bigger bounce » : la tête ne subit pas le rebond, elle le
	# compense. 18ᵉ os — le seul que la course ajoute à la marche.
	p.d("Head", -3.0, 0.0, 0.0)
	return dh


## Marche accroupie. Fréquence : `max(0,4 ; vitesse / 0,95)` Hz — foulée deux fois plus courte
## qu'en course, donc jambes deux fois plus rapides à vitesse égale.
##
## ⚠️ APPELLE `hip()` DEUX FOIS : une fois dans `_gait` (rebond), une fois ici (−0,30 m
## d'accroupissement). La valeur renvoyée est la SOMME des deux — c'est précisément le genre de
## double écriture que le §B rend visible.
static func crouch_walk(p: Poser, ph: float) -> Vector3:
	var dh := _gait(p, ph, CROUCH)
	dh += p.hip(0.0, -0.30, -0.02)
	p.d("Spine2", 4.0, 0.0, 0.0)
	return dh


## « Static crouch — knees loaded, torso upright behind the weapon. »
## Boucle à 0,19 Hz comme `idle` (défaut de l'animateur, cf. inventaire).
##
## ⚠️ C'est la posture la plus basse du fichier : −0,315 m de hanche à elle seule, et le premier
## terme du pire cas du §B. Chez nous l'accroupi N'EST PAS une amplitude d'animation : c'est
## `SILHOUETTE_TOP_DOWN`, une entrée de la table angulaire serveur. La vue doit descendre
## EXACTEMENT là — ni plus, ni moins. Cf. `trench_soldier_bounds.gd`.
static func crouch_idle(p: Poser, ph: float) -> Vector3:
	var t := ph * TAU
	var breath := sin(t * 0.6)
	var dh := p.hip(0.004 * sin(t * 0.4), -0.315 + 0.004 * breath, -0.02)
	p.d("Hips", 7.0, 1.5, 1.0)
	p.d("UpLegR", 44.0, 3.0, -6.0)
	p.d("LegR", -78.0, 0.0, 0.0)
	p.d("FootR", 30.0, -2.0, 0.0)
	p.d("UpLegL", 36.0, -6.0, 7.0)
	p.d("LegL", -86.0, 0.0, 0.0)
	p.d("FootL", 32.0, 4.0, 0.0)
	# Le buste reste DROIT : la respiration seule l'anime. C'est ce qui distingue « accroupi
	# derrière son arme » de « accroupi pour se cacher » — le second replierait le rachis.
	p.d("Spine", 6.0 + 0.6 * breath, 0.0, 0.0)
	p.d("Spine1", 5.0 + 0.8 * breath, 0.0, 0.0)
	p.d("Spine2", 3.0 + 1.0 * breath, 0.0, 0.0)
	p.d("Neck", 2.0, 0.0, 0.0)
	p.d("ClavicleR", -2.0, 0.0, 1.5)
	p.d("ClavicleL", -1.5, 0.0, -1.5)
	return dh


## « Prone-ish crawl is out of scope; a wounded low stance stands in for it. »
## Déclenché sous 35 points de vie (`agent.js:950`). Boucle à 0,19 Hz.
##
## ⚠️ Un seul terme animé (`sin(t·1,6)` sur Spine2) : tout le reste est FIGÉ. C'est délibéré — un
## blessé ne se balance pas, il tient. Et c'est aussi ce qui fait que ce clip pousse `HeadTop` de
## +0,398 m vers l'avant en permanence, sans jamais revenir : une posture, pas une oscillation.
static func hurt_idle(p: Poser, ph: float) -> Vector3:
	var t := ph * TAU
	var dh := p.hip(0.0, -0.10, -0.03)
	p.d("Hips", 10.0, 0.0, 4.0)
	p.d("Spine", 12.0, 0.0, -3.0)
	p.d("Spine1", 9.0, 0.0, -2.0)
	p.d("Spine2", 5.0 + sin(t * 1.6), 0.0, 0.0)
	p.d("Neck", 6.0, 0.0, 0.0)
	p.d("UpLegR", 16.0, 0.0, -3.0)
	p.d("LegR", -28.0, 0.0, 0.0)
	p.d("FootR", 12.0, 0.0, 0.0)
	p.d("UpLegL", 10.0, 0.0, 4.0)
	p.d("LegL", -20.0, 0.0, 0.0)
	p.d("FootL", 9.0, 0.0, 0.0)
	return dh


## Aiguillage sur les six clips de locomotion, équivalent de leur export `CLIPS` (`clips.js:354`).
## Un nom inconnu retombe sur `idle`, comme chez eux (`animator.js:243`).
## ⚠️ On passe par une variable plutôt que par six `return` dans le `match` : l'analyseur GDScript
## ne prouve pas toujours qu'un `match` est exhaustif, et « Not all code paths return a value » est
## une erreur de COMPILATION — donc invisible à un `--import` qu'on croit vert (cf. mémoire projet).
static func locomotion(p: Poser, nom: String, ph: float) -> Vector3:
	var dh := Vector3.ZERO
	match nom:
		"walk":
			dh = walk(p, ph)
		"run":
			dh = run(p, ph)
		"crouchWalk":
			dh = crouch_walk(p, ph)
		"crouchIdle":
			dh = crouch_idle(p, ph)
		"hurtIdle":
			dh = hurt_idle(p, ph)
		_:
			dh = idle(p, ph)
	return dh


# =================================================================================================
# 6. COUPS UNIQUES ET ADDITIFS
# =================================================================================================
# ⚠️⚠️ PIÈGE D'UNITÉ, hérité tel quel de la référence et NON corrigé (le corriger aurait changé
# des constantes) : les cinq fonctions ci-dessous ne prennent PAS le même `t`.
#
#     recoil_add(t)   → t en SECONDES depuis le tir            (garde interne à 0,26 s)
#     hit_add(t)      → t en SECONDES depuis l'impact          (garde interne à 0,50 s)
#     reload_add(t)   → t NORMALISÉ 0..1 sur la durée du clip  (aucune garde)
#     turn_step(t)    → t NORMALISÉ 0..1 sur 0,42 s            (aucune garde, `min(1, t)` interne)
#     vault(t)        → t NORMALISÉ 0..1 sur 0,80–0,85 s       (aucune garde)
#
# Se tromper ne lève rien : `reload_add(0.4)` reçu comme des secondes joue simplement 40 % du clip
# à chaque image, pour l'éternité. C'est un défaut MUET, la pire espèce. Les appelants passent par
# `tick_seconds()` d'un côté et par une division explicite de l'autre.


## « Pivot on the balls of the feet: the trailing foot lifts and re-plants. »
## `t` NORMALISÉ sur 0,42 s. `dir` > 0 = pivot vers la droite. Renvoie la hanche (§B).
##
## 🩸 Seul clip du lot qui claque à 20 Hz : 0,42 s = 8,4 pas, le dernier échantillon laisse
## l'enveloppe à 0,149 et le suivant la met à 0. Cf. §A.1 — le correctif est une durée entière
## de pas, et il appartient à l'appelant.
static func turn_step(p: Poser, t: float, dir: float) -> Vector3:
	var e := sin(PI * minf(1.0, t))  # 0 → 1 → 0 : lever puis reposer, jamais de palier
	var s := "R" if dir > 0.0 else "L"
	var o := "L" if dir > 0.0 else "R"
	# La jambe qui MÈNE se lève et se replante…
	p.d("UpLeg" + s, 12.0 * e, dir * 16.0 * e, 0.0)
	p.d("Leg" + s, -34.0 * e, 0.0, 0.0)
	p.d("Foot" + s, 16.0 * e, 0.0, 0.0)
	# … l'autre pivote sur place, trois fois moins fort.
	p.d("UpLeg" + o, -4.0 * e, -dir * 4.0 * e, 0.0)
	p.d("Leg" + o, -10.0 * e, 0.0, 0.0)
	p.d("Hips", 0.0, dir * 6.0 * e, dir * -2.0 * e)
	return p.hip(0.0, -0.012 * e, 0.0)


## ⚠️⚠️ **NON UTILISÉE** — cf. §D de l'en-tête.
## Nos deux combattants sont confinés dans une tranchée : il n'y a rien à franchir, et aucun état
## serveur ne peut déclencher ce clip. Portée pour la complétude de l'inventaire, pas pour l'usage.
##
## ⛔ Si elle est branchée un jour : ce clip monte `HeadTop` de **+0,662 m** en profondeur, et la
## RACINE ajoute **+0,42 m** en vertical par-dessus (`agent.js:937`). Les deux vivent dans des
## fichiers différents et ne s'additionnent nulle part — la silhouette sort de la boîte serveur
## par le haut et par la profondeur en même temps.
##
## « Vault: plant the support hand, tuck the knees over the obstacle, land. Root motion (the actual
## translation) is driven by the agent. » `t` NORMALISÉ. 16 os (le brief en annonçait 15).
static func vault(p: Poser, t: float) -> Vector3:
	# Trois enveloppes décalées : la montée, le groupé (retardé de 12 %), la réception (30 % final).
	var rise := sin(PI * minf(1.0, t * 1.05))
	var tuck := sin(PI * minf(1.0, maxf(0.0, (t - 0.12) * 1.3)))
	var land := maxf(0.0, (t - 0.7) / 0.3)
	var dh := p.hip(0.0, 0.10 * rise, 0.02 * rise)
	# `- 16 * land` : le bassin se REDRESSE à la réception, sinon l'atterrissage reste plié.
	p.d("Hips", 26.0 * rise - 16.0 * land, 0.0, 0.0)
	p.d("Spine", 20.0 * rise, 0.0, -4.0 * rise)
	p.d("Spine1", 14.0 * rise, 0.0, -3.0 * rise)
	p.d("Spine2", 8.0 * rise, -14.0 * rise, 0.0)
	p.d("Neck", -8.0 * rise, 6.0 * rise, 0.0)
	p.d("UpLegR", 86.0 * tuck + 30.0 * land, 0.0, -10.0 * tuck)
	p.d("LegR", -104.0 * tuck - 20.0 * land, 0.0, 0.0)
	p.d("FootR", 24.0 * tuck, 0.0, 0.0)
	p.d("UpLegL", 68.0 * tuck + 12.0 * land, 0.0, 12.0 * tuck)
	p.d("LegL", -92.0 * tuck - 30.0 * land, 0.0, 0.0)
	p.d("FootL", 20.0 * tuck, 0.0, 0.0)
	# « support arm swings out of the weapon grip » — la main gauche lâche le garde-main pour se
	# poser sur l'obstacle. C'est la seule fonction du fichier qui touche `ForearmL`.
	p.d("ClavicleL", -18.0 * rise, 12.0 * rise, -14.0 * rise)
	p.d("UpperArmL", -46.0 * rise, 0.0, -28.0 * rise)
	p.d("ForearmL", -30.0 * rise, 0.0, 0.0)
	p.d("ClavicleR", -6.0 * rise, 0.0, 4.0 * rise)
	p.d("UpperArmR", -14.0 * rise, 0.0, 10.0 * rise)
	return dh


## « Firing impulse. `t` is seconds since the shot; the shape is a fast spike and a springy settle,
## which is what makes a burst read as recoil rather than as a wobble. »
##
## `t` en SECONDES. Ne pose rien au-delà de 0,26 s. Ne touche pas la hanche → renvoie `Vector3.ZERO`.
##
## 🩸 `osc = sin(92·t)` = 14,64 Hz : REPLIÉ à 20 Hz (Nyquist 10 Hz), il devient un battement à
## 5,36 Hz en sens inverse. Cf. §A.4 : la fonction étant pure, l'appelant peut choisir de
## l'échantillonner sur l'horloge de rendu — mais il choisit alors une pose qui dépend de la
## machine. Ce fichier ne tranche pas ; il refuse juste que le choix soit fait par accident.
##
## ⚠️ L'animateur garde la minuterie vivante jusqu'à 0,30 s (`animator.js:262`) alors que le clip
## se tait à 0,26 s : 40 ms où le recul « est en cours » sans rien poser. Sans conséquence, mais
## une garde et une minuterie qui ne sont pas d'accord finissent toujours par mentir à quelqu'un.
static func recoil_add(p: Poser, t: float, strength := 1.0) -> Vector3:
	if t > RECUL_DUREE:
		return Vector3.ZERO
	# La garde ci-dessus reproduit le `return` de la référence : au-delà, AUCUN os n'est écrit
	# (et non pas « écrit à zéro »). L'enveloppe, elle, n'est pas recopiée — un seul endroit
	# détient la formule.
	var e := recoil_envelope(t)
	var osc := sin(t * RECUL_OSC_RAD_S)
	var k := strength * e
	# L'impulsion part de l'épaule de tir et remonte la chaîne en s'atténuant : clavicule (−7),
	# rachis (−3,5 puis −2), nuque (−2,5), et la tête part en SENS INVERSE (+1,5) — c'est ce
	# désaccord tête/buste qui fait lire « encaissé » plutôt que « secoué ».
	p.d("ClavicleR", -7.0 * k, 0.0, 3.0 * k)
	p.d("UpperArmR", -9.0 * k + 2.0 * osc * k, 0.0, 5.0 * k)
	p.d("ForearmR", 7.0 * k, 0.0, 0.0)
	p.d("ClavicleL", -3.0 * k, 0.0, -2.0 * k)
	p.d("UpperArmL", -6.0 * k, 0.0, -3.0 * k)
	p.d("Spine2", -3.5 * k, 1.5 * k * osc, 0.0)
	p.d("Spine1", -2.0 * k, 0.0, 0.0)
	p.d("Neck", -2.5 * k, 0.0, 0.0)
	p.d("Head", 1.5 * k, 0.8 * k * osc, 0.0)
	return Vector3.ZERO


## « Region-specific hit reaction; `t` seconds since impact. »
##
## `t` en SECONDES. `dir_side` ≥ 0 → le corps part vers la droite du personnage. `strength` monte
## à 1,4 (`agent.js:835`). Renvoie la contribution de hanche (§B) — non nulle pour 'torso',
## 'legR' et 'legL' UNIQUEMENT.
##
## ⚠️ SEPT branches. Le brief n'en couvrait que quatre, en trois lignes de table ('head', 'torso',
## 'legR'/'legL') : 'armR', 'armL' et le cas par défaut manquaient à l'inventaire. Ils sont ici.
## ⚠️ L'enveloppe culmine à 0,711 124 et NON à 1 : `strength = 1` ne joue jamais l'amplitude
## écrite. Cf. §A — et `HIT_ENV_GAIN_20HZ` si l'appelant veut que le pic vaille exactement
## `strength` sur notre horloge.
static func hit_add(p: Poser, region: String, t: float, dir_side := 0.0, strength := 1.0) -> Vector3:
	if t > COUP_DUREE:
		return Vector3.ZERO
	# Même règle que pour le recul : la garde reproduit leur `return` sec, l'enveloppe vit dans
	# `hit_envelope()` et nulle part ailleurs.
	var k := strength * hit_envelope(t)
	var side := 1.0 if dir_side >= 0.0 else -1.0
	match region:
		"head":
			# La tête part plus fort que la nuque (−20 contre −16) : c'est le décalage qui fait le
			# fouet. Amplitudes égales donneraient un buste rigide qui bascule d'un bloc.
			p.d("Neck", -16.0 * k, 10.0 * k * side, 6.0 * k * side)
			p.d("Head", -20.0 * k, 14.0 * k * side, 8.0 * k * side)
			p.d("Spine2", -7.0 * k, 4.0 * k * side, 0.0)
			p.d("Spine1", -4.0 * k, 0.0, 0.0)
		"torso":
			# Gradient INVERSE de 'head' : le choc grandit en montant (−6 → −9 → −11) parce qu'il
			# entre par le sternum. Et la nuque part à CONTRE-SENS (+6) : le menton tombe.
			p.d("Spine", -6.0 * k, 3.0 * k * side, 2.0 * k * side)
			p.d("Spine1", -9.0 * k, 5.0 * k * side, 3.0 * k * side)
			p.d("Spine2", -11.0 * k, 6.0 * k * side, 4.0 * k * side)
			p.d("Neck", 6.0 * k, -3.0 * k * side, 0.0)
			p.d("Hips", 4.0 * k, 0.0, 0.0)
			return p.hip(-0.02 * k * side, -0.02 * k, -0.03 * k)
		"armR":
			p.d("ClavicleR", -14.0 * k, 6.0 * k, 10.0 * k)
			p.d("UpperArmR", -22.0 * k, 0.0, 14.0 * k)
			p.d("ForearmR", 16.0 * k, 0.0, 0.0)
			p.d("Spine2", -5.0 * k, 6.0 * k, 0.0)
		"armL":
			p.d("ClavicleL", -14.0 * k, -6.0 * k, -10.0 * k)
			p.d("UpperArmL", -24.0 * k, 0.0, -16.0 * k)
			p.d("ForearmL", 18.0 * k, 0.0, 0.0)
			p.d("Spine2", -5.0 * k, -6.0 * k, 0.0)
		"legR":
			# ⚠️ Le −0,05 m de hanche ci-dessous est le terme que le chiffrage d'origine (−0,47)
			# avait oublié : avec `strength` à 1,4 il pèse 48 mm dans le cumul du §B.
			p.d("UpLegR", 14.0 * k, 0.0, -8.0 * k)
			p.d("LegR", -30.0 * k, 0.0, 0.0)
			p.d("Hips", 8.0 * k, 0.0, -6.0 * k)
			return p.hip(0.0, -0.05 * k, 0.0)
		"legL":
			p.d("UpLegL", 14.0 * k, 0.0, 8.0 * k)
			p.d("LegL", -30.0 * k, 0.0, 0.0)
			p.d("Hips", 8.0 * k, 0.0, 6.0 * k)
			return p.hip(0.0, -0.05 * k, 0.0)
		_:
			# Région inconnue : un tressaillement symétrique du buste. Jamais rien, jamais un cri
			# d'erreur — une région mal orthographiée doit produire une réaction, pas un mannequin.
			p.d("Spine1", -6.0 * k, 0.0, 0.0)
			p.d("Spine2", -6.0 * k, 0.0, 0.0)
	return Vector3.ZERO


## « Flinch/duck when rounds crack past. »
##
## ADDITIF CONTINU, `w` = intensité de suppression (plafonnée à 1 par l'appelant,
## `animator.js:258`). Renvoie la hanche (§B) : −0,10 m, troisième terme du pire cas.
##
## ⚠️ Purement sagittal : sur les dix os, pas UN seul terme de torsion (y) ni de latéral (z) — que
## de la flexion. Se baisser sous une rafale, c'est plier en avant, pas s'écarter ; du latéral ici
## ferait lire « esquive », soit un mensonge sur une balle déjà partie. (La hanche, elle, descend
## de 0,10 m : c'est une translation, pas une rotation.)
static func suppress_add(p: Poser, w: float) -> Vector3:
	if w <= 0.0:
		return Vector3.ZERO
	p.d("Hips", 7.0 * w, 0.0, 0.0)
	p.d("Spine", 9.0 * w, 0.0, 0.0)
	p.d("Spine1", 8.0 * w, 0.0, 0.0)
	p.d("Spine2", 6.0 * w, 0.0, 0.0)
	# Nuque et tête à CONTRE-SENS du buste : le corps plonge, le regard reste sur la menace.
	p.d("Neck", -6.0 * w, 0.0, 0.0)
	p.d("Head", -8.0 * w, 0.0, 0.0)
	p.d("UpLegR", 16.0 * w, 0.0, 0.0)
	p.d("LegR", -26.0 * w, 0.0, 0.0)
	p.d("UpLegL", 14.0 * w, 0.0, 0.0)
	p.d("LegL", -24.0 * w, 0.0, 0.0)
	return p.hip(0.0, -0.10 * w, 0.0)


## « Reload: the support hand leaves the handguard, drops the magazine, fetches a fresh one from
## the chest and slaps it home. The hand path itself is driven by the animator's IK target; this is
## the body language around it. »
##
## `t` NORMALISÉ 0..1 sur la durée du rechargement. Ne touche pas la hanche → `Vector3.ZERO`.
##
## ⚠️ La durée n'est PAS un paramètre de ce clip, et c'est volontaire : chez nous elle vient du
## serveur (`reload_ticks`), et l'appelant divise lui-même. Recopier un défaut (2,35 / 2,4 / 2,9 —
## la référence en a trois) recréerait la seconde source de vérité du §8.148 : la main reviendrait
## au garde-main après que le serveur a réautorisé le tir. Cf. `trench_wclips.gd` §D.1.
##
## `w` est une fenêtre trapézoïdale : montée sur le premier sixième, plateau, descente sur le
## dernier sixième. C'est ce qui garantit que le clip PART de la pose de base et Y REVIENT — la
## porte du cahier §5. Sur 2,35 s, les rampes durent 392 ms (7,8 pas de simulation).
##
## ⚠️ `w(0) = w(1) = 0` EXACTEMENT : ce clip ne laisse aucun résidu — à condition que l'appelant
## échantillonne bien t = 1,0. Avec un `t` accumulé en flottant (`t += dt`), 47 × 0,05 vaut
## 2,350 000 000 000 000 5 : la comparaison `> durée` coupe **un pas trop tôt**, à t = 46/47, où
## `w` vaut encore 0,128 — un claquement de 2° sur le rachis, dû à un bit de mantisse. D'où
## `tick_seconds()` : un compteur ENTIER de pas divisé par un nombre ENTIER de pas ne dérive pas.
static func reload_add(p: Poser, t: float) -> Vector3:
	var w := minf(1.0, maxf(0.0, minf(t * 6.0, (1.0 - t) * 6.0)))
	# Le buste se tourne de 16° vers la main d'appui : c'est le corps qui amène l'arme à la main,
	# pas la main qui va chercher l'arme. Tête et nuque suivent (+8, +6) pour regarder le puits.
	p.d("Spine2", 4.0 * w, -16.0 * w, -3.0 * w)
	p.d("Spine1", 3.0 * w, -6.0 * w, 0.0)
	p.d("Neck", 6.0 * w, 8.0 * w, 0.0)
	p.d("Head", -4.0 * w, 6.0 * w, 3.0 * w)
	p.d("ClavicleR", -4.0 * w, -4.0 * w, 4.0 * w)
	p.d("UpperArmR", 6.0 * w, 0.0, 10.0 * w)
	p.d("ForearmR", -6.0 * w, 0.0, 0.0)
	return Vector3.ZERO
