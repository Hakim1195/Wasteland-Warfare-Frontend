extends Resource
class_name SkinData

## Ressource data-driven décrivant un SKIN de héros (lot M5 — §8.69, pattern factions §4.3).
## Les .tres de ce dossier sont chargés dynamiquement (DirAccess, tri alphabétique) par les
## écrans qui affichent un héros (Split-Screen VS, draft, boutique). Ajouter un skin = déposer
## un nouveau .tres ici + l'article correspondant au catalogue serveur (shop_catalog.py).
##
## L'`id` DOIT correspondre à l'id du catalogue serveur (ShopItem.id, ex. "skin_aegis_obsidienne")
## — c'est la valeur diffusée dans PlayerState.equipped_skin (champ public).
## PLACEHOLDER (convention §4.3) : si `portrait_path`/`model_path` sont absents ou introuvables,
## l'affichage retombe sur un ColorRect teinté `accent_override`.

# Identifiant technique (= ShopItem.id du catalogue serveur). Diffusé dans l'état de partie.
@export var id: String = ""
# Faction liée (= ShopItem.hero_key / id du registre factions). Un skin n'habille qu'UN héros.
@export var faction_id: String = ""
# Clé i18n du nom d'affichage (résolue par tr() — R4).
@export var name_key: String = ""
# Chemin res:// du portrait 2D alternatif (optionnel ; placeholder si absent).
@export var portrait_path: String = ""
# Chemin res:// du modèle 3D (.glb) alternatif (optionnel ; repli portrait 2D puis placeholder).
@export var model_path: String = ""
# Teinte d'accent du skin — utilisée par le placeholder ET comme accent de présentation.
@export var accent_override: Color = Color("e0b249")
