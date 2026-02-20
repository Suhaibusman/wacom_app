import 'dart:typed_data';
import 'package:flutter/material.dart';

class SignatureBoxOverlay extends StatefulWidget {
  final Rect rect; // Changed from initialPosition
  final Function(Rect) onUpdate;
  final VoidCallback onConfirm;
  final VoidCallback onDelete;
  final Uint8List? signatureImage;

  const SignatureBoxOverlay({
    super.key,
    required this.rect,
    required this.onUpdate,
    required this.onConfirm,
    required this.onDelete,
    this.signatureImage,
  });

  @override
  State<SignatureBoxOverlay> createState() => _SignatureBoxOverlayState();
}

class _SignatureBoxOverlayState extends State<SignatureBoxOverlay> {
  late Offset _position;
  late Size _size;

  @override
  void initState() {
    super.initState();
    _position = widget.rect.topLeft;
    _size = widget.rect.size;
  }

  @override
  void didUpdateWidget(SignatureBoxOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rect != widget.rect) {
      _position = widget.rect.topLeft;
      _size = widget.rect.size;
    }
  }

  void _updatePosition(Offset newPosition) {
    setState(() {
      _position = newPosition;
    });
  }

  void _updateSize(Size newSize) {
    setState(() {
      _size = newSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Container(
        width: _size.width,
        height: _size.height,
        // The main container decoration
        decoration: BoxDecoration(
          color: widget.signatureImage != null
              ? Colors.transparent
              : Colors.blue.withAlpha(25),
          border: Border.all(color: Colors.blueAccent, width: 2),
        ),
        child: Stack(
          clipBehavior:
              Clip.none, // Allow buttons to be slightly outside if needed
          children: [
            // 1. Drag Handler (Center/Background)
            Positioned.fill(
              child: GestureDetector(
                onPanUpdate: (details) {
                  _updatePosition(_position + details.delta);
                },
                onPanEnd: (details) {
                  // Commit final position to parent
                  widget.onUpdate(
                    Rect.fromLTWH(
                      _position.dx,
                      _position.dy,
                      _size.width,
                      _size.height,
                    ),
                  );
                },
                onTap: widget.onConfirm, // Setup tap to open dialog
                child: Container(
                  color: Colors.transparent, // Capture taps
                  child: widget.signatureImage != null
                      ? Image.memory(
                          widget.signatureImage!,
                          fit: BoxFit.contain,
                        )
                      : const Center(
                          child: Text(
                            "Tap to Sign",
                            style: TextStyle(color: Colors.blue),
                          ),
                        ),
                ),
              ),
            ),

            // 2. Resize Handle (Bottom Right)
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onPanUpdate: (details) {
                  _updateSize(
                    Size(
                      (_size.width + details.delta.dx).clamp(100.0, 500.0),
                      (_size.height + details.delta.dy).clamp(50.0, 300.0),
                    ),
                  );
                },
                onPanEnd: (details) {
                  widget.onUpdate(
                    Rect.fromLTWH(
                      _position.dx,
                      _position.dy,
                      _size.width,
                      _size.height,
                    ),
                  );
                },
                child: Container(
                  width: 30, // Larger hit area
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                    ),
                  ),
                  child: const Icon(
                    Icons.drag_handle,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),

            // 3. Confirm/Sign Button (Top Right)
            Positioned(
              right: 0, // Inside the box
              top: 0,
              child: GestureDetector(
                onTap: widget.onConfirm,
                child: Container(
                  width: 36, // Explicit larger size
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 24),
                ),
              ),
            ),

            // 4. Delete Button (Top Left)
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: 36, // Explicit larger size
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.only(
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
