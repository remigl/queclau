import 'package:flutter/services.dart';
import 'package:llamadart/llamadart.dart';

import '../models/alarm.dart';
import 'nlp_service.dart';

/// Parser de secours : un petit modèle de langage exécuté sur le téléphone
/// (llama.cpp via `llamadart`, fichier GGUF embarqué dans l'APK).
///
/// Il n'est interrogé que lorsque le parser déterministe n'a rien compris.
/// Sa réponse est contrainte par une grammaire : elle a forcément la forme
/// « demain 07:15 », « aujourdhui 20:50 », « inconnu 06:00 » ou « aucune ».
/// Un petit modèle peut se tromper : l'heure trouvée est signalée comme
/// « à vérifier » ([ParsedAlarm.fromModel]) et n'est jamais programmée sans
/// validation de l'utilisateur.
///
/// Si l'APK a été compilé sans modèle, ce parser ne renvoie simplement rien.
class LlmAlarmParser extends AlarmParser {
  static const _channel = MethodChannel('reveil/model');

  /// Sortie autorisée, au format GBNF de llama.cpp.
  static const _grammar = r'''
root ::= "aucune" | jour " " heure ":" minute
jour ::= "aujourdhui" | "demain" | "inconnu"
heure ::= [01] [0-9] | "2" [0-3]
minute ::= [0-5] [0-9]
''';

  static const _system = 'Tu extrais l’heure d’un réveil à partir d’une phrase '
      'en français. Réponds uniquement sous la forme « JOUR HH:MM », en '
      'format 24 heures. JOUR vaut « demain », « aujourdhui », ou « inconnu » '
      'si le jour n’est pas précisé. Si la phrase ne contient aucune heure, '
      'réponds « aucune ».';

  /// Exemples donnés au modèle avant la phrase de l'utilisateur.
  static const _examples = [
    ('réveille-moi à sept heures et quart demain matin', 'demain 07:15'),
    ('je dois me lever pour 6h', 'inconnu 06:00'),
    ('ce soir vers neuf heures moins dix', 'aujourdhui 20:50'),
    ('quel temps fait-il', 'aucune'),
    ('debout à midi vingt', 'inconnu 12:20'),
    ('demain je me lève à cinq heures et demie', 'demain 05:30'),
  ];

  static final _reply = RegExp(r'^(aujourdhui|demain|inconnu) (\d{2}):(\d{2})$');

  Future<LlamaEngine?>? _loading;

  /// Copie le modèle hors de l'APK au premier appel (llama.cpp a besoin d'un
  /// vrai fichier), puis le charge en mémoire. `null` si indisponible.
  Future<LlamaEngine?> _load() => _loading ??= _doLoad();

  Future<LlamaEngine?> _doLoad() async {
    try {
      final path = await _channel.invokeMethod<String>('prepare');
      if (path == null) return null;
      return await LlamaEngine.load(
        LlamaModel(ModelSource.path(path)),
        params: const ModelParams(
          contextSize: 1024,
          device: ComputeDevice.cpu,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ParsedAlarm?> parse(String text) async {
    final sentence = text.trim();
    if (sentence.isEmpty || sentence.length > 200) return null;

    final engine = await _load();
    if (engine == null) return null;

    try {
      final messages = <LlamaChatMessage>[
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: _system,
        ),
        for (final (question, answer) in _examples) ...[
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: question),
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: answer,
          ),
        ],
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: sentence),
      ];

      final reply = await engine
          .create(
            messages,
            params: const GenerationParams(
              maxTokens: 16,
              temp: 0,
              penalty: 1,
              seed: 0,
              grammar: _grammar,
            ),
            enableThinking: false,
          )
          .text()
          .timeout(const Duration(seconds: 30));

      return decode(reply);
    } catch (_) {
      return null;
    }
  }

  /// « demain 07:15 » → réveil ; « aucune » ou texte inattendu → `null`.
  static ParsedAlarm? decode(String reply) {
    final match = _reply.firstMatch(reply.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(2)!);
    final minute = int.parse(match.group(3)!);
    if (hour > 23 || minute > 59) return null;
    return ParsedAlarm(
      hour: hour,
      minute: minute,
      day: switch (match.group(1)) {
        'demain' => AlarmDay.tomorrow,
        'aujourdhui' => AlarmDay.today,
        _ => null,
      },
      fromModel: true,
    );
  }

  /// Libère la mémoire occupée par le modèle (plusieurs centaines de Mo).
  @override
  Future<void> release() async {
    final loading = _loading;
    _loading = null;
    if (loading == null) return;
    try {
      final engine = await loading;
      await engine?.dispose();
    } catch (_) {
      // Rien à faire : le modèle sera rechargé au prochain besoin.
    }
  }
}
