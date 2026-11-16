import 'package:flutter/services.dart';

import '../models/alarm.dart';

/// Pont vers le code Android natif (MainActivity.kt / AlarmScheduler.kt).
///
/// Toute la programmation réelle (AlarmManager, sonnerie, redémarrage du
/// téléphone) vit côté Kotlin : elle doit fonctionner application fermée,
/// donc sans moteur Flutter.
class AlarmService {
  static const _channel = MethodChannel('reveil/alarm');

  /// Code d'erreur : l'heure demandée est déjà passée.
  static const errorPast = 'past';

  /// Code d'erreur : l'autorisation « alarmes exactes » est refusée.
  static const errorExactAlarmDenied = 'exact_alarm_denied';

  /// Programme (ou remplace) le réveil. Lève une [PlatformException] avec
  /// [errorPast] ou [errorExactAlarmDenied] en cas d'échec.
  Future<void> schedule(Alarm alarm) =>
      _channel.invokeMethod<void>('schedule', alarm.toMap());

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  /// Le réveil actuellement programmé, s'il y en a un.
  Future<Alarm?> current() async {
    final map = await _channel.invokeMapMethod<String, dynamic>('getAlarm');
    return map == null ? null : Alarm.fromMap(map);
  }

  /// Ouvre l'écran système « Alarmes et rappels » (Android 12 et 12L).
  Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod<void>('openExactAlarmSettings');

  /// Demande l'autorisation d'afficher des notifications (Android 13+).
  Future<bool> requestNotificationPermission() async =>
      await _channel.invokeMethod<bool>('requestNotificationPermission') ??
      false;
}
