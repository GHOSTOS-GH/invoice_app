// lib/models/invoice.dart
import 'dart:collection';

/// Compteur monotone garantissant l'unicité de deux ids générés dans la même
/// microseconde.
int _invoiceItemIdSequence = 0;

/// Identifiant stable d'un article : compteur + horodatage en microsecondes.
/// Il sert de clé d'interface (lignes éditables, suppression par glissement)
/// et ne participe ni aux calculs ni aux exports.
String generateInvoiceItemId() {
  _invoiceItemIdSequence += 1;
  return '${DateTime.now().microsecondsSinceEpoch}-$_invoiceItemIdSequence';
}

class InvoiceItem {
  /// Identifiant stable de l'article. Conservé par [copyWith] et écrit dans le
  /// JSON ; les anciens articles sans id en reçoivent un au chargement.
  final String id;

  final String name;
  final int quantity;

  /// Prix unitaire en FCFA (toujours entier, jamais de décimal).
  final int unitPrice;

  InvoiceItem({
    String? id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
  }) : id = id ?? generateInvoiceItemId();

  /// Sous-total de la ligne en FCFA (entier).
  int get subtotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  /// Lit un article, y compris depuis les anciens JSON qui contenaient des
  /// prix décimaux (99.99 → 100) ou pas d'id : le chargement ne doit jamais
  /// échouer.
  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return InvoiceItem(
      id: rawId is String && rawId.trim().isNotEmpty ? rawId : null,
      name: json['name'] as String,
      quantity: (json['quantity'] as num?)?.round() ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.round() ?? 0,
    );
  }

  InvoiceItem copyWith({
    String? id,
    String? name,
    int? quantity,
    int? unitPrice,
  }) =>
      InvoiceItem(
        id: id ?? this.id,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
      );
}

/// Statut d'une facture. Aucune couleur ici : l'apparence vient de
/// `statusStyle(context, status)` (lib/theme/app_colors.dart), et le PDF
/// possède son propre mapping.
enum InvoiceStatus {
  enCours('En cours'),
  enLivraison('En livraison'),
  livree('Livrée'),
  archivee('Archivée');

  final String label;

  const InvoiceStatus(this.label);
}

class Invoice {
  final String id;
  final String clientName;
  final DateTime createdAt;
  final List<InvoiceItem> _items;
  final InvoiceStatus status;
  final String? notes;

  /// Remise accordée sur la facture, en FCFA (0 = aucune). Entier.
  final int discount;

  /// Taux de TVA en pourcentage (0 = aucune). Seul montant non entier du
  /// modèle : c'est un pourcentage, pas une somme d'argent.
  final double taxRate;

  Invoice({
    required this.id,
    required this.clientName,
    required this.createdAt,
    required List<InvoiceItem> items,
    this.status = InvoiceStatus.enCours,
    this.notes,
    this.discount = 0,
    this.taxRate = 0,
  }) : _items = List.unmodifiable(items);

  UnmodifiableListView<InvoiceItem> get items => UnmodifiableListView(_items);

  /// Sous-total = somme des articles (avant remise et TVA).
  int get total => _items.fold(0, (sum, item) => sum + item.subtotal);

  /// Alias lisible de [total] : sous-total de la facture, en FCFA.
  int get subtotal => total;

  /// Remise réellement appliquée : jamais négative, jamais supérieure au
  /// sous-total (les anciennes données peuvent contenir une remise trop
  /// grande).
  int get discountApplied {
    if (discount <= 0) return 0;
    return discount > total ? total : discount;
  }

  /// Montant de la TVA = (sous-total − remise appliquée) × taux / 100,
  /// arrondi à l'entier le plus proche (FCFA).
  int get taxAmount => ((total - discountApplied) * taxRate / 100).round();

  /// Total à payer = sous-total − remise + TVA. C'est LE montant de
  /// référence : il doit être utilisé partout (écrans, PDF, reçu, CSV).
  int get payableTotal => total - discountApplied + taxAmount;

  bool get hasBreakdown => discount > 0 || taxRate > 0;

  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientName': clientName,
        'createdAt': createdAt.toIso8601String(),
        'items': _items.map((e) => e.toJson()).toList(),
        'status': status.name,
        'notes': notes,
        'discount': discount,
        'taxRate': taxRate,
      };

  /// Lit une facture, y compris depuis les anciens JSON (prix 99.99,
  /// remise 10.5…) : les montants sont arrondis via `.round()`.
  factory Invoice.fromJson(Map<String, dynamic> json) => Invoice(
        id: json['id'] as String,
        clientName: json['clientName'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        items: (json['items'] as List)
            .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        status: InvoiceStatus.values.firstWhere(
          (e) => e.name == (json['status'] ?? 'enCours'),
          orElse: () => InvoiceStatus.enCours,
        ),
        notes: json['notes'] as String?,
        discount: (json['discount'] as num?)?.round() ?? 0,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
      );

  Invoice copyWith({
    String? id,
    String? clientName,
    DateTime? createdAt,
    List<InvoiceItem>? items,
    InvoiceStatus? status,
    String? notes,
    int? discount,
    double? taxRate,
  }) =>
      Invoice(
        id: id ?? this.id,
        clientName: clientName ?? this.clientName,
        createdAt: createdAt ?? this.createdAt,
        items: items ?? _items,
        status: status ?? this.status,
        notes: notes ?? this.notes,
        discount: discount ?? this.discount,
        taxRate: taxRate ?? this.taxRate,
      );
}
