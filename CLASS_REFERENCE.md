# PesoScan - Complete Class Reference

## 🎯 Overview

This document contains all class mappings and configurations for the PesoScan Flutter application.

---

## 🏷️ DETECTOR MODEL - 19 Classes

**Model**: `assets/models/best_detector.pt`  
**Purpose**: Identify Philippine peso denominations and coins  
**Output**: Detection with confidence score and bounding box

### Class List

| Index | Class Name | Type | Notes |
|-------|-----------|------|-------|
| 0 | 1000_Pesos | Bill (Old) | Violet/Purple |
| 1 | 100_Pesos | Bill (Old) | Green |
| 2 | 10_Pesos_New | Bill (Old) | Pink (New Series) |
| 3 | 10_Pesos_Old | Bill (Old) | Red (Old Series) |
| 4 | 1_Coin_New | Coin | New design |
| 5 | 1_Coin_Old | Coin | Old design |
| 6 | 200_Pesos | Bill (Old) | Blue |
| 7 | 20_Coin | Coin | Single coin |
| 8 | 20_Pesos | Bill (Old) | Orange |
| 9 | 25_Centavo_New | Coin | New design |
| 10 | 25_Centavo_Old | Coin | Old design |
| 11 | 500_Pesos | Bill (Old) | Brown |
| 12 | 50_Pesos | Bill (Old) | Yellow |
| 13 | 5_Coin_New | Coin | New design |
| 14 | 5_Coin_Old | Coin | Old design |
| 15 | Polymer_1000_Pesos | Bill (Polymer) | Purple polymer |
| 16 | Polymer_100_Pesos | Bill (Polymer) | Green polymer |
| 17 | Polymer_500_Pesos | Bill (Polymer) | Brown polymer |
| 18 | Polymer_50_Pesos | Bill (Polymer) | Blue polymer |

### Denominations Summary

**Coins** (6 classes): 1, 5, 20, 25¢ (old & new variants)  
**Old Bills** (6 classes): 10, 20, 50, 100, 200, 500, 1000 Pesos  
**Polymer Bills** (4 classes): 50, 100, 500, 1000 Pesos (new generation)

---

## 🔐 OLD BILL VERIFIER - 8 Features

**Model**: `assets/models/best_verifier_old.pt`  
**Purpose**: Detect security features in old Philippine bills  
**Output**: Feature detection with confidence score  
**Used for**: All non-polymer bills (10, 20, 50, 100, 200, 500, 1000 Pesos)

### Feature Classes

| Index | Class Name | Description | Where Found |
|-------|-----------|-------------|------------|
| 0 | concealed_value | Hidden denomination visible at angle | Corner |
| 1 | optically_variable_ink | Color-shifting ink | Design elements |
| 2 | security_thread | Embedded metal thread | Center strip |
| 3 | see_through_mark | Watermark visible when held to light | Multiple spots |
| 4 | serial_number | Unique bill number | Front & back |
| 5 | value | Denomination numbers | Corners & edges |
| 6 | value_watermark | Denomination watermark | Background |
| 7 | watermark | Portrait/design watermark | Background |

### Verification Logic (Old Bills)

```
Genuine:        ≥ 3 features detected
Uncertain:      1-2 features detected
Counterfeit:    0 features detected
```

**Confidence Threshold**: 0.70 (features must be ≥70% confident)

---

## 💎 POLYMER BILL VERIFIER - 9 Features

**Model**: `assets/models/best_verifier_polymer.pt`  
**Purpose**: Detect security features in polymer Philippine bills  
**Output**: Feature detection with confidence score  
**Used for**: Polymer bills (50, 100, 500, 1000 Pesos - new generation)

### Feature Classes

| Index | Class Name | Description | Type |
|-------|-----------|-------------|------|
| 0 | back_image | Back side design | Visual |
| 1 | denomination_value | Denomination numbers | Tactile/Visual |
| 2 | embossed_print | Raised printing | Tactile |
| 3 | flora_window | Clear window with flora design | Transparent |
| 4 | image | Main portrait/image | Visual |
| 5 | latent_image | Image visible at different angles | Optical |
| 6 | metallic | Metallic inks/elements | Visual |
| 7 | security_thread | Embedded security thread | Visual |
| 8 | transparent_window | Clear transparent window | Transparent |

### Verification Logic (Polymer Bills)

