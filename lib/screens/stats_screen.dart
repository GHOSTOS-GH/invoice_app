// lib/screens/stats_screen.dart
// Écran de statistiques repensé : héros, KPI, sélecteur de période,
// chiffre d'affaires, répartition par statut, top clients et produits.

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import '../widgets/skeleton_loader.dart';

const Color _kPrimary = Color(0xFF2563EB);
const Color _kPrimaryDark = Color(0xFF1D4ED8);
const Color _kInk = Color(0xFF0F172A);
const Color _kBody = Color(0xFF64748B);
const Color _kMuted = Color(0xFF94A3B8);

enum _Period { week, month, all }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _storageService = StorageService();
  List<Invoice> _invoices = [];
  bool _isLoading = true;
  _Period _period = _Period.week;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invoices = await _storageService.loadInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ---------- Données calculées ----------

  List<Invoice> get _periodInvoices {
    final now = DateTime.now();
    final start = switch (_period) {
      _Period.week => DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
      _Period.month => DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
      _Period.all => null,
    };
    if (start == null) return _invoices;
    return _invoices.where((inv) => !inv.createdAt.isBefore(start)).toList();
  }

  double get _totalCA => _periodInvoices.fold(0.0, (s, inv) => s + inv.total);
  int get _invoiceCount => _periodInvoices.length;
  double get _averageInvoice => _invoiceCount == 0 ? 0 : _totalCA / _invoiceCount;
  int get _totalUnits => _periodInvoices.fold(0, (s, inv) => s + inv.totalQuantity);
  double get _biggestInvoice =>
      _periodInvoices.isEmpty ? 0 : _periodInvoices.map((i) => i.total).reduce((a, b) => a > b ? a : b);

  /// Série temporelle du CA : quotidienne (7/30 jours) ou mensuelle (tout).
  List<({String label, String short, double value})> _caSeries() {
    final now = DateTime.now();
    if (_period == _Period.all) {
      final map = <String, ({String label, String short, double value})>{};
      final sorted = List<Invoice>.from(_invoices)..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final inv in sorted) {
        final key = DateFormat('MMMM yyyy', 'fr_FR').format(inv.createdAt);
        final short = DateFormat('MMM', 'fr_FR').format(inv.createdAt);
        final existing = map[key];
        map[key] = (
          label: key,
          short: short,
          value: (existing?.value ?? 0) + inv.total,
        );
      }
      return map.values.toList();
    }

    final days = _period == _Period.week ? 7 : 30;
    final map = <String, double>{};
    for (var i = days - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      map[DateFormat('E d/M', 'fr_FR').format(day)] = 0;
    }
    for (final inv in _periodInvoices) {
      final key = DateFormat('E d/M', 'fr_FR').format(inv.createdAt);
      if (map.containsKey(key)) map[key] = map[key]! + inv.total;
    }
    final keys = map.keys.toList();
    return [
      for (var i = 0; i < keys.length; i++)
        (
          label: keys[i],
          short: _period == _Period.week
              ? keys[i].split(' ').first
              : (i % 5 == 0 ? keys[i].substring(keys[i].indexOf(' ') + 1) : ''),
          value: map[keys[i]]!,
        ),
    ];
  }

  List<MapEntry<InvoiceStatus, double>> get _statusRepartition {
    final map = <InvoiceStatus, double>{};
    for (final status in InvoiceStatus.values) {
      map[status] = _periodInvoices
          .where((inv) => inv.status == status)
          .fold(0.0, (s, inv) => s + inv.total);
    }
    return map.entries.toList();
  }

  List<MapEntry<String, double>> _topClients(int count) {
    final map = <String, double>{};
    for (final inv in _periodInvoices) {
      map[inv.clientName] = (map[inv.clientName] ?? 0) + inv.total;
    }
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).toList();
  }

  List<MapEntry<String, int>> _topProducts(int count) {
    final map = <String, int>{};
    for (final inv in _periodInvoices) {
      for (final item in inv.items) {
        map[item.name] = (map[item.name] ?? 0) + item.quantity;
      }
    }
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).toList();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: SkeletonList());
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Statistiques'),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _load,
          ),
        ],
      ),
      body: _invoices.isEmpty ? _buildEmptyState() : _buildContent(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.insert_chart_outlined, size: 48, color: _kPrimary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Aucune donnée pour le moment',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _kInk),
          ),
          const SizedBox(height: 6),
          const Text(
            'Créez vos premières factures pour voir les statistiques',
            style: TextStyle(fontSize: 14, color: _kBody),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final caSeries = _caSeries();
    final statusData = _statusRepartition;
    final topClients = _topClients(5);
    final topProducts = _topProducts(5);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          _buildHero(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildKpiCard(label: 'Factures', value: '$_invoiceCount', icon: Icons.receipt_long, color: const Color(0xFF6366F1))),
              const SizedBox(width: 12),
              Expanded(child: _buildKpiCard(label: 'Panier moyen', value: formatCurrency(_averageInvoice), icon: Icons.shopping_cart_checkout, color: const Color(0xFF16A34A))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildKpiCard(label: 'Articles vendus', value: '$_totalUnits', icon: Icons.inventory_2, color: const Color(0xFFD97706))),
              const SizedBox(width: 12),
              Expanded(child: _buildKpiCard(label: 'Plus grosse facture', value: formatCurrency(_biggestInvoice), icon: Icons.workspace_premium, color: const Color(0xFFDB2777))),
            ],
          ),
          const SizedBox(height: 20),
          _buildSectionCard(
            title: 'Évolution du chiffre d\'affaires',
            trailing: _buildPeriodHint(caSeries.length),
            child: caSeries.every((e) => e.value == 0)
                ? _buildNoData('Aucune vente sur cette période')
                : _buildCaChart(caSeries),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Répartition par statut',
            child: _buildStatusCard(statusData),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Top 5 clients',
            child: topClients.isEmpty
                ? _buildNoData('Aucun client sur cette période')
                : _buildRankedList(topClients.map((e) => (label: e.key, value: formatCurrency(e.value), raw: e.value, unit: false)).toList()),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Top 5 produits',
            child: topProducts.isEmpty
                ? _buildNoData('Aucun produit sur cette période')
                : _buildRankedList(topProducts.map((e) => (label: e.key, value: '${e.value} unités', raw: e.value.toDouble(), unit: true)).toList()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return SegmentedButton<_Period>(
      segments: const [
        ButtonSegment(value: _Period.week, label: Text('7 jours'), icon: Icon(Icons.today, size: 16)),
        ButtonSegment(value: _Period.month, label: Text('30 jours'), icon: Icon(Icons.calendar_month, size: 16)),
        ButtonSegment(value: _Period.all, label: Text('Tout'), icon: Icon(Icons.all_inclusive, size: 16)),
      ],
      selected: {_period},
      onSelectionChanged: (selection) => setState(() => _period = selection.first),
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      ),
    );
  }

  Widget _buildPeriodHint(int bars) {
    final label = switch (_period) {
      _Period.week => '7 derniers jours',
      _Period.month => '30 derniers jours',
      _Period.all => '$bars mois',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kPrimary)),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kPrimary, _kPrimaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _kPrimary.withValues(alpha: 0.30),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.payments, color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Text(
                'CHIFFRE D\'AFFAIRES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white70,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatCurrency(_totalCA),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_invoiceCount facture(s) · $_totalUnits article(s)',
            style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({required String label, required String value, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDF1F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _kInk, letterSpacing: -0.3),
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: _kBody, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEDF1F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kInk, letterSpacing: -0.2),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildCaChart(List<({String label, String short, double value})> series) {
    final maxValue = series.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.25;

    return SizedBox(
      height: 210,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: const Color(0xFFF1F5F9),
              strokeWidth: 1,
              dashArray: [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: const Color(0xFF0F172A),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final item = series[group.x];
                return BarTooltipItem(
                  '${item.label}\n${formatCurrency(item.value)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.length) return const SizedBox.shrink();
                  final short = series[index].short;
                  if (short.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(short, style: const TextStyle(fontSize: 10, color: _kMuted, fontWeight: FontWeight.w600)),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: series[i].value,
                    gradient: const LinearGradient(
                      colors: [_kPrimary, Color(0xFF60A5FA)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    width: _period == _Period.week ? 22 : (_period == _Period.month ? 8 : 20),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(List<MapEntry<InvoiceStatus, double>> data) {
    final total = data.fold(0.0, (s, e) => s + e.value);
    if (total <= 0) return _buildNoData('Aucune vente sur cette période');

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 52,
                  sections: [
                    for (final entry in data)
                      if (entry.value > 0)
                        PieChartSectionData(
                          value: entry.value,
                          color: Color(entry.key.color),
                          radius: 62,
                          title: '',
                        ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Total', style: TextStyle(fontSize: 11, color: _kMuted, fontWeight: FontWeight.w600)),
                  Text(
                    formatCurrency(total),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _kInk),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final entry in data)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: Color(entry.key.color), borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.key.label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kInk),
                  ),
                ),
                Text(
                  '${(total > 0 ? entry.value / total * 100 : 0).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kMuted),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: Text(
                    formatCurrency(entry.value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kInk),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRankedList(List<({String label, String value, double raw, bool unit})> items) {
    final max = items.map((e) => e.raw).reduce((a, b) => a > b ? a : b);
    final colors = [
      const Color(0xFF2563EB),
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFF0EA5E9),
      const Color(0xFF14B8A6),
    ];

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length].withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors[i % colors.length]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _kInk),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 6,
                          color: const Color(0xFFF1F5F9),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: max <= 0 ? 0 : (items[i].raw / max).clamp(0.04, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [colors[i % colors.length], colors[i % colors.length].withValues(alpha: 0.6)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  items[i].value,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: _kInk),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNoData(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(message, style: const TextStyle(fontSize: 13, color: _kMuted)),
          ],
        ),
      ),
    );
  }
}
