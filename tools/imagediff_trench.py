#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =================================================================================================
# LA TRANCHEE (§8.151, LOT E — cahier §7.1) — PORTE IMAGEDIFF PAR-PIXEL.
#
# Compare deux REPERTOIRES de captures PNG apparies par NOM de fichier (inventaire PLAT, pas de
# recursion). C'est LA PORTE du chantier « experience AAA » : elle prouve qu'un changement est
# pixel-neutre (prewarm du LOT E), que les baselines du LOT 0 (`frontend/tools/baselines/`) sont
# reproductibles d'une execution a l'autre, et elle attrape les regressions de rendu des LOTS C/D
# (le sabotage `fog_sky_affect` du cahier §5 doit rougir ICI).
#
# ╔═ ROLE DE PORTE — POURQUOI LE VERDICT EST AUSSI STRICT (cahier §2.2 et §7) ═══════════════════╗
# ║ Code retour 0 UNIQUEMENT si TOUT est identique (a la tolerance demandee pres, defaut 0).      ║
# ║ Un fichier manquant d'UN cote est un ECHEC : une porte qui compare moins de fichiers que      ║
# ║ prevu est une porte trouee. Deux repertoires sans AUCUN PNG sont un ECHEC aussi : une         ║
# ║ comparaison vide qui rendrait 0 serait un faux vert — la lecon des inventaires a plat         ║
# ║ (§8.144). Et une tolerance > 0 qui absorbe des ecarts le DIT (etat TOLERE) au lieu de les     ║
# ║ manger en silence.                                                                            ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# Sortie texte STABLE et PARSABLE : une ligne `FICHIER | cle=valeur | ...` par nom, ordre trie,
# francais sans accent (les consoles cp1252 et les pipelines `OS.execute` ne cassent jamais) ;
# aucune horloge, aucun RNG — memes entrees, meme sortie, octet pour octet.
# Le verdict final tient sur une ligne greppable : `VERDICT=OK` ou `VERDICT=ECHEC`.
#
# USAGE (depuis `frontend/`) :
#   py tools/imagediff_trench.py <repertoire_a> <repertoire_b> [--tolerance N]
# Codes retour : 0 = tout identique (tolerance comprise) · 1 = ecarts detectes · 2 = erreur d'usage.
# Teste par `tools/test_imagediff_trench.py` (autonome, PYTHONUTF8=1, sans pytest).
# =================================================================================================

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

# Ordre des canaux du mode canonique RGBA — les etiquettes de `delta_max` s'y alignent.
CANAUX = ("R", "V", "B", "A")

# Etats possibles d'une ligne FICHIER. Seuls les deux premiers laissent la porte verte.
ETATS_VERTS = ("IDENTIQUE", "TOLERE")


def lister_png(dossier: Path) -> dict[str, Path]:
    """Inventaire PLAT des PNG d'un repertoire : nom de fichier -> chemin.

    Seule l'extension `.png` (casse ignoree) est retenue ; sous-repertoires et autres
    fichiers sont ignores — les jeux de baselines sont plats par construction (LOT 0).
    """
    return {p.name: p for p in dossier.iterdir() if p.is_file() and p.suffix.lower() == ".png"}


def charger_rgba(chemin: Path) -> np.ndarray:
    """Charge un PNG en tableau uint8 (hauteur x largeur x 4), mode canonique RGBA.

    La conversion RGBA neutralise les choix d'encodage (RGB, palette, niveaux de gris) :
    ce sont les VALEURS de pixels qui sont comparees, pas la maniere dont l'encodeur les range.
    """
    with Image.open(chemin) as image:
        return np.asarray(image.convert("RGBA"), dtype=np.uint8)


def comparer_paire(nom: str, chemin_a: Path, chemin_b: Path, tolerance: int) -> tuple[str, str]:
    """Compare un couple de PNG apparies par nom. Renvoie (etat, ligne formatee).

    Etats rendus : IDENTIQUE, TOLERE (ecarts tous <= tolerance), DIFFERENT,
    TAILLES_DIFFERENTES, ILLISIBLE.
    """
    try:
        a = charger_rgba(chemin_a)
    except Exception as exc:  # fichier corrompu/illisible : la porte echoue, elle ne devine pas
        return "ILLISIBLE", f"FICHIER | nom={nom} | etat=ILLISIBLE | cote=A | erreur={exc}"
    try:
        b = charger_rgba(chemin_b)
    except Exception as exc:
        return "ILLISIBLE", f"FICHIER | nom={nom} | etat=ILLISIBLE | cote=B | erreur={exc}"

    if a.shape != b.shape:
        taille_a = f"{a.shape[1]}x{a.shape[0]}"
        taille_b = f"{b.shape[1]}x{b.shape[0]}"
        return "TAILLES_DIFFERENTES", (
            f"FICHIER | nom={nom} | etat=TAILLES_DIFFERENTES"
            f" | taille_a={taille_a} | taille_b={taille_b}"
        )

    # int32 AVANT la soustraction : sur uint8, 1 - 2 vaudrait 255 (enroulement) et un ecart
    # minuscule se maquillerait en ecart enorme — ou l'inverse selon le sens.
    delta = np.abs(a.astype(np.int32) - b.astype(np.int32))  # hauteur x largeur x 4
    delta_max_canal = delta.reshape(-1, delta.shape[2]).max(axis=0)
    delta_max_txt = " ".join(f"{c}:{int(v)}" for c, v in zip(CANAUX, delta_max_canal))

    # Un pixel est FAUTIF si AU MOINS UN canal depasse la tolerance (strict : delta > tolerance ;
    # avec --tolerance 1, un ecart de 1 passe, un ecart de 2 echoue).
    fautifs = np.any(delta > tolerance, axis=2)
    nb_fautifs = int(np.count_nonzero(fautifs))

    if nb_fautifs == 0:
        if int(delta_max_canal.max()) == 0:
            return "IDENTIQUE", (
                f"FICHIER | nom={nom} | etat=IDENTIQUE | pixels_differents=0"
                f" | delta_max={delta_max_txt}"
            )
        # Des ecarts existent mais tiennent TOUS dans la tolerance : le fichier passe, et on
        # l'ecrit noir sur blanc — une tolerance qui absorbe en silence fabrique des faux verts.
        nb_toleres = int(np.count_nonzero(np.any(delta > 0, axis=2)))
        return "TOLERE", (
            f"FICHIER | nom={nom} | etat=TOLERE | pixels_differents=0"
            f" | pixels_dans_tolerance={nb_toleres} | delta_max={delta_max_txt}"
        )

    # Premier pixel fautif en ordre de LECTURE (haut vers bas, puis gauche vers droite) :
    # np.nonzero parcourt ligne par ligne, son premier resultat est donc le bon.
    ys, xs = np.nonzero(fautifs)
    y0, x0 = int(ys[0]), int(xs[0])
    valeur_a = ",".join(str(int(v)) for v in a[y0, x0])
    valeur_b = ",".join(str(int(v)) for v in b[y0, x0])
    return "DIFFERENT", (
        f"FICHIER | nom={nom} | etat=DIFFERENT | pixels_differents={nb_fautifs}"
        f" | delta_max={delta_max_txt}"
        f" | premier_x={x0} | premier_y={y0}"
        f" | valeur_a={valeur_a} | valeur_b={valeur_b}"
    )


