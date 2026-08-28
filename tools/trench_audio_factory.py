#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =================================================================================================
# LA TRANCHÉE (§8.151, LOT A) — USINE AUDIO OFFLINE : les .wav du duel, synthétisés en numpy.
#
# Transposition des RECETTES de la référence `War-Of-Indipendence/Claude-of-Duty-main/`
# (`src/audio/weapons.js` : le commentaire d'en-tête = la recette des 7 couches d'un tir ;
# `src/audio/dsp.js` : les briques ad/sweep/biquad/saturationCurve/struckResonator). On transpose
# des recettes, JAMAIS du code : Web Audio ≠ numpy, et le rendu ici est OFFLINE (fichiers .wav),
# pas temps réel.
#
# ╔═ LE CONTRAT AVEC LE MOTEUR ═══════════════════════════════════════════════════════════════════╗
# ║ `audio_manager.gd::_finalize` (l.1175) produit du PCM 16 bits MONO à `MIX_RATE = 44100` Hz    ║
# ║ (l.21). L'usine parle la MÊME langue : 44 100 Hz, 16 bits, mono. Les fichiers se déposent     ║
# ║ dans `assets/audio/sfx/` — la mécanique `_load_override` les prend alors en priorité sur les  ║
# ║ synthés GDScript, qui RESTENT le repli headless (§8.151 : extension additive, rien à casser). ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ REPRODUCTIBILITÉ (§3.1) ═════════════════════════════════════════════════════════════════════╗
# ║ Graine FIXE par son : crc32 du nom de fichier (PAS `hash()`, randomisé par processus — leçon  ║
# ║ mémoire projet §8.149). Deux exécutions de l'usine → fichiers aux hash IDENTIQUES. Le module  ║
# ║ `wave` n'écrit aucun horodatage : l'octet près est tenable, et `test_trench_audio.py` le      ║
# ║ prouve à chaque passage.                                                                      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# ╔═ NIVEAUX : LES PLACEHOLDERS SONT LA RÉFÉRENCE DE MIX ═════════════════════════════════════════╗
# ║ Ces fichiers REMPLACENT des synthés GDScript sous des sites d'appel déjà réglés en partie     ║
# ║ réelle (§8.141 : « le pas signale, il ne crie pas »). Un fichier plus fort que son placeholder║
# ║ casserait ce réglage en silence. L'usine re-synthétise donc chaque placeholder (formules      ║
# ║ transposées d'`audio_manager.gd`, l.654+/776+) et CALE le RMS de la famille dessus, mesuré    ║
# ║ sur la fenêtre de tête = durée du placeholder. Les familles SANS placeholder (whizz, shell,   ║
# ║ bolt) se placent PAR RAPPORT au tir. Garde-pic finale : -1,5 dBFS (marge sur le -1 exigé).    ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
#
# scipy est DÉTECTÉ, jamais présumé (§3.1) : présent → `scipy.signal.lfilter` (rapide) ; absent →
# biquads maison en forme directe II transposée (boucle Python, acceptable offline). ⚠️ Les deux
# chemins ne sont PAS bit-identiques entre eux : sur une machine sans scipy, régénérer TOUT (`all`)
# puis réimporter — ne jamais mélanger des fichiers issus des deux chemins.
#
# USAGE (depuis n'importe où, chemins absolus dérivés de __file__) :
#   py frontend/tools/trench_audio_factory.py all          # les 48 fichiers de la liste FERMÉE
#                                                          # (§3.3 + voix d'armes §3.6)
#   py frontend/tools/trench_audio_factory.py shot         # trench_shot_1..6 (7 couches, §3.2)
#   py frontend/tools/trench_audio_factory.py armes        # les 4 VOIX D'ARMES §3.6 (vipere ×4,
#                                                          # frelon ×6, chacal ×4, condor ×4)
#                                                          # + le télégraphe trench_laser_warn
#   py frontend/tools/trench_audio_factory.py whizz        # trench_whizz_1..4
#   py frontend/tools/trench_audio_factory.py explosion    # near_1..3 + far_1..3
#   py frontend/tools/trench_audio_factory.py mech         # douille, culasse, pas, retombées,
#                                                          # grenade + retours d'interface
#   py frontend/tools/trench_audio_factory.py check        # contrôles techniques §3.4 (exit 0/1)
#   py frontend/tools/trench_audio_factory.py dsp          # équivalence scipy <-> forme directe II
# Contre-épreuves sabotage (§ contre-épreuves LOT A) :
#   py ... shot  --sabotage sans-transitoire    # retire la couche 1 de trench_shot_1 -> check ROUGIT
#   py ... armes --sabotage sans-corps-condor   # retire corps+sub des 4 condor -> la bande
#                                               # « corps 20-150 Hz » et le contrôle inter-armes
#                                               # condor>frelon ROUGISSENT
# =================================================================================================

from __future__ import annotations

import argparse
import math
import sys
import wave
import zlib
from pathlib import Path

import numpy as np

# --- Contrat moteur (relevé du 2026-08-26 dans audio_manager.gd, l.21 et l.1175-1190) -----------
MIX_RATE = 44100                 # DOIT égaler audio_manager.gd::MIX_RATE — même langue que _finalize
SR = float(MIX_RATE)
TAU = 2.0 * math.pi
FLOOR = 1e-4                     # plancher des enveloppes exponentielles (dsp.js::FLOOR)
PIC_PLAFOND = 10.0 ** (-1.5 / 20.0)   # -1,5 dBFS : marge de 0,5 dB sur l'exigence « pic <= -1 dBFS »

RACINE_FRONTEND = Path(__file__).resolve().parent.parent
SORTIE = RACINE_FRONTEND / "assets" / "audio" / "sfx"

# scipy : détecté, jamais présumé (§3.1). Le repli maison vit dans _df2t_python().
try:
    from scipy.signal import lfilter as _scipy_lfilter  # type: ignore
    SCIPY_OK = True
except ImportError:              # pragma: no cover - dépend de la machine
    SCIPY_OK = False


# =================================================================================================
# LA LISTE FERMÉE (§3.3 + voix d'armes §3.6) — le nommage EST le contrat avec AudioManager
# (_load_override + rotation de variantes du §3.5). Un fichier hors liste dans `sfx/trench_*.wav`
# fait ROUGIR `check`. Les `trench_shot_1..6` restent le REPLI GÉNÉRIQUE (§3.6 : aucun fichier
# supprimé) ; les voix par arme s'y AJOUTENT — frelon ×6 car sa rafale de 3 consomme vite le
# round-robin, les autres ×4.
# =================================================================================================
FAMILLES: dict = {
    # famille -> (fichiers, bornes de durée en s, commande CLI qui la produit)
    "shot":           ([f"trench_shot_{i}" for i in range(1, 7)],           (0.45, 0.95), "shot"),
    "shot_vipere":    ([f"trench_shot_vipere_{i}" for i in range(1, 5)],    (0.25, 0.55), "armes"),
    "shot_frelon":    ([f"trench_shot_frelon_{i}" for i in range(1, 7)],    (0.25, 0.55), "armes"),
    "shot_chacal":    ([f"trench_shot_chacal_{i}" for i in range(1, 5)],    (0.50, 0.90), "armes"),
    "shot_condor":    ([f"trench_shot_condor_{i}" for i in range(1, 5)],    (0.95, 1.65), "armes"),
    "laser_warn":     (["trench_laser_warn"],                               (0.50, 0.75), "armes"),
    "whizz":          ([f"trench_whizz_{i}" for i in range(1, 5)],          (0.08, 0.35), "whizz"),
    "explosion_near": ([f"trench_explosion_near_{i}" for i in range(1, 4)], (0.80, 1.60), "explosion"),
    "explosion_far":  ([f"trench_explosion_far_{i}" for i in range(1, 4)],  (1.00, 1.80), "explosion"),
    "shell":          ([f"trench_shell_{i}" for i in range(1, 4)],          (0.15, 0.50), "mech"),
    "bolt":           (["trench_bolt"],                                     (0.25, 0.60), "mech"),
    "step":           ([f"trench_step_{i}" for i in range(1, 5)],           (0.08, 0.25), "mech"),
    "debris":         (["trench_debris"],                                   (0.40, 0.90), "mech"),
    "grenade":        (["trench_grenade"],                                  (0.08, 0.30), "mech"),
    "hitmarker":      (["trench_hitmarker"],                                (0.03, 0.15), "mech"),
    "hit":            (["trench_hit"],                                      (0.08, 0.35), "mech"),
    "refused":        (["trench_refused"],                                  (0.03, 0.15), "mech"),
}

