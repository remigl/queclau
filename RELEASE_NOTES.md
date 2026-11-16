Réveil devient une simple sphère qui écoute : on ouvre l'application, on dit l'heure, l'alarme est réglée dans l'Horloge du téléphone.

## Ce qui change

- **Un seul élément à l'écran** : une sphère lumineuse animée, qui écoute dès l'ouverture et bouge avec la voix.
- **L'alarme est celle du téléphone** : l'application ne sonne plus elle-même. Elle crée l'alarme dans l'application Horloge, où elle apparaît avec la sonnerie et les réglages habituels.
- **Compris** : la sphère vire au vert et affiche le jour et l'heure retenus (« Demain à 08:30 »).
- **Pas compris** : la sphère tremble légèrement, puis réécoute.
- **Modèle de langage local inclus** (Qwen2.5-0.5B-Instruct, llama.cpp) : il prend le relais quand le parser à règles ne comprend pas la phrase.

## Installation

`reveil-v1.1.0.apk`, environ 560 Mo, pour Android 8.0 ou plus, 64 bits (arm64).

Si la version 1.0.0 est installée, la désinstaller d'abord : les deux APK ne sont pas signés avec la même clé.

## À savoir

- Cette version a été compilée et ses tests automatiques passent, mais elle n'a pas encore été essayée sur un téléphone : suivre la checklist du README au premier lancement.
- L'Horloge choisit elle-même le jour : toujours la prochaine occurrence de l'heure demandée. « Demain 8h30 » dit alors que 8h30 n'est pas encore passée est refusé, car l'Horloge sonnerait dès aujourd'hui.
- L'alarme est réglée sans confirmation : vérifier d'un coup d'œil l'heure affichée sous la sphère, surtout quand le modèle de langage a répondu (il peut se tromper).
- Au premier lancement, le modèle est copié hors de l'APK en tâche de fond : 491 Mo de stockage en plus.
- Selon la marque du téléphone, l'Horloge peut s'ouvrir brièvement au moment du réglage.
