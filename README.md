# 📱 Application Flutter de Gestion de Factures

Une application mobile moderne et élégante pour créer, gérer, suivre et partager vos factures, développée avec Flutter et Dart.

## ✨ Fonctionnalités

### 🆕 Création de facture
- Nom du client avec **autocomplétion** basée sur l'historique
- Ajout illimité d'articles depuis la **bibliothèque produits** (photos, catégories)
- Quantité (obligatoire) + prix unitaire en FCFA
- **Prix intelligent par client** : le dernier prix vendu à ce client précis est pré-rempli automatiquement et affiché dans un encart contextuel (les prix peuvent varier selon les clients)
- Brouillon automatique : la facture en cours est sauvegardée même si on quitte l'application
- Total à payer et compteur d'articles mis à jour en temps réel
- Finalisation en un clic

### 📝 Édition des factures (détails)
- Modification du client, du **statut** (dropdown) et des **notes**
- **Ajout d'articles via la bibliothèque produits** (pas de saisie manuelle, même prix intelligent par client)
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
- **Filigrane du logo** (assets/watermark/logo.png) sur toutes les factures générées
- Export en image PNG ou JPG (idéal pour WhatsApp)
- Partage natif direct depuis l'application
- **Export groupé** : les factures sélectionnées sont générées puis partagées en **un seul partage natif** (liste de PDF), au lieu d'ouvrir le partage une fois par facture

### 🖨️ Reçu thermique & impression (Bluetooth / Wi-Fi)
- **Aperçu temps réel** : le ticket thermique est simulé à l'écran et se met à jour instantanément quand les paramètres changent (rendu identique à l'impression)
- **Paramètres du reçu** : informations boutique (nom, adresse, téléphone, NINEA/RC), caissier, message pied de page, logo monochrome et **format du papier 58 mm / 80 mm**
- Éléments affichables / masquables : logo, en-tête, adresse, téléphone, NINEA, pied de page et **QR code de la facture**
- **Impression Bluetooth** (Android) : liste des appareils appairés, **connexion robuste** (déconnexion préalable si un socket existe déjà, reprise automatique sur socket résiduel « already connected », re-vérification après court délai), mémorisation de l'imprimante par défaut
- **Impression Wi-Fi** (Android + iPhone) : adresse IP de l'imprimante (port 9100) avec test de connexion
- Envoi ESC/POS fiabilisé : **permissions runtime Android 12+** (BLUETOOTH_SCAN / BLUETOOTH_CONNECT), **envoi par chunks de 512 octets** (adapté aux petits buffers Bluetooth), **timeout de 15 s** si l'imprimante ne répond pas, et **libération de la connexion** après chaque impression
- **Tableau des articles sans débordement** : largeurs des colonnes (nom / quantité / prix) recalculées en caractères selon le format du papier (58 mm / 80 mm) et alignées sur l'allocation réelle de l'imprimante ; nom wrappé et prix tronqué proprement pour ne jamais dépasser le bord du ticket

### 🔐 Sécurité & accès
- Écran de connexion administrateur (connexion requise une fois par jour)
- Identifiants par défaut : `Admin` / `0000` (modifiables dans `lib/utils/constants.dart`)

