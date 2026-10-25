// lib/screens/new_invoice_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/invoice.dart';
import '../models/product.dart';
import '../services/storage_service.dart';
import '../services/history_service.dart';
import '../services/client_price_index.dart';
import '../services/invoice_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../utils/text_utils.dart';
import '../widgets/product_grid_sheet.dart';
import '../widgets/last_price_hint.dart';
import '../widgets/ui/ui.dart';

class NewInvoiceScreen extends StatefulWidget {
  final VoidCallback onInvoiceCreated;
  final Invoice? initialInvoice;
  const NewInvoiceScreen({
    super.key,
    required this.onInvoiceCreated,
    this.initialInvoice,
  });

  @override
  State<NewInvoiceScreen> createState() => _NewInvoiceScreenState();
}

class _NewInvoiceScreenState extends State<NewInvoiceScreen>
    with WidgetsBindingObserver {
  final _clientNameController = TextEditingController();
  final _storageService = StorageService();
  final _historyService = HistoryService();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<InvoiceItem> _items = [];
  bool _isLoading = false;
  final FocusNode _clientFocusNode = FocusNode();

  // Nom appliqué par une suggestion : tant que le champ garde ce texte, la
  // liste de suggestions reste fermée (elle ne se rouvre pas au focus).
  String? _lastAppliedClientName;
  bool _clientOptionsSuppressed = false;

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
      _items.addAll(
        widget.initialInvoice!.items.map((item) => item.copyWith()),
      );
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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

  // ---------- Client ----------

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
    final starts =
        names.where((name) => normalizeKey(name).startsWith(query)).toList();
    return starts.length == 1 ? starts.single : null;
  }

  void _applyClientName(String name) {
    _lastAppliedClientName = name;
    _clientOptionsSuppressed = true;
    _clientNameController.text = name;
    if (!mounted) return;
    setState(() {});
  }

  // ---------- Articles ----------

  /// Ouvre la feuille « Nouvel article » (bottom sheet) : la liste et le
  /// total suivent dès la validation.
  void _openAddItemSheet() {
    FocusScope.of(context).unfocus();
    final scaffold = _scaffoldKey.currentState;
    if (scaffold == null) return;

    late PersistentBottomSheetController controller;
    controller = scaffold.showBottomSheet(
      (sheetContext) => _AddItemSheet(
        clientController: _clientNameController,
        onAdd: (item) {
          controller.close();
          _onItemAdded(item);
        },
        onClose: () => controller.close(),
      ),
    );
  }

  void _onItemAdded(InvoiceItem item) {
    if (!mounted) return;
    setState(() => _items.add(item));
    _historyService.saveProductName(item.name);
    _saveDraft();
  }

  void _editItem(int index) {
    showDialog(
      context: context,
      builder: (_) => _ItemEditDialog(
        item: _items[index],
        onSave: (updated) {
          if (!mounted) return;
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

    HapticFeedback.lightImpact();
    setState(() => _items.removeAt(index));
    _saveDraft();

    AppSnack.show(
      context,
      'Article supprimé',
      actionLabel: 'ANNULER',
      onAction: () {
        if (!mounted) return;
        setState(() {
          final position = index.clamp(0, _items.length);
          _items.insert(position, item);
        });
        _saveDraft();
      },
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
      AppSnack.info(
        context,
        'Ajoutez au moins un article avant de finaliser',
      );
      return;
    }

    HapticFeedback.lightImpact();
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
        _isLoading = false;
      });

      AppSnack.success(context, 'Facture enregistrée avec succès !');
      widget.onInvoiceCreated();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppSnack.error(context, 'Erreur lors de la sauvegarde: $e');
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
              child: Text(
                'Effacer',
                style: TextStyle(color: AppColors.of(context).danger),
              ),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }

    await _storageService.clearDraft();
    if (!mounted) return;
    setState(() {
      _clientNameController.clear();
      _items.clear();
    });
    AppSnack.neutral(context, 'Brouillon effacé');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: const Text('Nouvelle Facture'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Effacer le brouillon',
            onPressed: _clearDraft,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Ajouter un article',
            onPressed: _openAddItemSheet,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(
          children: [
            _buildClientSection(),
            Expanded(
              child: _items.isEmpty ? _buildEmptyState() : _buildItemsList(),
            ),
            StickyTotalBar(
              total: _previewInvoice.payableTotal,
              itemCount: _items.length,
              actionLabel: 'Finaliser',
              isLoading: _isLoading,
              onAction: _items.isEmpty ? null : _finalizeInvoice,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientSection() {
    final colors = AppColors.of(context);

    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClientAvatar(name: _clientNameController.text),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildClientField()),
            ],
          ),
          if (_singleStartingClient != null)
            _buildExistingClientLine(_singleStartingClient!),
        ],
      ),
    );
  }

  Widget _buildClientField() {
    final colors = AppColors.of(context);
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
          decoration: const InputDecoration(
            labelText: 'Nom du client (optionnel)',
            hintText: 'Ex. Aïssatou Diop',
            prefixIcon: Icon(Icons.person_outline, size: 20),
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
            elevation: 6,
            borderRadius: BorderRadius.circular(AppRadius.md),
            color: colors.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 220,
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
                    leading: Icon(
                      Icons.history,
                      size: 18,
                      color: colors.textMuted,
                    ),
                    title: Text(
                      name,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onTap: () => onSelect(name),
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
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: InkWell(
        onTap: () => _applyClientName(name),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              Icon(Icons.person_search, size: 16, color: colors.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Client existant : $name — Utiliser',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textBody,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: Icons.shopping_cart_outlined,
      title: 'Aucun article',
      message: 'Ajoutez votre premier article pour construire la facture.',
      actionLabel: 'Ajouter un article',
      onAction: _openAddItemSheet,
    );
  }

  Widget _buildItemsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: _buildDismissBackground(),
            onDismissed: (_) => _removeItem(item),
            child: _buildItemCard(item, index),
          ),
        );
      },
    );
  }

  Widget _buildDismissBackground() {
    final colors = AppColors.of(context);
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.danger,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Icon(Icons.delete_outline, color: colors.surface, size: 22),
    );
  }

  Widget _buildItemCard(InvoiceItem item, int index) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.shopping_bag_outlined,
                color: colors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textStrong,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${item.quantity} × ${formatNumber(item.unitPrice)} FCFA',
                  style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Sous-total : ${formatCurrency(item.subtotal)}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: colors.primary,
            onPressed: () => _editItem(index),
            tooltip: 'Modifier',
          ),
        ],
      ),
    );
  }
}

