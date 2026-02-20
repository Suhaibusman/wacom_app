import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:wacom_app/core/providers.dart';
import 'package:wacom_app/features/home/ui/widgets/wacom_connect_button.dart';
import '../../signature/ui/signature_dialog.dart';
import '../../signature/ui/saved_signatures_dialog.dart';
import 'widgets/signature_box_overlay.dart';

class SignatureBoxModel {
  final String id;
  // We store the PDF Rect (unscaled, page coordinates)
  Rect pdfRect;
  Uint8List? image;
  int pageIndex; // 0-based page index

  SignatureBoxModel({
    required this.id,
    required this.pdfRect,
    this.image,
    required this.pageIndex,
  });
}

class PdfViewerScreen extends ConsumerStatefulWidget {
  final File file;

  const PdfViewerScreen({super.key, required this.file});

  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey _pdfKey = GlobalKey();

  // PDF Metadata
  PdfDocument? _document;
  List<Size>? _pageSizes;
  bool _isDocumentLoaded = false;

  // Signature Boxes State
  final List<SignatureBoxModel> _signatures = [];

  Size? _viewportSize;

  // Debounce/Throttle for scroll updates if necessary
  // For now, we update on every frame for smoothness.
  Timer? _scrollPoller;

  @override
  void initState() {
    super.initState();
    _loadPdfMetadata();
    // Start polling scroll offset to ensure sticky signatures update
    // This acts as a backup if NotificationListener doesn't catch internal scrolls
    _scrollPoller = Timer.periodic(const Duration(milliseconds: 32), (_) {
      if (_isDocumentLoaded && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _scrollPoller?.cancel();
    super.dispose();
  }

  Future<void> _loadPdfMetadata() async {
    try {
      final bytes = await widget.file.readAsBytes();
      _document = PdfDocument(inputBytes: bytes);
      _pageSizes = [];
      for (int i = 0; i < _document!.pages.count; i++) {
        _pageSizes!.add(_document!.pages[i].getClientSize());
      }
      setState(() {
        _isDocumentLoaded = true;
      });
    } catch (e) {
      debugPrint("Error loading PDF metadata: $e");
    }
  }

  // ... _addSignatureBox ...

  // ...

  // Calculate/Guess spacing between pages in SfPdfViewer.
  // Common default is around 8-10 pixels.
  final double _pageSpacing = 8.0;

  Rect _getScreenRect(SignatureBoxModel model) {
    if (_pageSizes == null || _isDocumentLoaded == false) return Rect.zero;

    final zoom = _pdfController.zoomLevel;
    final scroll = _pdfController.scrollOffset;

    // Calculate Vertical Offset of the Page
    double pageTop = 0;
    for (int i = 0; i < model.pageIndex; i++) {
      // ...
      // Syncfusion lays out pages vertically.
      // Height = Page Height * Zoom + Spacing
      pageTop += (_pageSizes![i].height * zoom) + _pageSpacing;
    }

    // Calculate Horizontal Centering Margin
    double marginLeft = 0;
    if (_viewportSize != null) {
      final pageWidthScaled = _pageSizes![model.pageIndex].width * zoom;
      if (pageWidthScaled < _viewportSize!.width) {
        marginLeft = (_viewportSize!.width - pageWidthScaled) / 2;
      }
    }

    const double kShadowOffset = 10.0;

    final double screenX =
        (model.pdfRect.left * zoom) + marginLeft + kShadowOffset - scroll.dx;
    final double screenY =
        (model.pdfRect.top * zoom) + pageTop + kShadowOffset - scroll.dy;
    final double screenW = model.pdfRect.width * zoom;
    final double screenH = model.pdfRect.height * zoom;

    // Debugging scroll tracking
    // debugPrint("P${model.pageIndex} Scroll:${scroll.dy.toStringAsFixed(1)} Top:$pageTop Y:$screenY");

    return Rect.fromLTWH(screenX, screenY, screenW, screenH);
  }

  void _addSignatureBox() {
    // Basic implementation: Add to the CURRENT page center
    if (!_isDocumentLoaded || _pageSizes == null) return;

    // Get current page (1-based from controller)
    final int pageNum = _pdfController.pageNumber;
    final int pageIndex = pageNum - 1;

    if (pageIndex < 0 || pageIndex >= _pageSizes!.length) return;

    final pageSize = _pageSizes![pageIndex];
    // Center of the PDF page
    final double w = 200;
    final double h = 100;

    final pdfRect = Rect.fromLTWH(
      (pageSize.width - w) / 2,
      (pageSize.height - h) / 2,
      w,
      h,
    );

    setState(() {
      _signatures.add(
        SignatureBoxModel(
          id: const Uuid().v4(),
          pdfRect: pdfRect,
          pageIndex: pageIndex,
        ),
      );
    });
  }

  void _showSignatureOptions(SignatureBoxModel model) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.create),
                title: const Text("Create New Signature"),
                onTap: () {
                  Navigator.pop(context);
                  _openSignatureDialog(model);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text("Select Saved Signature"),
                onTap: () {
                  Navigator.pop(context);
                  _openSavedSignaturesDialog(model);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSignatureDialog(SignatureBoxModel model) async {
    // Validation: Check if Wacom is connected
    final wacomState = ref.read(wacomConnectionProvider);
    if (!wacomState.isConnected) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Device Not Connected"),
          content: const Text("Please connect the Wacom device first."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    final Uint8List? result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SignatureDialog(),
    );

    if (!mounted) return;
    if (result != null) {
      setState(() {
        model.image = result;
      });
    }
  }

  void _openSavedSignaturesDialog(SignatureBoxModel model) async {
    final Uint8List? result = await showDialog(
      context: context,
      builder: (context) => const SavedSignaturesDialog(),
    );

    if (!mounted) return;
    if (result != null) {
      setState(() {
        model.image = result;
      });
    }
  }

  void _updateModelFromScreenRect(SignatureBoxModel model, Rect screenRect) {
    if (_pageSizes == null) return;

    final zoom = _pdfController.zoomLevel;
    final scroll = _pdfController.scrollOffset;

    double pageTop = 0;
    for (int i = 0; i < model.pageIndex; i++) {
      pageTop += (_pageSizes![i].height * zoom) + _pageSpacing;
    }

    // Calculate Horizontal Centering Margin
    double marginLeft = 0;
    if (_viewportSize != null) {
      final pageWidthScaled = _pageSizes![model.pageIndex].width * zoom;
      if (pageWidthScaled < _viewportSize!.width) {
        marginLeft = (_viewportSize!.width - pageWidthScaled) / 2;
      }
    }

    final double pdfX = (screenRect.left + scroll.dx - marginLeft) / zoom;
    final double pdfY = (screenRect.top + scroll.dy - pageTop) / zoom;
    final double pdfW = screenRect.width / zoom;
    final double pdfH = screenRect.height / zoom;

    debugPrint("--- Coord Debug ---");
    debugPrint("ScreenRect: $screenRect");
    debugPrint("Scroll: $scroll, Zoom: $zoom");
    debugPrint("Viewport: $_viewportSize");
    debugPrint("PageSize(PDF): ${_pageSizes![model.pageIndex]}");
    debugPrint("PageTop: $pageTop, MarginLeft: $marginLeft");
    debugPrint("Calculated PDF: X=$pdfX, Y=$pdfY");
    debugPrint("-------------------");

    model.pdfRect = Rect.fromLTWH(pdfX, pdfY, pdfW, pdfH);
  }

  void _saveDocument() async {
    // Check if any signature is placed
    if (_signatures.isEmpty && _signatures.every((s) => s.image == null)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No signatures to save.")));
      return;
    }

    final signedBoxes = _signatures.where((s) => s.image != null).toList();
    if (signedBoxes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign at least one box.")),
      );
      return;
    }

    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Signed PDF',
        fileName: 'signed_${path.basename(widget.file.path)}',
        allowedExtensions: ['pdf'],
        type: FileType.custom,
      );

      if (outputFile == null) {
        return; // User canceled
      }

      if (!outputFile.toLowerCase().endsWith('.pdf')) {
        outputFile = '$outputFile.pdf';
      }

      final pdfService = ref.read(pdfServiceProvider);

      final newBytes = await pdfService.embedSignatures(
        pdfFile: widget.file,
        signatures: signedBoxes
            .map(
              (s) => {
                'image': s.image!,
                'x': s.pdfRect.left,
                'y': s.pdfRect.top,
                'width': s.pdfRect.width,
                'height': s.pdfRect.height,
                'pageIndex':
                    s.pageIndex + 1, // Service likely expects 1-based index
              },
            )
            .toList(),
      );

      final fileService = ref.read(fileServiceProvider);
      final savedFile = await fileService.saveSignedPdf(newBytes, outputFile);

      await ref.read(recentFilesServiceProvider).addRecentFile(savedFile.path);
      ref.invalidate(recentFilesProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Saved to: ${savedFile.path}")));
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
          const WacomConnectButton(),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveDocument,
            tooltip: "Save Document",
          ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Rebuild on scroll to update sticky signatures
          setState(() {});
          return true;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Update viewport size
            if (_viewportSize != constraints.biggest) {
              // Determine if we need to schedule a build or just update state
              // Since this is inside build, we shouldn't setState immediately if it triggers rebuild
              // But we need the value for calculating rects.
              _viewportSize = constraints.biggest;
            }

            return Stack(
              clipBehavior: Clip.none,
              key: _pdfKey,
              children: [
                SfPdfViewer.file(
                  widget.file,
                  controller: _pdfController,
                  pageSpacing: 8.0, // Explicitly match our calculation
                  enableDoubleTapZooming: false,
                  onTap: (details) {
                    // Place signature exactly where the user taps
                    final pagePos = details.pagePosition;
                    final int pageIndex = details.pageNumber - 1; // 0-based

                    setState(() {
                      _signatures.add(
                        SignatureBoxModel(
                          id: const Uuid().v4(),
                          pdfRect: Rect.fromLTWH(
                            pagePos.dx,
                            pagePos.dy,
                            200,
                            100,
                          ),
                          pageIndex: pageIndex,
                        ),
                      );
                    });
                  },
                  onPageChanged: (details) {
                    setState(() {});
                  },
                  onZoomLevelChanged: (details) {
                    setState(() {});
                  },
                ),

                if (_isDocumentLoaded)
                  ..._signatures.map((model) {
                    final rect = _getScreenRect(model);
                    // Only render if visible on screen? Optional optimization.
                    return SignatureBoxOverlay(
                      rect: rect,
                      signatureImage: model.image,
                      onUpdate: (newRect) {
                        _updateModelFromScreenRect(model, newRect);
                      },
                      onConfirm: () => _showSignatureOptions(model),
                      onDelete: () {
                        setState(() {
                          _signatures.remove(model);
                        });
                      },
                    );
                  }),

                // Floating Action Button to add signature
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: FloatingActionButton.extended(
                    onPressed: _addSignatureBox,
                    label: const Text("Add Signature"),
                    icon: const Icon(Icons.add),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