### 💾 Sauvegarde & export des données
- **Export CSV** : toutes les factures (une ligne par article), séparateur `;` compatible Excel FR et BOM UTF-8 pour les accents
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
│   ├── invoice.dart                   # Invoice, InvoiceItem, InvoiceStatus
│   ├── product.dart                   # Produit de la bibliothèque
│   └── receipt_settings.dart          # Paramètres du reçu thermique (ESC/POS)
├── services/
│   ├── storage_service.dart           # Persistance + prix historiques par client
│   ├── history_service.dart           # Autocomplétion clients/articles
│   ├── product_service.dart           # Bibliothèque produits
│   ├── pdf_service.dart               # Génération PDF/PNG/JPG + filigrane
│   ├── backup_service.dart            # Export CSV + sauvegarde/restauration JSON
│   ├── auth_service.dart              # Authentification journalière
│   ├── receipt_builder.dart           # Construction du reçu ESC/POS (même plan pour l'aperçu, colonnes du tableau calées sur le format 58/80 mm)
│   ├── receipt_printer_common.dart    # Préparation commune des octets ESC/POS
│   ├── receipt_settings_service.dart  # Persistance des paramètres du reçu + imprimante par défaut
│   ├── bluetooth_printer_service.dart # Impression Bluetooth (Android) : permissions, connexion robuste (connectSafely), chunks, timeout
│   └── network_printer_service.dart   # Impression Wi-Fi (socket TCP port 9100)
├── screens/
│   ├── new_invoice_screen.dart        # Création de facture
│   ├── history_screen.dart            # Historique + filtres + période
│   ├── invoice_detail_screen.dart     # Détails et édition
│   ├── receipt_preview_screen.dart    # Aperçu du reçu + envoi Bluetooth / Wi-Fi
│   ├── stats_screen.dart              # Statistiques
│   ├── settings_screen.dart           # Paramètres (clients, articles, produits, sauvegarde, reçu)
│   └── login_screen.dart              # Connexion admin
├── utils/
│   ├── constants.dart                 # Clés, identifiants, tailles
│   └── formatters.dart                # Formatage FCFA
└── widgets/
    ├── last_price_hint.dart           # Encart « dernier prix par client »
    ├── product_grid_sheet.dart        # Grille de sélection de produits
    ├── product_form_dialog.dart       # Formulaire produit (photo)
    ├── receipt_preview.dart           # Rendu du ticket thermique à l'écran
    ├── receipt_settings_tab.dart      # Onglet « Reçu » des paramètres
    ├── bluetooth_device_sheet.dart    # Sélection / connexion imprimante Bluetooth
    ├── network_printer_sheet.dart     # Configuration imprimante Wi-Fi (IP + test)
    ├── skeleton_loader.dart           # Squelettes de chargement
    └── item_form_dialog.dart          # (conservé pour compatibilité)
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
`Date;Réf;Client;Statut;Article;Quantité;Prix unitaire;Sous-total;Total facture;Notes`

### Format de sauvegarde (JSON)

Le fichier de sauvegarde complet contient tout, dans un seul document :

```json
{
  "app": "Gestion de Factures",
  "backupVersion": "1.0",
  "exportedAt": "2026-08-15T10:00:00.000Z",
  "invoices": [],
  "products": [],
  "clientNames": [],
  "productNames": []
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
      "unitPrice": 150.0
    }
  ]
}
```

## 🧪 Tests

```bash
flutter test
```

- `test/widget_test.dart` : test de fumée (connexion admin + navigation entre les 4 onglets)
- `test/backup_service_test.dart` : export CSV (échappement, une ligne par article) et aller-retour sauvegarde → restauration
- `test/receipt_builder_test.dart` : plan du reçu et génération des octets ESC/POS (58 mm / 80 mm), y compris les largeurs de colonnes du tableau (nom long + prix à 6 chiffres sans débordement, prix extrême tronqué)
- `test/receipt_settings_service_test.dart` : persistance des paramètres du reçu et de l'imprimante par défaut

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

- Les largeurs de colonnes (nom / quantité / prix) sont **recalculées en caractères selon le format du papier** (58 mm → 32 caractères, 80 mm → 48 caractères) puis converties en ratios ESC/POS cohérents avec l'allocation réelle de l'imprimante (espacement inter-colonnes pris en compte).
- Le nom de l'article est wrappé exactement à la largeur de sa colonne et le prix est **tronqué proprement** (espaces de milliers retirés, puis troncature) s'il dépasse — aucun texte ne déborde du bord du ticket, quel que soit le format.

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

- Mode sombre 🌙
- Numérotation automatique des factures (ex : FAC-2026-001)
- Fiche client détaillée (adresse, téléphone, historique)
- Multi-devises

## 📄 Licence

Ce projet est fourni à titre éducatif et de démonstration.

## 👨‍💻 Auteur

Développé avec ❤️ en utilisant Flutter et Dart

---

**Note** : l'application est **100 % fonctionnelle** et prête à l'emploi. Il suffit d'exécuter `flutter pub get` puis `flutter run`.
