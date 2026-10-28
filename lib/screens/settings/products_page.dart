// lib/screens/settings/products_page.dart
// Bibliothèque de produits : recherche, filtres par catégorie et grille.

import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../services/product_image_store.dart';
import '../../services/product_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/product_form_dialog.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/ui/ui.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
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
    _load();
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

  Future<void> _load() async {
    final products = await _productService.loadProducts();
    if (!mounted) return;
    setState(() {
      _products = products;
      _categories = products.map((p) => p.category).toSet().toList()..sort();
      if (_selectedCategory != null &&
          !_categories.contains(_selectedCategory)) {
        _selectedCategory = null;
      }
      _isLoading = false;
    });
  }

  List<Product> get _filtered {
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
    await _load();
  }

  Future<void> _editProduct(Product product) async {
    await showProductFormSheet(
      context: context,
      product: product,
      onSave: (updated) => _productService.updateProduct(updated),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce produit ?'),
        content: Text('« ${product.name} » sera retiré de la bibliothèque.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Supprimer',
              style: TextStyle(color: AppColors.of(context).danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _productService.deleteProduct(product.id);
    await ProductImageStore.instance.deleteIfManaged(product.imagePath);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    AppSnack.neutral(context, 'Produit supprimé');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: const Text('Produits'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ajouter un produit',
            onPressed: _addProduct,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: _isLoading ? const SkeletonList(itemCount: 4) : _buildBody(),
    );
  }

  Widget _buildBody() {
    final colors = AppColors.of(context);
    final products = _filtered;

    return Column(
      children: [
        Container(
          color: colors.surface,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
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
              const SizedBox(height: AppSpacing.md),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
            ],
          ),
        ),
        Expanded(
          child: products.isEmpty
              ? EmptyState(
                  icon: Icons.storefront_outlined,
                  title: _products.isEmpty
                      ? 'Aucun produit enregistré'
                      : 'Aucun résultat',
                  message: _products.isEmpty
                      ? 'Ajoutez vos produits pour les retrouver dans la '
                          'facture.'
                      : 'Modifiez la recherche ou la catégorie.',
                  actionLabel: _products.isEmpty ? 'Nouveau produit' : null,
                  onAction: _products.isEmpty ? _addProduct : null,
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) => _ProductTile(
                    product: products[index],
                    onTap: () => _editProduct(products[index]),
                    onDelete: () => _deleteProduct(products[index]),
                  ),
                ),
        ),
      ],
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

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProductTile({
    required this.product,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final imageFile = ProductImageStore.instance.resolve(product.imagePath);

    return AppCard(
      padding: EdgeInsets.zero,
      radius: AppRadius.md,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.md),
                  ),
                  child: imageFile != null
                      ? Image.file(
                          imageFile,
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          errorBuilder: (_, __, ___) => Container(
                            color: colors.surfaceAlt,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: colors.textMuted,
                            ),
                          ),
                        )
                      : Container(
                          color: colors.surfaceAlt,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: colors.textMuted,
                            size: 28,
                          ),
                        ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_horiz, color: colors.textBody),
                    tooltip: 'Options du produit',
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('Supprimer'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
