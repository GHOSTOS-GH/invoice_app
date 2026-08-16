// lib/utils/constants.dart
// Constantes globales de l'application

class Constants {
  // Clés SharedPreferences
  static const String invoicesKey = 'invoices';
  static const String draftInvoiceKey = 'draft_invoice';
  static const String lastLoginDateKey = 'last_login_date';

  // Clés du module reçu thermique (ESC/POS)
  static const String receiptSettingsKey = 'receipt_settings';
  static const String defaultPrinterMacKey = 'default_printer_mac';
  static const String defaultPrinterIpKey = 'default_printer_ip';

  // Identifiants admin
  static const String adminUsername = 'Admin';
  static const String adminPassword = '0000';

  // Tailles pour l'harmonisation de l'UI
  static const double cardRadius = 16.0;
  static const double buttonRadius = 14.0;
  static const double inputRadius = 14.0;
}