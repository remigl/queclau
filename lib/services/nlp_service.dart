import 'dart:async';

import '../models/alarm.dart';

/// Contrat commun à tout ce qui sait transformer un texte en réveil.
///
/// Le retour est un [FutureOr] : le parser déterministe répond tout de suite,
/// le modèle local (`LlmAlarmParser`, un petit GGUF via llama.cpp) répond de
/// façon asynchrone, derrière la même interface.
abstract class AlarmParser {
  FutureOr<ParsedAlarm?> parse(String text);

  /// Libère les ressources lourdes éventuelles (modèle en mémoire).
  Future<void> release() async {}
}

/// Point d'entrée de la compréhension : interroge les parsers dans l'ordre et
/// renvoie le premier résultat.
///
/// Par défaut, seul le parser déterministe est branché. L'application y
/// ajoute le modèle local en secours :
///
/// ```dart
/// NlpService(parsers: [RuleBasedAlarmParser(), LlmAlarmParser()]);
/// ```
class NlpService {
  NlpService({List<AlarmParser>? parsers})
      : _parsers = parsers ?? [RuleBasedAlarmParser()];

  final List<AlarmParser> _parsers;

  Future<ParsedAlarm?> parse(String text) async {
    for (final parser in _parsers) {
      final result = await parser.parse(text);
      if (result != null) return result;
    }
    return null;
  }

  Future<void> release() async {
    for (final parser in _parsers) {
      await parser.release();
    }
  }
}

/// Parser déterministe, 100 % local, pour le français courant.
///
/// Comprend notamment : « 8h30 », « 8:30 », « 8 h 30 », « 8 heures »,
/// « huit heures trente », « midi et demi », « 9 heures moins le quart »,
/// « 7 heures du soir », avec ou sans « demain » / « aujourd'hui », y compris
/// au milieu d'une phrase (« mets mon réveil à 6h45 »).
class RuleBasedAlarmParser extends AlarmParser {
  // « 8h30 », « 8 h », « 8 heures 30 »
  static final _hourMarker =
      RegExp(r'\b(\d{1,2})\s*(?:heures?|h)(?![a-z])\s*(\d{1,2})?(?!\d)');
  // « 8:30 », « 8.30 »
  static final _separator = RegExp(r'\b(\d{1,2})\s*[:.]\s*(\d{2})\b');
  // Mots tolérés autour d'une heure donnée sans « h » (« demain à 8 30 »).
  static final _filler = RegExp(
      r'\b(demain|aujourd hui|a|pour|vers|ce|cet|du|de|l|le|matin|soir)\b');
  static final _bare = RegExp(r'^(\d{1,2})(?: (\d{2}))?$');
  static final _compact = RegExp(r'^(\d{1,2})(\d{2})$');

