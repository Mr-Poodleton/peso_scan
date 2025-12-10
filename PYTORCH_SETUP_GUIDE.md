# PesoScan - PyTorch Mobile Migration Complete

## What Has Been Done

✅ Created `lib/services/pytorch_service.dart` - Handles TorchScript model loading and inference
✅ Updated `lib/screens/scanning_screen.dart` - Uses PyTorch instead of TFLite
✅ Updated `pubspec.yaml` - Added pytorch_lite dependency, removed tflite_flutter
✅ Created `assets/labels/` directory with class label files

## Next Steps: Preparing Your Models

### Step 1: Export Your Models to TorchScript

You MUST have your original `.pt` files and convert them. Run this Python script on your machine:

```python
from ultralytics import YOLO

# Update these paths to your actual model locations
detector_path = r"path/to/your/detector/best.pt"
verifier_old_path = r"path/to/your/old_verifier/best.pt"
verifier_polymer_path = r"path/to/your/polymer_verifier/best.pt"

print("Loading models...")
detector = YOLO(detector_path)
verifier_old = YOLO(verifier_old_path)
verifier_polymer = YOLO(verifier_polymer_path)

print("Exporting to TorchScript...")
detector.export(format='torchscript', optimize=True)
verifier_old.export(format='torchscript', optimize=True)
verifier_polymer.export(format='torchscript', optimize=True)

print("✓ Export complete!")
print("\nYou will see files like 'best.torchscript' in each model directory")
print("Rename them as follows and move to peso_scan/assets/models/:")
print("  best.torchscript → detector.pt")
print("  best.torchscript → verifier_old.pt")
print("  best.torchscript → verifier_polymer.pt")
```

### Step 2: Copy Models to Flutter Assets

After exporting and renaming, place them in:
```
peso_scan/
├── assets/
│   ├── models/
│   │   ├── detector.pt                      ← TorchScript export
│   │   ├── verifier_old.pt                  ← TorchScript export
│   │   └── verifier_polymer.pt              ← TorchScript export
│   └── labels/
│       ├── labels_detector.txt              ✓ Created (19 class names)
│       ├── labels_old.txt                   ✓ Created (genuine/counterfeit)
│       └── labels_polymer.txt               ✓ Created (genuine/counterfeit)
```

### Step 3: Update Label Files

Edit the label files to match your actual class names:

**`assets/labels/labels_detector.txt`** - One class name per line:
```
10_Pesos_New
5_Coin_Old
5_Coin_New
1_Coin_Old
10_Pesos_Old
1_Coin_New
20_Coin
25_Centavo_New
20_Pesos
100_Pesos
500_Pesos
200_Pesos
Polymer_1000_Pesos
50_Pesos
1000_Pesos
25_Centavo_Old
Polymer_500_Pesos
Polymer_100_Pesos
Polymer_50_Pesos
```

**`assets/labels/labels_old.txt`** and **`assets/labels/labels_polymer.txt`**:
```
genuine
counterfeit
```

### Step 4: Update Class Counts in pytorch_service.dart

If your verifier models have different class counts, update these lines in `lib/services/pytorch_service.dart`:

```dart
// Line 16: Change 19 to your detector's actual number of classes
await PytorchLite.loadObjectDetectionModel(
  "assets/detector.pt", 19, 640, 640, ...);  // ← number of classes

// Lines 19, 22: Change 2 to your verifier's actual number of classes  
await PytorchLite.loadObjectDetectionModel(
  "assets/verifier_old.pt", 2, 640, 640, ...);  // ← number of classes
```

## Build and Test

Once you have the `.pt` files in place:

```bash
cd peso_scan
flutter clean
flutter pub get
flutter run -d <device_id>
```

## Architecture Overview

```
Camera Stream (every 2 seconds)
    ↓
PytorchService.detect()
    ↓
    └→ Returns: { label, confidence, rect }
         ↓
         If confidence > 0.5:
            ├→ Crop image to bounding box
            └→ PytorchService.verify() (route to old/polymer verifier)
                 ↓
                 Show result (Genuine/Counterfeit)
                 Play TTS
```

## Troubleshooting

### "Asset file 'assets/models/detector.pt' doesn't exist"
- Ensure your `.pt` files are in the correct location and named exactly: `detector.pt`, `verifier_old.pt`, `verifier_polymer.pt`
- Run `flutter pub get` after adding files

### "PyTorchLite: Model loading failed"
- Verify the `.pt` files are valid TorchScript exports (not regular `.pt`)
- Check that the number of classes matches your model
- Re-export using `detector.export(format='torchscript', optimize=True)`

### "Label count mismatch"
- Ensure the number of lines in label files matches the number of classes:
  - `labels_detector.txt` should have 19 lines (or your detector's class count)
  - `labels_old.txt` and `labels_polymer.txt` should have 2 lines each (or your verifier's class count)

## Key Differences from TFLite

- **PyTorch Mobile** loads `.pt` TorchScript files (not `.tflite`)
- **Output format** is simpler: dictionary with `label` and `confidence`
- **Slightly slower** than TFLite on mobile, but more Python-friendly if you iterate
- **More experimental** - pytorch_lite package is less stable on some Android versions

## Next: Integrate Verifier Logic

Once detection works, you can add the cropping logic to automatically verify detected bills:

```dart
if (detectionResult != null) {
  // Crop to bounding box
  var cropped = img.copyCrop(
    image,
    x: detectionResult['rect']['x'],
    y: detectionResult['rect']['y'],
    width: detectionResult['rect']['w'],
    height: detectionResult['rect']['h']
  );
  
  // Route to correct verifier
  bool isPolymer = detectionResult['label'].contains('Polymer');
  var isGenuine = await _detector.verify(cropped, isPolymer);
  
  // Show result
  if (isGenuine) {
    _tts.speak("Genuine ${detectionResult['label']} detected!");
  } else {
    _tts.speak("Counterfeit detected!");
  }
}
```

---

**Status**: Ready to export and deploy with PyTorch Mobile. Your TFLite detector_service.dart is still in the codebase but not used. You can delete it once PyTorch works:

```bash
rm lib/services/detector_service.dart
rm lib/models/detection_result.dart
```

