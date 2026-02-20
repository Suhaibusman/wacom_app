import 'dart:async';
import 'package:flutter/services.dart';

class WacomService {
  static const methodChannel = MethodChannel('wacom_stu_channel');
  static const eventChannel = EventChannel('wacom_stu_events');

  StreamSubscription? _penSubscription;

  Future<Map<String, dynamic>> connect() async {
    try {
      final result = await methodChannel.invokeMethod('connect');
      if (result is Map) {
        return {
          'status': result['status'],
          'maxX': (result['maxX'] as int).toDouble(),
          'maxY': (result['maxY'] as int).toDouble(),
          'screenWidth': result.containsKey('screenWidth')
              ? (result['screenWidth'] as int).toDouble()
              : null,
          'screenHeight': result.containsKey('screenHeight')
              ? (result['screenHeight'] as int).toDouble()
              : null,
        };
      } else {
        throw Exception('Unexpected result format: $result');
      }
    } on PlatformException catch (e) {
      throw Exception("Connection Error: ${e.message}");
    }
  }

  Future<String> disconnect() async {
    await _penSubscription?.cancel();
    _penSubscription = null;
    try {
      final result = await methodChannel.invokeMethod('disconnect');
      return result.toString();
    } on PlatformException catch (e) {
      throw Exception("Disconnect Error: ${e.message}");
    }
  }

  Future<void> clearScreen() async {
    try {
      await methodChannel.invokeMethod('clearScreen');
    } on PlatformException catch (e) {
      print("ClearScreen Error: ${e.message}");
    }
  }

  Stream<Map<String, dynamic>> get penEvents {
    return eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map) {
        return {
          'x': (event['x'] as int).toDouble(),
          'y': (event['y'] as int).toDouble(),
          'pressure': (event['pressure'] as int).toDouble(),
          'sw': (event['sw'] as int),
        };
      }
      throw Exception("Invalid event format");
    });
  }

  Future<void> setSignatureScreen(Uint8List rgbBytes, int mode) async {
    try {
      await methodChannel.invokeMethod('setSignatureScreen', {
        'data': rgbBytes,
        'mode': mode,
      });
    } catch (e) {
      print("Error setting signature screen: $e");
    }
  }
}
