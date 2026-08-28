# -*- coding: utf-8 -*-
"""
LOT 0 §8.151 — HARNAIS DE BASELINES de LA TRANCHÉE (baseline_trench.py).

Pilote chaque scène `tools/shot_trench_*.tscn` dans un PROCESSUS GODOT SÉPARÉ — la leçon de
reproductibilité de la référence Claude-of-Duty (README §Tooling) : « les captures n'étaient pas
reproductibles » parce que l'état FUYAIT entre shots partagés (âge des particules, exposition).
Un processus par scène, l'état ne peut pas fuir.

Ce que fait le harnais :
  1. purge le répertoire de sortie `user://` de la scène (aucun PNG d'une passe précédente ne
     peut se faire passer pour un PNG du jour) ;
  2. lance la scène FENÊTRÉE (les captures exigent un viewport qui rend — §8.100/§8.111) ;
  3. range les PNG dans `tools/baselines/run<N>/<scene>/` + le log console dans
     `tools/baselines/logs/` ;
  4. exécute le tout DEUX FOIS, compare par SHA-256, et pour chaque fichier instable mesure
     l'écart réel (pixels différents, delta max, boîte englobante — Pillow) pour étayer la
     CAUSE SUSPECTÉE. ⚠️ IL NE CORRIGE RIEN : consigner sans corriger est le contrat du LOT 0,
     le LOT E traite les causes.

⚠️ JAMAIS deux Godot en même temps (cache d'import corrompu) : tout est STRICTEMENT séquentiel.
⚠️ `tools/baselines/` porte un `.gdignore` (sans lui, le prochain `--import` avalerait les PNG
   comme des assets et sèmerait des `.import`) et un `.gitignore` local (les baselines sont des
   sorties de mesure, pas des sources).

Usage (depuis n'importe où, PYTHONUTF8=1 exporté) :
  py tools/baseline_trench.py all          # passe 1 + passe 2 + comparaison (le mode normal)
  py tools/baseline_trench.py run 1        # une passe seule (PNG -> run1/)
  py tools/baseline_trench.py compare      # comparaison seule (run1/ et run2/ déjà sur disque)
"""

import hashlib
import shutil
import subprocess
import sys
import time
from pathlib import Path

GODOT = Path("C:/Users/Hakim/Desktop/Godot_v4.7-stable_win64_console.exe")
FRONTEND = Path(__file__).resolve().parent.parent          # .../frontend
BASELINES = FRONTEND / "tools" / "baselines"
LOGS = BASELINES / "logs"
MANIFEST = BASELINES / "manifest.txt"
# Le nom du projet (project.godot -> config/name) fixe le répertoire user:// des scènes.
USER_DATA = Path.home() / "AppData/Roaming/Godot/app_userdata/Wasteland Warfare"
TIMEOUT_S = 420

# Chaque scène écrit dans SON répertoire user:// (relevé dans les .gd le 2026-08-26) ; la cause
# de non-déterminisme SUSPECTÉE vient de la lecture du code, la mesure Pillow vient l'étayer.
SCENES = [
    {
        "scene": "shot_trench_ambient",
        "out": "trench_ambient_shots",
        "cause": ("brume qui defile sur TIME (horloge GPU/murale, trench_haze.gdshader) + "
                  "cendres/braises GPUParticles2D sans graine fixe (RNG visuel) + instants de "
                  "capture poses par create_timer (horloge murale)"),
    },
    {
        "scene": "shot_trench_delivery",
        "out": "trench_delivery",
        "cause": ("couche d'ambiance animee (TIME + particules RNG) jamais figee + traçantes/"
                  "recul du viewmodel captures a un instant d'horloge murale + bench final "
                  "sensible a la charge machine"),
    },
    {
        "scene": "shot_trench_help",
        "out": "trench_help_shot",
        "cause": ("panneau F1 statique MAIS duel vivant derriere (ambiance TIME + particules "
                  "RNG) — l'arriere-plan de la capture bouge, pas le panneau"),
    },
    {
        "scene": "shot_trench_sprites",
        "out": "trench_sprite_shots",
        "cause": ("partie soldat figee par reduced_motion, mais partie viewmodel SANS "
                  "reduced_motion (ambiance TIME + particules RNG) + fenetre 'fire' de 90 ms "
                  "re-armee par frame (phase de l'animation non deterministe)"),
    },
]


