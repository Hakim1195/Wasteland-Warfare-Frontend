#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests de la porte imagediff de LA TRANCHÉE (§8.151, LOT E — cahier §7.1).

Convention du projet : script AUTONOME, sans pytest, lancé depuis `frontend/tools/` par
`py test_imagediff_trench.py` avec `PYTHONUTF8=1` exporté (sinon UnicodeEncodeError cp1252).

Le test fabrique des PNG synthétiques déterministes (aucun RNG) dans le scratchpad de session
(repli : répertoire temporaire système), puis exerce l'outil PAR SON CLI réel (sous-processus,
même interpréteur) — c'est le contrat complet qui est testé : codes retour, lignes parsables,
coordonnées du premier pixel fautif. Les répertoires de travail sont laissés en place après
exécution pour inspection ; ils sont balayés et recréés à chaque lancement.

Couverture exigée par la mission (cahier §7, contre-épreuve « sabotage ») :
  identiques → code 0 ; UN pixel décalé d'UN pas de quantification → détecté aux BONNES
  coordonnées ; tailles différentes → échec ; fichier manquant → échec ; tolérance 1 → le
  pixel à +1 passe, à +2 échoue. Plus deux gardes anti-faux-vert : comparaison vide refusée,
  répertoire inexistant refusé.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

# --- Emplacements --------------------------------------------------------------------------------
OUTIL = Path(__file__).resolve().parent / "imagediff_trench.py"

# Scratchpad de la session de chantier §8.151 (convention : les fichiers temporaires y vont).
# Hors session, le chemin n'existe plus : repli propre sur le répertoire temporaire système.
_SCRATCHPAD_SESSION = Path(
    "C:/Users/Hakim/AppData/Local/Temp/claude/"
    "C--Users-Hakim-Documents-Wasteland-Warfare-Project/"
    "0067b943-65e6-4a39-a4c0-1b7aead40116/scratchpad"
)
BASE = _SCRATCHPAD_SESSION if _SCRATCHPAD_SESSION.is_dir() else Path(tempfile.gettempdir())
RACINE = BASE / "imagediff_selftest"

# Pixel saboté du scénario « un pas de quantification » — coordonnées non triviales (ni coin,
# ni diagonale) pour que des coordonnées inversées x/y soient détectées comme fausses.
PIXEL_X, PIXEL_Y = 17, 5

_FAILURES = []
_RUN = 0


def check(condition, label):
    global _RUN
    _RUN += 1
    if condition:
        print(f"  [OK]   {label}")
    else:
        print(f"  [FAIL] {label}")
        _FAILURES.append(label)


# --- Outillage -----------------------------------------------------------------------------------
def image_degradee(largeur=32, hauteur=24, graine=0):
    """PNG synthétique déterministe : dégradé arithmétique, canaux < 200 (jamais de débordement
    quand le test décale un canal de +1 ou +2)."""
    image = Image.new("RGB", (largeur, hauteur))
    pixels = image.load()
    for y in range(hauteur):
        for x in range(largeur):
            pixels[x, y] = ((x * 3 + graine * 11) % 200,
                            (y * 5 + graine * 7) % 200,
                            (x + y * 2) % 200)
    return image


def paire_repertoires(nom):
    """Crée (vides) les deux répertoires d'un scénario et les renvoie."""
    cote_a = RACINE / f"{nom}_a"
    cote_b = RACINE / f"{nom}_b"
    cote_a.mkdir(parents=True)
    cote_b.mkdir(parents=True)
    return cote_a, cote_b


def lancer_porte(repertoire_a, repertoire_b, *options):
    """Lance l'outil par son CLI réel (même interpréteur) ; renvoie (code retour, sortie texte)."""
    environnement = dict(os.environ, PYTHONUTF8="1")
    processus = subprocess.run(
        [sys.executable, str(OUTIL), str(repertoire_a), str(repertoire_b), *options],
        capture_output=True, text=True, encoding="utf-8", env=environnement,
    )
    return processus.returncode, processus.stdout + processus.stderr