/// Feuille « Nouvel article » : produit, quantité, prix et dernier prix.
class _AddItemSheet extends StatefulWidget {
  final TextEditingController clientController;
  final ValueChanged<InvoiceItem> onAdd;
  final VoidCallback onClose;

  const _AddItemSheet({
    required this.clientController,
    required this.onAdd,
    required this.onClose,
  });

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  Product? _selectedProduct;
  bool _priceTouched = false;
  String? _quantityError;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    widget.clientController.addListener(_onClientChanged);
  }

  @override
  void dispose() {
    widget.clientController.removeListener(_onClientChanged);
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String? get _resolvedClientName {
    final query = normalizeKey(widget.clientController.text);
    if (query.isEmpty) return null;
    for (final name in ClientPriceIndex().clientNames()) {
      if (normalizeKey(name) == query) return name;
    }
    return null;
  }

  LastSale? get _lastSale {
    final product = _selectedProduct;
    if (product == null || _resolvedClientName == null) return null;
    return ClientPriceIndex()
        .lastSale(widget.clientController.text, product.name);
  }

  void _syncPriceFromLastSale() {
    if (_priceTouched) return;
    final sale = _lastSale;
    final text = sale == null ? '' : sale.price.toString();
    if (_priceController.text == text) return;
    _priceController.text = text;
  }

  /// Le client saisi derrière la feuille doit rafraîchir l'encart et le prix.
  void _onClientChanged() {
    if (!mounted) return;
    setState(_syncPriceFromLastSale);
  }

  void _openProductGrid() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (ctx) => ProductGridSheet(
        onProductSelected: (product) {
          if (!mounted) return;
          setState(() {
            final isSameProduct = _selectedProduct?.id == product.id;
            _selectedProduct = product;
            if (!isSameProduct) {
              // Nouveau produit : le pré-remplissage redevient autorisé.
              _priceTouched = false;
              _syncPriceFromLastSale();
            }
          });
        },
      ),
    );
  }

  void _submit() {
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
      AppSnack.info(context, 'Veuillez sélectionner un produit');
      return;
    }

    // Saisie invalide : la feuille reste ouverte et l'article n'est pas ajouté.
    if (_quantityError != null || _priceError != null) return;

    final item = InvoiceItem(
      name: _selectedProduct!.name,
      quantity: quantity!,
      unitPrice: price!,
    );
    widget.onAdd(item);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selectedProduct = _selectedProduct;
    final sale = _lastSale;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.add_box_outlined, color: colors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Nouvel article',
                    style: textTheme.titleMedium?.copyWith(
                      color: colors.textStrong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Fermer',
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            InkWell(
              onTap: _openProductGrid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: colors.textMuted, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        selectedProduct?.name ??
                            'Appuyez pour choisir un produit',
                        style: textTheme.bodyLarge?.copyWith(
                          color: selectedProduct != null
                              ? colors.textStrong
                              : colors.textMuted,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more, color: colors.textMuted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            QuantityStepper(
              controller: _quantityController,
              onChanged: (_) {
                if (_quantityError != null) {
                  setState(() => _quantityError = null);
                }
              },
            ),
            if (_quantityError != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: AppSpacing.xs,
                ),
                child: Text(
                  _quantityError!,
                  style: textTheme.bodySmall?.copyWith(color: colors.danger),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
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
                prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                errorText: _priceError,
              ),
            ),
            LastPriceHint(
              lastPrice: sale?.price,
              lastDate: sale?.date,
              clientName: widget.clientController.text,
              onUsePrice: sale == null
                  ? null
                  : () {
                      setState(() {
                        _priceController.text = sale.price.toString();
                        _priceTouched = true;
                      });
                    },
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check, size: 20),
              label: const Text('Ajouter l\'article'),
            ),
          ],
        ),
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
    _quantityController =
        TextEditingController(text: widget.item.quantity.toString());
    _priceController =
        TextEditingController(text: widget.item.unitPrice.toString());
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
      AppSnack.error(context, 'Valeurs invalides');
      return;
    }
    final updated = widget.item.copyWith(
      name: _nameController.text.trim().isEmpty
          ? 'Sans nom'
          : _nameController.text.trim(),
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
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Quantité'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration:
                        const InputDecoration(labelText: 'Prix unitaire'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
