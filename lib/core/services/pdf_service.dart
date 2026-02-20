import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfService {
  Future<Uint8List> embedSignature({
    required File pdfFile,
    required Uint8List signatureImage,
    required double x,
    required double y,
    required double width,
    required double height,
    required int pageIndex,
    required double viewWidth,
  }) async {
    final pdfBytes = await pdfFile.readAsBytes();

    // Load the existing PDF document
    final PdfDocument document = PdfDocument(inputBytes: pdfBytes);

    try {
      // Get the specific page
      // SfPdfViewer 'pageNumber' is 1-based. syncfusion_flutter_pdf is 0-based.
      // We'll normalize by subtracting 1 if > 0.
      final int index = (pageIndex > 0 && pageIndex <= document.pages.count)
          ? pageIndex - 1
          : 0;
      final PdfPage page = document.pages[index];

      final Size pageSize = page.getClientSize();

      // Calculate scale factor assuming "Fit Width" behavior of the viewer
      // scale = viewWidth / pdfPageWidth
      // coordinate_in_pdf = coordinate_in_screen / scale
      // Therefore: coordinate_in_pdf = coordinate_in_screen * (pdfPageWidth / viewWidth)

      final double scaleFactor = pageSize.width / viewWidth;

      final double pdfX = x * scaleFactor;
      final double pdfY = y * scaleFactor;
      final double pdfWidth = width * scaleFactor;
      final double pdfHeight = height * scaleFactor;

      // Draw the signature image
      page.graphics.drawImage(
        PdfBitmap(signatureImage),
        Rect.fromLTWH(pdfX, pdfY, pdfWidth, pdfHeight),
      );

      // Save the document
      final List<int> bytes = await document.save();
      return Uint8List.fromList(bytes);
    } finally {
      document.dispose();
    }
  }
}
