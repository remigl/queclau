import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Ce que la sphère exprime.
enum OrbState {
  /// Au repos : sombre et lente. Toucher pour relancer l'écoute.
  idle,

  /// À l'écoute : vivante, elle gonfle avec le volume de la voix.
  listening,

  /// Compréhension en cours : les couleurs tournent plus vite.
  thinking,

  /// Alarme réglée : la sphère vire au vert avec une pulsation.
  success,

  /// Pas compris : léger tremblement de gauche à droite.
  error,
}

/// Sphère lumineuse animée, seul élément visuel de l'application.
class Orb extends StatefulWidget {
  const Orb({
    super.key,
    required this.state,
    required this.level,
    this.diameter = 220,
  });

  final OrbState state;

  /// Volume de la voix, de 0 à 1.
  final ValueListenable<double> level;

  final double diameter;

  @override
  State<Orb> createState() => _OrbState();
}

/// Valeurs animées, lues par le peintre à chaque image.
class _OrbValues {
  double phase = 0; // avance plus ou moins vite selon l'état
  double level = 0; // volume lissé
  double brightness = 0.4;
  double success = 0; // 0 = couleurs normales, 1 = vert
  double shake = -1; // secondes depuis le début du tremblement, -1 = aucun
  double pulse = -1; // idem pour la pulsation de succès
}

class _OrbState extends State<Orb> with SingleTickerProviderStateMixin {
  static const _shakeDuration = 0.6;
  static const _pulseDuration = 0.7;

  final _values = _OrbValues();
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(Orb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == oldWidget.state) return;
    if (widget.state == OrbState.error) _values.shake = 0;
    if (widget.state == OrbState.success) _values.pulse = 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final v = _values;
    final state = widget.state;

    final speed = switch (state) {
      OrbState.idle => 0.25,
      OrbState.listening => 1.0,
      OrbState.thinking => 2.8,
      OrbState.success => 0.6,
      OrbState.error => 1.0,
    };
    v.phase += dt * speed;

    // Lissage exponentiel vers les valeurs cibles.
    double ease(double current, double target, double rate) =>
        current + (target - current) * (1 - math.exp(-dt * rate));

    final voice = state == OrbState.listening ? widget.level.value : 0.0;
    v.level = ease(v.level, voice.clamp(0.0, 1.0), 10);
    v.brightness = ease(v.brightness, state == OrbState.idle ? 0.4 : 1.0, 5);
    v.success = ease(v.success, state == OrbState.success ? 1.0 : 0.0, 6);

    if (v.shake >= 0) {
      v.shake += dt;
      if (v.shake > _shakeDuration) v.shake = -1;
    }
    if (v.pulse >= 0) {
      v.pulse += dt;
      if (v.pulse > _pulseDuration) v.pulse = -1;
    }

    _frame.value++;
  }

  @override
  Widget build(BuildContext context) {
    // La zone de dessin dépasse la sphère pour laisser la place au halo.
    return SizedBox.square(
      dimension: widget.diameter * 1.7,
      child: CustomPaint(
        painter: _OrbPainter(
          _values,
          radius: widget.diameter / 2,
          repaint: _frame,
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.v, {required this.radius, required Listenable repaint})
      : super(repaint: repaint);

  final _OrbValues v;
  final double radius;

  static const _normal = [
    Color(0xFF4F7CFF),
    Color(0xFF9B5CFF),
    Color(0xFF22D3EE),
    Color(0xFFFF5CA8),
  ];
  static const _green = [
    Color(0xFF34D399),
    Color(0xFF22D3EE),
    Color(0xFFA3E635),
    Color(0xFF10B981),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Tremblement amorti (« pas compris »).
    var dx = 0.0;
    if (v.shake >= 0) {
      final progress = v.shake / _OrbState._shakeDuration;
      dx = math.sin(v.shake * 2 * math.pi * 5) * radius * 0.08 * (1 - progress);
    }

    // Respiration, volume de la voix, pulsation de succès.
    var scale = 1 + 0.035 * math.sin(v.phase * 1.7) + 0.16 * v.level;
    if (v.pulse >= 0) {
      scale +=
          0.12 * math.sin(v.pulse / _OrbState._pulseDuration * math.pi);
    }

    final center = size.center(Offset.zero) + Offset(dx, 0);
    final r = radius * scale;
    final rect = Rect.fromCircle(center: center, radius: r);
    final colors = [
      for (var i = 0; i < _normal.length; i++)
        Color.lerp(_normal[i], _green[i], v.success)!,
    ];

    // Halo.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = colors[0].withValues(alpha: 0.45 * v.brightness)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(rect));

    // Fond de la sphère.
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF0B1030));

    // Taches de couleur floues qui tournent les unes autour des autres.
    for (var i = 0; i < colors.length; i++) {
      final direction = i.isEven ? 1 : -1;
      final angle = v.phase * (0.7 + 0.23 * i) * direction + i * math.pi / 2;
      final distance = r * (0.32 + 0.12 * math.sin(v.phase * 0.9 + i * 1.3));
      final position =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      canvas.drawCircle(
        position,
        r * (0.62 + 0.25 * v.level),
        Paint()
          ..color = colors[i].withValues(alpha: 0.75 * v.brightness)
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.28),
      );
    }

    // Reflet en haut à gauche.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.9,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.28 * v.brightness),
            const Color(0x00FFFFFF),
          ],
          stops: const [0, 0.6],
        ).createShader(rect),
    );

    // Bord assombri, pour le volume.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0x59000000)],
          stops: [0.72, 1],
        ).createShader(rect),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) => oldDelegate.radius != radius;
}
