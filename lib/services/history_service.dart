// lib/services/history_service.dart

import 'package:shared_preferences/shared_preferences.dart';

class HistoryService {
  static const String _clientNamesKey = 'history_client_names';
  static const String _productNamesKey = 'history_product_names';

  Future<List<String>> getClientNames() async {
    return _loadHistory(_clientNamesKey);
  }

  Future<List<String>> getProductNames() async {
    return _loadHistory(_productNamesKey);
  }

  Future<List<String>> searchClientNames(String query) async {
    final names = await getClientNames();
    final searchTerm = query.trim().toLowerCase();
    if (searchTerm.isEmpty) return [];
    return names.where((name) => name.toLowerCase().contains(searchTerm)).toList();
  }

  Future<void> saveClientName(String clientName) async {
    await _saveHistoryItem(_clientNamesKey, clientName);
  }

  Future<void> saveProductName(String productName) async {
    await _saveHistoryItem(_productNamesKey, productName);
  }

  Future<void> deleteClientName(String clientName) async {
    await _deleteHistoryItem(_clientNamesKey, clientName);
  }

  Future<void> deleteProductName(String productName) async {
    await _deleteHistoryItem(_productNamesKey, productName);
  }

  Future<void> clearClientNames() async {
    await _clearHistory(_clientNamesKey);
  }

  Future<void> clearProductNames() async {
    await _clearHistory(_productNamesKey);
  }

  /// Remplace entièrement les historiques (utilisé lors d'une restauration).
  Future<void> replaceAll(List<String> clientNames, List<String> productNames) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_clientNamesKey, clientNames);
    await prefs.setStringList(_productNamesKey, productNames);
  }

  Future<List<String>> _loadHistory(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key) ?? <String>[];
  }

  Future<void> _saveHistoryItem(String key, String item) async {
    final normalized = item.trim();
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(key) ?? <String>[];
    history.removeWhere((value) => value.toLowerCase() == normalized.toLowerCase());
    history.insert(0, normalized);
    await prefs.setStringList(key, history);
  }

  Future<void> _deleteHistoryItem(String key, String item) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(key) ?? <String>[];
    history.removeWhere((value) => value.toLowerCase() == item.trim().toLowerCase());
    await prefs.setStringList(key, history);
  }

  Future<void> _clearHistory(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

