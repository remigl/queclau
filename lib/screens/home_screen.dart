import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../models/alarm.dart';
import '../services/alarm_service.dart';
import '../services/nlp_service.dart';
import '../services/speech_service.dart';

/// L'unique écran de l'application.
///
/// Deux états simples :
///  * un « brouillon » ([_hour], [_minute], [_day]) : l'heure dite ou choisie,
///    pas encore programmée ;
///  * le réveil réellement programmé côté Android ([_scheduled]).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _notUnderstood = 'Je n’ai pas compris l’heure.\n\n'
      'Essayez :\n« 8h30 »\n« demain 7h45 »';
  static const _speechUnavailableText =
      'La reconnaissance vocale n’est pas disponible.\n'
      'Choisissez l’heure manuellement.';

  final _speech = SpeechService();
  final _nlp = NlpService();
  final _alarms = AlarmService();

  // Brouillon en cours.
  int? _hour;
  int? _minute;
  AlarmDay? _day;

  // Réveil programmé côté Android.
  Alarm? _scheduled;

  bool _listening = false;
  bool _handled = false; // le texte de l'écoute en cours a déjà été traité
  bool _speechUnavailable = false;
  bool _exactAlarmDenied = false;
  String _heard = '';
  String? _message;

  bool get _hasDraft => _hour != null && _minute != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.onDone = _onListeningDone;
    _refreshScheduled();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speech.onDone = null;
    _speech.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour dans l'application, le réveil a pu sonner entre-temps.
    if (state == AppLifecycleState.resumed) _refreshScheduled();
  }

  Future<void> _refreshScheduled() async {
    try {
      final alarm = await _alarms.current();
      if (mounted) setState(() => _scheduled = alarm);
    } on PlatformException {
      // Sans réponse du côté natif, on affiche simplement « aucun réveil ».
    } on MissingPluginException {
      // Idem (tests, plateforme non Android).
    }
  }

  // --- Voix ----------------------------------------------------------------

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      return;
    }

    final available = await _speech.init();
    if (!mounted) return;
    if (!available) {
      setState(() {
        _speechUnavailable = true;
        _message = _speechUnavailableText;
      });
      return;
    }

    setState(() {
      _listening = true;
      _handled = false;
      _heard = '';
      _message = null;
    });

    try {
      await _speech.listen(
        onResult: (text, isFinal) {
          if (!mounted) return;
          setState(() => _heard = text);
          if (isFinal) _understand(text);
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listening = false;
        _speechUnavailable = true;
        _message = _speechUnavailableText;
      });
    }
  }

  Future<void> _onListeningDone() async {
    if (!mounted) return;
    setState(() => _listening = false);
    // Le résultat final peut arriver juste après la fin de l'écoute.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _handled || _listening) return;
    if (_heard.trim().isEmpty) {
      setState(() => _message = _notUnderstood);
    } else {
      await _understand(_heard);
    }
  }

  Future<void> _understand(String text) async {
    if (_handled) return;
    _handled = true;
    final parsed = await _nlp.parse(text);
    if (!mounted) return;
    if (parsed == null) {
      setState(() => _message = _notUnderstood);
    } else {
      _applyTime(parsed.hour, parsed.minute, parsed.day);
    }
  }

  // --- Choix de l'heure et du jour ----------------------------------------

  /// Applique la règle de date :
  ///  * heure déjà passée aujourd'hui → demain ;
  ///  * jour dit explicitement → ce jour ;
  ///  * sinon → aucun jour présélectionné, l'utilisateur choisit.
  void _applyTime(int hour, int minute, AlarmDay? requestedDay) {
    final past = isPastToday(hour, minute, DateTime.now());
    setState(() {
      _hour = hour;
      _minute = minute;
      _day = past ? AlarmDay.tomorrow : requestedDay;
      _exactAlarmDenied = false;
      _message = (past && requestedDay == AlarmDay.today)
          ? '${formatTime(hour, minute)} est déjà passée aujourd’hui : '
              'réveil proposé pour demain.'
          : null;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _hour ?? _scheduled?.hour ?? 8,
        minute: _minute ?? _scheduled?.minute ?? 0,
      ),
      helpText: 'Heure du réveil',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    _applyTime(picked.hour, picked.minute, _day);
  }

  // --- Programmation -------------------------------------------------------

  Future<void> _schedule() async {
    final day = _day;
    if (!_hasDraft || day == null) return;
    final alarm = Alarm.forDay(day, _hour!, _minute!, DateTime.now());

    try {
      // Android 13+ : sans cette autorisation, le réveil sonne quand même
      // mais l'écran et la notification « Arrêter » ne s'affichent pas.
      await _alarms.requestNotificationPermission();
      await _alarms.schedule(alarm);
      if (!mounted) return;
      setState(() {
        _scheduled = alarm;
        _hour = null;
        _minute = null;
        _day = null;
        _heard = '';
        _message = null;
        _exactAlarmDenied = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (e.code) {
          case AlarmService.errorPast:
            _day = AlarmDay.tomorrow;
            _message = 'Cette heure est déjà passée : choisissez demain.';
          case AlarmService.errorExactAlarmDenied:
            _exactAlarmDenied = true;
            _message = 'Android n’autorise pas cette application à '
                'programmer des alarmes exactes.';
          default:
            _message = 'Impossible de programmer le réveil.';
        }
      });
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _message = 'Impossible de programmer le réveil.');
    }
  }

  Future<void> _cancel() async {
    try {
      await _alarms.cancel();
    } on PlatformException {
      // Rien à faire : l'état est relu juste après.
    }
    await _refreshScheduled();
  }

  // --- Interface -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();

    final String timeText;
    if (_hasDraft) {
      timeText = formatTime(_hour!, _minute!);
    } else if (_scheduled != null) {
      timeText = _scheduled!.timeLabel;
    } else {
      timeText = '--:--';
    }

    final todayPossible = _hasDraft && !isPastToday(_hour!, _minute!, now);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Réveil',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: InkWell(
                      onTap: _pickTime,
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Text(
                          timeText,
                          semanticsLabel: 'Heure du réveil : $timeText. '
                              'Toucher pour la modifier.',
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: 88,
                            fontWeight: FontWeight.w300,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStatus(theme, now),
                  if (_listening || _heard.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _heard.isEmpty ? 'J’écoute…' : '« $_heard »',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: colors.error),
                    ),
                  ],
                  if (_exactAlarmDenied) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _alarms.openExactAlarmSettings,
                      child: const Text('Autoriser les alarmes'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton.tonalIcon(
                    onPressed: _toggleListening,
                    icon: Icon(_listening ? Icons.stop : Icons.mic),
                    label: Text(_listening ? 'Arrêter l’écoute' : 'Dire l’heure'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                  ),
                  if (_speechUnavailable || !_hasDraft) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _pickTime,
                      child: const Text('Choisir l’heure manuellement'),
                    ),
                  ],
                  if (_hasDraft) ...[
                    const SizedBox(height: 20),
                    SegmentedButton<AlarmDay>(
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: AlarmDay.today,
                          label: const Text('Aujourd’hui'),
                          enabled: todayPossible,
                        ),
                        const ButtonSegment(
                          value: AlarmDay.tomorrow,
                          label: Text('Demain'),
                        ),
                      ],
                      selected: {if (_day != null) _day!},
                      onSelectionChanged: (selection) => setState(() {
                        if (selection.isNotEmpty) _day = selection.first;
                      }),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _day == null ? null : _schedule,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: const Text('Programmer le réveil'),
                    ),
                  ] else if (_scheduled != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _cancel,
                      child: const Text('Annuler le réveil'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme, DateTime now) {
    final colors = theme.colorScheme;

    if (_hasDraft) {
      final text = switch (_day) {
        AlarmDay.today => 'Réveil aujourd’hui',
        AlarmDay.tomorrow => 'Réveil demain',
        null => 'Aujourd’hui ou demain ?',
      };
      return Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium,
      );
    }

    final scheduled = _scheduled;
    if (scheduled != null) {
      return Column(
        children: [
          Text(
            '✓ Réveil programmé',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(color: colors.primary),
          ),
          const SizedBox(height: 4),
          Text(
            '${scheduled.dayLabel(now)} à ${scheduled.timeLabel}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      );
    }

    return Text(
      'Aucun réveil programmé',
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium
          ?.copyWith(color: colors.onSurfaceVariant),
    );
  }
}
