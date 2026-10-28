# Tests manuels à exécuter sur téléphone

Checklist de recette de la version refondue (`v2.0.0-refonte`).
À dérouler **sur un vrai appareil Android** (les points 1 et 2 valent aussi
pour iPhone en Wi-Fi). Cocher chaque case et noter tout écart.

Préparation :

- installer l'APK release (`flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`) ;
- garder une imprimante thermique 58 mm, idéalement aussi une 80 mm, appairée en Bluetooth ;
- avoir une facture avec remise, TVA, notes et au moins 3 articles ;
- avoir WhatsApp installé.

---

## 1. Impression Bluetooth — reçu thermique (58 mm et 80 mm)

1. [ ] Paramètres → Reçu thermique : laisser le format sur **58 mm**, choisir l'imprimante Bluetooth (elle doit apparaître dans la liste des appareils appairés).
2. [ ] Ouvrir une facture → **Aperçu du reçu** : le ticket affiché à l'écran doit correspondre à ce qui sort.
3. [ ] Imprimer : le ticket sort complet, sans caractère manquant ni ligne coupée.
4. [ ] Vérifier le total imprimé (`TOTAL À PAYER`) : il doit être **identique** à celui de l'écran de détail.
5. [ ] Tableau des articles : nom tronqué/wrappé à 10 caractères, quantité `x4` max, prix 8 caractères max — **aucun débordement du bord du papier**.
6. [ ] Repasser le format en **80 mm** et réimprimer : mêmes règles, l'espace restant doit devenir de la marge (colonnes non agrandies).
7. [ ] Tester avec le **logo** activé puis désactivé, et avec le **QR code** activé puis désactivé.
8. [ ] Refuser la permission Bluetooth (écran « Appareils à proximité ») puis réessayer : le message d'erreur doit être explicite et actionnable.
9. [ ] Éteindre le Bluetooth et imprimer : message « Bluetooth indisponible / éteint », pas de plantage.

> Non vérifiable en test automatique : tout le chemin natif ESC/POS.

---

## 2. Impression réseau Wi-Fi

1. [ ] Téléphone et imprimante sur le **même réseau Wi-Fi**.
2. [ ] Paramètres → Reçu thermique → **Imprimante Wi-Fi** : saisir l'IP, lancer **Tester la connexion** (port 9100).
3. [ ] Imprimer une facture : le rendu doit être **identique** à celui du Bluetooth.
4. [ ] Saisir une IP invalide puis imprimer : message d'erreur clair, pas de blocage de l'application.
5. [ ] Couper le Wi-Fi pendant l'impression : message d'erreur, retour possible à l'application.

> Non vérifiable en test automatique : socket TCP réelle vers l'imprimante.

---

## 3. Partage WhatsApp — PDF, PNG, JPG

1. [ ] Depuis une facture → **Partager** → format **PDF** → WhatsApp : le fichier arrive, s'ouvre, et le total est correct.
2. [ ] Même test en **PNG** : image lisible, texte net, marges correctes.
3. [ ] Même test en **JPG** : comparer la **taille du fichier** et la **qualité** (le JPG doit être plus léger que le PNG, sans être illisible).
4. [ ] Compositeur WhatsApp : la vignette du document s'affiche correctement (pas de page blanche).
5. [ ] Sur un document multi-pages (voir point 9), vérifier que **toutes** les pages arrivent dans le partage.
6. [ ] Vérifier le nom des fichiers partagés (référence de facture lisible).
7. [ ] Refuser l'accès aux photos/fichiers si demandé, puis réessayer : message compréhensible.

> Non vérifiable en test automatique : partage natif, applications destinataires, tailles réelles.

---

## 4. Mise à jour par-dessus l'ancienne version (données existantes)

**À faire avant d'installer la nouvelle version** : sur l'ancienne application,
créer 2–3 factures, 2 produits avec photo, et noter les totaux.

1. [ ] Installer le nouvel APK **sans désinstaller** l'ancien.
2. [ ] Se reconnecter (`Admin` / `0000` si le code n'a jamais été changé).
3. [ ] **Historique** : les factures sont toujours là, avec les mêmes montants et statuts.
4. [ ] **Produits** : les deux produits sont là et **leurs photos s'affichent** (migration des anciennes images).
5. [ ] Ouvrir une ancienne facture : aucune erreur, total inchangé.
6. [ ] Créer une nouvelle facture puis vérifier qu'elle apparaît bien dans l'historique et les stats.

> Point le plus critique de la recette : c'est la seule vérification réelle de
> la rétro-compatibilité du stockage.

---

## 5. Restauration d'une sauvegarde v1 (créée avec l'ANCIENNE version)

1. [ ] Récupérer un fichier de sauvegarde `.json` exporté par l'ancienne version (`"backupVersion": "1.0"`).
2. [ ] Paramètres → Sauvegarde → **Restaurer** → choisir ce fichier.
3. [ ] L'aperçu (nombre de factures, produits, clients) s'affiche **avant** confirmation.
4. [ ] Confirmer : les factures anciennes sont restaurées, les prix décimaux sont arrondis à l'entier le plus proche, aucune facture n'est perdue.
5. [ ] Vérifier qu'un fichier `pre_restore_….json` a bien été créé (dossier de sauvegarde de sécurité de l'application) — sinon, au moins vérifier que la restauration reste réversible en réimportant l'ancien fichier.
6. [ ] Refaire un export immédiatement après : le fichier produit doit être en `"backupVersion": "2.0"`.

