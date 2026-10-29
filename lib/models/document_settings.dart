// lib/models/document_settings.dart
// Réglages du document de facture (PDF et images) : informations de
// l'entreprise, éléments affichés, style, paiement / QR, pied de page et
// réglages des images. Persistés sous la clé `document_settings`.

import 'package:flutter/foundation.dart';

/// Modèle visuel du document. Les trois valeurs sont des variantes d'un même
/// layout (style d'en-tête, de tableau et de totaux), jamais trois moteurs.
enum DocumentTemplate {
  classic('Classique', 'Bandeau d’accent et tableau souligné'),
  modern('Moderne', 'Encarts arrondis et lignes alternées'),
  minimal('Minimal', 'Filets fins, sans aplat de couleur');

  const DocumentTemplate(this.label, this.description);

  final String label;
  final String description;

  static DocumentTemplate fromName(String? name) =>
      DocumentTemplate.values.firstWhere(
        (value) => value.name == name,
        orElse: () => DocumentTemplate.modern,
      );
}

/// Format de sortie des images de facture.
enum DocumentImageFormat {
  a4('A4', 'Toutes les pages au format A4'),
  long('Long', 'Une seule image continue, marges rognées');

  const DocumentImageFormat(this.label, this.description);

  final String label;
  final String description;

  static DocumentImageFormat fromName(String? name) =>
      DocumentImageFormat.values.firstWhere(
        (value) => value.name == name,
        orElse: () => DocumentImageFormat.a4,
      );
}

/// Qualité (résolution) des images générées.
enum DocumentImageQuality {
  standard('Standard', 150),
  high('Haute', 200),
  ultra('Ultra', 300);

  const DocumentImageQuality(this.label, this.dpi);

  final String label;

  /// Résolution de rastérisation du PDF, en points par pouce.
  final int dpi;

  static DocumentImageQuality fromName(String? name) =>
      DocumentImageQuality.values.firstWhere(
        (value) => value.name == name,
        orElse: () => DocumentImageQuality.high,
      );
}

/// Contenu du QR code imprimé sur la facture.
enum DocumentQrContent {
  reference('Référence de la facture'),
  custom('Texte personnalisé');

  const DocumentQrContent(this.label);

  final String label;

  static DocumentQrContent fromName(String? name) =>
      DocumentQrContent.values.firstWhere(
        (value) => value.name == name,
        orElse: () => DocumentQrContent.reference,
      );
}

/// Réglages complets du document de facture.
///
/// Tous les champs ont une valeur par défaut sûre : un JSON absent, corrompu
/// ou issu d'une version antérieure (champs manquants) donne un document
/// valide, sans jamais lever d'exception.
@immutable
class DocumentSettings {
  /// Version du schéma JSON enregistré (v2 : qualités d'image relevées).
  static const int currentVersion = 2;

  /// Logo utilisé tant que l'utilisateur n'en a pas choisi un autre.
  static const String defaultLogoAsset = 'assets/watermark/logo.png';

  /// Pastilles de couleur d'accent proposées dans les paramètres.
  static const List<int> accentPalette = <int>[
    0xFF2563EB, // bleu (défaut)
    0xFF4F46E5, // indigo
    0xFF0D9488, // sarcelle
    0xFF15803D, // vert
    0xFFB45309, // ambre
    0xFFEA580C, // orange
    0xFFBE123C, // rose
    0xFF475569, // ardoise
  ];

  // ---------- Entreprise ----------
  final String businessName;
  final String businessAddress;
  final String businessPhone;
  final String businessEmail;
  final String businessRegistration; // NINEA / RC

  // ---------- Logo ----------
  /// Asset (`assets/...`) ou chemin de fichier local, null = aucun logo.
  final String? logoPath;

  // ---------- Éléments affichés ----------
  final bool showLogo;
  final bool showWatermark;

  /// Opacité du filigrane (0.03 à 0.15).
  final double watermarkOpacity;

  final bool showBusinessInfo;
  final bool showInvoiceNumber;
  final bool showDateTime;
  final bool showStatusBadge;
  final bool showItemIndex;
  final bool showUnitPrice;
  final bool showTotalsSummary;
  final bool showNotes;

