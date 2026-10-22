// test/invoice_money_test.dart
// Montants FCFA : calculs entiers du modèle, formats d'affichage et
// rétro-compatibilité avec les anciens JSON décimaux.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_app/models/invoice.dart';
import 'package:invoice_app/utils/formatters.dart';

void main() {
  Invoice invoiceWith({
    int unitPrice = 10000,
    int quantity = 1,
    int discount = 0,
    double taxRate = 0,
  }) =>
      Invoice(
        id: '20260815123456',
        clientName: 'Client Test',
        createdAt: DateTime(2026, 8, 15, 10, 30),
        items: [
          InvoiceItem(name: 'Article', quantity: quantity, unitPrice: unitPrice),
        ],
        discount: discount,
        taxRate: taxRate,
      );

  group('Invoice : calculs en entiers FCFA', () {
    test('TVA arrondie sur le net de remise (10 000 − 500 à 18 %)', () {
      final inv = invoiceWith(discount: 500, taxRate: 18);

      expect(inv.total, 10000);
      expect(inv.subtotal, 10000); // alias de total
      expect(inv.discountApplied, 500);
      expect(inv.taxAmount, 1710);
      expect(inv.payableTotal, 11210);
      expect(inv.hasBreakdown, isTrue);
    });

    test('remise supérieure au sous-total plafonnée, jamais négative', () {
      final inv = invoiceWith(discount: 15000, taxRate: 18);

      expect(inv.discountApplied, 10000,
          reason: 'la remise appliquée ne dépasse jamais le sous-total');
      expect(inv.taxAmount, 0);
      expect(inv.payableTotal, 0);
    });

    test('remise négative ignorée', () {
      final inv = invoiceWith(discount: -500);
      expect(inv.discountApplied, 0);
      expect(inv.payableTotal, 10000);
    });

    test('TVA arrondie au FCFA le plus proche (.round())', () {
      // 3 × 111 = 333 ; 333 × 18 % = 59,94 → 60.
      final inv = invoiceWith(unitPrice: 111, quantity: 3, taxRate: 18);
      expect(inv.total, 333);
      expect(inv.taxAmount, 60);
      expect(inv.payableTotal, 393);
    });

    test('sans remise ni TVA, payableTotal = sous-total', () {
      final inv = invoiceWith(quantity: 3);
      expect(inv.hasBreakdown, isFalse);
      expect(inv.payableTotal, 30000);
    });

    test('toJson écrit des entiers pour les montants', () {
      final inv = invoiceWith(discount: 500, taxRate: 18);
      final json = inv.toJson();

      expect(json['discount'], isA<int>());
      expect(json['taxRate'], isA<double>());
      final item = (json['items'] as List).first as Map<String, dynamic>;
      expect(item['unitPrice'], isA<int>());
      expect(item['quantity'], isA<int>());

      final encoded = jsonEncode(json);
      expect(encoded, contains('"unitPrice":10000'));
      expect(encoded, contains('"discount":500'));
    });

    test('copyWith conserve les montants entiers', () {
      final inv = invoiceWith(discount: 500);
      final copy = inv.copyWith(items: inv.items.toList());
      expect(copy.discount, 500);
      expect(copy.payableTotal, inv.payableTotal);
    });
  });

  group('Rétro-compatibilité : ancien JSON avec décimales', () {
    test('prix 99.99 et remise 10.5 relus sans erreur et arrondis', () {
      // Format historique (avant le passage aux entiers FCFA).
      const oldJson = '''
      {
        "id": "1700000000000",
        "clientName": "Ancien Client",
        "createdAt": "2026-01-02T10:30:00.000",
        "items": [
          {"name": "Riz", "quantity": 2, "unitPrice": 99.99},
          {"name": "Huile", "quantity": 1, "unitPrice": 1500.4}
        ],
        "status": "livree",
        "notes": null,
        "discount": 10.5,
        "taxRate": 18.0
      }
      ''';

      final inv = Invoice.fromJson(jsonDecode(oldJson) as Map<String, dynamic>);

      expect(inv.items.first.unitPrice, 100, reason: '99.99 → 100');
      expect(inv.items.last.unitPrice, 1500, reason: '1500.4 → 1500');
      expect(inv.items.first.subtotal, 200);
      expect(inv.total, 1700);
      expect(inv.discount, 11, reason: '10.5 → 11');
      expect(inv.taxRate, 18.0);
      expect(inv.taxAmount, 304); // (1700 − 11) × 18 % = 304,02 → 304
      expect(inv.payableTotal, 1993); // 1700 − 11 + 304
      expect(inv.clientName, 'Ancien Client');
    });

    test('JSON ancien sans remise ni TVA reste lisible', () {
      const oldJson = '''
      {
        "id": "1700000000001",
        "clientName": "Client",
        "createdAt": "2026-01-02T10:30:00.000",
        "items": [{"name": "Article", "quantity": 1, "unitPrice": 2500.0}],
        "status": "enCours"
      }
      ''';

      final inv = Invoice.fromJson(jsonDecode(oldJson) as Map<String, dynamic>);
      expect(inv.items.first.unitPrice, 2500);
      expect(inv.discount, 0);
      expect(inv.taxRate, 0);
      expect(inv.payableTotal, 2500);
    });
  });

  group('formatNumber / formatCurrency', () {
    test('formatNumber sépare les milliers (insécable par défaut)', () {
      expect(formatNumber(0), '0');
      expect(formatNumber(999), '999');
      expect(formatNumber(1000), '1\u00A0000');
      expect(formatNumber(1234567), '1\u00A0234\u00A0567');
    });

    test('formatNumber gère le signe sur la valeur absolue', () {
      expect(formatNumber(-123), '-123');
      expect(formatNumber(-1234567), '-1\u00A0234\u00A0567');
    });

    test('formatNumber accepte un séparateur explicite (espace normal)', () {
      expect(formatNumber(1234567, sep: ' '), '1 234 567');
      expect(formatNumber(-1000, sep: ' '), '-1 000');
    });

    test('formatCurrency ajoute FCFA après le montant', () {
      expect(formatCurrency(0), '0 FCFA');
      expect(formatCurrency(1234567), '1\u00A0234\u00A0567 FCFA');
      expect(formatCurrency(1234567, sep: ' '), '1 234 567 FCFA');
      expect(formatCurrency(-123), '-123 FCFA');
    });
  });
}
