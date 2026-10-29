# Changelog de la refonte — points d'audit a) à n)

Branche `refonte/p6-recette`. État final : `flutter analyze` = 0 problème,
`flutter test` = **201 tests verts** (174 s sur la machine de recette).

Pour chaque point : ce qui a été fait, puis ce qui **n'a pas pu être vérifié
sans appareil physique**.

Convention : les tests cités sont dans `test/audit_regression_test.dart`
(sauf mention contraire, chaque point a son test nommé `a)`, `b)`, …).

---

## Retours utilisateur — v2.0.1 (`fix/retours-utilisateur`)

Trois corrections ciblées après la recette. `flutter analyze` = 0 problème,
`flutter test` = **212 tests verts**. Ni l'impression, ni l'`applicationId`,
ni la configuration de signature n'ont été touchés.

### 1. Prix vide = 1 FCFA à l'ajout d'un article

Un prix unitaire **vide ou à 0** vaut **1 FCFA** à l'ajout, et reste
modifiable ensuite ; le champ affiche « Laisser vide = 1 FCFA (à modifier plus
tard) ». La **quantité reste obligatoire**. Même règle sur le panneau d'ajout
du détail en édition ; la validation des lignes existantes (`_EditableItemTile`,
prix > 0 obligatoire) est inchangée.

**Tests.** `c) prix vide = 1 FCFA par défaut` (quantité vide refusée, prix vide
et prix « 0 » acceptés à 1 FCFA) et `ajout sans prix en édition : ligne à
1 FCFA, total recalculé` dans `test/invoice_detail_screen_test.dart`.

### 2. Qualité des images PNG / JPG relevée

