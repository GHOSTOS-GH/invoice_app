// lib/utils/formatters.dart

String formatCurrency(double value) {
  final intValue = value.toInt();
  final formatted = intValue.toString();
  final buffer = StringBuffer();
  int count = 0;
  for (int i = formatted.length - 1; i >= 0; i--) {
    if (count == 3) {
      buffer.write(' ');
      count = 0;
    }
    buffer.write(formatted[i]);
    count++;
  }
  final reversed = buffer.toString().split('').reversed.join();
  return '$reversed FCFA';
}

String formatNumber(double value) {
  final intValue = value.toInt();
  final formatted = intValue.toString();
  final buffer = StringBuffer();
  int count = 0;
  for (int i = formatted.length - 1; i >= 0; i--) {
    if (count == 3) {
      buffer.write(' ');
      count = 0;
    }
    buffer.write(formatted[i]);
    count++;
  }
  final reversed = buffer.toString().split('').reversed.join();
  return reversed;
}