import 'package:flutter/services.dart';

/// Règle une alarme dans l'application Horloge du téléphone.
///
/// Côté Android (MainActivity.kt), c'est l'intent standard
/// `AlarmClock.ACTION_SET_ALARM` : l'alarme appartient à l'Horloge, qui la
/// fait sonner avec sa sonnerie, son bouton « Répéter » et ses réglages.
/// L'Horloge choisit elle-même le jour : la prochaine occurrence de l'heure.
class AlarmService {
  static const _channel = MethodChannel('reveil/alarm');

  /// Lève une [PlatformException] si aucune application Horloge n'accepte
  /// la demande.
  Future<void> setAlarm(int hour, int minute) => _channel
      .invokeMethod<void>('setAlarm', {'hour': hour, 'minute': minute});
}
