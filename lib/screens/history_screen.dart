// lib/screens/history_screen.dart
// Historique : recherche, bandeau de filtres unique, options dans une feuille,
// cartes compactes, sélection multiple et résumé de période.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/invoice.dart';
import '../services/backup_service.dart';
import '../services/invoice_repository.dart';
import '../services/pdf_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/ui/ui.dart';
import 'invoice_detail_screen.dart';

enum SortOption {
  dateDesc,
  dateAsc,
  totalDesc,
  totalAsc,
  clientAsc,
  statusAsc,
}

class HistoryScreen extends StatefulWidget {
  final VoidCallback onInvoiceUpdated;
  const HistoryScreen({super.key, required this.onInvoiceUpdated});

  @override
  State<HistoryScreen> createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen>
    with AutomaticKeepAliveClientMixin {
  final _repository = InvoiceRepository();
  final _pdfService = PdfService();
  List<Invoice> _invoices = [];
  List<Invoice> _filteredInvoices = [];
  bool _isLoading = true;
  bool _loadingError = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSelectionMode = false;
  Set<String> _selectedIds = {};

  // Filtres d'état
  final Set<InvoiceStatus> _statusFilters = {};

  // Filtre par période de dates (ex: factures du 10/02 au 11/02)
  DateTimeRange? _filterDateRange;

  // Option de tri
  SortOption _currentSort = SortOption.dateDesc;

  // Pagination
  final ScrollController _scrollController = ScrollController();
  int _displayedCount = 50;

  /// Minuteur de la recherche (250 ms), annulé dans dispose.
  Timer? _searchDebounce;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _repository.addListener(_onRepositoryChanged);
    _loadInvoices();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _repository.removeListener(_onRepositoryChanged);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_displayedCount < _filteredInvoices.length) {
        setState(() {
          _displayedCount =
              (_displayedCount + 50).clamp(0, _filteredInvoices.length);
        });
      }
    }
  }

  /// Recherche différée : une seule mise à jour après 250 ms de calme.
  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filteredInvoices = _applyFilters();
        _displayedCount = 50;
      });
    });
  }

  /// Recherche + période, SANS le filtre de statut : sert de base aux
  /// compteurs des puces, qui doivent rester lisibles quand un statut est
  /// sélectionné.
  List<Invoice> _baseFiltered() {
    var result = List<Invoice>.from(_invoices);

    final dateRange = _filterDateRange;
    if (dateRange != null) {
      final start = DateTime(
        dateRange.start.year,
        dateRange.start.month,
        dateRange.start.day,
      );
      final end = DateTime(
        dateRange.end.year,
        dateRange.end.month,
        dateRange.end.day,
        23,
        59,
        59,
      );
      result = result
          .where((invoice) =>
              !invoice.createdAt.isBefore(start) &&
              !invoice.createdAt.isAfter(end))
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      result = result.where((invoice) {
        if (invoice.clientName.toLowerCase().contains(_searchQuery)) {
          return true;
        }
        if (invoice.id.toLowerCase().contains(_searchQuery)) return true;
        if (invoice.notes != null &&
            invoice.notes!.toLowerCase().contains(_searchQuery)) {
          return true;
        }
        for (final item in invoice.items) {
          if (item.name.toLowerCase().contains(_searchQuery)) return true;
        }
        return false;
      }).toList();
    }

    return result;
  }

  /// Méthode PURE : calcule la liste filtrée et triée sans toucher à l'état ni
  /// appeler setState.
  List<Invoice> _applyFilters() {
    var result = _baseFiltered();
    if (_statusFilters.isNotEmpty) {
      result = result
          .where((invoice) => _statusFilters.contains(invoice.status))
          .toList();
    }
    _sortRows(result);
    return result;
  }

  void _sortRows(List<Invoice> rows) {
    switch (_currentSort) {
      case SortOption.dateDesc:
        rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.dateAsc:
        rows.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.totalDesc:
        rows.sort((a, b) => b.total.compareTo(a.total));
        break;
      case SortOption.totalAsc:
        rows.sort((a, b) => a.total.compareTo(b.total));
        break;
      case SortOption.clientAsc:
        rows.sort((a, b) => a.clientName.compareTo(b.clientName));
        break;
      case SortOption.statusAsc:
        rows.sort((a, b) => a.status.index.compareTo(b.status.index));
        break;
    }
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
      _loadingError = false;
    });
    await _repository.load();
    if (!mounted) return;
    setState(() {
      _invoices = List<Invoice>.from(_repository.invoices);
      _filteredInvoices = _applyFilters();
      _isLoading = false;
      _loadingError = _repository.hasLoadError;
    });
  }

  /// La liste suit le repository : aucune clé globale de rafraîchissement.
  void _onRepositoryChanged() {
    if (!mounted) return;
    setState(() {
      _invoices = List<Invoice>.from(_repository.invoices);
      _filteredInvoices = _applyFilters();
      _isLoading = false;
      _loadingError = _repository.hasLoadError;
    });
  }

  String _formatDate(DateTime date) =>
      DateFormat('dd/MM/yyyy', 'fr_FR').format(date);

  void _openInvoiceDetail(Invoice invoice) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) =>
            InvoiceDetailScreen(
          invoice: invoice,
          onInvoiceUpdated: widget.onInvoiceUpdated,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _filteredInvoices.length) {
        _selectedIds.clear();
      } else {
        _selectedIds = _filteredInvoices.map((inv) => inv.id).toSet();
      }
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Confirmer la suppression'),
        content: Text(
          'Voulez-vous vraiment supprimer ${_selectedIds.length} facture(s) ?',
        ),
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
    if (confirm != true || !mounted) return;

    final deletedCount = _selectedIds.length;
    await _repository.removeByIds(_selectedIds);
    if (!mounted) return;
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
      _displayedCount = 50;
    });
    AppSnack.success(context, '$deletedCount facture(s) supprimée(s)');
  }

  /// Exporte en CSV la sélection actuellement filtrée (période, statut,
  /// recherche...).
  Future<void> _exportFilteredCsv() async {
    if (_filteredInvoices.isEmpty) return;
    final backupService = BackupService();
    final csv = backupService.invoicesToCsv(_filteredInvoices);
    final filename =
        'factures_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';

    AppSnack.info(
      context,
      'Export CSV de ${_filteredInvoices.length} facture(s)...',
      duration: const Duration(seconds: 2),
    );
    try {
      await backupService.shareCsv(csv, filename);
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Erreur d\'export : $e');
    }
  }

  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty) return;
    final selectedInvoices =
        _invoices.where((inv) => _selectedIds.contains(inv.id)).toList();

    AppSnack.info(
      context,
      'Export de ${selectedInvoices.length} facture(s)...',
      duration: const Duration(seconds: 2),
    );

    // Un seul partage groupé (liste de XFile) au lieu d'ouvrir le
    // partage natif une fois par facture.
    try {
      await _pdfService.shareInvoicesAsPdf(selectedInvoices);
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Erreur d\'export : $e');
    }
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _clearStatusFilters() {
    setState(() {
      _statusFilters.clear();
      _filteredInvoices = _applyFilters();
      _displayedCount = 50;
    });
  }

  void _toggleStatusFilter(InvoiceStatus status) {
    setState(() {
      if (!_statusFilters.add(status)) _statusFilters.remove(status);
      _filteredInvoices = _applyFilters();
      _displayedCount = 50;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: _filterDateRange,
      helpText: 'Sélectionner une période',
      saveText: 'Appliquer',
      cancelText: 'Annuler',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filterDateRange = picked;
      _filteredInvoices = _applyFilters();
      _displayedCount = 50;
    });
  }

  void _clearDateFilter() {
    setState(() {
      _filterDateRange = null;
      _filteredInvoices = _applyFilters();
      _displayedCount = 50;
    });
  }

  Future<void> _openOptionsSheet() async {
    await showAppSheet<void>(
      context: context,
      maxHeightFactor: 0.8,
      builder: (_) => _HistoryOptionsSheet(
        currentSort: _currentSort,
        filteredCount: _filteredInvoices.length,
        onSort: (option) {
          setState(() {
            _currentSort = option;
            _filteredInvoices = _applyFilters();
            _displayedCount = 50;
          });
        },
        onExportCsv: _exportFilteredCsv,
        onResetFilters: () {
          setState(() {
            _statusFilters.clear();
            _filterDateRange = null;
            _currentSort = SortOption.dateDesc;
            _searchController.clear();
            _searchQuery = '';
            _filteredInvoices = _applyFilters();
            _displayedCount = 50;
          });
        },
      ),
    );
  }

  int get _totalInvoices => _filteredInvoices.length;
  int get _totalAmount =>
      _filteredInvoices.fold(0, (sum, inv) => sum + inv.payableTotal);

  int _countFor(InvoiceStatus status) {
    if (!_statusFilters.contains(status)) {
      // Compteur stable par rapport à la recherche et à la période.
      return _baseFiltered().where((inv) => inv.status == status).length;
    }
    return _filteredInvoices.where((inv) => inv.status == status).length;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${_selectedIds.length} sélectionnée(s)'
              : 'Historique',
        ),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Quitter la sélection',
                onPressed: _exitSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Options et tri',
                  onPressed: _openOptionsSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: 'Sélectionner',
                  onPressed: () => setState(() => _isSelectionMode = true),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
      ),
      body: _isLoading
          ? const SkeletonList(itemCount: 5)
          : _loadingError
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Erreur de chargement',
                  message:
                      'Les factures n\'ont pas pu être lues. Réessayez sans '
                      'rien perdre : les données sont conservées.',
                  actionLabel: 'Réessayer',
                  actionIcon: Icons.refresh,
                  onAction: _loadInvoices,
                )
              : Column(
                  children: [
                    if (!_isSelectionMode) _buildSearchAndFilters(),
                    Expanded(child: _buildList()),
                    if (_isSelectionMode) _buildSelectionBar(),
                  ],
                ),
    );
  }

  Widget _buildSearchAndFilters() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
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
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rechercher par client, article, notes, n°...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Effacer la recherche',
                      onPressed: () => _searchController.clear(),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // UN SEUL bandeau de filtres : statuts (avec compteurs) + période.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final status in InvoiceStatus.values) ...[
                  _StatusFilterChip(
                    status: status,
                    count: _countFor(status),
                    selected: _statusFilters.contains(status),
                    onTap: () => _toggleStatusFilter(status),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                _PeriodChip(
                  range: _filterDateRange,
                  onPressed: _pickDateRange,
                  onClear: _filterDateRange == null ? null : _clearDateFilter,
                ),
                if (_statusFilters.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: _clearStatusFilters,
                    child: const Text('Réinitialiser'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$_totalInvoices facture(s)',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  _filterDateRange != null
                      ? 'Total (${DateFormat('dd/MM').format(_filterDateRange!.start)} → ${DateFormat('dd/MM').format(_filterDateRange!.end)}) : ${formatCurrency(_totalAmount)}'
                      : 'Total à payer : ${formatCurrency(_totalAmount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_filteredInvoices.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: _searchQuery.isEmpty ? 'Aucune facture' : 'Aucun résultat',
        message: _searchQuery.isEmpty
            ? 'Les factures créées apparaîtront ici.'
            : 'Aucune facture ne correspond à cette recherche.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInvoices,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(AppSpacing.lg),
        itemCount: (_displayedCount < _filteredInvoices.length)
            ? _displayedCount + 1
            : _filteredInvoices.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          if (index == _displayedCount &&
              _displayedCount < _filteredInvoices.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final invoice = _filteredInvoices[index];
          final isSelected = _selectedIds.contains(invoice.id);

          if (_isSelectionMode) {
            return _buildInvoiceCard(invoice, isSelected);
          }
          return _buildSwipeableInvoiceCard(invoice, isSelected);
        },
      ),
    );
  }

  Widget _buildSwipeableInvoiceCard(Invoice invoice, bool isSelected) {
    final colors = AppColors.of(context);
    return Dismissible(
      key: Key('swipe_${invoice.id}'),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Gauche → Droite : statut avance
          InvoiceStatus newStatus;
          switch (invoice.status) {
            case InvoiceStatus.enCours:
              newStatus = InvoiceStatus.enLivraison;
              break;
            case InvoiceStatus.enLivraison:
              newStatus = InvoiceStatus.livree;
              break;
            case InvoiceStatus.livree:
              newStatus = InvoiceStatus.archivee;
              break;
            case InvoiceStatus.archivee:
              return false; // Ne rien faire si archivée
          }
          await _updateInvoiceStatus(invoice, newStatus);
          return false; // Ne pas supprimer la carte
        } else {
          // Droite → Gauche : statut recule
          InvoiceStatus newStatus;
          switch (invoice.status) {
            case InvoiceStatus.livree:
              newStatus = InvoiceStatus.enLivraison;
              break;
            case InvoiceStatus.enLivraison:
              newStatus = InvoiceStatus.enCours;
              break;
            case InvoiceStatus.enCours:
              return false; // Déjà au minimum
            case InvoiceStatus.archivee:
              newStatus = InvoiceStatus.livree;
              break;
          }
          await _updateInvoiceStatus(invoice, newStatus);
          return false; // Ne pas supprimer la carte
        }
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.xl),
        decoration: BoxDecoration(
          color: colors.success,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(Icons.arrow_forward, color: colors.surface, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Avancer',
              style: TextStyle(
                color: colors.surface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(
          color: colors.warning,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Reculer',
              style: TextStyle(
                color: colors.surface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.arrow_back, color: colors.surface, size: 22),
          ],
        ),
      ),
      direction: DismissDirection.horizontal,
      movementDuration: const Duration(milliseconds: 200),
      resizeDuration: null,
      child: _buildInvoiceCard(invoice, isSelected),
    );
  }

  Future<void> _updateInvoiceStatus(
    Invoice invoice,
    InvoiceStatus newStatus,
  ) async {
    final updatedInvoice = invoice.copyWith(status: newStatus);
    await _repository.update(updatedInvoice);
    if (!mounted) return;
    widget.onInvoiceUpdated();
    if (!mounted) return;
    AppSnack.neutral(
      context,
      '${invoice.clientName} → ${newStatus.label}',
      duration: const Duration(seconds: 2),
    );
  }

  Widget _buildInvoiceCard(Invoice invoice, bool isSelected) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      color: isSelected ? colors.primary.withValues(alpha: 0.06) : null,
      border: isSelected
          ? BorderSide(color: colors.primary.withValues(alpha: 0.5))
          : null,
      onTap: () {
        if (_isSelectionMode) {
          _toggleSelection(invoice.id);
        } else {
          _openInvoiceDetail(invoice);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_isSelectionMode) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleSelection(invoice.id),
                  activeColor: colors.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
              ] else ...[
                ClientAvatar(name: invoice.clientName),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: colors.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 12, color: colors.textMuted),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _formatDate(invoice.createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AmountText(
                  invoice.payableTotal,
                  size: AmountSize.medium,
                  color: colors.textStrong,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(status: invoice.status, compact: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar() {
    final colors = AppColors.of(context);
    final hasSelection = _selectedIds.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: _selectedIds.length == _filteredInvoices.length
                    ? 'Tout désélectionner'
                    : 'Tout sélectionner',
                onPressed: _selectAll,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                color: colors.danger,
                tooltip: 'Supprimer la sélection',
                onPressed: hasSelection ? _deleteSelected : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: hasSelection ? _exportSelected : null,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Partager'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puce de filtre de statut avec compteur.
class _StatusFilterChip extends StatelessWidget {
  final InvoiceStatus status;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _StatusFilterChip({
    required this.status,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final palette = statusStyle(context, status);
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: '${status.label}, $count facture(s)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? palette.background : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? palette.foreground : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status.label,
                style: textTheme.labelSmall?.copyWith(
                  color: selected ? palette.foreground : colors.textBody,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? palette.foreground : colors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: textTheme.labelSmall?.copyWith(
                    color: selected ? palette.background : colors.textBody,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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

/// Puce de période : ouvre le sélecteur de dates, avec effacement possible.
class _PeriodChip extends StatelessWidget {
  final DateTimeRange? range;
  final VoidCallback onPressed;
  final VoidCallback? onClear;

  const _PeriodChip({
    required this.range,
    required this.onPressed,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final active = range != null;
    final label = range == null
        ? 'Période'
        : '${DateFormat('dd/MM/yyyy').format(range!.start)} → '
            '${DateFormat('dd/MM/yyyy').format(range!.end)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: active
                  ? colors.primary.withValues(alpha: 0.12)
                  : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: active ? colors.primary : colors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.date_range,
                  size: 16,
                  color: active ? colors.primary : colors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: active ? colors.primary : colors.textBody,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
        if (onClear != null)
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Effacer la période',
            onPressed: onClear,
          ),
      ],
    );
  }
}

/// Options avancées : tri, export CSV et réinitialisation des filtres.
class _HistoryOptionsSheet extends StatelessWidget {
  final SortOption currentSort;
  final int filteredCount;
  final ValueChanged<SortOption> onSort;
  final VoidCallback onExportCsv;
  final VoidCallback onResetFilters;

  const _HistoryOptionsSheet({
    required this.currentSort,
    required this.filteredCount,
    required this.onSort,
    required this.onExportCsv,
    required this.onResetFilters,
  });

  static const Map<SortOption, String> _labels = {
    SortOption.dateDesc: 'Date (récente → ancienne)',
    SortOption.dateAsc: 'Date (ancienne → récente)',
    SortOption.totalDesc: 'Montant (décroissant)',
    SortOption.totalAsc: 'Montant (croissant)',
    SortOption.clientAsc: 'Client (A → Z)',
    SortOption.statusAsc: 'Par statut',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        const SectionHeader(
          title: 'Options et tri',
          subtitle: 'Affinez la liste sans quitter l\'historique',
          icon: Icons.tune,
        ),
        const SizedBox(height: AppSpacing.md),
        for (final entry in _labels.entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: AppSpacing.sm,
            title: Text(entry.value),
            trailing: currentSort == entry.key
                ? Icon(Icons.check, color: colors.primary)
                : null,
            onTap: () {
              onSort(entry.key);
              Navigator.pop(context);
            },
          ),
        Divider(color: colors.border),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: AppSpacing.sm,
          leading: Icon(Icons.table_chart_outlined, color: colors.primary),
          title: const Text('Exporter en CSV'),
          subtitle: Text(
            '$filteredCount facture(s) filtrée(s)',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
          onTap: () {
            Navigator.pop(context);
            onExportCsv();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: AppSpacing.sm,
          leading: Icon(Icons.filter_alt_off_outlined, color: colors.textMuted),
          title: const Text('Réinitialiser les filtres'),
          onTap: () {
            Navigator.pop(context);
            onResetFilters();
          },
        ),
      ],
    );
  }
}
