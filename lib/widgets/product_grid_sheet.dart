// lib/widgets/product_grid_sheet.dart

import 'dart:io';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import 'product_form_dialog.dart';

class ProductGridSheet extends StatefulWidget {
  final Function(Product) onProductSelected;

  const ProductGridSheet({super.key, required this.onProductSelected});

  @override
  State<ProductGridSheet> createState() => _ProductGridSheetState();
}

class _ProductGridSheetState extends State<ProductGridSheet> with SingleTickerProviderStateMixin {
  final ProductService _productService = ProductService();
  List<Product> _products = [];
  List<String> _categories = [];
  String? _selectedCategory;
  // Nullable : créé seulement à la fin de _loadData(), il peut ne pas
  // exister si le widget est fermé pendant le chargement.
  TabController? _tabController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    // Libère le TickerProvider pour éviter la fuite « Ticker was active ».
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final products = await _productService.loadProducts();
    if (!mounted) return;
    final categories = await _productService.getCategories();
    if (!mounted) return;
    // Ajouter une catégorie "Tous"
    categories.insert(0, 'Tous');
    setState(() {
      _products = products;
      _categories = categories;
      _selectedCategory = 'Tous';
    });
    // Disposer l'ancien contrôleur avant d'en créer un nouveau (chaque
    // TabController réserve un Ticker auprès du TickerProvider) : sans
    // cela, chaque appel à _loadData() fuyait un Ticker.
    _tabController?.dispose();
    _tabController = TabController(length: _categories.length, vsync: this);
    _tabController!.addListener(() {
      if (!mounted) return;
      setState(() {
        _selectedCategory = _categories[_tabController!.index];
      });
    });
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  List<Product> get _filteredProducts {
    if (_selectedCategory == null || _selectedCategory == 'Tous') {
      return _products;
    }
    return _products.where((p) => p.category == _selectedCategory).toList();
  }

  void _addProduct() async {
    await showDialog(
      context: context,
      builder: (ctx) => ProductFormDialog(
        onSave: (product) async {
          await _productService.addProduct(product);
          if (!mounted) return;
          _loadData();
        },
      ),
    );
  }

  void _editProduct(Product product) async {
    await showDialog(
      context: context,
      builder: (ctx) => ProductFormDialog(
        product: product,
        onSave: (updated) async {
          await _productService.updateProduct(updated);
          if (!mounted) return;
          _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choisir un produit',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...[
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: _categories.map((cat) => Tab(text: cat)).toList(),
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
            ),
            Expanded(
              child: _filteredProducts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'Aucun produit dans cette catégorie',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          TextButton.icon(
                            onPressed: _addProduct,
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter un produit'),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.8,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _filteredProducts.length,
                      itemBuilder: (ctx, index) {
                        final product = _filteredProducts[index];
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
        ],
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
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: product.imagePath != null && File(product.imagePath!).existsSync()
                    ? Image.file(File(product.imagePath!), fit: BoxFit.cover)
                    : Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                product.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
