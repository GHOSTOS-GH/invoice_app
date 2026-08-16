// lib/models/receipt_settings.dart
// Paramètres du reçu thermique (ESC/POS) : informations boutique,
// logo, format papier (58/80 mm) et éléments affichés / masqués.

enum ReceiptPaperFormat {
  mm58('58 mm', 32),
  mm80('80 mm', 48);

  const ReceiptPaperFormat(this.label, this.charsPerLine);

  /// Libellé affiché dans l'interface.
  final String label;

  /// Nombre de caractères imprimables par ligne (police standard).
  final int charsPerLine;

  static ReceiptPaperFormat fromName(String? name) =>
      ReceiptPaperFormat.values.firstWhere(
        (e) => e.name == name,
        orElse: () => ReceiptPaperFormat.mm58,
      );
}

class ReceiptSettings {
  // ---------- Informations boutique ----------
  final String shopName;
  final String shopAddress;
  final String shopPhone;
  final String shopNinea; // NINEA / RC
  final String footerMessage;
  final String cashierName;

  /// Chemin local du fichier image du logo (null si aucun logo).
  final String? logoPath;

  /// Format du papier (58 mm → 32 caractères, 80 mm → 48 caractères).
  final ReceiptPaperFormat format;

  // ---------- Éléments affichés / masqués ----------
  final bool showLogo;
  final bool showShopName;
  final bool showAddress;
  final bool showPhone;
  final bool showNinea;
  final bool showFooter;
  final bool showBarcode;

  const ReceiptSettings({
    this.shopName = '',
    this.shopAddress = '',
    this.shopPhone = '',
    this.shopNinea = '',
    this.footerMessage = 'Merci de votre visite !',
    this.cashierName = 'Admin',
    this.logoPath,
    this.format = ReceiptPaperFormat.mm58,
    this.showLogo = true,
    this.showShopName = true,
    this.showAddress = true,
    this.showPhone = true,
    this.showNinea = true,
    this.showFooter = true,
    this.showBarcode = true,
  });

  factory ReceiptSettings.defaults() => const ReceiptSettings();

  ReceiptSettings copyWith({
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    String? shopNinea,
    String? footerMessage,
    String? cashierName,
    String? logoPath,
    bool clearLogo = false,
    ReceiptPaperFormat? format,
    bool? showLogo,
    bool? showShopName,
    bool? showAddress,
    bool? showPhone,
    bool? showNinea,
    bool? showFooter,
    bool? showBarcode,
  }) =>
      ReceiptSettings(
        shopName: shopName ?? this.shopName,
        shopAddress: shopAddress ?? this.shopAddress,
        shopPhone: shopPhone ?? this.shopPhone,
        shopNinea: shopNinea ?? this.shopNinea,
        footerMessage: footerMessage ?? this.footerMessage,
        cashierName: cashierName ?? this.cashierName,
        logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
        format: format ?? this.format,
        showLogo: showLogo ?? this.showLogo,
        showShopName: showShopName ?? this.showShopName,
        showAddress: showAddress ?? this.showAddress,
        showPhone: showPhone ?? this.showPhone,
        showNinea: showNinea ?? this.showNinea,
        showFooter: showFooter ?? this.showFooter,
        showBarcode: showBarcode ?? this.showBarcode,
      );

  Map<String, dynamic> toJson() => {
        'shopName': shopName,
        'shopAddress': shopAddress,
        'shopPhone': shopPhone,
        'shopNinea': shopNinea,
        'footerMessage': footerMessage,
        'cashierName': cashierName,
        'logoPath': logoPath,
        'format': format.name,
        'showLogo': showLogo,
        'showShopName': showShopName,
        'showAddress': showAddress,
        'showPhone': showPhone,
        'showNinea': showNinea,
        'showFooter': showFooter,
        'showBarcode': showBarcode,
      };

  factory ReceiptSettings.fromJson(Map<String, dynamic> json) =>
      ReceiptSettings(
        shopName: json['shopName'] as String? ?? '',
        shopAddress: json['shopAddress'] as String? ?? '',
        shopPhone: json['shopPhone'] as String? ?? '',
        shopNinea: json['shopNinea'] as String? ?? '',
        footerMessage: json['footerMessage'] as String? ?? 'Merci de votre visite !',
        cashierName: json['cashierName'] as String? ?? 'Admin',
        logoPath: json['logoPath'] as String?,
        format: ReceiptPaperFormat.fromName(json['format'] as String?),
        showLogo: json['showLogo'] as bool? ?? true,
        showShopName: json['showShopName'] as bool? ?? true,
        showAddress: json['showAddress'] as bool? ?? true,
        showPhone: json['showPhone'] as bool? ?? true,
        showNinea: json['showNinea'] as bool? ?? true,
        showFooter: json['showFooter'] as bool? ?? true,
        showBarcode: json['showBarcode'] as bool? ?? true,
      );
}
