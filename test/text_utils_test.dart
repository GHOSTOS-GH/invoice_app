// test/text_utils_test.dart
// Normalisation des clés clients / produits.

import 'package:flutter_test/flutter_test.dart';
import 'package:invoice_app/utils/text_utils.dart';

void main() {
  group('normalizeKey', () {
    test('retire les accents, la casse et les espaces superflus', () {
      expect(normalizeKey('Aïssatou  Diop'), 'aissatou diop');
      expect(normalizeKey('  Aïssatou  Diop  '), 'aissatou diop');
      expect(normalizeKey('AISSATOU DIOP'), 'aissatou diop');
    });

    test('gère les accents majuscules et les ligatures', () {
      expect(normalizeKey('ÉLÈVE ÇA'), 'eleve ca');
      expect(normalizeKey('Œuf Æther'), 'oeuf aether');
      expect(normalizeKey('François  N’Guessan'), 'francois n’guessan');
    });

    test('réduit tabulations et retours ligne en un espace', () {
      expect(normalizeKey('Riz\t\nparfumé'), 'riz parfume');
    });

    test('chaîne vide ou espaces uniquement → vide', () {
      expect(normalizeKey(''), '');
      expect(normalizeKey('   '), '');
    });
  });
}
