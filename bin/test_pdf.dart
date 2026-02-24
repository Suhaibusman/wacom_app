import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() async {
  // Create a new PDF document.
  final PdfDocument document = PdfDocument();

  // Add a new page to the document.
  final PdfPage page = document.pages.add();

  // Draw a rectangle at exactly 0,0 with width 100 and height 100
  // and color it red.
  page.graphics.drawRectangle(
    brush: PdfSolidBrush(PdfColor(255, 0, 0)),
    bounds: const Rect.fromLTWH(0, 0, 100, 100),
  );

  page.graphics.drawRectangle(
    brush: PdfSolidBrush(PdfColor(0, 255, 0)),
    bounds: const Rect.fromLTWH(0, 700, 100, 100),
  ); // Should be bottom left if origin is top-left

  // Save the document.
  final List<int> bytes = await document.save();

  // Dispose the document.
  document.dispose();

  // Write the PDF to a file.
  File('test_pdf.pdf').writeAsBytesSync(bytes);
  print('PDF generated successfully. Check test_pdf.pdf');
}
