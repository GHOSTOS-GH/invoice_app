// test/client_price_index_test.dart
// Index des dernières ventes : normalisation, exclusion de la facture en
// cours et fusion avec l'historique des clients.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/services/client_price_index.dart';
import 'package:invoice_app/services/history_service.dart';
import 'package:invoice_app/services/invoice_repository.dart';
import 'package:invoice_app/services/storage_service.dart';

Invoice _invoice({
  required String id,
  required String client,
  required String product,
  required int price,
  required DateTime date,
}) =>
    Invoice(
      id: id,
      clientName: client,
      createdAt: date,
      items: [InvoiceItem(name: product, quantity: 1, unitPrice: price)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InvoiceRepository().resetForTests();
    HistoryService.resetCacheForTests();
  });

  test('lastSale retrouve la vente la plus récente malgré les accents', () async {
    final index = ClientPriceIndex();
    await InvoiceRepository().replaceAll([
      _invoice(
        id: 'old',
        client: 'Aïssatou  Diop',
        product: 'Riz parfumé',
        price: 1000,
        date: DateTime(2026, 8, 1),
      ),
      _invoice(
        id: 'new',
        client: 'AISSATOU DIOP',
        product: 'RIZ PARFUME',
        price: 1200,
        date: DateTime(2026, 8, 10),
      ),
    ]);

    final sale = index.lastSale('aissatou diop', 'riz parfume');
    expect(sale, isNotNull);
    expect(sale!.price, 1200);
    expect(sale.invoiceId, 'new');
  });

  test('excludeInvoiceId ignore la facture en cours d’édition', () async {
    final index = ClientPriceIndex();
    await InvoiceRepository().replaceAll([
      _invoice(
        id: 'old',
        client: 'Client A',
        product: 'Article',
        price: 1000,
        date: DateTime(2026, 8, 1),
      ),
      _invoice(
        id: 'current',
        client: 'Client A',
        product: 'Article',
        price: 1200,
        date: DateTime(2026, 8, 10),
      ),
    ]);

    expect(index.lastSale('client a', 'article')!.price, 1200);
    expect(
      index.lastSale('client a', 'article', excludeInvoiceId: 'current')!.price,
      1000,
    );
    // Si la seule vente est exclue, il n'y a plus d'historique.
    expect(
      index.lastSale('client a', 'article', excludeInvoiceId: 'old')!.price,
      1200,
    );
  });

  test('clientNames dédoublonne et fusionne avec l’historique', () async {
    final history = HistoryService();
    await history.saveClientName('Fatou');
    final index = ClientPriceIndex();

    await InvoiceRepository().replaceAll([
      _invoice(
        id: '1',
        client: 'Aïssatou  Diop',
        product: 'A',
        price: 100,
        date: DateTime(2026, 8, 1),
      ),
      _invoice(
        id: '2',
        client: 'AISSATOU DIOP',
        product: 'B',
        price: 200,
        date: DateTime(2026, 8, 5),
      ),
    ]);

    final names = index.clientNames();
    expect(names.where((n) => n.toLowerCase().contains('aissatou')).length, 1);
    expect(names, contains('Fatou'));
    expect(names.first, 'AISSATOU DIOP');
  });

  test('StorageService.getClientPriceMap délègue à l’index', () async {
    ClientPriceIndex();
    await InvoiceRepository().replaceAll([
      _invoice(
        id: '1',
        client: 'Élodie',
        product: 'Huile rouge',
        price: 2500,
        date: DateTime(2026, 8, 1),
      ),
    ]);

    final prices = await StorageService().getClientPriceMap('elodie');
    expect(prices['huile rouge'], 2500);
    expect(await StorageService().getLastPriceForClientProduct(
      'Élodie',
      'Huile rouge',
    ), 2500);
  });
}
