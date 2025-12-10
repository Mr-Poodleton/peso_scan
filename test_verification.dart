import 'dart:io';
import 'dart:math';

// Test the verification logic
void main() {
  stdout.writeln('===== PESO VERIFICATION TEST =====\n');

  // Constants from pytorch_service.dart
  const int minFeaturesGenuineOld = 3;
  const int minFeaturesGenuinePolymer = 4;
  const int minFeaturesUncertain = 1;

  const List<String> verifierOldClasses = [
    'concealed_value',
    'optically_variable_ink',
    'security_thread',
    'see_through_mark',
    'serial_number',
    'value',
    'value_watermark',
    'watermark',
  ];

  const List<String> verifierPolymerClasses = [
    'back_image',
    'denomination_value',
    'embossed_print',
    'flora_window',
    'image',
    'latent_image',
    'metallic',
    'security_thread',
    'transparent_window',
  ];

  // Test OLD BILLS
    stdout.writeln('========== OLD BILLS TEST ==========');
    stdout
      .writeln('Max possible features: ${verifierOldClasses.length}');
    stdout
      .writeln('Minimum for GENUINE: $minFeaturesGenuineOld features');
    stdout.writeln('Minimum for UNCERTAIN: $minFeaturesUncertain features\n');

  testVerification(
    isPolymer: false,
    maxFeatures: verifierOldClasses.length,
    minGenuine: minFeaturesGenuineOld,
    minUncertain: minFeaturesUncertain,
    label: 'OLD BILL',
    iterations: 20,
  );

    stdout.writeln('\n\n========== POLYMER BILLS TEST ==========');
    stdout
      .writeln('Max possible features: ${verifierPolymerClasses.length}');
    stdout.writeln(
      'Minimum for GENUINE: $minFeaturesGenuinePolymer features');
    stdout
      .writeln('Minimum for UNCERTAIN: $minFeaturesUncertain features\n');

  testVerification(
    isPolymer: true,
    maxFeatures: verifierPolymerClasses.length,
    minGenuine: minFeaturesGenuinePolymer,
    minUncertain: minFeaturesUncertain,
    label: 'POLYMER BILL',
    iterations: 20,
  );

  // Statistics
  stdout.writeln('\n\n========== STATISTICS ==========');
  printStatistics(
    isPolymer: false,
    maxFeatures: verifierOldClasses.length,
    minGenuine: minFeaturesGenuineOld,
  );

  printStatistics(
    isPolymer: true,
    maxFeatures: verifierPolymerClasses.length,
    minGenuine: minFeaturesGenuinePolymer,
  );
}

void testVerification({
  required bool isPolymer,
  required int maxFeatures,
  required int minGenuine,
  required int minUncertain,
  required String label,
  required int iterations,
}) {
  final Map<String, int> results = {
    'genuine': 0,
    'uncertain': 0,
    'counterfeit': 0,
  };

  final random = Random();

  for (int i = 0; i < iterations; i++) {
    final featureCount = random.nextInt(maxFeatures + 1);
    String result;

    if (featureCount >= minGenuine) {
      result = 'genuine';
      stdout.writeln(
          '✅ GENUINE ($label #${i + 1}): $featureCount features detected');
    } else if (featureCount >= minUncertain) {
      result = 'uncertain';
      stdout.writeln(
          '⚠️  UNCERTAIN ($label #${i + 1}): $featureCount feature(s) detected');
    } else {
      result = 'counterfeit';
      stdout.writeln('❌ COUNTERFEIT ($label #${i + 1}): No features detected');
    }

    results[result] = results[result]! + 1;
  }

  stdout.writeln('\n--- Results after $iterations tests ---');
  stdout.writeln('  ✅ GENUINE: ${results['genuine']} times');
  stdout.writeln('  ⚠️  UNCERTAIN: ${results['uncertain']} times');
  stdout.writeln('  ❌ COUNTERFEIT: ${results['counterfeit']} times');
}

void printStatistics({
  required bool isPolymer,
  required int maxFeatures,
  required int minGenuine,
}) {
  final type = isPolymer ? 'POLYMER' : 'OLD';
  stdout.writeln('\n$type BILLS:');
  stdout.writeln(
      '  Features 0-${minGenuine - 1}: ❌ COUNTERFEIT ($minGenuine out of ${maxFeatures + 1} outcomes = ${(minGenuine / (maxFeatures + 1) * 100).toStringAsFixed(1)}%)');
  stdout.writeln(
      '  Features $minGenuine-$maxFeatures: ✅ GENUINE (${maxFeatures + 1 - minGenuine} out of ${maxFeatures + 1} outcomes = ${((maxFeatures + 1 - minGenuine) / (maxFeatures + 1) * 100).toStringAsFixed(1)}%)');
}
