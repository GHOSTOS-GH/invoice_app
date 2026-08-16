// lib/widgets/receipt_settings_tab.dart
// Onglet « Reçu » des paramètres : informations de la boutique,
// logo (monochrome), format du ticket (58/80 mm), éléments affichés
// et imprimante Bluetooth par défaut. Toute modification est
// enregistrée immédiatement et l'aperçu se met à jour en temps réel.

import 'dart:io';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/receipt_settings.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/network_printer_service.dart';
import '../services/receipt_settings_service.dart';
import '../utils/constants.dart';
import 'bluetooth_device_sheet.dart';
import 'network_printer_sheet.dart';

class ReceiptSettingsTab extends StatefulWidget {
  const ReceiptSettingsTab({super.key});

  @override
  State<ReceiptSettingsTab> createState() => _ReceiptSettingsTabState();
}

class _ReceiptSettingsTabState extends State<ReceiptSettingsTab> {
  final ReceiptSettingsService _service = ReceiptSettingsService();
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  final NetworkPrinterService _networkService = NetworkPrinterService();
  final ImagePicker _picker = ImagePicker();

  late ReceiptSettings _settings;
  bool _loading = true;
  bool _pickingLogo = false;

  final _shopNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nineaController = TextEditingController();
  final _cashierController = TextEditingController();
  final _footerController = TextEditingController();