```
Genuine:        ≥ 4 features detected
Uncertain:      1-2 features detected
Counterfeit:    0 features detected
```

**Confidence Threshold**: 0.70 (features must be ≥70% confident)

**Note**: Polymer bills require MORE features for genuine classification (4 vs 3) because:
- Fewer but more distinctive security features
- Stronger anti-counterfeit design
- More reliable authentication

---

## 📋 Classification Rules

### Bill Type Detection
```
if "Polymer" in label → Polymer bill → Use Polymer Verifier (9 features)
if "Coin" in label → Coin → Skip verification (no features to count)
else → Old bill → Use Old Bill Verifier (8 features)
```

### Authenticity Classification

**GENUINE** 🟢
```
Old Bill:     3+ security features detected above 0.70 confidence
Polymer Bill: 4+ security features detected above 0.70 confidence
```

**UNCERTAIN** 🟡
```
Any Bill Type: 1-2 security features detected above 0.70 confidence
(Needs manual inspection or better imaging)
```

**COUNTERFEIT** 🔴
```
Any Bill Type: 0 security features detected above 0.70 confidence
(No authentic security features found)
```

**COIN** 🔵
```
Denomination announced only, verification skipped
No security features verification needed
```

---

## 🔄 Detection Flow

```
DETECTOR MODEL (19 classes)
    ↓
Which denomination?
    ├─ Coin? → Announce & Done
    └─ Bill? → Determine type
        ├─ Polymer_* → Use Polymer Verifier
        └─ Regular → Use Old Bill Verifier

VERIFIER MODEL (8 or 9 features)
    ↓
Count features above 0.70 confidence
    ├─ ≥ Min threshold → GENUINE ✅
    ├─ 1-2 features → UNCERTAIN ⚠️
    └─ 0 features → COUNTERFEIT ❌
```

---

## 📊 Statistics

| Metric | Count | Details |
|--------|-------|---------|
| **Total Denominations** | 19 | 6 coins + 6 old bills + 4 polymer bills |
| **Coins** | 6 | 1, 5, 20, 25¢ (each old & new) |
| **Old Bills** | 6 | 10, 20, 50, 100, 200, 500, 1000 Pesos |
| **Polymer Bills** | 4 | 50, 100, 500, 1000 Pesos |
| **Old Features** | 8 | Thread, watermark, ink, serial, etc. |
| **Polymer Features** | 9 | Window, hologram, tactile, transparent, etc. |
| **Feature Detection Min (Old)** | 3 | For genuine classification |
| **Feature Detection Min (Polymer)** | 4 | For genuine classification |
| **Confidence Threshold** | 0.70 | 70% for feature detection |
| **Detection Threshold** | 0.80 | 80% for initial detection |

---

## 🎨 UI Color Codes

| Color | Meaning | Conditions |
|-------|---------|-----------|
| 🟢 Green | GENUINE | Bill detected + features ≥ minimum |
| 🔴 Red | COUNTERFEIT | Bill detected + 0 features |
| 🟡 Orange | UNCERTAIN | Bill detected + 1-2 features |
| 🔵 Blue | COIN | Coin detected (no verification) |

---

## 🔧 Configuration Constants

Located in: `lib/services/pytorch_service.dart`

```dart
// Thresholds
static const double CONFIDENCE_THRESHOLD = 0.70;     // Feature detection
static const double DETECT_THRESHOLD = 0.80;         // Bill detection
static const int MIN_FEATURES_GENUINE_OLD = 3;       // Old bills
static const int MIN_FEATURES_GENUINE_POLYMER = 4;   // Polymer bills
static const int MIN_FEATURES_UNCERTAIN = 1;         // Uncertain threshold

// Timing (in scanning_screen.dart)
static const Duration COOLDOWN_DURATION = Duration(seconds: 3);    // Between scans
static const Duration DETECTION_DURATION = Duration(seconds: 4);   // Detection phase
static const Duration VERIFICATION_DURATION = Duration(seconds: 4); // Verification phase
```

---

## 📁 Asset Files

### Label Files

**`assets/labels/labels_detector.txt`**
```
1000_Pesos
100_Pesos
10_Pesos_New
10_Pesos_Old
1_Coin_New
1_Coin_Old
200_Pesos
20_Coin
20_Pesos
25_Centavo_New
25_Centavo_Old
500_Pesos
50_Pesos
5_Coin_New
5_Coin_Old
Polymer_1000_Pesos
Polymer_100_Pesos
Polymer_500_Pesos
Polymer_50_Pesos
```

