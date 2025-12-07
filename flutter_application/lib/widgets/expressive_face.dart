import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class ExpressionData {
  final double mouth; // -1 (frown) .. 1 (big smile)
  final double eyes; // 0 (closed) .. 1 (wide)
  final double eyebrow; // -1 (down) .. 1 (up)
  final double blush; // 0 .. 1
  final double pupilX; // -1 .. 1
  final double pupilY; // -1 .. 1
  final double headTilt; // radians, small
  final Color faceColor;

  const ExpressionData({
    required this.mouth,
    required this.eyes,
    required this.eyebrow,
    required this.blush,
    required this.pupilX,
    required this.pupilY,
    required this.headTilt,
    required this.faceColor,
  });

  factory ExpressionData.neutral() => ExpressionData(
        mouth: 0.0,
        eyes: 1.0,
        eyebrow: 0.0,
        blush: 0.0,
        pupilX: 0.0,
        pupilY: 0.0,
        headTilt: 0.0,
        faceColor: const Color(0xFFFFE066),
      );

  static ExpressionData lerp(ExpressionData a, ExpressionData b, double t) {
    return ExpressionData(
      mouth: _lerpDouble(a.mouth, b.mouth, t),
      eyes: _lerpDouble(a.eyes, b.eyes, t),
      eyebrow: _lerpDouble(a.eyebrow, b.eyebrow, t),
      blush: _lerpDouble(a.blush, b.blush, t),
      pupilX: _lerpDouble(a.pupilX, b.pupilX, t),
      pupilY: _lerpDouble(a.pupilY, b.pupilY, t),
      headTilt: _lerpDouble(a.headTilt, b.headTilt, t),
      faceColor: Color.lerp(a.faceColor, b.faceColor, t) ?? a.faceColor,
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  ExpressionData copyWith({
    double? mouth,
    double? eyes,
    double? eyebrow,
    double? blush,
    double? pupilX,
    double? pupilY,
    double? headTilt,
    Color? faceColor,
  }) {
    return ExpressionData(
      mouth: mouth ?? this.mouth,
      eyes: eyes ?? this.eyes,
      eyebrow: eyebrow ?? this.eyebrow,
      blush: blush ?? this.blush,
      pupilX: pupilX ?? this.pupilX,
      pupilY: pupilY ?? this.pupilY,
      headTilt: headTilt ?? this.headTilt,
      faceColor: faceColor ?? this.faceColor,
    );
  }
}

class ExpressionController {
  final ValueNotifier<ExpressionData> _notifier;

  ExpressionController([ExpressionData? initial]) : _notifier = ValueNotifier(initial ?? ExpressionData.neutral());

  ValueListenable<ExpressionData> get listenable => _notifier;

  ExpressionData get value => _notifier.value;

  void setExpression(ExpressionData e) => _notifier.value = e;

  void dispose() => _notifier.dispose();
}

class ExpressionTween extends Tween<ExpressionData> {
  ExpressionTween({ExpressionData? begin, ExpressionData? end}) : super(begin: begin, end: end);

  @override
  ExpressionData lerp(double t) => ExpressionData.lerp(begin ?? ExpressionData.neutral(), end ?? ExpressionData.neutral(), t);
}

class ExpressiveFace extends StatefulWidget {
  final ExpressionController controller;
  final double size;

  const ExpressiveFace({Key? key, required this.controller, this.size = 220}) : super(key: key);

  @override
  State<ExpressiveFace> createState() => _ExpressiveFaceState();
}

class _ExpressiveFaceState extends State<ExpressiveFace> {
  late ExpressionData _last;

  @override
  void initState() {
    super.initState();
    _last = widget.controller.value;
    widget.controller.listenable.addListener(_onExprChanged);
  }

  @override
  void didUpdateWidget(covariant ExpressiveFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.listenable.removeListener(_onExprChanged);
      _last = widget.controller.value;
      widget.controller.listenable.addListener(_onExprChanged);
    }
  }

  void _onExprChanged() {
    setState(() {
      // trigger rebuild; TweenAnimationBuilder will animate from _last -> current
    });
  }

  @override
  void dispose() {
    widget.controller.listenable.removeListener(_onExprChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.value;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: TweenAnimationBuilder<ExpressionData>(
        tween: ExpressionTween(begin: _last, end: current),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _last = current;
          });
          return CustomPaint(
            painter: _FacePainter(value),
            size: Size(widget.size, widget.size),
          );
        },
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  final ExpressionData e;

  _FacePainter(this.e);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final faceRadius = size.width * 0.45;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(e.headTilt);
    canvas.translate(-center.dx, -center.dy);

    final facePaint = Paint()..color = e.faceColor;
    canvas.drawCircle(center, faceRadius, facePaint);

    // blush
    if (e.blush > 0.01) {
      final blushPaint = Paint()..color = Colors.pink.withOpacity(0.35 * e.blush);
      final offsetY = faceRadius * 0.25;
      final offsetX = faceRadius * 0.6;
      canvas.drawCircle(center + Offset(-offsetX, offsetY), faceRadius * 0.18 * e.blush, blushPaint);
      canvas.drawCircle(center + Offset(offsetX, offsetY), faceRadius * 0.18 * e.blush, blushPaint);
    }

    // Eyes
    final eyePaint = Paint()..color = Colors.black;
    final eyeWhite = Paint()..color = Colors.white;

    final eyeW = faceRadius * 0.36;
    final eyeH = faceRadius * 0.22 * e.eyes.clamp(0.0, 1.0);
    final eyeY = center.dy - faceRadius * 0.1;
    final eyeXOffset = faceRadius * 0.55;

    // Left eye
    final leftEyeCenter = Offset(center.dx - eyeXOffset, eyeY);
    final rightEyeCenter = Offset(center.dx + eyeXOffset, eyeY);

    final leftEyeRect = Rect.fromCenter(center: leftEyeCenter, width: max(1.0, eyeW), height: max(1.0, eyeH));
    final rightEyeRect = Rect.fromCenter(center: rightEyeCenter, width: max(1.0, eyeW), height: max(1.0, eyeH));

    canvas.drawOval(leftEyeRect, eyeWhite);
    canvas.drawOval(rightEyeRect, eyeWhite);

    // Pupils
    final pupilRadius = faceRadius * 0.07;
    final pupilOffsetMax = faceRadius * 0.14;
    final pupilOffset = Offset(e.pupilX * pupilOffsetMax, e.pupilY * pupilOffsetMax);

    canvas.drawCircle(leftEyeCenter + pupilOffset, pupilRadius, eyePaint);
    canvas.drawCircle(rightEyeCenter + pupilOffset, pupilRadius, eyePaint);

    // Eyebrows
    final browPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = max(1.0, faceRadius * 0.06)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final browOffsetY = faceRadius * 0.36;
    final browLen = faceRadius * 0.5;
    final eyebrowTilt = e.eyebrow * 0.8; // tilt in radians

    final leftBrowP1 = leftEyeCenter + Offset(-browLen / 2, -browOffsetY);
    final leftBrowP2 = leftEyeCenter + Offset(browLen / 2, -browOffsetY) + Offset(0, -eyebrowTilt * 8);

    final rightBrowP1 = rightEyeCenter + Offset(-browLen / 2, -browOffsetY) + Offset(0, -eyebrowTilt * 8);
    final rightBrowP2 = rightEyeCenter + Offset(browLen / 2, -browOffsetY);

    canvas.drawLine(leftBrowP1, leftBrowP2, browPaint);
    canvas.drawLine(rightBrowP1, rightBrowP2, browPaint);

    // Mouth: quadratic bezier
    final mouthWidth = faceRadius * 1.0;
    final mouthY = center.dy + faceRadius * 0.45;
    final leftMouth = Offset(center.dx - mouthWidth / 2, mouthY);
    final rightMouth = Offset(center.dx + mouthWidth / 2, mouthY);
    // Positive mouth value -> Smile (curve down) -> Control point Y increases
    // Negative mouth value -> Frown (curve up) -> Control point Y decreases
    final control = Offset(center.dx, mouthY + e.mouth * faceRadius * 0.6);

    final mouthPath = Path();
    mouthPath.moveTo(leftMouth.dx, leftMouth.dy);
    mouthPath.quadraticBezierTo(control.dx, control.dy, rightMouth.dx, rightMouth.dy);

    final mouthPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.0, faceRadius * 0.08)
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(mouthPath, mouthPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) => oldDelegate.e != e;
}

double max(double a, double b) => a > b ? a : b;
