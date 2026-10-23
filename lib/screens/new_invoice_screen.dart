// lib/screens/new_invoice_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/invoice.dart';
import '../models/product.dart';
import '../services/storage_service.dart';
import '../services/history_service.dart';
import '../services/client_price_index.dart';
import '../services/invoice_repository.dart';
import '../utils/formatters.dart';
import '../utils/constants.dart';
import '../utils/text_utils.dart';
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
  final FocusNode _clientFocusNode = FocusNode();

  // Dernier prix : le prix n'est pré-rempli que tant que l'utilisateur ne l'a
  // pas modifié à la main. Le drapeau est remis à false quand le produit change.
  bool _priceTouched = false;

  // Nom appliqué par une suggestion : tant que le champ garde ce texte, la
  // liste de suggestions reste fermée (elle ne se rouvre pas au focus).
  String? _lastAppliedClientName;
  bool _clientOptionsSuppressed = false;

  // Erreurs de saisie affichées sous les champs (le panneau reste ouvert).
  String? _quantityError;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clientNameController.addListener(_onClientNameChanged);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (widget.initialInvoice != null) {
      _clientNameController.text = widget.initialInvoice!.clientName;
      _items.addAll(widget.initialInvoice!.items.map((item) => item.copyWith()));
    } else {
      final draft = await _storageService.loadDraft();
      if (!mounted) return;
      if (draft != null) {
        // Un brouillon peut avoir un client vide : ne remplace pas le champ
        // par une chaîne vide inutile.
        if (draft.clientName.trim().isNotEmpty) {
          _clientNameController.text = draft.clientName;
        }
        _items.addAll(draft.items);
      }
    }
    // Garantit que les derniers prix sont disponibles (chargement unique).
    await InvoiceRepository().load();
    if (!mounted) return;
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
    // Sauvegarde avant de libérer les contrôleurs : _saveDraft lit encore
    // le nom du client.
    _saveDraft();
    _clientNameController.removeListener(_onClientNameChanged);
    _clientNameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _clientFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveDraft() async {
    if (_items.isEmpty && _clientNameController.text.trim().isEmpty) {
      await _storageService.clearDraft();
      return;
    }
    // Le nom vide est autorisé dans le brouillon : « Client inconnu » ne doit
    // pas être stocké à la place d'un champ resté vide.
    final draft = Invoice(
      id: 'draft',
      clientName: _clientNameController.text.trim(),
      createdAt: DateTime.now(),
      items: List.from(_items),
    );
    await _storageService.saveDraft(draft);
  }

  // ---------- Client / dernier prix ----------

  /// Nom du client connu correspondant exactement au texte saisi (null tant
  /// que la saisie n'est pas résolue).
  String? get _resolvedClientName {
    final query = normalizeKey(_clientNameController.text);
    if (query.isEmpty) return null;
    for (final name in ClientPriceIndex().clientNames()) {
      if (normalizeKey(name) == query) return name;
    }
    return null;
  }

  /// Dernière vente du produit sélectionné au client résolu (synchrone).
  LastSale? get _lastSale {
    final product = _selectedProduct;
    if (product == null) return null;
    if (_resolvedClientName == null) return null;
    return ClientPriceIndex()
        .lastSale(_clientNameController.text, product.name);
  }

  /// Pré-remplit (ou vide) le champ prix à partir du dernier prix connu, sauf
  /// si l'utilisateur a déjà saisi un prix à la main.
  void _syncPriceFromLastSale() {
    if (_priceTouched) return;
    final sale = _lastSale;
    final text = sale == null ? '' : sale.price.toString();
    if (_priceController.text == text) return;
    _priceController.text = text;
  }

  void _onClientNameChanged() {
    if (!mounted) return;
    final text = _clientNameController.text;
    setState(() {
      if (_lastAppliedClientName != null &&
          text.trim() != _lastAppliedClientName) {
        // L'utilisateur retape : les suggestions redeviennent disponibles.
        _lastAppliedClientName = null;
        _clientOptionsSuppressed = false;
      }
      _syncPriceFromLastSale();
    });
  }

  /// Suggestions calculées de façon SYNCHRONE (aucun await, donc aucune course).
  Iterable<String> _buildClientOptions(TextEditingValue value) {
    if (_clientOptionsSuppressed) return const <String>[];
    final query = normalizeKey(value.text);
    if (query.isEmpty) return const <String>[];

    final names = ClientPriceIndex().clientNames();
    // Nom déjà complet : plus rien à proposer, la liste reste fermée.
    if (names.any((name) => normalizeKey(name) == query)) {
      return const <String>[];
    }

    final matches = <String>[];
    for (final name in names) {
      if (normalizeKey(name).contains(query)) matches.add(name);
    }

    // Les noms qui commencent par la recherche d'abord ; à égalité, l'ordre de
    // l'index (du plus récent au plus ancien) est conservé.
    final ranked = matches.asMap().entries.toList()
      ..sort((a, b) {
        final aStarts = normalizeKey(a.value).startsWith(query) ? 0 : 1;
        final bStarts = normalizeKey(b.value).startsWith(query) ? 0 : 1;
        if (aStarts != bStarts) return aStarts - bStarts;
        return a.key - b.key;
      });
    return ranked.map((entry) => entry.value).take(6).toList();
  }

  /// Seul client connu commençant par la saisie courante (quand elle n'est pas
  /// encore résolue) : affiché en aide discrète sous le champ.
  String? get _singleStartingClient {
    final query = normalizeKey(_clientNameController.text);
    if (query.isEmpty) return null;
    final names = ClientPriceIndex().clientNames();
    if (names.any((name) => normalizeKey(name) == query)) return null;
    final starts = names
        .where((name) => normalizeKey(name).startsWith(query))
        .toList();
    return starts.length == 1 ? starts.single : null;
  }

  void _applyClientName(String name) {
    _lastAppliedClientName = name;
    _clientOptionsSuppressed = true;
    _clientNameController.text = name;
    if (!mounted) return;
    setState(_syncPriceFromLastSale);
  }

  // ---------- Articles ----------

  void _addItem() {
    final quantity = int.tryParse(_quantityController.text.trim());
    final price = int.tryParse(_priceController.text.trim());

    setState(() {
      _quantityError = (quantity == null || quantity <= 0)
          ? 'Quantité obligatoire (entier supérieur à 0)'
          : null;
      _priceError = (price == null || price <= 0)
          ? 'Prix obligatoire (entier supérieur à 0)'
          : null;
    });

    if (_selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un produit'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Saisie invalide : le panneau reste ouvert et l'article n'est pas ajouté.
    if (_quantityError != null || _priceError != null) return;

    final productName = _selectedProduct!.name;
    final item = InvoiceItem(
      name: productName,
      quantity: quantity!,
      unitPrice: price!,
    );

    setState(() {
      _items.add(item);
      _quantityController.clear();
      _priceController.clear();
      _selectedProduct = null;
      _isAddingItem = false;
      _quantityError = null;
      _priceError = null;
      _priceTouched = false;
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

  /// Retrait immédiat + possibilité d'annuler : l'article retrouve alors sa
  /// position d'origine. Le brouillon est sauvegardé dans les deux cas.
  void _removeItem(InvoiceItem item) {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) return;

    setState(() => _items.removeAt(index));
    _saveDraft();

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Article supprimé'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'ANNULER',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              final position = index.clamp(0, _items.length);
              _items.insert(position, item);
            });
            _saveDraft();
          },
        ),
      ),
    );
  }

  /// Facture en cours de saisie : le total affiché est toujours son
  /// `payableTotal` (cet écran ne gère ni remise ni TVA).
  Invoice get _previewInvoice => Invoice(
        id: 'draft',
        clientName: _clientNameController.text.trim(),
        createdAt: DateTime.now(),
        items: List.from(_items),
      );

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
      await InvoiceRepository().add(invoice);
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
        _selectedProduct = null;
        _priceTouched = false;
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

  /// Efface le brouillon, en demandant confirmation quand il contient des
  /// articles.
  Future<void> _clearDraft() async {
    if (_items.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Constants.cardRadius),
          ),
          title: const Text('Effacer le brouillon ?'),
          content: Text(
            'Le brouillon contient ${_items.length} article'
            '${_items.length > 1 ? 's' : ''}. Cette action est irréversible.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Effacer', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await _storageService.clearDraft();
    if (!mounted) return;
    setState(() {
      _clientNameController.clear();
      _items.clear();
      _isAddingItem = false;
      _selectedProduct = null;
      _priceTouched = false;
      _quantityController.clear();
      _priceController.clear();
      _quantityError = null;
      _priceError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Brouillon effacé'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
        // Nouveau produit : le pré-remplissage redevient autorisé.
        _priceTouched = false;
        _syncPriceFromLastSale();
      }
    });
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
            onPressed: _clearDraft,
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildClientField(),
                  if (_singleStartingClient != null)
                    _buildExistingClientLine(_singleStartingClient!),
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
                          key: ValueKey(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (_) => _removeItem(item),
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

  Widget _buildClientField() {
    return RawAutocomplete<String>(
      textEditingController: _clientNameController,
      focusNode: _clientFocusNode,
      optionsBuilder: _buildClientOptions,
      displayStringForOption: (option) => option,
      onSelected: (option) => _applyClientName(option),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            labelText: 'Nom du client (optionnel)',
            prefixIcon: Icon(Icons.person, color: Colors.blue[700]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Constants.inputRadius),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
        );
      },
      optionsViewBuilder: (context, onSelect, options) {
        if (_clientOptionsSuppressed) return const SizedBox.shrink();
        final entries = options.toList();
        if (entries.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 200,
                maxWidth: MediaQuery.sizeOf(context).width - 32,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final name = entries[i];
                  return ListTile(
                    key: ValueKey('client-option-$name'),
                    dense: true,
                    leading: Icon(Icons.history, size: 16, color: Colors.grey[400]),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    onTap: () => onSelect(name),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExistingClientLine(String name) {
    return InkWell(
      onTap: () => _applyClientName(name),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, left: 4, right: 4, bottom: 2),
        child: Row(
          children: [
            Icon(Icons.person_search, size: 15, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Client existant : $name — Utiliser',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[700]),
              ),
            ),
          ],
        ),
      ),
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
      shadowColor: Colors.blue.withValues(alpha: 0.05),
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
    final sale = _lastSale;
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
                    _priceTouched = false;
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
                  onChanged: (_) {
                    if (_quantityError != null) {
                      setState(() => _quantityError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Quantité *',
                    prefixIcon: const Icon(Icons.numbers),
                    errorText: _quantityError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) {
                    // Saisie manuelle : le pré-remplissage ne doit plus écraser.
                    _priceTouched = true;
                    if (_priceError != null) {
                      setState(() => _priceError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Prix unitaire (FCFA)',
                    prefixIcon: const Icon(Icons.attach_money),
                    errorText: _priceError,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          LastPriceHint(
            lastPrice: sale?.price,
            lastDate: sale?.date,
            clientName: _clientNameController.text,
            onUsePrice: sale == null
                ? null
                : () {
                    setState(() {
                      _priceController.text = sale.price.toString();
                      _priceTouched = true;
                    });
                  },
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
                          formatCurrency(_previewInvoice.payableTotal),
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
    final price = int.tryParse(_priceController.text);
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
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
