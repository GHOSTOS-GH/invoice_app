// lib/widgets/bluetooth_device_sheet.dart
// Feuille modale de gestion de l'imprimante Bluetooth :
// état du Bluetooth, appareils appairés, connexion et mémorisation
// de l'imprimante par défaut.

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';

import '../services/bluetooth_printer_service.dart';
import '../utils/constants.dart';

/// Ouvre la feuille de sélection de l'imprimante Bluetooth.
/// Retourne l'appareil sélectionné (et connecté), ou null si annulé.
Future<BluetoothDevice?> showBluetoothDeviceSheet(
  BuildContext context,
  BluetoothPrinterService service,
) {
  return showModalBottomSheet<BluetoothDevice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _BluetoothDeviceSheet(service: service),
  );
}

class _BluetoothDeviceSheet extends StatefulWidget {
  final BluetoothPrinterService service;
  const _BluetoothDeviceSheet({required this.service});

  @override
  State<_BluetoothDeviceSheet> createState() => _BluetoothDeviceSheetState();
}

class _BluetoothDeviceSheetState extends State<_BluetoothDeviceSheet> {
  bool _btOn = false;
  bool _btAvailable = true;
  bool _loading = true;
  bool _connecting = false;
  bool _permissionDenied = false;
  List<BluetoothDevice> _devices = [];
  String? _defaultMac;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });

    // Sur iOS, le Bluetooth n'est pas proposé : rien à charger.
    if (!widget.service.isSupported) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      // Android 12+ : demande explicite des permissions runtime Bluetooth
      // avant de lire l'état ou de lister les appareils appairés.
      await widget.service.ensureBluetoothPermissions();
      final available = await widget.service.isAvailable;
      final on = await widget.service.isOn;
      final defaultMac = await widget.service.getDefaultPrinterMac();
      final devices = await widget.service.getBondedDevices();
      final connected = await widget.service.isConnected;
      if (!mounted) return;
      setState(() {
        _btAvailable = available;
        _btOn = on;
        _defaultMac = defaultMac;
        _devices = devices;
        _connected = connected;
        _loading = false;
      });
    } on BluetoothPermissionDeniedException catch (e) {
      if (!mounted) return;
      setState(() {
        _permissionDenied = true;
        _btAvailable = false;
        _loading = false;
      });
      _showSnack(e.message, action: 'Réglages', onAction: () {
        widget.service.openAppSettingsPage();
        _load();
      });
    } on BluetoothUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _btAvailable = false;
        _btOn = false;
        _loading = false;
      });
      _showSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _btAvailable = false;
        _loading = false;
      });
    }
  }

  void _showSnack(String message, {String? action, VoidCallback? onAction}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: action != null
            ? SnackBarAction(
                label: action,
                textColor: Colors.white,
                onPressed: onAction ?? () {},
              )
            : null,
      ),
    );
  }

  Future<void> _select(BluetoothDevice device) async {
    setState(() => _connecting = true);
    try {
      // Connexion robuste : déconnexion préalable si un socket existe
      // déjà (évite l'erreur native « already connected »), retry
      // automatique après disconnect() sur socket résiduel, et court
      // délai + re-vérification de isConnected avant de conclure.
      final ok = await widget.service.connectSafely(device);
      if (ok) {
        await widget.service.saveDefaultPrinter(device);
        if (!mounted) return;
        Navigator.pop(context, device);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Connexion impossible. Vérifiez l'imprimante."),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on BluetoothPermissionDeniedException catch (e) {
      _showSnack(e.message, action: 'Réglages', onAction: () {
        widget.service.openAppSettingsPage();
        _load();
      });
    } on BluetoothUnavailableException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Erreur de connexion : $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.85,
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
              'Imprimante Bluetooth',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'ESC/POS · 58 mm / 80 mm',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!widget.service.isSupported) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 56, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              "L'impression Bluetooth n'est disponible que sur Android.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Permission Bluetooth refusée : état dédié avec accès aux réglages.
    if (_permissionDenied) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_searching,
                size: 56, color: Color(0xFFF59E0B)),
            const SizedBox(height: 12),
            const Text(
              "Permissions Bluetooth refusées",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              "Autorisez l'accès aux « Appareils à proximité » dans les réglages de l'application pour lister vos imprimantes appairées.",
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                await widget.service.openAppSettingsPage();
                _load();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Ouvrir les réglages'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // État Bluetooth
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(Constants.cardRadius),
          ),
          child: Row(
            children: [
              Icon(
                _btOn ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: _btOn ? const Color(0xFF2563EB) : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _btAvailable
                          ? (_btOn ? 'Bluetooth activé' : 'Bluetooth désactivé')
                          : 'Bluetooth indisponible',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _btOn
                          ? 'Sélectionnez votre imprimante ci-dessous'
                          : "Activez le Bluetooth puis appairez l'imprimante dans les réglages Android.",
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (!_btOn)
                TextButton(
                  onPressed: () async {
                    await widget.service.openBluetoothSettings();
                    _load();
                  },
                  child: const Text('Activer'),
                ),
            ],
          ),
        ),
        if (_connected) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Text(
                'Imprimante connectée',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await widget.service.disconnect();
                  _load();
                },
                child: const Text('Déconnecter'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Imprimantes appairées (${_devices.length})',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_devices.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(Constants.cardRadius),
            ),
            child: Column(
              children: [
                Icon(Icons.print_disabled, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  "Aucune imprimante appairée.\nAppairez-la depuis les réglages Bluetooth d'Android, puis revenez ici.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          )
        else
          ..._devices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: _defaultMac == device.address
                    ? const Color(0xFF2563EB).withValues(alpha: 0.08)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _connecting ? null : () => _select(device),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF2563EB).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.print,
                            color: Color(0xFF2563EB),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name ?? 'Imprimante',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                device.address ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_defaultMac == device.address)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Défaut',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        if (_connecting)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(Icons.chevron_right, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Astuce : touchez une imprimante pour vous y connecter et la définir comme imprimante par défaut.',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }
}
