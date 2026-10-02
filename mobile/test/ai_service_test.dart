import 'package:flutter_test/flutter_test.dart';
import 'package:kitakitar_mobile/models/ai_scan_model.dart';
import 'package:kitakitar_mobile/models/material_types.dart';
import 'package:kitakitar_mobile/services/ai_service.dart';

void main() {
  group('canonicalMaterialType', () {
    test('canonical slugs map to themselves', () {
      for (final m in kMaterialTypes) {
        expect(canonicalMaterialType(m['type']!), m['type']);
      }
    });

    test('old AI vocabulary maps to center slugs', () {
      expect(canonicalMaterialType('cardboard'), 'paper');
      expect(canonicalMaterialType('hazardous'), 'hazardous_waste');
      expect(canonicalMaterialType('Aluminium'), 'aluminum');
      expect(canonicalMaterialType('used oil'), 'used_oil');
      expect(canonicalMaterialType('E-Waste'), 'electronics');
    });

    test('names no center accepts map to null', () {
      expect(canonicalMaterialType('other'), isNull);
      expect(canonicalMaterialType(''), isNull);
      expect(canonicalMaterialType('textiles'), isNull);
    });
  });

  group('AIService.parseResponse', () {
    test('normalizes types, merges duplicates, drops unmatched', () {
      final result = AIService.parseResponse('''
{
  "detectedMaterials": [
    {"type": "cardboard", "estimatedWeight": 0.5},
    {"type": "paper", "estimatedWeight": 0.25},
    {"type": "hazardous", "estimatedWeight": 1},
    {"type": "other", "estimatedWeight": 2},
    {"type": "glass", "estimatedWeight": 0}
  ],
  "preparationTip": "  Flatten boxes.  "
}''');

      expect(result.materials.map((m) => m.type), ['paper', 'hazardous_waste']);
      expect(result.materials[0].estimatedWeight, closeTo(0.75, 1e-9));
      expect(result.materials[1].estimatedWeight, 1.0);
      expect(result.preparationTip, 'Flatten boxes.');
    });

    test('accepts fenced JSON and string weights', () {
      final result = AIService.parseResponse(
        '```json\n{"detectedMaterials": [{"type": "Plastic", "estimatedWeight": "0.3"}]}\n```',
      );
      expect(result.materials.single.type, 'plastic');
      expect(result.materials.single.estimatedWeight, 0.3);
      expect(result.preparationTip, isNull);
    });

    test('nothing recognizable is an empty result, not an error', () {
      final result = AIService.parseResponse(
        '{"detectedMaterials": [], "preparationTip": "Sort by material type before drop-off."}',
      );
      expect(result.materials, isEmpty);
    });

    test('unreadable output throws instead of returning a fake result', () {
      expect(
        () => AIService.parseResponse('{"detectedMaterials": [{"type": "pla'),
        throwsA(isA<AIScanException>()),
      );
      expect(
        () => AIService.parseResponse('Sorry, I cannot help with that.'),
        throwsA(isA<AIScanException>()),
      );
    });
  });

  test('history entries saved with old names are normalized on read', () {
    final m = DetectedMaterial.fromMap({'type': 'cardboard', 'estimatedWeight': 1});
    expect(m.type, 'paper');
    final unknown = DetectedMaterial.fromMap({'type': 'other', 'estimatedWeight': 1});
    expect(unknown.type, 'other');
  });
}