  // ---------- Paiement ----------
  final bool showPaymentInfo;
  final String paymentInfoText;

  // ---------- QR ----------
  final bool showQr;
  final DocumentQrContent qrContentMode;
  final String qrCustomText;

  // ---------- Pied de page ----------
  final bool showFooter;
  final String footerLine1;
  final String footerLine2;
  final bool showPageNumbers;

  // ---------- Style ----------
  final DocumentTemplate template;

  /// Couleur d'accent ARGB (une des [accentPalette]).
  final int accentColor;

  // ---------- Images ----------
  final DocumentImageFormat imageFormat;
  final DocumentImageQuality imageQuality;

  /// Qualité JPEG (70 à 98).
  final int jpgQuality;

  const DocumentSettings({
    this.businessName = 'Facturier Konté Business Services',
    this.businessAddress = '',
    this.businessPhone = '',
    this.businessEmail = '',
    this.businessRegistration = '',
    this.logoPath = defaultLogoAsset,
    this.showLogo = true,
    this.showWatermark = true,
    this.watermarkOpacity = 0.08,
    this.showBusinessInfo = true,
    this.showInvoiceNumber = true,
    this.showDateTime = true,
    this.showStatusBadge = false,
    this.showItemIndex = true,
    this.showUnitPrice = true,
    this.showTotalsSummary = true,
    this.showNotes = true,
    this.showPaymentInfo = false,
    this.paymentInfoText = '',
    this.showQr = false,
    this.qrContentMode = DocumentQrContent.reference,
    this.qrCustomText = '',
    this.showFooter = true,
    this.footerLine1 = 'Merci pour votre confiance',
    this.footerLine2 = 'Solution conçue par Mohamed',
    this.showPageNumbers = true,
    this.template = DocumentTemplate.modern,
    this.accentColor = 0xFF2563EB,
    this.imageFormat = DocumentImageFormat.a4,
    this.imageQuality = DocumentImageQuality.high,
    this.jpgQuality = 92,
  });

  factory DocumentSettings.defaults() => const DocumentSettings();

  /// Vrai si le logo doit être dessiné (activé et chemin fourni).
  bool get hasLogo => showLogo && (logoPath?.trim().isNotEmpty ?? false);

  /// Vrai si un texte de paiement doit apparaître.
  bool get hasPaymentInfo =>
      showPaymentInfo && paymentInfoText.trim().isNotEmpty;

  /// Vrai si le QR doit apparaître.
  bool get hasQr =>
      showQr &&
      (qrContentMode == DocumentQrContent.reference ||
          qrCustomText.trim().isNotEmpty);

