import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wacom_app/core/services/file_service.dart';
import 'package:wacom_app/core/services/pdf_service.dart';
import 'package:wacom_app/core/services/recent_files_service.dart';
import 'package:wacom_app/core/services/wacom_service.dart';
import 'package:wacom_app/core/services/signature_storage_service.dart';

final wacomServiceProvider = Provider<WacomService>((ref) => WacomService());
final fileServiceProvider = Provider<FileService>((ref) => FileService());
final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());
final signatureStorageServiceProvider = Provider<SignatureStorageService>(
  (ref) => SignatureStorageService(),
);
final recentFilesServiceProvider = Provider<RecentFilesService>(
  (ref) => RecentFilesService(),
);

final recentFilesProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.watch(recentFilesServiceProvider);
  return service.getRecentFiles();
});

// Wacom Connection State Management
class WacomConnectionState {
  final bool isConnected;
  final String? error;
  final Map<String, dynamic>? capabilities;

  WacomConnectionState({
    this.isConnected = false,
    this.error,
    this.capabilities,
  });
}

class WacomConnectionNotifier extends Notifier<WacomConnectionState> {
  @override
  WacomConnectionState build() {
    return WacomConnectionState();
  }

  Future<void> connect() async {
    final wacomService = ref.read(wacomServiceProvider);
    try {
      state = WacomConnectionState(
        isConnected: false,
        error: null,
      ); // Reset error
      final caps = await wacomService.connect();
      state = WacomConnectionState(isConnected: true, capabilities: caps);
    } catch (e) {
      state = WacomConnectionState(isConnected: false, error: e.toString());
    }
  }

  Future<void> disconnect() async {
    final wacomService = ref.read(wacomServiceProvider);
    try {
      await wacomService.disconnect();
      state = WacomConnectionState(isConnected: false);
    } catch (e) {
      state = WacomConnectionState(isConnected: false, error: e.toString());
    }
  }
}

final wacomConnectionProvider =
    NotifierProvider<WacomConnectionNotifier, WacomConnectionState>(
      WacomConnectionNotifier.new,
    );
