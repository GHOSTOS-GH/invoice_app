// lib/widgets/product_form_dialog.dart
// Formulaire produit : même contenu pour le dialogue et la feuille modale.
// La compression d'image reste déportée dans un isolate via compute().

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../services/product_image_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'ui/app_sheet.dart';
import 'ui/app_snack.dart';

/// Ouvre le formulaire produit en feuille modale (usage principal).
Future<void> showProductFormSheet({
  required BuildContext context,
  Product? product,
  required Future<void> Function(Product) onSave,
}) {
  return showAppSheet<void>(
    context: context,
    maxHeightFactor: 0.9,
    builder: (_) => ProductFormDialog(product: product, onSave: onSave),
  );
}

/// Ouvre le formulaire produit dans un dialogue (écrans denses).
Future<void> showProductFormDialog({
  required BuildContext context,
  Product? product,
  required Future<void> Function(Product) onSave,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProductFormDialog(
      product: product,
      onSave: onSave,
      embedded: false,
    ),
  );
}

class ProductFormDialog extends StatefulWidget {
  final Product? product;
  final Future<void> Function(Product) onSave;

  /// Vrai (par défaut) quand le formulaire est déjà placé dans une feuille.
  final bool embedded;

  const ProductFormDialog({
    super.key,
    this.product,
    required this.onSave,
    this.embedded = true,
  });

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  String? _imagePath;
  int? _originalFileSize;
  int? _compressedFileSize;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!.name;
      _categoryController.text = widget.product!.category;
      _imagePath = widget.product!.imagePath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 75,
    );
    if (!mounted) return;
    if (image == null) return;

    final originalFile = File(image.path);
    final originalSize = await originalFile.length();
    if (!mounted) return;

    // Compression supplémentaire avec le package image
    final compressedPath = await _compressImage(image.path);
    if (!mounted) return;

    if (compressedPath != null) {
      final compressedFile = File(compressedPath);
      final compressedSize = await compressedFile.length();
      if (!mounted) return;
      // Copie durable : seul le NOM du fichier est conservé dans le produit.
      final storedName =
          await ProductImageStore.instance.importFile(compressedFile);
      if (!mounted) return;
      setState(() {
        _imagePath = storedName;
        _originalFileSize = originalSize;
        _compressedFileSize = compressedSize;
      });
    } else {
      final storedName =
          await ProductImageStore.instance.importFile(File(image.path));
      if (!mounted) return;
      setState(() {
        _imagePath = storedName;
        _originalFileSize = originalSize;
        _compressedFileSize = originalSize;
      });
    }
  }

  Future<String?> _compressImage(String imagePath) async {
    try {
      final originalFile = File(imagePath);
      final originalBytes = await originalFile.readAsBytes();
      // Décodage, redimensionnement et encodage JPEG déportés sur un
      // isolate via compute() : ces opérations sont coûteuses et
      // bloquaient le thread UI.
      final compressedBytes = await compute(
        _compressImageIsolate,
        (originalBytes, 800),
        debugLabel: 'ProductFormDialog._compressImage',
      );
      if (compressedBytes == null) return null;

      // Sauvegarder avec un nouveau nom
      final dir = originalFile.parent;
      final fileName =
          'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final compressedFile =
          File('${dir.path}${Platform.pathSeparator}$fileName');
      await compressedFile.writeAsBytes(compressedBytes);

      return compressedFile.path;
    } catch (e) {
      debugPrint('Erreur de compression: $e');
      return null;
    }
  }

  /// Point d'entrée de l'isolate : décode, redimensionne (max [maxDim]
  /// pixels) puis encode en JPEG qualité 70%. Seuls des types
  /// transmissibles circulent entre isolates (Uint8List / int), jamais
  /// l'objet img.Image (non « sendable »).
  static Uint8List? _compressImageIsolate((Uint8List, int) args) {
    final originalBytes = args.$1;
    final maxDim = args.$2;
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) return null;

      // Redimensionner si trop grand (max 800x800)
      img.Image processed = decoded;
      if (processed.width > maxDim || processed.height > maxDim) {
        processed = img.copyResize(
          processed,
          width: processed.width > maxDim ? maxDim : processed.width,
          height: processed.height > maxDim ? maxDim : processed.height,
        );
      }

      // Compresser en JPEG avec qualité 70%
      return Uint8List.fromList(img.encodeJpg(processed, quality: 70));
    } catch (_) {
      return null;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    if (name.isEmpty || category.isEmpty) {
      AppSnack.info(context, 'Nom et catégorie requis');
      return;
    }

    setState(() => _isLoading = true);

    final previousImagePath = widget.product?.imagePath;
    final product = Product(
      id: widget.product?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      category: category,
      imagePath: _imagePath,
    );

    // L'ancienne image est supprimée seulement si elle a été remplacée.
    if (previousImagePath != null && previousImagePath != _imagePath) {
      await ProductImageStore.instance.deleteIfManaged(previousImagePath);
    }
    if (!mounted) return;

    await widget.onSave(product);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.embedded) {
      return Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _buildBody(context, withHeader: true),
        ),
      );
    }
    return _buildBody(context, withHeader: true);
  }

  Widget _buildBody(BuildContext context, {required bool withHeader}) {
    final colors = AppColors.of(context);
    final imageFile = ProductImageStore.instance.resolve(_imagePath);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (withHeader) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.product == null
                          ? 'Nouveau produit'
                          : 'Modifier le produit',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.textStrong,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Center(
              child: InkWell(
                onTap: _pickImage,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Stack(
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: colors.border),
                      ),
                      child: imageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: Image.file(
                                imageFile,
                                fit: BoxFit.cover,
                                cacheWidth: 300,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 44,
                                  color: colors.textMuted,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 44,
                              color: colors.textMuted,
                            ),
                    ),
                    if (_imagePath != null)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.edit,
                              size: 14, color: colors.onPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_originalFileSize != null && _compressedFileSize != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: colors.success.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.compress, size: 14, color: colors.success),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '${_formatFileSize(_originalFileSize!)} → '
                        '${_formatFileSize(_compressedFileSize!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nom du produit',
                prefixIcon: Icon(Icons.label_outline, size: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Catégorie (ex: Boissons, Snacks)',
                prefixIcon: Icon(Icons.category_outlined, size: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onPrimary,
                            ),
                          )
                        : const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
