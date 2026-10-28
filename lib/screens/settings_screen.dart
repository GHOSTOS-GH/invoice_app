// lib/screens/settings_screen.dart
// Paramètres : liste d'entrées groupées en cartes, chacune ouvrant une
// sous-page dédiée.

import 'package:flutter/material.dart';

import '../services/history_service.dart';
import '../services/invoice_repository.dart';
import '../services/product_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_controller.dart';
import '../widgets/ui/app_card.dart';
import '../widgets/ui/section_header.dart';
import 'settings/appearance_page.dart';
import 'settings/backup_page.dart';
import 'settings/document_page.dart';
import 'settings/name_history_page.dart';
import 'settings/products_page.dart';
import 'settings/receipt_page.dart';
import 'settings/security_page.dart';

class SettingsScreen extends StatefulWidget {
  /// Appelé après une restauration de données pour rafraîchir les autres écrans.
  final VoidCallback? onDataRestored;

  /// Appelé après une déconnexion (retour à l'écran de connexion).
  final VoidCallback? onLogout;

  const SettingsScreen({super.key, this.onDataRestored, this.onLogout});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final HistoryService _historyService = HistoryService();
  final ProductService _productService = ProductService();
  final InvoiceRepository _repository = InvoiceRepository();

  int _clientCount = 0;
  int _productHistoryCount = 0;
  int _productCount = 0;
  int _invoiceCount = 0;

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
    final clients = await _historyService.getClientNames();
    final productNames = await _historyService.getProductNames();
    final products = await _productService.loadProducts();
    if (!mounted) return;
    setState(() {
      _clientCount = clients.length;
      _productHistoryCount = productNames.length;
      _productCount = products.length;
      _invoiceCount = _repository.invoices.length;
    });
  }

  void _onRepositoryChanged() {
    if (!mounted) return;
    setState(() => _invoiceCount = _repository.invoices.length);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    final catalog = <Widget>[
      _SettingsTile(
        icon: Icons.person_outline,
        title: 'Clients',
        subtitle: '$_clientCount nom(s) mémorisé(s) pour l\'autocomplétion',
        onTap: () => _open(
          const NameHistoryPage(kind: NameHistoryKind.clients),
        ),
      ),
      _SettingsTile(
        icon: Icons.inventory_2_outlined,
        title: 'Historique des articles',
        subtitle: '$_productHistoryCount nom(s) de produit(s) mémorisé(s)',
        onTap: () => _open(
          const NameHistoryPage(kind: NameHistoryKind.products),
        ),
      ),
      _SettingsTile(
        icon: Icons.storefront_outlined,
        title: 'Produits',
        subtitle: '$_productCount produit(s) dans la bibliothèque',
        onTap: () => _open(const ProductsPage()),
      ),
    ];

    final billing = <Widget>[
      _SettingsTile(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Facture (PDF & images)',
        subtitle:
            'Entreprise, éléments affichés, modèle, QR et images',
        onTap: () => _open(const DocumentSettingsPage()),
      ),
    ];

    final printing = <Widget>[
      _SettingsTile(
        icon: Icons.print_outlined,
        title: 'Reçu thermique',
        subtitle: 'Boutique, logo, format 58 / 80 mm et imprimante',
        onTap: () => _open(const ReceiptSettingsPage()),
      ),
    ];

    final data = <Widget>[
      _SettingsTile(
        icon: Icons.backup_outlined,
        title: 'Sauvegarde',
        subtitle:
            '$_invoiceCount facture(s) · export CSV, JSON et restauration',
        onTap: () => _open(
          BackupPage(onDataRestored: widget.onDataRestored),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _buildGroup(
            title: 'Catalogue',
            icon: Icons.category_outlined,
            tiles: catalog,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildGroup(
            title: 'Facturation',
            icon: Icons.receipt_long_outlined,
            tiles: billing,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildGroup(
            title: 'Impression',
            icon: Icons.print_outlined,
            tiles: printing,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildGroup(
            title: 'Données',
            icon: Icons.storage_outlined,
            tiles: data,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildGroup(
            title: 'Application',
            icon: Icons.tune,
            tiles: [
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: 'Apparence',
                subtitle: 'Thème Système, Clair ou Sombre',
                trailing: ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeController.instance,
                  builder: (context, mode, _) => Text(
                    ThemeController.labelOf(mode),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                onTap: () => _open(const AppearancePage()),
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'Sécurité',
                subtitle: 'Identifiant, code et déconnexion',
                onTap: () => _open(SecurityPage(onLogout: widget.onLogout)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              'Montants en FCFA · Stockage local',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _buildGroup({
    required String title,
    required IconData icon,
    required List<Widget> tiles,
  }) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, icon: icon),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) Divider(height: 1, color: colors.border, indent: 64),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground = colors.textStrong;
    final secondary = colors.textMuted;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: colors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: secondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (trailing != null) trailing!,
            if (onTap != null)
              Icon(Icons.chevron_right, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
