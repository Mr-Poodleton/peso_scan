// ============================================================
// FILE: lib/screens/scanning_screen.dart
// ============================================================
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'package:image/image.dart' as img;
import '../services/onnx_service.dart';
import '../services/tts_service.dart';
import '../main.dart';

class ScanningScreen extends StatefulWidget {
  const ScanningScreen({Key? key}) : super(key: key);

  @override
  State<ScanningScreen> createState() => _ScanningScreenState();
}

class _ScanningScreenState extends State<ScanningScreen> {
  CameraController? _cameraController;
  final OnnxService _onnx = OnnxService();
  final TTSService _tts = TTSService();
  
  String? _lastDetectedLabel;
  double _lastConfidence = 0.0;
  VerificationSummary? _verificationSummary;
  VerificationStatus? _verificationStatus;

  bool _isInitialized = false;
  bool _isScanning = false;
  DateTime _lastScanTime = DateTime.now();
  String _statusMessage = "Initializing...";

  static const Duration _cooldownDuration = Duration(seconds: 3);
  static const int _requiredStableDetections = 2;
  static const double _maxConfidenceVariance = 0.1;
  static const double _maxAreaVariance = 0.08;
  static const double _maxCenterVariance = 0.08;

  String? _candidateLabel;
  double _candidateConfidence = 0;
  double _candidateAreaRatio = 0;
  int _candidateCount = 0;
  double _candidateCenterX = 0.5;
  double _candidateCenterY = 0.5;

  bool _isFlashOn = false;

  void _log(String message) => debugPrint('[SCAN] $message');

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Initialize TTS
      await _tts.initialize();

      // Initialize ONNX models
      _log('Loading ONNX models...');
      await _onnx.initialize();

      // Initialize camera
      if (cameras.isEmpty) {
        setState(() {
          _statusMessage = "No camera available";
        });
        _tts.speak("No camera available");
        return;
      }

      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      // Set exposure and focus
      await _cameraController!.setExposureMode(ExposureMode.auto);
      await _cameraController!.setFocusMode(FocusMode.auto);
      await _cameraController!.setFlashMode(FlashMode.off);

      setState(() {
        _isInitialized = true;
        _statusMessage = "Ready to scan";
      });

      _tts.speak("PesoScan is ready. Please hold a bill in front of the camera.");

