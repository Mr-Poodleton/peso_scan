# PyTorch Mobile Migration Guide for PesoScan

## Step 1: Export Models to TorchScript (Python)

Run this Python script on your machine with your original `.pt` model files:

```python
from ultralytics import YOLO
import os

# Paths to your original models
detector_path = r"path/to/detector/best.pt"
verifier_old_path = r"path/to/verifier_old/best.pt"
verifier_polymer_path = r"path/to/verifier_polymer/best.pt"

# Load models
print("Loading detector...")
detector = YOLO(detector_path)

print("Loading verifier_old...")
verifier_old = YOLO(verifier_old_path)

print("Loading verifier_polymer...")
verifier_polymer = YOLO(verifier_polymer_path)

# Export to TorchScript
print("Exporting detector to TorchScript...")
detector.export(format='torchscript', optimize=True)

print("Exporting verifier_old to TorchScript...")
verifier_old.export(format='torchscript', optimize=True)

print("Exporting verifier_polymer to TorchScript...")
verifier_polymer.export(format='torchscript', optimize=True)

print("✓ Export complete!")
print("\nNow rename the exported files:")
print("  best.torchscript → detector.pt")
print("  best.torchscript → verifier_old.pt")
print("  best.torchscript → verifier_polymer.pt")
print("\nMove them to: assets/models/")
```

## Step 2: Extract Class Labels from Models

The label files tell PyTorch which class names correspond to each output index.

For each model, you need to create a `.txt` file with class names (one per line):

- `assets/labels/labels_detector.txt` - List of all bill/coin classes your detector recognizes
- `assets/labels/labels_old.txt` - Security features for old bills (usually something like "genuine\ncounterfeit")
- `assets/labels/labels_polymer.txt` - Security features for polymer bills

Example format for `labels_detector.txt`:
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

## Step 3: Verify TorchScript Export

You can verify the exported model works in Python:

```python
import torch
from ultralytics import YOLO

# Load the TorchScript model
model = torch.jit.load("path/to/detector.pt")
print(model)  # Should show the model architecture

# Or test with ultralytics:
detector = YOLO("detector.pt")
results = detector("test_image.jpg")
print(results)
```

## Step 4: Test in Flutter

Once you have:
- `assets/models/detector.pt`
- `assets/models/verifier_old.pt`
- `assets/models/verifier_polymer.pt`
- `assets/labels/labels_detector.txt`
- `assets/labels/labels_old.txt`
- `assets/labels/labels_polymer.txt`

Run:
```
flutter pub get
flutter run
```

## Troubleshooting

### Models not found
Make sure the asset paths in `pubspec.yaml` match exactly.

### PyTorch loading errors
Check that the `.pt` files are valid TorchScript exports. Re-export if needed.

### Label mismatch
Ensure the number of lines in label files matches the number of output classes in each model.

