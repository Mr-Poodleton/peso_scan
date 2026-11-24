# PesoScan

Mobile Flutter app that identifies Philippine peso coins and banknotes through
the device camera and provides spoken detection and verification feedback.

> TODO: Add a screenshot or demo GIF at `docs/demo.gif`.

## Features

- Captures frames from the device camera.
- Runs an ONNX detector on each processed image.
- Recognizes the denominations and coin categories listed in
  `assets/labels/labels_detector.txt`.
- Runs separate feature checks for old-series and polymer banknotes.
- Announces readiness, detections, and verification results with text-to-speech.

## How it works

1. `lib/main.dart` initializes the available camera and opens the scanning screen.
2. `ScanningScreen` decodes camera images and sends them to `OnnxService`.
3. `OnnxService` loads the detector and verifier ONNX assets, preprocesses the
   image, runs inference, applies confidence and non-maximum-suppression
   filtering, and selects the best detection.
4. The detected label is classified as a coin or banknote. Banknotes are
   checked with the old-series or polymer verifier, then the result is spoken
   through `TTSService`.

The repository includes three ONNX model assets:

- `assets/models/detector.onnx`
- `assets/models/verifier_old.onnx`
- `assets/models/verifier_polymer.onnx`

Detected classes include Philippine denominations from 1,000 pesos down to
coins and centavos, including old, new, and polymer labels. The model training
source and dataset size are not documented in this repository.

## Tech stack

- Dart and Flutter
- ONNX Runtime for Flutter
- Camera plugin
- `image` package for image processing
- Flutter TTS
- Permission Handler

## Getting started

### Prerequisites

- Flutter SDK with Dart 3
- A supported Android, iOS, desktop, or web development target
- A camera-enabled device for live scanning

### Run locally

```bash
flutter pub get
flutter run
```

The model and label assets are declared in `pubspec.yaml` and are bundled
during the Flutter build.

## Results

TODO: Add measured evaluation results such as detection accuracy, verification
accuracy, latency, or supported-device performance.

## My role

Project owner and developer. TODO: Confirm whether any other contributors
participated before describing this as a solo project.
