# Réveil

Un réveil Android minimaliste, réglable à la voix. On ouvre l'application, on
dit « 8h30 », on valide : le réveil est programmé.

Pas de compte, pas de serveur, pas de publicité, aucune API distante.
L'application (version release) ne demande même pas l'accès à Internet.

```text
             Réveil

             08:30

          Réveil demain

      [ 🎙  Dire l'heure ]

     [ Aujourd'hui | Demain ]

    [ Programmer le réveil ]
```

## Fonctionnement

| Ce qu'on dit | Résultat |
| --- | --- |
| « 8h30 » alors qu'il est 18h | demain 08:30 (l'heure est passée aujourd'hui) |
| « 8h30 » alors qu'il est 7h | l'appli demande : aujourd'hui ou demain ? |
| « demain 7h45 » | demain 07:45 |
| « aujourd'hui 9h » | aujourd'hui 09:00 |
| « mets mon réveil à 6h45 » | 06:45, même règle de date |
| « huit heures trente », « midi et demi », « 7 heures du soir » | compris aussi |

Quand l'heure n'est pas encore passée et qu'aucun jour n'a été dit, aucun jour
n'est présélectionné : le bouton « Programmer le réveil » reste grisé tant que
l'on n'a pas choisi. C'est volontaire, un réveil réglé sur le mauvais jour
étant la pire erreur possible.

On peut aussi toucher l'heure affichée (ou « Choisir l'heure manuellement »)
pour la régler sans la voix. Un seul réveil à la fois : en programmer un
nouveau remplace l'ancien.

## Architecture

```text
lib/
  main.dart                    Application, thème Material 3
  models/alarm.dart            Alarm, ParsedAlarm, règle « heure déjà passée »
  screens/home_screen.dart     L'unique écran
  services/
    nlp_service.dart           Parser local déterministe (+ point d'extension)
    speech_service.dart        Reconnaissance vocale Android
    alarm_service.dart         Pont MethodChannel vers le Kotlin

android/app/src/main/
  AndroidManifest.xml          Permissions, receivers, service
  kotlin/com/remigl/reveil/
    MainActivity.kt            Canal « reveil/alarm »
    AlarmScheduler.kt          AlarmManager.setAlarmClock + mémorisation
    AlarmReceiver.kt           AlarmReceiver (déclenchement) + BootReceiver
    AlarmRingService.kt        Service au premier plan : son, vibration, notification
    AlarmActivity.kt           Écran de réveil plein écran, bouton « Arrêter »
  res/raw/reveil.wav           Son du réveil (embarqué)

test/nlp_service_test.dart     Tests du parser et de la règle de date
```

### Pourquoi du Kotlin natif

Un réveil doit sonner application fermée, téléphone verrouillé, en veille
profonde et après un redémarrage. Aucun moteur Flutter ne tourne à ce
moment-là : toute la chaîne de déclenchement est donc native.

1. `AlarmScheduler` programme l'alarme avec `AlarmManager.setAlarmClock()`,
   l'API prévue pour les réveils : exacte, exemptée du mode Doze, avec l'icône
   de réveil dans la barre d'état.
2. À l'heure dite, Android envoie un `PendingIntent` à `AlarmReceiver`
   (un `BroadcastReceiver`), même si le processus de l'application est mort.
3. `AlarmReceiver` démarre `AlarmRingService`, un service au premier plan qui
   joue `reveil.wav` en boucle sur le canal audio « alarme » (il sonne donc en
   mode silencieux), fait vibrer, et publie une notification avec un bouton
   « Arrêter » et un *full-screen intent*.
4. Écran verrouillé ou éteint, ce *full-screen intent* ouvre `AlarmActivity`
   par-dessus l'écran de verrouillage. Écran allumé, la notification s'affiche
   en bandeau avec son bouton « Arrêter ».
5. `BootReceiver` reprogramme l'alarme après un redémarrage (AlarmManager
   oublie tout), y compris avant le premier déverrouillage du téléphone, et
   après un changement d'heure ou de fuseau.

La sonnerie s'arrête d'elle-même au bout de 10 minutes. Si le volume
« alarme » du téléphone est à zéro, il est remonté à environ 60 %.

### Fuseau horaire

Le package `timezone` n'est pas utilisé, car rien n'est converti côté Dart.
Dart ne transmet que l'heure « murale » (année, mois, jour, heure, minute) ;
la conversion en instant réel est faite en Kotlin avec `java.time` et le
fuseau courant du téléphone (`ZoneId.systemDefault()`). Si le téléphone
change de fuseau ou d'heure, `BootReceiver` recalcule l'instant : un réveil
réglé sur 8h30 sonne à 8h30 de l'horloge du téléphone, changement d'heure
compris. « Demain » est calculé par jour calendaire, jamais par « + 24 h ».

### Permissions

| Permission | Rôle |
| --- | --- |
| `RECORD_AUDIO` | Micro pour la reconnaissance vocale (demandée au premier appui sur le micro). |
| `USE_EXACT_ALARM` | Android 13+ : alarmes exactes pour les applications de réveil. Accordée à l'installation. |
| `SCHEDULE_EXACT_ALARM` (≤ Android 12L) | Android 12 / 12L : alarmes exactes. Accordée par défaut, révocable ; si elle est révoquée, l'appli affiche un bouton vers le réglage système. |
| `POST_NOTIFICATIONS` | Android 13+ : notification du réveil (demandée à la première programmation). |
| `USE_FULL_SCREEN_INTENT` | Écran de réveil par-dessus l'écran verrouillé. |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Service qui joue la sonnerie. |
| `WAKE_LOCK`, `VIBRATE` | Garder le processeur éveillé pendant la sonnerie ; vibration. |
| `RECEIVE_BOOT_COMPLETED` | Reprogrammer le réveil après un redémarrage. |

