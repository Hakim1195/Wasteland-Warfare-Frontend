#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =================================================================================================
# LA TRANCHÉE (§8.151, LOT A) — TEST DE L'USINE AUDIO : `py frontend/tools/test_trench_audio.py`
#
# Script AUTONOME (convention projet : pas de pytest, prints PASS/FAIL, exit 0/1). Il pilote
# `trench_audio_factory.py` par SOUS-PROCESSUS — on teste la vraie CLI et les vrais fichiers sur
# disque, pas des fonctions en mémoire (leçon §8.144 : les faux verts naissent des raccourcis).
#
# Les sept preuves, dans l'ordre :
#   1. PRODUCTION    `all` sort en code 0 et la liste FERMÉE (§3.3 + §3.6, 48 fichiers) est sur
#      disque.
#   2. REPRODUCTIBILITÉ (§3.1)  deuxième `all` → les 48 hash sha256 sont IDENTIQUES.
#   3. CHECK (§3.4)  `check` est 100 % vert (code 0, verdict global PASS, zéro ligne FAIL).
#   4. CONTRÔLES §3.6 RÉELLEMENT EXÉCUTÉS  la sortie de `check` contient bien les 6 corrélations
#      inter-armes, le contrôle « calibre » condor>frelon, les 4 niveaux relatifs et les 2
#      contrôles du télégraphe laser (un contrôle absent ne peut pas être vert — leçon §8.146 :
#      une garde qui ne voit pas la faute reste verte dessus).
#   5. DSP           équivalence scipy <-> repli forme directe II (le repli n'est pas du code mort).
#   6. SABOTAGE tir (contre-épreuve LOT A)  `shot --sabotage sans-transitoire` → le contrôle de
#      bande transitoire de trench_shot_1 ROUGIT (check code 1) → regénération → hash de NOUVEAU
#      identiques au relevé de l'étape 1 (la restauration est prouvée, pas déclarée).
#   7. SABOTAGE condor (contre-épreuve §3.6)  `armes --sabotage sans-corps-condor` → la bande
#      « corps 20-150 Hz » rougit sur les 4 variantes ET le contrôle inter-armes calibre rougit
#      → regénération → hash identiques au relevé.
#
# ⚠️ Les sabotages écrivent VRAIMENT dans assets/audio/sfx/ puis restaurent : ne pas interrompre
# au milieu ; en cas de doute, `py trench_audio_factory.py shot` (ou `armes`) remet les sains.
# =================================================================================================

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path

ICI = Path(__file__).resolve().parent
USINE = ICI / "trench_audio_factory.py"
SFX = ICI.parent / "assets" / "audio" / "sfx"
ATTENDUS = 48                    # liste fermée : 29 (§3.3) + 19 voix d'armes §3.6 (4+6+4+4+1)

_resultats: list = []


def note(nom: str, ok: bool, detail: str = "") -> None:
    _resultats.append(ok)
    print("TEST %s  %s%s" % ("PASS" if ok else "FAIL", nom, (" - " + detail) if detail else ""))


def usine(*args: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, PYTHONUTF8="1")
    return subprocess.run([sys.executable, str(USINE), *args],
                          capture_output=True, text=True, encoding="utf-8",
                          errors="replace", env=env)


def hashes() -> dict:
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(SFX.glob("trench_*.wav"))}


