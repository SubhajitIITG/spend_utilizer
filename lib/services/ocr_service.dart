import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Reads text from an image on the device (Google ML Kit). Nothing is
/// uploaded. Available on Android (and iOS); not on desktop.
class OcrService {
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// The reader in use. Tests replace it, since ML Kit only runs on a
  /// phone.
  @visibleForTesting
  static Future<String> Function(String imagePath) reader = _mlKitRead;

  static Future<String> readText(String imagePath) => reader(imagePath);

  static Future<String> _mlKitRead(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      // Blocks come in reading order; one line of the screen per text line.
      return result.blocks.expand((b) => b.lines).map((l) => l.text).join('\n');
    } finally {
      await recognizer.close();
    }
  }
}
