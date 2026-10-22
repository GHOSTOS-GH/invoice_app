// lib/services/invoice_repository.dart
// Source de données unique pour les factures : liste en mémoire, notifiée à
// chaque changement, persistée via une file d'écriture sérialisée.

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/invoice.dart';
import '../utils/constants.dart';
import 'storage_service.dart';

class InvoiceRepository extends ChangeNotifier {
  InvoiceRepository._();

  static final InvoiceRepository _instance = InvoiceRepository._();
  factory InvoiceRepository() => _instance;

  /// Clé de secours où est conservée la chaîne brute de `invoices` quand
  /// elle n'a pas pu être décodée. Elle n'est jamais écrasée par une écriture
  /// ultérieure du repository.
  static const String corruptBackupKey = 'invoices_corrupt_backup';

  final StorageService _storage = StorageService();

  List<Invoice> _invoices = const [];
  bool _isLoaded = false;
  bool _hasLoadError = false;
  Object? _loadError;
  Future<void>? _loading;
  Future<void> _writeQueue = Future<void>.value();
  bool _corruptBackupSaved = false;

  /// Liste non modifiable des factures en mémoire.
  UnmodifiableListView<Invoice> get invoices =>
      UnmodifiableListView<Invoice>(_invoices);

  /// Vrai quand le chargement initial a réussi.
  bool get isLoaded => _isLoaded;

  /// Vrai si le dernier chargement a échoué (JSON corrompu).
  bool get hasLoadError => _hasLoadError;

  /// Erreur du dernier chargement, exposée à l'UI.
  Object? get loadError => _loadError;

  /// Charge la liste une seule fois. Un nouvel appel après un échec retente
  /// le chargement (bouton « Réessayer » de l'historique).
  Future<void> load() async {
    if (_isLoaded) return;
    final pending = _loading;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _loadFromStorage();
    _loading = future;
    try {
      await future;
    } finally {
      if (identical(_loading, future)) _loading = null;
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final loaded = await _storage.loadInvoices();
      _invoices = loaded;
      _isLoaded = true;
      _hasLoadError = false;
      _loadError = null;
    } catch (error) {
      // Ne jamais écraser les données : la chaîne brute est mise de côté
      // avant toute écriture ultérieure.
      _invoices = const [];
      _isLoaded = false;
      _hasLoadError = true;
      _loadError = error;
      debugPrint('InvoiceRepository : chargement impossible ($error)');
      await _saveCorruptBackup();
    }
    notifyListeners();
  }

  Future<void> _saveCorruptBackup() async {
    if (_corruptBackupSaved) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(Constants.invoicesKey);
      if (raw == null) return;
      await prefs.setString(corruptBackupKey, raw);
      _corruptBackupSaved = true;
    } catch (error) {
      debugPrint('InvoiceRepository : sauvegarde du JSON corrompu impossible '
          '($error)');
    }
  }

  /// Ajoute une facture (ou remplace celle qui porte le même id).
  Future<void> add(Invoice invoice) {
    _upsert(invoice);
    return _persist();
  }

  /// Met à jour la facture portant le même id (ajoutée si absente).
  Future<void> update(Invoice invoice) {
    _upsert(invoice);
    return _persist();
  }

  void _upsert(Invoice invoice) {
    final index = _invoices.indexWhere((item) => item.id == invoice.id);
    if (index == -1) {
      _invoices = [..._invoices, invoice];
    } else {
      final copy = List<Invoice>.from(_invoices);
      copy[index] = invoice;
      _invoices = copy;
    }
    _isLoaded = true;
    _hasLoadError = false;
    _loadError = null;
    notifyListeners();
  }

  /// Supprime toutes les factures dont l'id figure dans [ids].
  Future<void> removeByIds(Iterable<String> ids) {
    final selected = ids.toSet();
    if (selected.isEmpty) return Future<void>.value();
    _invoices =
        _invoices.where((invoice) => !selected.contains(invoice.id)).toList();
    notifyListeners();
    return _persist();
  }

  /// Remplace entièrement la liste (restauration de sauvegarde).
  Future<void> replaceAll(List<Invoice> invoices) {
    _invoices = List<Invoice>.from(invoices);
    _isLoaded = true;
    _hasLoadError = false;
    _loadError = null;
    notifyListeners();
    return _persist();
  }

  /// Sérialise l'état courant mémoire. Les écritures sont enchaînées : deux
  /// enregistrements ne peuvent jamais se chevaucher, et chacune capture
  /// l'état au moment de l'appel.
  Future<void> _persist() {
    final snapshot = List<Invoice>.from(_invoices);
    final next = _writeQueue.then((_) async {
      await _saveCorruptBackup();
      await _storage.saveInvoices(snapshot);
    });
    // La file continue même si une écriture échoue ; l'erreur reste
    // remontée à l'appelant.
    _writeQueue = next.catchError((Object error, StackTrace stack) {
      debugPrint('InvoiceRepository : écriture impossible ($error)');
    });
    return next;
  }

  /// Remet le singleton dans son état initial (tests uniquement).
  @visibleForTesting
  void resetForTests() {
    _invoices = const [];
    _isLoaded = false;
    _hasLoadError = false;
    _loadError = null;
    _loading = null;
    _writeQueue = Future<void>.value();
    _corruptBackupSaved = false;
  }
}