# Bandes d'énergie attendues (§3.4) : fraction de l'énergie totale (20 Hz - Nyquist) dans la bande.
# « L'absence d'une bande = une couche oubliée. » Les seuils sont CALIBRÉS sur la production réelle
# (mesures consignées au rapport §8.151.1) avec une marge >= x2 de chaque côté.
BANDES: dict = {
    "shot": [("sub 40-100 Hz", 40, 100, 0.015, None),
             ("crack 1500-3500 Hz", 1500, 3500, 0.05, None),
             ("mordant 5000-10000 Hz", 5000, 10000, 0.010, None)],
    # --- Les 4 voix d'armes (§3.6) : bandes ADAPTÉES au profil — chaque arme a SA signature. ----
    # Seuils CALIBRÉS sur la production (mesures 2026-08-26, marge >= x2 côté vert sauf mention).
    # Vipère (pistolet) : claquant et léger — corps bref, crack ~2,7 kHz, mécanique brillante.
    "shot_vipere": [("corps 60-260 Hz", 60, 260, 0.30, None),          # mesuré 0,60-0,67
                    ("crack 1800-4200 Hz", 1800, 4200, 0.025, None),   # mesuré 0,051-0,091
                    ("mecanique 4000-9000 Hz", 4000, 9000, 0.06, None)],  # mesuré 0,13-0,18
    # Frelon (mitraillette) : détonation LÉGÈRE et VIVE — crack ~3 kHz, mordant présent, grave
    # CONTENU (max 0,55 : mesuré 0,30-0,38 ; s'il rejoignait le chacal (~0,66-0,71), la légèreté
    # serait morte — complément du contrôle inter-armes condor > frelon).
    "shot_frelon": [("corps 60-260 Hz", 60, 260, 0.30, None),          # mesuré 0,63-0,69
                    ("crack 2000-4600 Hz", 2000, 4600, 0.027, None),   # mesuré 0,055-0,080
                    ("mordant 4000-9000 Hz", 4000, 9000, 0.055, None), # mesuré 0,11-0,18
                    ("grave 20-150 Hz", 20, 150, None, 0.55)],
    # Chacal (fusil d'assaut) : la voix de tranchée recalibrée nerveuse — mêmes bandes que `shot`,
    # fenêtre de crack montée avec le profil (2,1 kHz).
    "shot_chacal": [("sub 40-110 Hz", 40, 110, 0.16, None),            # mesuré 0,32-0,43
                    ("crack 1300-3800 Hz", 1300, 3800, 0.026, None),   # mesuré 0,053-0,073
                    ("mordant 5000-10000 Hz", 5000, 10000, 0.014, None)],  # mesuré 0,029-0,050
    # Condor (précision) : LE CALIBRE — l'énergie sous 150 Hz est sa promesse. C'est LA bande que
    # le sabotage `sans-corps-condor` fait rougir (mesuré : 0,82-0,85 sain contre 0,003-0,006
    # saboté — marge x2 côté vert, x87 côté rouge). Et l'aigu reste BORNÉ : un calibre ne crie pas.
    "shot_condor": [("corps 20-150 Hz", 20, 150, 0.40, None),
                    ("crack 800-2800 Hz", 800, 2800, 0.025, None),     # mesuré 0,051-0,067
                    ("aigus 2500-10000 Hz", 2500, 10000, None, 0.12)], # mesuré 0,047-0,061
    # Télégraphe laser : bourdonnement bas, RIEN d'agressif dans les aigus (pas un buzzer).
    "laser_warn": [("fondamentale 80-450 Hz", 80, 450, 0.55, None),
                   ("aigus 2000-12000 Hz", 2000, 12000, None, 0.02)],
    "whizz": [("sifflement 1000-5500 Hz", 1000, 5500, 0.40, None)],
    "explosion_near": [("sub 30-120 Hz", 30, 120, 0.10, None),
                       ("claquement 1500-5000 Hz", 1500, 5000, 0.015, None)],
    # Le far est le MÊME événement SANS le claquement : l'aigu doit être ABSENT (timbre, pas volume).
    "explosion_far": [("sub 30-150 Hz", 30, 150, 0.25, None),
                      ("aigus 2500-10000 Hz", 2500, 10000, None, 0.02)],
    "shell": [("tintement 2500-9000 Hz", 2500, 9000, 0.45, None),
              ("grave 20-300 Hz", 20, 300, None, 0.15)],
    "bolt": [("metal 800-4500 Hz", 800, 4500, 0.35, None)],
    "step": [("matiere 40-300 Hz", 40, 300, 0.45, None),
             ("aigus 2000-12000 Hz", 2000, 12000, None, 0.12)],
    "debris": [("crepitement 300-4000 Hz", 300, 4000, 0.30, None)],
    "grenade": [("corps 250-1500 Hz", 250, 1500, 0.30, None)],
    "hitmarker": [("aigu 1200-4000 Hz", 1200, 4000, 0.50, None)],
    "hit": [("grave 80-500 Hz", 80, 500, 0.50, None)],
    # Le refus ne ressemble à AUCUN son d'action (§8.141.9) : rien dans les aigus balistiques.
    "refused": [("grave 60-600 Hz", 60, 600, 0.35, None),
                ("aigus 1500-12000 Hz", 1500, 12000, None, 0.05)],
}

# ╔═ LE CONTRÔLE DU TRANSITOIRE EST TEMPORISÉ — leçon de calibration (2026-08-26) ════════════════╗
# ║ Une bande pleine durée ne voit PAS la couche 1 disparaître : la saturation du crack (drive    ║
# ║ 7,5 → harmoniques jusqu'à 10 kHz+) et le souffle mécanique remplissent les mêmes fréquences   ║
# ║ (mesuré : retirer le transitoire ne bouge la bande 5-10 kHz que de x1,4). La signature UNIQUE ║
# ║ du transitoire est son ATTAQUE INSTANTANÉE : dans les 0,8 premières ms, toutes les autres     ║
# ║ couches rampent encore depuis le plancher (attaques 1,2-6 ms). On mesure donc                 ║
# ║ RMS(passe-haut 2,6 kHz, fenêtre 0-0,8 ms) / RMS(fichier entier). Mesuré sur les 6 variantes : ║
# ║ AVEC transitoire >= 2,08 ; SANS (sabotage) <= 0,027 — séparation x89-x196. Seuil 0,5 :        ║
# ║ marge >= x4 côté vert, >= x18 côté rouge. C'est LE contrôle que le sabotage fait rougir.      ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
ATTAQUE_TRANSITOIRE: dict = {
    # famille -> (coupure passe-haut Hz, fenêtre s, ratio minimal)
    "shot": (2600.0, 0.0008, 0.5),
}

# ╔═ CONTRÔLES INTER-ARMES (§3.6) — « quatre voix, pas une » (mesures du 2026-08-26) ═════════════╗
# ║ 1. Corrélation normalisée entre TOUTE paire de variantes de deux armes différentes < 0,90.    ║
# ║    Mesuré : pire paire 0,73 (vipere~frelon, deux tirs brefs et brillants) ; toutes les autres ║
# ║    paires d'armes <= 0,33. La production est DÉTERMINISTE (graines fixes) : ces valeurs ne    ║
# ║    bougent pas d'une exécution à l'autre — le seuil borne les RE-RÉGLAGES futurs.             ║
# ║ 2. Le CALIBRE s'entend : fraction moyenne sous 150 Hz du condor >= 2× celle du frelon.        ║
# ║    Mesuré : condor 0,834 contre frelon 0,330 — rapport 2,5× ; côté rouge, le sabotage         ║
# ║    sans-corps-condor effondre le condor à ~0,005 (rapport 0,01×), le contrôle rougit fort.    ║
# ║ 3. Niveaux relatifs à l'ancre chacal : le disque doit suivre POLITIQUE_NIVEAU (le registre),  ║
# ║    tolérance ±0,8 dB (±1,0 pour le laser) — un fichier périmé après un re-réglage rougit.     ║
# ║    Mesuré : vipere −2,00 · frelon −3,00 · condor +1,84 (la garde-pic −1,5 dBFS mange 0,16 dB  ║
# ║    du +2 visé — assumé §3.6) · laser −18,00.                                                  ║
# ╚═══════════════════════════════════════════════════════════════════════════════════════════════╝
ARMES = ("shot_vipere", "shot_frelon", "shot_chacal", "shot_condor")
CORRELATION_INTER_ARMES_MAX = 0.90
RAPPORT_GRAVE_CONDOR_FRELON_MIN = 2.0

# Le télégraphe laser doit MONTER (la menace approche) et entrer en FONDU (ambiance, pas buzzer).
LASER_MONTEE_MIN = 1.12          # freq dominante (dernier tiers) / (premier tiers)
LASER_FONDU_MAX = 0.45           # RMS(0-40 ms) / RMS(250-450 ms) — le fondu d'entrée s'entend

# Politique de niveau par famille (voir l'encadré « NIVEAUX » en tête).
#   ("placeholder", <ref>, fenetre_s) : RMS de tête calé sur le synthé GDScript re-synthétisé ici.
#   ("relatif", "trench_shot", dB)    : décalage en dB par rapport au RMS du placeholder du tir.
POLITIQUE_NIVEAU: dict = {
    "shot":           ("placeholder", "trench_shot", 0.18),
    "explosion_near": ("placeholder", "explosion", 0.70),
    "explosion_far":  ("placeholder", "trench_explosion_far", 0.95),
    "step":           ("placeholder", "trench_step", 0.12),
    "debris":         ("placeholder", "trench_debris", 0.55),
    "grenade":        ("placeholder", "blip_grenade", 0.09),
    "hitmarker":      ("placeholder", "blip_hitmarker", 0.05),
    "hit":            ("placeholder", "blip_hit", 0.14),
    "refused":        ("placeholder", "blip_refused", 0.045),
    "whizz":          ("relatif", "trench_shot", -5.0),   # la balle qui passe : juste sous le tir
    "shell":          ("relatif", "trench_shot", -14.0),  # la douille : un détail, jamais un événement
    "bolt":           ("relatif", "trench_shot", -10.0),  # la culasse : audible (signature), pas un tir
    # --- Voix d'armes (§3.6) : RMS en RELATIF à la voix CHACAL, l'ancre de la famille. ----------
    #   Le chacal reprend la place de mix de la voix générique qu'il spécialise (même placeholder,
    #   même fenêtre) ; les trois autres se posent PAR RAPPORT à lui, via ("relatif_arme", ...) :
    #   la référence est le RMS MESURÉ de la famille chacal normalisée (garde-pic comprise), pas
    #   un placeholder — l'ancre est la voix réelle, pas une formule.
    "shot_chacal":    ("placeholder", "trench_shot", 0.18),
    "shot_vipere":    ("relatif_arme", "shot_chacal", -2.0),   # pistolet : léger
    "shot_frelon":    ("relatif_arme", "shot_chacal", -3.0),   # mitraille : la RÉPÉTITION fait le poids
    "shot_condor":    ("relatif_arme", "shot_chacal", 2.0),    # le calibre (garde-pic -1,5 dBFS famille)
    "laser_warn":     ("relatif_arme", "shot_chacal", -18.0),  # très discret : ambiance côté cible
}

# =================================================================================================
# PROFIL « FUSIL DE TRANCHÉE » (§3.2) — l'équivalent de WEAPON_PROFILES pour NOTRE arme unique.
# Entre `ak` et `shotgun` de la référence : corps 120 -> 45 Hz, crack 1,6-2,2 kHz, queue extérieure
# 0,4-0,6 s, et la couche MÉCANIQUE FORTE (culasse manuelle) qui est notre signature.
# =================================================================================================
PROFIL_FUSIL = {
    "bodyF": 120.0, "bodyF2": 45.0, "bodyDecay": 0.105,
    "subF": 50.0, "subDecay": 0.16,
    "crackF": 1900.0, "crackQ": 0.9, "crackDecay": 0.068,
    "drive": 7.5, "asym": 0.5,
    "midF": 700.0, "midDecay": 0.058,
    "tailDecay": 0.50, "tailF": 4000.0, "tailEndF": 500.0,
    "mechDelay": 0.030, "mechLevel": 0.62, "mechPartials": (1250.0, 2150.0, 3450.0),
    "echo": (0.16, 0.09),          # gains des 2 réflexions de tranchée (valeurs historiques)
    "phase_sub": 0.0,              # phase de départ du sub (0.0 = comportement historique exact)
    "pic_crack": 1.0,              # trim du PIC d'enveloppe du crack (1.0 = historique)
    "gain_sub": 1.0,               # trim de la couche sub (1.0 = historique)
}

