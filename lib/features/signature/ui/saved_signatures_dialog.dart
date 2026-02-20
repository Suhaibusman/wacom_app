import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wacom_app/core/providers.dart';

class SavedSignaturesDialog extends ConsumerStatefulWidget {
  const SavedSignaturesDialog({super.key});

  @override
  ConsumerState<SavedSignaturesDialog> createState() =>
      _SavedSignaturesDialogState();
}

class _SavedSignaturesDialogState extends ConsumerState<SavedSignaturesDialog> {
  List<File> _signatures = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignatures();
  }

  Future<void> _loadSignatures() async {
    final storageService = ref.read(signatureStorageServiceProvider);
    final files = await storageService.getSavedSignatures();
    if (mounted) {
      setState(() {
        _signatures = files;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSignature(File file) async {
    final storageService = ref.read(signatureStorageServiceProvider);
    await storageService.deleteSignature(file);
    _loadSignatures();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Select Saved Signature"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _signatures.isEmpty
            ? const Center(child: Text("No saved signatures found."))
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _signatures.length,
                itemBuilder: (context, index) {
                  final file = _signatures[index];
                  return Stack(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final bytes = await file.readAsBytes();
                          if (mounted) {
                            Navigator.of(context).pop(bytes);
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            color: Colors
                                .white, // Ensure visibility against dialog
                          ),
                          child: Image.file(file, fit: BoxFit.contain),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteSignature(file),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
      ],
    );
  }
}
