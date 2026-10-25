// lib/screens/invoice_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/product.dart';
import '../services/client_price_index.dart';
import '../services/invoice_repository.dart';
import '../services/pdf_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/last_price_hint.dart';
import '../widgets/product_grid_sheet.dart';
import '../widgets/ui/ui.dart';
import 'new_invoice_screen.dart';
import 'receipt_preview_screen.dart';

class InvoiceDetailScreen extends StatefulWidget {
  final Invoice invoice;
  final VoidCallback onInvoiceUpdated;
  const InvoiceDetailScreen({
    super.key,
    required this.invoice,
    required this.onInvoiceUpdated,
  });

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

/// Brouillon de saisie d'une ligne : les textes bruts sont conservés pour que
/// le total se mette à jour à chaque frappe et pour que la validation se fasse
/// au moment d'enregistrer.
class _ItemDraft {
  final String id;
  final String name;
  final String quantity;
  final String unitPrice;

  const _ItemDraft({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  factory _ItemDraft.fromItem(InvoiceItem item) => _ItemDraft(
        id: item.id,
        name: item.name,
        quantity: item.quantity.toString(),
        unitPrice: item.unitPrice.toString(),
      );

  _ItemDraft copyWith({String? name, String? quantity, String? unitPrice}) =>
      _ItemDraft(
        id: id,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
      );

  String get trimmedName => name.trim();

  int get quantityValue => int.tryParse(quantity.trim()) ?? 0;

  int get unitPriceValue => int.tryParse(unitPrice.trim()) ?? 0;

  bool get isValidName => trimmedName.isNotEmpty;

  bool get isValidQuantity => quantityValue > 0;

  bool get isValidPrice => unitPriceValue > 0;

  bool get hasError => !isValidName || !isValidQuantity || !isValidPrice;

  InvoiceItem toItem() => InvoiceItem(
        id: id,
        name: trimmedName,
        quantity: quantityValue,
        unitPrice: unitPriceValue,
      );
}

enum _DetailAction { archiver, dupliquer, supprimer }

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  late Invoice _invoice;

  /// Instantané de la facture enregistrée à l'entrée en édition : « Annuler »
  /// restaure exactement cet état.
  late Invoice _original;

  bool _isEditing = false;
  bool _isSaving = false;
  bool _isSharing = false;
  late TextEditingController _clientNameController;
  late TextEditingController _notesController;
  late TextEditingController _discountController;
  late TextEditingController _taxRateController;
  final InvoiceRepository _repository = InvoiceRepository();
  final ClientPriceIndex _priceIndex = ClientPriceIndex();
  final PdfService _pdfService = PdfService();

  // Brouillons de l'édition : les valeurs saisies y remontent à chaque frappe,
  // sans toucher à la facture enregistrée.
  late InvoiceStatus _draftStatus;
  List<_ItemDraft> _draftItems = [];
  bool _showItemErrors = false;
  final Map<String, GlobalKey> _itemKeys = {};

  // Ajout d'articles en mode édition (via la bibliothèque produits)
  bool _isAddingItem = false;
  Product? _selectedProduct;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;

  // Erreurs de saisie affichées sous les champs (la saisie reste ouverte).
  String? _quantityError;
  String? _priceError;
  String? _discountError;
  String? _taxRateError;

  @override
  void initState() {
    super.initState();
    _invoice = widget.invoice;
    _original = widget.invoice;
    _draftStatus = _invoice.status;
    _clientNameController = TextEditingController(text: _invoice.clientName);
    _notesController = TextEditingController(text: _invoice.notes ?? '');
    _discountController =
        TextEditingController(text: _amountInputValue(_invoice.discount));
    _taxRateController =
        TextEditingController(text: _taxRateInputValue(_invoice.taxRate));
    _quantityController = TextEditingController();
    _priceController = TextEditingController();
    _clientNameController.addListener(_onClientNameChangedForPrices);
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
    if (!mounted) return;
    setState(() {});
  }

  /// Dernière vente de [product] au client saisi, en excluant la facture
  /// en cours d'édition.
  LastSale? _lastSaleFor(Product product) => _priceIndex.lastSale(
        _clientNameController.text,
        product.name,
        excludeInvoiceId: _invoice.id,
      );

  String _formatDate(DateTime date) =>
      DateFormat('dd MMMM yyyy à HH:mm', 'fr_FR').format(date);

  /// Valeur affichée dans un champ montant (FCFA entier, vide si 0).
  String _amountInputValue(int value) => value == 0 ? '' : value.toString();

  /// Valeur affichée dans le champ TVA (pourcentage entier, vide si 0).
  String _taxRateInputValue(double value) =>
      value == 0 ? '' : value.round().toString();

  int _parseAmount(String text) => int.tryParse(text.trim()) ?? 0;

  String get _reference => _invoice.id.length >= 6
      ? _invoice.id.substring(_invoice.id.length - 6)
      : _invoice.id;

  // ---------- Édition / annulation ----------

  void _toggleEdit() {
    setState(() {
      if (_isEditing) {
        _restoreOriginal();
        _isEditing = false;
      } else {
        _original = _invoice;
        _prepareDraftsFrom(_invoice);
        _isEditing = true;
      }
      _discountError = null;
      _taxRateError = null;
      _quantityError = null;
      _priceError = null;
      _showItemErrors = false;
      _isAddingItem = false;
      _selectedProduct = null;
      _quantityController.clear();
      _priceController.clear();
    });
  }

  void _prepareDraftsFrom(Invoice source) {
    _draftStatus = source.status;
    _draftItems = source.items.map(_ItemDraft.fromItem).toList();
    _itemKeys.clear();
    for (final draft in _draftItems) {
      _itemKeys[draft.id] = GlobalKey();
    }
  }

  /// « Annuler » : restaure TOUT (client, notes, remise, TVA, statut, articles).
  void _restoreOriginal() {
    _clientNameController.text = _original.clientName;
    _notesController.text = _original.notes ?? '';
    _discountController.text = _amountInputValue(_original.discount);
    _taxRateController.text = _taxRateInputValue(_original.taxRate);
    _prepareDraftsFrom(_original);
  }

  void _updateDraft(_ItemDraft updated) {
    final index = _draftItems.indexWhere((draft) => draft.id == updated.id);
    if (index == -1) return;
    setState(() => _draftItems[index] = updated);
  }

  void _deleteDraftItem(_ItemDraft draft) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Confirmer la suppression'),
        content: Text('Supprimer "${draft.name.trim()}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (!mounted) return;
              HapticFeedback.lightImpact();
              setState(() {
                _draftItems.removeWhere(
                  (candidate) => candidate.id == draft.id,
                );
                _itemKeys.remove(draft.id);
              });
            },
            child: Text(
              'Supprimer',
              style: TextStyle(color: AppColors.of(context).danger),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Total en direct ----------

  /// Facture construite à partir des brouillons (édition) ou de la facture
  /// enregistrée : le total affiché suit toujours l'état courant.
  Invoice get _displayInvoice {
    if (!_isEditing) return _invoice;
    return Invoice(
      id: _invoice.id,
      clientName: _clientNameController.text.trim(),
      createdAt: _invoice.createdAt,
      items: _draftItems.map((draft) => draft.toItem()).toList(),
      status: _draftStatus,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      discount: _parseAmount(_discountController.text),
      taxRate: (int.tryParse(_taxRateController.text.trim()) ?? 0).toDouble(),
    );
  }

  // ---------- Ajout d'article ----------

  void _openProductGrid() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).surface,
      builder: (ctx) => ProductGridSheet(onProductSelected: _onProductSelected),
    );
  }

