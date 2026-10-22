# Baseline — état du projet avant la refonte

Étape P0 — règles du projet. **Aucun code applicatif n'a été modifié.**

- Date de la mesure : 2026-10-22
- Branche de départ : `main` (commit `c33eeed` — « Taille edit »)
- Branche de travail : `refonte/p0-regles`
- Tag du commit de départ : `pre-refonte`
- Machine : Windows, exécution locale (aucun appareil physique connecté)

## 1. Environnement

```
Flutter 3.44.0 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 559ffa3f75 (5 months ago) • 2026-05-15 14:13:13 -0700
Engine • hash fcf463a2242790d1fdcd9d044f533080f5022e18 (revision 4c525dac5e) (5 months ago)
Tools • Dart 3.12.0 • DevTools 2.57.0
```

## 2. `flutter pub get`

- Résultat : **succès** — `Got dependencies!`
- Remarque : `66 packages have newer versions incompatible with dependency constraints.`
  (mise à jour non faite : les nouvelles dépendances sont interdites par les règles du projet.)

## 3. `flutter analyze`

- Commande : `flutter analyze`
- Résultat global : **23 problèmes — 23 `info`, 0 `warning`, 0 `error`**
- Code de sortie : `1` (Flutter renvoie un code non nul dès qu'un problème, même `info`, est remonté)
- Message final : `23 issues found. (ran in 53.6s)`

Répartition par règle :

| Règle | Nombre |
|---|---|
| `prefer_const_constructors` | 13 |
| `deprecated_member_use` (`withOpacity`) | 9 |
| `prefer_const_literals_to_create_immutables` | 1 |

Répartition par fichier :

| Fichier | Nombre |
|---|---|
| `lib/services/pdf_service.dart` | 11 |
| `lib/screens/history_screen.dart` | 7 |
| `lib/screens/invoice_detail_screen.dart` | 2 |
| `lib/screens/new_invoice_screen.dart` | 1 |
| `lib/screens/stats_screen.dart` | 1 |
| `lib/widgets/product_form_dialog.dart` | 1 |

Détail :

- `prefer_const_constructors` / `prefer_const_literals_to_create_immutables` :
  `invoice_detail_screen.dart:625`, `stats_screen.dart:441`, `pdf_service.dart:252, 259, 371, 467, 468, 492, 498, 512, 544, 560, 585`,
  `product_form_dialog.dart:202`.
- `deprecated_member_use` (`withOpacity`, à remplacer par `withValues(alpha:)`) :
  `history_screen.dart:581, 592, 603, 614, 797, 869, 887`,
  `invoice_detail_screen.dart:529`, `new_invoice_screen.dart:422`.

Ces 23 points ne sont **pas** corrigés à cette étape (aucune modification de code applicatif).
Ils constituent la dette à résorber pour que chaque étape suivante se termine avec
`flutter analyze` = 0 problème.

## 4. `flutter test`

- Commande : `flutter test`
- Résultat : **`All tests passed!` — 37 tests passés, 0 échec, 0 test ignoré**
- Code de sortie : `0`
- 6 fichiers de test exécutés dans `test/` :
  - `backup_service_test.dart`
  - `receipt_builder_test.dart`
  - `receipt_preview_screen_test.dart`
  - `receipt_settings_service_test.dart`
  - `receipt_settings_test.dart`
  - `widget_test.dart`

Aucun test n'était en échec au départ : il n'y a donc rien à corriger ni à contourner.

## 5. Ce qui n'a pas pu être vérifié

- Tout ce qui exige un vrai appareil : impression Bluetooth, impression Wi-Fi, permissions
  Bluetooth/localisation, rendu réel des PDF/PNG sur un téléphone, comportement de
  `share_plus` et de l'ouverture de fichiers.
- Les tests tournent sur la plateforme de test Flutter (VM) : aucune vérification sur cible
  Android/iOS physique ou émulateur.
- Aucun build de release (`flutter build apk`/`ios`) n'a été lancé à cette étape.
