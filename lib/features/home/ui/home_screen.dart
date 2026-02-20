import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:path/path.dart' as path;
import '../../../core/providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../pdf_viewer/ui/pdf_viewer_screen.dart';
import 'widgets/wacom_connect_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Invalidate to force refresh
    Future.microtask(() => ref.invalidate(recentFilesProvider));
  }

  void _openPdf() async {
    final fileService = ref.read(fileServiceProvider);
    final file = await fileService.pickPdfFile();
    if (file != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => PdfViewerScreen(file: file)),
      );
    }
  }

  void _openRecentFile(String path) {
    final file = File(path);
    if (file.existsSync()) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => PdfViewerScreen(file: file)),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("File not found")));
      ref.read(recentFilesServiceProvider).removeRecentFile(path);
      ref.invalidate(recentFilesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentFilesAsync = ref.watch(recentFilesProvider);

    // Listen for connection errors
    ref.listen(wacomConnectionProvider, (previous, next) {
      if (next.error != null && next.error!.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Wacom Error: ${next.error}")));
      } else if (next.isConnected &&
          (previous == null || !previous.isConnected)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Wacom Tablet Connected")));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text("Wacom PDF Signer"),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: const [WacomConnectButton()],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Welcome",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Sign PDFs professionally with your Wacom tablet.",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _openPdf,
                      icon: const Icon(Icons.file_open),
                      label: const Text("Open PDF Document"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    "Recent Signed Documents",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          recentFilesAsync.when(
            data: (files) {
              if (files.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text("No recent documents"),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final filePath = files[index];
                  final fileName = path.basename(filePath);
                  return ListTile(
                    leading: const Icon(
                      Icons.picture_as_pdf,
                      color: Colors.red,
                    ),
                    title: Text(fileName),
                    subtitle: Text(filePath),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ref
                            .read(recentFilesServiceProvider)
                            .removeRecentFile(filePath);
                        ref.invalidate(recentFilesProvider);
                      },
                    ),
                    onTap: () => _openRecentFile(filePath),
                  );
                }, childCount: files.length),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, stack) =>
                SliverToBoxAdapter(child: Center(child: Text("Error: $err"))),
          ),
        ],
      ),
    );
  }
}