  void _onProductSelected(Product product) {
    setState(() {
      final isSameProduct = _selectedProduct?.id == product.id;
      _selectedProduct = product;
      if (!isSameProduct) {
        // Pré-remplit le prix avec le dernier prix vendu à ce client,
        // hors facture en cours d'édition.
        final lastSale = _lastSaleFor(product);
        if (lastSale != null) {
          _priceController.text = lastSale.price.toString();
        } else {
          _priceController.clear();
        }
      }
    });
  }

  void _addNewItem() {
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

    // Saisie invalide : le panneau reste ouvert et l'article n'est pas ajouté.
    if (_quantityError != null || _priceError != null) return;

    final item = InvoiceItem(
      name: _selectedProduct!.name,
      quantity: quantity!,
      unitPrice: price!,
    );
    setState(() {
      _draftItems.add(_ItemDraft.fromItem(item));
      _itemKeys[item.id] = GlobalKey();
      _isAddingItem = false;
      _selectedProduct = null;
      _quantityController.clear();
      _priceController.clear();
      _quantityError = null;
      _priceError = null;
    });
  }

  Widget _buildAddItemPanel() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final selectedProduct = _selectedProduct;
    final lastSale =
        selectedProduct == null ? null : _lastSaleFor(selectedProduct);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.add_box_outlined, color: colors.primary, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Nouvel article',
                  style: textTheme.titleSmall?.copyWith(
                    color: colors.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Fermer',
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
            lastPrice: lastSale?.price,
            lastDate: lastSale?.date,
            clientName: _clientNameController.text,
            onUsePrice: lastSale == null
                ? null
                : () => setState(() {
                      _priceController.text = lastSale.price.toString();
                    }),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _addNewItem,
            icon: const Icon(Icons.check, size: 20),
            label: const Text('Ajouter l\'article'),
          ),
        ],
      ),
    );
  }

  // ---------- Enregistrement ----------

  void _scrollToFirstItemError() {
    _ItemDraft? firstError;
    for (final draft in _draftItems) {
      if (draft.hasError) {
        firstError = draft;
        break;
      }
    }
    if (firstError == null) return;
    final draftId = firstError.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _itemKeys[draftId]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _saveChanges() async {
    // Remise et TVA sont saisies en entiers (FCFA / pourcentage).
    final discount = _parseAmount(_discountController.text);
    final taxRate = int.tryParse(_taxRateController.text.trim()) ?? 0;
    final subtotal = _draftItems.fold<int>(
      0,
      (sum, draft) => sum + draft.quantityValue * draft.unitPriceValue,
    );

    if (_draftItems.isEmpty) {
      AppSnack.info(
          context, 'Ajoutez au moins un article avant d\'enregistrer');
      return;
    }

    final discountError = discount > subtotal
        ? 'Remise limitée au sous-total (${formatCurrency(subtotal)})'
        : null;
    final taxRateError =
        taxRate > 100 ? 'La TVA doit être comprise entre 0 et 100' : null;
    final hasItemError = _draftItems.any((draft) => draft.hasError);

    if (hasItemError || discountError != null || taxRateError != null) {
      // Saisie invalide : on reste en édition et on n'enregistre rien.
      setState(() {
        _showItemErrors = true;
        _discountError = discountError;
        _taxRateError = taxRateError;
      });
      if (hasItemError) _scrollToFirstItemError();
      return;
    }

    setState(() {
      _isSaving = true;
      _discountError = null;
      _taxRateError = null;
    });
    // Construit explicitement la facture (plutôt que copyWith) pour permettre
    // d'effacer réellement les notes quand le champ est vidé.
    final updatedInvoice = Invoice(
      id: _invoice.id,
      clientName: _clientNameController.text.trim().isEmpty
          ? 'Client inconnu'
          : _clientNameController.text.trim(),
      createdAt: _invoice.createdAt,
      items: _draftItems.map((draft) => draft.toItem()).toList(),
      status: _draftStatus,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      discount: discount,
      taxRate: taxRate.toDouble(),
    );

    await _repository.update(updatedInvoice);
    if (!mounted) return;

    setState(() {
      _invoice = updatedInvoice;
      _original = updatedInvoice;
      _isEditing = false;
      _isSaving = false;
      _showItemErrors = false;
    });

    widget.onInvoiceUpdated();
    if (!mounted) return;
    AppSnack.success(context, 'Facture mise à jour');
  }

  Future<void> _deleteInvoice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Supprimer la facture ?'),
        content: const Text('Cette action est irréversible.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Supprimer',
              style: TextStyle(color: AppColors.of(context).danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    HapticFeedback.lightImpact();
    await _repository.removeByIds([_invoice.id]);

    if (!mounted) return;
    widget.onInvoiceUpdated();
    Navigator.pop(context);
  }

  /// L'archivage ne persiste QUE le statut de la facture enregistrée : les
  /// modifications d'édition non sauvegardées ne partent jamais avec lui.
  Future<void> _toggleArchive() async {
    final newStatus = _invoice.status == InvoiceStatus.archivee
        ? InvoiceStatus.enCours
        : InvoiceStatus.archivee;
    final updated = _invoice.copyWith(status: newStatus);
    await _repository.update(updated);
    if (!mounted) return;
    setState(() {
      _invoice = updated;
      _original = updated;
      _draftStatus = newStatus;
    });
    widget.onInvoiceUpdated();
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
      MaterialPageRoute(
        builder: (_) => NewInvoiceScreen(
          onInvoiceCreated: widget.onInvoiceUpdated,
          initialInvoice: dup,
        ),
      ),
    );
  }

  void _onMenuAction(_DetailAction action) {
    switch (action) {
      case _DetailAction.archiver:
        _toggleArchive();
        break;
      case _DetailAction.dupliquer:
        _duplicateInvoice();
        break;
      case _DetailAction.supprimer:
        _deleteInvoice();
        break;
    }
  }

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Partager la facture',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              _shareOption(
                ctx,
                icon: Icons.print_outlined,
                tone: _ShareTone.primary,
                label: 'Reçu thermique (58 / 80 mm)',
                subtitle: 'Bluetooth (Android) · Wi-Fi (Android + iPhone)',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReceiptPreviewScreen(invoice: _invoice),
                    ),
                  );
                },
              ),
              _shareOption(
                ctx,
                icon: Icons.picture_as_pdf,
                tone: _ShareTone.danger,
                label: 'Document PDF',
                subtitle: 'Idéal pour l\'impression',
                onTap: () => _shareWith(
                  ctx,
                  () => _pdfService.shareAsPdf(_invoice),
                  'Erreur PDF',
                ),
              ),
              _shareOption(
                ctx,
                icon: Icons.image_outlined,
                tone: _ShareTone.primary,
                label: 'Image PNG',
                subtitle: 'Pour partager sur WhatsApp, etc.',
                onTap: () => _shareWith(
                  ctx,
                  () => _pdfService.shareAsPng(_invoice),
                  'Erreur PNG',
                ),
              ),
              _shareOption(
                ctx,
                icon: Icons.photo_camera_outlined,
                tone: _ShareTone.success,
                label: 'Image JPG',
                subtitle: 'Format photo compressé',
                onTap: () => _shareWith(
                  ctx,
                  () => _pdfService.shareAsJpg(_invoice),
                  'Erreur JPG',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareWith(
    BuildContext sheetContext,
    Future<void> Function() action,
    String errorLabel,
  ) async {
    Navigator.pop(sheetContext);
    setState(() => _isSharing = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, '$errorLabel : $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Widget _shareOption(
    BuildContext ctx, {
    required IconData icon,
    required _ShareTone tone,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colors = AppColors.of(ctx);
    final Color color = switch (tone) {
      _ShareTone.primary => colors.primary,
      _ShareTone.success => colors.success,
      _ShareTone.danger => colors.danger,
    };
    return ListTile(
      minVerticalPadding: AppSpacing.md,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        label,
        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
              color: colors.textStrong,
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
            ),
      ),
      onTap: onTap,
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final display = _displayInvoice;

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier' : 'Détails'),
        actions: _isEditing ? _buildEditActions() : _buildViewActions(),
      ),
      body: Column(
        children: [
          if (_isEditing) _buildEditBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: AppSpacing.lg),
                  _buildStatusCard(),
                  const SizedBox(height: AppSpacing.lg),
                  _buildItemsSection(),
                  const SizedBox(height: AppSpacing.lg),
                  _buildTotalsCard(display),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  List<Widget> _buildViewActions() {
    final colors = AppColors.of(context);
    final isArchived = _invoice.status == InvoiceStatus.archivee;
    return [
      IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Modifier',
        onPressed: _toggleEdit,
      ),
      PopupMenuButton<_DetailAction>(
        icon: const Icon(Icons.more_horiz),
        tooltip: 'Plus d\'actions',
        onSelected: _onMenuAction,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _DetailAction.archiver,
            child: Text(isArchived ? 'Désarchiver' : 'Archiver'),
          ),
          const PopupMenuItem(
            value: _DetailAction.dupliquer,
            child: Text('Dupliquer'),
          ),
          PopupMenuItem(
            value: _DetailAction.supprimer,
            child: Text(
              'Supprimer',
              style: TextStyle(color: colors.danger),
            ),
          ),
        ],
      ),
      const SizedBox(width: AppSpacing.xs),
    ];
  }

  List<Widget> _buildEditActions() {
    final isArchived = _invoice.status == InvoiceStatus.archivee;
    return [
      IconButton(
        icon: Icon(isArchived ? Icons.unarchive : Icons.archive_outlined),
        onPressed: _isSaving ? null : _toggleArchive,
        tooltip: isArchived ? 'Désarchiver' : 'Archiver',
      ),
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: _isSaving ? null : _toggleEdit,
        tooltip: 'Annuler',
      ),
      IconButton(
        icon: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        onPressed: _isSaving ? null : _saveChanges,
        tooltip: 'Enregistrer',
      ),
      const SizedBox(width: AppSpacing.xs),
    ];
  }

  Widget _buildEditBanner() {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      color: colors.primary.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note, size: 20, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Modification en cours',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Hero(
                tag: 'invoice-icon-${_invoice.id}',
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colors.primary, colors.primaryStrong],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.receipt_long,
                      color: colors.onPrimary, size: 24),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FACTURE',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textMuted,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#$_reference',
                      style: textTheme.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(child: StatusBadge(status: _invoice.status)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(color: colors.border, height: 1),
          const SizedBox(height: AppSpacing.lg),
          if (_isEditing)
            TextField(
              controller: _clientNameController,
              decoration: const InputDecoration(
                labelText: 'Nom du client',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            )
          else
            Row(
              children: [
                ClientAvatar(name: _invoice.clientName),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Client',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _invoice.clientName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          color: colors.textStrong,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: colors.textMuted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _formatDate(_invoice.createdAt),
                  style: textTheme.bodySmall?.copyWith(color: colors.textBody),
                ),
              ),
            ],
          ),
          if (_isEditing) ..._buildEditFields(),
          if (!_isEditing &&
              _invoice.notes != null &&
              _invoice.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                _invoice.notes!,
                style: textTheme.bodyMedium?.copyWith(color: colors.textBody),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildEditFields() {
    final colors = AppColors.of(context);
    return [
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _discountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _discountError = null),
              decoration: InputDecoration(
                labelText: 'Remise (FCFA)',
                errorText: _discountError,
                prefixIcon: const Icon(Icons.percent, size: 20),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: TextField(
              controller: _taxRateController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _taxRateError = null),
              decoration: InputDecoration(
                labelText: 'TVA (%)',
                errorText: _taxRateError,
                prefixIcon: const Icon(Icons.receipt_outlined, size: 20),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _notesController,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: 'Notes (optionnel)',
          hintText: 'Ajoutez vos notes ici...',
          prefixIcon: Icon(Icons.description_outlined,
              size: 20, color: colors.textMuted),
        ),
      ),
    ];
  }

  Widget _buildStatusCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
              title: 'Statut', icon: Icons.local_shipping_outlined),
          const SizedBox(height: AppSpacing.md),
          StatusStepper(
            status: _displayInvoice.status,
            onChanged: _isEditing
                ? (status) => setState(() => _draftStatus = status)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    final colors = AppColors.of(context);
    final items = _isEditing
        ? _draftItems.map((draft) => draft.toItem()).toList()
        : _invoice.items;
    final display = _displayInvoice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Articles',
          subtitle: '${items.length} ligne${items.length > 1 ? 's' : ''} · '
              '${display.totalQuantity} unité${display.totalQuantity > 1 ? 's' : ''}',
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_isEditing)
          ..._draftItems.asMap().entries.map((entry) {
            final index = entry.key;
            final draft = entry.value;
            final itemKey = _itemKeys[draft.id] ??= GlobalKey();
            return Padding(
              key: itemKey,
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _EditableItemTile(
                  key: ValueKey(draft.id),
                  index: index,
                  draft: draft,
                  showErrors: _showItemErrors,
                  onChanged: _updateDraft,
                  onDelete: () => _deleteDraftItem(draft),
                ),
              ),
            );
          })
        else
          ..._invoice.items.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: _CompactItemView(
                  index: entry.key,
                  item: entry.value,
                ),
              ),
            );
          }),
        if (_isEditing) ...[
          if (_isAddingItem)
            _buildAddItemPanel()
          else
            OutlinedButton.icon(
              onPressed: () => setState(() => _isAddingItem = true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Ajouter un article'),
            ),
        ],
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              'Aucun article sur cette facture',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _buildTotalsCard(Invoice display) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    Widget line(String label, String value, {bool strong = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: strong ? colors.textStrong : colors.textBody,
                  fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(
                color: strong ? colors.textStrong : colors.textBody,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Totaux', icon: Icons.calculate_outlined),
          const SizedBox(height: AppSpacing.md),
          // Le détail n'apparaît que s'il apporte une information : sans
          // remise ni TVA, le total est le sous-total.
          if (display.hasBreakdown) ...[
            line('Sous-total', formatCurrency(display.subtotal)),
            if (display.discountApplied > 0)
              line('Remise', '-${formatCurrency(display.discountApplied)}'),
            if (display.taxRate > 0)
              line(
                'TVA ${formatNumber(display.taxRate.round())}%',
                '+${formatCurrency(display.taxAmount)}',
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Divider(color: colors.border, height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  'TOTAL À PAYER',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textMuted,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: AmountText(
                  display.payableTotal,
                  size: AmountSize.large,
                  color: colors.primary,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _isEditing
                ? [
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _saveChanges,
                      icon: _isSaving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.check, size: 20),
                      label: const Text('Enregistrer'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: _isSaving ? null : _toggleEdit,
                      child: const Text('Annuler'),
                    ),
                  ]
                : [
                    OutlinedButton.icon(
                      onPressed: _toggleEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Modifier'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _isSharing ? null : _showShareSheet,
                      icon: _isSharing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onPrimary,
                              ),
                            )
                          : const Icon(Icons.share_outlined, size: 20),
                      label: const Text('Partager'),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

enum _ShareTone { primary, success, danger }

class _CompactItemView extends StatelessWidget {
  final int index;
  final InvoiceItem item;
  const _CompactItemView({required this.index, required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                item.name,
                style: textTheme.titleSmall?.copyWith(
                  color: colors.textStrong,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                '×${item.quantity}',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textBody,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                'Prix : ${formatCurrency(item.unitPrice)}',
                style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ),
            AmountText(
              item.subtotal,
              size: AmountSize.small,
              color: colors.textStrong,
            ),
          ],
        ),
      ],
    );
  }
}

class _EditableItemTile extends StatefulWidget {
  final int index;
  final _ItemDraft draft;
  final bool showErrors;
  final ValueChanged<_ItemDraft> onChanged;
  final VoidCallback onDelete;

  const _EditableItemTile({
    super.key,
    required this.index,
    required this.draft,
    required this.showErrors,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_EditableItemTile> createState() => _EditableItemTileState();
}

class _EditableItemTileState extends State<_EditableItemTile> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.draft.name);
    _quantityController = TextEditingController(text: widget.draft.quantity);
    _priceController = TextEditingController(text: widget.draft.unitPrice);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  /// Remonte la saisie au parent à chaque frappe : le total et les brouillons
  /// suivent immédiatement, sans bouton de validation par ligne.
  void _emit() {
    widget.onChanged(widget.draft.copyWith(
      name: _nameController.text,
      quantity: _quantityController.text,
      unitPrice: _priceController.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final showErrors = widget.showErrors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${widget.index + 1}',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: _nameController,
                onChanged: (_) => _emit(),
                decoration: InputDecoration(
                  labelText: 'Nom',
                  errorText: showErrors && !widget.draft.isValidName
                      ? 'Nom obligatoire'
                      : null,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _emit(),
                decoration: InputDecoration(
                  labelText: 'Quantité',
                  errorText: showErrors && !widget.draft.isValidQuantity
                      ? 'Quantité obligatoire (entier supérieur à 0)'
                      : null,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => _emit(),
                decoration: InputDecoration(
                  labelText: 'Prix unitaire',
                  errorText: showErrors && !widget.draft.isValidPrice
                      ? 'Prix obligatoire (entier supérieur à 0)'
                      : null,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: colors.danger,
            onPressed: widget.onDelete,
            tooltip: 'Supprimer',
          ),
        ),
      ],
    );
  }
}
