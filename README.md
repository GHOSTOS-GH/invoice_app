# 📱 Application Flutter de Gestion de Factures

Une application mobile moderne et élégante pour créer, gérer, suivre et partager vos factures, développée avec Flutter et Dart.

## 📌 Règles du projet

Les règles permanentes (stockage, montants, impression, qualité de code) sont
consignées dans [`CLAUDE.md`](CLAUDE.md) — copie identique dans [`AGENTS.md`](AGENTS.md).
Elles s'appliquent à toute évolution du projet.

Points clés :

- **Montants FCFA : toujours des entiers (`int`).** Aucun décimal dans les calculs, la
  saisie, l'affichage ou les exports ; les arrondis se font avec `.round()`.
  Seule exception : `taxRate` (pourcentage).
- **Un seul total de référence :** `Invoice.payableTotal`
  (= sous-total − remise appliquée + TVA). Il est utilisé dans les écrans,
  l'historique, les statistiques, le PDF, le reçu thermique et le CSV.
- **Rétro-compatibilité obligatoire** : les anciens JSON (prix `99.99`, remise `10.5`…)
  restent lisibles et sont arrondis au chargement.
- **Clés `SharedPreferences` figées** : `invoices`, `draft_invoice`, `last_login_date`,
  `receipt_settings`, `default_printer_mac`, `default_printer_ip`,
  `history_client_names`, `history_product_names`, `products`.
- **Interdits** : changer l'`applicationId`, la signature, la logique d'impression
  Bluetooth/Wi-Fi et les permissions du manifest.

L'état de référence du projet (versions, `flutter analyze`, `flutter test`) est dans
[`docs/BASELINE.md`](docs/BASELINE.md).

## ✨ Fonctionnalités

### 🧭 Vue d'ensemble de la refonte
- **Montants en FCFA entiers** : aucun décimal dans les calculs, l'affichage et les exports (arrondi `.round()`)
- **Réglages PDF et images** : logo, infos boutique, éléments affichés, style (3 modèles), couleur d'accent, format image (A4 / long WhatsApp), QR code, filigrane, pied de page — tous activables/désactivables dans Paramètres → Facture (PDF & images)
- **Mode sombre** : Système / Clair / Sombre, réglable dans Paramètres → Apparence
- **Sécurité** : identifiant et code modifiables dans l'application, stockage haché (sel + SHA-256)
- **Sauvegarde v2** : inclut les images produits (base64) et les réglages de facture ; rétro-compatible avec les sauvegardes v1
- **Refonte UI/UX complète** : design system Inter, thème Material 3 clair/sombre, widgets harmonisés, tous les écrans revus

### 🆕 Création de facture
- Nom du client avec **autocomplétion** basée sur l'historique
- Ajout illimité d'articles depuis la **bibliothèque produits** (photos, catégories)
- Quantité **obligatoire** et prix unitaire en **entiers FCFA** (clavier numérique, chiffres uniquement) : **prix vide = 1 FCFA par défaut (choix utilisateur)**, modifiable ensuite ; la quantité vide ou nulle affiche l'erreur sous le champ et n'ajoute pas l'article
- **Prix intelligent par client** : le dernier prix vendu à ce client précis est pré-rempli automatiquement et affiché dans un encart contextuel (les prix peuvent varier selon les clients)
- Brouillon automatique : la facture en cours est sauvegardée même si on quitte l'application
- Total à payer (`payableTotal`) et compteur d'articles mis à jour en temps réel
- Finalisation en un clic

### 📝 Édition des factures (détails)
- Modification du client, du **statut** (dropdown), des **notes**, de la **remise** (FCFA) et de la **TVA** (%) — toutes deux en entiers ; une remise supérieure au sous-total est refusée avec un message sous le champ
- **Détail du total** (sous-total, remise, TVA) affiché uniquement si une remise ou une TVA est renseignée, puis **TOTAL À PAYER**
- **Ajout d'articles via la bibliothèque produits** (pas de saisie manuelle, même prix intelligent par client, mêmes règles de saisie entière)
- Édition/suppression d'articles **sans mélange des valeurs**, même après plusieurs suppressions
- Duplication de facture, archivage/désarchivage, suppression
- Partage direct : PDF, PNG ou JPG

