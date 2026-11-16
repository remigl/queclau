import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Enveloppe minimale autour de la reconnaissance vocale Android.
///
/// La transcription est faite par le service de reconnaissance du téléphone
/// (hors ligne si le pack de langue français est installé) ; l'application
/// elle-même n'a aucun accès réseau.
class SpeechService {
  final SpeechToText _stt = SpeechToText();

  bool _initialized = false;
  String? _localeId;

  /// Appelé quand l'écoute se termine (avec ou sans résultat).
  void Function()? onDone;

  /// Demande l'autorisation micro si besoin et prépare la reconnaissance.
  /// Renvoie `false` si elle est indisponible ou refusée.
  Future<bool> init() async {
    if (_initialized) return true;
    try {
      _initialized = await _stt.initialize(
        onStatus: (String status) {
          if (status == 'done') onDone?.call();
        },
        onError: (SpeechRecognitionError error) => onDone?.call(),
      );
      if (_initialized) _localeId = await _pickFrenchLocale();
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  /// Le parser comprend le français : on force une locale française même si
  /// le téléphone est réglé dans une autre langue.
  Future<String?> _pickFrenchLocale() async {
    final system = await _stt.systemLocale();
    if (system != null && system.localeId.toLowerCase().startsWith('fr')) {
      return system.localeId;
    }
    final locales = await _stt.locales();
    for (final locale in locales) {
      if (locale.localeId.toLowerCase().startsWith('fr')) {
        return locale.localeId;
      }
    }
    return 'fr_FR';
  }

  /// Démarre l'écoute. [onResult] reçoit le texte reconnu au fil de l'eau.
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
  }) {
    return _stt.listen(
      localeId: _localeId,
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords, result.finalResult),
    );
  }

  Future<void> stop() => _stt.stop();
}