  BluetoothDevice? _printerDevice;
  String? _wifiIp;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _nineaController.dispose();
    _cashierController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final settings = await _service.loadSettings();
    // Le Bluetooth n'existe que sur Android : on n'interroge pas le plugin
    // sur iOS (il lèverait une exception sans gestionnaire).
    if (Platform.isAndroid) {
      _printerDevice = await _printerService.getDefaultDevice();
    }
    _wifiIp = await _networkService.getDefaultPrinterIp();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _syncControllers(settings);
      _loading = false;
    });
  }

  void _syncControllers(ReceiptSettings settings) {
    _shopNameController.text = settings.shopName;
    _addressController.text = settings.shopAddress;
    _phoneController.text = settings.shopPhone;
    _nineaController.text = settings.shopNinea;
    _cashierController.text = settings.cashierName;
    _footerController.text = settings.footerMessage;
  }

  Future<void> _save(ReceiptSettings settings) async {
    _settings = settings;
    await _service.saveSettings(settings);
  }

  // ---------- Logo ----------

  Future<void> _pickLogo() async {
    setState(() => _pickingLogo = true);
    try {
      final picked =
          await _picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
      if (picked == null || !mounted) return;

      final dir = await getApplicationDocumentsDirectory();
      final dest = File('${dir.path}/receipt_logo.png');
      await File(picked.path).copy(dest.path);

      await _save(_settings.copyWith(logoPath: dest.path));
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors du chargement du logo : $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    await _save(_settings.copyWith(clearLogo: true));
    if (!mounted) return;
    setState(() {});
  }

  // ---------- Imprimante ----------

  Future<void> _openPrinterSheet() async {
    final device = await showBluetoothDeviceSheet(context, _printerService);
    if (device != null && mounted) {
      setState(() => _printerDevice = device);
    } else if (mounted) {
      _printerDevice = await _printerService.getDefaultDevice();
      setState(() {});
    }
  }

  Future<void> _openNetworkPrinterSheet() async {
    final saved = await showNetworkPrinterSheet(context, _networkService);
    if (saved && mounted) {
      _wifiIp = await _networkService.getDefaultPrinterIp();
      setState(() {});
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionHeader(
          icon: Icons.storefront_outlined,
          title: 'Informations boutique',
          subtitle: 'Affichées en haut du ticket',
        ),
        const SizedBox(height: 10),
        _card(
          children: [
            _textField(
              _shopNameController,
              'Nom de la boutique',
              Icons.storefront,
              onChanged: (v) => _save(_settings.copyWith(shopName: v)),
            ),
            const SizedBox(height: 12),
            _textField(
              _addressController,
              'Adresse',
              Icons.location_on_outlined,
              onChanged: (v) => _save(_settings.copyWith(shopAddress: v)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _textField(
                    _phoneController,
                    'Téléphone',
                    Icons.phone_outlined,
                    onChanged: (v) => _save(_settings.copyWith(shopPhone: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _textField(
                    _nineaController,
                    'NINEA / RC',
                    Icons.badge_outlined,
                    onChanged: (v) => _save(_settings.copyWith(shopNinea: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _textField(
              _cashierController,
              'Nom du caissier',
              Icons.person_outline,
              onChanged: (v) => _save(_settings.copyWith(cashierName: v)),
            ),
            const SizedBox(height: 12),
            _textField(
              _footerController,
              'Message pied de page',
              Icons.favorite_border,
              maxLines: 2,
              onChanged: (v) => _save(_settings.copyWith(footerMessage: v)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _sectionHeader(
          icon: Icons.image_outlined,
          title: 'Logo',
          subtitle: 'Converti en monochrome à l’impression',
        ),
        const SizedBox(height: 10),
        _card(
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _settings.logoPath != null
                      ? Image.file(File(_settings.logoPath!),
                          fit: BoxFit.contain)
                      : const Icon(Icons.add_photo_alternate_outlined,
                          color: Color(0xFF94A3B8), size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _settings.logoPath != null
                            ? 'Logo actuel'
                            : 'Aucun logo',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'PNG / JPG. Le logo est imprimé en noir & blanc en haut du ticket.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_settings.logoPath != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Supprimer le logo',
                    onPressed: _removeLogo,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickingLogo ? null : _pickLogo,
                icon: _pickingLogo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(_settings.logoPath != null
                    ? 'Changer le logo'
                    : 'Choisir une image'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _sectionHeader(
          icon: Icons.straighten,
          title: 'Format du ticket',
          subtitle: 'Largeur de l’imprimante thermique',
        ),
        const SizedBox(height: 10),
        _card(
          children: [
            SegmentedButton<ReceiptPaperFormat>(
              segments: ReceiptPaperFormat.values
                  .map(
                    (f) => ButtonSegment(
                      value: f,
                      label: Text(f.label),
                      icon: Icon(
                        f == ReceiptPaperFormat.mm58
                            ? Icons.receipt_long
                            : Icons.receipt,
                        size: 18,
                      ),
                    ),
                  )
                  .toList(),
              selected: {_settings.format},
              onSelectionChanged: (selection) {
                _save(_settings.copyWith(format: selection.first));
              },
            ),
            const SizedBox(height: 10),
            Text(
              '${_settings.format.label} → ${_settings.format.charsPerLine} caractères par ligne',
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _sectionHeader(
          icon: Icons.tune,
          title: 'Éléments affichés',
          subtitle: 'Afficher ou masquer chaque partie du ticket',
        ),
        const SizedBox(height: 10),
        _card(
          children: [
            _switchTile(
              'Logo',
              Icons.image_outlined,
              _settings.showLogo,
              (v) => _save(_settings.copyWith(showLogo: v)),
            ),
            _switchTile(
              'Nom de la boutique',
              Icons.storefront_outlined,
              _settings.showShopName,
              (v) => _save(_settings.copyWith(showShopName: v)),
            ),
            _switchTile(
              'Adresse',
              Icons.location_on_outlined,
              _settings.showAddress,
              (v) => _save(_settings.copyWith(showAddress: v)),
            ),
            _switchTile(
              'Téléphone',
              Icons.phone_outlined,
              _settings.showPhone,
              (v) => _save(_settings.copyWith(showPhone: v)),
            ),
            _switchTile(
              'NINEA / RC',
              Icons.badge_outlined,
              _settings.showNinea,
              (v) => _save(_settings.copyWith(showNinea: v)),
            ),
            _switchTile(
              'Message pied de page',
              Icons.favorite_border,
              _settings.showFooter,
              (v) => _save(_settings.copyWith(showFooter: v)),
            ),
            _switchTile(
              'QR code de la facture',
              Icons.qr_code_2,
              _settings.showBarcode,
              (v) => _save(_settings.copyWith(showBarcode: v)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (Platform.isAndroid) ...[
          _sectionHeader(
            icon: Icons.bluetooth,
            title: 'Imprimante Bluetooth',
            subtitle: 'Appairée dans les réglages Android',
          ),
          const SizedBox(height: 10),
          _card(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (_printerDevice != null
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF64748B))
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _printerDevice != null
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth,
                      color: _printerDevice != null
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _printerDevice?.name ?? 'Aucune imprimante',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          _printerDevice?.address ??
                              'Choisissez votre imprimante thermique',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: _openPrinterSheet,
                    child:
                        Text(_printerDevice != null ? 'Changer' : 'Choisir'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        _card(
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (_wifiIp != null
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF64748B))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _wifiIp != null ? Icons.wifi : Icons.wifi_off,
                    color: _wifiIp != null
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _wifiIp ?? 'Aucune imprimante Wi-Fi',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _wifiIp != null
                            ? 'Port 9100 · Android + iPhone'
                            : 'Saisissez l\'adresse IP de l\'imprimante',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _openNetworkPrinterSheet,
                  child: Text(_wifiIp != null ? 'Changer' : 'Configurer'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '💡 Astuce : ouvrez « Aperçu du reçu » depuis une facture pour voir le ticket en temps réel avant impression.',
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.grey[600],
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF2563EB)),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Constants.cardRadius),
        border: Border.all(color: const Color(0xFFEDF1F7)),
      ),
      child: Column(children: children),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        isDense: maxLines == 1,
      ),
    );
  }

  Widget _switchTile(
    String title,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      secondary: Icon(icon, size: 20, color: const Color(0xFF64748B)),
      value: value,
      activeTrackColor: const Color(0xFF2563EB),
      onChanged: onChanged,
    );
  }
}