def say(text: str) -> None:
    print(text, flush=True)


def purge(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def run_pass(num: int) -> bool:
    """Une passe complète : chaque scène en processus séparé, PNG rangés dans run<num>/."""
    ok = True
    run_dir = BASELINES / f"run{num}"
    purge(run_dir)
    LOGS.mkdir(parents=True, exist_ok=True)
    for spec in SCENES:
        scene = spec["scene"]
        out_user = USER_DATA / spec["out"]
        # 1) Purge de la sortie user:// — un PNG d'hier qui survivrait ici deviendrait un faux
        #    stable (deux passes copieraient LE MÊME fichier au lieu d'en produire deux).
        purge(out_user)
        # 2) Le processus séparé, FENÊTRÉ, un seul Godot à la fois.
        say(f"[PASSE {num}] {scene} ...")
        t0 = time.monotonic()
        try:
            proc = subprocess.run(
                [str(GODOT), "--path", str(FRONTEND), f"res://tools/{scene}.tscn"],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
                timeout=TIMEOUT_S,
            )
            code = proc.returncode
            log_text = proc.stdout + "\n--- STDERR ---\n" + proc.stderr
        except subprocess.TimeoutExpired as exc:
            code = -1
            log_text = ((exc.stdout or "") + "\n--- STDERR ---\n" + (exc.stderr or "")
                        + f"\n[TIMEOUT apres {TIMEOUT_S}s]")
        elapsed = time.monotonic() - t0
        (LOGS / f"run{num}_{scene}.log").write_text(log_text, encoding="utf-8")
        # 3) Collecte des PNG produits.
        dest = run_dir / scene
        dest.mkdir(parents=True, exist_ok=True)
        pngs = sorted(out_user.glob("*.png")) if out_user.exists() else []
        for png in pngs:
            shutil.copy2(png, dest / png.name)
        say(f"  -> code {code} · {len(pngs)} PNG · {elapsed:.0f}s")
        if code != 0:
            # Un code non nul n'est pas forcement fatal (shot_trench_help rend 1 si un de SES
            # controles rougit) : on le CONSIGNE, la comparaison se fait quand meme.
            say(f"  ⚠️ {scene} : code de sortie {code} (voir logs/run{num}_{scene}.log)")
        if not pngs:
            say(f"  ⚠️ {scene} : AUCUN PNG produit — passe invalide pour cette scene")
            ok = False
    return ok


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def pixel_diff(a: Path, b: Path):
    """Écart réel entre deux PNG : (pixels différents, delta max par canal, bbox) — Pillow+numpy.

    ⚠️ PIÈGE MESURÉ (LOT 0, 2026-08-26) : sur une image RGBA, `Image.getbbox()` de Pillow ≥ 10 ne
    regarde par défaut QUE le canal ALPHA (`alpha_only=True`). Deux captures 100 % opaques dont les
    RGB diffèrent donnent un diff à alpha nul partout → `getbbox()` rend None, et la première
    version de ce harnais concluait « 0 px différents » sur 35 fichiers aux SHA distincts. La bbox
    se calcule donc en numpy, sur les QUATRE canaux — jamais via `getbbox()`.
    """
    try:
        import numpy as np
        from PIL import Image, ImageChops
    except ImportError:
        return None
    with Image.open(a) as im_a, Image.open(b) as im_b:
        im_a = im_a.convert("RGBA")
        im_b = im_b.convert("RGBA")
        if im_a.size != im_b.size:
            return ("tailles differentes", 255, None)
        diff = ImageChops.difference(im_a, im_b)
        arr = np.asarray(diff)
        mask = arr.max(axis=2) > 0
        count = int(mask.sum())
        if count == 0:
            return (0, 0, None)
        ys, xs = np.nonzero(mask)
        bbox = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
        return (count, int(arr.max()), bbox)


def compare() -> int:
    """Compare run1/ et run2/ par hash, mesure les écarts, écrit le manifest. Renvoie le code."""
    run1 = BASELINES / "run1"
    run2 = BASELINES / "run2"
    if not run1.exists() or not run2.exists():
        say("ERREUR : run1/ ou run2/ manquant — lancer d'abord les deux passes.")
        return 2
    lines = [
        "# BASELINES LA TRANCHEE — LOT 0 §8.151 — genere par baseline_trench.py",
        "# Deux executions COMPLETES (processus separes par scene), comparees par SHA-256.",
        "# ⚠️ Les instables sont CONSIGNEES, pas corrigees : c'est le travail du LOT E (§7.2).",
        "# format : BASELINE|scene|fichier|stable|pixels_diff|delta_max|bbox|sha256_run1|sha256_run2",
    ]
    stable_n = 0
    unstable_n = 0
    missing_n = 0
    for spec in SCENES:
        scene = spec["scene"]
        d1 = run1 / scene
        d2 = run2 / scene
        names = sorted({p.name for p in d1.glob("*.png")} | {p.name for p in d2.glob("*.png")})
        if not names:
            say(f"⚠️ {scene} : aucun PNG dans les deux passes")
            missing_n += 1
            continue
        scene_unstable = []
        scene_stable = 0
        for name in names:
            f1, f2 = d1 / name, d2 / name
            if not f1.exists() or not f2.exists():
                missing_n += 1
                lines.append(f"BASELINE|{scene}|{name}|ABSENT_D_UNE_PASSE|-|-|-|-|-")
                say(f"  ⚠️ {scene}/{name} : absent d'une des deux passes")
                continue
            h1, h2 = sha256_of(f1), sha256_of(f2)
            if h1 == h2:
                stable_n += 1
                scene_stable += 1
                lines.append(f"BASELINE|{scene}|{name}|oui|0|0|-|{h1}|{h2}")
            else:
                unstable_n += 1
                measured = pixel_diff(f1, f2)
                if measured is None:
                    count, delta, bbox = "?", "?", "?"
                else:
                    count, delta, bbox = measured
                lines.append(f"BASELINE|{scene}|{name}|NON|{count}|{delta}|{bbox}|{h1}|{h2}")
                scene_unstable.append((name, count, delta, bbox))
        say(f"\n=== {scene} ===")
        say(f"  stables : {scene_stable}/{len(names)}")
        for name, count, delta, bbox in scene_unstable:
            say(f"  INSTABLE {name} : {count} px differents, delta max {delta}, bbox {bbox}")
        if scene_unstable:
            say(f"  cause suspectee : {spec['cause']}")
            lines.append(f"CAUSE|{scene}|{spec['cause']}")
    lines.append(f"TOTAL|stables={stable_n}|instables={unstable_n}|absents={missing_n}")
    MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    say(f"\nTOTAL|stables={stable_n}|instables={unstable_n}|absents={missing_n}")
    say(f"[MANIFEST] {MANIFEST}")
    # Une baseline instable n'est PAS un échec du LOT 0 (c'est une MESURE, le LOT E corrigera) ;
    # seuls des fichiers absents rendent la comparaison elle-même invalide.
    return 0 if missing_n == 0 else 1


def main() -> int:
    if not GODOT.exists():
        say(f"ERREUR : binaire Godot introuvable : {GODOT}")
        return 2
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode == "run":
        num = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        return 0 if run_pass(num) else 1
    if mode == "compare":
        return compare()
    if mode == "all":
        ok1 = run_pass(1)
        ok2 = run_pass(2)
        code = compare()
        return code if (ok1 and ok2) else 1
    say(f"mode inconnu : {mode} (attendu : all | run <n> | compare)")
    return 2


if __name__ == "__main__":
    sys.exit(main())
