// lib/services/product_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

class ProductService {
  static const String _productsKey = 'products';

  Future<List<Product>> loadProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_productsKey);
    if (jsonString == null) return [];
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => Product.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveProducts(List<Product> products) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = products.map((p) => p.toJson()).toList();
    await prefs.setString(_productsKey, jsonEncode(jsonList));
  }

  Future<void> addProduct(Product product) async {
    final products = await loadProducts();
    products.add(product);
    await saveProducts(products);
  }

  Future<void> updateProduct(Product product) async {
    final products = await loadProducts();
    final index = products.indexWhere((p) => p.id == product.id);
    if (index != -1) {
      products[index] = product;
      await saveProducts(products);
    }
  }

  Future<void> deleteProduct(String id) async {
    final products = await loadProducts();
    products.removeWhere((p) => p.id == id);
    await saveProducts(products);
  }

  Future<List<String>> getCategories() async {
    final products = await loadProducts();
    return products.map((p) => p.category).toSet().toList();
  }
}
