import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  Future<Uint8List> embedSignatures({
    required File pdfFile,
    required List<Map<String, dynamic>> signatures,
  }) async {
    final pdfBytes = await pdfFile.readAsBytes();

    // Load the existing PDF document
    final PdfDocument document = PdfDocument(inputBytes: pdfBytes);

    try {
      debugPrint(
        "EmbedSignatures: Processing ${signatures.length} signatures.",
      );
      for (final signature in signatures) {
        final Uint8List image = signature['image'];
        final double x = signature['x'];
        final double y = signature['y'];
        final double width = signature['width'];
        final double height = signature['height'];
        final int pageIndex = signature['pageIndex'];

        debugPrint(
          "Embedding Signature: Page=$pageIndex, X=$x, Y=$y, W=$width, H=$height",
        );

        // Get the specific page
        // SfPdfViewer 'pageNumber' is 1-based or whatever passed.
        // We ensure consistent 0-based indexing relative to the document.
        // If the caller passes 1-based, we convert.
        // Here we assume the caller has already handled the logic or we check bounds.
        // In this app, we passed 'pageIndex + 1' from PdfViewerScreen to Service previously?
        // Let's check PdfViewerScreen. currently it passes 's.pageIndex + 1'.
        // So 'pageIndex' here is 1-based.

        final int index = (pageIndex > 0 && pageIndex <= document.pages.count)
            ? pageIndex - 1
            : 0;

        debugPrint(
          "Target PDF Page Index: $index (Total Pages: ${document.pages.count})",
        );

        final PdfPage page = document.pages[index];
        final Size pageSize = page.getClientSize();
        debugPrint("PDF Page Size: W=${pageSize.width}, H=${pageSize.height}");

        if (x + width > pageSize.width || y + height > pageSize.height) {
          debugPrint(
            "WARNING: Signature might be out of bounds! MaxW=${pageSize.width}, MaxH=${pageSize.height}",
          );
        }

        // Draw the signature image directly using PDF coordinates
        page.graphics.drawImage(
          PdfBitmap(image),
          Rect.fromLTWH(x, y, width, height),
        );
      }

      // Save the document
      final List<int> bytes = await document.save();
      return Uint8List.fromList(bytes);
    } finally {
      document.dispose();
    }
  }
}
