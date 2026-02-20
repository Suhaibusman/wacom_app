import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/constants/app_colors.dart';

class SignatureDialog extends ConsumerStatefulWidget {
  const SignatureDialog({super.key});

  @override
  ConsumerState<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends ConsumerState<SignatureDialog> {
  List<List<Offset>> strokes = [];
  List<Offset> currentStroke = [];
  StreamSubscription? _penSubscription;

  // Dialog Canvas Size (Fixed for simplicity or mapped)
  final double canvasWidth = 400;
  final double canvasHeight = 200;

  @override
  void initState() {
    super.initState();
    _connectWacom();
  }

  void _connectWacom() async {
    final wacomNotifier = ref.read(wacomConnectionProvider.notifier);
    final wacomState = ref.read(wacomConnectionProvider);

    if (!wacomState.isConnected) {
      await wacomNotifier.connect();
    }

    // Start listening to events from the service
    final wacomService = ref.read(wacomServiceProvider);
    // Be sure to cancel previous subscription if any
    await _penSubscription?.cancel();

    // We assume if connected, capabilities are available
    final currentState = ref.read(wacomConnectionProvider);
    if (currentState.isConnected && currentState.capabilities != null) {
      _penSubscription = wacomService.penEvents.listen((event) {
        if (!mounted) return;
        _handlePenEvent(event, currentState.capabilities!);
      });
    }
  }

  void _handlePenEvent(Map<String, dynamic> event, Map<String, dynamic> caps) {
    final x = event['x'] as double;
    final y = event['y'] as double;
    final pressure = event['pressure'] as double;
    final sw =
        event['sw']
            as int; // 0 = pen down/hover, 1 = touch? check SDK docs. Usually sw!=0 or pressure>0 means down.

    final maxX = caps['maxX'] as double;
    final maxY = caps['maxY'] as double;

    // Map to canvas
    // Simple linear mapping
    final double screenX = (x / maxX) * canvasWidth;
    final double screenY = (y / maxY) * canvasHeight;

    setState(() {
      if (pressure > 0 || sw != 0) {
        currentStroke.add(Offset(screenX, screenY));
      } else {
        if (currentStroke.isNotEmpty) {
          strokes.add(List.from(currentStroke));
          currentStroke.clear();
        }
      }
    });
  }

  @override
  void dispose() {
    _penSubscription?.cancel();
    // Do not disconnect global service on dialog close, so we can keep connection alive if desired.
    // However, if we want to release the device for other apps, we might disconnect.
    // For now, let's keep it connected as per user request for "manual connection".
    super.dispose();
  }

  void _clear() {
    setState(() {
      strokes.clear();
      currentStroke.clear();
    });
    ref.read(wacomServiceProvider).clearScreen();
  }

  Future<void> _apply() async {
    // Generate Image from strokes
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    // Transparent background? Or White?
    // Signature usually transparent background.
    // canvas.drawColor(Colors.transparent, BlendMode.clear);

    _drawStrokes(canvas);

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    if (mounted) {
      Navigator.of(context).pop(pngBytes);
    }
  }

  void _drawStrokes(Canvas canvas) {
    final paint = Paint()
      ..color = AppColors.signatureInk
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.isNotEmpty) {
      final path = Path();
      path.moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (var i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Sign Here"),
      content: Container(
        width: canvasWidth,
        height: canvasHeight,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          color: Colors.white,
        ),
        child: CustomPaint(painter: _SignaturePainter(strokes, currentStroke)),
      ),
      actions: [
        TextButton(onPressed: _clear, child: const Text("Clear")),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(onPressed: _apply, child: const Text("Apply")),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  _SignaturePainter(this.strokes, this.currentStroke);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.signatureInk
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path();
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }

    if (currentStroke.isNotEmpty) {
      final path = Path();
      path.moveTo(currentStroke.first.dx, currentStroke.first.dy);
      for (var i = 1; i < currentStroke.length; i++) {
        path.lineTo(currentStroke[i].dx, currentStroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
