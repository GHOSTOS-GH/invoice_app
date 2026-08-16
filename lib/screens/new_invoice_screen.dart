// lib/screens/new_invoice_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/invoice.dart';
import '../models/product.dart';
import '../services/storage_service.dart';
import '../services/history_service.dart'; 
import '../utils/formatters.dart';
import '../utils/constants.dart';
import '../widgets/product_grid_sheet.dart';
import '../widgets/last_price_hint.dart';

class NewInvoiceScreen extends StatefulWidget {
  final VoidCallback onInvoiceCreated;
  final Invoice? initialInvoice;
  const NewInvoiceScreen({super.key, required this.onInvoiceCreated, this.initialInvoice});

  @override
  State<NewInvoiceScreen> createState() => _NewInvoiceScreenState();
}

class _NewInvoiceScreenState extends State<NewInvoiceScreen> with WidgetsBindingObserver {
  final _clientNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _storageService = StorageService();
  final _historyService = HistoryService();
  final List<InvoiceItem> _items = [];
  bool _isAddingItem = false;
  Product? _selectedProduct;
  bool _isLoading = false;
  List<String> _clientSuggestions = [];
  bool _showClientSuggestions = false;
  final FocusNode _clientFocusNode = FocusNode();

  // Dernier prix par produit (clé : nom du produit en minuscules) pour le client saisi
  Map<String, double> _clientPrices = {};
  String _lastPriceClient = '';
  int _priceLoadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clientNameController.addListener(_onClientNameChanged);
    _loadInitialData();
    _clientFocusNode.addListener(() {
      if (!_clientFocusNode.hasFocus) {
        setState(() => _showClientSuggestions = false);
      }
    });
  }

  Future<void> _loadInitialData() async {
    if (widget.initialInvoice != null) {
      _clientNameController.text = widget.initialInvoice!.clientName;
      _items.addAll(widget.initialInvoice!.items.map((item) => item.copyWith()));
    } else {
      final draft = await _storageService.loadDraft();
      if (!mounted) return;
      if (draft != null) {
        _clientNameController.text = draft.clientName;
        _items.addAll(draft.items);
      }
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveDraft();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clientNameController.removeListener(_onClientNameChanged);
    _clientNameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _clientFocusNode.dispose();
    _saveDraft();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    if (_items.isEmpty && _clientNameController.text.trim().isEmpty) {
      await _storageService.clearDraft();
      return;
    }
    final draft = Invoice(
      id: 'draft',
      clientName: _clientNameController.text.trim().isEmpty
          ? 'Client inconnu'
          : _clientNameController.text.trim(),
      createdAt: DateTime.now(),
      items: List.from(_items),
    );
    await _storageService.saveDraft(draft);
  }

  void _onClientNameChanged() async {
    final clientText = _clientNameController.text;
    if (clientText.isEmpty) {
      setState(() {
        _showClientSuggestions = false;
        _clientPrices = {};
        _lastPriceClient = '';
      });
      return;
    }
    final suggestions = await _historyService.searchClientNames(clientText);
    if (!mounted) return;

    // Charge (une seule fois par nom de client) la table des derniers prix
    if (clientText.trim().toLowerCase() != _lastPriceClient) {
      final token = ++_priceLoadToken;
      final prices = await _storageService.getClientPriceMap(clientText);
      if (!mounted || token != _priceLoadToken) return;
      _clientPrices = prices;
      _lastPriceClient = clientText.trim().toLowerCase();
    }

    setState(() {
      _clientSuggestions = suggestions;
      _showClientSuggestions = suggestions.isNotEmpty && _clientFocusNode.hasFocus;
    });
  }

  void _addItem() {
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
        ),
      );
      return;
    }

    final productName = _selectedProduct!.name;
    final item = InvoiceItem(
      name: productName,
      quantity: quantity,
      unitPrice: price,
    );

    setState(() {
      _items.add(item);
      _quantityController.clear();
      _priceController.clear();
      _selectedProduct = null;
      _isAddingItem = false;
    });

    _historyService.saveProductName(productName);
    _saveDraft();
  }

  void _editItem(int index) {
    showDialog(
      context: context,
      builder: (_) => _ItemEditDialog(
        item: _items[index],
        onSave: (updated) {
          setState(() => _items[index] = updated);
          _saveDraft();
        },
      ),
    );
  }

  void _deleteItem(int index) {
    setState(() => _items.removeAt(index));
    _saveDraft();
  }

  double _calculateTotal() => _items.fold(0.0, (sum, item) => sum + item.subtotal);

  Future<void> _finalizeInvoice() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins un article avant de finaliser'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final clientName = _clientNameController.text.trim().isEmpty
        ? 'Client inconnu'
        : _clientNameController.text.trim();

    final invoice = Invoice(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      clientName: clientName,
      createdAt: DateTime.now(),
      items: List.from(_items),
    );

    try {
      await _storageService.addInvoice(invoice);
      if (clientName != 'Client inconnu') {
        await _historyService.saveClientName(clientName);
      }
      await _storageService.clearDraft();

      if (!mounted) return;

      setState(() {
        _clientNameController.clear();
        _items.clear();
        _isAddingItem = false;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Facture enregistrée avec succès !'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onInvoiceCreated();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de la sauvegarde: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openProductGrid() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ProductGridSheet(
        onProductSelected: _onProductSelected,
      ),
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

  String _priceInputValue(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Nouvelle Facture'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Effacer le brouillon',
            onPressed: () async {
              await _storageService.clearDraft();
              if (!context.mounted) return;
              setState(() {
                _clientNameController.clear();
                _items.clear();
                _isAddingItem = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Brouillon effacé'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _showClientSuggestions = false);
        },
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _clientNameController,
                    focusNode: _clientFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Nom du client (optionnel)',
                      prefixIcon: Icon(Icons.person, color: Colors.blue[700]),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Constants.inputRadius)),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                  ),
                  if (_showClientSuggestions && _clientSuggestions.isNotEmpty)
                    _buildSuggestions(
                      _clientSuggestions,
                      onSelect: (s) {
                        _clientNameController.text = s;
                        setState(() => _showClientSuggestions = false);
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _items.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Dismissible(
                          key: Key('item_$index'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => _deleteItem(index),
                          child: _buildItemCard(item, index),
                        );
                      },
                    ),
            ),
            if (_isAddingItem) _buildAddItemPanel(),
            _buildBottomBar(),
          ],
        ),
      ),
      floatingActionButton: _isAddingItem || _items.isNotEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() => _isAddingItem = true),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un article'),
              backgroundColor: const Color(0xFF2563EB),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Aucun article',
              style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Appuyez sur + pour ajouter un article',
              style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildItemCard(InvoiceItem item, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shadowColor: Colors.blue.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Constants.cardRadius),
        side: BorderSide(color: Colors.grey.withAlpha(30)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shopping_bag, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.quantity} × ${formatNumber(item.unitPrice)} FCFA',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sous-total : ${formatCurrency(item.subtotal)}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit, color: Colors.blue[700], size: 20),
              onPressed: () => _editItem(index),
              tooltip: 'Modifier',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddItemPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                    _quantityController.clear();
                    _priceController.clear();
                    _selectedProduct = null;
                  });
                },
              )
            ],
          ),
          const SizedBox(height: 12),
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
                  decoration: InputDecoration(
                    labelText: 'Quantité *',
                    prefixIcon: const Icon(Icons.numbers),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  decoration: InputDecoration(
                    labelText: 'Prix unitaire (FCFA)',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          LastPriceHint(
            lastPrice: _selectedProduct == null
                ? null
                : _clientPrices[_selectedProduct!.name.trim().toLowerCase()],
            clientName: _clientNameController.text,
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.check),
            label: const Text('Ajouter l\'article'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(List<String> items, {required void Function(String) onSelect}) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 140),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[100]),
        itemBuilder: (context, i) {
          return ListTile(
            dense: true,
            leading: Icon(Icons.history, size: 16, color: Colors.grey[400]),
            title: Text(items[i], style: const TextStyle(fontSize: 14)),
            onTap: () => onSelect(items[i]),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          if (_items.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total à payer',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatCurrency(_calculateTotal()),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_items.length} article${_items.length > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_isAddingItem && _items.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _isAddingItem = true),
                    icon: const Icon(Icons.add, color: Color(0xFF2563EB)),
                    label: const Text('Ajouter', style: TextStyle(color: Color(0xFF2563EB))),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: Color(0xFF2563EB)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _finalizeInvoice,
                    icon: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check_circle),
                    label: Text(_isLoading ? 'Enregistrement...' : 'Finaliser'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ItemEditDialog extends StatefulWidget {
  final InvoiceItem item;
  final Function(InvoiceItem) onSave;

  const _ItemEditDialog({required this.item, required this.onSave});

  @override
  State<_ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<_ItemEditDialog> {
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
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _save() {
    final quantity = int.tryParse(_quantityController.text);
    final price = double.tryParse(_priceController.text);
    if (quantity == null || quantity <= 0 || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valeurs invalides'), backgroundColor: Colors.red),
      );
      return;
    }
    final updated = widget.item.copyWith(
      name: _nameController.text.trim().isEmpty ? 'Sans nom' : _nameController.text.trim(),
      quantity: quantity,
      unitPrice: price,
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier l\'article'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Nom',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
                  decoration: InputDecoration(
                    labelText: 'Quantité',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  decoration: InputDecoration(
                    labelText: 'Prix unitaire',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}