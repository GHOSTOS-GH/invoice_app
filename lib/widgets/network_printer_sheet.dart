// lib/widgets/network_printer_sheet.dart
// Configuration de l'imprimante thermique Wi-Fi (ESC/POS) :
// saisie de l'adresse IP, test de connexion et mémorisation comme
// imprimante par défaut.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/network_printer_service.dart';

/// Ouvre la feuille de configuration de l'imprimante Wi-Fi.
/// Retourne true si une imprimante a été enregistrée.
Future<bool> showNetworkPrinterSheet(
  BuildContext context,
  NetworkPrinterService service,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
    final result = await widget.service
        .testConnection(_ipController.text.trim());
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Imprimante Wi-Fi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'ESC/POS · port 9100 · Android + iPhone',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _ipController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Adresse IP de l\'imprimante',
                      hintText: '192.168.1.50',
                      prefixIcon: Icon(Icons.wifi),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_testResult != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (_testOk
                                ? const Color(0xFF16A34A)
                                : Colors.red)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _testOk
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 18,
                            color: _testOk
                                ? const Color(0xFF16A34A)
                                : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testResult!,
                              style: TextStyle(
                                fontSize: 13,
                                color: _testOk
                                    ? const Color(0xFF166534)
                                    : const Color(0xFF991B1B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: Text(_testing ? 'Test en cours…' : 'Tester la connexion'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Enregistrer cette imprimante'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'L\'imprimante doit être connectée au même réseau Wi-Fi que votre téléphone/tablette. Son adresse IP se trouve dans les réglages de l\'imprimante (ou sur une page de test). Le port 9100 est utilisé par défaut.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
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
