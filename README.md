# Réveil

On ouvre l'application, une sphère lumineuse attend qu'on parle. On dit
« 8h30 » : l'alarme est réglée dans l'Horloge du téléphone. C'est tout.

Pas de compte, pas de serveur, pas de publicité, aucune API distante.
L'application ne demande même pas l'accès à Internet.

## Fonctionnement

| La sphère | Signification |
| --- | --- |
| Colorée, elle bouge avec la voix | Elle écoute (dès l'ouverture de l'application). |
| Les couleurs tournent vite | Elle analyse la phrase. |
| Elle vire au vert, avec « Demain à 08:30 » | L'alarme est réglée dans l'Horloge. |
| Elle tremble légèrement | Elle n'a pas compris ; elle réécoute aussitôt. |
| Sombre et lente | Au repos. La toucher relance l'écoute. |

Après trois essais ratés d'affilée, ou si elle n'a rien entendu, la sphère se
met au repos au lieu de réécouter en boucle. La toucher pendant l'écoute
arrête l'écoute.

Phrases comprises : « 8h30 », « 8:30 », « 8 heures », « huit heures trente »,
« midi et demi », « 7 heures du soir », « neuf heures moins le quart »,
« mets mon réveil à 6h45 », « demain 7h45 », « aujourd'hui 9h »…

### C'est l'Horloge du téléphone qui sonne

L'application ne fait pas sonner d'alarme elle-même. Elle demande à
l'application Horloge du téléphone d'en créer une (intent Android standard
`ACTION_SET_ALARM`). L'alarme apparaît donc dans la liste de l'Horloge, avec
sa sonnerie, son bouton « Répéter » et ses réglages, et c'est là qu'on la
modifie ou qu'on la supprime.

Conséquence : **l'Horloge choisit elle-même le jour**, toujours la prochaine
occurrence de l'heure demandée. « 8h30 » dit à 18h sonnera demain ; dit à 7h,
il sonnera aujourd'hui. L'application affiche le jour retenu (« Demain à
08:30 »). Deux demandes ne peuvent pas être honorées, et sont refusées avec
une explication plutôt que réglées sur le mauvais jour :

- « demain 8h30 » dit à 7h (l'Horloge sonnerait dès aujourd'hui) ;
- « aujourd'hui 9h » dit à 10h (l'heure est passée).

Selon la marque du téléphone, l'Horloge peut afficher un court message de
confirmation, ou s'ouvrir brièvement.

### Comprendre la phrase

Tout est local, en deux temps :

1. **Un parser à règles** (`RuleBasedAlarmParser`), instantané et prévisible,
   traite les formulations courantes.
2. S'il ne comprend pas, **un petit modèle de langage** prend le relais
   (`LlmAlarmParser`) : Qwen2.5-0.5B-Instruct (Alibaba, licence Apache 2.0),
   quantifié Q4_K_M, au format GGUF (491 Mo), exécuté par llama.cpp via le
   package `llamadart`. Sa réponse est contrainte par une grammaire : il ne
   peut répondre que « demain 07:15 », « aujourdhui 20:50 »,
   « inconnu 06:00 » ou « aucune ».

À savoir sur le modèle :

- un modèle de cette taille peut se tromper d'heure, et l'alarme est réglée
  sans confirmation : l'heure retenue s'affiche sous la sphère, à vérifier
  d'un coup d'œil ;
- son fichier est embarqué dans l'APK (environ 560 Mo au total) puis copié
  une fois hors de l'APK au premier lancement, en tâche de fond : 491 Mo de
  stockage en plus ;
- il n'est chargé en mémoire que lorsqu'il sert, et déchargé dès que
  l'application passe en arrière-plan ; sa réponse prend quelques secondes ;
- les heures relatives (« dans vingt minutes ») ne sont pas gérées.

La transcription de la voix est faite par le service de reconnaissance vocale
du téléphone (`speech_to_text`). Elle fonctionne hors ligne si le pack de
langue français y est installé ; sinon ce service peut passer par le réseau.

Si la reconnaissance vocale est indisponible ou le micro refusé, toucher la
sphère ouvre un sélecteur d'heure.

## Architecture

