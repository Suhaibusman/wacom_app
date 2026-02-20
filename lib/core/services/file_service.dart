import 'dart:io';
import 'package:file_picker/file_picker.dart';

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

  Future<File> saveSignedPdf(List<int> bytes, String destinationPath) async {
    final file = File(destinationPath);
    return await file.writeAsBytes(bytes);
  }
}