### 📚 Historique complet
- **Filtre par période de dates** (ex : factures du 10 février au 11 février) via un sélecteur de période
- Filtres par statut : 🔴 En cours, 🟡 En livraison, 🟢 Livrée, ⚪ Archivée
- Recherche textuelle (client, article, notes, n°)
- Tri par date, montant, client ou statut
- Sélection multiple : **export groupé** et suppression groupée
- **Export CSV de la sélection filtrée** (période, statut, recherche) avec total affiché par période
- Glissement latéral pour faire avancer/reculer le statut d'une facture
- Détails complets au clic

### 📊 Statistiques repensées
- Sélecteur de période : **7 jours / 30 jours / Tout**
- Carte héros « Chiffre d'affaires » + 4 KPI (factures, panier moyen, articles vendus, plus grosse facture)
- **Évolution du chiffre d'affaires** (quotidien ou mensuel selon la période)
- **Répartition par statut** (donut + légende avec pourcentages)
- **Top 5 clients** et **Top 5 produits** avec barres de progression
- Actualisation par glissement

### 📄 Export professionnel (PDF / PNG / JPG)
- Document PDF au design moderne (en-tête, tableau, total en dégradé, notes, pied de page)
- **Bloc total** : sous-total, remise, TVA et **TOTAL À PAYER** quand une remise ou une TVA existe ; sinon un simple `TOTAL`, comme avant
- **Filigrane du logo** (assets/watermark/logo.png) sur toutes les factures générées
- Export en image PNG ou JPG (idéal pour WhatsApp), en qualité **Standard (150 dpi)**, **Haute (200 dpi, par défaut)** ou **Ultra (300 dpi)**, avec qualité JPG réglable de 70 à 98
- **Garde-fou mémoire** : une page qui dépasserait 24 Mpx est générée en 200 dpi pour cette image, sans modifier le réglage
- Astuce affichée dans l'application : pour une netteté parfaite sur WhatsApp, envoyer le PDF ou joindre l'image comme Document (WhatsApp recompresse les photos)
- Partage natif direct depuis l'application
- **Export groupé** : les factures sélectionnées sont générées puis partagées en **un seul partage natif** (liste de PDF), au lieu d'ouvrir le partage une fois par facture

### 🖨️ Reçu thermique & impression (Bluetooth / Wi-Fi)
- **Aperçu temps réel** : le ticket thermique est simulé à l'écran et se met à jour instantanément quand les paramètres changent (rendu identique à l'impression)
- **Paramètres du reçu** : informations boutique (nom, adresse, téléphone, NINEA/RC), caissier, message pied de page, logo monochrome et **format du papier 58 mm / 80 mm**
- Éléments affichables / masquables : logo, en-tête, adresse, téléphone, NINEA, pied de page et **QR code de la facture**
- **Impression Bluetooth** (Android) : liste des appareils appairés, **connexion robuste** (déconnexion préalable si un socket existe déjà, reprise automatique sur socket résiduel « already connected », re-vérification après court délai), mémorisation de l'imprimante par défaut
- **Impression Wi-Fi** (Android + iPhone) : adresse IP de l'imprimante (port 9100) avec test de connexion
- Envoi ESC/POS fiabilisé : **permissions runtime Android 12+** (BLUETOOTH_SCAN / BLUETOOTH_CONNECT), **envoi par chunks de 512 octets** (adapté aux petits buffers Bluetooth), **timeout de 15 s** si l'imprimante ne répond pas, et **libération de la connexion** après chaque impression
- **Tableau des articles sans débordement** : règles métier **fixes** et identiques sur les deux formats de papier — nom d'article **10 caractères max**, quantité **4 caractères max** (« x » inclus, couvre « x999 »), prix de ligne **8 caractères max** (espaces inclus) ; le nom est wrappé proprement et le prix compacté/tronqué via `_fitPrice`, et les mêmes 8 caractères s'appliquent aux montants des totaux (SOUS-TOTAL, TOTAL À PAYER). L'espace restant du papier (surtout en 80 mm) devient de la marge : les colonnes ne sont jamais agrandies