# --------------------------------------------------------------------------------------------------
def test_identiques():
    print("\n[1] Répertoires identiques → code 0, VERDICT=OK")
    cote_a, cote_b = paire_repertoires("s1_identiques")
    for nom, graine in (("shot_ambient.png", 0), ("shot_delivery.png", 4)):
        image = image_degradee(graine=graine)
        image.save(cote_a / nom)
        image.save(cote_b / nom)
    code, texte = lancer_porte(cote_a, cote_b)
    check(code == 0, f"code retour 0 (obtenu {code})")
    check("VERDICT=OK" in texte, "ligne VERDICT=OK présente")
    check(texte.count("etat=IDENTIQUE") == 2, "les 2 fichiers sont marqués IDENTIQUE")
    check("etat=DIFFERENT" not in texte, "aucun fichier marqué DIFFERENT")


def test_un_pas_de_quantification():
    print("\n[2] UN pixel décalé d'UN pas (+1 sur le canal V) → détecté aux bonnes coordonnées")
    cote_a, cote_b = paire_repertoires("s2_un_pas")
    image = image_degradee()
    image.save(cote_a / "capture.png")
    r, v, b = image.getpixel((PIXEL_X, PIXEL_Y))
    sabotee = image.copy()
    sabotee.putpixel((PIXEL_X, PIXEL_Y), (r, v + 1, b))
    sabotee.save(cote_b / "capture.png")

    code, texte = lancer_porte(cote_a, cote_b)
    check(code == 1, f"code retour 1 (obtenu {code})")
    check("VERDICT=ECHEC" in texte, "ligne VERDICT=ECHEC présente")
    check("etat=DIFFERENT" in texte, "fichier marqué DIFFERENT")
    check("pixels_differents=1" in texte, "exactement 1 pixel fautif compté")
    check(f"premier_x={PIXEL_X}" in texte, f"coordonnée x du premier fautif = {PIXEL_X}")
    check(f"premier_y={PIXEL_Y}" in texte, f"coordonnée y du premier fautif = {PIXEL_Y}")
    check("delta_max=R:0 V:1 B:0 A:0" in texte, "delta max par canal : V:1, le reste à 0")
    check(f"valeur_a={r},{v},{b},255" in texte, "valeurs du pixel côté A rapportées")
    check(f"valeur_b={r},{v + 1},{b},255" in texte, "valeurs du pixel côté B rapportées")


def test_tailles_differentes():
    print("\n[3] Tailles différentes → échec explicite")
    cote_a, cote_b = paire_repertoires("s3_tailles")
    image_degradee(32, 24).save(cote_a / "capture.png")
    image_degradee(16, 12).save(cote_b / "capture.png")
    code, texte = lancer_porte(cote_a, cote_b)
    check(code == 1, f"code retour 1 (obtenu {code})")
    check("etat=TAILLES_DIFFERENTES" in texte, "état TAILLES_DIFFERENTES rapporté")
    check("taille_a=32x24" in texte and "taille_b=16x12" in texte,
          "les deux tailles figurent dans la ligne")
    check("VERDICT=ECHEC" in texte, "ligne VERDICT=ECHEC présente")


def test_fichier_manquant():
    print("\n[4] Fichier manquant d'un côté (dans chaque sens) → échec")
    cote_a, cote_b = paire_repertoires("s4_manquant")
    commun = image_degradee(graine=2)
    commun.save(cote_a / "shot_1.png")
    commun.save(cote_b / "shot_1.png")
    image_degradee(graine=3).save(cote_a / "shot_2.png")   # absent de B
    image_degradee(graine=5).save(cote_b / "shot_3.png")   # absent de A
    code, texte = lancer_porte(cote_a, cote_b)
    check(code == 1, f"code retour 1 (obtenu {code})")
    check("nom=shot_2.png | etat=MANQUANT_B" in texte, "shot_2.png signalé manquant côté B")
    check("nom=shot_3.png | etat=MANQUANT_A" in texte, "shot_3.png signalé manquant côté A")
    check("manquants=2" in texte, "le bilan compte 2 manquants")
    check("VERDICT=ECHEC" in texte, "ligne VERDICT=ECHEC présente")