# =================================================================================================
# LES 4 VOIX D'ARMES (§3.6, ajout 2026-08-26) — l'équivalent des WEAPON_PROFILES de la référence,
# UNE voix PAR arme de `TRENCH_WEAPONS` (backend/api/game/trench_sim.py, relu ce jour). Une seule
# voix aplatissait les 4 mécaniques ; ici chaque profil transpose le patron de la référence qui
# correspond au RÔLE de l'arme — les fréquences/enveloppes viennent de `weapons.js`, l'écho de
# tranchée est le nôtre. Les `trench_shot_1..6` (PROFIL_FUSIL) restent le repli générique.
# =================================================================================================
PROFILS_ARMES: dict = {
    # VIPÈRE (pistolet, 1 proj/0,9 s, 12 dég) — patron `pistol` : sec, claquant, léger. Corps haut
    # (186 Hz) et BREF, crack ~2,7 kHz très court, mécanique menue et rapprochée. L'écho reste
    # discret : une arme de poing ne remplit pas la tranchée.
    "vipere": {
        "bodyF": 186.0, "bodyF2": 84.0, "bodyDecay": 0.05,
        "subF": 92.0, "subDecay": 0.07,
        "crackF": 2750.0, "crackQ": 1.15, "crackDecay": 0.035,
        "drive": 4.5, "asym": 0.28,
        "midF": 950.0, "midDecay": 0.03,
        "tailDecay": 0.16, "tailF": 6800.0, "tailEndF": 1000.0,
        "mechDelay": 0.038, "mechLevel": 0.46, "mechPartials": (2450.0, 4200.0, 6900.0),
        "echo": (0.12, 0.06),
        "phase_sub": 0.0, "pic_crack": 1.0, "gain_sub": 1.0,
    },
    # FRELON (mitraillette : rafale de 3 espacés de 2 ticks = 100 ms, 5 dég) — patron `smg` :
    # détonation LÉGÈRE et VIVE. Corps 172 Hz TRÈS bref, crack ~3 kHz, queue courte (0,19 s) et
    # écho réduit : c'est la RÉPÉTITION à 100 ms qui fait la mitraille — chaque coup doit rester
    # court et net, sinon trois détonations se chevauchent en bouillie.
    "frelon": {
        "bodyF": 172.0, "bodyF2": 72.0, "bodyDecay": 0.06,
        "subF": 78.0, "subDecay": 0.08,
        "crackF": 3050.0, "crackQ": 1.05, "crackDecay": 0.04,
        "drive": 5.0, "asym": 0.30,
        "midF": 900.0, "midDecay": 0.035,
        "tailDecay": 0.19, "tailF": 6200.0, "tailEndF": 900.0,
        "mechDelay": 0.021, "mechLevel": 0.50, "mechPartials": (2200.0, 3900.0, 6300.0),
        "echo": (0.09, 0.045),
        # Sub AMINCI (−7 dB) : la queue du sub (~104 ms) retombe EXACTEMENT sur le coup suivant
        # de la rafale (burst_gap 2 ticks = 100 ms) — à trois coups superposés, les subs
        # s'additionnent en boue. Trimé, la rafale reste NETTE. (Le grave restant vient du corps
        # et de son octave basse — c'est le contrôle inter-armes qui le borne face au condor.)
        "phase_sub": 0.0, "pic_crack": 1.0, "gain_sub": 0.45,
    },
    # CHACAL (fusil d'assaut : rafale de 2, 8 dég) — la voix « fusil de tranchée » actuelle
    # recalibrée UN PEU PLUS NERVEUSE (patron `rifle`/`ak` : le corps monte 120→132 Hz, le crack
    # 1900→2100 Hz, décroissances et queue raccourcies, mécanique un rien plus prompte). C'est
    # l'ANCRE de niveau de la famille (POLITIQUE_NIVEAU).
    "chacal": {
        "bodyF": 132.0, "bodyF2": 50.0, "bodyDecay": 0.095,
        "subF": 54.0, "subDecay": 0.14,
        "crackF": 2100.0, "crackQ": 0.92, "crackDecay": 0.062,
        "drive": 7.0, "asym": 0.45,
        "midF": 730.0, "midDecay": 0.052,
        "tailDecay": 0.42, "tailF": 4400.0, "tailEndF": 560.0,
        "mechDelay": 0.027, "mechLevel": 0.58, "mechPartials": (1320.0, 2260.0, 3560.0),
        "echo": (0.16, 0.09),
        "phase_sub": 0.0, "pic_crack": 1.0, "gain_sub": 1.0,
    },
    # CONDOR (précision : 30 dég, laser 0,5 s avant le tir) — patron `sniper` : le CALIBRE
    # s'entend. Corps 96 Hz aux décroissances LONGUES, crack bas (1,3 kHz) saturé fort, queue
    # ~0,9 s, mécanique LOURDE et TARDIVE (0,19 s : la culasse d'un fusil long), écho de
    # tranchée le plus présent des quatre — c'est lui qui remplit le no man's land.
    "condor": {
        "bodyF": 96.0, "bodyF2": 34.0, "bodyDecay": 0.16,
        "subF": 38.0, "subDecay": 0.24,
        "crackF": 1320.0, "crackQ": 0.80, "crackDecay": 0.11,
        "drive": 10.0, "asym": 0.55,
        "midF": 470.0, "midDecay": 0.10,
        "tailDecay": 0.90, "tailF": 3300.0, "tailEndF": 380.0,
        "mechDelay": 0.19, "mechLevel": 0.65, "mechPartials": (1150.0, 2050.0, 3400.0),
        "echo": (0.20, 0.12),
        # Anti-crête (mesuré) : le pic de famille vit à ~4 ms, où les premiers ventres du
        # sub et du corps s'empilent avec l'attaque du crack. On DÉCALE la phase du sub
        # (affaire de phase pure : spectre et RMS inchangés) et on trime le pic du crack —
        # crête 23,4 -> 21,3 dB, ce qui laisse le +2 dB de POLITIQUE_NIVEAU passer sous la
        # garde-pic à 0,15 dB près (sans quoi la garde mangeait 2,3 dB du calibre).
        "phase_sub": 1.5 * math.pi, "pic_crack": 0.8, "gain_sub": 1.0,
    },
}


def graine(nom: str) -> np.random.Generator:
    """RNG déterministe par nom de fichier : crc32, PAS hash() (randomisé par processus)."""
    return np.random.Generator(np.random.PCG64(zlib.crc32(nom.encode("utf-8"))))


def semis(n: float) -> float:
    """Rapport de demi-tons — le jitter de hauteur s'exprime musicalement (dsp.js::semis)."""
    return 2.0 ** (n / 12.0)


# =================================================================================================
# BRIQUES DSP (transposition offline de dsp.js)
# =================================================================================================

def _rbj(ftype: str, freq: float, q: float, gain_db: float = 0.0):
    """Coefficients biquad RBJ (Audio EQ Cookbook). Fréquence bornée comme dsp.js::biquad."""
    f = min(max(freq, 10.0), SR * 0.45)
    w = TAU * f / SR
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2.0 * max(q, 1e-3))
    if ftype == "lowpass":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif ftype == "highpass":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif ftype == "bandpass":               # gain crête 0 dB (comme le bandpass Web Audio)
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif ftype == "peaking":
        A = 10.0 ** (gain_db / 40.0)
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    else:
        raise ValueError("type de biquad inconnu : %s" % ftype)
    a0 = a[0]
    return ([bi / a0 for bi in b], [1.0, a[1] / a0, a[2] / a0])


def _df2t_python(b, a, x: np.ndarray, zi: np.ndarray):
    """Repli SANS scipy : filtre en forme directe II transposée, boucle Python (§3.1 — offline,
    1-2 s à 44,1 kHz : acceptable). Même contrat que scipy.signal.lfilter(b, a, x, zi=zi).
    ⚠️ Accepte les ordres 1 ET 2 : les bruits rose/brun et l'AR(1) des références sont des
    UN-PÔLES (b=[g], a=[1, -p]) — b/a sont complétés à 3 coefficients (absents = 0), sinon le
    dépaquetage plantait et le repli ne produisait RIEN sur une machine sans scipy."""
    b = tuple(b) + (0.0,) * (3 - len(b))
    a = tuple(a) + (0.0,) * (3 - len(a))
    y = np.empty_like(x)
    z1, z2 = float(zi[0]), float(zi[1])
    b0, b1, b2 = b
    a1, a2 = a[1], a[2]
    for i in range(len(x)):
        xi = float(x[i])
        yi = b0 * xi + z1
        z1 = b1 * xi - a1 * yi + z2
        z2 = b2 * xi - a2 * yi
        y[i] = yi
    return y, np.array([z1, z2])


def _lfilter(b, a, x: np.ndarray, zi: np.ndarray):
    if SCIPY_OK:
        return _scipy_lfilter(b, a, x, zi=zi)
    return _df2t_python(b, a, x, zi)


def biquad(x: np.ndarray, ftype: str, freq: float, q: float, gain_db: float = 0.0) -> np.ndarray:
    b, a = _rbj(ftype, freq, q, gain_db)
    y, _ = _lfilter(b, a, x, np.zeros(2))
    return y