```text
lib/
  main.dart                    Application, thème sombre
  models/alarm.dart            ParsedAlarm, règle « heure déjà passée »
  screens/home_screen.dart     L'unique écran : écoute, compréhension, réglage
  widgets/orb.dart             La sphère animée
  services/
    speech_service.dart        Reconnaissance vocale Android
    nlp_service.dart           Parser à règles (prioritaire)
    llm_alarm_parser.dart      Modèle de langage local (secours)
    alarm_service.dart         Pont MethodChannel vers le Kotlin

android/app/src/main/
  AndroidManifest.xml          Permissions
  kotlin/com/remigl/reveil/
    MainActivity.kt            Règle l'alarme dans l'Horloge (ACTION_SET_ALARM)
    ModelFiles.kt              Copie du modèle hors de l'APK
  assets/models/               Modèle GGUF (téléchargé par tool/fetch_model.sh)

test/nlp_service_test.dart     Tests du parser
tool/fetch_model.sh            Télécharge le modèle de langage
.github/workflows/build.yml    Build de l'APK et release
```

### Permissions

| Permission | Rôle |
| --- | --- |
| `RECORD_AUDIO` | Micro pour la reconnaissance vocale (demandée au premier lancement). |
| `com.android.alarm.permission.SET_ALARM` | Créer une alarme dans l'Horloge. Accordée à l'installation. |

### Dépendances

- `material_ui` : composants Material 3.
- `speech_to_text` : reconnaissance vocale Android.
- `llamadart` : llama.cpp, pour le modèle de langage local.

## Compiler

Prérequis : Flutter 3.50 ou plus, Android SDK, JDK 17.

```bash
tool/fetch_model.sh          # télécharge le modèle (491 Mo)
flutter pub get
flutter build apk --release
```

L'APK est produit dans `build/app/outputs/flutter-apk/app-release.apk`.
Ajouter `--target-platform android-arm64` pour un APK plus léger, limité aux
téléphones 64 bits (tous les téléphones récents).

Sans `tool/fetch_model.sh`, l'application se compile et fonctionne avec le
seul parser à règles. Au premier build, `llamadart` télécharge ses
bibliothèques natives précompilées : il faut une connexion à ce moment-là.

Le dépôt ne contient pas les fichiers que Flutter génère lui-même
(`gradlew`, `gradle-wrapper.jar`, `local.properties`) : ils sont créés au
premier build.

Tests du parser :

```bash
flutter test
```

### Releases

Chaque push sur `main` compile l'application sur GitHub Actions
(`.github/workflows/build.yml`). Si la version de `pubspec.yaml` n'a pas
encore de release GitHub, elle est publiée avec l'APK arm64. Pour sortir une
nouvelle version : augmenter `version:` dans `pubspec.yaml`, mettre à jour
`RELEASE_NOTES.md`, pousser sur `main`. Si un build échoue, son journal est
poussé sur la branche `ci-logs`.

L'APK est signé avec une clé de debug propre à chaque build : pour installer
une nouvelle version, il faut d'abord désinstaller la précédente.

## Installer sur le téléphone

Télécharger l'APK depuis la page
[Releases](https://github.com/remigl/queclau/releases) sur le téléphone,
l'ouvrir et autoriser l'installation depuis cette source.

Par USB, avec le débogage USB activé :

```bash
adb install -r reveil-v1.1.0.apk
```

## Checklist de test

- [ ] Ouvrir l'application : la sphère s'anime, le micro écoute.
- [ ] Premier lancement : accepter la demande d'accès au micro.
- [ ] Parler : la sphère gonfle avec la voix.
- [ ] Dire « 8h30 » : la sphère vire au vert, « Demain à 08:30 » ou
      « Aujourd'hui à 08:30 » s'affiche.
- [ ] Ouvrir l'Horloge du téléphone : l'alarme de 08:30 y figure, activée.
- [ ] Dire « bonjour » : la sphère tremble, puis réécoute.
- [ ] Ne rien dire : la sphère tremble puis se met au repos ; la toucher
      relance l'écoute.
- [ ] Dire « je dois me lever pour six heures » (non couvert par les
      règles) : les couleurs tournent quelques secondes, puis 06:00 est réglé.
- [ ] Dire « demain » + une heure encore à venir aujourd'hui : refus avec
      l'explication.
- [ ] Quitter puis rouvrir l'application : elle réécoute aussitôt.
- [ ] Régler une alarme 2 minutes plus tard, verrouiller le téléphone :
      l'Horloge sonne.
