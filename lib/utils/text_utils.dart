// lib/utils/text_utils.dart
// Normalisation des textes utilisés comme clés (clients, produits).

/// Table explicite des lettres latines accentuées (minuscules et
/// majuscules) vers leur équivalent ASCII.
const Map<String, String> _latinAccentMap = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss',
  'À': 'a', 'Á': 'a', 'Â': 'a', 'Ä': 'a', 'Ã': 'a', 'Å': 'a',
  'Ç': 'c',
  'È': 'e', 'É': 'e', 'Ê': 'e', 'Ë': 'e',
  'Ì': 'i', 'Í': 'i', 'Î': 'i', 'Ï': 'i',
  'Ñ': 'n',
  'Ò': 'o', 'Ó': 'o', 'Ô': 'o', 'Ö': 'o', 'Õ': 'o', 'Ø': 'o',
  'Ù': 'u', 'Ú': 'u', 'Û': 'u', 'Ü': 'u',
  'Ý': 'y', 'Ÿ': 'y',
  'Æ': 'ae', 'Œ': 'oe',
};

/// Clé de comparaison d'un nom : trim, minuscules, accents retirés et
/// espaces multiples réduits à un seul.
///
/// Exemple : « Aïssatou  Diop » → « aissatou diop ».
String normalizeKey(String value) {
  final buffer = StringBuffer();
  for (final rune in value.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_latinAccentMap[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
