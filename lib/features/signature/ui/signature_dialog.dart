import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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

  Color _selectedColor = const Color(0xFF2563EB);
  bool _isClosing = false; // Prevent multiple pops
  bool _wacomUiActive = false;

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

    // Show idle screen immediately after device connects
    final wacomService = ref.read(wacomServiceProvider);
    final connectedState = ref.read(wacomConnectionProvider);
    if (connectedState.isConnected && connectedState.capabilities != null) {
      _setWacomIdleScreen(connectedState.capabilities!, wacomService);
    }

    // Give device a moment to settle
    await Future.delayed(const Duration(milliseconds: 500));

    // Start listening to events from the service
    // Be sure to cancel previous subscription if any
    await _penSubscription?.cancel();

    // We assume if connected, capabilities are available
    final currentState = ref.read(wacomConnectionProvider);
    if (currentState.isConnected && currentState.capabilities != null) {
      // Set the Wacom Screen Image (Buttons)
      if (mounted) {
        _showWacomSignatureScreen(currentState.capabilities!, wacomService);
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

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFF8FAFC),
    );

    // Title
    final textPainter = TextPainter(
      text: const TextSpan(
        text: "Sign here",
        style: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((width - textPainter.width) / 2, 36));

    // Signature field
    final fieldRect = Rect.fromLTWH(
      width * 0.08,
      height * 0.22,
      width * 0.84,
      height * 0.42,
    );
    canvas.drawRect(fieldRect, Paint()..color = Colors.white);
    canvas.drawRect(
      fieldRect,
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final hintPainter = TextPainter(
      text: const TextSpan(
        text: "Please sign in the box",
        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 20),
      ),
      textDirection: TextDirection.ltr,
    );
    hintPainter.layout();
    hintPainter.paint(
      canvas,
      Offset(
        (width - hintPainter.width) / 2,
        fieldRect.center.dy - (hintPainter.height / 2),
      ),
    );

    // Draw Buttons at bottom
    final buttonHeight = height * 0.2; // Bottom 20%
    final buttonTop = height - buttonHeight;
    final buttonWidth = width / 3;

    // Clear Button (Left)
    _drawWacomButton(
      canvas,
      "Clear",
      const Color(0xFFE2E8F0),
      const Color(0xFF0F172A),
      Rect.fromLTWH(0, buttonTop, buttonWidth, buttonHeight),
    );
    // Cancel Button (Middle)
    _drawWacomButton(
      canvas,
      "Cancel",
      const Color(0xFFF1F5F9),
      const Color(0xFF0F172A),
      Rect.fromLTWH(buttonWidth, buttonTop, buttonWidth, buttonHeight),
    );
    // Apply Button (Right)
    _drawWacomButton(
      canvas,
      "Apply",
      const Color(0xFF059669),
      Colors.white,
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

  void _drawWacomButton(
    Canvas canvas,
    String text,
    Color color,
    Color textColor,
    Rect rect,
  ) {
    canvas.drawRect(rect, Paint()..color = color);
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.w700,
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
    if (!_wacomUiActive) {
      return; // Ignore pen input when device is in idle/ready state
    }
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
        _closeDialog();
      } else {
        debugPrint("Action: Apply");
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
    _showWacomIdleScreen();
    super.dispose();
  }

  Future<void> _showWacomSignatureScreen(
    Map<String, dynamic> caps,
    WacomService service,
  ) async {
    _wacomUiActive = true;
    await _setWacomScreen(caps, service);
  }

  Future<void> _showWacomIdleScreen() async {
    if (!_wacomUiActive) return;
    final wacomService = ref.read(wacomServiceProvider);
    final currentState = ref.read(wacomConnectionProvider);
    if (currentState.isConnected && currentState.capabilities != null) {
      await _setWacomIdleScreen(currentState.capabilities!, wacomService);
    }
    _wacomUiActive = false;
  }

  Future<void> _setWacomIdleScreen(
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
        text: "Sindh High Court",
        style: TextStyle(
          color: Color(0xFF059669),
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final subtextPainter = TextPainter(
      text: const TextSpan(
        text: "Device Ready",
        style: TextStyle(color: Colors.grey, fontSize: 24),
      ),
      textDirection: TextDirection.ltr,
    );
    subtextPainter.layout();

    // Draw App Logo (center, text below)
    double logoBottom = height * 0.4;
    try {
      final data = await rootBundle.load('assets/images/hc_logo.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: (width * 0.22).toInt(),
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final logoSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final logoOffset = Offset(
        (width - logoSize.width) / 2,
        height * 0.22,
      );
      logoBottom = logoOffset.dy + logoSize.height;
      canvas.drawImage(
        image,
        logoOffset,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    } catch (_) {
      // Ignore logo load errors for the idle screen
    }

    textPainter.paint(
      canvas,
      Offset(
        (width - textPainter.width) / 2,
        logoBottom + 12,
      ),
    );

    subtextPainter.paint(
      canvas,
      Offset(
        (width - subtextPainter.width) / 2,
        logoBottom + 12 + textPainter.height + 10,
      ),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData != null) {
      final rgbaBytes = byteData.buffer.asUint8List();
      final int pixelCount = width * height;
      final Uint8List rgbBytes = Uint8List(pixelCount * 3);

      for (int i = 0; i < pixelCount; i++) {
        final int rgbaIndex = i * 4;
        final int rgbIndex = i * 3;
        rgbBytes[rgbIndex] = rgbaBytes[rgbaIndex + 2]; // B
        rgbBytes[rgbIndex + 1] = rgbaBytes[rgbaIndex + 1]; // G
        rgbBytes[rgbIndex + 2] = rgbaBytes[rgbaIndex]; // R
      }
      await service.setSignatureScreen(rgbBytes, 4);
    }
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
      _closeDialog(pngBytes);
    }
  }

  Future<void> _closeDialog([Uint8List? result]) async {
    if (_isClosing) return;
    _isClosing = true;
    if (mounted) {
      Navigator.of(context).pop(result);
    }
    unawaited(_penSubscription?.cancel());
    unawaited(_showWacomIdleScreen());
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
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 520 ? screenWidth - 32 : 520.0;
    final bool hasInk = strokes.isNotEmpty || currentStroke.isNotEmpty;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: AppColors.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.draw_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Sign here",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Use your Wacom pen to sign in the box",
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: canvasWidth,
                height: canvasHeight,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border, width: 2),
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFFFFFFF),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    if (!hasInk)
                      Center(
                        child: Text(
                          "Sign here",
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.4),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) {
                            setState(() {
                              currentStroke = [details.localPosition];
                            });
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              currentStroke.add(details.localPosition);
                            });
                          },
                          onPanEnd: (_) {
                            if (currentStroke.isNotEmpty) {
                              setState(() {
                                strokes.add(List.from(currentStroke));
                                currentStroke.clear();
                              });
                            }
                          },
                          child: CustomPaint(
                            painter: _SignaturePainter(
                              strokes,
                              currentStroke,
                              _selectedColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _saveSignature,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onChanged: (v) =>
                        setState(() => _saveSignature = v ?? false),
                  ),
                  const Text(
                    "Save Signature",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  _colorOption(const Color(0xFF0F172A)),
                  const SizedBox(width: 10),
                  _colorOption(const Color(0xFF2563EB)),
                  const SizedBox(width: 10),
                  _colorOption(const Color(0xFFDC2626)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _clear,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text("Clear"),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _closeDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: const Text("Cancel"),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _apply,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Apply"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
