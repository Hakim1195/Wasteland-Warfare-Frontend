extends Resource
class_name FactionData

## Ressource data-driven décrivant une faction jouable (Règle d'Or §6.3).
## Les fichiers .tres de ce dossier sont chargés dynamiquement par le carrousel de
## sélection (faction_selection.gd). Ajouter une faction = déposer un nouveau .tres ici,
## aucun code à modifier.
##
## L'`id` DOIT correspondre à une clé du registre serveur (backend/api/game/factions.py)
## pour que le choix transmis au réseau soit appliqué côté moteur.

# Identifiant technique (clé du registre backend, ex: "phalanges_acier"). Envoyé au serveur.
@export var id: String = ""
# Nom affiché de la faction (ex: "Les Phalangistes").
@export var name: String = ""
# Description / lore + résumé du pouvoir (affiché dans le carrousel).
@export_multiline var description: String = ""
# Modificateurs de règles (miroir frontend du registre backend §4.3). Clé -> valeur.
@export var modifiers: Dictionary = {}
# Chemin res:// vers le logo de la faction (optionnel ; placeholder si absent).
@export var logo_path: String = ""
# Chemin res:// vers le portrait du héros (optionnel ; placeholder coloré si absent).
@export var hero_path: String = ""
# Chemin res:// vers le modèle 3D (.glb) du héros (optionnel ; repli sur hero_path 2D si absent).
# Consommé par le composant hero_viewport_3d (SubViewport transparent) dans main_menu / split_screen_vs.
@export var hero_model_path: String = ""
# Couleur d'accent de la faction (dans la charte : dérivée de l'Orange Fusion #d35400).
@export var accent_color: Color = Color("#d35400")
