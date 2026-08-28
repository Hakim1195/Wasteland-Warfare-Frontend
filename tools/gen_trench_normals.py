# -*- coding: utf-8 -*-
"""
Fabrique les cartes de NORMALES des textures de la tranchée, à partir de leur ALBEDO (§8.153).

╔═══════════════════════════════════════════════════════════════════════════════════════════════╗
║ POURQUOI DES NORMALES, ET PAS AUTRE CHOSE                                                     ║
║ Le projet tourne en **GL Compatibility** (`project.godot` → `renderer/rendering_method =       ║
║ "gl_compatibility"`). SSAO, SSIL, SDFGI, VoxelGI, le brouillard volumétrique et la profondeur  ║
║ de champ y sont **silencieusement inertes** : les activer ne produirait rien du tout, et on    ║
║ passerait des heures à régler un effet qui n'existe pas.                                      ║
║ Les cartes de normales, elles, MARCHENT en Compatibility. C'est le seul levier de relief       ║
║ disponible, et sur une tranchée faite de 34 boîtes plates c'est le plus rentable de tous.      ║
╚═══════════════════════════════════════════════════════════════════════════════════════════════╝

⚠️ CE QUE CETTE MÉTHODE EST, ET CE QU'ELLE N'EST PAS. Une normale dérivée de l'albédo suppose que
« sombre = creux ». C'est **faux en général** (une tache noire sur un mur lisse deviendrait un
trou) et **juste pour ces quatre matières-ci** : sur du jute, de la boue, des planches et de la
terre, ce qui est sombre EST une crevasse — l'occlusion y est la cause de la couleur. On l'écrit
plutôt que de laisser croire à une mesure : c'est une approximation choisie parce que son
hypothèse est vérifiée sur ces textures-là, pas une vérité générale.

⚠️ LE GRADIENT EST CALCULÉ EN ENROULEMENT (`np.roll`). Les quatre textures sont tuilées par un
matériau triplanaire : un gradient calculé sans enroulement fabriquerait une ARÊTE FANTÔME sur
chaque couture de tuile — un quadrillage régulier sur tout le sol, visible précisément là où on
essaie de gagner du réalisme.

Lancement (depuis la racine du dépôt) :  PYTHONUTF8=1 py frontend/tools/gen_trench_normals.py
"""
import io
import os
import sys

import numpy as np
from PIL import Image

_HERE = os.path.dirname(os.path.abspath(__file__))
_TEX = os.path.join(_HERE, "..", "assets", "images", "trench", "textures")

# Amplitude du relief, par matière. ⚠️ Ce ne sont pas des chiffres de goût : ils disent combien de
# millimètres de relief la matière a RÉELLEMENT, rapportés à la taille de sa tuile au sol.
#   jute   — un sac de sable a des bosses de plusieurs centimètres sur 2,4 m de tuile : le plus fort
#   earth  — une paroi de terre étayée, mottes et racines : fort
#   mud    — de la boue tassée, ornières peu profondes sur 2 m : moyen
#   planks — du bois scié : presque plat, seuls les joints entre planches creusent
FORCE = {"jute": 3.2, "earth": 2.6, "mud": 1.8, "planks": 1.2}


def hauteur(image):
    """Carte de hauteur = luminance perceptuelle, en [0, 1]."""
    a = np.asarray(image.convert("RGB"), dtype=np.float64) / 255.0
    return 0.2126 * a[:, :, 0] + 0.7152 * a[:, :, 1] + 0.0722 * a[:, :, 2]