def biquad_balaye(x: np.ndarray, ftype: str, ftraj: np.ndarray, q: float,
                  gain_db: float = 0.0, bloc: int = 64) -> np.ndarray:
    """Biquad à fréquence BALAYÉE : coefficients recalculés par bloc de 64 échantillons (~1,5 ms),
    état conservé entre blocs. C'est la transposition offline d'un `sweep()` sur biquad.frequency."""
    y = np.empty_like(x)
    zi = np.zeros(2)
    n = len(x)
    for i in range(0, n, bloc):
        j = min(i + bloc, n)
        f = float(ftraj[min(i + (j - i) // 2, n - 1)])
        b, a = _rbj(ftype, f, q, gain_db)
        y[i:j], zi = _lfilter(b, a, x[i:j], zi)
    return y


def traj_expo(n: int, f0: float, f1: float, dur: float) -> np.ndarray:
    """Trajectoire exponentielle f0 -> f1 sur `dur` s puis tenue à f1 — l'équivalent offline
    d'`exponentialRampToValueAtTime` (dsp.js::sweep)."""
    t = np.arange(n) / SR
    u = np.clip(t / max(dur, 1e-4), 0.0, 1.0)
    f0 = max(f0, 1e-3)
    f1 = max(f1, 1e-3)
    return f0 * (f1 / f0) ** u


def osc_sin(ftraj: np.ndarray) -> np.ndarray:
    return np.sin(np.cumsum(TAU * ftraj / SR))


def osc_tri(ftraj: np.ndarray) -> np.ndarray:
    return (2.0 / math.pi) * np.arcsin(np.sin(np.cumsum(TAU * ftraj / SR)))


def env_hit(n: int, pic: float, decroissance: float, t0: float = 0.0) -> np.ndarray:
    """Attaque instantanée + décroissance exponentielle vers le plancher (dsp.js::hit)."""
    p = max(pic, FLOOR * 4.0)
    t = np.arange(n) / SR - t0
    e = np.zeros(n)
    m = (t >= 0.0) & (t <= decroissance)
    e[m] = p * (FLOOR / p) ** (t[m] / max(decroissance, 1e-4))
    return e


def env_ad(n: int, pic: float, attaque: float, decroissance: float, t0: float = 0.0) -> np.ndarray:
    """Attaque/décroissance exponentielles (dsp.js::ad). Attaque < 0,8 ms = saut direct au pic."""
    p = max(pic, FLOOR * 4.0)
    t = np.arange(n) / SR - t0
    e = np.zeros(n)
    if attaque > 0.0008:
        ma = (t >= 0.0) & (t < attaque)
        e[ma] = FLOOR * (p / FLOOR) ** (t[ma] / attaque)
    else:
        attaque = 0.0
    md = (t >= attaque) & (t <= attaque + decroissance)
    e[md] = p * (FLOOR / p) ** ((t[md] - attaque) / max(decroissance, 1e-4))
    return e


def saturation(x: np.ndarray, drive: float, asym: float) -> np.ndarray:
    """Saturation tanh asymétrique (dsp.js::saturationCurve) : `asym` ajoute les harmoniques
    paires — le « chuff » d'une bouche de canon, pas un fuzz symétrique."""
    k = 1.0 + drive
    xa = x + asym * x * x * np.sign(x) * 0.5
    return np.tanh(k * xa) / math.tanh(k)


def bruit_blanc(rng: np.random.Generator, n: int) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n)


def bruit_rose(rng: np.random.Generator, n: int) -> np.ndarray:
    """Filtre « économique » de Paul Kellet (dsp.js::fillNoise 'pink') : 6 un-pôles + terme retardé."""
    w = rng.uniform(-1.0, 1.0, n)
    poles = [(0.99886, 0.0555179), (0.99332, 0.0750759), (0.969, 0.153852),
             (0.8665, 0.3104856), (0.55, 0.5329522), (-0.7616, -0.016898)]
    out = w * 0.5362
    for (p, g) in poles:
        y, _ = _lfilter([g], [1.0, -p], w, np.zeros(1) if SCIPY_OK else np.zeros(2))
        out = out + y
    out[1:] += w[:-1] * 0.115926        # b6 : le blanc RETARDÉ d'un échantillon
    return out * 0.11


def bruit_brun(rng: np.random.Generator, n: int) -> np.ndarray:
    """Intégrateur qui fuit (dsp.js 'brown') : -6 dB/oct, la matière du vent et du roulement."""
    w = rng.uniform(-1.0, 1.0, n)
    y, _ = _lfilter([0.019 * 0.9985], [1.0, -0.9985], w, np.zeros(1) if SCIPY_OK else np.zeros(2))
    return y * 5.2


def resonateur_frappe(rng: np.random.Generator, n: int, t0: float, partiels,
                      duree_excitation: float = 0.004) -> np.ndarray:
    """Banque de passe-bandes à Q élevé excitée par un burst de bruit (dsp.js::struckResonator) :
    le modèle bon marché d'un objet métallique frappé. `partiels` = [(f, q, g, decroissance)].
    Le rattrapage sqrt(q) compense la bande passante f/Q — sans lui, tout métal serait inaudible."""
    excitation = bruit_blanc(rng, n) * env_hit(n, 1.0, duree_excitation, t0)
    out = np.zeros(n)
    for (f, q, g, dec) in partiels:
        out += biquad(excitation, "bandpass", f, q) * env_hit(n, g * math.sqrt(q) * 0.85, dec, t0)
    return out


def ping(n: int, t0: float, f: float, tau: float, amp: float, phase: float = 0.0) -> np.ndarray:
    """Sinusoïde amortie déclenchée à t0 — pour les TINTEMENTS longs (douille) : un biquad Q~50
    ne sonne que ~5 ms, un vrai tintement de laiton en demande 50-150. Synthèse directe."""
    t = np.arange(n) / SR - t0
    out = np.zeros(n)
    m = t >= 0.0
    out[m] = amp * np.sin(TAU * f * t[m] + phase) * np.exp(-t[m] / max(tau, 1e-4))
    return out


def grains(rng: np.random.Generator, n: int, t0: float, taux0: float, tau_taux: float,
           w_lo: float, w_hi: float, amp: float = 1.0) -> np.ndarray:
    """Train de grains façon dsp.js 'crackle', mais à DENSITÉ DÉCROISSANTE (Poisson aminci) :
    chaque grain est un ping à deux pôles (matière, pas un clic), le taux décroît en exp —
    l'oreille entend la pluie de terre RALENTIR (rôle §8.141 de `trench_debris`)."""
    out = np.zeros(n)
    t = t0
    fin = n / SR
    while True:
        t += rng.exponential(1.0 / max(taux0, 1e-3))
        if t >= fin:
            break
        if rng.uniform() > math.exp(-(t - t0) / max(tau_taux, 1e-3)):
            continue                     # amincissement : le taux réel suit l'exponentielle
        i0 = int(t * SR)
        w = rng.uniform(w_lo, w_hi)      # pulsation en rad/échantillon (matière du grain)
        dec = math.exp(-rng.uniform(0.004, 0.05))
        a = rng.uniform(0.25, 1.0) * (1.8 if rng.uniform() < 0.12 else 0.7) * amp
        k = np.arange(min(220, n - i0))
        out[i0:i0 + len(k)] += np.sin(w * k) * a * (dec ** k)
    return out


def ajout_retarde(dst: np.ndarray, src: np.ndarray, retard: float, gain: float) -> None:
    """Ajoute `src` dans `dst` avec un retard en secondes (réflexions, rebond de sol)."""
    d = int(retard * SR)
    m = min(len(src), len(dst) - d)
    if m > 0:
        dst[d:d + m] += src[:m] * gain


# =================================================================================================
# RÉFÉRENCES DE NIVEAU — les placeholders GDScript re-synthétisés (formules transposées
# d'audio_manager.gd ; graines numpy : la STATISTIQUE de niveau est la même, pas les échantillons).
# =================================================================================================

def _ar1(rng: np.random.Generator, n: int, alpha: float) -> np.ndarray:
    """`lp = lerpf(lp, bruit, alpha)` de GDScript = filtre AR(1) : y = (1-a)y' + a*bruit."""
    w = rng.uniform(-1.0, 1.0, n)
    y, _ = _lfilter([alpha], [1.0, -(1.0 - alpha)], w, np.zeros(1) if SCIPY_OK else np.zeros(2))
    return y


def _lerp_clamp(t: np.ndarray, a: float, b: float, dur: float) -> np.ndarray:
    return a + (b - a) * np.clip(t / dur, 0.0, 1.0)


def _ref_blip(freq: float, dur: float, vol: float) -> np.ndarray:
    """_make_blip (l.654) : sinus + harmonique légère, enveloppe exp(-18t) * min(1, 220t)."""
    t = np.arange(int(SR * dur)) / SR
    env = np.exp(-t * 18.0) * np.minimum(1.0, t * 220.0)
    corps = np.sin(TAU * freq * t) + 0.25 * np.sin(TAU * freq * 2.0 * t)
    return corps * env * vol


def _ref_trench_shot() -> np.ndarray:
    """_make_trench_shot (l.776) : corps 220->70 Hz exp(-42t)*0,55 + claque AR(0,72) exp(-55t)*0,7."""
    n = int(SR * 0.18)
    t = np.arange(n) / SR
    rng = graine("ref_trench_shot")
    corps = np.sin(TAU * _lerp_clamp(t, 220.0, 70.0, 0.05) * t) * np.exp(-t * 42.0)
    claque = _ar1(rng, n, 0.72)
    return corps * 0.55 + claque * np.exp(-t * 55.0) * 0.7


def _ref_trench_step() -> np.ndarray:
    """_make_trench_step (l.798) : thump 120->55 Hz *0,42 + bruit AR(0,10) exp(-38t)*0,30."""
    n = int(SR * 0.12)
    t = np.arange(n) / SR
    rng = graine("ref_trench_step")
    thump = np.sin(TAU * _lerp_clamp(t, 120.0, 55.0, 0.04) * t) * np.exp(-t * 46.0)
    return thump * 0.42 + _ar1(rng, n, 0.10) * np.exp(-t * 38.0) * 0.30


def _ref_explosion() -> np.ndarray:
    """_make_explosion (l.860) : sub 90->32 Hz + burst à coupure qui se referme + débris épars."""
    n = int(SR * 0.7)
    rng = graine("ref_explosion")
    s = np.zeros(n)
    lp = 0.0
    for i in range(n):
        t = i / SR
        f = 90.0 + (32.0 - 90.0) * min(t / 0.14, 1.0)
        sub = math.sin(TAU * f * t) * math.exp(-t * 9.0) * 0.62
        cut = min(max(0.55 * math.exp(-t * 4.5), 0.03), 0.55)
        lp += cut * (rng.uniform(-1.0, 1.0) - lp)
        burst = lp * math.exp(-t * 5.5) * 0.5
        debris = 0.0
        if t > 0.12 and rng.uniform() < 0.012:
            debris = rng.uniform(-1.0, 1.0) * 0.18
        s[i] = sub + burst + debris * math.exp(-t * 2.0)
    return s


def _ref_trench_explosion_far() -> np.ndarray:
    """_make_trench_explosion_far (l.819) : montée molle 0,06 s, sub 70->30, roulement AR(0,05)."""
    n = int(SR * 0.95)
    t = np.arange(n) / SR
    rng = graine("ref_trench_explosion_far")
    swell = np.clip(t / 0.06, 0.0, 1.0)
    sub = np.sin(TAU * _lerp_clamp(t, 70.0, 30.0, 0.25) * t) * np.exp(-t * 4.2)
    return swell * (sub * 0.5 + _ar1(rng, n, 0.05) * np.exp(-t * 3.0) * 0.55)


def _ref_trench_debris() -> np.ndarray:
    """_make_trench_debris (l.840) : grains tenus décroissants *0,86 par échantillon, *0,42."""
    n = int(SR * 0.55)
    rng = graine("ref_trench_debris")
    s = np.zeros(n)
    g = 0.0
    for i in range(n):
        t = i / SR
        if rng.uniform() < 0.035 * math.exp(-t * 3.4):
            g = rng.uniform(-1.0, 1.0) * rng.uniform(0.25, 1.0)
        g *= 0.86
        s[i] = g * 0.42
    return s


_REFERENCES_CACHE: dict = {}


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def en_db(v: float) -> float:
    return 20.0 * math.log10(max(v, 1e-9))


def reference_rms(nom: str) -> float:
    """RMS (linéaire) du placeholder GDScript re-synthétisé — calculé une fois, mis en cache."""
    if not _REFERENCES_CACHE:
        _REFERENCES_CACHE.update({
            "trench_shot": rms(_ref_trench_shot()),
            "trench_step": rms(_ref_trench_step()),
            "explosion": rms(_ref_explosion()),
            "trench_explosion_far": rms(_ref_trench_explosion_far()),
            "trench_debris": rms(_ref_trench_debris()),
            "blip_grenade": rms(_ref_blip(420.0, 0.09, 0.18)),
            "blip_hitmarker": rms(_ref_blip(1900.0, 0.05, 0.16)),
            "blip_hit": rms(_ref_blip(180.0, 0.14, 0.30)),
            "blip_refused": rms(_ref_blip(140.0, 0.045, 0.22)),
        })
    return _REFERENCES_CACHE[nom]


# =================================================================================================
# LES SONS — recettes par famille
# =================================================================================================

def synth_shot(nom: str, sans_transitoire: bool = False, profil: dict | None = None,
               sans_corps: bool = False) -> np.ndarray:
    """LE TIR, 7 couches (§3.2, transposition du commentaire d'en-tête de weapons.js).
    La couche 7 (boom lointain) n'existe que pour les variantes _far d'un événement distant :
    la liste fermée §3.3 n'a PAS de tir _far (duel frontal à 9 m), elle vit donc dans
    `trench_explosion_far`. `profil` (§3.6) : une des 4 voix de PROFILS_ARMES — par défaut
    PROFIL_FUSIL, la voix générique historique (le flux RNG et les formules sont INCHANGÉS :
    trench_shot_1..6 restent bit-identiques). Contre-épreuves sabotage : `sans_transitoire`
    (couche 1 retirée) ; `sans_corps` (couche 2 corps+sub CALCULÉE mais non mélangée — le flux
    RNG est préservé : le fichier saboté est le fichier sain moins la couche 2 et moins la part
    de la couche 2 dans l'écho de tranchée, qui se construit sur le mix)."""
    rng = graine(nom)
    p = PROFIL_FUSIL if profil is None else profil
    # Le « slot » round-robin de la variante (§3.2) : désaccords en demi-tons, Q, queue, tilt.
    v_body = semis(rng.uniform(-1.0, 1.0))
    v_crack = semis(rng.uniform(-1.7, 1.7))       # 1900 Hz * [0,906..1,103] = 1722..2096 Hz
    v_q = rng.uniform(0.85, 1.15)
    v_tail = rng.uniform(0.85, 1.15)              # 0,50 s * [0,85..1,15] = 0,425..0,575 s (§3.3)
    v_drive = rng.uniform(0.85, 1.2)
    v_mid = semis(rng.uniform(-2.0, 2.0))
    v_mech = rng.uniform(0.8, 1.25)
    v_tilt = rng.uniform(-2.5, 2.5)               # dB — variance « micro/position » du slot

    duree_queue = p["tailDecay"] * v_tail
    n = int((duree_queue * 1.3 + 0.14) * SR)
    t = np.arange(n) / SR
    mix = np.zeros(n)

    # --- 1. TRANSITOIRE (< 1 ms) : « sans lui, le fusil sonne comme un pétard ». -----------------
    if not sans_transitoire:
        clic = biquad(bruit_blanc(rng, n), "highpass", 2600.0, 0.6)
        clic = biquad(clic, "peaking", 6200.0 * v_crack, 1.1, 8.0 + v_tilt)
        mix += clic * env_hit(n, 0.9, 0.0075)
        # Le cycle unique de triangle ~1,7 kHz : le « snap » que le bruit seul ne produit pas.
        mix += osc_tri(np.full(n, 1750.0 * v_crack)) * env_hit(n, 0.35, 0.004)

    # --- 2. CORPS + SUB : le coup dans la poitrine. ----------------------------------------------
    # (Toujours CALCULÉE — même sous sabotage `sans_corps`, pour préserver le flux RNG — puis
    # mélangée seulement si la couche n'est pas retirée.)
    corps = osc_sin(traj_expo(n, p["bodyF"] * v_body, p["bodyF2"] * v_body, p["bodyDecay"] * 1.4))
    corps += osc_tri(traj_expo(n, p["bodyF"] * v_body * 0.5, p["bodyF2"] * v_body * 0.55,
                               p["bodyDecay"] * 1.6))
    corps *= env_ad(n, 0.85, 0.0012, p["bodyDecay"] * rng.uniform(0.9, 1.15))
    corps = saturation(corps, p["drive"] * v_drive * 0.5, p["asym"])
    # `phase_sub` (§3.6, anti-crête du condor) : une affaire de PHASE pure — spectre et RMS
    # inchangés, seul l'empilement d'attaque bouge. À 0.0 : formule historique exacte.
    traj_sub = traj_expo(n, p["subF"] * v_body * 1.5, p["subF"] * v_body * 0.8, p["subDecay"])
    sub = np.sin(np.cumsum(TAU * traj_sub / SR) + p["phase_sub"])
    if not sans_corps:
        mix += biquad(corps, "lowpass", 2200.0, 0.9)
        mix += sub * env_ad(n, 0.5 * p["gain_sub"], 0.004, p["subDecay"] * 1.3)

    # --- 3. CRACK : « le caractère du calibre vit ici » — bande qui GLISSE vers le bas. ----------
    fc = traj_expo(n, p["crackF"] * v_crack * 1.35, p["crackF"] * v_crack * 0.8,
                   p["crackDecay"] * 2.0)
    crack = biquad_balaye(bruit_blanc(rng, n), "bandpass", fc, p["crackQ"] * v_q)
    crack = biquad(crack, "peaking", p["crackF"] * v_crack * 1.9, 1.6, 6.0 + v_tilt)
    crack = saturation(crack, p["drive"] * v_drive, p["asym"] * 0.6)
    mix += crack * env_ad(n, 1.05 * p["pic_crack"], 0.0015, p["crackDecay"] * rng.uniform(0.85, 1.2))

    # --- 4. COLLE MÉDIANE : soude corps et crack. ------------------------------------------------
    colle = biquad(bruit_rose(rng, n), "bandpass", p["midF"] * v_mid, 1.1)
    mix += colle * env_ad(n, 0.5, 0.002, p["midDecay"] * 1.4)

    # --- 5. QUEUE : passe-bas qui TOMBE 4 kHz -> 500 Hz — « ce que le terrain entend ». ----------
    queue = biquad(bruit_rose(rng, n), "highpass", 160.0, 0.7)
    queue = biquad_balaye(queue, "lowpass", traj_expo(n, p["tailF"], p["tailEndF"], duree_queue), 0.6)
    mix += queue * env_ad(n, 0.42, 0.006, duree_queue)

    # --- 6. MÉCANIQUE (FORTE — culasse manuelle, notre signature §3.2). --------------------------
    md = p["mechDelay"] * rng.uniform(0.85, 1.2)
    lvl = p["mechLevel"] * v_mech
    p0, p1, p2 = p["mechPartials"]
    mix += resonateur_frappe(rng, n, md, [
        (p0 * rng.uniform(0.96, 1.05), 26, 0.5 * lvl, 0.055),
        (p1 * rng.uniform(0.96, 1.05), 20, 0.34 * lvl, 0.035),
        (p2 * rng.uniform(0.96, 1.05), 14, 0.2 * lvl, 0.02)], 0.0035)
    # Retour en batterie : un second clac plus doux, un peu plus tard.
    mix += resonateur_frappe(rng, n, md * 2.1, [
        (p0 * 0.88, 18, 0.3 * lvl, 0.04),
        (p1 * 1.12, 12, 0.16 * lvl, 0.022)], 0.003)
    souffle = biquad(bruit_blanc(rng, n), "bandpass", 4200.0 * rng.uniform(0.9, 1.1), 1.4)
    mix += souffle * env_ad(n, 0.12 * lvl, 0.006, 0.05, md * 0.6)

    # --- Écho de tranchée discret (§3.2 couche 5, ⚙ admis) : 2 réflexions 30-80 ms, atténuées,
    #     passe-bas — les parois de la tranchée, pas une convolution. Gains PAR PROFIL (§3.6 :
    #     le frelon reste net à 100 ms de cadence, le condor remplit le no man's land). ------------
    tot = biquad(mix * env_hit(n, 1.0, 0.12), "lowpass", 2400.0, 0.7)
    d1 = rng.uniform(0.032, 0.055)
    d2 = d1 + rng.uniform(0.020, 0.035)           # d1+0,020..d1+0,035 : borne haute < 0,090 s
    ajout_retarde(mix, tot, d1, p["echo"][0])
    ajout_retarde(mix, tot, d2, p["echo"][1])
    return mix


def synth_laser_warn(nom: str) -> np.ndarray:
    """LE TÉLÉGRAPHE DU CONDOR (§3.6) : bourdonnement MONTANT discret, joué côté CIBLE pendant
    `laser_lead_ticks` (10 ticks = 0,5 s au registre serveur ; le fichier dure 0,62 s — le danger
    annoncé doit S'ENTENDRE, pas seulement se voir). Deux sinusoïdes BATTANTES (écart fixe 2,8 Hz,
    le battement pulse doucement sur toute la montée) + ombre d'octave désaccordée + montée douce
    138 -> 205 Hz + fondu d'entrée 0,12 s et gonflement lent : un avertissement d'AMBIANCE.
    PAS un buzzer agressif : tout passe sous un passe-bas ~900 Hz, aucun transitoire."""
    rng = graine(nom)
    dur = 0.62
    n = int(dur * SR)
    t = np.arange(n) / SR
    ftraj = traj_expo(n, 138.0, 205.0, dur)
    # Les deux voix battantes : écart FIXE en Hz, le battement reste ~2,8 Hz pendant la montée.
    mix = osc_sin(ftraj) * 0.50
    mix += osc_sin(ftraj + 2.8) * 0.50
    # Ombre d'octave légèrement désaccordée : le « shimmer » du faisceau, à peine là.
    mix += osc_sin(ftraj * 2.01) * 0.16
    # Souffle très doux sous 600 Hz : l'air autour du faisceau.
    mix += biquad(bruit_rose(rng, n), "lowpass", 600.0, 0.7) * 0.06
    # Adoucissement global — la promesse « pas un buzzer » est tenue par construction.
    mix = biquad(mix, "lowpass", 900.0, 0.7)
    # Fondu d'entrée + gonflement lent (la menace s'approche) + sortie brève (le tir la coupe).
    env = np.clip(t / 0.12, 0.0, 1.0) * np.clip((dur - t) / 0.06, 0.0, 1.0)
    env *= 0.65 + 0.35 * np.clip(t / dur, 0.0, 1.0)
    return mix * env


def synth_whizz(nom: str, idx: int) -> np.ndarray:
    """LE SIFFLEMENT DE BALLE (§3.3, weapons.js::bulletWhizz) : passe-bande balayé VIOLENT
    ~4,5 kHz -> ~1,2 kHz en 60-130 ms (Doppler d'un projectile à Mach 2,5) + snap passe-haut
    du front de choc. Taillé pour les tirs adverses qui MANQUENT."""
    rng = graine(nom)
    dur = (0.068, 0.088, 0.108, 0.126)[idx] * rng.uniform(0.95, 1.05)
    n = int((dur * 2.0 + 0.08) * SR)
    f0 = rng.uniform(4300.0, 5200.0)
    f1 = rng.uniform(1050.0, 1450.0)
    siffle = biquad_balaye(bruit_blanc(rng, n), "bandpass", traj_expo(n, f0, f1, dur),
                           3.2 * rng.uniform(0.85, 1.15))
    mix = siffle * env_ad(n, 1.5, 0.004, dur)
    snap = biquad(bruit_blanc(rng, n), "highpass", 4000.0, 0.7)
    mix += snap * env_hit(n, 0.85, 0.006)
    return mix


def synth_explosion_near(nom: str) -> np.ndarray:
    """L'EXPLOSION PROCHE (§3.3) : sub dans la poitrine + CLAQUEMENT + débris serrés. C'est le son
    qui accompagne une secousse de caméra — il doit la justifier (rôle §8.141 conservé)."""
    rng = graine(nom)
    d = semis(rng.uniform(-1.0, 1.0))
    n = int((1.15 + rng.uniform(-0.05, 0.10)) * SR)
    mix = np.zeros(n)
    # Transitoire du front d'onde.
    mix += biquad(bruit_blanc(rng, n), "highpass", 1800.0, 0.7) * env_hit(n, 0.8, 0.006)
    # Claquement : bande 3 kHz -> 1,2 kHz saturée — la partie que le _far n'aura PAS.
    claque = biquad_balaye(bruit_blanc(rng, n), "bandpass",
                           traj_expo(n, 3000.0 * d, 1200.0 * d, 0.08), 1.1)
    mix += saturation(claque, 8.0, 0.5) * env_ad(n, 1.0, 0.001, 0.06)
    # Sub : 95 -> 30 Hz, légèrement saturé (les harmoniques donnent le « dans la poitrine »).
    sub = osc_sin(traj_expo(n, 95.0 * d, 30.0 * d, 0.20))
    mix += saturation(sub * env_ad(n, 1.0, 0.002, 0.35), 3.0, 0.4)
    # Souffle : rose sous un passe-bas qui se referme.
    souffle = biquad_balaye(bruit_rose(rng, n), "lowpass", traj_expo(n, 3500.0, 260.0, 0.5), 0.8)
    mix += souffle * env_ad(n, 0.8, 0.003, 0.45)
    # Débris SERRÉS : rafale de grains dense qui s'éteint vite (près = tout retombe autour).
    serres = grains(rng, n, 0.06, 500.0, 0.16, 0.10, 0.48)
    mix += biquad(serres, "highpass", 500.0, 0.7) * 0.30
    # Traîne grave.
    mix += biquad(bruit_brun(rng, n), "lowpass", 240.0, 0.7) * env_ad(n, 0.5, 0.010, 0.70)
    return mix


def synth_explosion_far(nom: str) -> np.ndarray:
    """L'EXPLOSION LOINTAINE (§3.2 couche 7 + rôle §8.141) : houle grave + REBOND DE SOL discret
    20-100 ms après — SANS claquement. L'air mange l'aigu : c'est le TIMBRE qui dit la distance,
    pas le volume (le contrôle de bande « aigus ABSENTS » le prouve)."""
    rng = graine(nom)
    d = semis(rng.uniform(-1.0, 1.0))
    n = int((1.40 + rng.uniform(-0.05, 0.12)) * SR)
    mix = np.zeros(n)
    # Houle : bruit brun sous un passe-bas qui descend, attaque MOLLE (front d'onde émoussé).
    houle = biquad_balaye(bruit_brun(rng, n), "lowpass", traj_expo(n, 380.0 * d, 170.0 * d, 0.5), 0.8)
    mix += houle * env_ad(n, 1.0, 0.050, 0.95)
    # Sub adouci.
    sub = osc_sin(traj_expo(n, 66.0 * d, 28.0 * d, 0.30))
    mix += sub * env_ad(n, 0.55, 0.030, 0.55)
    # Rebond de sol : UNE claque sourde discrète après le son direct — ce qui fait lire
    # « extérieur et lointain » (weapons.js couche 7).
    rebond = biquad(bruit_rose(rng, n), "lowpass", 800.0, 0.7)
    mix += rebond * env_ad(n, 0.40, 0.005, 0.16, 0.02 + rng.uniform(0.0, 0.08))
    # Roulement médian très doux.
    mix += biquad(bruit_rose(rng, n), "lowpass", 500.0, 0.7) * env_ad(n, 0.18, 0.060, 0.80)
    return mix


def synth_shell(nom: str) -> np.ndarray:
    """LA DOUILLE (§3.3, consommée par le LOT D) : tintements de laiton — sinusoïdes amorties
    DIRECTES (un biquad Q~50 ne sonne que ~5 ms, un tintement en demande 50-150) + rebonds."""
    rng = graine(nom)
    d = semis(rng.uniform(-0.8, 0.8))
    n = int(0.32 * SR)
    partiels = [(3350.0 * d * rng.uniform(0.98, 1.02), 0.075, 0.9),
                (5150.0 * d * rng.uniform(0.98, 1.02), 0.055, 0.6),
                (7420.0 * d * rng.uniform(0.98, 1.02), 0.040, 0.35)]
    mix = np.zeros(n)
    # 1er contact + 2 rebonds : amplitudes et hauteurs qui montent LÉGÈREMENT (la douille pivote).
    for (t0, g, dh) in ((0.002, 1.0, 1.0), (0.075 + rng.uniform(0.0, 0.02), 0.55, 1.04),
                        (0.16 + rng.uniform(0.0, 0.03), 0.28, 1.07)):
        for (f, tau, a) in partiels:
            mix += ping(n, t0, f * dh, tau * 0.8 if g < 1.0 else tau, a * g,
                        rng.uniform(0.0, TAU))
        # Micro-transitoire du contact (bruit très court, passe-haut).
        clic = biquad(bruit_blanc(rng, n), "highpass", 2500.0, 0.8)
        mix += clic * env_hit(n, 0.30 * g, 0.0025, t0)
    return mix


def synth_bolt(nom: str) -> np.ndarray:
    """LA CULASSE MANUELLE (§3.3) : cycle complet — clac d'ouverture, glissière, clac de fermeture
    plus fort, ressort. Réutilise la couche 6 du tir. Jouée à la CADENCE AUTORISÉE ; un tir refusé
    ne la joue JAMAIS (§8.141.9 : le refus, c'est `trench_refused`, rien d'autre)."""
    rng = graine(nom)
    n = int(0.42 * SR)
    p0, p1, p2 = PROFIL_FUSIL["mechPartials"]
    mix = np.zeros(n)
    # Ouverture.
    mix += resonateur_frappe(rng, n, 0.004, [
        (p0 * rng.uniform(0.97, 1.03), 24, 0.50, 0.05),
        (p1 * rng.uniform(0.97, 1.03), 18, 0.32, 0.032),
        (p2 * rng.uniform(0.97, 1.03), 13, 0.18, 0.018)], 0.0035)
    # Glissière : friction bande étroite qui descend, courte.
    glisse = biquad_balaye(bruit_blanc(rng, n), "bandpass",
                           traj_expo(n, 2900.0, 1800.0, 0.10), 2.0)
    mix += glisse * env_ad(n, 0.22, 0.012, 0.085, 0.070)
    # Fermeture : PLUS FORTE que l'ouverture (le verrouillage), partiels un peu plus bas.
    mix += resonateur_frappe(rng, n, 0.225, [
        (p0 * 0.92, 22, 0.62, 0.055),
        (p1 * 0.95, 16, 0.40, 0.035),
        (p2 * 0.90, 12, 0.22, 0.02)], 0.004)
    # Ressort/gaz après chaque clac.
    souffle = biquad(bruit_blanc(rng, n), "bandpass", 4100.0, 1.4)
    mix += souffle * env_ad(n, 0.07, 0.006, 0.04, 0.012)
    mix += souffle * env_ad(n, 0.09, 0.006, 0.05, 0.232)
    return mix


def synth_step(nom: str) -> np.ndarray:
    """LE PAS (§3.3) : rôle et niveau du placeholder CONSERVÉS (verdict §8.141 : il signale, il ne
    crie pas). Terre détrempée : thump talon + pose de pointe + matière très filtrée + 3 graviers."""
    rng = graine(nom)
    d = semis(rng.uniform(-0.7, 0.7))
    n = int(0.15 * SR)
    t = np.arange(n) / SR
    mix = np.zeros(n)
    # Talon : la formule du placeholder, désaccordée par variante.
    mix += osc_sin(traj_expo(n, 120.0 * d, 55.0 * d, 0.04)) * env_hit(n, 0.75, 0.055)
    # Pointe : second contact plus doux et un peu plus haut, 45-70 ms après.
    mix += osc_sin(traj_expo(n, 140.0 * d, 70.0 * d, 0.03)) * \
        env_hit(n, 0.38, 0.04, 0.045 + rng.uniform(0.0, 0.025))
    # Matière : bruit passe-bas fermé (la boue absorbe tout l'aigu).
    mix += biquad(bruit_blanc(rng, n), "lowpass", 320.0, 0.7) * np.exp(-t * 38.0) * 0.55
    # Trois graviers discrets (bande médiane, minuscules).
    mix += biquad(grains(rng, n, 0.005, 60.0, 0.05, 0.15, 0.42), "bandpass", 1400.0, 0.8) * 0.10
    return mix


def synth_debris(nom: str) -> np.ndarray:
    """LES RETOMBÉES (§3.3) : rôle conservé — crépitement épars qui RALENTIT (0,4 s après la
    détonation, timing géré par l'appelant). Grains de matière + deux mottes sourdes."""
    rng = graine(nom)
    n = int(0.55 * SR)
    mix = grains(rng, n, 0.0, 220.0, 0.28, 0.08, 0.50) * 0.55
    # Deux mottes plus grosses : thuds graves discrets dans la pluie.
    for (t0, f) in ((0.12, 110.0), (0.31, 88.0)):
        mix += osc_sin(np.full(n, f)) * env_hit(n, 0.30, 0.045, t0 + rng.uniform(0.0, 0.04))
    return mix


def synth_grenade(nom: str) -> np.ndarray:
    """LE DÉPART DU LANCER (§3.3) : rôle conservé (bref, mécanique — la goupille, le bras).
    Le blip 420 Hz du placeholder reste le corps ; s'y ajoutent la goupille et le geste."""
    rng = graine(nom)
    n = int(0.16 * SR)
    t = np.arange(n) / SR
    # Goupille : micro-tintement métallique, tout de suite.
    mix = resonateur_frappe(rng, n, 0.001, [(2600.0, 22, 0.16, 0.03), (4650.0, 15, 0.08, 0.018)],
                            0.002)
    # Corps : le blip du placeholder (sinus + harmonique légère).
    env = np.exp(-t * 18.0) * np.minimum(1.0, t * 220.0)
    mix += (np.sin(TAU * 420.0 * t) + 0.25 * np.sin(TAU * 840.0 * t)) * env * 0.9
    # Le bras : petit woosh d'air, bande qui descend.
    woosh = biquad_balaye(bruit_rose(rng, n), "bandpass", traj_expo(n, 950.0, 420.0, 0.11), 1.2)
    mix += woosh * env_ad(n, 0.55, 0.010, 0.10, 0.015)
    return mix


def synth_hitmarker(nom: str) -> np.ndarray:
    """MA TOUCHE CONFIRMÉE (§3.3, ⚙ retenue) : RETOUR D'INTERFACE, pas un son du monde. On garde le
    blip 1900 Hz lisible et bref ; on ajoute seulement une pointe métallique et un tic de texture."""
    rng = graine(nom)
    n = int(0.055 * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 18.0) * np.minimum(1.0, t * 220.0)
    mix = (np.sin(TAU * 1900.0 * t) + 0.25 * np.sin(TAU * 3800.0 * t)) * env
    mix += ping(n, 0.0, 2850.0, 0.022, 0.30)      # partiel 1,5x : le « cristal » de la confirmation
    tic = biquad(bruit_blanc(rng, n), "highpass", 3000.0, 0.8)
    mix += tic * env_hit(n, 0.10, 0.0015)
    return mix


def synth_hit(nom: str) -> np.ndarray:
    """LE COUP ENCAISSÉ (§3.3, ⚙ retenue) : grave et MAT, impossible à confondre avec un tir
    (aucun crack, aucun transitoire brillant). Blip 180 Hz + chute de hauteur + thud de chair."""
    rng = graine(nom)
    n = int(0.15 * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 16.0) * np.minimum(1.0, t * 200.0)
    mix = (osc_sin(traj_expo(n, 205.0, 160.0, 0.08)) +
           0.25 * osc_sin(traj_expo(n, 410.0, 320.0, 0.08))) * env
    mix += biquad(bruit_blanc(rng, n), "lowpass", 300.0, 0.7) * env_hit(n, 0.55, 0.05)
    return mix


def synth_refused(nom: str) -> np.ndarray:
    """LE GESTE REFUSÉ (§3.3, ⚙ retenue + §8.141.9) : il ne ressemble à AUCUN son d'action —
    l'oreille doit comprendre « rien n'a eu lieu ». Clic sec, grave, MORT (étouffé, sans queue)."""
    rng = graine(nom)
    n = int(0.05 * SR)
    mix = osc_sin(traj_expo(n, 150.0, 118.0, 0.03)) * env_hit(n, 0.9, 0.028)
    mix += biquad(bruit_blanc(rng, n), "lowpass", 520.0, 0.7) * env_hit(n, 0.5, 0.006)
    return mix


# =================================================================================================
# NORMALISATION (voir l'encadré « NIVEAUX ») + ÉCRITURE
# =================================================================================================

def _normaliser_famille(fam: str, sons: dict) -> dict:
    """1) RMS égalisé entre variantes (l'homogénéité ±1,5 dB du §3.4 devient exacte) ;
    2) gain de famille posé par la politique (placeholder, relatif, ou relatif_arme §3.6) ;
    3) garde-pic familiale à -1,5 dBFS (la relation de niveau ENTRE variantes est préservée)."""
    cible = POLITIQUE_NIVEAU[fam]
    moyenne = float(np.exp(np.mean([math.log(max(rms(x), 1e-9)) for x in sons.values()])))
    sons = {k: v * (moyenne / max(rms(v), 1e-9)) for k, v in sons.items()}
    if cible[0] == "placeholder":
        fenetre = int(cible[2] * SR)
        tete = float(np.mean([rms(x[:fenetre]) for x in sons.values()]))
        gain = reference_rms(cible[1]) / max(tete, 1e-9)
    elif cible[0] == "relatif_arme":
        # §3.6 : la référence est le RMS MESURÉ d'une autre FAMILLE normalisée (l'ancre chacal),
        # garde-pic comprise — pas un placeholder. Regénérée à la demande : déterministe.
        vise = _rms_famille_normalisee(cible[1]) * (10.0 ** (cible[2] / 20.0))
        gain = vise / max(moyenne, 1e-9)
    else:
        vise = reference_rms(cible[1]) * (10.0 ** (cible[2] / 20.0))
        gain = vise / max(moyenne, 1e-9)
    sons = {k: v * gain for k, v in sons.items()}
    pic = max(float(np.max(np.abs(v))) for v in sons.values())
    garde = min(1.0, PIC_PLAFOND / max(pic, 1e-9))
    if garde < 1.0:
        sons = {k: v * garde for k, v in sons.items()}
    return sons


_RMS_FAMILLE_CACHE: dict = {}


def _rms_famille_normalisee(fam: str) -> float:
    """RMS (linéaire, moyenne géométrique) d'une famille APRÈS normalisation complète — l'ancre
    des politiques ("relatif_arme", ...). Synthèse déterministe (graine par nom) : la valeur est
    la même que la famille soit produite avant, après, ou jamais dans cette exécution."""
    if fam not in _RMS_FAMILLE_CACHE:
        sons = _normaliser_famille(fam, _synthetiser_famille(fam, None))
        _RMS_FAMILLE_CACHE[fam] = float(np.exp(np.mean(
            [math.log(max(rms(x), 1e-9)) for x in sons.values()])))
    return _RMS_FAMILLE_CACHE[fam]


def ecrire_wav(chemin: Path, x: np.ndarray) -> None:
    pcm = np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(chemin), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(MIX_RATE)
        w.writeframes(pcm.tobytes())


def _synthetiser_famille(fam: str, sabotage: str | None) -> dict:
    fichiers = FAMILLES[fam][0]
    sons: dict = {}
    for i, nom in enumerate(fichiers):
        if fam == "shot":
            saboter = (sabotage == "sans-transitoire" and i == 0)
            sons[nom] = synth_shot(nom, sans_transitoire=saboter)
        elif fam in ("shot_vipere", "shot_frelon", "shot_chacal", "shot_condor"):
            arme = fam[len("shot_"):]
            # Sabotage §3.6 : corps+sub retirés des 4 VARIANTES condor (toute la famille perd son
            # calibre — la bande « corps 20-150 Hz » ET le contrôle inter-armes rougissent).
            saboter = (sabotage == "sans-corps-condor" and arme == "condor")
            sons[nom] = synth_shot(nom, profil=PROFILS_ARMES[arme], sans_corps=saboter)
        elif fam == "laser_warn":
            sons[nom] = synth_laser_warn(nom)
        elif fam == "whizz":
            sons[nom] = synth_whizz(nom, i)
        elif fam == "explosion_near":
            sons[nom] = synth_explosion_near(nom)
        elif fam == "explosion_far":
            sons[nom] = synth_explosion_far(nom)
        elif fam == "shell":
            sons[nom] = synth_shell(nom)
        elif fam == "bolt":
            sons[nom] = synth_bolt(nom)
        elif fam == "step":
            sons[nom] = synth_step(nom)
        elif fam == "debris":
            sons[nom] = synth_debris(nom)
        elif fam == "grenade":
            sons[nom] = synth_grenade(nom)
        elif fam == "hitmarker":
            sons[nom] = synth_hitmarker(nom)
        elif fam == "hit":
            sons[nom] = synth_hit(nom)
        elif fam == "refused":
            sons[nom] = synth_refused(nom)
    return sons


def produire(familles: list, sabotage: str | None = None) -> None:
    SORTIE.mkdir(parents=True, exist_ok=True)
    for fam in familles:
        sons = _normaliser_famille(fam, _synthetiser_famille(fam, sabotage))
        for nom, x in sons.items():
            ecrire_wav(SORTIE / (nom + ".wav"), x)
            print("USINE  %-28s %5.2f s   pic %6.1f dBFS   rms %6.1f dBFS"
                  % (nom + ".wav", len(x) / SR, en_db(float(np.max(np.abs(x)))), en_db(rms(x))))
    if sabotage:
        print("ATTENTION : production SABOTÉE (%s) — contre-épreuve uniquement, "
              "regénérer ensuite sans --sabotage." % sabotage)


# =================================================================================================
# CHECK (§3.4) — les contrôles techniques, sur LES FICHIERS ÉCRITS (la vérité du disque, pas la
# mémoire du processus qui vient de les produire).
# =================================================================================================

def lire_wav(chemin: Path):
    with wave.open(str(chemin), "rb") as w:
        params = (w.getnchannels(), w.getsampwidth(), w.getframerate())
        data = w.readframes(w.getnframes())
    return params, np.frombuffer(data, dtype="<i2").astype(np.float64) / 32768.0


def fraction_bande(x: np.ndarray, lo: float, hi: float) -> float:
    spectre = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    total = float(spectre[freqs >= 20.0].sum())
    if total <= 0.0:
        return 0.0
    return float(spectre[(freqs >= lo) & (freqs < hi)].sum()) / total


def freq_dominante(x: np.ndarray) -> float:
    """Fréquence du pic spectral (>= 40 Hz) — pour prouver la MONTÉE du télégraphe laser."""
    spectre = np.abs(np.fft.rfft(x)) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    m = freqs >= 40.0
    return float(freqs[m][int(np.argmax(spectre[m]))])


def correlation_normalisee(a: np.ndarray, b: np.ndarray) -> float:
    n = max(len(a), len(b))
    pa = np.zeros(n); pa[:len(a)] = a
    pb = np.zeros(n); pb[:len(b)] = b
    na, nb = float(np.linalg.norm(pa)), float(np.linalg.norm(pb))
    if na == 0.0 or nb == 0.0:
        return 1.0
    return abs(float(np.dot(pa, pb))) / (na * nb)


def cmd_check() -> int:
    echecs = 0
    controles = 0

    def controle(ok: bool, texte: str) -> None:
        nonlocal echecs, controles
        controles += 1
        if not ok:
            echecs += 1
        print("CHECK %s  %s" % ("PASS" if ok else "FAIL", texte))

    # --- 0. La liste est FERMÉE : tout présent, rien en trop. ------------------------------------
    attendus = {nom + ".wav" for (fichiers, _, _) in FAMILLES.values() for nom in fichiers}
    presents = {p.name for p in SORTIE.glob("trench_*.wav")}
    controle(attendus <= presents,
             "liste fermee : %d/%d fichiers presents%s"
             % (len(attendus & presents), len(attendus),
                "" if attendus <= presents else " ; manquants: " + ", ".join(sorted(attendus - presents))))
    controle(presents <= attendus,
             "liste fermee : aucun intrus trench_*.wav%s"
             % ("" if presents <= attendus else " ; intrus: " + ", ".join(sorted(presents - attendus))))

    donnees_par_famille: dict = {}
    for fam, (fichiers, (dur_min, dur_max), _) in FAMILLES.items():
        donnees = donnees_par_famille.setdefault(fam, {})
        for nom in fichiers:
            chemin = SORTIE / (nom + ".wav")
            if not chemin.exists():
                continue
            params, x = lire_wav(chemin)
            donnees[nom] = x
            # Format : le contrat _finalize — mono, 16 bits, 44100 Hz.
            controle(params == (1, 2, MIX_RATE),
                     "%s format mono/16bits/%d Hz (lu: %s)" % (nom, MIX_RATE, str(params)))
            # Pas d'écrêtage : pic <= -1 dBFS (§3.4).
            pic = en_db(float(np.max(np.abs(x))))
            controle(pic <= -1.0, "%s pic %.2f dBFS (<= -1.0)" % (nom, pic))
            # Durée dans les bornes de la famille.
            dur = len(x) / SR
            controle(dur_min <= dur <= dur_max,
                     "%s duree %.3f s (bornes %s : %.2f-%.2f)" % (nom, dur, fam, dur_min, dur_max))
            # Bandes d'énergie attendues : l'absence d'une bande = une couche oubliée.
            for (etiquette, lo, hi, mini, maxi) in BANDES[fam]:
                frac = fraction_bande(x, lo, hi)
                if mini is not None:
                    controle(frac >= mini, "%s bande %s frac=%.4f (min %.4f)"
                             % (nom, etiquette, frac, mini))
                if maxi is not None:
                    controle(frac <= maxi, "%s bande %s frac=%.4f (max %.4f)"
                             % (nom, etiquette, frac, maxi))
            # Transitoire (couche 1) : bande d'énergie TEMPORISÉE sur la fenêtre d'attaque —
            # voir l'encadré ATTAQUE_TRANSITOIRE. C'est ce contrôle que le sabotage fait rougir.
            if fam in ATTAQUE_TRANSITOIRE:
                (fc, fenetre, mini) = ATTAQUE_TRANSITOIRE[fam]
                hp = biquad(x, "highpass", fc, 0.7)
                ratio = rms(hp[:int(fenetre * SR)]) / max(rms(x), 1e-12)
                controle(ratio >= mini,
                         "%s bande transitoire (passe-haut %.0f Hz, fenetre 0-%.1f ms) "
                         "ratio=%.3f (min %.2f)" % (nom, fc, fenetre * 1000.0, ratio, mini))
        # Contrôles de FAMILLE (variantes) : distinctes ET homogènes.
        if len(donnees) >= 2:
            noms = list(donnees)
            for i in range(len(noms)):
                for j in range(i + 1, len(noms)):
                    c = correlation_normalisee(donnees[noms[i]], donnees[noms[j]])
                    controle(c < 0.98, "%s ~ %s correlation %.4f (< 0.98 : variantes distinctes)"
                             % (noms[i], noms[j], c))
            rmss = {nom: en_db(rms(x)) for nom, x in donnees.items()}
            centre = float(np.mean(list(rmss.values())))
            for nom, valeur in rmss.items():
                controle(abs(valeur - centre) <= 1.5,
                         "%s rms %.2f dBFS (moyenne famille %.2f, tolerance +/-1.5 dB)"
                         % (nom, valeur, centre))

    # =============================================================================================
    # §3.6 — CONTRÔLES INTER-ARMES : quatre voix, pas une. Ne tournent que si les familles sont
    # COMPLÈTES sur disque (sinon la liste fermée a déjà rougi — pas de KeyError par-dessus).
    # =============================================================================================
    familles_completes = all(
        len(donnees_par_famille.get(f, {})) == len(FAMILLES[f][0]) for f in ARMES + ("laser_warn",))
    if familles_completes:
        # --- 1. Corrélations inter-armes : la PIRE paire de variantes de chaque paire d'armes. ---
        for i in range(len(ARMES)):
            for j in range(i + 1, len(ARMES)):
                pire, pire_paire = -1.0, ""
                for na, xa in donnees_par_famille[ARMES[i]].items():
                    for nb, xb in donnees_par_famille[ARMES[j]].items():
                        c = correlation_normalisee(xa, xb)
                        if c > pire:
                            pire, pire_paire = c, "%s ~ %s" % (na, nb)
                controle(pire < CORRELATION_INTER_ARMES_MAX,
                         "inter-armes %s ~ %s correlation max %.4f (< %.2f ; pire paire : %s)"
                         % (ARMES[i][5:], ARMES[j][5:], pire, CORRELATION_INTER_ARMES_MAX,
                            pire_paire))
        # --- 2. Le CALIBRE s'entend : condor >= 2x le frelon sous 150 Hz (moyennes de famille). --
        grave_condor = float(np.mean([fraction_bande(x, 20.0, 150.0)
                                      for x in donnees_par_famille["shot_condor"].values()]))
        grave_frelon = float(np.mean([fraction_bande(x, 20.0, 150.0)
                                      for x in donnees_par_famille["shot_frelon"].values()]))
        controle(grave_condor >= grave_frelon * RAPPORT_GRAVE_CONDOR_FRELON_MIN,
                 "inter-armes calibre : energie <150 Hz condor %.4f vs frelon %.4f "
                 "(rapport %.1fx, min %.1fx)"
                 % (grave_condor, grave_frelon,
                    grave_condor / max(grave_frelon, 1e-9), RAPPORT_GRAVE_CONDOR_FRELON_MIN))
        # --- 3. Niveaux relatifs a l'ancre chacal : le disque suit POLITIQUE_NIVEAU (registre). --
        rms_db = {f: float(np.mean([en_db(rms(x)) for x in donnees_par_famille[f].values()]))
                  for f in ARMES + ("laser_warn",)}
        for f in ("shot_vipere", "shot_frelon", "shot_condor", "laser_warn"):
            cible_db = POLITIQUE_NIVEAU[f][2]
            tol = 1.0 if f == "laser_warn" else 0.8
            ecart = rms_db[f] - rms_db["shot_chacal"]
            controle(abs(ecart - cible_db) <= tol,
                     "niveau %s : %+.2f dB vs chacal (politique %+.1f dB, tolerance %.1f)"
                     % (f[5:] if f.startswith("shot_") else f, ecart, cible_db, tol))
        # --- 4. Le telegraphe laser MONTE et entre en FONDU (avertissement, pas buzzer). ---------
        xl = donnees_par_famille["laser_warn"]["trench_laser_warn"]
        tiers = len(xl) // 3
        f_debut = freq_dominante(xl[:tiers])
        f_fin = freq_dominante(xl[-tiers:])
        controle(f_fin >= f_debut * LASER_MONTEE_MIN,
                 "laser_warn montee : dominante %.0f -> %.0f Hz (rapport %.3f, min %.2f)"
                 % (f_debut, f_fin, f_fin / max(f_debut, 1e-9), LASER_MONTEE_MIN))
        fondu = rms(xl[:int(0.040 * SR)]) / max(rms(xl[int(0.25 * SR):int(0.45 * SR)]), 1e-12)
        controle(fondu <= LASER_FONDU_MAX,
                 "laser_warn fondu d'entree : RMS(0-40 ms)/RMS(250-450 ms) = %.3f (max %.2f)"
                 % (fondu, LASER_FONDU_MAX))
    else:
        controle(False, "controles inter-armes SAUTES : familles d'armes incompletes sur disque")

    verdict = "PASS" if echecs == 0 else "FAIL"
    print("CHECK GLOBAL %s  (%d controles, %d echecs)" % (verdict, controles, echecs))
    return 0 if echecs == 0 else 1


def cmd_dsp() -> int:
    """Équivalence scipy <-> forme directe II maison : le repli n'est pas du code mort.
    Tolérance 1e-9 : mêmes coefficients, même topologie (DF2 transposée), seul l'ordre des
    flottants diffère."""
    if not SCIPY_OK:
        print("DSP SKIP  scipy absent : le repli forme directe II est le SEUL chemin (rien a comparer)")
        return 0
    rng = graine("dsp_selftest")
    x = rng.uniform(-1.0, 1.0, 4096)
    pire = 0.0
    for (ftype, f, q, g) in (("lowpass", 800.0, 0.7, 0.0), ("highpass", 2600.0, 0.6, 0.0),
                             ("bandpass", 1900.0, 0.9, 0.0), ("peaking", 6200.0, 1.1, 8.0)):
        b, a = _rbj(ftype, f, q, g)
        y_scipy, _ = _scipy_lfilter(b, a, x, zi=np.zeros(2))
        y_py, _ = _df2t_python(b, a, x, np.zeros(2))
        pire = max(pire, float(np.max(np.abs(y_scipy - y_py))))
    # Ordre 1 — le crash historique vivait ICI : bruit rose/brun et AR(1) passent b=[g],
    # a=[1, -p], et un DF2 qui PRÉSUME 3 coefficients plante au dépaquetage. Un `dsp` qui ne
    # testait que l'ordre 2 restait vert sur ce crash (leçon §8.146 : une garde qui ne voit
    # qu'un délimiteur reste verte sur la faute).
    for (b, a) in (([0.0555179], [1.0, -0.99886]),        # 1er pôle du rose (Paul Kellet)
                   ([0.019 * 0.9985], [1.0, -0.9985]),    # brun : intégrateur qui fuit
                   ([0.45], [1.0, -0.55])):               # AR(1) des références (alpha 0,45)
        y_scipy, _ = _scipy_lfilter(b, a, x, zi=np.zeros(1))
        y_py, _ = _df2t_python(b, a, x, np.zeros(2))
        pire = max(pire, float(np.max(np.abs(y_scipy - y_py))))
    ok = pire < 1e-9
    print("DSP %s  ecart max scipy <-> DF2 python (ordres 1 et 2) : %.3e (tolerance 1e-9)"
          % ("PASS" if ok else "FAIL", pire))
    return 0 if ok else 1


# =================================================================================================
# CLI
# =================================================================================================

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Usine audio LA TRANCHEE (LOT A §8.151) - .wav 44100 Hz / PCM16 / mono, "
                    "graine fixe par son, liste fermee du cahier §3.3 + voix d'armes §3.6.")
    ap.add_argument("commande", choices=["all", "shot", "armes", "whizz", "explosion", "mech",
                                         "check", "dsp"])
    ap.add_argument("--sabotage", choices=["sans-transitoire", "sans-corps-condor"], default=None,
                    help="CONTRE-EPREUVES uniquement : `sans-transitoire` (avec `shot`) retire la "
                         "couche 1 de trench_shot_1 ; `sans-corps-condor` (avec `armes`) retire "
                         "corps+sub des 4 variantes condor. Dans les deux cas `check` doit ROUGIR.")
    args = ap.parse_args()

    if args.sabotage == "sans-transitoire" and args.commande != "shot":
        print("ERREUR : --sabotage sans-transitoire ne s'applique qu'a la commande `shot`.")
        return 2
    if args.sabotage == "sans-corps-condor" and args.commande != "armes":
        print("ERREUR : --sabotage sans-corps-condor ne s'applique qu'a la commande `armes`.")
        return 2
    if args.commande == "check":
        return cmd_check()
    if args.commande == "dsp":
        return cmd_dsp()

    ordres = {
        "shot": ["shot"],
        "armes": ["shot_vipere", "shot_frelon", "shot_chacal", "shot_condor", "laser_warn"],
        "whizz": ["whizz"],
        "explosion": ["explosion_near", "explosion_far"],
        "mech": ["shell", "bolt", "step", "debris", "grenade", "hitmarker", "hit", "refused"],
        "all": list(FAMILLES.keys()),
    }
    print("Usine audio TRANCHEE - scipy %s - sortie : %s"
          % ("present (lfilter)" if SCIPY_OK else "ABSENT (repli forme directe II)", SORTIE))
    produire(ordres[args.commande], args.sabotage)
    return 0


if __name__ == "__main__":
    sys.exit(main())
