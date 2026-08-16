// lib/screens/settings_screen.dart
// Écran de paramètres : autocomplétions + bibliothèque produits + sauvegarde

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../services/backup_service.dart';
import '../services/history_service.dart';
import '../services/product_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/product_form_dialog.dart';
import '../widgets/receipt_settings_tab.dart';

class SettingsScreen extends StatefulWidget {
  /// Appelé après une restauration de données pour rafraîchir les autres écrans.
  final VoidCallback? onDataRestored;
  const SettingsScreen({super.key, this.onDataRestored});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final HistoryService _historyService = HistoryService();
  final ProductService _productService = ProductService();
  final StorageService _storageService = StorageService();
  final BackupService _backupService = BackupService();
  late TabController _tabController;

  List<String> _clientNames = [];
  List<String> _productNames = [];
  List<Product> _products = [];
  int _invoiceCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final clients = await _historyService.getClientNames();
    final historyProducts = await _historyService.getProductNames();
    final libraryProducts = await _productService.loadProducts();
    final invoices = await _storageService.loadInvoices();
    if (!mounted) return;
    setState(() {
      _clientNames = clients;
      _productNames = historyProducts;
      _products = libraryProducts;
      _invoiceCount = invoices.length;
      _isLoading = false;
    });
  }

  Future<void> _deleteClient(String name) async {
    await _historyService.deleteClientName(name);
    if (!mounted) return;
    setState(() => _clientNames.remove(name));
  }

  Future<void> _deleteProductName(String name) async {
    await _historyService.deleteProductName(name);
    if (!mounted) return;
    setState(() => _productNames.remove(name));
  }

  Future<void> _deleteLibraryProduct(String id) async {
    await _productService.deleteProduct(id);
    if (!mounted) return;
    setState(() => _products.removeWhere((p) => p.id == id));
  }

  void _editLibraryProduct(Product product) {
    showDialog(
      context: context,
      builder: (ctx) => ProductFormDialog(
        product: product,
        onSave: (updated) async {
          await _productService.updateProduct(updated);
          if (!mounted) return;
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Paramètres'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF2563EB),
          unselectedLabelColor: const Color(0xFF94A3B8),
          indicatorColor: const Color(0xFF2563EB),
          tabs: const [
            Tab(icon: Icon(Icons.person_outline), text: 'Clients'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Hist. articles'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Produits'),
            Tab(icon: Icon(Icons.backup_outlined), text: 'Sauvegarde'),
            Tab(icon: Icon(Icons.print_outlined), text: 'Reçu'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildStringList(
                  names: _clientNames,
                  emptyIcon: Icons.person_off_outlined,
                  emptyLabel: 'Aucun client enregistré',
                  onDelete: _deleteClient,
                  onEdit: (index, old) async {
                    final r = await _editDialog(old);
                    if (r != null) {
                      await _historyService.deleteClientName(old);
                      await _historyService.saveClientName(r);
                      if (!mounted) return;
                      _load();
                    }
                  },
                  onClear: () async {
                    if (await _confirm('Vider tout l\'historique clients ?')) {
                      await _historyService.clearClientNames();
                      if (!mounted) return;
                      setState(() => _clientNames.clear());
                    }
                  },
                  chipColor: const Color(0xFF2563EB),
                ),
                _buildStringList(
                  names: _productNames,
                  emptyIcon: Icons.inventory_2_outlined,
                  emptyLabel: 'Aucun historique article',
                  onDelete: _deleteProductName,
                  onEdit: (index, old) async {
                    final r = await _editDialog(old);
                    if (r != null) {
                      await _historyService.deleteProductName(old);
                      await _historyService.saveProductName(r);
                      if (!mounted) return;
                      _load();
                    }
                  },
                  onClear: () async {
                    if (await _confirm('Vider tout l\'historique articles ?')) {
                      await _historyService.clearProductNames();
                      if (!mounted) return;
                      setState(() => _productNames.clear());
                    }
                  },
                  chipColor: const Color(0xFF16A34A),
                ),
                _buildProductList(),
                _buildBackupTab(),
                const ReceiptSettingsTab(),
              ],
            ),
    );
  }

  // ---------- Onglet Sauvegarde ----------

  Widget _buildBackupTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(Constants.cardRadius),
          ),
          child: Row(
            children: [
              const Icon(Icons.storage, color: Color(0xFF2563EB), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$_invoiceCount facture(s) · ${_products.length} produit(s) · ${_clientNames.length} client(s) enregistré(s)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildBackupActionCard(
          icon: Icons.table_chart_outlined,
          color: const Color(0xFF2563EB),
          title: 'Exporter en CSV',
          subtitle: 'Toutes les factures (une ligne par article), ouvrable dans Excel / Sheets',
          onTap: _exportCsv,
        ),
        const SizedBox(height: 12),
        _buildBackupActionCard(
          icon: Icons.save_alt,
          color: const Color(0xFF16A34A),
          title: 'Sauvegarde complète (JSON)',
          subtitle: 'Factures, produits et historique d\'autocomplétion',
          onTap: _exportBackup,
        ),
        const SizedBox(height: 12),
        _buildBackupActionCard(
          icon: Icons.restore,
          color: const Color(0xFFD97706),
          title: 'Restaurer une sauvegarde',
          subtitle: 'Remplace les données actuelles par celles d\'un fichier .json',
          onTap: _restoreBackup,
        ),
        const SizedBox(height: 16),
        const Text(
          '💾 Astuce : exportez régulièrement une sauvegarde complète (JSON) pour protéger vos données. La restauration remplace toutes les données existantes.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
        ),
      ],
    );
  }

  Widget _buildBackupActionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Constants.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Constants.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Constants.cardRadius),
            border: Border.all(color: const Color(0xFFEDF1F7)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  String _timestamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _exportCsv() async {
    final invoices = await _storageService.loadInvoices();
    if (invoices.isEmpty) {
      _showSnack('Aucune facture à exporter', color: Colors.red);
      return;
    }
    try {
      final csv = _backupService.invoicesToCsv(invoices);
      await _backupService.shareCsv(csv, 'factures_${_timestamp()}.csv');
      _showSnack('CSV de ${invoices.length} facture(s) généré', color: const Color(0xFF16A34A));
    } catch (e) {
      _showSnack('Erreur lors de l\'export CSV : $e', color: Colors.red);
    }
  }

  Future<void> _exportBackup() async {
    try {
      final json = await _backupService.createBackupJson();
      await _backupService.shareBackupJson(json, 'sauvegarde_${_timestamp()}.json');
      _showSnack('Sauvegarde complète générée', color: const Color(0xFF16A34A));
    } catch (e) {
      _showSnack('Erreur lors de la sauvegarde : $e', color: Colors.red);
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final picked = await _backupService.pickAndReadJson();
      if (picked == null || !mounted) return; // annulé

      final preview = _backupService.decodeBackup(picked.content);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Constants.cardRadius),
          ),
          title: const Text('Restaurer la sauvegarde'),
          content: Text(
            'Le fichier « ${picked.filename} » contient :\n\n'
            '• ${preview.invoiceCount} facture(s)\n'
            '• ${preview.productCount} produit(s)\n'
            '• ${preview.clientCount} client(s) enregistré(s)\n\n'
            'Les données actuelles seront entièrement remplacées. Continuer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurer',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await _backupService.restoreFromJson(picked.content);
      widget.onDataRestored?.call();
      await _load();
      _showSnack(
        'Données restaurées (${preview.invoiceCount} facture(s))',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack('Restauration impossible : $e', color: Colors.red);
    }
  }

  Widget _buildStringList({
    required List<String> names,
    required IconData emptyIcon,
    required String emptyLabel,
    required Future<void> Function(String) onDelete,
    required Future<void> Function(int, String) onEdit,
    required VoidCallback onClear,
    required Color chipColor,
  }) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text('${names.length} entrée(s)',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B))),
              const Spacer(),
              if (names.isNotEmpty)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_sweep,
                      color: Colors.red, size: 18),
                  label: const Text('Tout vider',
                      style: TextStyle(color: Colors.red, fontSize: 13)),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: names.isEmpty
              ? Center(
                  child: Icon(emptyIcon, size: 64, color: Colors.grey[300]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: names.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final name = names[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(Constants.cardRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: chipColor.withValues(alpha: 0.26),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('${index + 1}',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: chipColor,
                                    fontSize: 13)),
                          ),
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 20, color: Color(0xFF2563EB)),
                              onPressed: () => onEdit(index, name),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: Colors.red),
                              onPressed: () => onDelete(name),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProductList() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Text('${_products.length} produit(s)',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () async {
                  await showDialog(
                    context: context,
                    builder: (ctx) => ProductFormDialog(onSave: (p) async {
                      await _productService.addProduct(p);
                      if (!mounted) return;
                      _load();
                    }),
                  );
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _products.isEmpty
              ? Center(
                  child: Icon(Icons.storefront_outlined,
                      size: 64, color: Colors.grey[300]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(Constants.cardRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: CircleAvatar(
                          backgroundImage: product.imagePath != null
                              ? FileImage(File(product.imagePath!))
                              : null,
                          child: product.imagePath == null
                              ? Icon(Icons.image, color: Colors.grey[400])
                              : null,
                        ),
                        title: Text(product.name),
                        subtitle: Text(product.category),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () =>
                                  _editLibraryProduct(product),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  size: 20, color: Colors.red),
                              onPressed: () =>
                                  _deleteLibraryProduct(product.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Constants.cardRadius)),
            title: const Text('Confirmer'),
            content: Text(msg),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler')),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('Vider', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _editDialog(String current) async {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Constants.cardRadius)),
        title: const Text('Modifier'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Nom',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(
                    Constants.buttonRadius)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Enregistrer')),
        ],
      ),
    );
  }
}