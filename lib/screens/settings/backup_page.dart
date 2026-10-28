// lib/screens/settings/backup_page.dart
// Sauvegarde et restauration des données (CSV / JSON).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/backup_service.dart';
import '../../services/history_service.dart';
import '../../services/invoice_repository.dart';
import '../../services/product_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/ui/ui.dart';

class BackupPage extends StatefulWidget {
  final VoidCallback? onDataRestored;

  const BackupPage({super.key, this.onDataRestored});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final InvoiceRepository _repository = InvoiceRepository();
  final BackupService _backupService = BackupService();
  final ProductService _productService = ProductService();
  final HistoryService _historyService = HistoryService();

  int _invoiceCount = 0;
  int _productCount = 0;
  int _clientCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _repository.load();
    final products = await _productService.loadProducts();
    final clients = await _historyService.getClientNames();
    if (!mounted) return;
    setState(() {
      _invoiceCount = _repository.invoices.length;
      _productCount = products.length;
      _clientCount = clients.length;
      _isLoading = false;
    });
  }

  String _timestamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  Future<void> _exportCsv() async {
    await _repository.load();
    final invoices = _repository.invoices.toList();
    if (invoices.isEmpty) {
      if (!mounted) return;
      AppSnack.error(context, 'Aucune facture à exporter');
      return;
    }
    try {
      final csv = _backupService.invoicesToCsv(invoices);
      await _backupService.shareCsv(csv, 'factures_${_timestamp()}.csv');
      if (!mounted) return;
      AppSnack.success(context, 'CSV de ${invoices.length} facture(s) généré');
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Erreur lors de l\'export CSV : $e');
    }
  }

  Future<void> _exportBackup() async {
    try {
      final json = await _backupService.createBackupJson();
      await _backupService.shareBackupJson(
        json,
        'sauvegarde_${_timestamp()}.json',
      );
      if (!mounted) return;
      AppSnack.success(context, 'Sauvegarde complète générée');
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Erreur lors de la sauvegarde : $e');
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: const Text('Restaurer la sauvegarde'),
          content: Text(
            'Le fichier « ${picked.filename} » contient :\n\n'
            '• ${preview.invoiceCount} facture(s)\n'
            '• ${preview.productCount} produit(s)\n'
            '• ${preview.clientCount} client(s) enregistré(s)\n\n'
            'Les données actuelles seront entièrement remplacées.\n\n'
            'Une sauvegarde de sécurité sera créée automatiquement avant la '
            'restauration. Continuer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await _backupService.restoreFromJson(picked.content);
      widget.onDataRestored?.call();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      AppSnack.success(
        context,
        'Données restaurées (${preview.invoiceCount} facture(s))',
      );
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Restauration impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(title: const Text('Sauvegarde')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Icon(Icons.storage, color: colors.primary, size: 26),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          '$_invoiceCount facture(s) · $_productCount '
                          'produit(s) · $_clientCount client(s) enregistré(s)',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.textBody,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _BackupActionCard(
                  icon: Icons.table_chart_outlined,
                  tone: _BackupTone.primary,
                  title: 'Exporter en CSV',
                  subtitle:
                      'Toutes les factures (une ligne par article), ouvrable '
                      'dans Excel / Sheets',
                  onTap: _exportCsv,
                ),
                const SizedBox(height: AppSpacing.md),
                _BackupActionCard(
                  icon: Icons.save_alt,
                  tone: _BackupTone.success,
                  title: 'Sauvegarde complète (JSON)',
                  subtitle:
                      'Factures, produits et historique d\'autocomplétion',
                  onTap: _exportBackup,
                ),
                const SizedBox(height: AppSpacing.md),
                _BackupActionCard(
                  icon: Icons.restore,
                  tone: _BackupTone.warning,
                  title: 'Restaurer une sauvegarde',
                  subtitle:
                      'Remplace les données actuelles par celles d\'un fichier '
                      '.json',
                  onTap: _restoreBackup,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Astuce : exportez régulièrement une sauvegarde complète '
                  '(JSON) pour protéger vos données. La restauration remplace '
                  'toutes les données existantes.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.textMuted, height: 1.5),
                ),
              ],
            ),
    );
  }
}

enum _BackupTone { primary, success, warning }

class _BackupActionCard extends StatelessWidget {
  final IconData icon;
  final _BackupTone tone;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _BackupActionCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = switch (tone) {
      _BackupTone.primary => colors.primary,
      _BackupTone.success => colors.success,
      _BackupTone.warning => colors.warning,
    };

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textStrong,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textMuted,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.chevron_right, color: colors.textMuted),
        ],
      ),
    );
  }
}