  DocumentSettings copyWith({
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessEmail,
    String? businessRegistration,
    String? logoPath,
    bool clearLogo = false,
    bool? showLogo,
    bool? showWatermark,
    double? watermarkOpacity,
    bool? showBusinessInfo,
    bool? showInvoiceNumber,
    bool? showDateTime,
    bool? showStatusBadge,
    bool? showItemIndex,
    bool? showUnitPrice,
    bool? showTotalsSummary,
    bool? showNotes,
    bool? showPaymentInfo,
    String? paymentInfoText,
    bool? showQr,
    DocumentQrContent? qrContentMode,
    String? qrCustomText,
    bool? showFooter,
    String? footerLine1,
    String? footerLine2,
    bool? showPageNumbers,
    DocumentTemplate? template,
    int? accentColor,
    DocumentImageFormat? imageFormat,
    DocumentImageQuality? imageQuality,
    int? jpgQuality,
  }) =>
      DocumentSettings(
        businessName: businessName ?? this.businessName,
        businessAddress: businessAddress ?? this.businessAddress,
        businessPhone: businessPhone ?? this.businessPhone,
        businessEmail: businessEmail ?? this.businessEmail,
        businessRegistration: businessRegistration ?? this.businessRegistration,
        logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
        showLogo: showLogo ?? this.showLogo,
        showWatermark: showWatermark ?? this.showWatermark,
        watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
        showBusinessInfo: showBusinessInfo ?? this.showBusinessInfo,
        showInvoiceNumber: showInvoiceNumber ?? this.showInvoiceNumber,
        showDateTime: showDateTime ?? this.showDateTime,
        showStatusBadge: showStatusBadge ?? this.showStatusBadge,
        showItemIndex: showItemIndex ?? this.showItemIndex,
        showUnitPrice: showUnitPrice ?? this.showUnitPrice,
        showTotalsSummary: showTotalsSummary ?? this.showTotalsSummary,
        showNotes: showNotes ?? this.showNotes,
        showPaymentInfo: showPaymentInfo ?? this.showPaymentInfo,
        paymentInfoText: paymentInfoText ?? this.paymentInfoText,
        showQr: showQr ?? this.showQr,
        qrContentMode: qrContentMode ?? this.qrContentMode,
        qrCustomText: qrCustomText ?? this.qrCustomText,
        showFooter: showFooter ?? this.showFooter,
        footerLine1: footerLine1 ?? this.footerLine1,
        footerLine2: footerLine2 ?? this.footerLine2,
        showPageNumbers: showPageNumbers ?? this.showPageNumbers,
        template: template ?? this.template,
        accentColor: accentColor ?? this.accentColor,
        imageFormat: imageFormat ?? this.imageFormat,
        imageQuality: imageQuality ?? this.imageQuality,
        jpgQuality: jpgQuality ?? this.jpgQuality,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': currentVersion,
        'businessName': businessName,
        'businessAddress': businessAddress,
        'businessPhone': businessPhone,
        'businessEmail': businessEmail,
        'businessRegistration': businessRegistration,
        'logoPath': logoPath,
        'showLogo': showLogo,
        'showWatermark': showWatermark,
        'watermarkOpacity': watermarkOpacity,
        'showBusinessInfo': showBusinessInfo,
        'showInvoiceNumber': showInvoiceNumber,
        'showDateTime': showDateTime,
        'showStatusBadge': showStatusBadge,
        'showItemIndex': showItemIndex,
        'showUnitPrice': showUnitPrice,
        'showTotalsSummary': showTotalsSummary,
        'showNotes': showNotes,
        'showPaymentInfo': showPaymentInfo,
        'paymentInfoText': paymentInfoText,
        'showQr': showQr,
        'qrContentMode': qrContentMode.name,
        'qrCustomText': qrCustomText,
        'showFooter': showFooter,
        'footerLine1': footerLine1,
        'footerLine2': footerLine2,
        'showPageNumbers': showPageNumbers,
        'template': template.name,
        'accentColor': accentColor,
        'imageFormat': imageFormat.name,
        'imageQuality': imageQuality.name,
        'jpgQuality': jpgQuality,
      };