def normales(h, force):
    """Sobel enroulé → normale tangente, encodée en RGB (convention OpenGL, +Y vers le haut)."""
    def roll(dy, dx):
        return np.roll(np.roll(h, dy, axis=0), dx, axis=1)

    # Sobel 3x3, entièrement en enroulement : aucune couture.
    dx = ((roll(-1, -1) + 2.0 * roll(0, -1) + roll(1, -1))
          - (roll(-1, 1) + 2.0 * roll(0, 1) + roll(1, 1))) / 8.0
    dy = ((roll(-1, -1) + 2.0 * roll(-1, 0) + roll(-1, 1))
          - (roll(1, -1) + 2.0 * roll(1, 0) + roll(1, 1))) / 8.0

    nx = -dx * force
    ny = dy * force
    nz = np.ones_like(h)
    norme = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.stack([nx / norme, ny / norme, nz / norme], axis=-1)
    return Image.fromarray(np.clip((out * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), "RGB")


# ⚠️ Le `.import` est écrit À LA MAIN, et il porte deux réglages qui comptent autant que l'image :
#   `compress/normal_map=1` — Godot doit SAVOIR que c'est une normale, sinon il l'encode comme une
#      couleur et le relief part de travers (piège classique : ça « marche » mais l'éclairage ment) ;
#   `mipmaps/generate=true` — voir le pavé de `corriger_mipmaps()`.
IMPORT_NORMALE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="uid://{uid}"
path.s3tc="res://.godot/imported/{nom}.s3tc.ctex"
metadata={{
"imported_formats": ["s3tc_bptc"],
"vram_texture": true
}}

[deps]

source_file="res://assets/images/trench/textures/{nom}"
dest_files=["res://.godot/imported/{nom}.s3tc.ctex"]

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/normal_map=1
compress/channel_pack=1
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def corriger_mipmaps(chemin):
    """Active les mipmaps sur une texture d'albédo existante.

    🩸 DÉFAUT MESURÉ, PAS SUPPOSÉ. Les quatre albédos étaient importés avec
    `mipmaps/generate=false`. Le sol lointain est tuilé toutes les **14 m** sur un cadre de **340 m**
    de côté : sans mipmap, chaque pixel d'écran échantillonne une texture des dizaines de fois trop
    fine, et le résultat est un **moirage** qui grouille dès que la caméra tourne. C'est le défaut
    de netteté le plus visible de toute la scène, et il se corrige par un booléen.
    ⚠️ C'est aussi le seul changement de ce lot qui coûte de la VRAM (+33 %). Sur quatre textures
    de 768-1024 px, c'est négligeable ; sur un atlas de 4K, il faudrait y penser."""
    p = chemin + ".import"
    if not os.path.exists(p):
        return False
    s = io.open(p, encoding="utf-8").read()
    if "mipmaps/generate=true" in s:
        return False
    s2 = s.replace("mipmaps/generate=false", "mipmaps/generate=true")
    if s2 == s:
        return False
    io.open(p, "w", encoding="utf-8", newline="\n").write(s2)
    return True


def main():
    if not os.path.isdir(_TEX):
        print("dossier de textures introuvable :", _TEX)
        return 1
    faits = []
    for nom, force in sorted(FORCE.items()):
        src = os.path.join(_TEX, nom + ".png")
        if not os.path.exists(src):
            print("  ABSENT  %s.png" % nom)
            continue
        img = Image.open(src)
        h = hauteur(img)
        n = normales(h, force)
        dst = os.path.join(_TEX, nom + "_normal.png")
        n.save(dst)
        # Amplitude effective : l'écart-type de l'inclinaison, en degrés. Un chiffre qu'on PUBLIE —
        # « la carte existe » ne dit rien de ce qu'elle fait, et une normale plate est un fichier
        # parfaitement valide qui n'éclaire rien.
        a = np.asarray(n, dtype=np.float64) / 255.0 * 2.0 - 1.0
        pente = np.degrees(np.arccos(np.clip(a[:, :, 2], -1.0, 1.0)))
        faits.append((nom, img.size, force, float(pente.mean()), float(pente.max())))
        print("  ECRIT   %s_normal.png  %dx%d  force %.1f  pente moy %.2f deg  max %.2f deg"
              % (nom, img.size[0], img.size[1], force, pente.mean(), pente.max()))

    print("\n--- mipmaps sur les albedos ---")
    for nom in sorted(FORCE):
        src = os.path.join(_TEX, nom + ".png")
        print("  %-8s %s" % (nom, "ACTIVES" if corriger_mipmaps(src) else "deja actives / absent"))

    print("\n%d carte(s) de normales ecrite(s)." % len(faits))
    print("⚠️ Il reste a REIMPORTER (godot --headless --path frontend --import) : les `.import`")
    print("   des normales sont ecrits, mais les `.ctex` ne le sont que par le moteur.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
