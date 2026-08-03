extends Control

# =========================================================================
# ÉCRAN DÉFIS — COQUILLE DE REDIRECTION (§8.134)
# =========================================================================
# L'écran DÉFIS n'existe plus en propre : son contenu est devenu `missions_panel.gd`, hébergé par
# le 4ᵉ onglet du HUB ÉVÉNEMENTS. Ce fichier ne garde qu'un rôle : rattraper les CHEMINS LEGACY.
#
# POURQUOI GARDER LA SCÈNE PLUTÔT QUE LA SUPPRIMER :
#   • un `.tscn` supprimé casse tout `change_scene` qui le viserait encore — y compris depuis un
#     build plus ancien, une sauvegarde de session ou un raccourci qu'on aurait oublié de recenser ;
#   • l'uid de la scène reste valide, donc aucun `.import`/`.uid` n'est à toucher (règle projet) ;
#   • le joueur qui arrive ici atterrit AU BON ENDROIT, sans écran d'erreur et sans même s'en rendre
#     compte : il voit le hub, onglet DÉFIS ouvert.
#
# Le recensement exhaustif des appelants a été fait (grep intégral `missions.tscn`) : il n'en
# restait que DEUX — l'onglet de la nav et le pied de la carte « DÉFIS EN COURS » du QG. Les deux
# pointent désormais directement le hub. Cette coquille est donc une CEINTURE, pas un chemin nominal.

const EventsScreen = preload("res://scripts/ui/events_screen.gd")

const HUB_SCENE := "res://scenes/ui/events.tscn"


func _ready() -> void:
	# Onglet cible posé AVANT le changement de scène (patron §8.107) : le hub le lit à son `_ready`
	# puis le purge. `call_deferred` — on ne change JAMAIS de scène depuis le `_ready` d'une scène
	# en cours de construction (l'arbre est encore verrouillé).
	EventsScreen.target_tab = "missions"
	_go.call_deferred()


func _go() -> void:
	TransitionManager.change_scene(HUB_SCENE)