      // Start scanning loop
      _startScanningLoop();

    } catch (e) {
      debugPrint('Initialization error: $e');
      setState(() {
        _statusMessage = "Initialization failed: $e";
      });
    }
  }

  void _startScanningLoop() {
    _log('Starting scanning loop...');
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted || !_isInitialized) {
        _log('Timer cancelled');
        timer.cancel();
        return;
      }

      if (_isScanning) {
        _log('Already scanning, skipping');
        return;
      }

      // Check cooldown
      if (DateTime.now().difference(_lastScanTime) < _cooldownDuration) {
        setState(() {
          _statusMessage = "Scanning... (cooldown)";
        });
        return;
      }

      _log('Performing scan...');
      _performScan();
    });
  }

  Future<void> _performScan() async {
    if (_isScanning || !_isInitialized || _cameraController == null) return;

    setState(() {
      _isScanning = true;
      _statusMessage = "Capturing...";
      _verificationSummary = null;
      _verificationStatus = null;
    });

    try {
      final imageFile = await _cameraController!.takePicture();
      final imageBytes = await imageFile.readAsBytes();

      setState(() {
        _statusMessage = "Detecting...";
      });

      var decoded = img.decodeImage(imageBytes);
      if (decoded == null) {
        setState(() {
          _statusMessage = "Failed to decode image";
        });
        return;
      }

      _log('Camera image: ${decoded.width}x${decoded.height}, channels: ${decoded.numChannels}');
      
      // Fix orientation - camera images might be rotated
      if (decoded.width > decoded.height) {
        _log('Rotating landscape image to portrait');
        decoded = img.copyRotate(decoded, angle: 90);
        _log('After rotation: ${decoded.width}x${decoded.height}');
      }

      final detection = await _onnx.detect(decoded);

      if (detection == null) {
        setState(() {
          _statusMessage = "No detection";
          _lastDetectedLabel = null;
          _lastConfidence = 0;
        });
        _resetDetectionCandidate();
        return;
      }

      setState(() {
        _lastDetectedLabel = detection.label;
        _lastConfidence = detection.confidence;
        _verificationSummary = null;
        _verificationStatus = null;
      });

      final friendlyLabel = detection.label.replaceAll('_', ' ');

      if (!_registerDetectionCandidate(detection)) {
        setState(() {
          _statusMessage = "Confirming detection...";
        });
        return;
      }

      _lastScanTime = DateTime.now();

      if (_onnx.isCoinLabel(detection.label)) {
        setState(() {
          _statusMessage = "$friendlyLabel (Coin)";
        });
        await _tts.speak("$friendlyLabel coin detected.");
        await Future.delayed(const Duration(seconds: 2));
        return;
      }

      setState(() {
        _statusMessage = "Verifying...";
      });

      final isPolymer = _onnx.isPolymerLabel(detection.label);
      final cropped = _onnx.cropToBoundingBox(
        decoded,
        detection.boundingBox,
      );

      final verification = await _onnx.verify(
        cropped ?? decoded,
        isPolymer,
      );

      _verificationSummary = verification;
      _verificationStatus = verification.status;

      final featureWord = verification.featureCount == 1 ? 'feature' : 'features';
      final featuresText =
          "${verification.featureCount} security $featureWord detected";

      switch (verification.status) {
        case VerificationStatus.genuine:
          _tts.speak(
            "Genuine $friendlyLabel detected. $featuresText.",
          );
          break;
        case VerificationStatus.uncertain:
          _tts.speak(
            "Warning: Uncertain result for $friendlyLabel. $featuresText.",
          );
          break;
        case VerificationStatus.counterfeit:
          _tts.speak(
            "Alert! Counterfeit $friendlyLabel detected. No security features found.",
          );
          break;
      }

      setState(() {
        _statusMessage = "$friendlyLabel (${_verificationSummaryLabel()})";
      });

      _log('Bill verified: ${verification.status.name}');

      await Future.delayed(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Scan error: $e');
      setState(() {
        _statusMessage = "Camera error - retrying...";
      });
    } finally {
      setState(() {
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _cameraController == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_statusMessage),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('PesoScan'),
        backgroundColor: Colors.black87,
      ),
      body: Stack(
        children: [
          // Camera preview
          CameraPreview(_cameraController!),

          // Flash toggle button
          Positioned(
            top: 20,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggleFlash,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isFlashOn ? Icons.flash_on : Icons.flash_off,
                    color: _isFlashOn ? Colors.yellow : Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),

          // Status overlay
          Positioned(
            top: 20,
            left: 20,
            right: 80,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Detection label
          if (_lastDetectedLabel != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getResultColor().withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastDetectedLabel!.replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Confidence: ${(_lastConfidence * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    if (_verificationStatus != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Status: ${_verificationSummaryLabel()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _getResultColor() {
    switch (_verificationStatus) {
      case VerificationStatus.genuine:
        return Colors.green;
      case VerificationStatus.counterfeit:
        return Colors.red;
      case VerificationStatus.uncertain:
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  String _verificationSummaryLabel() {
    if (_verificationSummary == null) {
      return _verificationStatus?.name.toUpperCase() ?? 'PENDING';
    }

    final summary = _verificationSummary!;
    final statusText = summary.status.name.toUpperCase();
    final featureWord = summary.featureCount == 1 ? 'feature' : 'features';
    return '$statusText (${summary.featureCount} $featureWord)';
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _onnx.dispose();
    _tts.stop();
    super.dispose();
  }

  bool _registerDetectionCandidate(DetectionOutput detection) {
    final sameLabel = detection.label == _candidateLabel;
    final closeConfidence =
        (_candidateConfidence - detection.confidence).abs() <=
            _maxConfidenceVariance;
    final closeArea =
        (_candidateAreaRatio - detection.areaRatio).abs() <= _maxAreaVariance;
    final closeCenter =
        (_candidateCenterX - detection.centerX).abs() <= _maxCenterVariance &&
        (_candidateCenterY - detection.centerY).abs() <= _maxCenterVariance;

    if (sameLabel && closeConfidence && closeArea && closeCenter) {
      _candidateCount += 1;
    } else {
      _candidateLabel = detection.label;
      _candidateConfidence = detection.confidence;
      _candidateAreaRatio = detection.areaRatio;
      _candidateCenterX = detection.centerX;
      _candidateCenterY = detection.centerY;
      _candidateCount = 1;
    }

    final isStable = _candidateCount >= _requiredStableDetections;
    if (isStable) {
      _resetDetectionCandidate();
    }

    return isStable;
  }

  void _resetDetectionCandidate() {
    _candidateLabel = null;
    _candidateConfidence = 0;
    _candidateAreaRatio = 0;
    _candidateCenterX = 0.5;
    _candidateCenterY = 0.5;
    _candidateCount = 0;
  }

  Future<void> _toggleFlash() async {
    if (_cameraController == null || !_isInitialized) return;
    
    try {
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
      
      await _cameraController!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
      
      _log('Flash ${_isFlashOn ? "enabled" : "disabled"}');
    } catch (e) {
      _log('Error toggling flash: $e');
      setState(() {
        _isFlashOn = !_isFlashOn; // Revert on error
      });
    }
  }
}