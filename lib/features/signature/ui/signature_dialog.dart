import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/wacom_service.dart';

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

  Color _selectedColor = AppColors.signatureInk;
  bool _isClosing = false; // Prevent multiple pops

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

    // Give device a moment to settle
    await Future.delayed(const Duration(milliseconds: 500));

    // Start listening to events from the service
    final wacomService = ref.read(wacomServiceProvider);
    // Be sure to cancel previous subscription if any
    await _penSubscription?.cancel();

    // We assume if connected, capabilities are available
    final currentState = ref.read(wacomConnectionProvider);
    if (currentState.isConnected && currentState.capabilities != null) {
      // Set the Wacom Screen Image (Buttons)
      if (mounted) {
        _setWacomScreen(currentState.capabilities!, wacomService);
      }

      _penSubscription = wacomService.penEvents.listen((event) {
        if (!mounted) return;
        _handlePenEvent(event, currentState.capabilities!);
      });
    }
  }

  Future<void> _setWacomScreen(
    Map<String, dynamic> caps,
    WacomService service,
  ) async {
    final width = caps['screenWidth']?.toInt() ?? 800;
    final height = caps['screenHeight']?.toInt() ?? 480;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Draw White Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = Colors.white,
    );

    // Draw Text/Instructions
    final textPainter = TextPainter(
      text: const TextSpan(
        text: "Sign here",
        style: TextStyle(color: Colors.black, fontSize: 24),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((width - textPainter.width) / 2, 50));

    // Draw Buttons at bottom
    final buttonHeight = height * 0.2; // Bottom 20%
    final buttonTop = height - buttonHeight;
    final buttonWidth = width / 3;

    // Clear Button (Left)
    _drawWacomButton(
      canvas,
      "Clear",
      Colors.redAccent,
      Rect.fromLTWH(0, buttonTop, buttonWidth, buttonHeight),
    );
    // Cancel Button (Middle)
    _drawWacomButton(
      canvas,
      "Cancel",
      Colors.grey,
      Rect.fromLTWH(buttonWidth, buttonTop, buttonWidth, buttonHeight),
    );
    // Apply Button (Right)
    _drawWacomButton(
      canvas,
      "Apply",
      Colors.green,
      Rect.fromLTWH(buttonWidth * 2, buttonTop, buttonWidth, buttonHeight),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData != null) {
      final rgbaBytes = byteData.buffer.asUint8List();
      // Convert RGBA (4 bytes) to BGR/RGB (3 bytes)
      // Wacom generally expects BGR for 24-bit
      // Mode 4 = 24-bit.

      final int pixelCount = width * height;
      final Uint8List rgbBytes = Uint8List(pixelCount * 3);

      for (int i = 0; i < pixelCount; i++) {
        final int rgbaIndex = i * 4;
        final int rgbIndex = i * 3;

        // RGBA -> BGR
        rgbBytes[rgbIndex] = rgbaBytes[rgbaIndex + 2]; // B
        rgbBytes[rgbIndex + 1] = rgbaBytes[rgbaIndex + 1]; // G
        rgbBytes[rgbIndex + 2] = rgbaBytes[rgbaIndex]; // R
      }

      await service.setSignatureScreen(rgbBytes, 4);
    }
  }

  void _drawWacomButton(Canvas canvas, String text, Color color, Rect rect) {
    canvas.drawRect(rect, Paint()..color = color);
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - textPainter.width) / 2,
        rect.top + (rect.height - textPainter.height) / 2,
      ),
    );
  }

  void _handlePenEvent(Map<String, dynamic> event, Map<String, dynamic> caps) {
    final x = event['x'] as double;
    final y = event['y'] as double;
    final pressure = event['pressure'] as double;
    final sw = event['sw'] as int;

    final maxX = caps['maxX'] as double;
    final maxY = caps['maxY'] as double;

    final screenW = caps['screenWidth']?.toDouble() ?? 800.0;
    final screenH = caps['screenHeight']?.toDouble() ?? 480.0;

    final mappedX = (x / maxX) * screenW;
    final mappedY = (y / maxY) * screenH;

    final buttonHeight = screenH * 0.2;
    final buttonTop = screenH - buttonHeight;

    // Debugging Button Logic
    // debugPrint("Wacom Event: x=$x, y=$y, pressure=$pressure, maxX=$maxX, maxY=$maxY");
    // debugPrint("Mapped: x=$mappedX, y=$mappedY");
    // debugPrint("Buttons: Top=$buttonTop, Height=$buttonHeight");

    if (mappedY > buttonTop && pressure > 0) {
      if (_isClosing) return;

      debugPrint("Button Click Detected! MappedX=$mappedX");
      // Button Clicked
      final buttonWidth = screenW / 3;
      if (mappedX < buttonWidth) {
        debugPrint("Action: Clear");
        _clear();
      } else if (mappedX < buttonWidth * 2) {
        debugPrint("Action: Cancel");
        _isClosing = true;
        _penSubscription?.cancel(); // Stop listening immediately
        if (mounted) {
          Navigator.of(context).pop(); // Cancel
        }
      } else {
        debugPrint("Action: Apply");
        _isClosing = true;
        _penSubscription?.cancel(); // Stop listening immediately
        _apply();
      }
      return; // Don't draw
    }

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
    // Clear the Wacom screen on exit?
    ref.read(wacomServiceProvider).clearScreen();
    super.dispose();
  }

  void _clear() {
    setState(() {
      strokes.clear();
      currentStroke.clear();
    });

    final wacomService = ref.read(wacomServiceProvider);
    final currentState = ref.read(wacomConnectionProvider);
    if (currentState.isConnected && currentState.capabilities != null) {
      _setWacomScreen(currentState.capabilities!, wacomService);
    }
  }

  bool _saveSignature = false;

  Future<void> _apply() async {
    // Generate Image from strokes
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    _drawStrokes(canvas);

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      canvasWidth.toInt(),
      canvasHeight.toInt(),
    );
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    if (_saveSignature) {
      final storageService = ref.read(signatureStorageServiceProvider);
      await storageService.saveSignature(pngBytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Signature Saved!")));
      }
    }

    if (mounted) {
      Navigator.of(context).pop(pngBytes);
    }
  }

  void _drawStrokes(Canvas canvas) {
    final paint = Paint()
      ..color = _selectedColor
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: canvasWidth,
            height: canvasHeight,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              color: Colors.white,
            ),
            child: CustomPaint(
              painter: _SignaturePainter(
                strokes,
                currentStroke,
                _selectedColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _colorOption(Colors.black),
              const SizedBox(width: 8),
              _colorOption(Colors.blue),
              const SizedBox(width: 8),
              _colorOption(Colors.red),
              const SizedBox(width: 8),
              _colorOption(Colors.green),
            ],
          ),
        ],
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Checkbox(
              value: _saveSignature,
              onChanged: (v) => setState(() => _saveSignature = v ?? false),
            ),
            const Text("Save Signature"),
          ],
        ),
        TextButton(onPressed: _clear, child: const Text("Clear")),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        ElevatedButton(onPressed: _apply, child: const Text("Apply")),
      ],
    );
  }

  Widget _colorOption(Color color) {
    return GestureDetector(
      onTap: () => setState(() => _selectedColor = color),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: _selectedColor == color
              ? Border.all(color: Colors.black, width: 2)
              : null,
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;
  final Color color;

  _SignaturePainter(this.strokes, this.currentStroke, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
