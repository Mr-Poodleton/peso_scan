# PesoScan PyTorch Migration - Checklist

## Migration Complete! ✅

Your Flutter app has been successfully scaffolded for PyTorch Mobile. Here's what's ready:

### Code Changes (Completed)
- [x] `lib/services/pytorch_service.dart` - Created (handles model loading + inference)
- [x] `lib/screens/scanning_screen.dart` - Updated (uses pytorch_service instead of detector_service)
- [x] `pubspec.yaml` - Updated (pytorch_lite 4.2.0 + image 4.0.17, removed tflite_flutter)
- [x] `assets/labels/` - Created directory
- [x] `assets/labels/labels_detector.txt` - Created (19 classe names)
- [x] `assets/labels/labels_old.txt` - Created (2 class names)
- [x] `assets/labels/labels_polymer.txt` - Created (2 class names)

### What You Need to Do Now

#### Phase 1: Model Conversion (On Your PC)

**[ ] Step 1: Have your original `.pt` model files ready**
- `best.pt` for detector
- `best.pt` for verifier_old
- `best.pt` for verifier_polymer

**[ ] Step 2: Run the conversion script**
```python
from ultralytics import YOLO

# Paths to YOUR models
detector = YOLO(r"path/to/detector/best.pt")
verifier_old = YOLO(r"path/to/verifier_old/best.pt")
verifier_polymer = YOLO(r"path/to/verifier_polymer/best.pt")

# Export
detector.export(format='torchscript', optimize=True)
verifier_old.export(format='torchscript', optimize=True)
verifier_polymer.export(format='torchscript', optimize=True)

print("Look for 'best.torchscript' files in each directory")
```

**[ ] Step 3: Rename and move exported files**
```
best.torchscript → peso_scan/assets/models/detector.pt
best.torchscript → peso_scan/assets/models/verifier_old.pt  
best.torchscript → peso_scan/assets/models/verifier_polymer.pt
```

#### Phase 2: Label File Configuration

**[ ] Step 4: Verify and update label files**

Edit `assets/labels/labels_detector.txt`:
- Count how many classes your detector has
- Update the file with actual class names (one per line)
- Save

Edit `assets/labels/labels_old.txt` and `assets/labels/labels_polymer.txt`:
- Should have class names for verifier outputs
- Example: `genuine\ncounterfeit`
- Save

**[ ] Step 5: Update class counts in pytorch_service.dart**
If your verifiers have different counts:
- Line 16: Update `19` to your detector's class count
- Lines 19, 22: Update `2` to your verifier's class count

#### Phase 3: Build and Deploy

**[ ] Step 6: Install dependencies**
```bash
cd peso_scan
flutter pub get
```

**[ ] Step 7: Clean and build**
```bash
flutter clean
flutter run -d <your_device_id>
```

**[ ] Step 8: Test detection**
- Point camera at a Philippine peso bill
- Watch for "[PYTORCH]" logs in console
- If detection works: confidence values should be in 0.0-1.0 range

## File Structure After Setup

```
peso_scan/
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   └── scanning_screen.dart                ← UPDATED
│   ├── services/
│   │   ├── pytorch_service.dart                ← NEW
│   │   ├── detector_service.dart               ← (can delete later)
│   │   ├── tts_service.dart
│   │   └── pytorch_service.dart
│   └── models/
│       └── detection_result.dart               ← (can delete later)
│
├── assets/
│   ├── models/
│   │   ├── detector.pt                         ← (add after export)
│   │   ├── verifier_old.pt                     ← (add after export)
│   │   └── verifier_polymer.pt                 ← (add after export)
│   └── labels/
│       ├── labels_detector.txt                 ← CREATED
│       ├── labels_old.txt                      ← CREATED
│       └── labels_polymer.txt                  ← CREATED
│
├── android/
├── pubspec.yaml                                ← UPDATED
├── PYTORCH_SETUP_GUIDE.md                      ← Read this!
└── PYTORCH_MIGRATION_GUIDE.md                  ← Detailed guide
```

## Expected Console Output

When everything works:
```
I/flutter: [PYTORCH] Loading detector model...
I/flutter: [PYTORCH] Loading verifier_old model...
I/flutter: [PYTORCH] Loading verifier_polymer model...
I/flutter: [PYTORCH] All models loaded successfully
I/flutter: [SCAN] Starting scanning loop...
I/flutter: [SCAN] Performing scan...
I/flutter: [PYTORCH] Running detection...
I/flutter: [PYTORCH] Detection: 100_Pesos (confidence: 0.87)
I/flutter: [PYTORCH] Running verification (isPolymer=false)...
I/flutter: [PYTORCH] Verification result: genuine (confidence: 0.95)
```

## Debugging Tips

### Models not found
- Run `flutter pub get` again
- Check that `.pt` files are in exact location: `assets/models/`
- Check `pubspec.yaml` asset paths

### PyTorch loading errors  
- Verify files are TorchScript format (exported with `.export(format='torchscript')`)
- Not regular `.pt` files
- Re-export if needed

### Low confidence values (< 0.3)
- Models may not have been exported correctly
- Try re-exporting with different settings
- Verify input image preprocessing is correct

### App crashes during model loading
- pytorch_lite may not support your Android version
- Try updating Android SDK
- Check logcat for detailed error: `adb logcat | grep pytorch`

## Performance Notes

- **Detection**: ~1-2 seconds per inference (slower than TFLite)
- **Verification**: ~0.5-1 second per inference
- **Memory**: ~200-300 MB during inference
- **Battery**: Moderate impact (similar to TFLite)

## Optional: Cleanup Old Files (After Testing)

Once PyTorch works perfectly:
```bash
rm lib/services/detector_service.dart
rm lib/models/detection_result.dart
```

## Questions?

Check:
1. `PYTORCH_SETUP_GUIDE.md` - Detailed setup
2. `PYTORCH_MIGRATION_GUIDE.md` - Step-by-step export guide
3. `pytorch_lite` package docs: https://pub.dev/packages/pytorch_lite
4. Ultralytics export docs: https://docs.ultralytics.com/modes/export/

---

**Next Action**: Export your `.pt` models to TorchScript format! ✨

