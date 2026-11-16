import 'package:flutter_test/flutter_test.dart';
import 'package:reveil/models/alarm.dart';
import 'package:reveil/services/nlp_service.dart';

void main() {
  final nlp = NlpService();

  Future<void> expectParse(
    String text,
    int hour,
    int minute, [
    AlarmDay? day,
  ]) async {
    expect(
      await nlp.parse(text),
      ParsedAlarm(hour: hour, minute: minute, day: day),
      reason: text,
    );
  }

  test('formats chiffrés', () async {
    await expectParse('8h30', 8, 30);
    await expectParse('08:30', 8, 30);
    await expectParse('8 h 30', 8, 30);
    await expectParse('8 heures', 8, 0);
    await expectParse('7h', 7, 0);
    await expectParse('20h05', 20, 5);
    await expectParse('8 30', 8, 30);
  });

  test('nombres en toutes lettres', () async {
    await expectParse('huit heures trente', 8, 30);
    await expectParse('sept heures quarante-cinq', 7, 45);
    await expectParse('vingt et une heures', 21, 0);
    await expectParse('dix-sept heures', 17, 0);
    await expectParse('midi et demi', 12, 30);
    await expectParse('neuf heures moins le quart', 8, 45);
    await expectParse('sept heures du soir', 19, 0);
  });

  test('jour explicite', () async {
    await expectParse('demain 8h30', 8, 30, AlarmDay.tomorrow);
    await expectParse('demain à 7 heures', 7, 0, AlarmDay.tomorrow);
    await expectParse('demain 7h45', 7, 45, AlarmDay.tomorrow);
    await expectParse("aujourd'hui 9h15", 9, 15, AlarmDay.today);
    await expectParse('aujourd’hui 9h', 9, 0, AlarmDay.today);
  });

  test('phrase complète', () async {
    await expectParse('mets mon réveil à 6h45', 6, 45);
    await expectParse('Réveille-moi demain à 6 heures et quart', 6, 15,
        AlarmDay.tomorrow);
  });

  test('texte incompréhensible', () async {
    expect(await nlp.parse(''), isNull);
    expect(await nlp.parse('bonjour'), isNull);
    expect(await nlp.parse('25h00'), isNull);
    expect(await nlp.parse('8h75'), isNull);
    expect(await nlp.parse('après-demain 8h'), isNull);
  });

  test('règle de date', () {
    final evening = DateTime(2026, 11, 16, 18, 0);
    final morning = DateTime(2026, 11, 16, 7, 0);
    expect(isPastToday(8, 30, evening), isTrue);
    expect(isPastToday(8, 30, morning), isFalse);

    final lastDay = DateTime(2026, 12, 31, 23, 0);
    final alarm = Alarm.forDay(AlarmDay.tomorrow, 8, 30, lastDay);
    expect([alarm.year, alarm.month, alarm.day], [2027, 1, 1]);
    expect(alarm.dayLabel(lastDay), 'Demain');
  });
}