`DocumentImageQuality` gagne **Ultra (300 dpi)** ; les défauts passent à
**Haute (200 dpi)** et **JPG 92**, et la borne JPG monte à **70–98** partout
(modèle, service d'images, curseur des paramètres). Migration rétro-compatible
du schéma (`currentVersion` 1 → 2) : un JSON v1 resté aux anciens défauts
(`standard` + `85`) passe à `high` + `92` ; toute autre valeur choisie par
l'utilisateur (Ultra, JPG 90…) est conservée, et un JSON absent ou corrompu
donnes les nouveaux défauts. Un garde-fou mémoire estime les pixels de la page
(largeur × hauteur réelles du format) et retombe à **200 dpi** au-delà de
**24 Mpx**, pour cette génération seulement ; le cache reste indexé par le dpi.

**Mesures (facture de 10 articles, rendu de test sans appareil).**
Haute — 1 654 × 2 339 px : **PNG 459 ms, JPG 465 ms**. Ultra — 2 480 × 3 508 px :
**PNG 1 376 ms, JPG 1 042 ms** (sous les 4 s : l'option est conservée). Ces
durées incluent PDF, rastérisation injectée, composition et encodage ; elles
ne préjugent pas du temps réel sur téléphone.

**Tests.** `test/document_settings_test.dart` : nouveaux défauts, migration v1
(standard/85 → haute/92 ; ultra ou JPG 90 conservés), JSON corrompu → défauts,
aller-retour de sauvegarde v2 avec `imageQuality` / `jpgQuality`.
`test/invoice_image_test.dart` : dpi attendus (200 par défaut, 300 en Ultra),
repli à 200 dpi au-delà de 24 Mpx, cache distinct par dpi, et mesure des durées
PNG / JPG en Haute et en Ultra.

### 3. Clavier qui s'ouvre au retour d'un détail

`UnfocusNavigatorObserver` (`lib/utils/focus_observer.dart`) défocalise le
champ actif après chaque `didPush`, `didPop` et `didReplace` d'une `PageRoute`
(uniquement : les feuilles, dialogues et sélecteurs de date gardent leur
focus). Il est branché sur le `MaterialApp`, le changement d'onglet ferme aussi
le clavier, et l'historique défocalise sa recherche avant d'ouvrir un détail
avec un `FocusNode` dédié (`onTapOutside` pour la fermer au toucher ailleurs).

**Tests.** `test/focus_test.dart` : l'observateur seul (page poussée puis
retirée), le parcours Historique → détail → retour avec la recherche focalisée,
et l'enchaînement complet InvoiceApp Stats → Historique → détail → retour
(frames, sans `pumpAndSettle` sur les écrans à animations continues).

**Non vérifiable sans appareil.** Le comportement réel du clavier Android/iOS
(fermeture visuelle, `resizeToAvoidBottomInset`) et le rendu des images
partagées par WhatsApp.

---

## a) Un seul total de référence

**Fait.** `Invoice.payableTotal` (= sous-total − remise appliquée + TVA) est
désormais le seul montant de référence. Il est lu par l'écran de détail,
l'historique (ligne et total de liste), les statistiques, l'export CSV, le PDF
(`InvoicePdfBuilder`) et le reçu thermique (`ReceiptBuilder`). Plus aucun écran
ne recalcule sa propre addition : les anciens calculs locaux ont été supprimés.

**Tests.** `a) un seul total (payableTotal) cohérent entre détail, historique,
stats, CSV et reçu` vérifie les 7 700 FCFA sur les cinq supports ;
`a) le PDF est produit depuis le même total à payer` vérifie qu'un PDF valide
est produit par le moteur unique.

**Non vérifiable sans appareil.** Le **texte** du PDF n'est pas extractible en
test : les polices embarquées sont sous-ensemblées (glyphes partiels) et
`pdf` compresse les flux par défaut. La cohérence du total est donc couverte
par l'unification du getter `payableTotal` (une seule source) et vérifiée sur
le détail, l'historique, les stats, le CSV et le reçu ; le PDF, lui, n'est
contrôlé que structurellement (signature `%PDF-`, nombre de pages, taille).
Le paramètre `compress` (désactivable) n'est utilisé que par les tests.

---

## b) PDF multi-pages

**Fait.** Le moteur PDF utilise **uniquement `pw.MultiPage`** (plus aucun
`pw.Page`) : le tableau des articles se poursuit sur autant de pages que
nécessaire, l'en-tête complet n'apparaît qu'en première page puis en version
compacte, l'en-tête du tableau se répète à chaque page et le bloc totaux +
notes + paiement + QR est insécable. Le test `b) PDF multi-pages sans
exception (80 articles)` vérifie `pages > 1`.

**Non vérifiable sans appareil.** Le rendu visuel réel (coupure des lignes en
bas de page, logo, filigrane, QR) et l'impression papier du PDF.

---

## c) Prix vide = 1 FCFA par défaut (choix utilisateur)

**Fait.** À l'ajout d'un article, un prix unitaire vide **ou à 0** vaut
**1 FCFA**, modifiable ensuite ; un texte d'aide sous le champ le rappelle
(« Laisser vide = 1 FCFA (à modifier plus tard) »). La **quantité reste
obligatoire** : sans elle, l'article n'est pas ajouté et l'erreur s'affiche
sous le champ. Le même comportement s'applique au panneau d'ajout du détail
en mode édition ; la validation des lignes déjà existantes (prix > 0
obligatoire) ne change pas. Le prix peut varier par client (voir point h)).

**Tests.** `c) prix vide = 1 FCFA par défaut` : quantité vide refusée, prix
vide accepté à 1 FCFA, prix « 0 » accepté à 1 FCFA ; côté détail,
`ajout sans prix en édition : ligne à 1 FCFA, total recalculé`.

**Non vérifiable sans appareil.** Le comportement du clavier numérique natif
Android/iOS (chiffres uniquement).

---

## d) Statistiques rafraîchies après création

**Fait.** Les statistiques lisent le `InvoiceRepository` (source de données
unique en mémoire) et se reconstruisent quand une facture est créée, modifiée
ou supprimée, sans quitter l'écran. Le squelette de chargement a été conservé
pour le premier affichage.

**Tests.** `d) statistiques rafraîchies après création` : l'écran affiche
d'abord l'état vide, une facture est ajoutée au repository, le chiffre
d'affaires apparaît sans navigation.

**Non vérifiable sans appareil.** Aucun point spécifique (test widget).

---

## e) Saisies non validées conservées

**Fait.** En édition, les controllers de quantité / prix / notes ne sont plus
reconstruits à chaque `setState` : supprimer une ligne, en ajouter une ou
changer le statut ne perd plus les valeurs en cours de frappe.

**Tests.** `e) modifications non validées conservées` : quantité `7` et note
saisies, suppression d'une autre ligne, les deux valeurs sont toujours là.

