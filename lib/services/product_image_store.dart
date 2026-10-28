// lib/services/product_image_store.dart
// Stockage durable des images produit : dossier de documents de l'application,
// Product.imagePath ne contient que le NOM du fichier.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import 'product_service.dart';

class ProductImageStore {
  ProductImageStore({Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory =
            documentsDirectory ?? getApplicationDocumentsDirectory;

  /// Instance utilisée par l'application.
  static final ProductImageStore instance = ProductImageStore();

  /// Drapeau de migration unique des anciens chemins absolus.
  static const String migrationFlagKey = 'product_images_migrated';

  static const String _folderName = 'product_images';

  final Future<Directory> Function() _documentsDirectory;
  Directory? _directory;
  Future<void>? _initializing;

  /// Dossier des images, null tant que [init] n'a pas abouti.
  Directory? get directory => _directory;

  /// À appeler une fois au démarrage, avant `runApp`.
  Future<void> init() async {
    await ensureDirectory();
    await migrateLegacyImages();
  }

  /// Résout (et crée au besoin) le dossier `documents/product_images`.
  Future<Directory> ensureDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;

    final pending = _initializing;
    if (pending != null) {
      await pending;
      return _directory!;
    }

    final future = _openDirectory();
    _initializing = future;
    try {
      await future;
    } finally {
      if (identical(_initializing, future)) _initializing = null;
    }
    return _directory!;
  }

  Future<void> _openDirectory() async {
    final documents = await _documentsDirectory();
    final dir = Directory(
      '${documents.path}${Platform.pathSeparator}$_folderName',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _directory = dir;
  }

  /// Fichier correspondant à [stored].
  ///
  /// - null / vide → null ;
  /// - ancien format absolu (contient un séparateur) → renvoyé tel quel ;
  /// - nom de fichier → résolu dans le dossier `product_images`.
  File? resolve(String? stored) {
    if (stored == null) return null;
    final value = stored.trim();
    if (value.isEmpty) return null;
    if (_hasPathSeparator(value)) return File(value);
    final dir = _directory;
    if (dir == null) {
      // init() pas encore appelé : meilleur effort (fichier relatif).
      return File(value);
    }
    return File('${dir.path}${Platform.pathSeparator}$value');
  }

  /// Copie [source] dans `product_images` et renvoie le NOM du fichier.
  Future<String> importFile(File source) async {
    final dir = await ensureDirectory();
    final extension = _extensionOf(source.path);
    final name =
        'img_${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination =
        File('${dir.path}${Platform.pathSeparator}$name');
    await source.copy(destination.path);
    return name;
  }

  /// Écrit des octets (restauration de sauvegarde) sous [name].
  Future<File> writeBytes(String name, Uint8List bytes) async {
    final dir = await ensureDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Supprime un fichier UNIQUEMENT s'il appartient à `product_images`.
  Future<void> deleteIfManaged(String? stored) async {
    final dir = _directory;
    if (dir == null || stored == null || stored.trim().isEmpty) return;
    final file = resolve(stored);
    if (file == null) return;
    if (file.parent.path != dir.path) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('ProductImageStore : suppression impossible ($error)');
    }
  }

  /// Migration unique : les anciens chemins absolus sont copiés dans
  /// `product_images` et remplacés par le nom du fichier. Si le fichier
  /// n'existe plus, `imagePath` est mis à null. Rien n'est supprimé.
  Future<void> migrateLegacyImages() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(migrationFlagKey) == true) return;

    try {
      final dir = await ensureDirectory();
      final products = await ProductService().loadProducts();
      var changed = false;
      for (final product in products) {
        if (await _migrateProduct(product, dir)) changed = true;
      }
      if (changed) {
        await ProductService().saveProducts(products);
      }
      await prefs.setBool(migrationFlagKey, true);
    } catch (error) {
      // Le drapeau n'est pas posé : la migration sera retentée au prochain
      // démarrage. Aucune donnée n'est supprimée.
      debugPrint('ProductImageStore : migration impossible ($error)');
    }
  }

  Future<bool> _migrateProduct(Product product, Directory dir) async {
    final stored = product.imagePath;
    if (stored == null || stored.trim().isEmpty) return false;
    // Déjà au nouveau format (nom de fichier) : rien à faire.
    if (!_hasPathSeparator(stored)) return false;

    final legacy = File(stored);
    if (!await legacy.exists()) {
      product.imagePath = null;
      return true;
    }

    final extension = _extensionOf(stored);
    final name = 'migrated_${DateTime.now().microsecondsSinceEpoch}$extension';
    try {
      await legacy.copy('${dir.path}${Platform.pathSeparator}$name');
      product.imagePath = name;
      return true;
    } catch (error) {
      debugPrint('ProductImageStore : copie impossible ($error)');
      return false;
    }
  }

  static bool _hasPathSeparator(String value) =>
      value.contains('/') || value.contains('\\');

  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.jpg';
    final extension = name.substring(dot).toLowerCase();
    return extension.length > 6 ? '.jpg' : extension;
  }
}
