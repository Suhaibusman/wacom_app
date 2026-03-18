import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileService {
  Future<File?> pickPdfFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }

  Future<File> downloadPdfFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Please enter a valid PDF URL.');
    }

    final client = HttpClient();

    try {
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Failed to download PDF (${response.statusCode}).',
          uri: uri,
        );
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      return _writeTempPdf(bytes);
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _writeTempPdf(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${tempDir.path}\\document_$timestamp.pdf');
    return file.writeAsBytes(bytes, flush: true);
  }

  Future<File> saveSignedPdf(List<int> bytes, String destinationPath) async {
    final file = File(destinationPath);
    return await file.writeAsBytes(bytes);
  }
}
