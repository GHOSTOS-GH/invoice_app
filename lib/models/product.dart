// lib/models/product.dart

class Product {
  final String id;
  String name;
  String category;
  String? imagePath; // chemin local de l'image

  Product({
    required this.id,
    required this.name,
    required this.category,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'imagePath': imagePath,
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        imagePath: json['imagePath'] as String?,
      );

  Product copyWith({
    String? name,
    String? category,
    String? imagePath,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        category: category ?? this.category,
        imagePath: imagePath ?? this.imagePath,
      );
}