def test_tolerance():
    print("\n[5] --tolerance 1 : le pixel à +1 passe, à +2 échoue")
    # +1 : doit passer (état TOLERE, dit et compté — jamais absorbé en silence).
    cote_a, cote_b = paire_repertoires("s5_tolerance_plus1")
    image = image_degradee(graine=6)
    image.save(cote_a / "capture.png")
    r, v, b = image.getpixel((PIXEL_X, PIXEL_Y))
    plus_un = image.copy()
    plus_un.putpixel((PIXEL_X, PIXEL_Y), (r, v + 1, b))
    plus_un.save(cote_b / "capture.png")
    code, texte = lancer_porte(cote_a, cote_b, "--tolerance", "1")
    check(code == 0, f"+1 sous tolérance 1 : code retour 0 (obtenu {code})")
    check("VERDICT=OK" in texte, "+1 sous tolérance 1 : VERDICT=OK")
    check("etat=TOLERE" in texte, "+1 sous tolérance 1 : état TOLERE (l'écart est DIT)")
    check("pixels_dans_tolerance=1" in texte, "+1 sous tolérance 1 : 1 pixel dans la tolérance")

    # +2 : doit échouer (delta strictement supérieur à la tolérance).
    cote_a2, cote_b2 = paire_repertoires("s5_tolerance_plus2")
    image.save(cote_a2 / "capture.png")
    plus_deux = image.copy()
    plus_deux.putpixel((PIXEL_X, PIXEL_Y), (r, v + 2, b))
    plus_deux.save(cote_b2 / "capture.png")
    code2, texte2 = lancer_porte(cote_a2, cote_b2, "--tolerance", "1")
    check(code2 == 1, f"+2 sous tolérance 1 : code retour 1 (obtenu {code2})")
    check("etat=DIFFERENT" in texte2, "+2 sous tolérance 1 : état DIFFERENT")
    check("pixels_differents=1" in texte2, "+2 sous tolérance 1 : 1 pixel fautif compté")
    check("delta_max=R:0 V:2 B:0 A:0" in texte2, "+2 sous tolérance 1 : delta max V:2")


def test_vert_vide_refuse():
    print("\n[6] Deux répertoires sans aucun PNG → la porte refuse le vert vide")
    cote_a, cote_b = paire_repertoires("s6_vide")
    code, texte = lancer_porte(cote_a, cote_b)
    check(code == 2, f"code retour 2 (obtenu {code})")
    check("VERDICT=ECHEC" in texte, "ligne VERDICT=ECHEC présente")
    check("vert vide" in texte, "le motif « vert vide » est explicite")


def test_repertoire_inexistant():
    print("\n[7] Répertoire inexistant → erreur d'usage, jamais un vert")
    cote_a, _ = paire_repertoires("s7_existant")
    image_degradee().save(cote_a / "capture.png")
    code, texte = lancer_porte(cote_a, RACINE / "s7_inexistant_b")
    check(code == 2, f"code retour 2 (obtenu {code})")
    check("VERDICT=ECHEC" in texte, "ligne VERDICT=ECHEC présente")
    check("introuvable" in texte, "le répertoire fautif est signalé introuvable")


# --------------------------------------------------------------------------------------------------
def main():
    print("=" * 70)
    print("TESTS DE LA PORTE IMAGEDIFF — LA TRANCHÉE (LOT E, cahier §7.1)")
    print("=" * 70)
    print(f"outil    : {OUTIL}")
    print(f"travail  : {RACINE}")

    if not OUTIL.is_file():
        print(f"\n[FAIL] outil introuvable : {OUTIL}")
        return 1

    # Terrain propre à chaque lancement (les artefacts du run restent ensuite pour inspection).
    if RACINE.exists():
        shutil.rmtree(RACINE)
    RACINE.mkdir(parents=True)

    test_identiques()
    test_un_pas_de_quantification()
    test_tailles_differentes()
    test_fichier_manquant()
    test_tolerance()
    test_vert_vide_refuse()
    test_repertoire_inexistant()

    print("\n" + "=" * 70)
    if _FAILURES:
        print(f"ECHEC : {len(_FAILURES)}/{_RUN} controles en echec")
        for label in _FAILURES:
            print(f"  - {label}")
        return 1
    print(f"SUCCES : {_RUN}/{_RUN} controles passes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