def main() -> int:
    # --- 1. PRODUCTION -----------------------------------------------------------------------
    r = usine("all")
    note("production `all` (code retour 0)", r.returncode == 0,
         "" if r.returncode == 0 else (r.stderr or r.stdout)[-400:])
    releve = hashes()
    note("liste fermee : %d fichiers trench_*.wav" % len(releve), len(releve) == ATTENDUS,
         "attendu %d" % ATTENDUS)

    # --- 2. REPRODUCTIBILITÉ (graine fixe par son, §3.1) -------------------------------------
    r = usine("all")
    apres = hashes()
    memes = (releve == apres)
    diffs = [n for n in releve if apres.get(n) != releve[n]] if not memes else []
    note("reproductibilite : deux `all` -> hash identiques", r.returncode == 0 and memes,
         "" if memes else "fichiers differents : " + ", ".join(diffs[:5]))

    # --- 3. CHECK §3.4 -----------------------------------------------------------------------
    r = usine("check")
    vert = (r.returncode == 0 and "CHECK GLOBAL PASS" in r.stdout
            and "CHECK FAIL" not in r.stdout)
    note("controles techniques `check` 100 %% verts", vert,
         "" if vert else "\n".join(l for l in r.stdout.splitlines() if "FAIL" in l)[:400])

    # --- 4. Les contrôles §3.6 ont RÉELLEMENT tourné (un contrôle absent est toujours vert) --
    sortie_check = r.stdout
    inter = [l for l in sortie_check.splitlines() if "CHECK PASS  inter-armes" in l]
    note("§3.6 : 6 correlations inter-armes + 1 controle calibre presents", len(inter) == 7,
         "%d lignes inter-armes (attendu 7)" % len(inter))
    niveaux = [l for l in sortie_check.splitlines() if "CHECK PASS  niveau " in l]
    note("§3.6 : 4 niveaux relatifs a l'ancre chacal presents", len(niveaux) == 4,
         "%d lignes niveau (attendu 4)" % len(niveaux))
    note("§3.6 : montee et fondu du telegraphe laser controles",
         "laser_warn montee" in sortie_check and "laser_warn fondu" in sortie_check)

    # --- 5. DSP : le repli forme directe II est ÉQUIVALENT à scipy (pas du code mort) --------
    r = usine("dsp")
    note("equivalence scipy <-> forme directe II", r.returncode == 0 and "DSP FAIL" not in r.stdout,
         (r.stdout.strip().splitlines() or [""])[-1])

    # --- 6. SABOTAGE : retirer la couche transitoire DOIT faire rougir le contrôle de bande --
    r = usine("shot", "--sabotage", "sans-transitoire")
    note("sabotage : production sans transitoire", r.returncode == 0)
    r = usine("check")
    lignes_rouges = [l for l in r.stdout.splitlines()
                     if "FAIL" in l and "trench_shot_1" in l and "transitoire" in l]
    rougit = (r.returncode != 0 and len(lignes_rouges) > 0)
    note("sabotage : `check` rougit sur la bande transitoire de trench_shot_1", rougit,
         lignes_rouges[0].strip() if lignes_rouges else "check n'a PAS rougi (faux vert !)")

    # Restauration : regénérer, puis PROUVER le retour a l'état du relevé (hash, pas parole).
    r = usine("shot")
    restaure = hashes()
    note("restauration : hash de nouveau identiques au releve initial",
         r.returncode == 0 and restaure == releve,
         "" if restaure == releve else "fichiers encore differents : "
         + ", ".join(n for n in releve if restaure.get(n) != releve[n])[:200])

    # --- 7. SABOTAGE §3.6 : retirer corps+sub du condor DOIT tuer sa signature < 150 Hz ------
    r = usine("armes", "--sabotage", "sans-corps-condor")
    note("sabotage condor : production sans corps", r.returncode == 0)
    r = usine("check")
    rouges_corps = [l for l in r.stdout.splitlines()
                    if "FAIL" in l and "trench_shot_condor" in l and "corps 20-150" in l]
    rouges_calibre = [l for l in r.stdout.splitlines()
                      if "FAIL" in l and "inter-armes calibre" in l]
    rougit = (r.returncode != 0 and len(rouges_corps) == 4 and len(rouges_calibre) == 1)
    note("sabotage condor : bande corps 20-150 Hz rouge x4 ET controle calibre rouge", rougit,
         (rouges_corps[0].strip() if rouges_corps else "check n'a PAS rougi (faux vert !)")
         + " ; calibre: %d" % len(rouges_calibre))
    # Restauration prouvée par hash, comme pour le tir.
    r = usine("armes")
    restaure = hashes()
    note("restauration condor : hash de nouveau identiques au releve initial",
         r.returncode == 0 and restaure == releve,
         "" if restaure == releve else "fichiers encore differents : "
         + ", ".join(n for n in releve if restaure.get(n) != releve[n])[:200])

    total = len(_resultats)
    ok = sum(1 for x in _resultats if x)
    verdict = "PASS" if ok == total else "FAIL"
    print("TEST GLOBAL %s  (%d/%d)" % (verdict, ok, total))
    return 0 if ok == total else 1


if __name__ == "__main__":
    sys.exit(main())
