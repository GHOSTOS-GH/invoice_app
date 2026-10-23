// test/pdf_service_test.dart
// Génération des PDF de facture : le bloc total doit fonctionner avec
// et sans remise / TVA, sans jamais lever d'exception.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('fr_FR', null);
  });

  Invoice sampleInvoice({int discount = 0, double taxRate = 0}) => Invoice(
        id: '20260815123456',
        clientName: 'Client Test',
        createdAt: DateTime(2026, 8, 15, 14, 30),
        items: [
          InvoiceItem(name: 'Coca-Cola 1.5L', quantity: 2, unitPrice: 1000),
          InvoiceItem(name: 'Riz 5 kg', quantity: 1, unitPrice: 2500),
        ],
        discount: discount,
        taxRate: taxRate,
        notes: 'Merci de votre confiance',
      );

  test('génère un PDF avec remise et TVA sans exception', () async {
    final bytes =
        await PdfService().generatePdf(sampleInvoice(discount: 500, taxRate: 18));

    expect(bytes.length, greaterThan(1000), reason: 'PDF non vide attendu');
    // Signature d'un fichier PDF (%PDF-)
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('génère un PDF sans remise ni TVA sans exception', () async {
    final bytes = await PdfService().generatePdf(sampleInvoice());
    expect(bytes.length, greaterThan(1000));
  });
}
