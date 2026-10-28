// lib/screens/share_invoice_screen.dart
// Écran « Partager la facture » : aperçu réel (l'image générée depuis le
// PDF), choix du modèle et du format de sortie pour CE partage (sans modifier
// les réglages par défaut), bouton principal « Partager » et accès direct au
// reçu thermique.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/document_settings.dart';
import '../models/invoice.dart';
import '../services/document_settings_service.dart';
import '../services/invoice_image_service.dart';
import '../services/pdf_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../widgets/ui/ui.dart';
import 'receipt_preview_screen.dart';

class ShareInvoiceScreen extends StatefulWidget {
  const ShareInvoiceScreen({
    super.key,
    required this.invoice,
    this.pdfService,
    this.imageService,
    this.settingsLoader,
  });

  final Invoice invoice;
  final PdfService? pdfService;
  final InvoiceImageRenderer? imageService;
  final Future<DocumentSettings> Function()? settingsLoader;

  @override
  State<ShareInvoiceScreen> createState() => _ShareInvoiceScreenState();
}

class _ShareInvoiceScreenState extends State<ShareInvoiceScreen> {
  late final PdfService _pdfService = widget.pdfService ?? PdfService();
  late final InvoiceImageRenderer _imageService =
      widget.imageService ?? InvoiceImageService.instance;

  DocumentSettings? _settings;
  DocumentTemplate _template = DocumentTemplate.modern;
  InvoiceOutputFormat _output = InvoiceOutputFormat.pdf;

  List<Uint8List>? _preview;
  bool _loading = true;
  bool _sharing = false;
  String? _error;
  bool _forcedA4 = false;

  /// Jeton de génération : une réponse tardive n'écrase jamais l'aperçu
  /// d'un réglage plus récent.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final loader = widget.settingsLoader ??
        DocumentSettingsService.instance.loadSettings;
    try {
      final settings = await loader();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _template = settings.template;
      });
      await _generatePreview();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Réglages indisponibles : $error';
        _loading = false;
      });
    }
  }

  Future<void> _generatePreview() async {
    final settings = _settings;
    if (settings == null) return;
    final token = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });

    // Le PDF se prévisualise en A4 ; les images suivent le réglage courant.
    final format = _output == InvoiceOutputFormat.pdf
        ? DocumentImageFormat.a4
        : settings.imageFormat;
    try {
      final result = await _imageService.render(
        widget.invoice,
        settings: settings.copyWith(template: _template),
        imageFormat: format,
      );
      if (!mounted || token != _generation) return;
      setState(() {
        _preview = result.pages;
        _forcedA4 = result.forcedA4;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _generation) return;
      setState(() {
        _error = 'Aperçu indisponible. Vérifiez puis réessayez.';
        _loading = false;
        debugPrint('ShareInvoiceScreen : $error');
      });
    }
  }

  void _selectTemplate(DocumentTemplate template) {
    if (_template == template) return;
    setState(() => _template = template);
    _generatePreview();
  }

  void _selectOutput(InvoiceOutputFormat output) {
    if (_output == output) return;
    setState(() => _output = output);
    _generatePreview();
  }

  Future<void> _share() async {
    final settings = _settings;
    if (settings == null || _sharing) return;
    setState(() => _sharing = true);

    final effective = settings.copyWith(template: _template);
    try {
      if (_output == InvoiceOutputFormat.pdf) {
        await _pdfService.shareAsPdf(widget.invoice, settings: effective);
      } else {
        final result = await _imageService.render(
          widget.invoice,
          settings: effective,
          imageFormat: settings.imageFormat,
          output: _output,
        );
        if (!mounted) return;
        if (result.forcedA4 && result.pages.length > 1) {
          AppSnack.info(
            context,
            'Facture trop longue : partagée en ${result.pages.length} pages A4.',
            duration: const Duration(seconds: 4),
          );
        }
        await _pdfService.shareImagePages(
          result.pages,
          widget.invoice,
          _output == InvoiceOutputFormat.jpg ? 'jpg' : 'png',
          _output == InvoiceOutputFormat.jpg ? 'image/jpeg' : 'image/png',
        );
      }
    } catch (error) {
      if (!mounted) return;
      AppSnack.error(context, 'Partage impossible : $error');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _openReceipt() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptPreviewScreen(invoice: widget.invoice),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(title: const Text('Partager la facture')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const SectionHeader(
            title: 'Aperçu',
            subtitle: 'Le document tel qu’il sera partagé.',
            icon: Icons.visibility_outlined,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: _previewArea(),
          ),
          if (_forcedA4) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: colors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Facture trop longue pour une image continue : '
                    'elle sera partagée en plusieurs pages A4.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _templateSelector(),
          const SizedBox(height: AppSpacing.lg),
          _outputSelector(),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: (_loading || _error != null || _sharing) ? null : _share,
            icon: _sharing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.onPrimary,
                    ),
                  )
                : const Icon(Icons.ios_share, size: 20),
            label: Text(_sharing ? 'Partage en cours…' : 'Partager'),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _sharing ? null : _openReceipt,
            icon: const Icon(Icons.print_outlined, size: 20),
            label: const Text('Reçu thermique (58 / 80 mm)'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Le modèle et le format choisis ici ne modifient pas les réglages '
            'par défaut : ils s’appliquent à ce partage uniquement.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _previewArea() {
    final colors = AppColors.of(context);

    if (_loading) {
      return SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Génération de l’aperçu…',
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

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 32, color: colors.danger),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.textBody),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _generatePreview,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    final pages = _preview;
    if (pages == null || pages.isEmpty) {
      return const SizedBox(height: 120);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < pages.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.memory(
              pages[i],
              fit: BoxFit.fitWidth,
              width: double.infinity,
              gaplessPlayback: true,
            ),
          ),
          if (pages.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Page ${i + 1} / ${pages.length}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.textMuted),
              ),
            ),
        ],
      ],
    );
  }

  Widget _templateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Modèle',
          subtitle: 'Appliqué à ce partage uniquement.',
          icon: Icons.palette_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              for (final template in DocumentTemplate.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ChoiceTile(
                    title: template.label,
                    subtitle: template.description,
                    selected: _template == template,
                    onTap: () => _selectTemplate(template),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _outputSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Format de sortie',
          icon: Icons.file_present_outlined,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              for (final option in _outputOptions)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: ChoiceTile(
                    title: option.label,
                    subtitle: option.subtitle,
                    icon: option.icon,
                    selected: _output == option.format,
                    onTap: () => _selectOutput(option.format),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static const List<_OutputOption> _outputOptions = [
    _OutputOption(
      format: InvoiceOutputFormat.pdf,
      label: 'PDF',
      subtitle: 'Idéal pour l’impression et l’archivage',
      icon: Icons.picture_as_pdf_outlined,
    ),
    _OutputOption(
      format: InvoiceOutputFormat.png,
      label: 'PNG',
      subtitle: 'Image nette pour WhatsApp et e-mail',
      icon: Icons.image_outlined,
    ),
    _OutputOption(
      format: InvoiceOutputFormat.jpg,
      label: 'JPG',
      subtitle: 'Image compressée, plus légère',
      icon: Icons.photo_camera_outlined,
    ),
  ];
}

class _OutputOption {
  const _OutputOption({
    required this.format,
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  final InvoiceOutputFormat format;
  final String label;
  final String subtitle;
  final IconData icon;
}