### 🔐 Sécurité & accès
- Écran de connexion administrateur (connexion requise une fois par jour)
- Identifiants par défaut : `Admin` / `0000` (modifiables dans `lib/utils/constants.dart`)

### 💾 Sauvegarde & export des données
- **Export CSV** : toutes les factures (une ligne par article), séparateur `;` compatible Excel FR et BOM UTF-8 pour les accents ; 13 colonnes dont les totaux de facture et les notes, remplis **uniquement sur la première ligne** de chaque facture pour ne pas fausser les sommes du tableur
- **Sauvegarde complète (JSON)** : factures, produits et historiques d'autocomplétion dans un seul fichier
- **Restauration** : sélection d'un fichier `.json`, aperçu du contenu (factures, produits, clients) avec confirmation avant remplacement
- **Export CSV de la sélection filtrée** directement dans l'historique (période + statut + recherche combinés), avec total affiché par période

### ⚙️ Paramètres
- Gestion des clients enregistrés (renommer, supprimer, vider)
- Historique des articles
- **Bibliothèque produits** : ajout/modification avec photo compressée automatiquement et catégories — la compression (redimensionnement + encodage JPEG) est déportée sur un **isolate via `compute()`** pour ne jamais bloquer le thread UI
- Onglet **Sauvegarde** : export CSV, sauvegarde JSON et restauration (voir section dédiée)
- Onglet **Reçu** : personnalisation du ticket thermique (boutique, logo, format 58/80 mm, éléments affichés) et configuration des imprimantes Bluetooth / Wi-Fi

## 🎨 Design & Expérience utilisateur

- **Material Design 3** moderne : cartes arrondies avec bordures douces, ombres subtiles, gradients
- **Application entièrement en français** (sélecteurs de dates, dialogues, tooltips) via `flutter_localizations`
- Palette cohérente :
  - Bleu primaire : `#2563EB`
  - Gris neutres : `#0F172A`, `#64748B`, `#94A3B8`
  - Fonds clairs : `#F8FAFC`
- Typographie renforcée, espacements généreux, transitions de pages fluides
- **4 onglets** : 🧾 Facture, 📜 Historique, 📊 Stats, ⚙️ Paramètres
- Onglet **Paramètres** organisé en 5 sous-onglets : Clients, Hist. articles, Produits, Sauvegarde, Reçu
- Écrans de chargement en *skeleton* pour un rendu soigné

## 🏗️ Structure du projet

