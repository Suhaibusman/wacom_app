import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const methodChannel = MethodChannel('wacom_stu_channel');
  static const eventChannel = EventChannel('wacom_stu_events');

  String status = "Not Connected";
  StreamSubscription? _penSubscription;

  // Tablet capabilities
  double? tabletMaxX;
  double? tabletMaxY;
  double? tabletScreenWidth;
  double? tabletScreenHeight;

  // Drawing

  // Screen overlay annotations (Legacy/Direct)
  List<List<Offset>> screenAnnotations = [];
  List<Offset> currentScreenAnnotation = [];

  // Signature Box Logic
  bool _isSignatureDialogOpen = false;
  bool _isInlineSignatureMode = false;
  List<List<Offset>> signatureStrokes = [];
  List<Offset> currentSignatureStroke = [];
  final GlobalKey _signatureBoxKey = GlobalKey();
  Size? _signatureBoxSize;
  Offset? _signatureBoxPosition;

  // PDF
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey _pdfKey = GlobalKey();
  Size? _pdfViewSize;

  Future<void> connect() async {
    try {
      final result = await methodChannel.invokeMethod('connect');
      if (result is Map) {
        setState(() {
          status = result['status'];
          tabletMaxX = (result['maxX'] as int).toDouble();
          tabletMaxY = (result['maxY'] as int).toDouble();

          if (result.containsKey('screenWidth')) {
            tabletScreenWidth = (result['screenWidth'] as int).toDouble();
          }
          if (result.containsKey('screenHeight')) {
            tabletScreenHeight = (result['screenHeight'] as int).toDouble();
          }
        });
        startListening();
      } else {
        setState(() => status = result.toString());
      }
    } on PlatformException catch (e) {
      setState(() => status = "Error: ${e.message}");
    }
  }

  Future<void> disconnect() async {
    try {
      await _penSubscription?.cancel();
      _penSubscription = null;
      final result = await methodChannel.invokeMethod('disconnect');
      setState(() {
        status = result.toString();
        screenAnnotations.clear();
        currentScreenAnnotation.clear();
      });
    } on PlatformException catch (e) {
      setState(() => status = "Error: ${e.message}");
    }
  }

  Future<void> clearScreen() async {
    try {
      await methodChannel.invokeMethod('clearScreen');
    } on PlatformException catch (e) {
      debugPrint("ClearScreen Error: ${e.message}");
    }
  }

  void startListening() {
    print("Start listening to pen events");
    _penSubscription = eventChannel.receiveBroadcastStream().listen(
      (event) {
        print("Received event: $event");
        if (event is Map && tabletMaxX != null && tabletMaxY != null) {
          final x = (event['x'] as int).toDouble();
          final y = (event['y'] as int).toDouble();
          final pressure = (event['pressure'] as int).toDouble();
          final sw = (event['sw'] as int); // switch/button status

          if (_isSignatureDialogOpen) {
            print("Handling signature input: x=$x, y=$y");
            _handleSignatureInput(x, y, pressure, sw);
          } else if (_isInlineSignatureMode) {
            _handleInlineSignatureInput(x, y, pressure, sw);
          } else {
            _handleAnnotationInput(x, y, pressure, sw);
          }
        } else {
          print(
            "Event invalid or tablet caps null: caps=($tabletMaxX, $tabletMaxY)",
          );
        }
      },
      onError: (error) {
        print("Stream Error: $error");
        setState(() => status = "Stream Error: $error");
      },
    );
  }

  void _handleAnnotationInput(double x, double y, double pressure, int sw) {
    if (_pdfViewSize == null) return;

    // Full screen mapping for annotation
    final screenX = (x / tabletMaxX!) * _pdfViewSize!.width;
    final screenY = (y / tabletMaxY!) * _pdfViewSize!.height;

    setState(() {
      if (sw != 0 || pressure > 0) {
        currentScreenAnnotation.add(Offset(screenX, screenY));
      } else {
        if (currentScreenAnnotation.isNotEmpty) {
          screenAnnotations.add(List.from(currentScreenAnnotation));
          currentScreenAnnotation.clear();
        }
      }
    });
  }

  void _handleInlineSignatureInput(
    double x,
    double y,
    double pressure,
    int sw,
  ) {
    if (tabletScreenWidth == null || tabletScreenHeight == null) return;

    // Map to screen pixels
    // Note: Wacom coordinates are usually 0..tabletMaxX, 0..tabletMaxY
    // We map to 0..tabletScreenWidth, 0..tabletScreenHeight
    final double px = (x / tabletMaxX!) * tabletScreenWidth!;
    final double py = (y / tabletMaxY!) * tabletScreenHeight!;

    // Button Areas (Must match _generateSignatureScreenImage)
    final double btnHeight = tabletScreenHeight! * 0.2;
    final double btnY = tabletScreenHeight! - btnHeight;
    final double clearBtnWidth = tabletScreenWidth! * 0.4;
    final double applyBtnX = tabletScreenWidth! * 0.6;

    // Check for button taps (pressure > 0)
    if (pressure > 0) {
      // Clear Button
      if (py >= btnY && px <= clearBtnWidth) {
        setState(() {
          signatureStrokes.clear();
          currentSignatureStroke.clear();
        });
        // We might want to redraw the empty screen + strokes (which are now empty)
        // But strokes are on PDF view, so we just clear them.
        // Ideally we should clear the tablet screen too to remove "ink"?
        // But the tablet handles its own ink usually?
        // If we are in "image" mode, we might need to send image again to clear "ink" if the tablet draws on top.
        // However, standard writeImage just puts an image. Inking is separate.
        // If Inking is ON, the tablet draws ink internally.
        // To "clear" ink on tablet, we need to call clearScreen().
        if (sw != 0) {
          // On Click (sw is button?) or just pressure?
          // Wait, usually we want to debouce.
          _refreshTabletScreen();
        }
        return;
      }

      // Apply Button
      if (py >= btnY && px >= applyBtnX) {
        _applySignature();
        _stopInlineSignatureMode();
        return;
      }
    }

    // Drawing logic - Map to On-Screen Box
    if (_pdfViewSize != null) {
      // Box Dimensions (Must match the UI Positioned widget)
      const double boxWidth = 400;
      const double boxHeight = 200;
      final double boxLeft = (_pdfViewSize!.width / 2) - (boxWidth / 2);
      final double boxTop = (_pdfViewSize!.height / 2) - (boxHeight / 2);

      // Map tablet drawing area (0..tabletMaxX, 0..(tabletMaxY - btnHeight_in_tablet_coords))
      // to the box area on screen.

      // Tablet Drawing Area Height (excluding buttons)
      // tabletScreenHeight is pixel height. tabletMaxY is unit height.
      // We need to know how much of Y is buttons in *tablet units*.
      final double btnHeightPx = tabletScreenHeight! * 0.2;
      final double drawingHeightPx = tabletScreenHeight! - btnHeightPx;

      // Convert Px to Units
      final double drawingHeightUnits =
          (drawingHeightPx / tabletScreenHeight!) * tabletMaxY!;

      // Normalize coordinates to [0, 1] within the drawing area
      final double normX = x / tabletMaxX!;
      final double normY = y / drawingHeightUnits;

      // Check if inside drawing area
      if (normX >= 0 && normX <= 1 && normY >= 0 && normY <= 1) {
        final double screenX = boxLeft + (normX * boxWidth);
        // Invert Y? Wacom usually 0 at top.
        final double screenY = boxTop + (normY * boxHeight);

        setState(() {
          if (sw != 0 || pressure > 0) {
            currentSignatureStroke.add(
              Offset(screenX, screenY),
            ); // Store relative to screen/PDF for now
            // Ideally we should store relative to Box if we want to drag it later.
            // But for now, screen absolute (within PDF stack) is fine.
          } else {
            if (currentSignatureStroke.isNotEmpty) {
              signatureStrokes.add(List.from(currentSignatureStroke));
              currentSignatureStroke.clear();
            }
          }
        });
      }
    }
  }

  Future<void> _refreshTabletScreen() async {
    await clearScreen(); // Clears ink
    // Re-send buttons
    await _startInlineSignatureMode(refreshOnly: true);
  }

  Future<void> _startInlineSignatureMode({bool refreshOnly = false}) async {
    if (tabletScreenWidth == null || tabletScreenHeight == null) {
      print("Tablet screen dimensions unknown");
      return;
    }

    final w = tabletScreenWidth!.toInt();
    final h = tabletScreenHeight!.toInt();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.white,
    );

    // Buttons
    final double btnHeight = h * 0.2;
    final double btnY = h - btnHeight;
    final double clearBtnWidth = w * 0.4;
    final double applyBtnX = w * 0.6;
    final double applyBtnWidth = w * 0.4;

    // Draw Clear Button
    canvas.drawRect(
      Rect.fromLTWH(0, btnY, clearBtnWidth, btnHeight),
      Paint()..color = Colors.redAccent,
    );
    // Text logic needed... skipping for brevity, simpler boxes for now.

    // Draw Apply Button
    canvas.drawRect(
      Rect.fromLTWH(applyBtnX, btnY, applyBtnWidth, btnHeight),
      Paint()..color = Colors.green,
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(w, h); // w, h from capabilities
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData != null) {
      final bytes = byteData.buffer.asUint8List();
      // Convert RGBA to what Wacom wants?
      // EncodingMode_24bit_Bulk (0x14) or EncodingMode_24bit (0x04) usually takes RGB or BGR.
      // Trying 24bit encoded.
      // IMPORTANT: rawRgba has 4 bytes per pixel. Wacom 24bit expects 3.
      // We need to strip Alpha.

      final rgbBytes = Uint8List(w * h * 3);
      int listIndex = 0;
      for (int i = 0; i < bytes.length; i += 4) {
        rgbBytes[listIndex++] = bytes[i]; // R
        rgbBytes[listIndex++] = bytes[i + 1]; // G
        rgbBytes[listIndex++] = bytes[i + 2]; // B
        // a is skipped
      }

      try {
        await methodChannel.invokeMethod('setSignatureScreen', {
          'data': rgbBytes,
          'mode': 0x04, // EncodingMode_24bit
        });

        if (!refreshOnly) {
          setState(() {
            _isInlineSignatureMode = true;
            signatureStrokes.clear();
            currentSignatureStroke.clear();
          });
        }
      } catch (e) {
        print("Error setting signature screen: $e");
      }
    }
  }

  Future<void> _stopInlineSignatureMode() async {
    await clearScreen();
    setState(() {
      _isInlineSignatureMode = false;
    });
  }

  void _handleSignatureInput(double x, double y, double pressure, int sw) {
    if (_signatureBoxSize == null || _signatureBoxPosition == null) return;

    // Map tablet to signature box
    // Assuming we want to map the WHOLE tablet to the signature box for precision
    final boxX = (x / tabletMaxX!) * _signatureBoxSize!.width;
    final boxY = (y / tabletMaxY!) * _signatureBoxSize!.height;

    // Optional: Filter points outside? No, clamping might be better or just let it draw.

    setState(() {
      if (sw != 0 || pressure > 0) {
        currentSignatureStroke.add(Offset(boxX, boxY));
      } else {
        if (currentSignatureStroke.isNotEmpty) {
          signatureStrokes.add(List.from(currentSignatureStroke));
          currentSignatureStroke.clear();
        }
      }
    });

    // Notify dialog to rebuild
    _dialogSetState?.call(() {});
  }

  Function(void Function())? _dialogSetState;

  void _openSignatureDialog() {
    setState(() {
      _isSignatureDialogOpen = true;
      signatureStrokes.clear();
      currentSignatureStroke.clear();
      _signatureBoxSize = null;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            _dialogSetState = setState;
            return AlertDialog(
              title: const Text("Sign Here"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    key: _signatureBoxKey,
                    width: 400,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black),
                      color: Colors.white,
                    ),
                    child: CustomPaint(
                      painter: SignaturePainter(
                        signatureStrokes,
                        currentSignatureStroke,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text("Use Wacom Pen to Sign inside the box"),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      signatureStrokes.clear();
                      currentSignatureStroke.clear();
                    });
                  },
                  child: const Text("Clear"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Apply logic handled in then/or setState of main
                    setState(() {
                      // This setState is dialog's, but we need main's too?
                      // Actually we trigger main's setState below after pop.
                    });
                    _applySignature();
                  },
                  child: const Text("Apply"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text("Cancel"),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      _dialogSetState = null;
      if (_isSignatureDialogOpen) {
        setState(() => _isSignatureDialogOpen = false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSignatureBoxGeometry();
    });
  }

  void _applySignature() {
    setState(() {
      _isSignatureDialogOpen = false;
      // ADD TO SCREEN ANNOTATIONS for now to ensure visibility
      if (_pdfViewSize != null) {
        final center = Offset(
          _pdfViewSize!.width / 2 - 200,
          _pdfViewSize!.height / 2 - 100,
        );
        for (var stroke in signatureStrokes) {
          screenAnnotations.add(stroke.map((p) => p + center).toList());
        }
      }
    });
  }

  void _updateSignatureBoxGeometry() {
    final RenderBox? box =
        _signatureBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      // We don't need to rebuild dialog here, just update state variables
      // But _MyAppState holds them.
      // We do NOT need to call _dialogSetState here unless we want to show something.
      // But we should setState of MyApp to store the values.
      setState(() {
        _signatureBoxSize = box.size;
        _signatureBoxPosition = box.localToGlobal(Offset.zero);
      });
    } else {
      // Retry if not ready
      Future.delayed(
        const Duration(milliseconds: 100),
        _updateSignatureBoxGeometry,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Measure main PDF view for annotation mapping
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final RenderBox? box =
          _pdfKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        if (_pdfViewSize != box.size) {
          setState(() {
            _pdfViewSize = box.size;
          });
        }
      }
    });

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Wacom PDF Annotation"),
          actions: [
            Text(status, style: const TextStyle(fontSize: 12)),

            // Clear Menu
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'pdf') {
                  setState(() {
                    screenAnnotations.clear();
                    currentScreenAnnotation.clear();
                  });
                } else if (value == 'tablet') {
                  clearScreen();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'pdf',
                  child: Text('Clear PDF Drawings'),
                ),
                const PopupMenuItem<String>(
                  value: 'tablet',
                  child: Text('Clear Tablet Screen'),
                ),
              ],
            ),

            IconButton(
              icon: const Icon(Icons.edit_note),
              onPressed: _openSignatureDialog,
              tooltip: "Add Signature",
            ),

            IconButton(
              icon: const Icon(Icons.usb),
              onPressed: connect,
              tooltip: "Connect",
            ),
            IconButton(
              icon: const Icon(Icons.usb_off),
              onPressed: disconnect,
              tooltip: "Disconnect",
            ),
          ],
        ),
        body: Container(
          key: _pdfKey,
          color: Colors.grey[200],
          child: Stack(
            children: [
              // PDF Viewer with Scroll
              PdfViewer.asset(
                'assets/pdf/Research_Design.pdf',
                controller: _pdfController,
                // Using default params to ensure scrolling works
                params: PdfViewerParams(),
              ),
              // Screen Overlay for Direct Annotation (Floating)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring:
                      _isInlineSignatureMode, // Allow interaction if needed, or just let pen handle it
                  child: CustomPaint(
                    painter: SignaturePainter(
                      screenAnnotations,
                      currentScreenAnnotation,
                    ),
                  ),
                ),
              ),

              // Inline Signature Box Overlay
              if (_isInlineSignatureMode)
                Positioned(
                  left:
                      (_pdfViewSize?.width ??
                              MediaQuery.of(context).size.width) /
                          2 -
                      200,
                  top:
                      (_pdfViewSize?.height ??
                              MediaQuery.of(context).size.height) /
                          2 -
                      100,
                  child: Container(
                    width: 400,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      border: Border.all(color: Colors.blueAccent, width: 2),
                      boxShadow: const [
                        BoxShadow(blurRadius: 10, color: Colors.black26),
                      ],
                    ),
                    child: Stack(
                      children: [
                        const Positioned(
                          top: 5,
                          right: 5,
                          child: Text(
                            "Signature Box",
                            style: TextStyle(color: Colors.grey, fontSize: 10),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(400, 200),
                          painter: SignaturePainter(
                            signatureStrokes,
                            currentSignatureStroke,
                          ),
                        ),
                      ],
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

class SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> currentStroke;

  SignaturePainter(this.strokes, this.currentStroke);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
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
  bool shouldRepaint(SignaturePainter oldDelegate) => true;
}