> Non vérifiable en test automatique : le sélecteur de fichiers natif.

---

## 6. Changement du code depuis Paramètres → Sécurité

1. [ ] Paramètres → **Sécurité** : saisir le code actuel (`0000`), un nouvel identifiant et un nouveau code (4 à 12 caractères), confirmer.
2. [ ] Message de succès affiché.
3. [ ] Se **déconnecter**.
4. [ ] Se reconnecter avec les **nouveaux** identifiants : succès.
5. [ ] Se reconnecter avec `Admin` / `0000` : **refus**.
6. [ ] Saisir un mauvais code actuel dans la page Sécurité : le changement est refusé, l'ancien code fonctionne toujours.
7. [ ] **Fermer et rouvrir l'application** : les nouveaux identifiants fonctionnent toujours (persistance).

---

## 7. Mode sombre

Paramètres → Apparence : basculer entre **Système / Clair / Sombre**.

Pour chaque écran, vérifier : pas de texte noir sur fond noir, pas de carte
blanche qui « flashe », contrastes corrects, montants lisibles.

1. [ ] **Historique** (liste, filtres, sélection multiple, export CSV).
2. [ ] **Détail** d'une facture (mode lecture et mode édition).
3. [ ] **Stats** (carte chiffre d'affaires, donut, barres Top 5).
4. [ ] **Paramètres** (toutes les sous-pages, y compris Sécurité et Facture (PDF & images)).
5. [ ] Revenir en mode **Système** et changer le réglage sombre d'Android : l'application doit suivre sans redémarrage.

---

## 8. Aperçu PDF avec un logo personnalisé

1. [ ] Paramètres → **Facture (PDF & images)** → Logo → choisir une image dans la galerie.
2. [ ] L'aperçu du logo se met à jour immédiatement.
3. [ ] Ouvrir une facture → **Partager** → PDF : le logo apparaît, net, non déformé, à la bonne place.
4. [ ] Désactiver **Logo** dans les paramètres : le PDF suivant ne doit plus l'afficher.
5. [ ] Faire de même avec le **filigrane** (opacité faible, ne doit pas gêner la lecture).
6. [ ] Tester avec une image très claire et une image très sombre : le logo reste lisible.
7. [ ] Tester les **3 modèles** (Classique / Moderne / Minimal) et 2 couleurs d'accent, puis partager un PDF de chaque : le style doit changer, le contenu rester identique.

---

## 9. Facture à 50 articles

1. [ ] Créer une facture avec **50 articles** (noms longs pour être réaliste).
2. [ ] Le total et le compteur d'articles restent fluides pendant la saisie (pas de saccade).
3. [ ] Partager en **PDF** : le document fait **plusieurs pages**, l'en-tête du tableau se répète, aucun article n'est perdu entre deux pages.
4. [ ] Le bloc `TOTAL À PAYER` ne doit **jamais** être coupé au milieu : il descend en bloc sur la page suivante si nécessaire.
5. [ ] Vérifier le numéro de page en pied de page (si l'option est active).
6. [ ] Partager en **PNG format long** : une seule image continue, marges rognées, texte lisible.
7. [ ] Partager en **PNG format A4** : autant d'images que de pages.
8. [ ] Revenir à l'historique : l'ouverture de cette grosse facture reste fluide.

---

## 10. Sauvegarde JSON v2 (images produit incluses)

1. [ ] Créer au moins un produit **avec photo**.
2. [ ] Paramètres → Sauvegarde → **Exporter** : le fichier JSON doit contenir `"backupVersion": "2.0"`, `"productImages"` et `"documentSettings"`.
3. [ ] Modifier les réglages de facture (par exemple le nom de la boutique ou la couleur d'accent), puis **restaurer** le fichier exporté à l'étape 2.
4. [ ] Les factures, produits, clients **et les photos produits** sont restaurés.
5. [ ] Les réglages de facture sont restaurés à leur valeur du fichier.
6. [ ] Vérifier qu'une sauvegarde de sécurité `pre_restore_` a été créée avant l'écrasement.
7. [ ] Tester la restauration d'un fichier **corrompu** (tronqué) : message d'erreur clair, **données actuelles intactes**.

---

## Ce qu'il faut remonter après la recette

- Version d'Android, modèle du téléphone, marque et format de l'imprimante.
- Pour chaque échec : écran, action exacte, message affiché, capture d'écran.
- Toute différence entre l'aperçu à l'écran et le rendu imprimé.
