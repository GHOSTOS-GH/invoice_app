# Dépendances et build release

Étape P6 (branche `refonte/p6-recette`) — état au 2026-10-28.

## Dépendances de production

Aucune dépendance n'a été ajoutée pendant la refonte. Versions résolues
(`pubspec.lock`) :

| Paquet | Version | Usage |
|---|---|---|
| `flutter` / `flutter_localizations` | SDK | Framework + interface en français |
| `intl` | 0.20.x | Dates et nombres (`fr_FR`) |
| `shared_preferences` | 2.x | Stockage local (clés historiques conservées) |
| `pdf` | 3.10.x | Moteur unique du document (`pw.MultiPage`) |
| `printing` | 5.12.x | Rastérisation PDF → pixels pour PNG / JPG |
| `share_plus` | 7.x | Partage natif (WhatsApp, etc.) |
| `path_provider` | 2.x | Dossiers documents / temporaires |
| `file_picker` | 10.3.10 | Sélection du fichier de sauvegarde |
| `image_picker` | 1.2.1 | Photos produits et logo |
| `image` | 4.7.2 | Compression / redimensionnement / monochrome (isolates) |
| `fl_chart` | 0.66.2 | Graphiques des statistiques |
| `esc_pos_utils_plus` | 2.0.4 | Commandes ESC/POS du reçu |
| `blue_thermal_printer` | 1.2.3 | Impression Bluetooth (Android) |
| `qr_flutter` | 4.1.0 | QR code du reçu |
| `permission_handler` | 13.0.1 | Permissions runtime Android 12+ |
| `crypto` | 3.0.7 | Hachage SHA-256 du code admin |

Dépendances de développement : `flutter_test`, `flutter_lints` 3.0.2,
`flutter_launcher_icons` 0.13.1.

## Build release

### Environnement

```
Flutter 3.44.0 • channel stable • Dart 3.12.0
Compiler SDK Android : 36
Gradle 8.14 (wrapper) • AGP/Kotlin fournis par le projet
JDK utilisé : C:/Program Files/Java/jdk-24 (JDK 24)
```

### Tentative 1 — JDK 25 (Android Studio) : échec

Commande exécutée :

```bash
flutter build apk --release
```

Le build s'arrête pendant `assembleRelease`, avec pour toute explication le
numéro de version du JDK :

```
FAILURE: Build failed with an exception.

* What went wrong:
25.0.2

* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.

BUILD FAILED in 23s
```

Cause : le JDK 25 d'Android Studio (`C:/Program Files/Android/Android Studio/jbr`)
n'est pas supporté par la chaîne Gradle/AGP du projet ; le plugin se contente
d'afficher la version Java détectée (`25.0.2`) comme message d'erreur.

### Résolution

```bash
JAVA_HOME="C:/Program Files/Java/jdk-24" flutter build apk --release
```

Insuffisant à lui seul : Flutter reprenait le JDK d'Android Studio. Il faut
fixer le JDK au niveau de Flutter (réglage persistant, projets locaux
uniquement) :

```bash
flutter config --jdk-dir "C:/Program Files/Java/jdk-24"
flutter build apk --release
```

### Résultat

| | |
|---|---|
| Commande | `flutter build apk --release` (après `flutter config --jdk-dir`) |
| Résultat | **succès** |
| Sortie | `√ Built build\app\outputs\flutter-apk\app-release.apk` |
| Durée Gradle | `assembleRelease` ≈ 1 377 s (première compilation complète, caches froids) |
| Taille | 66 120 447 octets (63,1 Mo) |
| SHA-256 | `7c781033e26c82acc932439b91970af5487f4c76ce0d32435f7fcc0e2ea922c9` |

Aucune modification n'a été apportée à `applicationId`, à la configuration de
signature, au bloc d'impression ni au manifest.

## Build release — Avertissements

Avertissements relevés lors du build réussi. **Aucun n'est bloquant** ; ils
sont laissés en l'état (les corriger supposerait de changer `compileSdk`, le
système de build Kotlin ou des versions de plugins, hors périmètre de la
recette).

### 1. Accès natif restreint (JDK 24 / Gradle 8.14)

```
WARNING: A restricted method in java.lang.System has been called
WARNING: java.lang.System::load has been called by net.rubygrapefruit.platform.internal.NativeLibraryLoader in an unnamed module (.../gradle-8.14/lib/native-platform-0.22-milestone-28.jar)
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning for callers in this module
WARNING: Restricted methods will be blocked in a future release unless native access is enabled
```

### 2. `compileSdk` 36 < SDK requis par un plugin

```
Warning: The plugin permission_handler_android requires Android SDK version 37 or higher.
Your project is configured to compile against Android SDK 36, but the following plugin(s) require to be compiled against a higher Android SDK version:
- permission_handler_android compiles against Android SDK 37
Fix this issue by compiling against the highest Android SDK version (they are backward compatible).
Add the following to android/app/build.gradle.kts:

    android {
        compileSdk = 37
        ...
    }
```

Non corrigé volontairement : `compileSdk` touche à la configuration Android du
projet. À faire dans une étape dédiée (le build passe malgré le message).

### 3. Kotlin Gradle Plugin (KGP) / Built-in Kotlin

```
WARNING: Your Android app project: app applies the Kotlin Gradle Plugin, which will cause build failures in future versions of Flutter.
Please migrate your app to Built-in Kotlin (.../migrate-to-built-in-kotlin/...)

WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): file_picker, share_plus, shared_preferences_android
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
```

Dépend de versions futures de Flutter et de trois plugins : aucune action
possible côté application sans montée de version des paquets (interdite par
les règles du projet).

### 4. Mélange d'outils SDK

```
Warning: SDK processing. This version only understands SDK XML versions up to 3 but an SDK XML file of version 4 was encountered. This can happen if you use versions of Android Studio and the command-line tools that were released at different times.
```

### 5. Compilation Java des plugins (`source` / `target` 8)

```
warning: [options] source value 8 is obsolete and will be removed in a future release
warning: [options] target value 8 is obsolete and will be removed in a future release
warning: [options] To suppress warnings about obsolete options, use -Xlint:-options.
3 warnings
```

Répété pour chaque module de plugin compilé en Java 8 (dont
`blue_thermal_printer`). Le code source des plugins n'est pas dans le projet.

### 6. API dépréciée dans `blue_thermal_printer`

```
Note: .../blue_thermal_printer-1.2.3/android/src/main/java/id/kakzaki/blue_thermal_printer/BlueThermalPrinterPlugin.java uses or overrides a deprecated API.
Note: Recompile with -Xlint:deprecation for details.
```

Avertissement de compilation du plugin, pas du code de l'application.

### 7. Fontes réduites (tree-shaking)

```
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 16752 bytes (99.0% reduction).
```

Informatif : comportement normal du build release.

### Absence de ligne `w:` (Kotlin)

Aucune ligne `w:` (avertissement du compilateur Kotlin) n'a été émise : le
code Kotlin du projet (`MainActivity`) et des plugins se compile sans
avertissement.

## Remarque sur l'environnement de build

Le `flutter build apk --release` a dû être relancé plusieurs fois : les
tentatives interrompues laissent des démons Gradle qui se bloquent mutuellement
sur le verrou de `~/.gradle`. En cas de blocage silencieux après l'étape
« Font asset tree-shaken », arrêter les processus `flutter` et `java` du JDK 24
puis relancer une seule fois. Ce n'est pas un défaut de l'application.
