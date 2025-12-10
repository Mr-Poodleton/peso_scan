import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// Provides high-level helpers for running ONNX YOLO models in Flutter.
class OnnxService {
  OnnxService();

  static const _detectorModelAsset = 'assets/models/detector.onnx';
  static const _verifierOldModelAsset = 'assets/models/verifier_old.onnx';
  static const _verifierPolymerModelAsset = 'assets/models/verifier_polymer.onnx';

  static const _detectorLabelsAsset = 'assets/labels/labels_detector.txt';
  static const _verifierOldLabelsAsset = 'assets/labels/labels_old.txt';
  static const _verifierPolymerLabelsAsset = 'assets/labels/labels_polymer.txt';

  // Detection thresholds - ONNX outputs are already sigmoid-activated (0-1 range)
  static const _detectionConfidenceThreshold = 0.5;
  static const _detectionIouThreshold = 0.45;
  static const _minDetectionConfidence = 0.6;
  static const _minDetectionAreaRatio = 0.05;
  static const _maxDetectionAreaRatio = 0.85;
  static const _minDetectionMarginRatio = 0.0;

  // Verification thresholds (feature detection)
  static const _verificationConfidenceThreshold = 0.5;
  static const _verificationIouThreshold = 0.4;

  static const _inputSize = 640;
  static const _maxDetections = 300;

  static const _minFeaturesGenuineOld = 3;
  static const _minFeaturesGenuinePolymer = 4;
  static const _minFeaturesUncertain = 1;

  final Map<String, List<String>> _labelCache = {};

  OrtSession? _detectorSession;
  OrtSession? _verifierOldSession;
  OrtSession? _verifierPolymerSession;

  Future<void>? _initialization;

  bool get isInitialized =>
      _detectorSession != null &&
      _verifierOldSession != null &&
      _verifierPolymerSession != null;

  Future<void> initialize() {
    _initialization ??= _loadAllModels();
    return _initialization!;
  }

  Future<DetectionOutput?> detect(img.Image image) async {
    try {
      await initialize();
      if (_detectorSession == null) {
        print('ONNX: Detector session is null');
        return null;
      }

      final labels = await _loadLabels(_detectorLabelsAsset);
      print('ONNX: Loaded ${labels.length} labels');
      
      print('ONNX: Input image size: ${image.width}x${image.height}, channels: ${image.numChannels}');
      
      final prepared = _preprocess(image);
      if (prepared == null) {
        print('ONNX: Preprocessing failed');
        return null;
      }

      print('ONNX: Preprocessed image to ${prepared.inputWidth}x${prepared.inputHeight}');
      print('ONNX: Original size: ${prepared.originalWidth}x${prepared.originalHeight}, scale: ${prepared.scale.toStringAsFixed(3)}, pad: (${prepared.padX}, ${prepared.padY})');

      final inputOrt = OrtValueTensor.createTensorWithDataList(
        prepared.tensor,
        [1, 3, prepared.inputHeight, prepared.inputWidth],
      );

      print('ONNX: Running detector inference...');
      final runOptions = OrtRunOptions();
      final outputs = _detectorSession!.run(runOptions, {'images': inputOrt});
      runOptions.release();
      print('ONNX: Inference complete, got ${outputs.length} outputs');
      
      final outputTensor = outputs[0];
      if (outputTensor == null) {
        print('ONNX: Output tensor is null');
        inputOrt.release();
        outputs.forEach((element) => element?.release());
        return null;
      }

      final detections = _parseYoloOutputs(
        outputTensor,
        labels,
        confidenceThreshold: _detectionConfidenceThreshold,
        inputWidth: prepared.inputWidth,
        inputHeight: prepared.inputHeight,
      );

      print('ONNX: Found ${detections.length} detections before NMS');
      
      // Log top 5 detections to see what else the model is seeing
      final topDetections = [...detections]..sort((a, b) => b.confidence.compareTo(a.confidence));
      for (int i = 0; i < math.min(5, topDetections.length); i++) {
        final d = topDetections[i];
        print('ONNX:   #${i+1}: Class ${d.classIndex} = ${d.label} (${(d.confidence * 100).toStringAsFixed(1)}%)');
      }

      inputOrt.release();
      outputs.forEach((element) => element?.release());

      final filtered = _applyNms(detections, _detectionIouThreshold);
      print('ONNX: Found ${filtered.length} detections after NMS');
      if (filtered.isEmpty) return null;

      final best = filtered.reduce(
        (a, b) => a.confidence >= b.confidence ? a : b,
      );
      
      print('ONNX: After NMS, selected: Class ${best.classIndex} = ${best.label} (${(best.confidence * 100).toStringAsFixed(1)}%)');

      final boundingBox = _denormalizeBox(best.box, prepared);
      final areaRatio = _computeAreaRatio(
        boundingBox,
        prepared.originalWidth,
        prepared.originalHeight,
      );

      print('ONNX: Best detection: ${best.label}, conf: ${best.confidence.toStringAsFixed(3)}, area: ${areaRatio.toStringAsFixed(3)}');

      if (best.confidence < _minDetectionConfidence) {
        print('ONNX: Rejected - confidence too low (${best.confidence} < $_minDetectionConfidence)');
        return null;
      }
      
      if (areaRatio < _minDetectionAreaRatio) {
        print('ONNX: Rejected - area too small ($areaRatio < $_minDetectionAreaRatio)');
        return null;
      }
      
      if (areaRatio > _maxDetectionAreaRatio) {
        print('ONNX: Rejected - area too large ($areaRatio > $_maxDetectionAreaRatio)');
        return null;
      }
      
      if (!_isWithinMargins(boundingBox, prepared.originalWidth, prepared.originalHeight)) {
        print('ONNX: Rejected - not within margins');
        return null;
      }

      final center = _normalizedCenter(
        boundingBox,
        prepared.originalWidth,
        prepared.originalHeight,
      );

      print('ONNX: Detection accepted!');
      return DetectionOutput(
        label: best.label,
        confidence: best.confidence,
        boundingBox: boundingBox,
        areaRatio: areaRatio,
        centerX: center.$1,
        centerY: center.$2,
      );
    } catch (e, stack) {
      print('ONNX: Error in detect: $e');
      print('ONNX: Stack trace: $stack');
      return null;
    }
  }

