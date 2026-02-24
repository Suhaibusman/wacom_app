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
    Future.microtask(() {
      ref.invalidate(recentFilesProvider);

      // Auto-connect to Wacom on startup
      final wacomState = ref.read(wacomConnectionProvider);
      if (!wacomState.isConnected) {
        ref.read(wacomConnectionProvider.notifier).connect();
      }
    });
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

    ref.listen(wacomConnectionProvider, (previous, next) {
      if (next.error != null && next.error!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      } else if (next.isConnected &&
          (previous == null || !previous.isConnected)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Tablet Connected Successfully"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.success,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Sindh High Court",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: WacomConnectButton(),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Sidebar/Action Area
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.surfaceHover,
              padding: const EdgeInsets.all(48.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Image.asset(
                      'assets/images/hc_logo.png',
                      height: 64,
                      width: 64,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    "Digital Document\nSigning System.",
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                      letterSpacing: -1,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Securely authorize and sign digital PDFs for the Sindh High Court.",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Hero Action Button
                  SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _openPdf,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_box_rounded, size: 28),
                          SizedBox(width: 12),
                          Text(
                            "Open New Document",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Content Area (Recent Files)
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 48.0,
                vertical: 32.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Recent Documents",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Expanded(
                    child: recentFilesAsync.when(
                      data: (files) {
                        if (files.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.folder_open,
                                  size: 64,
                                  color: AppColors.border,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "No recent documents yet",
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: files.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final filePath = files[index];
                            final fileName = path.basename(filePath);
                            return Card(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                hoverColor: AppColors.surfaceHover,
                                onTap: () => _openRecentFile(filePath),
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.picture_as_pdf,
                                          color: Colors.redAccent,
                                          size: 32,
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              fileName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              filePath,
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: AppColors.textSecondary,
                                        ),
                                        hoverColor: AppColors.error.withValues(
                                          alpha: 0.1,
                                        ),
                                        onPressed: () async {
                                          await ref
                                              .read(recentFilesServiceProvider)
                                              .removeRecentFile(filePath);
                                          ref.invalidate(recentFilesProvider);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text("Error: $err")),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