**Non vérifiable sans appareil.** Aucun point spécifique.

---

## f) « Annuler » restaure tout

**Fait.** L'annulation d'une édition restaure **toutes** les valeurs d'origine
(client, notes, remise, TVA, lignes supprimées, quantités) à partir de la
facture enregistrée, et n'écrit rien dans le repository.

**Tests.** `f) Annuler restaure tout` : les trois articles, le client, les
notes et le total de 7 700 FCFA reviennent ; le repository est inchangé.

**Non vérifiable sans appareil.** Aucun point spécifique.

---

## g) Suppression d'articles sans mélange des valeurs

**Fait.** Chaque ligne d'édition est identifiée par une clé stable (id
d'article) : après suppression, les controllers restants gardent leurs propres
valeurs au lieu d'hériter de la ligne suivante.

**Tests.** `g) suppression d'articles sans mélange des valeurs` : suppression
de la ligne du milieu, quantités `2` / `4` et prix `1500` / `500` restent
correctement associés.

**Non vérifiable sans appareil.** Aucun point spécifique.

---

## h) Autocomplétion et dernier prix par client

**Fait.** L'autocomplétion client est branchée sur l'historique
(`history_client_names`) ; choisir une suggestion **fige** le client, ce qui
rend le dernier prix vendu à ce client disponible (`ClientPriceIndex`). Le prix
est pré-rempli et l'encart « Dernier prix pour … » s'affiche. Un nom saisi
librement ne bénéficie pas du prix client (comportement voulu).

**Tests.** `h) autocomplétion et dernier prix par client` : suggestion
`suggérée`, sélection, prix pré-rempli à 1 200 FCFA, encart affiché.

**Non vérifiable sans appareil.** Le rendu de la liste de suggestions sur
petit écran et le comportement du clavier virtuel.

---

## i) Images produit conservées après migration

**Fait.** Les anciennes images produit étaient référencées par un chemin
absolu (cache temporaire, effaçable). Elles sont migrées une fois au démarrage
vers `documents/product_images` par `ProductImageStore.migrateLegacyImages()`,
sous un nom de fichier simple, et l'original n'est jamais supprimé. Le
repository ne stocke plus que ce nom relatif.

**Tests.** `i) images produit conservées après migration` (répertoire
temporaire réel) ; le contenu binaire est identique après migration.

**Non vérifiable sans appareil.** La migration réelle sur le stockage interne
d'un téléphone (permissions, espace disponible) et l'affichage des photos
depuis ce dossier dans l'application.

---

## j) Restauration v1 / v2 et sauvegarde de sécurité

