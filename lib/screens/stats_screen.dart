// lib/screens/stats_screen.dart
// Statistiques : héros avec variation vs période précédente, KPI, évolution
// du chiffre d'affaires, répartition par statut et classements. Les graphiques
// fl_chart suivent les couleurs du thème clair / sombre.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/invoice.dart';
import '../services/invoice_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/ui/ui.dart';

enum _Period { week, month, all }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _repository = InvoiceRepository();
  List<Invoice> _invoices = [];
  bool _isLoading = true;
  _Period _period = _Period.week;

  @override
  void initState() {
    super.initState();
    _repository.addListener(_onRepositoryChanged);
    _load();
  }

  @override
  void dispose() {
    _repository.removeListener(_onRepositoryChanged);
    super.dispose();
  }

  Future<void> _load() async {
    await _repository.load();
    if (!mounted) return;
    setState(() {
      _invoices = _repository.invoices.toList();
      _isLoading = false;
    });
  }

  /// Les statistiques suivent le repository : aucune actualisation manuelle.
  void _onRepositoryChanged() {
    if (!mounted) return;
    setState(() {
      _invoices = _repository.invoices.toList();
      _isLoading = false;
    });
  }

  // ---------- Données calculées ----------

  /// Nombre de jours de la période courante (null = tout l'historique).
  int? get _periodDays => switch (_period) {
        _Period.week => 7,
        _Period.month => 30,
        _Period.all => null,
      };

  DateTime? get _periodStart {
    final days = _periodDays;
    if (days == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
  }

  List<Invoice> get _periodInvoices {
    final start = _periodStart;
    if (start == null) return _invoices;
    return _invoices.where((inv) => !inv.createdAt.isBefore(start)).toList();
  }

  /// Factures de la période précédente de même durée (vide sans historique).
  List<Invoice> get _previousPeriodInvoices {
    final days = _periodDays;
    final start = _periodStart;
    if (days == null || start == null) return const [];
    final previousStart = start.subtract(Duration(days: days));
    return _invoices
        .where((inv) =>
            !inv.createdAt.isBefore(previousStart) &&
            inv.createdAt.isBefore(start))
        .toList();
  }

  // Tous les montants sont des entiers FCFA (payableTotal fait foi).
  int get _totalCA => _periodInvoices.fold(0, (s, inv) => s + inv.payableTotal);
  int get _previousTotalCA =>
      _previousPeriodInvoices.fold(0, (s, inv) => s + inv.payableTotal);
  int get _invoiceCount => _periodInvoices.length;
  int get _averageInvoice =>
      _invoiceCount == 0 ? 0 : (_totalCA / _invoiceCount).round();
  int get _totalUnits =>
      _periodInvoices.fold(0, (s, inv) => s + inv.totalQuantity);
  int get _biggestInvoice => _periodInvoices.isEmpty
      ? 0
      : _periodInvoices
          .map((i) => i.payableTotal)
          .reduce((a, b) => a > b ? a : b);

  /// Variation en % vs la période précédente ; null quand elle n'existe pas
  /// (tout l'historique) ou ne contient aucune facture.
  int? get _variationPercent {
    if (_period == _Period.all) return null;
    if (_previousPeriodInvoices.isEmpty) return null;
    final previous = _previousTotalCA;
    if (previous <= 0) return null;
    return ((_totalCA - previous) * 100 / previous).round();
  }

  /// Série temporelle du CA : quotidienne (7/30 jours) ou mensuelle (tout).
  List<({String label, String short, int value})> _caSeries() {
    final now = DateTime.now();
    if (_period == _Period.all) {
      final map = <String, ({String label, String short, int value})>{};
      final sorted = List<Invoice>.from(_invoices)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final inv in sorted) {
        final key = DateFormat('MMMM yyyy', 'fr_FR').format(inv.createdAt);
        final short = DateFormat('MMM', 'fr_FR').format(inv.createdAt);
        final existing = map[key];
        map[key] = (
          label: key,
          short: short,
          value: (existing?.value ?? 0) + inv.payableTotal,
        );
      }
      return map.values.toList();
    }

    final days = _periodDays!;
    final map = <String, int>{};
    for (var i = days - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      map[DateFormat('E d/M', 'fr_FR').format(day)] = 0;
    }
    for (final inv in _periodInvoices) {
      final key = DateFormat('E d/M', 'fr_FR').format(inv.createdAt);
      if (map.containsKey(key)) map[key] = map[key]! + inv.payableTotal;
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

  List<MapEntry<InvoiceStatus, int>> get _statusRepartition {
    final map = <InvoiceStatus, int>{};
    for (final status in InvoiceStatus.values) {
      map[status] = _periodInvoices
          .where((inv) => inv.status == status)
          .fold(0, (s, inv) => s + inv.payableTotal);
    }
    return map.entries.toList();
  }

  List<MapEntry<String, int>> _topClients(int count) {
    final map = <String, int>{};
    for (final inv in _periodInvoices) {
      map[inv.clientName] = (map[inv.clientName] ?? 0) + inv.payableTotal;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).toList();
  }

  List<MapEntry<String, int>> _topProducts(int count) {
    final map = <String, int>{};
    for (final inv in _periodInvoices) {
      for (final item in inv.items) {
        map[item.name] = (map[item.name] ?? 0) + item.quantity;
      }
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).toList();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.canvas,
        body: const SkeletonList(),
      );
    }

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        title: const Text('Statistiques'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: _load,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: _invoices.isEmpty
          ? const EmptyState(
              icon: Icons.insert_chart_outlined,
              title: 'Aucune donnée pour le moment',
              message:
                  'Créez vos premières factures pour voir les statistiques.',
            )
          : _buildContent(),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: AppSpacing.lg),
          _buildHero(),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'Factures',
                  value: '$_invoiceCount',
                  icon: Icons.receipt_long,
                  tone: _KpiTone.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _KpiCard(
                  label: 'Panier moyen',
                  value: formatCurrency(_averageInvoice),
                  icon: Icons.shopping_cart_checkout,
                  tone: _KpiTone.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'Articles vendus',
                  value: '$_totalUnits',
                  icon: Icons.inventory_2,
                  tone: _KpiTone.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _KpiCard(
                  label: 'Plus grosse facture',
                  value: formatCurrency(_biggestInvoice),
                  icon: Icons.workspace_premium,
                  tone: _KpiTone.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildSectionCard(
            title: 'Évolution du chiffre d\'affaires',
            trailing: _buildPeriodHint(caSeries.length),
            child: caSeries.every((e) => e.value == 0)
                ? _buildNoData('Aucune vente sur cette période')
                : _buildCaChart(caSeries),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildSectionCard(
            title: 'Répartition par statut',
            child: _buildStatusCard(statusData),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildSectionCard(
            title: 'Top 5 clients',
            child: topClients.isEmpty
                ? _buildNoData('Aucun client sur cette période')
                : _buildRankedList(
                    topClients
                        .map((e) => (
                              label: e.key,
                              value: formatCurrency(e.value),
                              raw: e.value,
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildSectionCard(
            title: 'Top 5 produits',
            child: topProducts.isEmpty
                ? _buildNoData('Aucun produit sur cette période')
                : _buildRankedList(
                    topProducts
                        .map((e) => (
                              label: e.key,
                              value: '${e.value} unités',
                              raw: e.value,
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    // Défilement horizontal : à 320 dp avec un texte agrandi, les trois
    // choix ne tiennent pas forcément sur une seule ligne.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in _Period.values) ...[
            _PeriodChip(
              label: switch (period) {
                _Period.week => '7 jours',
                _Period.month => '30 jours',
                _Period.all => 'Tout',
              },
              selected: _period == period,
              onTap: () => setState(() => _period = period),
            ),
            if (period != _Period.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodHint(int bars) {
    final colors = AppColors.of(context);
    final label = switch (_period) {
      _Period.week => '7 derniers jours',
      _Period.month => '30 derniers jours',
      _Period.all => '$bars mois',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
      ),
    );
  }

  Widget _buildHero() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final variation = _variationPercent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.primary, colors.primaryStrong],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined,
                  color: colors.onPrimary.withValues(alpha: 0.85), size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'CHIFFRE D\'AFFAIRES',
                  style: textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colors.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ),
              _buildVariationChip(variation),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            formatCurrency(_totalCA),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineMedium?.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: colors.onPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$_invoiceCount facture(s) · $_totalUnits article(s)',
            style: textTheme.bodySmall?.copyWith(
              color: colors.onPrimary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariationChip(int? variation) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final hasVariation = variation != null;
    final isUp = (variation ?? 0) >= 0;
    final background = colors.onPrimary.withValues(alpha: 0.16);
    final foreground = colors.onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasVariation)
            Icon(
              isUp ? Icons.trending_up : Icons.trending_down,
              size: 14,
              color: foreground,
            ),
          if (hasVariation) const SizedBox(width: 4),
          Text(
            hasVariation
                ? '${isUp && variation != 0 ? '+' : ''}$variation %'
                : '—',
            style: textTheme.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    final colors = AppColors.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap plutôt que Row : à 320 dp avec un texte agrandi, le titre et
          // l'indicateur de période ne tiennent pas sur une ligne. L'indicateur
          // passe alors à la ligne au lieu de déborder.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colors.textStrong,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }

  Widget _buildCaChart(List<({String label, String short, int value})> series) {
    final colors = AppColors.of(context);
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
              color: colors.border,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: colors.textStrong,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final item = series[group.x];
                return BarTooltipItem(
                  '${item.label}\n${formatCurrency(item.value)}',
                  TextStyle(
                    color: colors.surface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= series.length) {
                    return const SizedBox.shrink();
                  }
                  final short = series[index].short;
                  if (short.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      short,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          barGroups: [
            for (var i = 0; i < series.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: series[i].value.toDouble(),
                    gradient: LinearGradient(
                      colors: [
                        colors.primary,
                        colors.primary.withValues(alpha: 0.55),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(6)),
                    width: _period == _Period.week
                        ? 22
                        : (_period == _Period.month ? 8 : 20),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(List<MapEntry<InvoiceStatus, int>> data) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final total = data.fold(0, (s, e) => s + e.value);
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
                          value: entry.value.toDouble(),
                          color: statusStyle(context, entry.key).foreground,
                          radius: 62,
                          title: '',
                        ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    formatCurrency(total),
                    style: textTheme.titleSmall?.copyWith(
                      color: colors.textStrong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final entry in data)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusStyle(context, entry.key).foreground,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.key.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${total > 0 ? (entry.value * 100 / total).round() : 0}%',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 96,
                  child: Text(
                    formatCurrency(entry.value),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textStrong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRankedList(
    List<({String label, String value, int raw})> items,
  ) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final max = items.map((e) => e.raw).reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textStrong,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 6,
                          color: colors.surfaceAlt,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: max <= 0
                                ? 0
                                : (items[i].raw / max).clamp(0.04, 1.0),
                            child: Container(color: colors.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  items[i].value,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildNoData(String message) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: colors.textMuted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? colors.primary : colors.border),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? colors.primary : colors.textBody,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

enum _KpiTone { primary, success, warning, info }

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final _KpiTone tone;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = switch (tone) {
      _KpiTone.primary => colors.primary,
      _KpiTone.success => colors.success,
      _KpiTone.warning => colors.warning,
      _KpiTone.info => colors.info,
    };
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: textTheme.titleMedium?.copyWith(
                color: colors.textStrong,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
