// lib/widgets/product_grid_sheet.dart
// Sélecteur de produit : recherche, chips de catégories et grille.

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_image_store.dart';
import '../services/product_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'product_form_dialog.dart';
import 'ui/empty_state.dart';
import 'ui/sheet_handle.dart';

class ProductGridSheet extends StatefulWidget {
  final Function(Product) onProductSelected;

  const ProductGridSheet({super.key, required this.onProductSelected});

  @override
  State<ProductGridSheet> createState() => _ProductGridSheetState();
}

class _ProductGridSheetState extends State<ProductGridSheet> {
  final ProductService _productService = ProductService();
  final TextEditingController _searchController = TextEditingController();
  List<Product> _products = [];
  List<String> _categories = [];
  String? _selectedCategory;
  String _query = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _query = _searchController.text.trim().toLowerCase());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final products = await _productService.loadProducts();
    if (!mounted) return;
    final categories = await _productService.getCategories();
    if (!mounted) return;
    setState(() {
      _products = products;
      _categories = categories..sort();
      if (_selectedCategory != null &&
          !_categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
      _isLoading = false;
    });
  }

  List<Product> get _filteredProducts {
    return _products.where((product) {
      final matchesCategory =
          _selectedCategory == null || product.category == _selectedCategory;
      final matchesQuery =
          _query.isEmpty || product.name.toLowerCase().contains(_query);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  Future<void> _addProduct() async {
    await showProductFormSheet(
      context: context,
      onSave: (product) => _productService.addProduct(product),
    );
    if (!mounted) return;
    await _loadData();
  }

  Future<void> _editProduct(Product product) async {
    await showProductFormSheet(
      context: context,
      product: product,
      onSave: (updated) => _productService.updateProduct(updated),
    );
    if (!mounted) return;
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final products = _filteredProducts;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      child: Column(
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choisir un produit',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.textStrong,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addProduct,
                  tooltip: 'Ajouter un produit',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher un produit...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Effacer la recherche',
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                _CategoryChip(
                  label: 'Toutes',
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                for (final category in _categories) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _CategoryChip(
                    label: category,
                    selected: _selectedCategory == category,
                    onTap: () => setState(() {
                      _selectedCategory =
                          _selectedCategory == category ? null : category;
                    }),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : products.isEmpty
                    ? EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: _products.isEmpty
                            ? 'Aucun produit enregistré'
                            : 'Aucun produit dans cette catégorie',
                        message: _products.isEmpty
                            ? 'Ajoutez un produit pour l\'utiliser dans vos '
                                'factures.'
                            : 'Modifiez la recherche ou la catégorie.',
                        actionLabel: 'Ajouter un produit',
                        onAction: _addProduct,
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: AppSpacing.md,
                          crossAxisSpacing: AppSpacing.md,
                          childAspectRatio: 0.82,
                        ),
                        itemCount: products.length,
                        itemBuilder: (ctx, index) {
                          final product = products[index];
                          return _ProductCard(
                            product: product,
                            onTap: () {
                              Navigator.pop(context);
                              widget.onProductSelected(product);
                            },
                            onLongPress: () => _editProduct(product),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? colors.primary : colors.border),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? colors.primary : colors.textBody,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ProductCard({
    required this.product,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final imageFile = ProductImageStore.instance.resolve(product.imagePath);

    final placeholder = Container(
      color: colors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: colors.textMuted,
      ),
    );

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: imageFile != null
                    ? Image.file(
                        imageFile,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, __, ___) => placeholder,
                      )
                    : placeholder,
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  product.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
