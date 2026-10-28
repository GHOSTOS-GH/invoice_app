// lib/services/client_price_index.dart
// Index en mémoire des dernières ventes : client → produit → dernier prix.
// Reconstruit à chaque notification du repository de factures.

import '../utils/text_utils.dart';
import 'history_service.dart';
import 'invoice_repository.dart';

/// Dernière vente connue d'un produit à un client.
class LastSale {
  final int price;
  final DateTime date;
  final String invoiceId;

  const LastSale({
    required this.price,
    required this.date,
    required this.invoiceId,
  });
}

class ClientPriceIndex {
  ClientPriceIndex._() {
    InvoiceRepository().addListener(_rebuild);
    _rebuild();
    // Charge l'historique partagé puis reconstruit pour le fusionner.
    _historyService.getClientNames().then((_) => _rebuild());
  }

  static final ClientPriceIndex _instance = ClientPriceIndex._();
  factory ClientPriceIndex() => _instance;

  final HistoryService _historyService = HistoryService();

  Map<String, Map<String, LastSale>> _index = const {};
  List<String> _clientNames = const [];

  /// Dernière vente de [productName] à [clientName].
  ///
  /// [excludeInvoiceId] permet d'ignorer la facture en cours d'édition.
  LastSale? lastSale(
    String clientName,
    String productName, {
    String? excludeInvoiceId,
  }) {
    final sale = _index[normalizeKey(clientName)]?[normalizeKey(productName)];
    if (sale == null) return null;
    if (excludeInvoiceId == null || sale.invoiceId != excludeInvoiceId) {
      return sale;
    }
    return _findSaleExcluding(clientName, productName, excludeInvoiceId);
  }

  /// Tous les derniers prix connus pour [clientName] :
  /// { clé produit normalisée → prix } (compatibilité StorageService).
  Map<String, int> pricesForClient(String clientName) {
    final products = _index[normalizeKey(clientName)];
    if (products == null) return const {};
    return {
      for (final entry in products.entries) entry.key: entry.value.price,
    };
  }

  /// Noms d'affichage des clients : ventes les plus récentes, dédoublonnés
  /// par clé normalisée, puis complétés par l'historique d'autocomplétion.
  List<String> clientNames() => List<String>.unmodifiable(_clientNames);

  void _rebuild() {
    final invoices = InvoiceRepository().invoices.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final index = <String, Map<String, LastSale>>{};
    final displayNames = <String, String>{};
    for (final invoice in invoices) {
      final clientKey = normalizeKey(invoice.clientName);
      if (clientKey.isEmpty) continue;
      displayNames.putIfAbsent(clientKey, () => invoice.clientName.trim());
      final products =
          index.putIfAbsent(clientKey, () => <String, LastSale>{});
      for (final item in invoice.items) {
        final productKey = normalizeKey(item.name);
        if (productKey.isEmpty) continue;
        products.putIfAbsent(
          productKey,
          () => LastSale(
            price: item.unitPrice,
            date: invoice.createdAt,
            invoiceId: invoice.id,
          ),
        );
      }
    }

    final merged = <String>[];
    final seen = <String>{};
    void addName(String rawName) {
      final name = rawName.trim();
      final key = normalizeKey(name);
      if (key.isEmpty || !seen.add(key)) return;
      merged.add(name);
    }

    // Les factures étant triées de la plus récente à la plus ancienne,
    // la première rencontre est bien le nom d'affichage le plus récent.
    for (final name in displayNames.values) {
      addName(name);
    }
    for (final name in _historyService.cachedClientNames) {
      addName(name);
    }

    _index = index;
    _clientNames = merged;
  }

  LastSale? _findSaleExcluding(
    String clientName,
    String productName,
    String excludeInvoiceId,
  ) {
    final clientKey = normalizeKey(clientName);
    final productKey = normalizeKey(productName);
    if (clientKey.isEmpty || productKey.isEmpty) return null;

    final invoices = InvoiceRepository().invoices.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final invoice in invoices) {
      if (invoice.id == excludeInvoiceId) continue;
      if (normalizeKey(invoice.clientName) != clientKey) continue;
      for (final item in invoice.items) {
        if (normalizeKey(item.name) == productKey) {
          return LastSale(
            price: item.unitPrice,
            date: invoice.createdAt,
            invoiceId: invoice.id,
          );
        }
      }
    }
    return null;
  }
}
