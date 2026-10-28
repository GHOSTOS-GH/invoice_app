# RÈGLES PERMANENTES DU PROJET

- Stockage : SharedPreferences. Clés existantes à ne JAMAIS renommer ni supprimer : invoices, draft_invoice, last_login_date, receipt_settings, default_printer_mac, default_printer_ip, history_client_names, history_product_names, products. Tout changement de modèle doit continuer à lire l'ancien JSON (rétro-compatibilité obligatoire, avec test sur un JSON ancien).
- Montants FCFA : TOUJOURS des entiers (int). Aucun décimal dans les calculs, la saisie, l'affichage, les exports. Arrondi = `.round()`.
- Les identifiants admin par défaut (Admin / 0000, dans lib/utils/constants.dart) et la génération des ids/références de facture (millisecondsSinceEpoch, référence = 6 derniers chiffres) restent inchangés.
- Interdits : changer `applicationId`, la config de signature, la logique d'impression Bluetooth/Wi-Fi (bluetooth_printer_service, network_printer_service, receipt_printer_common), les permissions Bluetooth/localisation du manifest. Le comportement de receipt_builder reste identique (seules les signatures peuvent s'adapter).
- Tout élément affiché sur les PDF et images de facture doit être activable/désactivable dans les Paramètres.
- Code : null-safety stricte ; `if (!mounted) return;` après chaque await avant setState/context ; dispose de tous les controllers/focus nodes/timers/listeners ; pas de `print` (utiliser debugPrint) ; pas de `withOpacity` (utiliser `withValues(alpha:)`) ; `const` partout où possible ; textes UI en français ; dates en locale fr_FR.
- Nouvelles dépendances : interdites sauf celles explicitement citées dans l'étape en cours.
- Chaque étape se termine par : `flutter analyze` = 0 problème, `flutter test` = tout vert, un commit propre (message en français, impératif), et un rapport final listant : fichiers modifiés, tests ajoutés, ce qui n'a PAS pu être vérifié (tout ce qui exige un vrai appareil).
- En cas d'ambiguïté ou de contradiction avec le code existant : t'arrêter et le signaler plutôt qu'inventer.
