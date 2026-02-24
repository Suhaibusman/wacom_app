import 'dart:typed_data';
import 'package:flutter/material.dart';

class SignatureBoxOverlay extends StatefulWidget {
  final Rect rect; // Changed from initialPosition
  final Function(Offset) onUpdate; // Pass Delta instead of absolute Rect
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
              : const Color(0xFF4F46E5).withAlpha(25), // AppColors.primary
          border: Border.all(
            color: const Color(0xFF4F46E5),
            width: 2,
            strokeAlign: BorderSide.strokeAlignCenter,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Drag Handler (Center/Background)
            Positioned.fill(
              child: GestureDetector(
                onPanUpdate: (details) {
                  _updatePosition(_position + details.delta);
                  // Commit delta to parent immediately
                  widget.onUpdate(details.delta);
                },
                onPanEnd: (details) {
                  // Finalizing
                },
                onTap: widget.onConfirm, // Setup tap to open dialog
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: widget.signatureImage != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            widget.signatureImage!,
                            fit: BoxFit.contain,
                          ),
                        )
                      : const Center(
                          child: Text(
                            "Tap to Sign",
                            style: TextStyle(
                              color: Color(0xFF4F46E5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ),
            ),

            // 2. Resize Handle (Bottom Right)
            Positioned(
              right: -12,
              bottom: -12,
              child: GestureDetector(
                onPanUpdate: (details) {
                  _updateSize(
                    Size(
                      (_size.width + details.delta.dx).clamp(100.0, 500.0),
                      (_size.height + details.delta.dy).clamp(50.0, 300.0),
                    ),
                  );
                  // We aren't doing size updates on the model yet for PDF, just UI.
                },
                onPanEnd: (details) {
                  // Size update finalization
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.open_in_full_rounded,
                      color: Color(0xFF64748B),
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),

            // 3. Confirm/Sign Button (Top Right)
            Positioned(
              right: -12,
              top: -12,
              child: GestureDetector(
                onTap: widget.onConfirm,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981), // success
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

            // 4. Delete Button (Top Left)
            Positioned(
              left: -12,
              top: -12,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444), // error
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
