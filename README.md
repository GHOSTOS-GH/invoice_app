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
- **Bibliothèque produits** : ajout/modification avec photo compressée automatiquement et catégories
- Onglet **Sauvegarde** : export CSV, sauvegarde JSON et restauration (voir section dédiée)

## 🎨 Design & Expérience utilisateur

- **Material Design 3** moderne : cartes arrondies avec bordures douces, ombres subtiles, gradients
- **Application entièrement en français** (sélecteurs de dates, dialogues, tooltips) via `flutter_localizations`
- Palette cohérente :
  - Bleu primaire : `#2563EB`
  - Gris neutres : `#0F172A`, `#64748B`, `#94A3B8`
  - Fonds clairs : `#F8FAFC`
- Typographie renforcée, espacements généreux, transitions de pages fluides
- **4 onglets** : 🧾 Facture, 📜 Historique, 📊 Stats, ⚙️ Paramètres
- Onglet **Paramètres** organisé en 4 sous-onglets : Clients, Hist. articles, Produits, Sauvegarde
- Écrans de chargement en *skeleton* pour un rendu soigné

## 🏗️ Structure du projet

```
lib/
├── main.dart                          # Point d'entrée, thème et navigation
├── models/
│   ├── invoice.dart                   # Invoice, InvoiceItem, InvoiceStatus
│   └── product.dart                   # Produit de la bibliothèque
├── services/
│   ├── storage_service.dart           # Persistance + prix historiques par client
│   ├── history_service.dart           # Autocomplétion clients/articles
│   ├── product_service.dart           # Bibliothèque produits
│   ├── pdf_service.dart               # Génération PDF/PNG/JPG + filigrane
│   ├── backup_service.dart            # Export CSV + sauvegarde/restauration JSON
│   └── auth_service.dart              # Authentification journalière
├── screens/
│   ├── new_invoice_screen.dart        # Création de facture
│   ├── history_screen.dart            # Historique + filtres + période
│   ├── invoice_detail_screen.dart     # Détails et édition
│   ├── stats_screen.dart              # Statistiques
│   ├── settings_screen.dart           # Paramètres (clients, articles, produits, sauvegarde)
│   └── login_screen.dart              # Connexion admin
├── utils/
│   ├── constants.dart                 # Clés, identifiants, tailles
│   └── formatters.dart                # Formatage FCFA
└── widgets/
    ├── last_price_hint.dart           # Encart « dernier prix par client »
    ├── product_grid_sheet.dart        # Grille de sélection de produits
    ├── product_form_dialog.dart       # Formulaire produit (photo)
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

## 🚧 Améliorations futures possibles

- Mode sombre 🌙
- Numérotation automatique des factures (ex : FAC-2026-001)
- Fiche client détaillée (adresse, téléphone, historique)
- Impression directe
- Multi-devises

## 📄 Licence

Ce projet est fourni à titre éducatif et de démonstration.

## 👨‍💻 Auteur

Développé avec ❤️ en utilisant Flutter et Dart

---

**Note** : l'application est **100 % fonctionnelle** et prête à l'emploi. Il suffit d'exécuter `flutter pub get` puis `flutter run`.
