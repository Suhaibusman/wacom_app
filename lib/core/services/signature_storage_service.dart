import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class SignatureStorageService {
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    final signatureDir = Directory(path.join(directory.path, 'signatures'));
    if (!await signatureDir.exists()) {
      await signatureDir.create(recursive: true);
    }
    return signatureDir.path;
  }

  Future<File> saveSignature(Uint8List bytes) async {
    final signaturePath = await _localPath;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(path.join(signaturePath, 'signature_$timestamp.png'));
    return await file.writeAsBytes(bytes);
  }

  Future<List<File>> getSavedSignatures() async {
    final signaturePath = await _localPath;
    final dir = Directory(signaturePath);
    if (!await dir.exists()) {
      return [];
    }
    final List<FileSystemEntity> entities = await dir.list().toList();
    return entities.whereType<File>().where((file) {
      return file.path.toLowerCase().endsWith('.png');
    }).toList();
  }

  Future<void> deleteSignature(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
