// test/receipt_settings_service_test.dart
// Tests de persistance des paramètres du reçu (SharedPreferences)
// et du helper partagé de préparation des octets ESC/POS.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/receipt_settings.dart';
import 'package:invoice_app/services/receipt_printer_common.dart';
import 'package:invoice_app/services/receipt_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReceiptSettingsService', () {
    test('sauvegarde puis recharge les paramètres du reçu', () async {
      final service = ReceiptSettingsService();
      await service.saveSettings(const ReceiptSettings(
        shopName: 'Boutique Test',
        format: ReceiptPaperFormat.mm80,
        showBarcode: false,
        cashierName: 'Awa',
      ));

      final loaded = await service.loadSettings();
      expect(loaded.shopName, 'Boutique Test');
      expect(loaded.format, ReceiptPaperFormat.mm80);
      expect(loaded.showBarcode, isFalse);
      expect(loaded.cashierName, 'Awa');
    });

    test('valeur par défaut quand rien n\'est enregistré', () async {
      final settings = await ReceiptSettingsService().loadSettings();
      expect(settings.shopName, '');
      expect(settings.format, ReceiptPaperFormat.mm58);
      expect(settings.showBarcode, isTrue);
    });

    test('IP imprimante Wi-Fi : enregistrement, lecture, effacement',
        () async {
      final service = ReceiptSettingsService();
      expect(await service.getDefaultPrinterIp(), isNull);

      await service.saveDefaultPrinterIp('192.168.1.50');
      expect(await service.getDefaultPrinterIp(), '192.168.1.50');

      await service.saveDefaultPrinterIp(null);
      expect(await service.getDefaultPrinterIp(), isNull);
    });

    test('le notifier est mis à jour après sauvegarde (aperçu temps réel)',
        () async {
      final service = ReceiptSettingsService();
      var notified = false;
      ReceiptSettingsService.settingsNotifier
          .addListener(() => notified = true);

      await service.saveSettings(
          const ReceiptSettings(shopName: 'Ma Boutique'));
      expect(notified, isTrue);
      expect(ReceiptSettingsService.settingsNotifier.value.shopName,
          'Ma Boutique');
    });
  });

  group('prepareReceiptBytes', () {
    test('génère le contenu et les octets d\'une facture', () async {
      final invoice = Invoice(
        id: '20260815123456',
        clientName: 'Client Test',
        createdAt: DateTime(2026, 8, 15, 14, 30),
        items: const [
          InvoiceItem(name: 'Article A', quantity: 1, unitPrice: 1000),
        ],
      );

      final (content, bytes) =
          await prepareReceiptBytes(invoice, settings: const ReceiptSettings());
      expect(content.invoice, invoice);
      expect(bytes.length, greaterThan(50));
      expect(content.plan, isNotEmpty);
    });
  });
}
