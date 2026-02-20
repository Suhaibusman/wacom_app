import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:wacom_app/core/providers.dart';
import '../../signature/ui/signature_dialog.dart';
import 'widgets/signature_box_overlay.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  final File file;

  const PdfViewerScreen({super.key, required this.file});

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey _pdfKey = GlobalKey();

  // Signature Box State
  bool _isBoxVisible = false;
  Rect _boxRect = const Rect.fromLTWH(100, 100, 200, 100);
  Uint8List? _signatureImage;

  void _onTapPdf(TapDownDetails details) {
    if (!_isBoxVisible) {
      // Get tap position relative to the Stack/Container
      final RenderBox box =
          _pdfKey.currentContext!.findRenderObject() as RenderBox;
      final localPos = box.globalToLocal(details.globalPosition);

      setState(() {
        _isBoxVisible = true;
        _boxRect = Rect.fromLTWH(localPos.dx, localPos.dy, 200, 100);
      });
    }
  }

  void _openSignatureDialog() async {
    print("Opening signature dialog...");
    final Uint8List? result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SignatureDialog(),
    );

    print("Signature Dialog Result: ${result?.length} bytes");

    if (result != null) {
      setState(() {
        _signatureImage = result;
      });
      print("Signature image set in state.");
    } else {
      print("Signature result was null.");
    }
  }

  void _saveDocument() async {
    if (_signatureImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign the document first.")),
      );
      return;
    }

    try {
      // 1. Ask user where to save
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Signed PDF',
        fileName: 'signed_${path.basename(widget.file.path)}',
        allowedExtensions: ['pdf'],
        type: FileType.custom,
      );

      if (outputFile == null) {
        // User canceled
        return;
      }

      // Ensure extension is .pdf
      if (!outputFile.toLowerCase().endsWith('.pdf')) {
        outputFile = '$outputFile.pdf';
      }

      final pdfService = ref.read(pdfServiceProvider);
      // Coordinate mapping logic would go here
      // For now, passing placeholder values or implementation-specific logic

      final newBytes = await pdfService.embedSignature(
        pdfFile: widget.file,
        signatureImage: _signatureImage!,
        x: _boxRect.left,
        y: _boxRect.top,
        width: _boxRect.width,
        height: _boxRect.height,
        pageIndex: _pdfController.pageNumber,
        viewWidth: MediaQuery.of(context).size.width,
      );

      final fileService = ref.read(fileServiceProvider);
      // Pass the chosen path directly
      final savedFile = await fileService.saveSignedPdf(
        newBytes,
        outputFile, // Use the user-picked path
      );

      await ref.read(recentFilesServiceProvider).addRecentFile(savedFile.path);

      // FORCE REFRESH the provider so Home Screen updates
      ref.invalidate(recentFilesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Saved to: ${savedFile.path}")));

      // Optionally navigate back or stay? User said "direct recent me show nhi horha",
      // implying they might expect to see it. If we stay here, valid.
      // If we go back:
      // Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error saving: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(path.basename(widget.file.path)),
        actions: [
          if (_signatureImage != null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveDocument,
              tooltip: "Save Document",
            ),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: _onTapPdf, // Double tap to add box? Or FAB?
        child: Stack(
          key: _pdfKey,
          children: [
            SfPdfViewer.file(
              widget.file,
              controller: _pdfController,
              enableDoubleTapZooming: false, // Disable to allow our gesture
              onTap: (details) {
                // Syncfusion has its own tap handling, might conflict with standard GestureDetector
                // Coordinate mapping is simpler if we use overlay
                // Logic: If box not visible, tap creates it?
              },
            ),

            // Floating Action Button instruction if box not present
            if (!_isBoxVisible)
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      _isBoxVisible = true;
                      _boxRect = const Rect.fromLTWH(100, 100, 200, 100);
                    });
                  },
                  label: const Text("Add Signature"),
                  icon: const Icon(Icons.edit),
                ),
              ),

            if (_isBoxVisible)
              SignatureBoxOverlay(
                initialPosition: _boxRect.topLeft,
                signatureImage: _signatureImage,
                onUpdate: (rect) {
                  _boxRect = rect;
                },
                onConfirm: _openSignatureDialog,
                onDelete: () {
                  setState(() {
                    _isBoxVisible = false;
                    _signatureImage = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}