def comparer_repertoires(repertoire_a: Path, repertoire_b: Path, tolerance: int,
                         sortie=print) -> int:
    """Deroule la comparaison complete et imprime le rapport. Renvoie le code retour."""
    sortie("=== PORTE IMAGEDIFF LA TRANCHEE (LOT E, cahier 7.1) ===")
    sortie(f"repertoire_a={repertoire_a}")
    sortie(f"repertoire_b={repertoire_b}")
    sortie(f"tolerance={tolerance}")

    pngs_a = lister_png(repertoire_a)
    pngs_b = lister_png(repertoire_b)
    noms = sorted(set(pngs_a) | set(pngs_b))

    if not noms:
        # Le piege du vert vide : comparer zero fichier et rendre 0 laisserait passer N'IMPORTE
        # QUEL chantier (mauvais chemin, baselines jamais generees). La porte refuse.
        sortie("ERREUR | aucun fichier PNG d'aucun cote : rien a comparer, la porte refuse un vert vide")
        sortie("VERDICT=ECHEC")
        return 2

    compteurs = {
        "IDENTIQUE": 0, "TOLERE": 0, "DIFFERENT": 0,
        "TAILLES_DIFFERENTES": 0, "ILLISIBLE": 0, "MANQUANT": 0,
    }
    for nom in noms:
        if nom not in pngs_a:
            compteurs["MANQUANT"] += 1
            sortie(f"FICHIER | nom={nom} | etat=MANQUANT_A | detail=present_en_B_absent_en_A")
            continue
        if nom not in pngs_b:
            compteurs["MANQUANT"] += 1
            sortie(f"FICHIER | nom={nom} | etat=MANQUANT_B | detail=present_en_A_absent_en_B")
            continue
        etat, ligne = comparer_paire(nom, pngs_a[nom], pngs_b[nom], tolerance)
        compteurs[etat] += 1
        sortie(ligne)

    sortie(
        f"BILAN | fichiers_examines={len(noms)}"
        f" | identiques={compteurs['IDENTIQUE']}"
        f" | toleres={compteurs['TOLERE']}"
        f" | differents={compteurs['DIFFERENT']}"
        f" | tailles_differentes={compteurs['TAILLES_DIFFERENTES']}"
        f" | manquants={compteurs['MANQUANT']}"
        f" | illisibles={compteurs['ILLISIBLE']}"
    )

    ecarts = (compteurs["DIFFERENT"] + compteurs["TAILLES_DIFFERENTES"]
              + compteurs["MANQUANT"] + compteurs["ILLISIBLE"])
    if ecarts == 0:
        sortie("VERDICT=OK")
        return 0
    sortie("VERDICT=ECHEC")
    return 1


def main(argv=None) -> int:
    analyseur = argparse.ArgumentParser(
        prog="imagediff_trench.py",
        description=("Porte imagediff de LA TRANCHEE : compare deux repertoires de PNG "
                     "apparies par nom, par-pixel strict. Code retour 0 uniquement si tout "
                     "est identique (a --tolerance pres)."),
    )
    analyseur.add_argument("repertoire_a", help="repertoire de reference (cote A)")
    analyseur.add_argument("repertoire_b", help="repertoire compare (cote B)")
    analyseur.add_argument("--tolerance", type=int, default=0,
                           help="ecart de canal admis par pixel (defaut 0 = strict ; "
                                "un delta STRICTEMENT superieur echoue)")
    args = analyseur.parse_args(argv)

    if args.tolerance < 0:
        print("ERREUR | tolerance negative : la porte n'admet que 0 ou plus")
        print("VERDICT=ECHEC")
        return 2

    repertoire_a = Path(args.repertoire_a)
    repertoire_b = Path(args.repertoire_b)
    for etiquette, dossier in (("repertoire_a", repertoire_a), ("repertoire_b", repertoire_b)):
        if not dossier.is_dir():
            print(f"ERREUR | {etiquette} introuvable ou pas un repertoire : {dossier}")
            print("VERDICT=ECHEC")
            return 2

    return comparer_repertoires(repertoire_a, repertoire_b, args.tolerance)


if __name__ == "__main__":
    sys.exit(main())
