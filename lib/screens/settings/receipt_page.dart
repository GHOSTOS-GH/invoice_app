// lib/screens/settings/receipt_page.dart
// Sous-page « Reçu thermique » : réutilise ReceiptSettingsTab tel quel.

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/receipt_settings_tab.dart';

class ReceiptSettingsPage extends StatelessWidget {
  const ReceiptSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).canvas,
      appBar: AppBar(title: const Text('Reçu thermique')),
      body: const ReceiptSettingsTab(),
    );
  }
}