  /// Lit un JSON de réglages. Toute valeur absente, de mauvais type ou hors
  /// bornes retombe sur la valeur par défaut correspondante.
  factory DocumentSettings.fromJson(Map<String, dynamic> json) {
    const fallback = DocumentSettings();

    String readString(String key, String defaultValue) {
      final value = json[key];
      return value is String ? value : defaultValue;
    }

    bool readBool(String key, bool defaultValue) {
      final value = json[key];
      return value is bool ? value : defaultValue;
    }

    String? readEnumName(String key) {
      final value = json[key];
      return value is String ? value : null;
    }

    final rawOpacity = json['watermarkOpacity'];
    final opacity = rawOpacity is num
        ? rawOpacity.toDouble().clamp(0.03, 0.15)
        : fallback.watermarkOpacity;

    final rawJpg = json['jpgQuality'];
    final jpgQuality =
        rawJpg is num ? rawJpg.round().clamp(70, 98) : fallback.jpgQuality;

    // Migration des réglages : un JSON d'avant la v2 qui porte encore les
    // anciens défauts (Standard + JPG 85), jamais personnalisés, passe aux
    // nouveaux (Haute + JPG 92). Toute valeur choisie par l'utilisateur est
    // conservée telle quelle.
    final rawVersion = json['version'];
    final storedVersion = rawVersion is num ? rawVersion.toInt() : 1;
    var imageQuality =
        DocumentImageQuality.fromName(readEnumName('imageQuality'));
    var resolvedJpgQuality = jpgQuality;
    if (storedVersion < currentVersion &&
        imageQuality == DocumentImageQuality.standard &&
        resolvedJpgQuality == 85) {
      imageQuality = DocumentImageQuality.high;
      resolvedJpgQuality = 92;
    }

    final rawAccent = json['accentColor'];
    final accentColor =
        rawAccent is num ? (rawAccent.toInt() & 0xFFFFFFFF) : fallback.accentColor;

    return DocumentSettings(
      businessName: readString('businessName', fallback.businessName),
      businessAddress: readString('businessAddress', fallback.businessAddress),
      businessPhone: readString('businessPhone', fallback.businessPhone),
      businessEmail: readString('businessEmail', fallback.businessEmail),
      businessRegistration:
          readString('businessRegistration', fallback.businessRegistration),
      // Une clé explicitement nulle signifie « aucun logo » ; une clé absente
      // (ancien JSON) garde le logo par défaut.
      logoPath: json.containsKey('logoPath')
          ? (json['logoPath'] is String ? json['logoPath'] as String : null)
          : fallback.logoPath,
      showLogo: readBool('showLogo', fallback.showLogo),
      showWatermark: readBool('showWatermark', fallback.showWatermark),
      watermarkOpacity: opacity,
      showBusinessInfo:
          readBool('showBusinessInfo', fallback.showBusinessInfo),
      showInvoiceNumber:
          readBool('showInvoiceNumber', fallback.showInvoiceNumber),
      showDateTime: readBool('showDateTime', fallback.showDateTime),
      showStatusBadge: readBool('showStatusBadge', fallback.showStatusBadge),
      showItemIndex: readBool('showItemIndex', fallback.showItemIndex),
      showUnitPrice: readBool('showUnitPrice', fallback.showUnitPrice),
      showTotalsSummary:
          readBool('showTotalsSummary', fallback.showTotalsSummary),
      showNotes: readBool('showNotes', fallback.showNotes),
      showPaymentInfo: readBool('showPaymentInfo', fallback.showPaymentInfo),
      paymentInfoText:
          readString('paymentInfoText', fallback.paymentInfoText),
      showQr: readBool('showQr', fallback.showQr),
      qrContentMode: DocumentQrContent.fromName(readEnumName('qrContentMode')),
      qrCustomText: readString('qrCustomText', fallback.qrCustomText),
      showFooter: readBool('showFooter', fallback.showFooter),
      footerLine1: readString('footerLine1', fallback.footerLine1),
      footerLine2: readString('footerLine2', fallback.footerLine2),
      showPageNumbers: readBool('showPageNumbers', fallback.showPageNumbers),
      template: DocumentTemplate.fromName(readEnumName('template')),
      accentColor: accentColor,
      imageFormat:
          DocumentImageFormat.fromName(readEnumName('imageFormat')),
      imageQuality: imageQuality,
      jpgQuality: resolvedJpgQuality,
    );
  }

  /// Champs comparés par [==] et [hashCode] (égalité par valeur, nécessaire
  /// au ValueNotifier des réglages).
  List<Object?> get _identity => <Object?>[
        businessName,
        businessAddress,
        businessPhone,
        businessEmail,
        businessRegistration,
        logoPath,
        showLogo,
        showWatermark,
        watermarkOpacity,
        showBusinessInfo,
        showInvoiceNumber,
        showDateTime,
        showStatusBadge,
        showItemIndex,
        showUnitPrice,
        showTotalsSummary,
        showNotes,
        showPaymentInfo,
        paymentInfoText,
        showQr,
        qrContentMode,
        qrCustomText,
        showFooter,
        footerLine1,
        footerLine2,
        showPageNumbers,
        template,
        accentColor,
        imageFormat,
        imageQuality,
        jpgQuality,
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentSettings && listEquals(_identity, other._identity);

  @override
  int get hashCode => Object.hashAll(_identity);
}
