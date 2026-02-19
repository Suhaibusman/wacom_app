import 'dart:async';
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

  // Drawing

  // Screen overlay annotations (Legacy/Direct)
  List<List<Offset>> screenAnnotations = [];
  List<Offset> currentScreenAnnotation = [];

  // Signature Box Logic
  bool _isSignatureDialogOpen = false;
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

  void _handleSignatureInput(double x, double y, double pressure, int sw) {
    if (_signatureBoxSize == null || _signatureBoxPosition == null) {
      print("Signature box size/pos is null");
      return;
    }

    // Map tablet to signature box
    // Assuming we want to map the WHOLE tablet to the signature box for precision
    final boxX = (x / tabletMaxX!) * _signatureBoxSize!.width;
    final boxY = (y / tabletMaxY!) * _signatureBoxSize!.height;

    print("Mapping: Tablet($x, $y) -> Box($boxX, $boxY)");

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
  }

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
                setState(() {
                  _isSignatureDialogOpen = false;
                  // ADD TO SCREEN ANNOTATIONS for now to ensure visibility
                  if (_pdfViewSize != null) {
                    final center = Offset(
                      _pdfViewSize!.width / 2 - 200,
                      _pdfViewSize!.height / 2 - 100,
                    );
                    for (var stroke in signatureStrokes) {
                      screenAnnotations.add(
                        stroke.map((p) => p + center).toList(),
                      );
                    }
                  }
                });
              },
              child: const Text("Apply"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _isSignatureDialogOpen = false);
              },
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    ).then((_) {
      if (_isSignatureDialogOpen) {
        setState(() => _isSignatureDialogOpen = false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSignatureBoxGeometry();
    });
  }

  void _updateSignatureBoxGeometry() {
    final RenderBox? box =
        _signatureBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
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
                  child: CustomPaint(
                    painter: SignaturePainter(
                      screenAnnotations,
                      currentScreenAnnotation,
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
