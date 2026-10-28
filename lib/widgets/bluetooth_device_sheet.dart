// lib/widgets/bluetooth_device_sheet.dart
// Feuille modale de gestion de l'imprimante Bluetooth :
// état du Bluetooth, appareils appairés, connexion et mémorisation
// de l'imprimante par défaut.

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';

import '../services/bluetooth_printer_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'ui/app_snack.dart';
import 'ui/sheet_handle.dart';

/// Ouvre la feuille de sélection de l'imprimante Bluetooth.
/// Retourne l'appareil sélectionné (et connecté), ou null si annulé.
Future<BluetoothDevice?> showBluetoothDeviceSheet(
  BuildContext context,
  BluetoothPrinterService service,
) {
  final colors = AppColors.of(context);
  return showModalBottomSheet<BluetoothDevice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.lg),
      ),
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
    AppSnack.error(
      context,
      message,
      actionLabel: action,
      onAction: onAction,
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
        _showSnack("Connexion impossible. Vérifiez l'imprimante.");
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
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            Text(
              'Imprimante Bluetooth',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'ESC/POS · 58 mm / 80 mm',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: colors.border),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    if (!widget.service.isSupported) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 56, color: colors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              "L'impression Bluetooth n'est disponible que sur Android.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    // Permission Bluetooth refusée : état dédié avec accès aux réglages.
    if (_permissionDenied) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_searching, size: 56, color: colors.warning),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Permissions Bluetooth refusées',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                color: colors.textStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Autorisez l'accès aux « Appareils à proximité » dans les "
              "réglages de l'application pour lister vos imprimantes "
              "appairées.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () async {
                await widget.service.openAppSettingsPage();
                _load();
              },
              icon: const Icon(Icons.settings, size: 18),
              label: const Text('Ouvrir les réglages'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // État Bluetooth
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                _btOn ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: _btOn ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _btAvailable
                          ? (_btOn ? 'Bluetooth activé' : 'Bluetooth désactivé')
                          : 'Bluetooth indisponible',
                      style: textTheme.titleSmall?.copyWith(
                        color: colors.textStrong,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _btOn
                          ? 'Sélectionnez votre imprimante ci-dessous'
                          : "Activez le Bluetooth puis appairez l'imprimante "
                              'dans les réglages Android.',
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
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
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.check_circle, color: colors.success, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Imprimante connectée',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.success,
                  ),
                ),
              ),
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
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Imprimantes appairées (${_devices.length})',
          style: textTheme.titleSmall?.copyWith(
            color: colors.textStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_devices.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              children: [
                Icon(Icons.print_disabled, size: 40, color: colors.textMuted),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "Aucune imprimante appairée.\nAppairez-la depuis les "
                  "réglages Bluetooth d'Android, puis revenez ici.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
              ],
            ),
          )
        else
          ..._devices.map(
            (device) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Material(
                color: _defaultMac == device.address
                    ? colors.primary.withValues(alpha: 0.08)
                    : colors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: _connecting ? null : () => _select(device),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            Icons.print,
                            color: colors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.name ?? 'Imprimante',
                                style: textTheme.titleSmall?.copyWith(
                                  color: colors.textStrong,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                device.address ?? '',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_defaultMac == device.address)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              'Défaut',
                              style: TextStyle(
                                color: colors.onPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        const SizedBox(width: AppSpacing.sm),
                        if (_connecting)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.chevron_right,
                            color: colors.textMuted,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Astuce : touchez une imprimante pour vous y connecter et la '
          'définir comme imprimante par défaut.',
          style: TextStyle(fontSize: 12, color: colors.textMuted),
        ),
      ],
    );
  }
}
