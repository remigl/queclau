Première version de Réveil : un réveil Android minimaliste, réglable à la voix, entièrement local.

## Quel fichier installer

| Fichier | Taille | Contenu |
| --- | --- | --- |
| `reveil-v1.0.0.apk` | environ 560 Mo | Application complète, avec le modèle de langage local embarqué. |
| `reveil-v1.0.0-sans-modele.apk` | environ 69 Mo | Même application, sans le modèle : seul le parser à règles comprend les phrases. |

Les deux APK sont pour téléphones Android 8.0 ou plus, 64 bits (arm64). Ils sont signés avec une clé de debug : pour passer de l'un à l'autre, ou installer une version compilée ailleurs, désinstaller d'abord l'ancienne.

## Ce que fait l'application

- Dire « 8h30 », « demain 7h45 », « aujourd'hui 9h », « mets mon réveil à 6h45 » : l'heure est comprise par un parser local.
- Si l'heure est déjà passée aujourd'hui, le réveil est proposé pour demain ; sinon l'application demande « aujourd'hui ou demain ? ».
- Le réveil sonne application fermée, téléphone verrouillé, en mode silencieux et après un redémarrage.
- Quand le parser ne comprend pas la phrase, la version complète interroge un petit modèle de langage local (Qwen2.5-0.5B-Instruct, llama.cpp). L'heure qu'il propose est à vérifier avant de programmer.

## À savoir

- Cette version a été compilée et ses tests automatiques passent, mais elle n'a pas encore été essayée sur un téléphone : suivre la checklist du README au premier lancement.
- L'application programme son propre réveil ; elle ne crée pas d'alarme dans l'application Horloge du téléphone.
- Version complète : à la première utilisation du modèle, compter plusieurs secondes et 491 Mo de stockage supplémentaires.
- Sur certains téléphones (Xiaomi, Huawei, Oppo…), autoriser l'application à fonctionner sans restriction de batterie.
