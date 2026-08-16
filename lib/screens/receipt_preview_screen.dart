// lib/screens/receipt_preview_screen.dart
// Écran « Aperçu du reçu » : simule le ticket thermique avant
// impression, se met à jour en temps réel quand les paramètres
// changent, et envoie les données à l'imprimante — Bluetooth (Android)
// ou Wi-Fi (Android + iPhone).

import 'dart:io';
import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/network_printer_service.dart';
import '../services/receipt_builder.dart';
import '../services/receipt_settings_service.dart';
import '../utils/constants.dart';
import '../widgets/bluetooth_device_sheet.dart';
import '../widgets/network_printer_sheet.dart';
import '../widgets/receipt_preview.dart';

class ReceiptPreviewScreen extends StatefulWidget {
  final Invoice invoice;
  const ReceiptPreviewScreen({super.key, required this.invoice});

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final ReceiptSettingsService _settingsService = ReceiptSettingsService();
  final BluetoothPrinterService _bluetoothService = BluetoothPrinterService();
  final NetworkPrinterService _networkService = NetworkPrinterService();

  Future<ReceiptContent>? _contentFuture;
  bool _printingBt = false;
  bool _printingWifi = false;
  BluetoothDevice? _btDevice;
  String? _wifiIp;

  bool get _isAndroid => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    ReceiptSettingsService.settingsNotifier.addListener(_onSettingsChanged);
    _reload();
    _loadPrinters();
  }

  @override
  void dispose() {
    ReceiptSettingsService.settingsNotifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// Recharge le contenu dès que les paramètres changent → aperçu en temps réel.
  void _onSettingsChanged() => _reload();

  void _reload() {
    // Garde mounted : le notifier peut encore notifier après le dispose
    // de l'écran (ex. pendant une transition de route).
    if (!mounted) return;
    setState(() {
      _contentFuture = _loadContent();
    });
  }

  Future<ReceiptContent> _loadContent() async {
    final settings = await _settingsService.loadSettings();
    Uint8List? logoBytes;
    if (settings.logoPath != null) {
      try {
        logoBytes = await File(settings.logoPath!).readAsBytes();
      } catch (_) {
        logoBytes = null;
      }
    }
    // Logo préparé hors du thread UI (isolate via compute()) puis mis en
    // cache : le traitement lourd n'est fait qu'une fois, jamais à chaque
    // rechargement de l'aperçu.
    await ReceiptBuilder.prepareLogoCached(
      logoBytes: logoBytes,
      logoPath: settings.logoPath,
      maxWidth: ReceiptBuilder.logoMaxWidth(settings.format),
    );
    return ReceiptBuilder.buildContent(widget.invoice, settings,
        logoBytes: logoBytes);
  }

  Future<void> _loadPrinters() async {
    // Le Bluetooth n'existe que sur Android : on ne touche pas au plugin
    // sur iOS (il lèverait une exception sans gestionnaire).
    BluetoothDevice? device;
    if (_isAndroid) {
      try {
        device = await _bluetoothService.getDefaultDevice();
      } catch (_) {
        device = null;
      }
    }
    final ip = await _networkService.getDefaultPrinterIp();
    if (!mounted) return;
    setState(() {
      _btDevice = device;
      _wifiIp = ip;
    });
  }

  /// Menu du haut : choisir / configurer l'imprimante.
  Future<void> _openPrinterMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
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
              'Imprimante du reçu',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.bluetooth, color: Color(0xFF2563EB)),
              title: const Text('Imprimante Bluetooth',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                _btDevice?.name ?? 'Non configurée · Android uniquement',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              trailing: _isAndroid
                  ? const Icon(Icons.chevron_right)
                  : const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
              onTap: _isAndroid
                  ? () => Navigator.pop(ctx, 'bluetooth')
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.wifi, color: Color(0xFF2563EB)),
              title: const Text('Imprimante Wi-Fi',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                _wifiIp ?? 'Non configurée · Android + iPhone',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, 'wifi'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'bluetooth') {
      final device = await showBluetoothDeviceSheet(context, _bluetoothService);
      if (device != null && mounted) {
        setState(() => _btDevice = device);
      }
    } else {
      final saved =
          await showNetworkPrinterSheet(context, _networkService);
      if (saved && mounted) {
        final ip = await _networkService.getDefaultPrinterIp();
        if (mounted) setState(() => _wifiIp = ip);
      }
    }
    _loadPrinters();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _printBluetooth() async {
    if (!_isAndroid) {
      _showSnack(
          "L'impression Bluetooth est disponible uniquement sur Android.",
          isError: true);
      return;
    }
    setState(() => _printingBt = true);
    try {
      final future = _contentFuture;
      final content = future == null ? null : await future;
      if (content == null) throw StateError('Aperçu indisponible, réessayez.');
      await _bluetoothService.imprimerFacture(widget.invoice,
          settings: content.settings);
      if (!mounted) return;
      _showSnack('Reçu envoyé à l’imprimante Bluetooth ✓');
    } catch (e) {
      _showPrintError(e, openSheet: _openPrinterMenu);
    } finally {
      if (mounted) setState(() => _printingBt = false);
    }
  }

  Future<void> _printWifi() async {
    setState(() => _printingWifi = true);
    try {
      final future = _contentFuture;
      final content = future == null ? null : await future;
      if (content == null) throw StateError('Aperçu indisponible, réessayez.');
      await _networkService.imprimerFacture(widget.invoice,
          settings: content.settings);
      if (!mounted) return;
      _showSnack('Reçu envoyé à l’imprimante Wi-Fi ✓');
    } catch (e) {
      _showPrintError(e, openSheet: _openPrinterMenu);
    } finally {
      if (mounted) setState(() => _printingWifi = false);
    }
  }

  void _showPrintError(Object e, {required Future<void> Function() openSheet}) {
    if (!mounted) return;
    final message = e.toString().replaceFirst('Bad state: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Configurer',
          textColor: Colors.white,
          onPressed: openSheet,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: const Text('Aperçu du reçu'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Configurer l’imprimante',
            onPressed: _openPrinterMenu,
          ),
        ],
      ),
      body: FutureBuilder<ReceiptContent>(
        future: _contentFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final content = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ReceiptPreviewView(content: content),
                ),
              ),
              const SizedBox(height: 16),
              _buildInfoBar(content),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              if (_isAndroid) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printingBt || _printingWifi ? null : _printBluetooth,
                    icon: _printingBt
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth),
                    label: Text(_printingBt ? 'Envoi…' : 'Bluetooth'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: _isAndroid ? 1 : 2,
                child: ElevatedButton.icon(
                  onPressed: _printingBt || _printingWifi ? null : _printWifi,
                  icon: _printingWifi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.wifi),
                  label: Text(_printingWifi ? 'Envoi…' : 'Imprimer Wi-Fi'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBar(ReceiptContent content) {
    final settings = content.settings;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Constants.cardRadius),
        border: Border.all(color: const Color(0xFFEDF1F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _chip(
                icon: Icons.straighten,
                label: settings.format.label,
              ),
              const SizedBox(width: 8),
              _chip(
                icon: _wifiIp != null
                    ? Icons.wifi
                    : Icons.wifi_off,
                label: _wifiIp ?? 'Wi-Fi : non configuré',
                color: _wifiIp != null
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF94A3B8),
              ),
            ],
          ),
          if (_isAndroid) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _chip(
                  icon: _btDevice != null
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  label: _btDevice?.name ?? 'Bluetooth : non configuré',
                  color: _btDevice != null
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: _openPrinterMenu,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Configurer les imprimantes'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final c = color ?? const Color(0xFF2563EB);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: c),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
