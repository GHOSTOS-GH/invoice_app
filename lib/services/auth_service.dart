// lib/services/auth_service.dart
// Gestion de l'authentification admin avec persistance journalière

import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class AuthService {
  static const String _lastLoginDateKey = Constants.lastLoginDateKey;

  // Vérifie si l'utilisateur est déjà authentifié aujourd'hui
  Future<bool> isAuthenticatedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final lastLogin = prefs.getString(_lastLoginDateKey);
    if (lastLogin == null) return false;

    final today = DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
    return lastLogin == today;
  }

  // Tente de se connecter avec les identifiants admin (constants)
  Future<bool> login(String username, String password) async {
    if (username == Constants.adminUsername && password == Constants.adminPassword) {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      await prefs.setString(_lastLoginDateKey, today);
      return true;
    }
    return false;
  }

  // Déconnexion manuelle (optionnelle)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastLoginDateKey);
  }
}