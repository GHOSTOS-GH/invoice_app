// lib/screens/settings/document_page.dart
// Sous-page « Facture (PDF & images) » : aperçu en direct en haut, sections
// repliables (Entreprise, Éléments affichés, Style, Paiement & QR, Pied de
// page, Images), enregistrement immédiat et réinitialisation confirmée.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/document_settings.dart';
import '../../models/invoice.dart';
import '../../services/document_settings_service.dart';
import '../../services/invoice_image_service.dart';
import '../../services/invoice_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/ui/ui.dart';

class DocumentSettingsPage extends StatefulWidget {
  const DocumentSettingsPage({
    super.key,
    this.imageService,
    this.imagePicker,
  });

  /// Rendu des aperçus (remplaçable dans les tests).
  final InvoiceImageRenderer? imageService;

  final ImagePicker? imagePicker;

  @override
  State<DocumentSettingsPage> createState() => _DocumentSettingsPageState();
}

class _DocumentSettingsPageState extends State<DocumentSettingsPage> {
  final DocumentSettingsService _service = DocumentSettingsService.instance;
  late final InvoiceImageRenderer _imageService =
      widget.imageService ?? InvoiceImageService.instance;
  late final ImagePicker _picker = widget.imagePicker ?? ImagePicker();

  DocumentSettings? _settings;
  Invoice? _invoice;

  Uint8List? _preview;
  bool _previewLoading = true;
  String? _previewError;
  Timer? _debounce;
  int _previewToken = 0;
  bool _busyLogo = false;

