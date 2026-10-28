// lib/services/history_service.dart
// Historique des noms (clients / produits). La liste est conservée en
// mémoire partagée pour un accès synchrone (autocomplétion, index des prix).

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/text_utils.dart';

class HistoryService {
  static const String _clientNamesKey = 'history_client_names';
  static const String _productNamesKey = 'history_product_names';

  static final List<String> _clientNames = <String>[];
  static final List<String> _productNames = <String>[];
  static bool _clientNamesLoaded = false;
  static bool _productNamesLoaded = false;

  /// Cache mémoire des noms de clients (vide tant que rien n'a été chargé).
  List<String> get cachedClientNames =>
      UnmodifiableListView<String>(_clientNames);

  /// Cache mémoire des noms de produits (vide tant que rien n'a été chargé).
  List<String> get cachedProductNames =>
      UnmodifiableListView<String>(_productNames);

  Future<List<String>> getClientNames() async {
    await _ensureClientNamesLoaded();
    return List<String>.from(_clientNames);
  }

  Future<List<String>> getProductNames() async {
    await _ensureProductNamesLoaded();
    return List<String>.from(_productNames);
  }

  /// Recherche insensible à la casse et aux accents dans le cache mémoire.
  Future<List<String>> searchClientNames(String query) async {
    await _ensureClientNamesLoaded();
    return searchClientNamesSync(query);
  }

  /// Variante synchrone (le cache doit avoir été chargé au moins une fois).
  List<String> searchClientNamesSync(String query) {
    final searchTerm = normalizeKey(query);
    if (searchTerm.isEmpty) return const [];
    return _clientNames
        .where((name) => normalizeKey(name).contains(searchTerm))
        .toList();
  }

  Future<void> saveClientName(String clientName) async {
    await _ensureClientNamesLoaded();
    await _saveHistoryItem(_clientNamesKey, _clientNames, clientName);
  }

  Future<void> saveProductName(String productName) async {
    await _ensureProductNamesLoaded();
    await _saveHistoryItem(_productNamesKey, _productNames, productName);
  }

  Future<void> deleteClientName(String clientName) async {
    await _ensureClientNamesLoaded();
    await _deleteHistoryItem(_clientNamesKey, _clientNames, clientName);
  }

  Future<void> deleteProductName(String productName) async {
    await _ensureProductNamesLoaded();
    await _deleteHistoryItem(_productNamesKey, _productNames, productName);
  }

  Future<void> clearClientNames() async {
    _clientNames.clear();
    _clientNamesLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clientNamesKey);
  }

  Future<void> clearProductNames() async {
    _productNames.clear();
    _productNamesLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_productNamesKey);
  }

  /// Remplace entièrement les historiques (utilisé lors d'une restauration).
  Future<void> replaceAll(
      List<String> clientNames, List<String> productNames) async {
    _clientNames
      ..clear()
      ..addAll(clientNames);
    _productNames
      ..clear()
      ..addAll(productNames);
    _clientNamesLoaded = true;
    _productNamesLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_clientNamesKey, _clientNames);
    await prefs.setStringList(_productNamesKey, _productNames);
  }

  /// Recharge les deux listes en mémoire.
  Future<void> reload() async {
    _clientNamesLoaded = false;
    _productNamesLoaded = false;
    await _ensureClientNamesLoaded();
    await _ensureProductNamesLoaded();
  }

  /// Vide le cache statique (tests uniquement).
  @visibleForTesting
  static void resetCacheForTests() {
    _clientNames.clear();
    _productNames.clear();
    _clientNamesLoaded = false;
    _productNamesLoaded = false;
  }

  static Future<void> _ensureClientNamesLoaded() async {
    if (_clientNamesLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _clientNames
      ..clear()
      ..addAll(prefs.getStringList(_clientNamesKey) ?? <String>[]);
    _clientNamesLoaded = true;
  }

  static Future<void> _ensureProductNamesLoaded() async {
    if (_productNamesLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _productNames
      ..clear()
      ..addAll(prefs.getStringList(_productNamesKey) ?? <String>[]);
    _productNamesLoaded = true;
  }

  static Future<void> _saveHistoryItem(
      String key, List<String> cache, String item) async {
    final normalized = item.trim();
    if (normalized.isEmpty) return;

    final itemKey = normalizeKey(normalized);
    cache.removeWhere((value) => normalizeKey(value) == itemKey);
    cache.insert(0, normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, cache);
  }

  static Future<void> _deleteHistoryItem(
      String key, List<String> cache, String item) async {
    final itemKey = normalizeKey(item);
    cache.removeWhere((value) => normalizeKey(value) == itemKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, cache);
  }
}
