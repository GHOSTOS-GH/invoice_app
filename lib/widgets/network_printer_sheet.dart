// lib/widgets/network_printer_sheet.dart
// Configuration de l'imprimante thermique Wi-Fi (ESC/POS) :
// saisie de l'adresse IP, test de connexion et mémorisation comme
// imprimante par défaut.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/network_printer_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'ui/sheet_handle.dart';

/// Ouvre la feuille de configuration de l'imprimante Wi-Fi.
/// Retourne true si une imprimante a été enregistrée.
Future<bool> showNetworkPrinterSheet(
  BuildContext context,
  NetworkPrinterService service,
) {
  final colors = AppColors.of(context);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
    ),
    builder: (ctx) => _NetworkPrinterSheet(service: service),
  ).then((v) => v ?? false);
}

class _NetworkPrinterSheet extends StatefulWidget {
  final NetworkPrinterService service;
  const _NetworkPrinterSheet({required this.service});

  @override
  State<_NetworkPrinterSheet> createState() => _NetworkPrinterSheetState();
}

class _NetworkPrinterSheetState extends State<_NetworkPrinterSheet> {
  late final TextEditingController _ipController;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ip = await widget.service.getDefaultPrinterIp();
    if (!mounted) return;
    if (ip != null) _ipController.text = ip;
  }

  String? _validate() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return 'Saisissez l\'adresse IP de l\'imprimante.';
    final parts = ip.split('.');
    if (parts.length != 4) {
      return 'Adresse IP invalide (exemple : 192.168.1.50).';
    }
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) {
        return 'Adresse IP invalide (exemple : 192.168.1.50).';
      }
    }
    return null;
  }

  Future<void> _test() async {
    final error = _validate();
    if (error != null) {
      setState(() {
        _testResult = error;
        _testOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result =
        await widget.service.testConnection(_ipController.text.trim());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = result == null;
      _testResult = result ?? 'Imprimante détectée sur le port 9100 ✓';
    });
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() {
        _testResult = error;
        _testOk = false;
      });
      return;
    }
    await widget.service.saveDefaultPrinterIp(_ipController.text.trim());
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Text(
              'Imprimante Wi-Fi',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'ESC/POS · port 9100 · Android + iPhone',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _ipController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Adresse IP de l\'imprimante',
                      hintText: '192.168.1.50',
                      prefixIcon: Icon(Icons.wifi, size: 20),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_testResult != null)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: (_testOk ? colors.success : colors.danger)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _testOk
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 18,
                            color: _testOk ? colors.success : colors.danger,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _testResult!,
                              style: TextStyle(
                                fontSize: 13,
                                color: _testOk ? colors.success : colors.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: Text(
                      _testing ? 'Test en cours…' : 'Tester la connexion',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Enregistrer cette imprimante'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'L\'imprimante doit être connectée au même réseau Wi-Fi '
                    'que votre téléphone/tablette. Son adresse IP se trouve '
                    'dans les réglages de l\'imprimante (ou sur une page de '
                    'test). Le port 9100 est utilisé par défaut.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
