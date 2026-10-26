// lib/services/pdf/pdf_assets.dart
// Ressources du moteur PDF : polices Inter embarquées (plus d'Helvetica par
// défaut) et images (logo / filigrane) décodées puis redimensionnées UNE seule
// fois, dans un isolate, et conservées en cache.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;

/// Demande de redimensionnement (message d'isolate : uniquement des données
/// simples et transférables).
class _ResizeRequest {
  const _ResizeRequest(this.bytes, this.maxSize);

  final Uint8List bytes;
  final int maxSize;
}

/// Redimensionne une image pour qu'elle tienne dans [maxSize] pixels.
///
/// Fonction de haut niveau (obligatoire pour `compute`) : aucun accès au
/// contexte Flutter, uniquement `package:image`.
Uint8List _resizeInIsolate(_ResizeRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) return request.bytes;
  if (decoded.width <= request.maxSize && decoded.height <= request.maxSize) {
    return request.bytes;
  }
  final resized = img.copyResize(
    decoded,
    width: decoded.width >= decoded.height ? request.maxSize : null,
    height: decoded.height > decoded.width ? request.maxSize : null,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodePng(resized));
}

class PdfAssets {
  PdfAssets._();

  /// Taille maximale (px) des images embarquées dans le PDF.
  static const int maxImageSize = 600;

  static const String _regularFont = 'assets/fonts/Inter-Regular.ttf';
  static const String _boldFont = 'assets/fonts/Inter-Bold.ttf';

  static Future<pw.ThemeData>? _theme;
  static final Map<String, Future<pw.MemoryImage?>> _images = {};

  /// Thème typographique : Inter pour le texte courant et le gras, avec les
  /// polices standard en secours pour les rares glyphes absents.
  static Future<pw.ThemeData> theme() => _theme ??= _loadTheme();

  static Future<pw.ThemeData> _loadTheme() async {
    final base = pw.Font.ttf(await rootBundle.load(_regularFont));
    final bold = pw.Font.ttf(await rootBundle.load(_boldFont));
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      italic: base,
      boldItalic: bold,
      fontFallback: [pw.Font.helvetica(), pw.Font.helveticaBold()],
    );
  }

  /// Image prête à être posée dans le PDF (null si introuvable / illisible).
  ///
  /// [path] peut être un asset (`assets/...`) ou un chemin de fichier local
  /// (logo choisi par l'utilisateur). Le résultat est mis en cache : un même
  /// chemin n'est décodé et redimensionné qu'une seule fois par processus.
  static Future<pw.MemoryImage?> image(String? path) {
    final value = path?.trim() ?? '';
    if (value.isEmpty) return Future<pw.MemoryImage?>.value(null);
    return _images.putIfAbsent(value, () => _loadImage(value));
  }

  static Future<pw.MemoryImage?> _loadImage(String path) async {
    try {
      final bytes = await _readBytes(path);
      if (bytes == null || bytes.isEmpty) return null;
      final resized = await _resize(bytes);
      return pw.MemoryImage(resized);
    } catch (error) {
      debugPrint('PdfAssets : image ignorée ($path, $error)');
      return null;
    }
  }

  static Future<Uint8List?> _readBytes(String path) async {
    if (path.startsWith('assets/')) {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    }
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Décodage / redimensionnement hors du thread UI. En cas d'isolate
  /// indisponible (très rare), l'image d'origine est utilisée telle quelle.
  static Future<Uint8List> _resize(Uint8List bytes) async {
    try {
      return await compute(_resizeInIsolate, _ResizeRequest(bytes, maxImageSize));
    } catch (error) {
      debugPrint('PdfAssets : redimensionnement hors isolate ($error)');
      return bytes;
    }
  }

  /// Vide les caches (tests).
  @visibleForTesting
  static void resetCache() {
    _theme = null;
    _images.clear();
  }
}