  final TextEditingController _businessName = TextEditingController();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _registration = TextEditingController();
  final TextEditingController _payment = TextEditingController();
  final TextEditingController _qrText = TextEditingController();
  final TextEditingController _footer1 = TextEditingController();
  final TextEditingController _footer2 = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _businessName.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _registration.dispose();
    _payment.dispose();
    _qrText.dispose();
    _footer1.dispose();
    _footer2.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final settings = await _service.loadSettings();
    final invoice = await _loadInvoice();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _invoice = invoice;
      _syncControllers(settings);
    });
    await _refreshPreview();
  }

  /// Dernière facture enregistrée, sinon une facture d'exemple.
  Future<Invoice> _loadInvoice() async {
    try {
      final repository = InvoiceRepository();
      await repository.load();
      if (repository.invoices.isNotEmpty) {
        final sorted = repository.invoices.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return sorted.first;
      }
    } catch (error) {
      debugPrint('DocumentSettingsPage : factures illisibles ($error)');
    }
    return _sampleInvoice();
  }

  static Invoice _sampleInvoice() => Invoice(
        id: '1700000000000',
        clientName: 'Aïssatou Diop',
        createdAt: DateTime(2026, 10, 12, 9, 30),
        items: [
          InvoiceItem(
            id: 'demo-1',
            name: 'Riz parfumé 25 kg',
            quantity: 2,
            unitPrice: 15000,
          ),
          InvoiceItem(
            id: 'demo-2',
            name: 'Huile rouge 5 L',
            quantity: 1,
            unitPrice: 6500,
          ),
          InvoiceItem(
            id: 'demo-3',
            name: 'Ciment 50 kg',
            quantity: 4,
            unitPrice: 4250,
          ),
        ],
        status: InvoiceStatus.enLivraison,
        notes: 'Livraison prévue lundi matin à la boutique.',
        discount: 1000,
        taxRate: 5,
      );

  void _syncControllers(DocumentSettings settings) {
    void sync(TextEditingController controller, String value) {
      if (controller.text != value) controller.text = value;
    }

    sync(_businessName, settings.businessName);
    sync(_address, settings.businessAddress);
    sync(_phone, settings.businessPhone);
    sync(_email, settings.businessEmail);
    sync(_registration, settings.businessRegistration);
    sync(_payment, settings.paymentInfoText);
    sync(_qrText, settings.qrCustomText);
    sync(_footer1, settings.footerLine1);
    sync(_footer2, settings.footerLine2);
  }

  // --------------------------------------------------------------- aperçu

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _refreshPreview);
  }

  Future<void> _refreshPreview() async {
    final settings = _settings;
    final invoice = _invoice;
    if (settings == null || invoice == null) return;

    final token = ++_previewToken;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final result = await _imageService.render(
        invoice,
        settings: settings,
        imageFormat: settings.imageFormat,
      );
      if (!mounted || token != _previewToken) return;
      setState(() {
        _preview = result.pages.first;
        _previewLoading = false;
      });
    } catch (error) {
      if (!mounted || token != _previewToken) return;
      debugPrint('DocumentSettingsPage : aperçu impossible ($error)');
      setState(() {
        _previewError = 'Aperçu indisponible pour le moment.';
        _previewLoading = false;
      });
    }
  }

  // ------------------------------------------------------------ réglages

  /// Enregistrement immédiat : l'écran, le partage et les exports lisent
  /// toujours les valeurs courantes.
  void _save(DocumentSettings next, {bool refreshPreview = true}) {
    setState(() => _settings = next);
    unawaited(_service.saveSettings(next));
    if (refreshPreview) _schedulePreview();
  }

  Future<void> _copyFromReceipt() async {
    try {
      final updated = await _service.copyBusinessInfoFromReceipt();
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _syncControllers(updated);
      });
      _schedulePreview();
      AppSnack.success(context, 'Informations du reçu copiées');
    } catch (error) {
      if (!mounted) return;
      AppSnack.error(context, 'Copie impossible : $error');
    }
  }

  Future<void> _pickLogo() async {
    setState(() => _busyLogo = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
      );
      if (picked == null || !mounted) return;
      final path = await _service.importLogo(picked.path);
      if (!mounted) return;
      final settings = _settings;
      if (settings == null) return;
      _save(settings.copyWith(logoPath: path));
    } catch (error) {
      if (!mounted) return;
      AppSnack.error(context, 'Logo impossible à charger : $error');
    } finally {
      if (mounted) setState(() => _busyLogo = false);
    }
  }

  void _removeLogo() {
    final settings = _settings;
    if (settings == null) return;
    _save(settings.copyWith(clearLogo: true));
  }

  Future<void> _resetToDefaults() async {
    final color = AppColors.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Réinitialiser les réglages ?'),
        content: const Text(
          'Le modèle, les informations de l’entreprise, les éléments affichés '
          'et les réglages d’images reviendront aux valeurs par défaut.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Réinitialiser',
              style: TextStyle(color: color.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final settings = await _service.resetToDefaults();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _syncControllers(settings);
    });
    _schedulePreview();
    AppSnack.success(context, 'Réglages du document réinitialisés');
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(title: const Text('Facture (PDF & images)')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const SectionHeader(
                  title: 'Aperçu en direct',
                  subtitle: 'Sur la dernière facture (ou un exemple).',
                  icon: Icons.visibility_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: _previewArea(),
                ),
                const SizedBox(height: AppSpacing.lg),
                _Section(
                  title: 'Entreprise',
                  icon: Icons.storefront_outlined,
                  initiallyExpanded: true,
                  children: _businessSection(settings),
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Éléments affichés',
                  icon: Icons.checklist_outlined,
                  children: _elementsSection(settings),
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Style',
                  icon: Icons.palette_outlined,
                  children: _styleSection(settings),
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Paiement & QR',
                  icon: Icons.qr_code_2_outlined,
                  children: _paymentSection(settings),
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Pied de page',
                  icon: Icons.horizontal_rule,
                  children: _footerSection(settings),
                ),
                const SizedBox(height: AppSpacing.md),
                _Section(
                  title: 'Images',
                  icon: Icons.image_outlined,
                  children: _imageSection(settings),
                ),
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton.icon(
                  onPressed: _resetToDefaults,
                  icon: Icon(Icons.restart_alt, size: 20, color: colors.danger),
                  label: Text(
                    'Réinitialiser aux valeurs par défaut',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
    );
  }

  Widget _previewArea() {
    final colors = AppColors.of(context);
    if (_previewLoading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_previewError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 28, color: colors.textMuted),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _previewError!,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _refreshPreview,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    final preview = _preview;
    if (preview == null) {
      return const SizedBox(height: 120);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Image.memory(
          preview,
          fit: BoxFit.contain,
          width: double.infinity,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  List<Widget> _businessSection(DocumentSettings settings) => [
        AppTextField(
          controller: _businessName,
          label: 'Nom de l’entreprise',
          icon: Icons.badge_outlined,
          onChanged: (value) =>
              _save(settings.copyWith(businessName: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _address,
          label: 'Adresse',
          icon: Icons.place_outlined,
          onChanged: (value) =>
              _save(settings.copyWith(businessAddress: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _phone,
          label: 'Téléphone',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          onChanged: (value) =>
              _save(settings.copyWith(businessPhone: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _email,
          label: 'E-mail',
          icon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          onChanged: (value) =>
              _save(settings.copyWith(businessEmail: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _registration,
          label: 'NINEA / RC',
          icon: Icons.numbers,
          onChanged: (value) =>
              _save(settings.copyWith(businessRegistration: value)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Logo',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppColors.of(context).textStrong,
              ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _logoPreview(settings),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton(
                    onPressed: _busyLogo ? null : _pickLogo,
                    child: const Text('Choisir'),
                  ),
                  TextButton(
                    onPressed: _busyLogo || settings.logoPath == null
                        ? null
                        : _removeLogo,
                    child: const Text('Retirer'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: _copyFromReceipt,
          icon: const Icon(Icons.copy_all_outlined, size: 18),
          label: const Text('Copier depuis les infos du reçu'),
        ),
      ];

  Widget _logoPreview(DocumentSettings settings) {
    final colors = AppColors.of(context);
    final path = settings.logoPath;
    Widget child;
    if (path == null) {
      child = Icon(Icons.image_not_supported_outlined, color: colors.textMuted);
    } else if (path.startsWith('assets/')) {
      child = Image.asset(path, fit: BoxFit.contain);
    } else {
      child = Image.file(File(path), fit: BoxFit.contain);
    }
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: child,
    );
  }

  List<Widget> _elementsSection(DocumentSettings settings) => [
        _switchTile(
          title: 'Logo',
          value: settings.showLogo,
          onChanged: (value) => _save(settings.copyWith(showLogo: value)),
        ),
        _switchTile(
          title: 'Filigrane',
          subtitle: 'Logo en transparence sur le fond',
          value: settings.showWatermark,
          onChanged: (value) =>
              _save(settings.copyWith(showWatermark: value)),
        ),
        if (settings.showWatermark) _opacitySlider(settings),
        _switchTile(
          title: 'Informations de l’entreprise',
          value: settings.showBusinessInfo,
          onChanged: (value) =>
              _save(settings.copyWith(showBusinessInfo: value)),
        ),
        _switchTile(
          title: 'Numéro de facture',
          value: settings.showInvoiceNumber,
          onChanged: (value) =>
              _save(settings.copyWith(showInvoiceNumber: value)),
        ),
        _switchTile(
          title: 'Date et heure',
          value: settings.showDateTime,
          onChanged: (value) =>
              _save(settings.copyWith(showDateTime: value)),
        ),
        _switchTile(
          title: 'Badge de statut',
          value: settings.showStatusBadge,
          onChanged: (value) =>
              _save(settings.copyWith(showStatusBadge: value)),
        ),
        _switchTile(
          title: 'Numéro des lignes',
          value: settings.showItemIndex,
          onChanged: (value) =>
              _save(settings.copyWith(showItemIndex: value)),
        ),
        _switchTile(
          title: 'Prix unitaire',
          value: settings.showUnitPrice,
          onChanged: (value) =>
              _save(settings.copyWith(showUnitPrice: value)),
        ),
        _switchTile(
          title: 'Résumé Articles / Unités',
          value: settings.showTotalsSummary,
          onChanged: (value) =>
              _save(settings.copyWith(showTotalsSummary: value)),
        ),
        _switchTile(
          title: 'Notes',
          value: settings.showNotes,
          onChanged: (value) => _save(settings.copyWith(showNotes: value)),
        ),
      ];

  Widget _opacitySlider(DocumentSettings settings) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Opacité du filigrane : ${(settings.watermarkOpacity * 100).round()} %',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textMuted),
          ),
          Slider(
            min: 3,
            max: 15,
            divisions: 12,
            value: (settings.watermarkOpacity * 100).roundToDouble(),
            label: '${(settings.watermarkOpacity * 100).round()} %',
            onChanged: (value) => setState(() {
              _settings =
                  settings.copyWith(watermarkOpacity: value.round() / 100);
            }),
            onChangeEnd: (value) =>
                _save(_settings!.copyWith(watermarkOpacity: value.round() / 100)),
          ),
        ],
      ),
    );
  }

  List<Widget> _styleSection(DocumentSettings settings) {
    final colors = AppColors.of(context);
    return [
      for (final template in DocumentTemplate.values)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ChoiceTile(
            title: template.label,
            subtitle: template.description,
            selected: settings.template == template,
            onTap: () => _save(settings.copyWith(template: template)),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Couleur d’accent',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: colors.textStrong),
      ),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final color in DocumentSettings.accentPalette)
            InkWell(
              onTap: () => _save(settings.copyWith(accentColor: color)),
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: kMinTapTarget,
                height: kMinTapTarget,
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: settings.accentColor == color
                            ? colors.textStrong
                            : colors.border,
                        width: settings.accentColor == color ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ];
  }

  List<Widget> _paymentSection(DocumentSettings settings) => [
        _switchTile(
          title: 'Informations de paiement',
          subtitle: 'Numéros Mobile Money, coordonnées bancaires…',
          value: settings.showPaymentInfo,
          onChanged: (value) =>
              _save(settings.copyWith(showPaymentInfo: value)),
        ),
        if (settings.showPaymentInfo) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _payment,
            label: 'Texte de paiement',
            hint: 'Orange Money : 77 000 00 00',
            icon: Icons.payments_outlined,
            maxLines: 4,
            minLines: 2,
            onChanged: (value) =>
                _save(settings.copyWith(paymentInfoText: value)),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _switchTile(
          title: 'QR code',
          value: settings.showQr,
          onChanged: (value) => _save(settings.copyWith(showQr: value)),
        ),
        if (settings.showQr) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final mode in DocumentQrContent.values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ChoiceTile(
                title: mode.label,
                selected: settings.qrContentMode == mode,
                onTap: () => _save(settings.copyWith(qrContentMode: mode)),
              ),
            ),
          if (settings.qrContentMode == DocumentQrContent.custom)
            AppTextField(
              controller: _qrText,
              label: 'Texte du QR code',
              icon: Icons.text_fields,
              maxLines: 3,
              minLines: 1,
              onChanged: (value) =>
                  _save(settings.copyWith(qrCustomText: value)),
            ),
        ],
      ];

  List<Widget> _footerSection(DocumentSettings settings) => [
        _switchTile(
          title: 'Pied de page',
          value: settings.showFooter,
          onChanged: (value) => _save(settings.copyWith(showFooter: value)),
        ),
        if (settings.showFooter) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _footer1,
            label: 'Première ligne',
            icon: Icons.short_text,
            onChanged: (value) =>
                _save(settings.copyWith(footerLine1: value)),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            controller: _footer2,
            label: 'Seconde ligne',
            icon: Icons.short_text,
            onChanged: (value) =>
                _save(settings.copyWith(footerLine2: value)),
          ),
        ],
        _switchTile(
          title: 'Numéros de page',
          subtitle: '« Page X / Y » en bas de chaque page',
          value: settings.showPageNumbers,
          onChanged: (value) =>
              _save(settings.copyWith(showPageNumbers: value)),
        ),
      ];

  List<Widget> _imageSection(DocumentSettings settings) {
    final colors = AppColors.of(context);
    return [
      for (final format in DocumentImageFormat.values)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ChoiceTile(
            title: format.label,
            subtitle: format.description,
            selected: settings.imageFormat == format,
            onTap: () => _save(settings.copyWith(imageFormat: format)),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      for (final quality in DocumentImageQuality.values)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: ChoiceTile(
            title: quality.label,
            subtitle: '${quality.dpi} dpi',
            selected: settings.imageQuality == quality,
            onTap: () => _save(settings.copyWith(imageQuality: quality)),
          ),
        ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Qualité JPG : ${settings.jpgQuality}',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: colors.textMuted),
      ),
      Slider(
        min: 70,
        max: 95,
        divisions: 25,
        value: settings.jpgQuality.toDouble(),
        label: '${settings.jpgQuality}',
        onChanged: (value) =>
            setState(() => _settings = settings.copyWith(jpgQuality: value.round())),
        onChangeEnd: (value) =>
            _save(_settings!.copyWith(jpgQuality: value.round())),
      ),
    ];
  }

  Widget _switchTile({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.of(context).textStrong,
            ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.of(context).textMuted),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Section repliable : en-tête tactile de 56 dp, contenu aligné en largeur.
class _Section extends StatefulWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 20, color: colors.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: colors.textStrong,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}
