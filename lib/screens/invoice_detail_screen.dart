// lib/screens/invoice_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/product.dart';
import '../services/storage_service.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import '../utils/constants.dart';
import '../widgets/last_price_hint.dart';
import '../widgets/product_grid_sheet.dart';
import 'new_invoice_screen.dart';
import 'receipt_preview_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final Invoice invoice;
  final VoidCallback onInvoiceUpdated;
  const InvoiceDetailScreen({super.key, required this.invoice, required this.onInvoiceUpdated});

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  late Invoice _invoice;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isSharing = false;
  late TextEditingController _clientNameController;
  late TextEditingController _notesController;
  late TextEditingController _discountController;
  late TextEditingController _taxRateController;
  final StorageService _storageService = StorageService();
  final PdfService _pdfService = PdfService();

  // Ajout d'articles en mode édition (via la bibliothèque produits)
  bool _isAddingItem = false;
  Product? _selectedProduct;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  Map<String, double> _clientPrices = {};
  String _lastPriceClient = '';

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
    _clientNameController = TextEditingController(text: _invoice.clientName);
    _notesController = TextEditingController(text: _invoice.notes ?? '');
    _discountController = TextEditingController(
        text: _invoice.discount == 0 ? '' : _priceInputValue(_invoice.discount));
    _taxRateController = TextEditingController(
        text: _invoice.taxRate == 0 ? '' : _priceInputValue(_invoice.taxRate));
    _quantityController = TextEditingController();
    _priceController = TextEditingController();
    _lastPriceClient = _invoice.clientName.trim().toLowerCase();
    _clientNameController.addListener(_onClientNameChangedForPrices);
    _loadClientPrices();
  }

  @override
  void dispose() {
    _clientNameController.removeListener(_onClientNameChangedForPrices);
    _clientNameController.dispose();
    _notesController.dispose();
    _discountController.dispose();
    _taxRateController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onClientNameChangedForPrices() {
    final name = _clientNameController.text.trim();
    if (name.isEmpty || name.toLowerCase() == _lastPriceClient) return;
    _lastPriceClient = name.toLowerCase();
    _loadClientPrices();
  }

  Future<void> _loadClientPrices() async {
    final prices = await _storageService.getClientPriceMap(_lastPriceClient);
    if (!mounted) return;
    setState(() => _clientPrices = prices);
  }

  String _formatDate(DateTime date) => DateFormat('EEEE dd MMMM yyyy à HH:mm', 'fr_FR').format(date);

  void _toggleEdit() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _clientNameController.text = _invoice.clientName;
        _notesController.text = _invoice.notes ?? '';
        _discountController.text =
            _invoice.discount == 0 ? '' : _priceInputValue(_invoice.discount);
        _taxRateController.text =
            _invoice.taxRate == 0 ? '' : _priceInputValue(_invoice.taxRate);
        _isAddingItem = false;
        _selectedProduct = null;
        _quantityController.clear();
        _priceController.clear();
      }
    });
  }

  void _updateItem(int index, InvoiceItem newItem) {
    final newItems = List<InvoiceItem>.from(_invoice.items);
    newItems[index] = newItem;
    setState(() {
      _invoice = _invoice.copyWith(items: newItems);
    });
  }

  void _deleteItem(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Constants.cardRadius)),
        title: const Text('Confirmer la suppression'),
        content: Text('Supprimer "${_invoice.items[index].name}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              final newItems = List<InvoiceItem>.from(_invoice.items)..removeAt(index);
              setState(() {
                _invoice = _invoice.copyWith(items: newItems);
              });
              Navigator.pop(context);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _openProductGrid() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductGridSheet(onProductSelected: _onProductSelected),
    );
  }

  void _onProductSelected(Product product) {
    setState(() {
      final isSameProduct = _selectedProduct?.id == product.id;
      _selectedProduct = product;
      if (!isSameProduct) {
        // Pré-remplit le prix avec le dernier prix vendu à ce client
        final lastPrice = _clientPrices[product.name.trim().toLowerCase()];
        if (lastPrice != null) {
          _priceController.text = _priceInputValue(lastPrice);
        } else {
          _priceController.clear();
        }
      }
    });
  }

  String _priceInputValue(double value) =>
      value % 1 == 0 ? value.toInt().toString() : value.toString();

  void _addNewItem() {
    final quantity = int.tryParse(_quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer une quantité valide'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    double? price = double.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) {
      price = 1.0;
      _priceController.text = '1';
    }

    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un produit'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final newItems = List<InvoiceItem>.from(_invoice.items)
      ..add(InvoiceItem(
        name: _selectedProduct!.name,
        quantity: quantity,
        unitPrice: price,
      ));
    setState(() {
      _invoice = _invoice.copyWith(items: newItems);
      _isAddingItem = false;
      _selectedProduct = null;
      _quantityController.clear();
      _priceController.clear();
    });
  }

  Widget _buildAddItemPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.add_box_outlined, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              const Text('Nouvel article', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  setState(() {
                    _isAddingItem = false;
                    _selectedProduct = null;
                    _quantityController.clear();
                    _priceController.clear();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openProductGrid,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.grey[600]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedProduct?.name ?? 'Appuyez pour choisir un produit',
                      style: TextStyle(
                        fontSize: 15,
                        color: _selectedProduct != null ? Colors.black : Colors.grey[600],
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Quantité *',
                    prefixIcon: Icon(Icons.numbers),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  decoration: const InputDecoration(
                    labelText: 'Prix unitaire (FCFA)',
                    prefixIcon: Icon(Icons.attach_money),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          LastPriceHint(
            lastPrice: _selectedProduct == null
                ? null
                : _clientPrices[_selectedProduct!.name.trim().toLowerCase()],
            clientName: _invoice.clientName,
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _addNewItem,
            icon: const Icon(Icons.check),
            label: const Text('Ajouter l\'article'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);
    // Construit explicitement la facture (plutôt que copyWith) pour permettre
    // d'effacer réellement les notes quand le champ est vidé.
    double parsePositive(String text) {
      final value = double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
      return value < 0 ? 0 : value;
    }

    final updatedInvoice = Invoice(
      id: _invoice.id,
      clientName: _clientNameController.text.trim().isEmpty
          ? 'Client inconnu'
          : _clientNameController.text.trim(),
      createdAt: _invoice.createdAt,
      items: _invoice.items.toList(),
      status: _invoice.status,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      discount: parsePositive(_discountController.text),
      taxRate: parsePositive(_taxRateController.text).clamp(0, 100).toDouble(),
    );

    final all = await _storageService.loadInvoices();
    final idx = all.indexWhere((inv) => inv.id == updatedInvoice.id);
    if (idx != -1) {
      all[idx] = updatedInvoice;
      await _storageService.saveInvoices(all);
    }

    setState(() {
      _invoice = updatedInvoice;
      _isEditing = false;
      _isSaving = false;
    });

    widget.onInvoiceUpdated();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Facture mise à jour'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _deleteInvoice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Constants.cardRadius)),
        title: const Text('Supprimer la facture ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    final all = await _storageService.loadInvoices();
    all.removeWhere((inv) => inv.id == _invoice.id);
    await _storageService.saveInvoices(all);

    if (!mounted) return;
    widget.onInvoiceUpdated();
    Navigator.pop(context);
  }

  void _toggleArchive() async {
    final newStatus = _invoice.status == InvoiceStatus.archivee ? InvoiceStatus.enCours : InvoiceStatus.archivee;
    setState(() {
      _invoice = _invoice.copyWith(status: newStatus);
    });
    await _saveChanges(); // save immédiatement
  }

  void _duplicateInvoice() {
    final dup = Invoice(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // ID unique
      clientName: _invoice.clientName,
      createdAt: DateTime.now(),
      items: _invoice.items.map((item) => item.copyWith()).toList(),
      notes: _invoice.notes,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NewInvoiceScreen(onInvoiceCreated: widget.onInvoiceUpdated, initialInvoice: dup)),
    );
  }

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('Partager la facture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _shareOption(ctx, icon: Icons.print_outlined, color: const Color(0xFF2563EB), label: 'Impression Bluetooth', subtitle: 'Aperçu du reçu thermique (58 / 80 mm)', onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceiptPreviewScreen(invoice: _invoice),
                  ),
                );
              }),
              _shareOption(ctx, icon: Icons.picture_as_pdf, color: const Color(0xFFDC2626), label: 'Document PDF', subtitle: 'Idéal pour l\'impression', onTap: () async {
                Navigator.pop(ctx);
                setState(() => _isSharing = true);
                try {
                  await _pdfService.shareAsPdf(_invoice);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur PDF : $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                  );
                } finally {
                  if (mounted) setState(() => _isSharing = false);
                }
              }),
              _shareOption(ctx, icon: Icons.image_outlined, color: const Color(0xFF2563EB), label: 'Image PNG', subtitle: 'Pour partager sur WhatsApp, etc.', onTap: () async {
                Navigator.pop(ctx);
                setState(() => _isSharing = true);
                try {
                  await _pdfService.shareAsPng(_invoice);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur PNG : $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                  );
                } finally {
                  if (mounted) setState(() => _isSharing = false);
                }
              }),
              _shareOption(ctx, icon: Icons.photo_camera_outlined, color: const Color(0xFF16A34A), label: 'Image JPG', subtitle: 'Format photo compressé', onTap: () async {
                Navigator.pop(ctx);
                setState(() => _isSharing = true);
                try {
                  await _pdfService.shareAsJpg(_invoice);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur JPG : $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
                  );
                } finally {
                  if (mounted) setState(() => _isSharing = false);
                }
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareOption(BuildContext ctx, {required IconData icon, required Color color, required String label, required String subtitle, required VoidCallback onTap}) {
    return ListTile(
      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color)),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier' : 'Détails'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        actions: _isEditing
            ? [
                IconButton(icon: const Icon(Icons.cancel), onPressed: _toggleEdit, tooltip: 'Annuler'),
                IconButton(
                  icon: _isSaving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  onPressed: _isSaving ? null : _saveChanges,
                  tooltip: 'Enregistrer',
                ),
              ]
            : [
                IconButton(icon: Icon(_invoice.status == InvoiceStatus.archivee ? Icons.unarchive : Icons.archive), onPressed: _toggleArchive, tooltip: _invoice.status == InvoiceStatus.archivee ? 'Désarchiver' : 'Archiver'),
                IconButton(icon: const Icon(Icons.content_copy), onPressed: _duplicateInvoice, tooltip: 'Dupliquer'),
                IconButton(icon: const Icon(Icons.edit), onPressed: _toggleEdit, tooltip: 'Modifier'),
                IconButton(icon: const Icon(Icons.delete), onPressed: _deleteInvoice, tooltip: 'Supprimer', color: Colors.red),
              ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Hero(
                        tag: 'invoice-icon-${_invoice.id}',
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1E40AF)]), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.receipt_long, color: Colors.white, size: 28),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('FACTURE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1.5)),
                            const SizedBox(height: 4),
                            Text(
                              '#${_invoice.id.length >= 6 ? _invoice.id.substring(_invoice.id.length - 6) : _invoice.id}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _isEditing
                      ? TextField(
                          controller: _clientNameController,
                          decoration: InputDecoration(labelText: 'Nom du client', prefixIcon: const Icon(Icons.person, color: Color(0xFF2563EB)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, fillColor: const Color(0xFFF1F5F9)),
                        )
                      : _InfoRow(icon: Icons.person, label: 'Client', value: _invoice.clientName),
                  const SizedBox(height: 12),
                  _InfoRow(icon: Icons.calendar_today, label: 'Date', value: _formatDate(_invoice.createdAt)),
                  const SizedBox(height: 12),
                  _isEditing
                      ? DropdownButton<InvoiceStatus>(
                          value: _invoice.status,
                          isExpanded: true,
                          items: InvoiceStatus.values.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: Color(s.color).withAlpha(26), borderRadius: BorderRadius.circular(8)),
                                child: Text(s.label, style: TextStyle(color: Color(s.color), fontWeight: FontWeight.w600)),
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _invoice = _invoice.copyWith(status: v));
                          },
                          underline: Container(),
                        )
                      : Row(
                          children: [
                            Icon(Icons.local_shipping, size: 20, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Text('Statut : ', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: Color(_invoice.status.color).withAlpha(40), borderRadius: BorderRadius.circular(8)),
                              child: Text(_invoice.status.label, style: TextStyle(fontSize: 14, color: Color(_invoice.status.color), fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                  if (_isEditing) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _discountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                            decoration: InputDecoration(labelText: 'Remise (FCFA)', prefixIcon: const Icon(Icons.percent, color: Color(0xFF2563EB)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, fillColor: const Color(0xFFF1F5F9)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _taxRateController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                            decoration: InputDecoration(labelText: 'TVA (%)', prefixIcon: const Icon(Icons.receipt, color: Color(0xFF2563EB)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, fillColor: const Color(0xFFF1F5F9)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Notes (optionnel)', style: const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(hintText: 'Ajoutez vos notes ici...', prefixIcon: const Icon(Icons.description, color: Color(0xFF2563EB)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, fillColor: const Color(0xFFF1F5F9)),
                    ),
                  ] else if (_invoice.notes != null && _invoice.notes!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE2E8F0))),
                      child: Text(_invoice.notes!, style: const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Articles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(10)), child: Text('${_invoice.items.length}', style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 13))),
                      const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)), child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2, size: 12, color: Color(0xFFD97706)),
                          const SizedBox(width: 3),
                          Text('${_invoice.totalQuantity} unités', style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._invoice.items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Constants.cardRadius), side: BorderSide(color: Colors.grey.withAlpha(30))),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: _isEditing
                            ? _EditableItemTile(index: index, item: item, onUpdate: (u) => _updateItem(index, u), onDelete: () => _deleteItem(index))
                            : _CompactItemView(index: index, item: item),
                      ),
                    );
                  }),
                  if (_isEditing) ...[
                    const SizedBox(height: 4),
                    if (_isAddingItem)
                      _buildAddItemPanel()
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _isAddingItem = true),
                          icon: const Icon(Icons.add, color: Color(0xFF2563EB)),
                          label: const Text('Ajouter un article', style: TextStyle(color: Color(0xFF2563EB))),
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), side: const BorderSide(color: Color(0xFF2563EB), width: 2)),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF1E40AF)]), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_invoice.hasBreakdown) ...[
                                _TotalBreakdownLine('Sous-total', formatCurrency(_invoice.total)),
                                if (_invoice.discount > 0)
                                  _TotalBreakdownLine('Remise', '-${formatCurrency(_invoice.discount)}'),
                                if (_invoice.taxRate > 0)
                                  _TotalBreakdownLine('TVA ${formatNumber(_invoice.taxRate)}%', '+${formatCurrency(_invoice.taxAmount)}'),
                                const SizedBox(height: 8),
                              ],
                              const Text('TOTAL À PAYER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1.2)),
                              const SizedBox(height: 6),
                              Text(formatCurrency(_invoice.payableTotal), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _isSharing ? null : _showShareSheet,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withAlpha(60))),
                            child: _isSharing ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.share, color: Colors.white, size: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalBreakdownLine extends StatelessWidget {
  final String label;
  final String value;
  const _TotalBreakdownLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        Text(value, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _CompactItemView extends StatelessWidget {
  final int index;
  final InvoiceItem item;
  const _CompactItemView({required this.index, required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 28, height: 28, decoration: const BoxDecoration(color: Color(0xFFDBEAFE), shape: BoxShape.circle), child: Center(child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB), fontSize: 12)))),
            const SizedBox(width: 10),
            Expanded(child: Text(item.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF2563EB).withAlpha(20), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF2563EB).withAlpha(60))), child: Text('×${item.quantity}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Prix : ${formatCurrency(item.unitPrice)}', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            Text(formatCurrency(item.subtotal), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
          ],
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2563EB)),
        const SizedBox(width: 10),
        Text('$label : ', style: const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)))),
      ],
    );
  }
}