```
lib/
├── main.dart                          # Point d'entrée, thème et navigation
├── models/
│   ├── invoice.dart                   # Invoice, InvoiceItem, InvoiceStatus (+ payableTotal)
│   ├── product.dart                   # Produit de la bibliothèque
│   ├── document_settings.dart         # Réglages PDF / images (logo, éléments, style, QR…)
│   └── receipt_settings.dart          # Paramètres du reçu thermique (ESC/POS)
├── theme/                             # Design system : couleurs, typo, espacements, rayons, thème
│   ├── app_colors.dart                # Jetons de couleur clair / sombre
│   ├── app_typography.dart            # Échelle typographique Inter
│   ├── app_spacing.dart               # Espacements
│   ├── app_radius.dart                # Rayons
│   ├── app_theme.dart                 # ThemeData Material 3 clair / sombre
│   └── theme_controller.dart          # Système / Clair / Sombre (persisté)
├── services/
│   ├── invoice_repository.dart        # Source de données unique en mémoire (factures)
│   ├── client_price_index.dart        # Index des derniers prix par client
│   ├── document_settings_service.dart # Persistance des réglages PDF et images
│   ├── invoice_image_service.dart     # Rastérisation PDF → PNG / JPG (isolates)
│   ├── product_image_store.dart       # Stockage durable des photos produits + migration
│   ├── storage_service.dart           # Persistance + prix historiques par client
│   ├── history_service.dart           # Autocomplétion clients/articles
│   ├── product_service.dart           # Bibliothèque produits
│   ├── pdf/                           # Moteur PDF
│   │   ├── invoice_pdf_builder.dart   # InvoicePdfBuilder (MultiPage, 3 modèles)
│   │   ├── pdf_assets.dart            # PdfAssets (polices, logo)
│   │   └── pdf_palette.dart           # PdfPalette (couleur d'accent)
│   ├── pdf_service.dart               # Façade PDF / images + partage
│   ├── backup_service.dart            # Export CSV + sauvegarde/restauration JSON (v2)
│   ├── auth_service.dart              # Authentification journalière (code haché)
│   ├── receipt_builder.dart           # Construction du reçu ESC/POS (même plan pour l'aperçu, tableau à règles métier fixes : nom 10 / qté 4 / prix 8, identiques en 58 et 80 mm)
│   ├── receipt_printer_common.dart    # Préparation commune des octets ESC/POS
│   ├── receipt_settings_service.dart  # Persistance des paramètres du reçu + imprimante par défaut
│   ├── bluetooth_printer_service.dart # Impression Bluetooth (Android) : permissions, connexion robuste (connectSafely), chunks, timeout
│   └── network_printer_service.dart   # Impression Wi-Fi (socket TCP port 9100)
├── screens/
│   ├── new_invoice_screen.dart        # Création de facture
│   ├── history_screen.dart            # Historique + filtres + période
│   ├── invoice_detail_screen.dart     # Détails et édition
│   ├── share_invoice_screen.dart      # Aperçu et partage PDF / PNG / JPG
│   ├── receipt_preview_screen.dart    # Aperçu du reçu + envoi Bluetooth / Wi-Fi
│   ├── stats_screen.dart              # Statistiques
│   ├── settings_screen.dart           # Paramètres (catalogue, facturation, impression, données, application)
│   ├── settings/                      # Sous-pages des paramètres
│   │   ├── appearance_page.dart       # Thème Système / Clair / Sombre
│   │   ├── backup_page.dart           # Export CSV, sauvegarde / restauration JSON
│   │   ├── document_page.dart         # Facture (PDF & images)
│   │   ├── name_history_page.dart     # Clients / historique des articles
│   │   ├── products_page.dart         # Bibliothèque produits
│   │   ├── receipt_page.dart          # Reçu thermique
│   │   └── security_page.dart         # Identifiant, code, déconnexion
│   └── login_screen.dart              # Connexion admin
├── utils/
│   ├── constants.dart                 # Clés, identifiants, tailles
│   └── formatters.dart                # formatNumber / formatCurrency (entiers, insécable par défaut)
└── widgets/
    ├── ui/                            # Widgets réutilisables du design system
    │   ├── app_card.dart              # AppCard
    │   ├── status_badge.dart          # StatusBadge
    │   ├── amount_text.dart           # AmountText
    │   ├── app_text_field.dart        # AppTextField
    │   ├── app_sheet.dart             # AppSheet
    │   ├── app_snack.dart             # AppSnack
    │   ├── choice_tile.dart / section_header.dart / sheet_handle.dart
    │   ├── client_avatar.dart / empty_state.dart
    │   ├── quantity_stepper.dart / status_stepper.dart
    │   └── sticky_total_bar.dart
    ├── last_price_hint.dart           # Encart « dernier prix par client »
    ├── product_grid_sheet.dart        # Grille de sélection de produits
    ├── product_form_dialog.dart       # Formulaire produit (photo)
    ├── receipt_preview.dart           # Rendu du ticket thermique à l'écran
    ├── receipt_settings_tab.dart      # Onglet « Reçu » des paramètres
    ├── bluetooth_device_sheet.dart    # Sélection / connexion imprimante Bluetooth
    ├── network_printer_sheet.dart     # Configuration imprimante Wi-Fi (IP + test)
    └── skeleton_loader.dart           # Squelettes de chargement
```

