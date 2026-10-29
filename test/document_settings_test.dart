// test/document_settings_test.dart
// Réglages du document : défauts sûrs (clé absente, JSON corrompu, ancien
// JSON), bornes, aller-retour JSON et intégration à la sauvegarde v2.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/document_settings.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/models/receipt_settings.dart';
import 'package:invoice_app/services/backup_service.dart';
import 'package:invoice_app/services/document_settings_service.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/product_image_store.dart';
import 'package:invoice_app/utils/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late DocumentSettingsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    InvoiceRepository().resetForTests();
    HistoryService.resetCacheForTests();
    DocumentSettingsService.settingsNotifier.value =
        DocumentSettings.defaults();

    temp = await Directory.systemTemp.createTemp('doc_settings_');
    addTearDown(() => temp.delete(recursive: true));

    service = DocumentSettingsService(
      documentsDirectory: () async => temp,
      receiptSettingsLoader: () async => const ReceiptSettings(
        shopName: 'Boutique Konté',
        shopAddress: 'Marché Sandaga',
        shopPhone: '77 123 45 67',
        shopNinea: 'NINEA 123456',
      ),
    );
  });

  group('Modèle', () {
    test('aller-retour JSON complet', () {
      const settings = DocumentSettings(
        businessName: 'Entreprise Ñandé',
        showStatusBadge: true,
        showQr: true,
        qrContentMode: DocumentQrContent.custom,
        qrCustomText: 'https://exemple.sn/f/1',
        watermarkOpacity: 0.12,
        template: DocumentTemplate.minimal,
        accentColor: 0xFF0D9488,
        imageFormat: DocumentImageFormat.long,
        imageQuality: DocumentImageQuality.high,
        jpgQuality: 92,
        logoPath: null,
      );
      final decoded =
          DocumentSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())));
      expect(decoded, settings);
      expect(decoded.toJson()['version'], DocumentSettings.currentVersion);
      // Un logo explicitement retiré le reste après lecture.
      expect(decoded.logoPath, isNull);
    });

    test('JSON ancien (champs manquants) : défauts sans crash', () {
      final decoded = DocumentSettings.fromJson(const <String, dynamic>{
        'businessName': 'Ancienne Boutique',
        'showQr': true,
      });
      expect(decoded.businessName, 'Ancienne Boutique');
      expect(decoded.showQr, isTrue);
      expect(decoded.template, DocumentTemplate.modern);
      expect(decoded.logoPath, DocumentSettings.defaultLogoAsset);
      expect(decoded.footerLine1, 'Merci pour votre confiance');
      expect(decoded.imageFormat, DocumentImageFormat.a4);
      expect(decoded.jpgQuality, 92);
      expect(decoded.imageQuality, DocumentImageQuality.high);
    });

    test('valeurs hors bornes ramenées dans le domaine', () {
      final decoded = DocumentSettings.fromJson(const <String, dynamic>{
        'watermarkOpacity': 2.0,
        'jpgQuality': 10,
      });
      expect(decoded.watermarkOpacity, 0.15);
      expect(decoded.jpgQuality, 70);

      final low = DocumentSettings.fromJson(const <String, dynamic>{
        'watermarkOpacity': 0.0,
        'jpgQuality': 300,
      });
      expect(low.watermarkOpacity, 0.03);
      expect(low.jpgQuality, 98);
    });

    test('trois niveaux de qualité, Haute et JPG 92 par défaut', () {
      expect(DocumentImageQuality.values.length, 3);
      expect(DocumentImageQuality.ultra.dpi, 300);
      expect(DocumentImageQuality.high.dpi, 200);
      const defaults = DocumentSettings();
      expect(defaults.imageQuality, DocumentImageQuality.high);
      expect(defaults.jpgQuality, 92);
      expect(DocumentSettings.currentVersion, 2);
    });

    test('migration v1 : les anciens défauts (standard / 85) passent à v2',
        () {
      final migrated = DocumentSettings.fromJson(const <String, dynamic>{
        'version': 1,
        'businessName': 'Ancienne Boutique',
        'imageQuality': 'standard',
        'jpgQuality': 85,
      });
      expect(migrated.imageQuality, DocumentImageQuality.high);
      expect(migrated.jpgQuality, 92);
      // Le reste des réglages est conservé.
      expect(migrated.businessName, 'Ancienne Boutique');
      // La relecture du JSON produit par la v2 ne migre plus.
      final reread =
          DocumentSettings.fromJson(jsonDecode(jsonEncode(migrated.toJson())));
      expect(reread, migrated);
    });

    test('migration v1 : une valeur choisie par l’utilisateur est conservée',
        () {
      final ultra = DocumentSettings.fromJson(const <String, dynamic>{
        'version': 1,
        'imageQuality': 'ultra',
        'jpgQuality': 85,
      });
      expect(ultra.imageQuality, DocumentImageQuality.ultra);
      expect(ultra.jpgQuality, 85);

      final jpg90 = DocumentSettings.fromJson(const <String, dynamic>{
        'version': 1,
        'imageQuality': 'standard',
        'jpgQuality': 90,
      });
      expect(jpg90.imageQuality, DocumentImageQuality.standard);
      expect(jpg90.jpgQuality, 90);

      // Déjà en v2 : plus aucune migration, même avec les anciens défauts.
      final v2 = DocumentSettings.fromJson(const <String, dynamic>{
        'version': 2,
        'imageQuality': 'standard',
        'jpgQuality': 85,
      });
      expect(v2.imageQuality, DocumentImageQuality.standard);
      expect(v2.jpgQuality, 85);
    });

    test('JSON corrompu ou absent : nouveaux défauts', () {
      expect(DocumentSettings.fromJson(const <String, dynamic>{}),
          DocumentSettings.defaults());
      final corrupted = DocumentSettings.fromJson(const <String, dynamic>{
        'version': 'deux',
        'imageQuality': 42,
        'jpgQuality': 'haute',
      });
      expect(corrupted.imageQuality, DocumentImageQuality.high);
      expect(corrupted.jpgQuality, 92);
    });

    test('mauvais types : défauts sans exception', () {
      final decoded = DocumentSettings.fromJson(const <String, dynamic>{
        'businessName': 42,
        'showLogo': 'oui',
        'template': 'inconnu',
        'imageFormat': 3,
      });
      expect(decoded.businessName, 'Facturier Konté Business Services');
      expect(decoded.showLogo, isTrue);
      expect(decoded.template, DocumentTemplate.modern);
      expect(decoded.imageFormat, DocumentImageFormat.a4);
    });

    test('huit pastilles d’accent, dont le bleu par défaut', () {
      expect(DocumentSettings.accentPalette.length, 8);
      expect(DocumentSettings.accentPalette.first, 0xFF2563EB);
      expect(const DocumentSettings().accentColor, 0xFF2563EB);
    });
  });

  group('Service', () {
    test('clé absente : défauts complétés par les infos du reçu', () async {
      final settings = await service.loadSettings();
      expect(settings.businessName, 'Boutique Konté');
      expect(settings.businessAddress, 'Marché Sandaga');
      expect(settings.businessPhone, '77 123 45 67');
      expect(settings.businessRegistration, 'NINEA 123456');

      // Le reçu thermique n'a pas été modifié.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(Constants.receiptSettingsKey), isNull);
      // Les réglages sont désormais persistés.
      expect(prefs.getString(Constants.documentSettingsKey), isNotNull);
      expect(
        DocumentSettingsService.settingsNotifier.value.businessName,
        'Boutique Konté',
      );
    });

    test('reçu vide : nom d’entreprise par défaut conservé', () async {
      final plain = DocumentSettingsService(
        documentsDirectory: () async => temp,
        receiptSettingsLoader: () async => ReceiptSettings.defaults(),
      );
      final settings = await plain.loadSettings();
      expect(settings.businessName, 'Facturier Konté Business Services');
    });

    test('JSON corrompu : valeurs par défaut sans crash', () async {
      SharedPreferences.setMockInitialValues({
        Constants.documentSettingsKey: '{ceci n’est pas du json',
      });
      final settings = await service.loadSettings();
      expect(settings, DocumentSettings.defaults());
    });

    test('JSON valide rechargé tel quel', () async {
      const initial = DocumentSettings(
        businessName: 'Konté Services',
        template: DocumentTemplate.classic,
        showPageNumbers: false,
      );
      SharedPreferences.setMockInitialValues({
        Constants.documentSettingsKey: jsonEncode(initial.toJson()),
      });
      expect(await service.loadSettings(), initial);
    });

    test('réinitialisation aux valeurs par défaut', () async {
      await service.saveSettings(
        const DocumentSettings(businessName: 'Autre', showQr: true),
      );
      final reset = await service.resetToDefaults();
      expect(reset, DocumentSettings.defaults());
      expect(DocumentSettingsService.settingsNotifier.value,
          DocumentSettings.defaults());
    });

    test('copie des infos du reçu sans toucher aux autres réglages', () async {
      await service.saveSettings(
        const DocumentSettings(businessName: 'Ancien nom', showQr: true),
      );
      final updated = await service.copyBusinessInfoFromReceipt();
      expect(updated.businessName, 'Boutique Konté');
      expect(updated.businessPhone, '77 123 45 67');
      expect(updated.showQr, isTrue);
    });

    test('logo importé dans documents/doc_assets', () async {
      final source = File('${temp.path}${Platform.pathSeparator}choisi.png');
      await source.writeAsBytes(<int>[1, 2, 3, 4]);

      final path = await service.importLogo(source.path);
      expect(path, contains('doc_assets'));
      final copied = File(path);
      expect(await copied.exists(), isTrue);
      expect(await copied.readAsBytes(), <int>[1, 2, 3, 4]);
      expect(path.endsWith('.png'), isTrue);
    });
  });

  group('Sauvegarde v2', () {
    Invoice invoice() => Invoice(
          id: '1700000000000',
          clientName: 'Client Test',
          createdAt: DateTime(2026, 10, 12),
          items: [InvoiceItem(name: 'Article', quantity: 2, unitPrice: 1500)],
        );

    test('export puis restauration des réglages du document', () async {
      final store = ProductImageStore(documentsDirectory: () async => temp);
      final backup = BackupService(
        imageStore: store,
        documentsDirectory: () async => temp,
      );

      await InvoiceRepository().replaceAll([invoice()]);
      const exported = DocumentSettings(
        businessName: 'Boutique Exportée',
        showQr: true,
        template: DocumentTemplate.minimal,
        accentColor: 0xFF15803D,
        imageQuality: DocumentImageQuality.ultra,
        jpgQuality: 96,
      );
      await service.saveSettings(exported);

      final json = await backup.createBackupJson();
      expect(json, contains('"documentSettings"'));
      expect(json, contains('Boutique Exportée'));

      // Réglages remplacés entre-temps puis restaurés depuis la sauvegarde.
      await service.resetToDefaults();
      final result = await backup.restoreFromJson(json);
      expect(result.invoiceCount, 1);

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(prefs.getString(Constants.documentSettingsKey)!)
          as Map<String, dynamic>;
      expect(stored['businessName'], 'Boutique Exportée');
      expect(stored['showQr'], isTrue);
      expect(stored['template'], 'minimal');
      expect(stored['imageQuality'], 'ultra');
      expect(stored['jpgQuality'], 96);
      // Le notifier est rafraîchi : l'aperçu repart des bonnes valeurs.
      expect(DocumentSettingsService.settingsNotifier.value.template,
          DocumentTemplate.minimal);
      expect(DocumentSettingsService.settingsNotifier.value.imageQuality,
          DocumentImageQuality.ultra);
      expect(DocumentSettingsService.settingsNotifier.value.jpgQuality, 96);
    });

    test('sauvegarde antérieure sans réglages du document : pas de crash',
        () async {
      final store = ProductImageStore(documentsDirectory: () async => temp);
      final backup = BackupService(
        imageStore: store,
        documentsDirectory: () async => temp,
      );
      const previous = DocumentSettings(businessName: 'Configuration locale');
      await service.saveSettings(previous);

      final legacy = jsonEncode(<String, dynamic>{
        'app': 'Gestion de Factures',
        'backupVersion': '2.0',
        'invoices': <dynamic>[],
      });
      await backup.restoreFromJson(legacy);

      // Sans champ documentSettings, la configuration locale reste en place.
      expect(await service.loadSettings(), previous);
    });
  });
}