**Fait.** La sauvegarde est passée en **version 2.0** : elle ajoute les images
produit (base64) et les réglages de facture (`documentSettings`), tout en
restant **rétro-compatible** avec les fichiers v1 (aucun champ obligatoire,
arrondi des anciens prix décimaux, ids d'articles générés). Avant tout
remplacement, une copie de sécurité `pre_restore_<horodatage>.json` est
écrite dans `documents/backups` (les 3 dernières sont conservées). Le contenu
est validé champ par champ avant remplacement : un fichier illisible ou
incohérent est rejeté avec un message, sans rien écraser.

**Tests.** `j) restauration v1 et v2 avec sauvegarde de sécurité` : v1 (prix
`99.99` → `100`, ids régénérés), v2 (réglages boutique restaurés), deux
sauvegardes `pre_restore_` présentes.

**Non vérifiable sans appareil.** Le choix de fichier réel via `file_picker`
(arborescence Android/iOS) et l'ouverture du fichier depuis un gestionnaire de
fichiers ou une messagerie.

---

## k) Code admin modifiable

**Fait.** `SecurityPage` (Paramètres → Sécurité) permet de changer l'identifiant
et le code : contrôle du code actuel, longueur minimale, confirmation
identique. Le stockage est **haché** (sel aléatoire + SHA-256, clés
`auth_username` / `auth_salt` / `auth_hash`) ; les identifiants par défaut
`Admin` / `0000` restent les seuls valables tant qu'aucun changement n'a été
fait. La déconnexion puis la reconnexion se font avec les nouveaux
identifiants.

**Tests.** `k) code admin modifiable puis reconnexion` (widget) et
`k) code actuel erroné : changement refusé` (service).

**Non vérifiable sans appareil.** Le clavier réel (masquage des caractères) et
le parcours complet connexion → paramètres → déconnexion sur téléphone.

---

## l) `formatNumber` / `formatCurrency`

**Fait.** Les formatters sont réécrits pour les **entiers FCFA uniquement** :
aucune décimale, séparateur de milliers (insécable par défaut, espace normale
pour l'impression ESC/POS), négatifs et zéro gérés. Aucun appel ne produit de
`,00` ou `.00`.

**Tests.** `l) formatNumber : entiers, séparateurs, négatifs, zéro`.

**Non vérifiable sans appareil.** Aucun point spécifique.

---

## m) Lecture d'un stockage ancien

**Fait.** `Invoice.fromJson` / `Product.fromJson` tolèrent les anciens JSON :
prix et remise décimaux arrondis (`.round()`), ids d'articles absents ou vides
régénérés, statut inconnu ramené à `enCours`, `notes` nulles, chemin d'image
absolu conservé. Les clés `SharedPreferences` existantes n'ont pas été
renommées.

**Tests.** `m) lecture d'un stockage ancien (décimales, sans ids)` +
`test/legacy_storage_test.dart`.

**Non vérifiable sans appareil.** La mise à jour réelle par-dessus l'ancienne
version installée (voir `docs/TESTS-MANUELS.md`, point 4).

---

## n) Réglages de facture : défauts sûrs

**Fait.** `DocumentSettings` (logo, infos boutique, éléments affichés, 3
modèles — Classique / Moderne / Minimal — couleur d'accent, format image
A4 / long WhatsApp, qualité, QR, filigrane, pied de page, numéros de page) a
un **défaut pour chaque champ**. `DocumentSettingsService` renvoie ces défauts
si la clé `document_settings` est absente ou corrompue, et complète un ancien
JSON partiel sans lever d'exception. Tous les éléments du PDF et des images
sont activables/désactivables depuis Paramètres → Facture PDF & images.

**Tests.** `n) réglages de facture : défauts sur JSON absent ou corrompu`
(absent, JSON tronqué, JSON partiel) + `test/document_settings_test.dart` et
`test/document_settings_page_test.dart`.

**Non vérifiable sans appareil.** Le rendu réel du PDF / PNG / JPG avec un
logo personnalisé chargé depuis la galerie (point 8 de
`docs/TESTS-MANUELS.md`), et la lisibilité du QR à l'impression.

---

## Limites connues de la vérification

1. **Texte du PDF** — non extractible en test (glyphes sous-ensemblés, flux
   compressés). Le contenu est couvert indirectement par l'unification de
   `payableTotal` (cf. point a).
2. **Logo du reçu thermique** — les `decodeImage` de
   `lib/services/receipt_builder.dart` (lignes 263 et 348) sont bien dans le
   corps de la méthode `prepareLogo`, mais cette méthode est exécutée via
   `compute` dans le flux normal (isolate) : le comportement est inchangé et
   couvert par le cache de logo. Aucun décodage lourd ne tourne sur le thread
   UI. *(Noté « c) » dans la consigne de recette ; dans la liste a) → n) des
   tests, `c)` correspond au prix vide. Le présent document suit la liste des
   tests.)*
3. **Tout ce qui exige un vrai appareil** : impression Bluetooth (58 / 80 mm),
   impression Wi-Fi, partage WhatsApp, montée de version sur une installation
   existante, restauration d'un fichier v1 réel, permissions runtime, rendu
   réel des PDF et des images. Voir `docs/TESTS-MANUELS.md`.

## Durée et état des vérifications

| Vérification | Résultat |
|---|---|
| `flutter analyze` | 0 problème |
| `flutter test` | 201 tests verts (174 s, ~2 min 54 s) |
| Greps de qualité (`print(`, `withOpacity`, `Color(0x` hors thème, `pw.Page(`) | 0 résultat |
| `dart format` | non modifié : le formateur « tall style » de Dart 3.12 réécrirait 42 fichiers du dépôt, hors périmètre de la recette (voir rapport) |
| `flutter build apk --release` (JDK 24) | voir `docs/DEPENDANCES.md` |
