import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const channel = MethodChannel('wacom_stu_channel');

  String status = "Not Connected";

  Future<void> connect() async {
    final result = await channel.invokeMethod('connect');
    setState(() => status = result);
  }

  Future<void> disconnect() async {
    final result = await channel.invokeMethod('disconnect');
    setState(() => status = result);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(status),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: connect,
                child: const Text("Connect STU-540"),
              ),
              ElevatedButton(
                onPressed: disconnect,
                child: const Text("Disconnect"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
