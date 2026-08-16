// lib/models/invoice.dart
import 'dart:collection';

class InvoiceItem {
  final String name;
  final int quantity;
  final double unitPrice;

  const InvoiceItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  double get subtotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };

  factory InvoiceItem.fromJson(Map<String, dynamic> json) => InvoiceItem(
        name: json['name'] as String,
        quantity: (json['quantity'] as num).toInt(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
      );

  InvoiceItem copyWith({
    String? name,
    int? quantity,
    double? unitPrice,
  }) =>
      InvoiceItem(
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
      );
}

enum InvoiceStatus {
  enCours('En cours', 0xFF6B4C4C),
  enLivraison('En livraison', 0xFFFFC107),
  livree('Livrée', 0xFF4CAF50),
  archivee('Archivée', 0xFF9E9E9E);

  final String label;
  final int color;

  const InvoiceStatus(this.label, this.color);
}

class Invoice {
  final String id;
  final String clientName;
  final DateTime createdAt;
  final List<InvoiceItem> _items;
  final InvoiceStatus status;
  final String? notes;

  /// Remise accordée sur la facture, en FCFA (0 = aucune).
  final double discount;

  /// Taux de TVA en pourcentage (0 = aucune).
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
  double get total => _items.fold(0.0, (sum, item) => sum + item.subtotal);

  /// Montant de la TVA = (sous-total − remise) × taux / 100.
  double get taxAmount => (total - discount) * taxRate / 100;

  /// Total à payer = sous-total − remise + TVA.
  double get payableTotal => total - discount + taxAmount;

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
        discount: (json['discount'] as num?)?.toDouble() ?? 0,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
      );

  Invoice copyWith({
    String? id,
    String? clientName,
    DateTime? createdAt,
    List<InvoiceItem>? items,
    InvoiceStatus? status,
    String? notes,
    double? discount,
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