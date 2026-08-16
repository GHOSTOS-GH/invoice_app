// lib/services/storage_service.dart
// Gestion du stockage des factures et des brouillons

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/invoice.dart';
import '../utils/constants.dart';

class StorageService {
  // ---------- Factures ----------
  Future<void> saveInvoices(List<Invoice> invoices) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = invoices.map((invoice) => invoice.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await prefs.setString(Constants.invoicesKey, jsonString);
  }

  Future<List<Invoice>> loadInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(Constants.invoicesKey);
    if (jsonString == null) return [];
    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => Invoice.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Relance l'exception pour que l'appelant puisse afficher un message utilisateur
      debugPrint('Erreur lors du chargement des factures: $e');
      rethrow;
    }
  }

  Future<void> addInvoice(Invoice invoice) async {
    final invoices = await loadInvoices();
    invoices.add(invoice);
    await saveInvoices(invoices);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.invoicesKey);
  }

  // ---------- Brouillon de facture ----------
  Future<void> saveDraft(Invoice draft) async {
    final prefs = await SharedPreferences.getInstance();
    final json = draft.toJson();
    final jsonString = jsonEncode(json);
    await prefs.setString(Constants.draftInvoiceKey, jsonString);
  }

  Future<Invoice?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(Constants.draftInvoiceKey);
    if (jsonString == null) return null;
    try {
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return Invoice.fromJson(jsonMap);
    } catch (e) {
      debugPrint('Erreur lors du chargement du brouillon: $e');
      return null;
    }
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.draftInvoiceKey);
  }

  // ---------- Prix historiques (dernier prix par client / produit) ----------

  /// Retourne le dernier prix unitaire du [productName] vendu à [clientName].
  /// Les prix variant selon les clients, on recherche dans les factures
  /// du client en partant de la plus récente. Retourne null si aucun historique.
  Future<double?> getLastPriceForClientProduct(String clientName, String productName) async {
    final map = await getClientPriceMap(clientName);
    return map[productName.trim().toLowerCase()];
  }

  /// Retourne la map { nomProduit(minuscule) -> dernierPrixUnitaire } pour le client.
  /// La facture la plus récente du client fait foi pour chaque produit.
  Future<Map<String, double>> getClientPriceMap(String clientName) async {
    final result = <String, double>{};
    final name = clientName.trim();
    if (name.isEmpty) return result;

    final invoices = await loadInvoices();
    final sorted = List<Invoice>.from(invoices)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    for (final inv in sorted) {
      if (inv.clientName.trim().toLowerCase() != name.toLowerCase()) continue;
      for (final item in inv.items) {
        result.putIfAbsent(item.name.trim().toLowerCase(), () => item.unitPrice);
      }
    }
    return result;
  }
}