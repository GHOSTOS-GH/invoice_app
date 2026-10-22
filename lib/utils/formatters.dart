// lib/utils/formatters.dart
// Formatage des montants FCFA : toujours des entiers, jamais de décimal.

/// Espace insécable utilisé par défaut comme séparateur de milliers
/// (affichage écran). L'imprimante thermique doit passer `sep: ' '`.
const String _defaultThousandsSeparator = '\u{00A0}';

/// Formate [v] en groupes de 3 chiffres séparés par [sep].
///
/// Le signe est géré sur la valeur absolue : -123 → « -123 »,
/// -1234567 → « -1 234 567 ». Les montants restent des entiers.
String formatNumber(int v, {String sep = _defaultThousandsSeparator}) {
  final digits = v.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(sep);
    buffer.write(digits[i]);
  }
  return v < 0 ? '-$buffer' : buffer.toString();
}

/// Formate [v] en FCFA : « 1 250 000 FCFA » (séparateur insécable).
String formatCurrency(int v, {String sep = _defaultThousandsSeparator}) =>
    '${formatNumber(v, sep: sep)} FCFA';