class _EditableItemTile extends StatefulWidget {
  final int index;
  final InvoiceItem item;
  final Function(InvoiceItem) onUpdate;
  final VoidCallback onDelete;
  const _EditableItemTile({required this.index, required this.item, required this.onUpdate, required this.onDelete});

  @override
  State<_EditableItemTile> createState() => _EditableItemTileState();
}

class _EditableItemTileState extends State<_EditableItemTile> {
  late TextEditingController _nameController;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.name);
    _quantityController = TextEditingController(text: widget.item.quantity.toString());
    _priceController = TextEditingController(text: widget.item.unitPrice.toString());
  }

  @override
  void didUpdateWidget(covariant _EditableItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-synchronise les champs quand l'article change (ex: suppression multiple
    // qui décale les index) pour éviter que les valeurs se mélangent.
    if (!identical(oldWidget.item, widget.item)) {
      _nameController.text = widget.item.name;
      _quantityController.text = widget.item.quantity.toString();
      _priceController.text = widget.item.unitPrice.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _update() {
    final quantity = int.tryParse(_quantityController.text);
    final price = double.tryParse(_priceController.text);
    if (quantity == null || quantity <= 0 || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valeurs invalides'), backgroundColor: Colors.red));
      return;
    }
    widget.onUpdate(widget.item.copyWith(
      name: _nameController.text.trim().isEmpty ? 'Sans nom' : _nameController.text.trim(),
      quantity: quantity,
      unitPrice: price,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 28, height: 28, decoration: const BoxDecoration(color: Color(0xFFDBEAFE), shape: BoxShape.circle), child: Center(child: Text('${widget.index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2563EB), fontSize: 12)))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder(), isDense: true))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: TextField(controller: _quantityController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Quantité', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _priceController, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))], decoration: const InputDecoration(labelText: 'Prix unitaire', border: OutlineInputBorder(), isDense: true))),
            IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: _update, tooltip: 'Valider'),
            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: widget.onDelete, tooltip: 'Supprimer'),
          ],
        ),
      ],
    );
  }
}