  Future<VerificationSummary> verify(
    img.Image input,
    bool isPolymer,
  ) async {
    await initialize();

    final session = isPolymer ? _verifierPolymerSession : _verifierOldSession;
    if (session == null) {
      throw StateError('Verifier model not loaded.');
    }

    final labels = await _loadLabels(
      isPolymer ? _verifierPolymerLabelsAsset : _verifierOldLabelsAsset,
    );

    final prepared = _preprocess(input);
    if (prepared == null) {
      return VerificationSummary.empty(
        isPolymer: isPolymer,
      );
    }

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      prepared.tensor,
      [1, 3, prepared.inputHeight, prepared.inputWidth],
    );

    final runOptions = OrtRunOptions();
    final outputs = session.run(runOptions, {'images': inputOrt});
    runOptions.release();
    final outputTensor = outputs[0];

    if (outputTensor == null) {
      inputOrt.release();
      outputs.forEach((element) => element?.release());
      return VerificationSummary.empty(isPolymer: isPolymer);
    }

    final detections = _parseYoloOutputs(
      outputTensor,
      labels,
      confidenceThreshold: _verificationConfidenceThreshold,
      inputWidth: prepared.inputWidth,
      inputHeight: prepared.inputHeight,
    );

    inputOrt.release();
    outputs.forEach((element) => element?.release());

    final filtered = _applyNms(detections, _verificationIouThreshold);

    final Map<String, double> featureMap = {};
    for (final detection in filtered) {
      featureMap.update(
        detection.label,
        (value) => math.max(value, detection.confidence),
        ifAbsent: () => detection.confidence,
      );
    }

    final featureCount = featureMap.length;
    final avgConfidence = featureCount == 0
        ? 0.0
        : featureMap.values.reduce((a, b) => a + b) / featureCount;
    final sortedFeatures = featureMap.keys.toList()..sort();

    final minFeatures = isPolymer
        ? _minFeaturesGenuinePolymer
        : _minFeaturesGenuineOld;

    final status = featureCount >= minFeatures
        ? VerificationStatus.genuine
        : (featureCount >= _minFeaturesUncertain
            ? VerificationStatus.uncertain
            : VerificationStatus.counterfeit);

