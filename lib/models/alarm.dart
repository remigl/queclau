/// Jour visé par un réveil, relatif à « maintenant ».
enum AlarmDay { today, tomorrow }

/// Résultat de la compréhension d'une commande (« demain 7h45 »).
///
/// [day] vaut `null` quand l'utilisateur n'a donné qu'une heure : c'est alors
/// l'écran qui décide (demain si l'heure est passée, sinon choix proposé).
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

  /// Vrai si l'heure a été déduite par le modèle de langage local (moins
  /// fiable que le parser déterministe) : l'écran demande alors de vérifier.
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

/// Un réveil programmé, exprimé en date et heure « murales » (celles affichées
/// par l'horloge du téléphone).
///
/// On ne manipule volontairement aucun instant absolu côté Dart : la
/// conversion en instant réel est faite côté Android avec le fuseau du
/// téléphone (voir AlarmScheduler.kt), ce qui évite tout décalage lié au
/// fuseau ou au changement d'heure.
class Alarm {
  const Alarm({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
  });

  /// Construit le réveil pour aujourd'hui ou demain à partir de [now].
  factory Alarm.forDay(AlarmDay day, int hour, int minute, DateTime now) {
    // Arithmétique calendaire (jour + 1) et non « + 24 heures » : reste exact
    // les jours de changement d'heure.
    final date = DateTime(
      now.year,
      now.month,
      now.day + (day == AlarmDay.tomorrow ? 1 : 0),
    );
    return Alarm(
      year: date.year,
      month: date.month,
      day: date.day,
      hour: hour,
      minute: minute,
    );
  }

  factory Alarm.fromMap(Map<dynamic, dynamic> map) => Alarm(
        year: map['year'] as int,
        month: map['month'] as int,
        day: map['day'] as int,
        hour: map['hour'] as int,
        minute: map['minute'] as int,
      );

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;

  Map<String, int> toMap() => {
        'year': year,
        'month': month,
        'day': day,
        'hour': hour,
        'minute': minute,
      };

  String get timeLabel => formatTime(hour, minute);

  /// « Aujourd'hui », « Demain » ou, à défaut, la date (JJ/MM).
  String dayLabel(DateTime now) {
    bool sameDate(DateTime d) =>
        d.year == year && d.month == month && d.day == day;
    if (sameDate(now)) return 'Aujourd’hui';
    if (sameDate(DateTime(now.year, now.month, now.day + 1))) return 'Demain';
    return 'Le ${_two(day)}/${_two(month)}';
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 8, 30 → « 08:30 ».
String formatTime(int hour, int minute) => '${_two(hour)}:${_two(minute)}';

/// Vrai si l'heure donnée est déjà passée (ou en cours) aujourd'hui.
bool isPastToday(int hour, int minute, DateTime now) =>
    hour * 60 + minute <= now.hour * 60 + now.minute;