**`assets/labels/labels_old.txt`**
```
concealed_value
optically_variable_ink
security_thread
see_through_mark
serial_number
value
value_watermark
watermark
```

**`assets/labels/labels_polymer.txt`**
```
back_image
denomination_value
embossed_print
flora_window
image
latent_image
metallic
security_thread
transparent_window
```

---

## 🚀 Usage Examples

### Example 1: Detecting Old 500 Peso Bill
```
Input: Camera frame with 500 Peso bill
↓
Detector Output: "500_Pesos" (confidence: 0.92)
↓
Determine Bill Type: Not polymer → Use Old Verifier
↓
Verifier Output: 
  - security_thread (0.95)
  - watermark (0.88)
  - serial_number (0.82)
  - value (0.78)
  - (Total: 4 features ≥ 3 minimum)
↓
Result: GENUINE ✅
↓
TTS: "Genuine 500 Pesos detected. Security features verified."
```

### Example 2: Detecting Polymer 100 Peso Bill
```
Input: Camera frame with Polymer 100 Peso bill
↓
Detector Output: "Polymer_100_Pesos" (confidence: 0.88)
↓
Determine Bill Type: Polymer detected → Use Polymer Verifier
↓
Verifier Output:
  - transparent_window (0.96)
  - flora_window (0.91)
  - metallic (0.85)
  - security_thread (0.79)
  - embossed_print (0.72)
  - (Total: 5 features ≥ 4 minimum)
↓
Result: GENUINE ✅
↓
TTS: "Genuine Polymer 100 Pesos detected. Security features verified."
```

### Example 3: Detecting Coin
```
Input: Camera frame with 20 peso coin
↓
Detector Output: "20_Coin" (confidence: 0.84)
↓
Determine Bill Type: Coin detected → Skip verification
↓
Result: COIN (no verification needed) 🔵
↓
TTS: "20 Coin detected."
```

### Example 4: Counterfeit Detection
```
Input: Camera frame with counterfeit bill
↓
Detector Output: "50_Pesos" (confidence: 0.75)
↓
Determine Bill Type: Old bill → Use Old Verifier
↓
Verifier Output: (No features above 0.70 confidence)
  - All detected features < 0.70 threshold
  - (Total: 0 features < 3 minimum)
↓
Result: COUNTERFEIT ❌
↓
TTS: "Alert! Counterfeit 50 Pesos detected."
```

---

## 🎓 Model Architecture Notes

### Detector Model
- **Type**: YOLO v8 (You Only Look Once v8)
- **Input**: Image (variable size, auto-resizes to 640x640)
- **Output**: Bounding box + class ID + confidence
- **Classes**: 19 denominations
- **Purpose**: Real-time detection of bills/coins

### Verifier Models (Old & Polymer)
- **Type**: YOLO v8 (detection mode, acts as classifier)
- **Input**: Cropped bill region (640x640)
- **Output**: Multiple detections of security features
- **Purpose**: Count and verify authenticity markers
- **Strategy**: Each security feature is a separate detection

---

## 📝 API Reference

### PytorchService Methods

```dart
// Initialize models
Future<void> loadModels()

// Detect denomination in image
Future<Map<String, dynamic>?> detect(img.Image image)
// Returns: {label, confidence, classIndex, x, y, w, h}

// Verify security features
Future<bool> verify(img.Image cropped, bool isPolymer)
// Returns: true if genuine, false if counterfeit/uncertain

// Helper methods
bool isCoin(String label)       // Check if coin
bool isPolymer(String label)    // Check if polymer bill

// Cleanup
void dispose()
```

---

## 🔍 Troubleshooting Reference

| Issue | Possible Cause | Solution |
|-------|---|---|
| Always showing "100_Pesos" | Using mock implementation | Real models not exported to TorchScript |
| Always showing "GENUINE" | Using mock verification | Real verifier models not integrated |
| Classes not matching | Outdated label files | Update labels_*.txt files |
| Too many false positives | Confidence threshold too low | Increase `DETECT_THRESHOLD` to 0.85+ |
| Too many missed detections | Confidence threshold too high | Decrease `DETECT_THRESHOLD` to 0.75 |
| Coins marked as bills | Classification error | Check `isCoin()` method logic |

---

**Version**: 1.0  
**Last Updated**: November 27, 2025  
**Status**: Complete Reference