    return VerificationSummary(
      status: status,
      featureCount: featureCount,
      avgConfidence: avgConfidence,
      features: sortedFeatures,
      isPolymer: isPolymer,
    );
  }

  img.Image? cropToBoundingBox(
    img.Image source,
    BoundingBoxPixels box, {
    double expandRatio = 0.25,
  }) {
    if (source.width < 2 || source.height < 2) {
      return null;
    }
    final expandW = box.width * expandRatio;
    final expandH = box.height * expandRatio;

    int clampInt(num value, int min, int max) =>
        value.clamp(min, max).toInt();

    final left = clampInt((box.left - expandW).floor(), 0, source.width - 1);
    final top = clampInt((box.top - expandH).floor(), 0, source.height - 1);
    final right = clampInt((box.right + expandW).ceil(), 0, source.width - 1);
    final bottom = clampInt((box.bottom + expandH).ceil(), 0, source.height - 1);

    final cropWidth = math.max(0, right - left);
    final cropHeight = math.max(0, bottom - top);

    if (cropWidth < 2 || cropHeight < 2) {
      return null;
    }

    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  bool isCoinLabel(String? label) {
    final value = label?.toLowerCase() ?? '';
    return value.contains('coin') || value.contains('centavo');
  }

  bool isPolymerLabel(String? label) =>
      label?.toLowerCase().contains('polymer') ?? false;

  void dispose() {
    _detectorSession?.release();
    _verifierOldSession?.release();
    _verifierPolymerSession?.release();
    _detectorSession = null;
    _verifierOldSession = null;
    _verifierPolymerSession = null;
    _initialization = null;
  }

  Future<void> _loadAllModels() async {
    try {
      print('ONNX: Initializing ONNX Runtime...');
      OrtEnv.instance.init();

      print('ONNX: Loading detector model...');
      final detectorBytes = await rootBundle.load(_detectorModelAsset);
      print('ONNX: Detector model size: ${detectorBytes.lengthInBytes} bytes');
      
      print('ONNX: Loading verifier_old model...');
      final verifierOldBytes = await rootBundle.load(_verifierOldModelAsset);
      print('ONNX: Verifier_old model size: ${verifierOldBytes.lengthInBytes} bytes');
      
      print('ONNX: Loading verifier_polymer model...');
      final verifierPolymerBytes = await rootBundle.load(_verifierPolymerModelAsset);
      print('ONNX: Verifier_polymer model size: ${verifierPolymerBytes.lengthInBytes} bytes');

      final sessionOptions = OrtSessionOptions();

      print('ONNX: Creating detector session...');
      _detectorSession = OrtSession.fromBuffer(
        detectorBytes.buffer.asUint8List(),
        sessionOptions,
      );
      
      print('ONNX: Creating verifier_old session...');
      _verifierOldSession = OrtSession.fromBuffer(
        verifierOldBytes.buffer.asUint8List(),
        sessionOptions,
      );
      
      print('ONNX: Creating verifier_polymer session...');
      _verifierPolymerSession = OrtSession.fromBuffer(
        verifierPolymerBytes.buffer.asUint8List(),
        sessionOptions,
      );

      sessionOptions.release();
      print('ONNX: All models loaded successfully!');
    } catch (e, stack) {
      print('ONNX: Error loading models: $e');
      print('ONNX: Stack trace: $stack');
      rethrow;
    }
  }

  Future<List<String>> _loadLabels(String assetPath) async {
    if (_labelCache.containsKey(assetPath)) {
      return _labelCache[assetPath]!;
    }

    final raw = await rootBundle.loadString(assetPath);
    final labels = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    _labelCache[assetPath] = labels;
    return labels;
  }

  _PreparedInput? _preprocess(img.Image source) {
    if (source.width == 0 || source.height == 0) return null;

    final rgb = source.convert(numChannels: 3);
    const targetWidth = _inputSize;
    const targetHeight = _inputSize;

    final scale = math.min(
      targetWidth / rgb.width,
      targetHeight / rgb.height,
    );

    final resizedWidth = (rgb.width * scale).round().clamp(1, targetWidth);
    final resizedHeight = (rgb.height * scale).round().clamp(1, targetHeight);

    final padX = ((targetWidth - resizedWidth) / 2).floor();
    final padY = ((targetHeight - resizedHeight) / 2).floor();

    final canvas = img.Image(
      width: targetWidth,
      height: targetHeight,
      numChannels: 3,
    );
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final resized = img.copyResize(
      rgb,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.linear,
    );

    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    final floats = Float32List(1 * 3 * targetHeight * targetWidth);
    int index = 0;

    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < targetHeight; y++) {
        for (int x = 0; x < targetWidth; x++) {
          final pixel = canvas.getPixel(x, y);
          final value = switch (c) {
            0 => pixel.r,
            1 => pixel.g,
            _ => pixel.b,
          };
          floats[index++] = value / 255.0;
        }
      }
    }

    return _PreparedInput(
      tensor: floats,
      inputWidth: targetWidth,
      inputHeight: targetHeight,
      originalWidth: rgb.width,
      originalHeight: rgb.height,
      padX: padX,
      padY: padY,
      scale: scale == 0 ? 1.0 : scale,
    );
  }

  List<_DetectionCandidate> _parseYoloOutputs(
    OrtValue? ortValue,
    List<String> labels, {
    required double confidenceThreshold,
    required int inputWidth,
    required int inputHeight,
  }) {
    try {
      if (ortValue == null) {
        print('ONNX: ortValue is null');
        return const [];
      }

      print('ONNX: Parsing YOLO outputs...');
      final data = ortValue.value;
      print('ONNX: Output data type: ${data.runtimeType}');

      if (data == null) {
        print('ONNX: Output data is null');
        return const [];
      }

      // Handle different output formats
      List<double> flatData = [];
      List<int> shape = [];

      if (data is List) {
        if (data.isEmpty) {
          print('ONNX: Output data is empty');
          return const [];
        }
        
        // Try to infer shape from nested structure
        if (data[0] is List) {
          final batch = data[0] as List;
          if (batch.isNotEmpty && batch[0] is List) {
            final row = batch[0] as List;
            shape = [data.length, batch.length, row.length];
            print('ONNX: Inferred shape from 3D list: $shape');
            
            // Flatten 3D list
            for (final batchItem in data) {
              for (final rowItem in batchItem as List) {
                for (final val in rowItem as List) {
                  flatData.add((val as num).toDouble());
                }
              }
            }
          } else {
            shape = [data.length, batch.length];
            print('ONNX: Inferred shape from 2D list: $shape');
            
            // Flatten 2D list
            for (final batchItem in data) {
              for (final val in batchItem as List) {
                flatData.add((val as num).toDouble());
              }
            }
          }
        } else {
          shape = [data.length];
          print('ONNX: Inferred shape from 1D list: $shape');
          
          // Already 1D
          for (final val in data) {
            flatData.add((val as num).toDouble());
          }
        }
      }

      if (flatData.isEmpty || shape.isEmpty) {
        print('ONNX: Failed to extract data or shape');
        return const [];
      }

      print('ONNX: Flat data length: ${flatData.length}, Shape: $shape');

      int outputRow;
      int outputColumn;
      final isTransposed = shape.length >= 3 && shape[1] < shape[2];

      if (isTransposed && shape.length >= 3) {
        outputColumn = shape[1];
        outputRow = shape[2];
      } else if (shape.length >= 3) {
        outputRow = shape[1];
        outputColumn = shape[2];
      } else if (shape.length == 2) {
        outputRow = shape[1];
        outputColumn = flatData.length ~/ outputRow;
      } else {
        outputRow = flatData.length ~/ (labels.length + 4);
        outputColumn = labels.length + 4;
      }

      print('ONNX: Output dimensions - rows: $outputRow, cols: $outputColumn, transposed: $isTransposed');

      final floats = Float32List.fromList(flatData);

      if (isTransposed) {
        return _parseYoloV8Transposed(
          floats,
          outputRow,
          outputColumn,
          labels,
          confidenceThreshold,
          inputWidth,
          inputHeight,
        );
      }

      return _parseYoloV8(
        floats,
        outputRow,
        outputColumn,
        labels,
        confidenceThreshold,
        inputWidth,
        inputHeight,
      );
    } catch (e, stack) {
      print('ONNX: Error parsing YOLO outputs: $e');
      print('ONNX: Stack trace: $stack');
      return const [];
    }
  }

  List<_DetectionCandidate> _parseYoloV8(
    Float32List outputs,
    int outputRow,
    int outputColumn,
    List<String> labels,
    double confidenceThreshold,
    int inputWidth,
    int inputHeight,
  ) {
    final candidates = <_DetectionCandidate>[];
    final numClasses = outputColumn - 4;

    for (int i = 0; i < outputRow; i++) {
      final baseIndex = i * outputColumn;
      if (baseIndex + outputColumn > outputs.length) break;

      double bestClassConf = -double.infinity;
      int classIdx = 0;
      for (int j = 0; j < numClasses; j++) {
        final classConf = outputs[baseIndex + 4 + j];
        if (classConf > bestClassConf) {
          bestClassConf = classConf;
          classIdx = j;
        }
      }

      if (bestClassConf < confidenceThreshold) continue;

      final candidate = _createCandidate(
        outputs[baseIndex],
        outputs[baseIndex + 1],
        outputs[baseIndex + 2],
        outputs[baseIndex + 3],
        bestClassConf,
        classIdx,
        labels,
        inputWidth,
        inputHeight,
      );
      candidates.add(candidate);
    }

    return candidates;
  }

  List<_DetectionCandidate> _parseYoloV8Transposed(
    Float32List outputs,
    int outputRow,
    int outputColumn,
    List<String> labels,
    double confidenceThreshold,
    int inputWidth,
    int inputHeight,
  ) {
    final candidates = <_DetectionCandidate>[];

    for (int i = 0; i < outputRow; i++) {
      final xCenter = outputs[i];
      final yCenter = outputs[outputRow + i];
      final width = outputs[2 * outputRow + i];
      final height = outputs[3 * outputRow + i];

      double bestClassConf = -double.infinity;
      int classIdx = 0;
      for (int j = 4; j < outputColumn; j++) {
        final classConf = outputs[j * outputRow + i];
        if (classConf > bestClassConf) {
          bestClassConf = classConf;
          classIdx = j - 4;
        }
      }

      if (bestClassConf < confidenceThreshold) continue;

      final candidate = _createCandidate(
        xCenter,
        yCenter,
        width,
        height,
        bestClassConf,
        classIdx,
        labels,
        inputWidth,
        inputHeight,
      );
      candidates.add(candidate);
    }

    return candidates;
  }

  _DetectionCandidate _createCandidate(
    double xCenter,
    double yCenter,
    double width,
    double height,
    double confidence,
    int classIdx,
    List<String> labels,
    int inputWidth,
    int inputHeight,
  ) {
    final left = (xCenter - width / 2) / inputWidth;
    final top = (yCenter - height / 2) / inputHeight;
    final normalizedWidth = width / inputWidth;
    final normalizedHeight = height / inputHeight;

    final box = _NormalizedBox(
      left: left.clamp(0.0, 1.0),
      top: top.clamp(0.0, 1.0),
      width: normalizedWidth.clamp(0.0, 1.0),
      height: normalizedHeight.clamp(0.0, 1.0),
    );

    final label = classIdx >= 0 && classIdx < labels.length
        ? labels[classIdx]
        : 'class_$classIdx';

    return _DetectionCandidate(
      label: label,
      confidence: confidence,
      classIndex: classIdx,
      box: box,
    );
  }

  List<_DetectionCandidate> _applyNms(
    List<_DetectionCandidate> detections,
    double iouThreshold,
  ) {
    if (detections.length <= 1) return detections;

    final sorted = [...detections]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final result = <_DetectionCandidate>[];
    final suppressed = List<bool>.filled(sorted.length, false);

    for (int i = 0; i < sorted.length; i++) {
      if (suppressed[i]) continue;

      result.add(sorted[i]);
      if (result.length >= _maxDetections) break;

      for (int j = i + 1; j < sorted.length; j++) {
        if (suppressed[j]) continue;
        final iou = _calculateIoU(sorted[i].box, sorted[j].box);
        if (iou > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return result;
  }

  double _calculateIoU(_NormalizedBox a, _NormalizedBox b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);

    final intersection = math.max(0.0, right - left) *
        math.max(0.0, bottom - top);
    if (intersection <= 0) return 0;

    final areaA = a.width * a.height;
    final areaB = b.width * b.height;

    final union = areaA + areaB - intersection;
    if (union <= 0) return 0;

    return intersection / union;
  }

  BoundingBoxPixels _denormalizeBox(
    _NormalizedBox box,
    _PreparedInput prepared,
  ) {
    final inputWidth = prepared.inputWidth.toDouble();
    final inputHeight = prepared.inputHeight.toDouble();

    final modelLeft = box.left * inputWidth;
    final modelTop = box.top * inputHeight;
    final modelRight = box.right * inputWidth;
    final modelBottom = box.bottom * inputHeight;

    final left = (modelLeft - prepared.padX) / prepared.scale;
    final top = (modelTop - prepared.padY) / prepared.scale;
    final right = (modelRight - prepared.padX) / prepared.scale;
    final bottom = (modelBottom - prepared.padY) / prepared.scale;

    final clampedLeft = left.clamp(0.0, prepared.originalWidth.toDouble());
    final clampedTop = top.clamp(0.0, prepared.originalHeight.toDouble());
    final clampedRight = right.clamp(0.0, prepared.originalWidth.toDouble());
    final clampedBottom = bottom.clamp(0.0, prepared.originalHeight.toDouble());

    return BoundingBoxPixels(
      left: math.min(clampedLeft, clampedRight),
      top: math.min(clampedTop, clampedBottom),
      right: math.max(clampedLeft, clampedRight),
      bottom: math.max(clampedTop, clampedBottom),
    );
  }

  double _computeAreaRatio(
    BoundingBoxPixels box,
    int width,
    int height,
  ) {
    if (width == 0 || height == 0) return 0;
    final boxArea = box.width * box.height;
    final imageArea = width * height;
    return boxArea <= 0 ? 0 : (boxArea / imageArea).clamp(0.0, 1.0);
  }

  bool _isWithinMargins(
    BoundingBoxPixels box,
    int width,
    int height,
  ) {
    if (width == 0 || height == 0) return false;
    final marginX = width * _minDetectionMarginRatio;
    final marginY = height * _minDetectionMarginRatio;
    final leftOk = box.left > marginX;
    final rightOk = box.right < (width - marginX);
    final topOk = box.top > marginY;
    final bottomOk = box.bottom < (height - marginY);
    return leftOk && rightOk && topOk && bottomOk;
  }

  (double, double) _normalizedCenter(
    BoundingBoxPixels box,
    int width,
    int height,
  ) {
    if (width == 0 || height == 0) return (0.5, 0.5);
    final cx = ((box.left + box.right) / 2) / width;
    final cy = ((box.top + box.bottom) / 2) / height;
    return (cx.clamp(0.0, 1.0), cy.clamp(0.0, 1.0));
  }
}

class DetectionOutput {
  const DetectionOutput({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    required this.areaRatio,
    required this.centerX,
    required this.centerY,
  });

  final String label;
  final double confidence;
  final BoundingBoxPixels boundingBox;
  final double areaRatio;
  final double centerX;
  final double centerY;
}

class BoundingBoxPixels {
  const BoundingBoxPixels({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => math.max(0, right - left);
  double get height => math.max(0, bottom - top);
}

enum VerificationStatus { genuine, uncertain, counterfeit }

class VerificationSummary {
  const VerificationSummary({
    required this.status,
    required this.featureCount,
    required this.avgConfidence,
    required this.features,
    required this.isPolymer,
  });

  final VerificationStatus status;
  final int featureCount;
  final double avgConfidence;
  final List<String> features;
  final bool isPolymer;

  const VerificationSummary.empty({required this.isPolymer})
      : status = VerificationStatus.counterfeit,
        featureCount = 0,
        avgConfidence = 0,
        features = const [];
}

class _PreparedInput {
  const _PreparedInput({
    required this.tensor,
    required this.inputWidth,
    required this.inputHeight,
    required this.originalWidth,
    required this.originalHeight,
    required this.padX,
    required this.padY,
    required this.scale,
  });

  final Float32List tensor;
  final int inputWidth;
  final int inputHeight;
  final int originalWidth;
  final int originalHeight;
  final int padX;
  final int padY;
  final double scale;
}

class _NormalizedBox {
  const _NormalizedBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
}

class _DetectionCandidate {
  const _DetectionCandidate({
    required this.label,
    required this.confidence,
    required this.classIndex,
    required this.box,
  });

  final String label;
  final double confidence;
  final int classIndex;
  final _NormalizedBox box;
}
