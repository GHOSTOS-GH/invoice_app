// lib/widgets/receipt_preview.dart
// Aperçu visuel du reçu thermique : fond blanc, texte noir en police
// monospace, rendu identique à l'impression (même plan de lignes que
// l'encodage ESC/POS).

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/receipt_settings.dart';
import '../services/receipt_builder.dart';

class ReceiptPreviewView extends StatelessWidget {
  final ReceiptContent content;

  const ReceiptPreviewView({super.key, required this.content});

  static const String _monoFamily = 'monospace';
  static const List<String> _monoFallback = [
    'Courier New',
    'Roboto Mono',
    'Menlo',
    'Consolas',
    'Courier',
  ];

  @override
  Widget build(BuildContext context) {
    final settings = content.settings;
    final width = settings.format == ReceiptPaperFormat.mm58 ? 240.0 : 340.0;
    final baseFontSize =
        (width / (settings.format.charsPerLine * 0.62)).clamp(9.0, 16.0);

    return Container(
      width: width,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (content.logoPngBytes != null) ...[
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width * 0.75, maxHeight: 90),
                child: Image.memory(content.logoPngBytes!),
              ),
            ),
            const SizedBox(height: 8),
          ],
          ...content.plan.map((item) => _buildItem(item, baseFontSize)),
          if (content.qrData != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(6),
                child: QrImageView(
                  data: content.qrData!,
                  version: QrVersions.auto,
                  size: width * 0.45,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItem(Object item, double baseFontSize) {
    if (item is ReceiptTableRow) {
      return _buildTableRow(item, baseFontSize);
    }
    final line = item as ReceiptLine;
    final style = TextStyle(
      fontFamily: _monoFamily,
      fontFamilyFallback: _monoFallback,
      fontSize: line.fontSize == 2 ? baseFontSize * 1.9 : baseFontSize,
      fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
      decoration: line.underline ? TextDecoration.underline : null,
      color: Colors.black,
      height: 1.25,
    );

    final text = Text(
      line.text,
      style: style,
      textAlign: _textAlign(line.align),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );

    if (line.reverse) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: text,
      );
    }
    return text;
  }

  Widget _buildTableRow(ReceiptTableRow row, double baseFontSize) {
    final style = TextStyle(
      fontFamily: _monoFamily,
      fontFamilyFallback: _monoFallback,
      fontSize: baseFontSize,
      fontWeight: row.bold ? FontWeight.w700 : FontWeight.w400,
      color: Colors.black,
      height: 1.25,
    );
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: Text(row.name, style: style, maxLines: 1, softWrap: false),
        ),
        Expanded(
          flex: 2,
          child: Text(row.qty,
              style: style, textAlign: TextAlign.center, maxLines: 1),
        ),
        Expanded(
          flex: 4,
          child: Text(row.price,
              style: style, textAlign: TextAlign.right, maxLines: 1),
        ),
      ],
    );
  }

  TextAlign _textAlign(ReceiptAlign align) {
    switch (align) {
      case ReceiptAlign.left:
        return TextAlign.left;
      case ReceiptAlign.center:
        return TextAlign.center;
      case ReceiptAlign.right:
        return TextAlign.right;
    }
  }
}
