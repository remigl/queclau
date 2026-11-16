/// Jour visé par une alarme, relatif à « maintenant ».
enum AlarmDay { today, tomorrow }

/// Résultat de la compréhension d'une commande (« demain 7h45 »).
///
/// [day] vaut `null` quand l'utilisateur n'a donné qu'une heure.
class ParsedAlarm {
  const ParsedAlarm({
    required this.hour,
    required this.minute,
    this.day,
    this.fromModel = false,
  });

  final int hour;
  final int minute;
  final AlarmDay? day;

  /// Vrai si l'heure a été déduite par le modèle de langage local plutôt que
  /// par le parser déterministe.
  final bool fromModel;

  @override
  bool operator ==(Object other) =>
      other is ParsedAlarm &&
      other.hour == hour &&
      other.minute == minute &&
      other.day == day &&
      other.fromModel == fromModel;

  @override
  int get hashCode => Object.hash(hour, minute, day, fromModel);

  @override
  String toString() => 'ParsedAlarm(${formatTime(hour, minute)}, $day)';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 8, 30 → « 08:30 ».
String formatTime(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// Vrai si l'heure donnée est déjà passée (ou en cours) aujourd'hui.
///
/// L'Horloge du téléphone règle toujours la prochaine occurrence d'une heure :
/// si elle est passée, l'alarme sonnera demain.
bool isPastToday(int hour, int minute, DateTime now) =>
    hour * 60 + minute <= now.hour * 60 + now.minute;
