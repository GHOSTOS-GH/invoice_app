// lib/screens/history_screen.dart
// Écran d'historique avec filtres, tri, statistiques, pagination, export groupé

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../services/backup_service.dart';
import '../services/storage_service.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import '../utils/constants.dart';
import '../widgets/skeleton_loader.dart';
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

class HistoryScreenState extends State<HistoryScreen> with AutomaticKeepAliveClientMixin {
  final _storageService = StorageService();
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
  bool _filterEnCours = false;
  bool _filterEnLivraison = false;
  bool _filterLivree = false;
  bool _filterArchivee = false;

  // Filtre par période de dates (ex: factures du 10/02 au 11/02)
  DateTimeRange? _filterDateRange;

  // Option de tri
  SortOption _currentSort = SortOption.dateDesc;

  // Pagination
  final ScrollController _scrollController = ScrollController();
  int _displayedCount = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_displayedCount < _filteredInvoices.length) {
        setState(() {
          _displayedCount = (_displayedCount + 50).clamp(0, _filteredInvoices.length);
        });
      }
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterInvoices();
      _displayedCount = 50;
    });
  }

  void _filterInvoices() {
    _filteredInvoices = List.from(_invoices);

    // Filtres de statut
    final hasActiveStatusFilter = _filterEnCours || _filterEnLivraison || _filterLivree || _filterArchivee;
    if (hasActiveStatusFilter) {
      _filteredInvoices = _filteredInvoices.where((invoice) {
        if (_filterEnCours && invoice.status == InvoiceStatus.enCours) return true;
        if (_filterEnLivraison && invoice.status == InvoiceStatus.enLivraison) return true;
        if (_filterLivree && invoice.status == InvoiceStatus.livree) return true;
        if (_filterArchivee && invoice.status == InvoiceStatus.archivee) return true;
        return false;
      }).toList();
    }

    // Filtre par période de dates
    if (_filterDateRange != null) {
      final start = DateTime(
        _filterDateRange!.start.year,
        _filterDateRange!.start.month,
        _filterDateRange!.start.day,
      );
      final end = DateTime(
        _filterDateRange!.end.year,
        _filterDateRange!.end.month,
        _filterDateRange!.end.day,
        23, 59, 59,
      );
      _filteredInvoices = _filteredInvoices.where((invoice) {
        final d = invoice.createdAt;
        return !d.isBefore(start) && !d.isAfter(end);
      }).toList();
    }

    // Recherche étendue (client, articles, notes, numéro)
    if (_searchQuery.isNotEmpty) {
      _filteredInvoices = _filteredInvoices.where((invoice) {
        if (invoice.clientName.toLowerCase().contains(_searchQuery)) return true;
        if (invoice.id.toLowerCase().contains(_searchQuery)) return true;
        if (invoice.notes != null && invoice.notes!.toLowerCase().contains(_searchQuery)) return true;
        for (var item in invoice.items) {
          if (item.name.toLowerCase().contains(_searchQuery)) return true;
        }
        return false;
      }).toList();
    }

    _sortInvoices();
    setState(() {});
  }

  void _sortInvoices() {
    switch (_currentSort) {
      case SortOption.dateDesc:
        _filteredInvoices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.dateAsc:
        _filteredInvoices.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case SortOption.totalDesc:
        _filteredInvoices.sort((a, b) => b.total.compareTo(a.total));
        break;
      case SortOption.totalAsc:
        _filteredInvoices.sort((a, b) => a.total.compareTo(b.total));
        break;
      case SortOption.clientAsc:
        _filteredInvoices.sort((a, b) => a.clientName.compareTo(b.clientName));
        break;
      case SortOption.statusAsc:
        _filteredInvoices.sort((a, b) => a.status.index.compareTo(b.status.index));
        break;
    }
  }

  Future<void> _loadInvoices() async {
    setState(() {
      _isLoading = true;
      _loadingError = false;
    });
    try {
      final invoices = await _storageService.loadInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _filterInvoices();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadingError = true;
      });
    }
  }

  void refreshData() {
    _loadInvoices();
  }

  String _formatDate(DateTime date) => DateFormat('dd/MM/yyyy à HH:mm', 'fr_FR').format(date);

  void _openInvoiceDetail(Invoice invoice) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => InvoiceDetailScreen(
          invoice: invoice,
          onInvoiceUpdated: widget.onInvoiceUpdated,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Constants.cardRadius)),
        title: const Text('Confirmer la suppression'),
        content: Text('Voulez-vous vraiment supprimer ${_selectedIds.length} facture(s) ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final deletedCount = _selectedIds.length;
    _invoices.removeWhere((inv) => _selectedIds.contains(inv.id));
    await _storageService.saveInvoices(_invoices);
    setState(() {
      _filterInvoices();
      _isSelectionMode = false;
      _selectedIds.clear();
      _displayedCount = 50;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$deletedCount facture(s) supprimée(s)'), backgroundColor: Colors.green,
      behavior: SnackBarBehavior.floating),
    );
  }

  /// Exporte en CSV la sélection actuellement filtrée (période, statut, recherche...).
  Future<void> _exportFilteredCsv() async {
    if (_filteredInvoices.isEmpty) return;
    final backupService = BackupService();
    final csv = backupService.invoicesToCsv(_filteredInvoices);
    final filename =
        'factures_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Export CSV de ${_filteredInvoices.length} facture(s)...'),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await backupService.shareCsv(csv, filename);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur d\'export : $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty) return;
    final selectedInvoices = _invoices.where((inv) => _selectedIds.contains(inv.id)).toList();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Export de ${selectedInvoices.length} facture(s)...'),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // Un seul partage groupé (liste de XFile) au lieu d'ouvrir le
    // partage natif une fois par facture.
    try {
      await _pdfService.shareInvoicesAsPdf(selectedInvoices);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur d\'export : $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
      _filterEnCours = false;
      _filterEnLivraison = false;
      _filterLivree = false;
      _filterArchivee = false;
      _filterInvoices();
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
      _filterInvoices();
      _displayedCount = 50;
    });
  }

  void _clearDateFilter() {
    setState(() {
      _filterDateRange = null;
      _filterInvoices();
      _displayedCount = 50;
    });
  }

  int get _totalInvoices => _filteredInvoices.length;
  double get _totalAmount => _filteredInvoices.fold(0.0, (sum, inv) => sum + inv.total);
  Map<InvoiceStatus, int> get _statusCount {
    return {
      InvoiceStatus.enCours: _filteredInvoices.where((inv) => inv.status == InvoiceStatus.enCours).length,
      InvoiceStatus.enLivraison: _filteredInvoices.where((inv) => inv.status == InvoiceStatus.enLivraison).length,
      InvoiceStatus.livree: _filteredInvoices.where((inv) => inv.status == InvoiceStatus.livree).length,
      InvoiceStatus.archivee: _filteredInvoices.where((inv) => inv.status == InvoiceStatus.archivee).length,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: _isSelectionMode ? Text('${_selectedIds.length} sélectionnée(s)') : const Text('Historique'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        leading: _isSelectionMode
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelectionMode)
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(icon: const Icon(Icons.select_all), onPressed: _selectAll),
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _selectedIds.isEmpty ? null : _exportSelected,
                  tooltip: 'Exporter la sélection',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                  color: Colors.red,
                ),
              ]
            : [
                PopupMenuButton<SortOption>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Trier par',
                  onSelected: (SortOption option) {
                    setState(() {
                      _currentSort = option;
                      _sortInvoices();
                      _displayedCount = 50;
                    });
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem(value: SortOption.dateDesc, child: Text('Date (récente → ancienne)')),
                    const PopupMenuItem(value: SortOption.dateAsc, child: Text('Date (ancienne → récente)')),
                    const PopupMenuItem(value: SortOption.totalDesc, child: Text('Montant (décroissant)')),
                    const PopupMenuItem(value: SortOption.totalAsc, child: Text('Montant (croissant)')),
                    const PopupMenuItem(value: SortOption.clientAsc, child: Text('Client (A → Z)')),
                    const PopupMenuItem(value: SortOption.statusAsc, child: Text('Par statut')),
                  ],
                ),
                IconButton(icon: const Icon(Icons.checklist), onPressed: () => setState(() => _isSelectionMode = true)),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInvoices),
              ],
        bottom: _isSelectionMode
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Rechercher par client, article, notes, n°...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
              ),
      ),
      body: _isLoading
          ? const SkeletonList(itemCount: 5)
          : _loadingError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('Erreur de chargement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _loadInvoices,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (!_isSelectionMode) ...[
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('$_totalInvoices facture(s)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _filterDateRange != null
                                        ? 'Total (${DateFormat('dd/MM').format(_filterDateRange!.start)} → ${DateFormat('dd/MM').format(_filterDateRange!.end)}) : ${formatCurrency(_totalAmount)}'
                                        : 'Total : ${formatCurrency(_totalAmount)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2563EB)),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.ios_share),
                                  tooltip: 'Exporter la sélection filtrée (CSV)',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _filteredInvoices.isEmpty ? null : _exportFilteredCsv,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildStatusChip('En cours', _statusCount[InvoiceStatus.enCours]!, InvoiceStatus.enCours.color),
                                  const SizedBox(width: 8),
                                  _buildStatusChip('En livraison', _statusCount[InvoiceStatus.enLivraison]!, InvoiceStatus.enLivraison.color),
                                  const SizedBox(width: 8),
                                  _buildStatusChip('Livrée', _statusCount[InvoiceStatus.livree]!, InvoiceStatus.livree.color),
                                  const SizedBox(width: 8),
                                  _buildStatusChip('Archivée', _statusCount[InvoiceStatus.archivee]!, InvoiceStatus.archivee.color),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickDateRange,
                                  icon: Icon(
                                    Icons.date_range,
                                    size: 18,
                                    color: _filterDateRange != null ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                  ),
                                  label: Text(
                                    _filterDateRange == null
                                        ? 'Période'
                                        : '${DateFormat('dd/MM/yyyy').format(_filterDateRange!.start)} → ${DateFormat('dd/MM/yyyy').format(_filterDateRange!.end)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _filterDateRange != null ? const Color(0xFF2563EB) : const Color(0xFF64748B),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    visualDensity: VisualDensity.compact,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    side: BorderSide(
                                      color: _filterDateRange != null ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                ),
                                if (_filterDateRange != null) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: _clearDateFilter,
                                    tooltip: 'Effacer la période',
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilterChip(
                                  label: const Text('En cours'),
                                  selected: _filterEnCours,
                                  onSelected: (v) {
                                    setState(() { _filterEnCours = v; _filterInvoices(); _displayedCount = 50; });
                                  },
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  selectedColor: Color(InvoiceStatus.enCours.color).withOpacity(0.2),
                                  labelStyle: TextStyle(color: _filterEnCours ? Color(InvoiceStatus.enCours.color) : const Color(0xFF64748B)),
                                  side: BorderSide(color: _filterEnCours ? Color(InvoiceStatus.enCours.color) : const Color(0xFFE2E8F0)),
                                ),
                                FilterChip(
                                  label: const Text('En livraison'),
                                  selected: _filterEnLivraison,
                                  onSelected: (v) {
                                    setState(() { _filterEnLivraison = v; _filterInvoices(); _displayedCount = 50; });
                                  },
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  selectedColor: Color(InvoiceStatus.enLivraison.color).withOpacity(0.2),
                                  labelStyle: TextStyle(color: _filterEnLivraison ? Color(InvoiceStatus.enLivraison.color) : const Color(0xFF64748B)),
                                  side: BorderSide(color: _filterEnLivraison ? Color(InvoiceStatus.enLivraison.color) : const Color(0xFFE2E8F0)),
                                ),
                                FilterChip(
                                  label: const Text('Livrée'),
                                  selected: _filterLivree,
                                  onSelected: (v) {
                                    setState(() { _filterLivree = v; _filterInvoices(); _displayedCount = 50; });
                                  },
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  selectedColor: Color(InvoiceStatus.livree.color).withOpacity(0.2),
                                  labelStyle: TextStyle(color: _filterLivree ? Color(InvoiceStatus.livree.color) : const Color(0xFF64748B)),
                                  side: BorderSide(color: _filterLivree ? Color(InvoiceStatus.livree.color) : const Color(0xFFE2E8F0)),
                                ),
                                FilterChip(
                                  label: const Text('Archivée'),
                                  selected: _filterArchivee,
                                  onSelected: (v) {
                                    setState(() { _filterArchivee = v; _filterInvoices(); _displayedCount = 50; });
                                  },
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  selectedColor: Color(InvoiceStatus.archivee.color).withOpacity(0.2),
                                  labelStyle: TextStyle(color: _filterArchivee ? Color(InvoiceStatus.archivee.color) : const Color(0xFF64748B)),
                                  side: BorderSide(color: _filterArchivee ? Color(InvoiceStatus.archivee.color) : const Color(0xFFE2E8F0)),
                                ),
                                if (_filterEnCours || _filterEnLivraison || _filterLivree || _filterArchivee)
                                  ActionChip(
                                    label: const Text('Réinitialiser'),
                                    onPressed: _clearStatusFilters,
                                    backgroundColor: Colors.grey[100],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    Expanded(
                      child: _filteredInvoices.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  Text(_searchQuery.isEmpty ? 'Aucune facture' : 'Aucun résultat', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadInvoices,
                              child: ListView.separated(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(16),
                                itemCount: (_displayedCount < _filteredInvoices.length) ? _displayedCount + 1 : _filteredInvoices.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  if (index == _displayedCount && _displayedCount < _filteredInvoices.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(child: CircularProgressIndicator()),
                                    );
                                  }
                                  final invoice = _filteredInvoices[index];
                                  final isSelected = _selectedIds.contains(invoice.id);
                                  
                                  if (_isSelectionMode) {
                                    return _buildInvoiceCard(invoice, isSelected, index);
                                  }
                                  
                                  return _buildSwipeableInvoiceCard(invoice, isSelected, index);
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSwipeableInvoiceCard(Invoice invoice, bool isSelected, int index) {
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
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Constants.cardRadius),
          gradient: const LinearGradient(
            colors: [Color(0xFF16A34A), Color(0xFF15803D)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.arrow_forward, color: Colors.white, size: 24),
            SizedBox(width: 8),
            Icon(Icons.local_shipping, color: Colors.white, size: 20),
            SizedBox(width: 4),
            Text('Avancer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Constants.cardRadius),
          gradient: const LinearGradient(
            colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Reculer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(width: 4),
            Icon(Icons.arrow_back, color: Colors.white, size: 24),
          ],
        ),
      ),
      direction: DismissDirection.horizontal,
      movementDuration: const Duration(milliseconds: 300),
      resizeDuration: null,
      child: _buildInvoiceCard(invoice, isSelected, index),
    );
  }

  Future<void> _updateInvoiceStatus(Invoice invoice, InvoiceStatus newStatus) async {
    final updatedInvoice = invoice.copyWith(status: newStatus);
    final all = await _storageService.loadInvoices();
    final idx = all.indexWhere((inv) => inv.id == invoice.id);
    if (idx != -1) {
      all[idx] = updatedInvoice;
      await _storageService.saveInvoices(all);
    }
    if (!mounted) return;
    setState(() {
      final listIdx = _invoices.indexWhere((inv) => inv.id == invoice.id);
      if (listIdx != -1) {
        _invoices[listIdx] = updatedInvoice;
      }
      _filterInvoices();
    });
    widget.onInvoiceUpdated();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${invoice.clientName} → ${newStatus.label}'),
        backgroundColor: Color(newStatus.color),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildInvoiceCard(Invoice invoice, bool isSelected, int index) {
    return Hero(
      tag: 'invoice-${invoice.id}',
      child: Card(
        elevation: 2,
        shadowColor: Colors.blue.withOpacity(0.05),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Constants.cardRadius)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Constants.cardRadius),
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(invoice.id);
            } else {
              _openInvoiceDetail(invoice);
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              setState(() {
                _isSelectionMode = true;
                _selectedIds.add(invoice.id);
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (_isSelectionMode) ...[
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(invoice.id),
                    activeColor: const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                ],
                Hero(
                  tag: 'invoice-icon-${invoice.id}',
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invoice.clientName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(_formatDate(invoice.createdAt), style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatCurrency(invoice.total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Color(invoice.status.color).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(invoice.status.label, style: TextStyle(fontSize: 12, color: Color(invoice.status.color), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, int count, int color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Color(color).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Color(color))),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: Color(color), shape: BoxShape.circle),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(count.toString(), style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}