Si les notifications sont refusées, le réveil sonne quand même, mais ni la
notification ni l'écran de réveil n'apparaissent : il faut alors ouvrir
l'application, qui affiche l'écran « Arrêter ».

### Voix et hors-ligne

La transcription est faite par le service de reconnaissance vocale du
téléphone (`speech_to_text`), pas par l'application. Elle fonctionne hors
ligne si le pack de langue français est installé sur le téléphone
(Réglages > Système > Langues > Reconnaissance vocale sur l'appareil, selon
les modèles) ; sinon ce service peut passer par le réseau. La compréhension
du texte, elle, est toujours locale.

### Ajouter plus tard un petit modèle local

`nlp_service.dart` définit l'interface `AlarmParser`. `NlpService` interroge
ses parsers dans l'ordre et garde le premier résultat. Pour brancher un petit
modèle (par exemple un GGUF via llama.cpp) en secours, il suffit d'écrire une
classe qui implémente `AlarmParser` et de l'ajouter après le parser
déterministe :

```dart
NlpService(parsers: [RuleBasedAlarmParser(), MonParserLlmLocal()]);
```

Pour le MVP, aucun modèle n'est embarqué : le parser à règles couvre les
formulations d'heure courantes et ne pèse rien.

## Dépendances

- `speech_to_text` : reconnaissance vocale Android.
- `flutter_localizations` (fourni par le SDK) : sélecteur d'heure en français.

C'est tout. Pas de `flutter_local_notifications` ni de `timezone` : la
notification et le fuseau sont gérés directement en Kotlin.

## Compiler

Prérequis : Flutter stable récent (3.29 ou plus), Android SDK, JDK 17.

```bash
flutter pub get
flutter build apk --release
```

L'APK est produit dans `build/app/outputs/flutter-apk/app-release.apk`.

Le dépôt ne contient pas les fichiers que Flutter génère lui-même
(`gradlew`, `gradle-wrapper.jar`, `local.properties`) : ils sont créés au
premier build. Si le build se plaint d'un fichier Android manquant, cette
commande les recrée sans toucher aux fichiers existants :

```bash
flutter create --platforms=android --project-name reveil --org com.remigl .
```

L'APK release est signé avec la clé de debug (suffisant pour une installation
personnelle ; à remplacer avant toute publication).

Tests du parser :

```bash
flutter test
```

## Installer sur le téléphone

Par USB :

1. Sur le téléphone : Réglages > À propos > toucher 7 fois « Numéro de
   build », puis Réglages > Options pour les développeurs > activer le
   « Débogage USB ».
2. Brancher le téléphone, accepter la demande d'autorisation, puis :

```bash
flutter install --release
# ou
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Sans câble : copier `app-release.apk` sur le téléphone, l'ouvrir depuis le
gestionnaire de fichiers et autoriser l'installation depuis cette source.

### Réglages à vérifier sur certains téléphones

Xiaomi, Huawei, Oppo, OnePlus, Samsung et d'autres ajoutent leur propre
gestion de batterie, qui peut bloquer les alarmes des applications
installées hors du Play Store. Si le réveil ne sonne pas application fermée :

- Réglages > Applis > Réveil > Batterie : choisir « Non restreinte ».
- Xiaomi / Oppo : activer « Démarrage automatique » pour Réveil.
- Vérifier que les notifications de Réveil sont autorisées.

## Checklist de test

Régler à chaque fois un réveil 2 ou 3 minutes plus tard.

- [ ] Dire « 8h30 » : 08:30 s'affiche.
- [ ] Si 8h30 est déjà passée : « Demain » est sélectionné et « Aujourd'hui » est grisé.
- [ ] Si 8h30 n'est pas passée : aucun jour sélectionné, le bouton est grisé.
- [ ] Choisir « Aujourd'hui », programmer : « ✓ Réveil programmé / Aujourd'hui à … ».
- [ ] Choisir « Demain », programmer : « ✓ Réveil programmé / Demain à … ».
- [ ] Dire « demain 7h45 » puis « aujourd'hui » + une heure proche : le jour est présélectionné.
- [ ] Dire « bonjour » : message « Je n'ai pas compris l'heure ».
- [ ] Toucher l'heure : le sélecteur manuel s'ouvre.
- [ ] L'icône de réveil apparaît dans la barre d'état d'Android.
- [ ] Fermer l'application (la retirer des applications récentes).
- [ ] Verrouiller le téléphone.
- [ ] Attendre l'heure du réveil.
- [ ] Le son se déclenche, l'écran s'allume sur l'écran de réveil.
- [ ] « Arrêter » coupe le son et la vibration.
- [ ] Même test téléphone déverrouillé : bandeau de notification avec « Arrêter ».
- [ ] Même test en mode silencieux : le réveil sonne.
- [ ] Programmer, redémarrer le téléphone, ne pas ouvrir l'appli : le réveil sonne.
- [ ] « Annuler le réveil » : l'icône de réveil disparaît et rien ne sonne.
