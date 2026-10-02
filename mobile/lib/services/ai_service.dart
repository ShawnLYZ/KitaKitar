import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:kitakitar_mobile/config/ai_config.dart';
import 'package:kitakitar_mobile/models/ai_scan_model.dart';
import 'package:kitakitar_mobile/models/material_types.dart';

/// Thrown when a photo couldn't be analyzed. [message] is shown to the user.
class AIScanException implements Exception {
  AIScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AIService {
  static const _prompt = '''
Analyze this photo of waste/recycling materials.

Return a valid JSON object with this exact structure (no markdown, no code blocks):
{
  "detectedMaterials": [
    {
      "type": "plastic",
      "estimatedWeight": 1.5
    }
  ],
  "preparationTip": "Brief advice in English for preparing this waste for drop-off at a recycling point."
}

Rules:
- type: use exactly one of these slugs:
  paper (also cardboard and cartons), plastic, glass, aluminum (cans, foil), metal (other metals),
  batteries, electronics, food, lawn (garden waste), used_oil, hazardous_waste (paint, chemicals, aerosols), tires
- Leave out items that fit none of these types (general waste)
- estimatedWeight: approximate weight in kg (0.1 to 100)
- If multiple waste types, add each to detectedMaterials with its own weight
- preparationTip: one short sentence in English, e.g. "Pour out liquids, keep caps on bottles.", "Rinse and flatten containers.", "Remove batteries if present." Adapt to what you see (bottles, cans, paper, etc.). If nothing specific, use a general tip like "Keep items dry and separate by type."
- If nothing recognizable, return {"detectedMaterials": [], "preparationTip": "Sort by material type before drop-off."}
''';

  GenerativeModel? _model;

  GenerativeModel get _generativeModel {
    _model ??= GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.2,
        maxOutputTokens: 1024,
        responseMimeType: 'application/json',
      ),
    );
    return _model!;
  }

  /// Detects waste materials in photo. Returns materials + optional preparation tip.
  /// Throws [AIScanException] when the photo couldn't be analyzed.
  Future<ScanResult> detectMaterials(String imagePath) async {
    if (useMockResponse) {
      debugPrint('[AIService] useMockResponse=true — returning mock (plastic 0.05, paper 0.02)');
      return _getMockResponse();
    }
    if (geminiApiKey.isEmpty) {
      throw AIScanException(
        'AI scanning is not set up: GEMINI_API_KEY is missing from mobile/.env.',
      );
    }

    final String? text;
    try {
      final imageBytes = await File(imagePath).readAsBytes();
      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await _generativeModel.generateContent([
        Content.multi([TextPart(_prompt), imagePart]),
      ]);

      _logGeminiResponseMeta(response);
      // Throws GenerativeAIException if the response was blocked.
      text = response.text;
    } on GenerativeAIException catch (e) {
      debugPrint('[AIService] Gemini API error: $e');
      throw AIScanException('The AI service returned an error: ${e.message}');
    } catch (e, stack) {
      debugPrint('[AIService] Gemini request failed: $e');
      debugPrint('[AIService] Stack: $stack');
      throw AIScanException(
        "Couldn't reach the AI service. Check your connection and try again.",
      );
    }

    if (text == null || text.isEmpty) {
      debugPrint('[AIService] Gemini returned empty response');
      throw AIScanException('The AI returned an empty answer. Please try again.');
    }

    debugPrint('[AIService] AI response (raw JSON): $text');
    final result = parseResponse(text);
    debugPrint('[AIService] Parsed: ${jsonEncode(result.toMap())}');
    return result;
  }

  void _logGeminiResponseMeta(GenerateContentResponse response) {
    final candidates = response.candidates;
    if (candidates.isEmpty) {
      debugPrint(
        '[AIService] candidates: empty; promptFeedback=${response.promptFeedback}',
      );
      return;
    }
    final first = candidates.first;
    debugPrint(
      '[AIService] finishReason=${first.finishReason}, '
      'finishMessage=${first.finishMessage}',
    );
    final um = response.usageMetadata;
    if (um != null) {
      debugPrint(
        '[AIService] usage tokens: prompt=${um.promptTokenCount}, '
        'candidates=${um.candidatesTokenCount}, total=${um.totalTokenCount}',
      );
    }
  }

  static String _cleanModelJsonText(String text) {
    return text
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'\s*```'), '')
        .trim();
  }

  /// Logs a long string in chunks so Flutter logcat is not truncated mid-line.
  static void _debugPrintSnippet(String label, String body, {int head = 800, int tail = 400}) {
    debugPrint('$label (len=${body.length})');
    if (body.length <= head + tail + 20) {
      debugPrint(body);
      return;
    }
    debugPrint('--- head (${head}ch) ---');
    debugPrint(body.substring(0, head));
    debugPrint('--- tail (${tail}ch) ---');
    debugPrint(body.substring(body.length - tail));
  }

  /// Parses the model's JSON. Material names are mapped to canonical slugs
  /// (see material_types.dart) so they match center materials; names no
  /// center accepts are dropped and duplicates are merged.
  /// Throws [AIScanException] if the JSON can't be read.
  @visibleForTesting
  static ScanResult parseResponse(String text) {
    final cleaned = _cleanModelJsonText(text);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[AIService] parseResponse failed: $e');
      _debugPrintSnippet('[AIService] cleaned model text', cleaned);
      throw AIScanException(
        "The AI's answer couldn't be read. Please try again.",
      );
    }

    final rawList = json['detectedMaterials'] is List
        ? json['detectedMaterials'] as List
        : const [];
    final weights = <String, double>{};
    for (final m in rawList.whereType<Map>()) {
      final rawType = (m['type'] ?? '').toString();
      final rawWeight = m['estimatedWeight'];
      final weight = rawWeight is num
          ? rawWeight.toDouble()
          : double.tryParse('$rawWeight') ?? 0;
      final type = canonicalMaterialType(rawType);
      if (type == null || weight <= 0) {
        debugPrint('[AIService] dropped material "$rawType" ($rawWeight kg)');
        continue;
      }
      weights[type] = (weights[type] ?? 0) + weight;
    }
    final tip = json['preparationTip'] is String
        ? (json['preparationTip'] as String).trim()
        : '';

    return ScanResult(
      materials: [
        for (final e in weights.entries)
          DetectedMaterial(type: e.key, estimatedWeight: e.value),
      ],
      preparationTip: tip.isNotEmpty ? tip : null,
    );
  }

  ScanResult _getMockResponse() {
    return ScanResult(
      materials: [
        DetectedMaterial(type: 'plastic', estimatedWeight: 0.05),
        DetectedMaterial(type: 'paper', estimatedWeight: 0.02),
      ],
      preparationTip: 'Rinse containers if needed; keep caps on bottles for recycling.',
    );
  }
}
