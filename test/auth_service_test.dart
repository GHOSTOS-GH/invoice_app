// test/auth_service_test.dart
// Identifiants admin : défaut, personnalisation et validation.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:invoice_app/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('les identifiants par défaut Admin / 0000 fonctionnent', () async {
    final auth = AuthService();
    expect(await auth.login('Admin', '0000'), isTrue);
    expect(await auth.login('Admin', '1234'), isFalse);
    expect(await auth.login('admin', '0000'), isFalse);
  });

  test('le changement d’identifiants fonctionne et l’ancien code est refusé',
      () async {
    final auth = AuthService();
    final result = await auth.changeCredentials(
      currentPassword: '0000',
      newUsername: 'Boutique',
      newPassword: '1234',
    );
    expect(result, CredentialChangeResult.success);

    expect(await auth.login('Admin', '0000'), isFalse);
    expect(await auth.login('Boutique', '0000'), isFalse);
    expect(await auth.login('Boutique', '1234'), isTrue);
  });

  test('le code n’est jamais stocké en clair', () async {
    final auth = AuthService();
    await auth.changeCredentials(
      currentPassword: '0000',
      newUsername: 'Boutique',
      newPassword: 'secret42',
    );

    final prefs = await SharedPreferences.getInstance();
    final values = prefs
        .getKeys()
        .map((key) => prefs.get(key).toString())
        .toList();
    expect(values.any((value) => value.contains('secret42')), isFalse);
    expect(values.any((value) => value == '0000'), isFalse);
  });

  test('un code actuel faux est refusé', () async {
    final auth = AuthService();
    final result = await auth.changeCredentials(
      currentPassword: '9999',
      newUsername: 'Boutique',
      newPassword: '1234',
    );
    expect(result, CredentialChangeResult.wrongCurrentPassword);
    // Les identifiants par défaut restent valides.
    expect(await auth.login('Admin', '0000'), isTrue);
  });

  test('un format invalide est refusé', () async {
    final auth = AuthService();

    expect(
      await auth.changeCredentials(
        currentPassword: '0000',
        newUsername: 'ab',
        newPassword: '1234',
      ),
      CredentialChangeResult.invalidFormat,
    );
    expect(
      await auth.changeCredentials(
        currentPassword: '0000',
        newUsername: ' Boutique',
        newPassword: '1234',
      ),
      CredentialChangeResult.invalidFormat,
    );
    expect(
      await auth.changeCredentials(
        currentPassword: '0000',
        newUsername: 'Boutique',
        newPassword: '123',
      ),
      CredentialChangeResult.invalidFormat,
    );
    expect(
      await auth.changeCredentials(
        currentPassword: '0000',
        newUsername: 'Boutique',
        newPassword: '1234567890123',
      ),
      CredentialChangeResult.invalidFormat,
    );
  });

  test('logout efface la session du jour', () async {
    final auth = AuthService();
    await auth.login('Admin', '0000');
    expect(await auth.isAuthenticatedToday(), isTrue);

    await auth.logout();
    expect(await auth.isAuthenticatedToday(), isFalse);
  });
}
