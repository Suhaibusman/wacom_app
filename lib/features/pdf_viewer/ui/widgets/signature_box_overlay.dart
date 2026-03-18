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
  static const double _controlSize = 32;
  static const double _controlInset = 12;
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
      left: _position.dx - _controlInset,
      top: _position.dy - _controlInset,
      child: SizedBox(
        width: _size.width + (_controlInset * 2),
        height: _size.height + (_controlInset * 2),
        child: Stack(
          children: [
            Positioned(
              left: _controlInset,
              top: _controlInset,
              child: Container(
                width: _size.width,
                height: _size.height,
                decoration: BoxDecoration(
                  color: widget.signatureImage != null
                      ? Colors.transparent
                      : const Color(0xFF4F46E5).withAlpha(25),
                  border: Border.all(
                    color: const Color(0xFF4F46E5),
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignCenter,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    _updatePosition(_position + details.delta);
                    widget.onUpdate(details.delta);
                  },
                  onTap: widget.onConfirm,
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
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDelete,
                child: Container(
                  width: _controlSize,
                  height: _controlSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
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
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  _updateSize(
                    Size(
                      (_size.width + details.delta.dx).clamp(100.0, 500.0),
                      (_size.height + details.delta.dy).clamp(50.0, 300.0),
                    ),
                  );
                },
                child: Container(
                  width: _controlSize,
                  height: _controlSize,
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
          ],
        ),
      ),
    );
  }
}
