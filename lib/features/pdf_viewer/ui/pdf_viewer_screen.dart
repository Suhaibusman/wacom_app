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
import 'package:wacom_app/core/constants/app_colors.dart';
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

  // Mouse Drag-to-Draw State
  bool _isDrawingMode = false;
  Offset? _dragStartScreenPos;
  Offset? _dragCurrentScreenPos;
  int? _dragPageIndex;

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

      // Attempt to auto-fit zoom after a short frame delay to allow LayoutBuilder to size
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_viewportSize != null && _pageSizes!.isNotEmpty) {
          double maxPageWidth = 0;
          for (var size in _pageSizes!) {
            if (size.width > maxPageWidth) maxPageWidth = size.width;
          }
          if (maxPageWidth > 0 && maxPageWidth > _viewportSize!.width) {
            // Add a slight margin so it doesn't touch edges tightly
            final double targetZoom =
                (_viewportSize!.width - 32) / maxPageWidth;
            // Syncfusion limits min zoom, so we just set it as low as we want and it caps itself
            _pdfController.zoomLevel = targetZoom;
          }
        }
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

  double get _internalScale {
    if (_viewportSize == null || _pageSizes == null || _pageSizes!.isEmpty) {
      return 1.0;
    }
    double maxPageWidth = 0;
    for (var size in _pageSizes!) {
      if (size.width > maxPageWidth) maxPageWidth = size.width;
    }
    if (maxPageWidth == 0) return 1.0;
    return _viewportSize!.width / maxPageWidth;
  }

  Rect _getScreenRect(SignatureBoxModel model) {
    if (_pageSizes == null || _isDocumentLoaded == false) return Rect.zero;

    final zoom = _pdfController.zoomLevel * _internalScale;
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

    final double screenX = (model.pdfRect.left * zoom) + marginLeft - scroll.dx;
    final double screenY = (model.pdfRect.top * zoom) + pageTop - scroll.dy;
    final double screenW = model.pdfRect.width * zoom;
    final double screenH = model.pdfRect.height * zoom;

    // Debugging scroll tracking
    if (model.pageIndex > 0) {
      // Log mainly for subsequent pages to reduce spam
      debugPrint(
        "Render Sig: P${model.pageIndex} | PageTop:$pageTop | Scroll:${scroll.dy} | ScreenY:$screenY | Rect:$screenX,$screenY",
      );
    }

    return Rect.fromLTWH(screenX, screenY, screenW, screenH);
  }

  void _toggleDrawingMode() {
    setState(() {
      _isDrawingMode = !_isDrawingMode;
      // Reset drag state if toggling off
      if (!_isDrawingMode) {
        _dragStartScreenPos = null;
        _dragCurrentScreenPos = null;
        _dragPageIndex = null;
      }
    });

    if (_isDrawingMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Draw Mode: Click and drag on the PDF to create a signature box.",
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }
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

  void _handleSignatureDrag(SignatureBoxModel model, Offset globalDelta) {
    if (_pageSizes == null || _pageSizes!.isEmpty) return;

    final zoom = _pdfController.zoomLevel * _internalScale;

    // Convert the screen-drag delta map directly into PDF Point delta.
    final double deltaX = globalDelta.dx / zoom;
    final double deltaY = globalDelta.dy / zoom;

    setState(() {
      model.pdfRect = Rect.fromLTWH(
        model.pdfRect.left + deltaX,
        model.pdfRect.top + deltaY,
        model.pdfRect.width,
        model.pdfRect.height,
      );

      // Now, casually check if it crossed a page boundary by seeing if Y exceeded
      // current page limits.
      // (This handles moving DOWN)
      final currentPageHeight = _pageSizes![model.pageIndex].height;
      if (model.pdfRect.top > currentPageHeight) {
        if (model.pageIndex < _pageSizes!.length - 1) {
          model.pageIndex++;
          // Shift the rect Y into the new page's coordinate space
          model.pdfRect = Rect.fromLTWH(
            model.pdfRect.left,
            model.pdfRect.top - currentPageHeight,
            model.pdfRect.width,
            model.pdfRect.height,
          );
        }
      }
      // (This handles moving UP)
      else if (model.pdfRect.top < 0) {
        if (model.pageIndex > 0) {
          model.pageIndex--;
          final previousPageHeight = _pageSizes![model.pageIndex].height;
          // Shift the rect Y back into the previous page's bottom bounds
          model.pdfRect = Rect.fromLTWH(
            model.pdfRect.left,
            previousPageHeight + model.pdfRect.top, // top is negative here
            model.pdfRect.width,
            model.pdfRect.height,
          );
        }
      }
    });

    // Debug tracking
    debugPrint(
      "Moved Sig to P${model.pageIndex} : PDF[${model.pdfRect.left}, ${model.pdfRect.top}]",
    );
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
        shadowColor: AppColors.border,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              path.basename(widget.file.path),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            const SizedBox(height: 2),
            const Text(
              "PDF Viewer",
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceHover,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out, size: 20),
                  tooltip: 'Zoom Out',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _pdfController.zoomLevel = (_pdfController.zoomLevel - 0.25)
                          .clamp(0.5, 3.0);
                    });
                  },
                ),
                Container(
                  width: 1,
                  height: 22,
                  color: AppColors.border,
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in, size: 20),
                  tooltip: 'Zoom In',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      _pdfController.zoomLevel = (_pdfController.zoomLevel + 0.25)
                          .clamp(0.5, 3.0);
                    });
                  },
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: WacomConnectButton(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: FilledButton.icon(
              onPressed: _saveDocument,
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text("Save Document"),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
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

                    final model = SignatureBoxModel(
                      id: const Uuid().v4(),
                      pdfRect: Rect.fromLTWH(
                        pagePos.dx,
                        pagePos.dy,
                        200,
                        100,
                      ),
                      pageIndex: pageIndex,
                    );
                    setState(() {
                      _signatures.add(model);
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _openSignatureDialog(model);
                      }
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
                      onUpdate: (delta) {
                        _handleSignatureDrag(model, delta);
                      },
                      onConfirm: () => _showSignatureOptions(model),
                      onDelete: () {
                        setState(() {
                          _signatures.remove(model);
                        });
                      },
                    );
                  }),

                // Invisible gesture detector over the PDF for drawing mode
                if (_isDrawingMode)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        setState(() {
                          _dragStartScreenPos = details.localPosition;
                          _dragCurrentScreenPos = details.localPosition;
                          _dragPageIndex = _pdfController.pageNumber > 0
                              ? _pdfController.pageNumber - 1
                              : 0;
                        });
                      },
                      onPanUpdate: (details) {
                        setState(() {
                          _dragCurrentScreenPos = details.localPosition;
                        });
                      },
                      onPanEnd: (details) {
                        if (_dragStartScreenPos != null &&
                            _dragCurrentScreenPos != null &&
                            _dragPageIndex != null &&
                            _pageSizes != null) {
                          // Calculate screen rect bounding box
                          final rawLeft = _dragStartScreenPos!.dx;
                          final rawTop = _dragStartScreenPos!.dy;
                          final rawRight = _dragCurrentScreenPos!.dx;
                          final rawBottom = _dragCurrentScreenPos!.dy;

                          final screenRect = Rect.fromLTRB(
                            rawLeft < rawRight ? rawLeft : rawRight,
                            rawTop < rawBottom ? rawTop : rawBottom,
                            rawLeft > rawRight ? rawLeft : rawRight,
                            rawTop > rawBottom ? rawTop : rawBottom,
                          );

                          // Enforce minimum size so users don't make tiny accidental cliques
                          if (screenRect.width > 30 && screenRect.height > 20) {
                            final zoom =
                                _pdfController.zoomLevel * _internalScale;
                            final scroll = _pdfController.scrollOffset;

                            // Reverse engineer screen -> pdf coordinates
                            // We need page top and left margins based on the zoom
                            double pageTop = 0;
                            for (int i = 0; i < _dragPageIndex!; i++) {
                              pageTop +=
                                  (_pageSizes![i].height * zoom) +
                                  (8.0 * zoom); // 8 is pageSpacing
                            }

                            double marginLeft = 0;
                            if (_viewportSize != null) {
                              final pageWidthScaled =
                                  _pageSizes![_dragPageIndex!].width * zoom;
                              if (pageWidthScaled < _viewportSize!.width) {
                                marginLeft =
                                    (_viewportSize!.width - pageWidthScaled) /
                                    2;
                              }
                            }

                            final double pdfX =
                                (screenRect.left + scroll.dx - marginLeft) /
                                zoom;
                            final double pdfY =
                                (screenRect.top + scroll.dy - pageTop) / zoom;
                            final double pdfW = screenRect.width / zoom;
                            final double pdfH = screenRect.height / zoom;

                            final model = SignatureBoxModel(
                              id: const Uuid().v4(),
                              pdfRect: Rect.fromLTWH(
                                pdfX,
                                pdfY,
                                pdfW,
                                pdfH,
                              ),
                              pageIndex: _dragPageIndex!,
                            );
                            setState(() {
                              _signatures.add(model);
                              // Exit drawing mode automatically after successful draw
                              _toggleDrawingMode();
                            });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _openSignatureDialog(model);
                              }
                            });
                          } else {
                            // Box too small, just cancel and let them try again
                            setState(() {
                              _dragStartScreenPos = null;
                              _dragCurrentScreenPos = null;
                            });
                          }
                        }
                      },
                      child: Stack(
                        children: [
                          if (_dragStartScreenPos != null &&
                              _dragCurrentScreenPos != null)
                            Positioned(
                              left:
                                  _dragStartScreenPos!.dx <
                                      _dragCurrentScreenPos!.dx
                                  ? _dragStartScreenPos!.dx
                                  : _dragCurrentScreenPos!.dx,
                              top:
                                  _dragStartScreenPos!.dy <
                                      _dragCurrentScreenPos!.dy
                                  ? _dragStartScreenPos!.dy
                                  : _dragCurrentScreenPos!.dy,
                              width:
                                  (_dragCurrentScreenPos!.dx -
                                          _dragStartScreenPos!.dx)
                                      .abs(),
                              height:
                                  (_dragCurrentScreenPos!.dy -
                                          _dragStartScreenPos!.dy)
                                      .abs(),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                    strokeAlign: BorderSide.strokeAlignOutside,
                                  ),
                                  color: AppColors.primaryLight.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                // Floating Action Button to toggle drawing mode OR add signature
                Positioned(
                  bottom: 32,
                  right: 32,
                  child: FloatingActionButton.extended(
                    onPressed: _toggleDrawingMode,
                    elevation: 4,
                    backgroundColor: _isDrawingMode
                        ? AppColors.error
                        : AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    label: Text(
                      _isDrawingMode ? "Cancel Drawing" : "Draw Signature Box",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    icon: Icon(
                      _isDrawingMode ? Icons.close : Icons.draw_rounded,
                    ),
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