## 📦 Dépendances

- **flutter** : Framework UI
- **flutter_localizations** : Interface en français
- **shared_preferences** : Stockage local persistant
- **intl** : Formatage des dates et nombres en français
- **pdf** + **printing** : Génération PDF et rasterisation PNG
- **share_plus** : Partage natif des fichiers
- **path_provider** : Dossier temporaire pour les exports
- **file_picker** : Sélection d'un fichier de sauvegarde pour la restauration
- **image_picker** + **image** : Photos produits compressées
- **fl_chart** : Graphiques statistiques
- **blue_thermal_printer** : Impression Bluetooth ESC/POS (Android)
- **esc_pos_utils_plus** : Génération des commandes ESC/POS du reçu
- **permission_handler** : Permissions runtime (Bluetooth Android 12+, etc.)
- **qr_flutter** : QR code de la facture sur le reçu thermique
- **flutter_launcher_icons** : Génération des icônes de lancement

## 🗂️ Étapes de refonte

| Étape | Branche | Contenu |
|---|---|---|
| P0 | `refonte/p0-regles` (tag `pre-refonte`) | Règles permanentes (`CLAUDE.md` / `AGENTS.md`) et état de référence (`docs/BASELINE.md`) |
| P1 | `refonte/p1-argent` | Montants 100 % entiers FCFA, `payableTotal` unifié partout, CSV enrichi, formatters réécrits |

## 🚀 Installation et lancement

### Prérequis
- Flutter SDK 3.0 ou supérieur
- Android Studio / VS Code avec extensions Flutter
- Émulateur Android ou appareil physique

### Étapes

```bash
cd invoice_app
flutter pub get
flutter run
```

## 💾 Stockage des données

L'application utilise **SharedPreferences** pour stocker :
- **Factures** : JSON sérialisé (client, date, statut, notes, articles)
- **Historique clients/articles** : listes pour l'autocomplétion
- **Bibliothèque produits** : avec chemins d'images compressées

Les **prix historiques par client** sont dérivés automatiquement des factures enregistrées : le dernier prix d'un produit vendu à un client donné est retrouvé en parcourant les factures les plus récentes de ce client.

### Format du CSV exporté

Une ligne par article, avec les colonnes suivantes :
`Date;Réf;Client;Statut;Article;Quantité;Prix unitaire;Sous-total article;Sous-total facture;Remise;TVA;Total à payer;Notes`

Les totaux de la facture (sous-total, remise, TVA, total à payer) et les notes ne sont
remplis que sur la **première ligne** de chaque facture, pour que les sommes du tableur
ne comptent pas plusieurs fois le même montant.

### Format de sauvegarde (JSON)

Le fichier de sauvegarde complet contient tout, dans un seul document :

```json
{
  "app": "Gestion de Factures",
  "backupVersion": "2.0",
  "exportedAt": "2026-08-15T10:00:00.000Z",
  "invoices": [],
  "products": [],
  "clientNames": [],
  "productNames": [],
  "productImages": {},
  "documentSettings": "{...}",
  "receiptSettings": "{...}"
}
```

### Structure de stockage de facture

```json
{
  "id": "1707987654321",
  "clientName": "Dupont & Associés",
  "createdAt": "2025-02-15T14:30:00.000Z",
  "status": "enCours",
  "notes": "Livraison rapide demandée",
  "items": [
    {
      "name": "Consulting",
      "quantity": 5,
      "unitPrice": 150
    }
  ]
}
```

## 🧪 Tests

```bash
flutter test
```

