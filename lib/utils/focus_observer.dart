// lib/utils/focus_observer.dart
// Retire le focus clavier à chaque changement de page : sans cela, le clavier
// peut se rouvrir tout seul au retour d'un détail, l'ancien champ ayant gardé
// son focus. Les routes popup (feuilles, dialogues, sélecteurs de date) sont
// ignorées : elles doivent garder leur focus.

import 'package:flutter/widgets.dart';

/// Défocalise le champ actif quand une page plein écran est poussée, retirée
/// ou remplacée.
class UnfocusNavigatorObserver extends NavigatorObserver {
  UnfocusNavigatorObserver();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _unfocusFor(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _unfocusFor(route);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _unfocusFor(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void _unfocusFor(Route<dynamic>? route) {
    // Une feuille ou un dialogue (PopupRoute) n'est pas une PageRoute : son
    // focus reste intact.
    if (route is! PageRoute) return;
    // Après la frame : le Navigator restaure d'abord le focus de la route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }
}
