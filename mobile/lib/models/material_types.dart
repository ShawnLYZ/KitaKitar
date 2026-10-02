/// Canonical material slugs: the `type` stored on center materials, QR codes
/// and transactions. Keep in sync with `kMaterialTypes` in
/// center_web/lib/models/center_material.dart and `CO2_MULTIPLIERS` in
/// firebase/functions/src/points.ts.
const List<Map<String, String>> kMaterialTypes = [
  {'type': 'paper', 'label': 'Paper / Cardboard'},
  {'type': 'plastic', 'label': 'Plastics'},
  {'type': 'glass', 'label': 'Glass'},
  {'type': 'aluminum', 'label': 'Aluminum'},
  {'type': 'batteries', 'label': 'Batteries'},
  {'type': 'electronics', 'label': 'Electronics'},
  {'type': 'food', 'label': 'Food'},
  {'type': 'lawn', 'label': 'Lawn Materials'},
  {'type': 'used_oil', 'label': 'Used Oil'},
  {'type': 'hazardous_waste', 'label': 'Household Hazardous Waste'},
  {'type': 'tires', 'label': 'Tires'},
  {'type': 'metal', 'label': 'Metal'},
];

/// Other names for canonical slugs: the vocabulary older scans were saved
/// with, plus common variants the AI may still return.
const Map<String, String> _materialAliases = {
  'cardboard': 'paper',
  'carton': 'paper',
  'plastics': 'plastic',
  'aluminium': 'aluminum',
  'can': 'aluminum',
  'battery': 'batteries',
  'electronic': 'electronics',
  'e_waste': 'electronics',
  'food_waste': 'food',
  'organic': 'food',
  'garden': 'lawn',
  'yard_waste': 'lawn',
  'oil': 'used_oil',
  'cooking_oil': 'used_oil',
  'hazardous': 'hazardous_waste',
  'tire': 'tires',
  'tyre': 'tires',
  'tyres': 'tires',
  'metals': 'metal',
};

/// Maps a material name to its canonical slug, or null when no center can
/// accept that kind of material (e.g. the AI's old `other`).
String? canonicalMaterialType(String name) {
  final key = name.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  if (kMaterialTypes.any((m) => m['type'] == key)) return key;
  return _materialAliases[key];
}

/// Display label for a material slug.
String materialLabel(String type) {
  for (final m in kMaterialTypes) {
    if (m['type'] == type) return m['label']!;
  }
  if (type.isEmpty) return type;
  return type[0].toUpperCase() + type.substring(1);
}
