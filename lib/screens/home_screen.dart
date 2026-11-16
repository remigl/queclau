import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/alarm.dart';
import '../services/alarm_service.dart';
import '../services/llm_alarm_parser.dart';
import '../services/nlp_service.dart';
import '../services/speech_service.dart';
import '../widgets/orb.dart';

/// L'unique écran : une sphère qui écoute dès l'ouverture.
///
///  * heure comprise → l'alarme est réglée dans l'Horloge du téléphone ;
///  * pas compris → la sphère tremble légèrement, puis réécoute.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  /// Nombre d'essais ratés d'affilée avant de cesser de réécouter seul.
  static const _maxRetries = 3;

  final _speech = SpeechService();
  final _alarms = AlarmService();
  final _llm = LlmAlarmParser();

  // Le parser déterministe d'abord ; le modèle local seulement s'il échoue.
  late final _nlp = NlpService(parsers: [RuleBasedAlarmParser(), _llm]);

  final _level = ValueNotifier<double>(0);

  OrbState _state = OrbState.idle;
  String _heard = '';
  String? _caption;
  bool _starting = false; // démarrage de l'écoute en cours
  bool _handled = false; // le texte de l'écoute en cours a déjà été traité
  bool _speechUnavailable = false;
  bool _wasInBackground = false;
  int _failures = 0;
  DateTime? _successAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.onDone = _onListeningDone;
    // Prépare le fichier du modèle en tâche de fond (long la première fois).
    _llm.prepareFile();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speech.onDone = null;
    _speech.stop();
    _nlp.release();
    _level.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _speech.stop();
      // En arrière-plan, inutile de garder le modèle en mémoire.
      _nlp.release();

      // Régler l'alarme passe brièvement par l'Horloge : ce n'est pas un
      // vrai départ de l'utilisateur, on garde la confirmation affichée.
      final at = _successAt;
      final justSet = at != null &&
          DateTime.now().difference(at) < const Duration(seconds: 4);
      if (!justSet) {
        _wasInBackground = true;
        setState(() {
          _state = OrbState.idle;
          _caption = null;
        });
      }
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      // Retour dans l'application : on réécoute, comme à l'ouverture.
      _wasInBackground = false;
      _failures = 0;
      if (_state == OrbState.idle) _listen();
    }
  }

  // --- Écoute ---------------------------------------------------------------

  Future<void> _listen() async {
    if (_starting ||
        _state == OrbState.listening ||
        _state == OrbState.thinking) {
      return;
    }
    _starting = true;
    try {
      final available = await _speech.init();
      if (!mounted) return;
      if (!available) {
        _setSpeechUnavailable();
        return;
      }
      _level.value = 0;
      setState(() {
        _state = OrbState.listening;
        _handled = false;
        _heard = '';
        _caption = null;
      });
      await _speech.listen(
        onResult: (text, isFinal) {
          if (!mounted) return;
          _heard = text;
          if (isFinal) _understand(text);
        },
        onLevel: (level) => _level.value = level,
      );
    } catch (_) {
      if (mounted) _setSpeechUnavailable();
    } finally {
      _starting = false;
    }
  }

  void _setSpeechUnavailable() {
    setState(() {
      _speechUnavailable = true;
      _state = OrbState.idle;
      _caption = 'Micro indisponible.\nTouchez la sphère pour choisir l’heure.';
    });
  }

  Future<void> _onListeningDone() async {
    // Le résultat final peut arriver juste après la fin de l'écoute.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _handled || _state != OrbState.listening) return;
    if (_heard.trim().isEmpty) {
      // Rien entendu : on ne réécoute pas en boucle dans le silence.
      _fail(retry: false);
    } else {
      await _understand(_heard);
    }
  }

  // --- Compréhension --------------------------------------------------------

  Future<void> _understand(String text) async {
    if (_handled) return;
    _handled = true;
    setState(() => _state = OrbState.thinking);

    ParsedAlarm? parsed;
    try {
      parsed = await _nlp.parse(text);
    } catch (_) {
      parsed = null;
    }
    if (!mounted || _state != OrbState.thinking) return;

    if (parsed == null) {
      _fail(retry: true);
    } else {
      await _setAlarm(parsed.hour, parsed.minute, parsed.day);
    }
  }

  // --- Réglage de l'alarme --------------------------------------------------

  /// L'Horloge du téléphone règle toujours la *prochaine* occurrence de
  /// l'heure donnée. On refuse donc les demandes qu'elle ne peut pas honorer
  /// plutôt que de régler l'alarme sur le mauvais jour.
  Future<void> _setAlarm(int hour, int minute, AlarmDay? day) async {
    final time = formatTime(hour, minute);
    final past = isPastToday(hour, minute, DateTime.now());

    if (day == AlarmDay.tomorrow && !past) {
      _fail(
        retry: false,
        caption: 'Impossible pour demain :\n'
            'l’Horloge sonnerait dès aujourd’hui à $time.',
      );
      return;
    }
    if (day == AlarmDay.today && past) {
      _fail(retry: false, caption: '$time est déjà passée aujourd’hui.');
      return;
    }

    try {
      await _alarms.setAlarm(hour, minute);
    } on PlatformException {
      if (mounted) {
        _fail(
          retry: false,
          caption: 'L’Horloge du téléphone n’a pas accepté l’alarme.',
        );
      }
      return;
    } on MissingPluginException {
      if (mounted) _fail(retry: false);
      return;
    }
    if (!mounted) return;

    _failures = 0;
    _successAt = DateTime.now();
    HapticFeedback.mediumImpact();
    setState(() {
      _state = OrbState.success;
      _caption = '${past ? 'Demain' : 'Aujourd’hui'} à $time';
    });
  }

  /// « Pas compris » : la sphère tremble, puis réécoute (ou se met au repos).
  void _fail({required bool retry, String? caption}) {
    _failures++;
    HapticFeedback.lightImpact();
    setState(() {
      _state = OrbState.error;
      _caption = caption;
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _state != OrbState.error) return;
      setState(() => _state = OrbState.idle);
      if (retry && _failures < _maxRetries) _listen();
    });
  }

  // --- Toucher la sphère ----------------------------------------------------

  Future<void> _onTap() async {
    if (_state == OrbState.thinking) return;
    if (_state == OrbState.listening) {
      await _speech.stop();
      return;
    }
    _failures = 0;
    if (_speechUnavailable) {
      await _pickTime();
    } else {
      await _listen();
    }
  }

  /// Secours quand la reconnaissance vocale n'est pas disponible.
  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Heure de l’alarme',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    await _setAlarm(picked.hour, picked.minute, null);
  }

  // --- Interface ------------------------------------------------------------

  String get _semantics => switch (_state) {
        OrbState.listening => 'À l’écoute. Dites l’heure de l’alarme.',
        OrbState.thinking => 'Analyse en cours.',
        OrbState.success => 'Alarme réglée. ${_caption ?? ''}',
        OrbState.error => 'Je n’ai pas compris l’heure.',
        OrbState.idle => 'Toucher pour dire l’heure de l’alarme.',
      };

  @override
  Widget build(BuildContext context) {
    final diameter =
        (MediaQuery.sizeOf(context).shortestSide * 0.52).clamp(140.0, 280.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Semantics(
                  button: true,
                  liveRegion: true,
                  label: _semantics,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTap,
                    child: Orb(
                      state: _state,
                      level: _level,
                      diameter: diameter,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, 0.72),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _caption ?? '',
                      key: ValueKey(_caption),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: _state == OrbState.success ? 26 : 16,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
