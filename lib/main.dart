// ============================================================
// FILE: lib/main.dart
// ============================================================
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'screens/scanning_screen.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error initializing cameras: $e');
  }
  
  runApp(const PesoScanApp());
}

class PesoScanApp extends StatelessWidget {
  const PesoScanApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PesoScan',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
      ),
      home: const ScanningScreen(),
    );
  }
}