  @override
  ParsedAlarm? parse(String text) {
    var t = _normalize(text);
    if (t.isEmpty) return null;

    // Non géré : mieux vaut ne pas comprendre que programmer le mauvais jour.
    if (RegExp(r'\bapres demain\b').hasMatch(t)) return null;

    AlarmDay? day;
    if (RegExp(r'\bdemain\b').hasMatch(t)) {
      day = AlarmDay.tomorrow;
    } else if (RegExp(r'\b(aujourd hui|ce soir|ce matin|cet apres midi)\b')
        .hasMatch(t)) {
      day = AlarmDay.today;
    }

    // « du soir » / « de l'après-midi » : format 12 heures.
    final pm = RegExp(r'\b(apres midi|soir)\b').hasMatch(t);
    t = t.replaceAll(RegExp(r'\bapres midi\b'), ' ');

    t = _numberWordsToDigits(t);
    t = t
        .replaceAll(RegExp(r'\bmidi\b'), '12 h')
        .replaceAll(RegExp(r'\bminuit\b'), '0 h')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    int? hour;
    var minute = 0;
    var minus = 0;

    final m = _hourMarker.firstMatch(t);
    if (m != null) {
      hour = int.parse(m.group(1)!);
      if (m.group(2) != null) {
        minute = int.parse(m.group(2)!);
      } else {
        final rest = t.substring(m.end).trimLeft();
        final moins = RegExp(r'^moins (\d{1,2})\b').firstMatch(rest);
        if (rest.startsWith('et demi')) {
          minute = 30;
        } else if (rest.startsWith('et quart')) {
          minute = 15;
        } else if (rest.startsWith('moins le quart')) {
          minus = 15;
        } else if (moins != null) {
          minus = int.parse(moins.group(1)!);
        }
      }
    } else {
      final s = _separator.firstMatch(t);
      if (s != null) {
        hour = int.parse(s.group(1)!);
        minute = int.parse(s.group(2)!);
      } else {
        // Heure « nue » : acceptée seulement si le texte ne contient rien
        // d'autre que des mots attendus, pour éviter les faux positifs.
        final stripped = t
            .replaceAll(_filler, ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final b = _bare.firstMatch(stripped) ?? _compact.firstMatch(stripped);
        if (b == null) return null;
        hour = int.parse(b.group(1)!);
        minute = b.group(2) == null ? 0 : int.parse(b.group(2)!);
      }
    }

    if (hour > 23 || minute > 59 || minus > 59) return null;
    if (pm && hour >= 1 && hour <= 11) hour += 12;

    final total = (hour * 60 + minute - minus) % (24 * 60);
    return ParsedAlarm(hour: total ~/ 60, minute: total % 60, day: day);
  }

  // --- Normalisation -------------------------------------------------------

  static const _accents = {
    'à': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
  };

  /// Minuscules, sans accents, apostrophes et traits d'union remplacés par
  /// des espaces (« aujourd'hui » → « aujourd hui », « dix-sept » → « dix sept »).
  static String _normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      if ("'’‘`´-–—,;!?  ".contains(char)) {
        buffer.write(' ');
      } else {
        buffer.write(_accents[char] ?? char);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // --- Nombres en toutes lettres ------------------------------------------

  static const _units = {
    'zero': 0, 'un': 1, 'une': 1, 'deux': 2, 'trois': 3, 'quatre': 4,
    'cinq': 5, 'six': 6, 'sept': 7, 'huit': 8, 'neuf': 9, 'dix': 10,
    'onze': 11, 'douze': 12, 'treize': 13, 'quatorze': 14, 'quinze': 15,
    'seize': 16,
  };

  static const _tens = {
    'vingt': 20, 'trente': 30, 'quarante': 40, 'cinquante': 50,
  };

  /// « huit heures trente » → « 8 heures 30 » (nombres de 0 à 59).
  static String _numberWordsToDigits(String text) {
    final tokens = text.split(' ');
    final out = <String>[];

    int? digit(int index) {
      if (index >= tokens.length) return null;
      final value = _units[tokens[index]];
      return (value != null && value >= 1 && value <= 9) ? value : null;
    }

    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      final tens = _tens[token];
      if (tens != null) {
        if (i + 2 < tokens.length &&
            tokens[i + 1] == 'et' &&
            digit(i + 2) == 1) {
          out.add('${tens + 1}'); // vingt et un
          i += 3;
        } else if (digit(i + 1) != null) {
          out.add('${tens + digit(i + 1)!}'); // vingt deux
          i += 2;
        } else {
          out.add('$tens');
          i += 1;
        }
      } else if (token == 'dix' && digit(i + 1) != null && digit(i + 1)! >= 7) {
        out.add('${10 + digit(i + 1)!}'); // dix sept, dix huit, dix neuf
        i += 2;
      } else if (token == 'zero' && digit(i + 1) != null) {
        out.add('0${digit(i + 1)!}'); // « zéro cinq » → 05
        i += 2;
      } else if (_units.containsKey(token)) {
        out.add('${_units[token]}');
        i += 1;
      } else {
        out.add(token);
        i += 1;
      }
    }
    return out.join(' ');
  }
}
