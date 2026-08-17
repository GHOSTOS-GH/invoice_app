// lib/widgets/product_form_dialog.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../models/product.dart';

class ProductFormDialog extends StatefulWidget {
  final Product? product;
  final Function(Product) onSave;

  const ProductFormDialog({super.key, this.product, required this.onSave});

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
    if (image != null) {
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
        setState(() {
          _imagePath = compressedPath;
          _originalFileSize = originalSize;
          _compressedFileSize = compressedSize;
        });
      } else {
        setState(() {
          _imagePath = image.path;
          _originalFileSize = originalSize;
          _compressedFileSize = originalSize;
        });
      }
    }
  }

  Future<String?> _compressImage(String imagePath) async {
    try {
      final originalFile = File(imagePath);
      final originalBytes = await originalFile.readAsBytes();
      // Décodage, redimensionnement et encodage JPEG déportés sur un
      // isolate via compute() : ces opérations sont coûteuses et
      // bloquaient le thread UI (même classe de bug que le logo du reçu,
      // déjà corrigé dans ReceiptBuilder).
      final compressedBytes = await compute(
        _compressImageIsolate,
        (originalBytes, 800),
        debugLabel: 'ProductFormDialog._compressImage',
      );
      if (compressedBytes == null) return null;

      // Sauvegarder avec un nouveau nom
      final dir = originalFile.parent;
      final fileName = 'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final compressedFile = File('${dir.path}${Platform.pathSeparator}$fileName');
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
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final category = _categoryController.text.trim();
    if (name.isEmpty || category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom et catégorie requis')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final product = Product(
      id: widget.product?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      category: category,
      imagePath: _imagePath,
    );

    widget.onSave(product);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Nouveau produit' : 'Modifier le produit'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: _imagePath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(File(_imagePath!), fit: BoxFit.cover),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined, size: 44, color: Colors.grey),
                  ),
                  if (_imagePath != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            if (_originalFileSize != null && _compressedFileSize != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.compress, size: 14, color: Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Text(
                      '${_formatFileSize(_originalFileSize!)} → ${_formatFileSize(_compressedFileSize!)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Nom du produit',
                prefixIcon: const Icon(Icons.label, size: 20, color: Color(0xFF2563EB)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryController,
              decoration: InputDecoration(
                labelText: 'Catégorie (ex: Boissons, Snacks)',
                prefixIcon: const Icon(Icons.category, size: 20, color: Color(0xFF2563EB)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
