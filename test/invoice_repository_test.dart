// test/invoice_repository_test.dart
// Source de données unique : chargement, notifications, écritures
// sérialisées et sauvegarde du JSON corrompu.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/storage_service.dart';
import 'package:invoice_app/utils/constants.dart';

Invoice _invoice(
  String id, {
  String clientName = 'Client',
  InvoiceStatus status = InvoiceStatus.enCours,
  int unitPrice = 1000,
}) =>
    Invoice(
      id: id,
      clientName: clientName,
      createdAt: DateTime(2026, 8, 15, 10, 30),
      items: [InvoiceItem(name: 'Riz', quantity: 1, unitPrice: unitPrice)],
      status: status,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    InvoiceRepository().resetForTests();
  });

  test('charge une seule fois et notifie une fois', () async {
    final invoice = _invoice('1');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      Constants.invoicesKey,
      jsonEncode([invoice.toJson()]),
    );

    final repository = InvoiceRepository();
    var notifications = 0;
    void listener() => notifications++;
    repository.addListener(listener);

    await repository.load();
    await repository.load();

    expect(repository.isLoaded, isTrue);
    expect(repository.invoices.length, 1);
    expect(repository.invoices.first.clientName, 'Client');
    expect(notifications, 1);

    repository.removeListener(listener);
  });

  test('add, update, removeByIds et replaceAll persistent et notifient',
      () async {
    final repository = InvoiceRepository();
    final storage = StorageService();

    await repository.add(_invoice('1'));
    await repository.add(_invoice('2', unitPrice: 2000));
    expect(repository.invoices.length, 2);

    await repository.update(_invoice('1', status: InvoiceStatus.livree));
    expect(
      repository.invoices.firstWhere((i) => i.id == '1').status,
      InvoiceStatus.livree,
    );

    await repository.removeByIds(['2']);
    expect(repository.invoices.map((i) => i.id), ['1']);

    await repository.replaceAll([
      _invoice('3', clientName: 'Autre'),
      _invoice('4'),
    ]);
    expect(repository.invoices.length, 2);

    final stored = await storage.loadInvoices();
    expect(stored.map((i) => i.id).toSet(), {'3', '4'});

    // La mémoire est bien la liste non modifiable exposée.
    expect(() => repository.invoices.add(_invoice('5')), throwsUnsupportedError);
  });

  test('les écritures simultanées sont sérialisées dans l’ordre des appels',
      () async {
    final repository = InvoiceRepository();
    await Future.wait([
      repository.add(_invoice('a')),
      repository.add(_invoice('b')),
      repository.replaceAll([_invoice('c')]),
    ]);

    final stored = await StorageService().loadInvoices();
    expect(stored.length, 1);
    expect(stored.single.id, 'c');
  });

  test('un JSON corrompu n’écrase pas les données brutes', () async {
    const raw = '{ceci n’est pas du json';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.invoicesKey, raw);

    final repository = InvoiceRepository();
    await repository.load();

    expect(repository.hasLoadError, isTrue);
    expect(repository.loadError, isNotNull);
    expect(repository.invoices, isEmpty);
    expect(prefs.getString(InvoiceRepository.corruptBackupKey), raw);

    // Une écriture ultérieure conserve la sauvegarde du JSON corrompu.
    await repository.add(_invoice('1'));
    expect(prefs.getString(InvoiceRepository.corruptBackupKey), raw);
    expect(repository.hasLoadError, isFalse);
    final stored = await StorageService().loadInvoices();
    expect(stored.single.id, '1');
  });
}