- **16 tests de régression d'audit** (`test/audit_regression_test.dart`, points a à n) : total unique, PDF multi-pages, prix vide = 1 FCFA par défaut, stats rafraîchies, saisies non validées conservées, « Annuler » qui restaure tout, suppression d'articles sans mélange, autocomplétion + dernier prix, migration des images produit, restauration v1/v2 + sauvegarde de sécurité, code admin modifiable, `formatNumber`, lecture d'un stockage ancien, défauts sûrs des réglages de facture
- **2 tests de parcours complet E2E** (`test/parcours_complet_test.dart`) : création → détail → remise + TVA → archivage → filtres → CSV → sauvegarde → restauration, et aperçu de partage généré depuis le détail
- **3 tests de focus** (`test/focus_test.dart`) : l'observateur de navigation défocalise à chaque page, et le clavier ne se rouvre ni au retour du détail ni au changement d'onglet
- **10 tests de robustesse** (`test/robustesse_test.dart`) : 1 000 factures, débordements de texte, rotation, très grands montants, etc.
- **Tests existants** : modèles, services, écrans, PDF, legacy storage (`invoice_money_test`, `backup_service_test`, `invoice_repository_test`, `client_price_index_test`, `document_settings_test`, `pdf_document_test`, `receipt_builder_test`, `screens_responsive_test`, `legacy_storage_test`, `widget_test`…)
- **Total : 212 tests, ~3 min**

## 🖨️ Impression thermique (ESC/POS)

Le module d'impression génère **le même ticket thermique** pour le Bluetooth (Android) et le Wi-Fi (Android + iPhone).

### Bluetooth (Android uniquement)

1. Appairez l'imprimante thermique dans les réglages Bluetooth d'Android.
2. Ouvrez **« Aperçu du reçu »** depuis une facture (ou Paramètres → Reçu), puis **« Configurer les imprimantes » → « Imprimante Bluetooth »**.
3. Touchez votre imprimante : elle est connectée et mémorisée comme imprimante par défaut.
4. Appuyez sur **« Bluetooth »** en bas de l'aperçu pour imprimer.

**Permissions Android 12+** : à la première ouverture, l'application demande `BLUETOOTH_SCAN` et `BLUETOOTH_CONNECT` (écran « Appareils à proximité »). Si elles sont refusées, un message invite à les activer depuis les réglages de l'application.

### Wi-Fi (Android + iPhone)

