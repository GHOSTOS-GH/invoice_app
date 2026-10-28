// lib/services/auth_service.dart
// Gestion de l'authentification admin avec persistance journalière.
// Les identifiants de Constants sont la valeur par défaut ; des identifiants
// personnalisés (sel + hash SHA-256) les remplacent s'ils existent.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

/// Résultat d'un changement d'identifiants admin.
enum CredentialChangeResult {
  success,
  wrongCurrentPassword,
  invalidFormat,
}

class AuthService {
  static const String _lastLoginDateKey = Constants.lastLoginDateKey;
  static const String _usernameKey = 'auth_username';
  static const String _saltKey = 'auth_salt';
  static const String _hashKey = 'auth_hash';

  // Vérifie si l'utilisateur est déjà authentifié aujourd'hui
  Future<bool> isAuthenticatedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final lastLogin = prefs.getString(_lastLoginDateKey);
    if (lastLogin == null) return false;

    final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
    return lastLogin == today;
  }

  // Tente de se connecter avec les identifiants admin (personnalisés ou
  // ceux de Constants).
  Future<bool> login(String username, String password) async {
    final valid = await _verify(username, password);
    if (!valid) return false;

    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString(_lastLoginDateKey, today);
    return true;
  }

  /// Change l'identifiant et le code admin après vérification du code actuel.
  ///
  /// L'identifiant doit faire 3 à 20 caractères sans espace de bord, le code
  /// 4 à 12 caractères. Le code n'est jamais stocké en clair.
  Future<CredentialChangeResult> changeCredentials({
    required String currentPassword,
    required String newUsername,
    required String newPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentUsername = prefs.getString(_usernameKey) ??
        Constants.adminUsername;

    if (!await _verify(currentUsername, currentPassword)) {
      return CredentialChangeResult.wrongCurrentPassword;
    }

    final username = newUsername.trim();
    final usernameValid =
        username == newUsername && username.length >= 3 && username.length <= 20;
    final passwordValid =
        newPassword.length >= 4 && newPassword.length <= 12;
    if (!usernameValid || !passwordValid) {
      return CredentialChangeResult.invalidFormat;
    }

    final salt = _generateSalt();
    await prefs.setString(_usernameKey, username);
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(salt, newPassword));
    return CredentialChangeResult.success;
  }

  // Déconnexion manuelle (optionnelle)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastLoginDateKey);
  }

  Future<bool> _verify(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUsername = prefs.getString(_usernameKey);
    final salt = prefs.getString(_saltKey);
    final hash = prefs.getString(_hashKey);

    // Aucun identifiant personnalisé : valeurs par défaut de Constants.
    if (storedUsername == null || salt == null || hash == null) {
      return username == Constants.adminUsername &&
          password == Constants.adminPassword;
    }

    if (username != storedUsername) return false;
    return _hash(salt, password) == hash;
  }

  static String _hash(String salt, String password) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
