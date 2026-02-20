import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wacom_app/core/providers.dart';


class WacomConnectButton extends ConsumerWidget {
  const WacomConnectButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(wacomConnectionProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: IconButton(
        icon: Icon(
          connectionState.isConnected ? Icons.usb : Icons.usb_off,
          color: connectionState.isConnected
              ? Colors.greenAccent
              : Colors.white,
        ),
        tooltip: connectionState.isConnected
            ? "Wacom Connected"
            : "Connect Wacom",
        onPressed: () {
          if (connectionState.isConnected) {
            ref.read(wacomConnectionProvider.notifier).disconnect();
          } else {
            ref.read(wacomConnectionProvider.notifier).connect();
          }
        },
      ),
    );
  }
}