1. Connectez le téléphone / la tablette et l'imprimante au **même réseau Wi-Fi**.
2. Trouvez l'adresse IP de l'imprimante (réglages de l'imprimante ou page de test).
3. Dans **« Configurer les imprimantes » → « Imprimante Wi-Fi »**, saisissez l'IP et validez avec **« Tester la connexion »** (port 9100).

### Fiabilité des envois

- **Connexion robuste (`connectSafely`)** : déconnexion préalable si un socket existe déjà (évite l'erreur native *« already connected »*), réessai automatique après `disconnect()` sur socket résiduel, et re-vérification de la connexion après un court délai (300 ms) avant d'afficher une erreur. Réutilisée par la feuille de sélection et par l'impression de facture.
- Envoi **par chunks de 512 octets** avec une courte pause entre chaque bloc — évite la perte de données sur les modules Bluetooth à petit buffer (notamment pour le logo rastérisé).
- **Timeout de 15 secondes** par écriture : si l'imprimante ne répond pas, message *« L'imprimante ne répond pas, réessayez. »*
- **Déconnexion automatique** après chaque impression (succès comme échec) pour libérer la connexion.
- **Erreurs différenciées** : permission refusée ≠ Bluetooth indisponible / éteint, avec message actionnable à chaque fois.

### Rendu du tableau des articles

- **Règles métier fixes, identiques sur les deux formats** (58 mm / 80 mm) : nom d'article **10 caractères max**, quantité **4 caractères max** (« x » inclus, couvre « x999 »), prix total de ligne **8 caractères max** (espaces inclus). Les cibles sont converties en ratios ESC/POS (grille de 12, somme = 12) cohérents avec l'allocation réelle de l'imprimante, mais les colonnes ne sont **jamais agrandies** : l'espace restant du papier (surtout en 80 mm) devient simplement de la marge / de l'espacement supplémentaire.
- Le nom de l'article est wrappé exactement à 10 caractères et le prix est **compacté puis tronqué proprement** (`_fitPrice` : espaces de milliers retirés, puis troncature en dernier recours) s'il dépasse — aucun texte ne déborde du bord du ticket, quel que soit le format.
- **Les montants des totaux** (SOUS-TOTAL, REMISE, TVA, TOTAL À PAYER) respectent la même limite de **8 caractères max** (espaces inclus) via `_fitPrice`, comme les prix de ligne des articles.
- **Sortie imprimée inchangée** : côté ESC/POS, `formatNumber` / `formatCurrency` sont appelés avec `sep: ' '` (espace normale) ; l'espace insécable n'est utilisé que pour l'affichage à l'écran. Les octets envoyés à l'imprimante sont donc identiques à ceux d'avant le passage aux montants entiers.

### Permissions Android (AndroidManifest.xml)

- `INTERNET` : sockets TCP vers l'imprimante Wi-Fi (indispensable en build release)
- `BLUETOOTH` / `BLUETOOTH_ADMIN` (≤ Android 11) et `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (Android 12+)
- `ACCESS_FINE_LOCATION` : découverte des appareils Bluetooth (Android ≤ 11)
- `CAMERA`, `READ/WRITE_EXTERNAL_STORAGE` : photos produits et exports

## 🎯 Validation des données

### Champs obligatoires
- **Quantité** : nombre entier positif
- **Prix unitaire** : nombre positif (décimales autorisées)

### Champs optionnels
- Nom du client (défaut : « Client inconnu »), notes, photos produits

### Messages
- SnackBars flottants colorés (vert = succès, rouge = erreur)
- Validation en temps réel

## 🔧 Fonctionnalités techniques

- **État** : StatefulWidget + callbacks parent/enfant pour le rafraîchissement
- **Autocomplétion** : historique limité, suggestions en temps réel
- **Filtrage** : statut + période de dates + recherche combinables
- **Navigation** : `IndexedStack` (état des onglets préservé) + transitions fluides
- **Performance** : `ListView.builder`, chargement asynchrone, skeleton loaders
- **Localisation** : `Locale('fr', 'FR')` avec delegates Material/Widgets/Cupertino

### ⚡ Stabilité & performance

- **Compression des photos produits sur isolate** : le décodage, le redimensionnement et l'encodage JPEG (package `image`) s'exécutent sur un **isolate via `compute()`**, plus jamais sur le thread UI (même approche que le logo du reçu thermique)
- **Gardes `mounted` systématiques** après chaque `await` avant tout `setState()` (sélection de photo, grille produits, chargements) : plus aucune erreur « setState() called after dispose() »
- **Aucune fuite de Ticker** : le `TabController` de la grille produits est disposé à la fermeture (`dispose()`) et **remplacé proprement** (l'ancien est disposé) à chaque rechargement
- **Fichiers temporaires partagés** (CSV, JSON, PDF, PNG, JPG) : la suppression est retardée d'**1 seconde** après le partage pour laisser le temps à l'application destinataire de lire le fichier

## 🚧 Améliorations futures possibles

- Numérotation automatique des factures (ex : FAC-2026-001)
- Fiche client détaillée (adresse, téléphone, historique)
- Multi-devises

## 📄 Licence

Ce projet est fourni à titre éducatif et de démonstration.

## 👨‍💻 Auteur

Développé avec ❤️ en utilisant Flutter et Dart

---

**Note** : l'application est **100 % fonctionnelle** et prête à l'emploi. Il suffit d'exécuter `flutter pub get` puis `flutter run`.
