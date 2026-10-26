// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/login_screen.dart';
import 'screens/new_invoice_screen.dart';
import 'screens/history_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings_screen.dart';
import 'services/auth_service.dart';
import 'services/document_settings_service.dart';
import 'services/invoice_repository.dart';
import 'services/product_image_store.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  // Thème choisi par l'utilisateur (Système / Clair / Sombre).
  await ThemeController.instance.load();
  // Dossier durable des images produit + migration des anciens chemins.
  await ProductImageStore.instance.init();
  // Chargement unique de la source de données des factures.
  await InvoiceRepository().load();
  // Réglages du document de facture (PDF & images).
  await DocumentSettingsService.instance.loadSettings();
  runApp(const InvoiceApp());
}

class InvoiceApp extends StatefulWidget {
  const InvoiceApp({super.key});

  @override
  State<InvoiceApp> createState() => _InvoiceAppState();
}

class _InvoiceAppState extends State<InvoiceApp> {
  final ThemeController _themeController = ThemeController.instance;

  @override
  void initState() {
    super.initState();
    _themeController.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _themeController.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gestion de Factures',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeController.value,
      home: const AuthChecker(),
    );
  }
}

class AuthChecker extends StatefulWidget {
  const AuthChecker({super.key});
  @override
  State<AuthChecker> createState() => _AuthCheckerState();
}

class _AuthCheckerState extends State<AuthChecker> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final authenticated = await _authService.isAuthenticatedToday();
    if (!mounted) return;
    setState(() {
      _isAuthenticated = authenticated;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_isAuthenticated) {
      return MainScreen(onLogout: _onLogout);
    } else {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }
  }

  void _onLoginSuccess() => setState(() => _isAuthenticated = true);

  void _onLogout() => setState(() => _isAuthenticated = false);
}

class MainScreen extends StatefulWidget {
  /// Appelé après une déconnexion depuis les paramètres.
  final VoidCallback? onLogout;

  const MainScreen({super.key, this.onLogout});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  void _onInvoiceCreated() {
    setState(() => _currentIndex = 1);
  }

  // Les écrans écoutent le repository : aucun rafraîchissement manuel.
  void _onInvoiceUpdated() {}

  @override
  Widget build(BuildContext context) {
    final screens = [
      NewInvoiceScreen(onInvoiceCreated: _onInvoiceCreated),
      HistoryScreen(onInvoiceUpdated: _onInvoiceUpdated),
      const StatsScreen(),
      SettingsScreen(
        onDataRestored: _onInvoiceUpdated,
        onLogout: widget.onLogout,
      ),
    ];

    return Scaffold(
      body: LazyIndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_outlined),
            selectedIcon: Icon(Icons.receipt),
            label: 'Facture',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Historique',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Stats',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Paramètres',
          ),
        ],
      ),
    );
  }
}

/// IndexedStack paresseux : un onglet n'est construit qu'à sa première visite,
/// puis reste vivant (Offstage + TickerMode) comme avec un IndexedStack.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  /// Un booléen par onglet : vrai dès qu'il a été construit une première fois.
  late List<bool> _built;

  @override
  void initState() {
    super.initState();
    _built = List<bool>.filled(widget.children.length, false);
    _markBuilt(widget.index);
  }

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      final previous = _built;
      _built = List<bool>.filled(widget.children.length, false);
      for (var i = 0; i < previous.length && i < _built.length; i++) {
        _built[i] = previous[i];
      }
    }
    _markBuilt(widget.index);
  }

  void _markBuilt(int index) {
    if (index >= 0 && index < _built.length) _built[index] = true;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final index = widget.index.clamp(0, widget.children.length - 1);
    _markBuilt(index);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_built[i])
            Offstage(
              offstage: i != index,
              child: TickerMode(
                enabled: i == index,
                child: widget.children[i],
              ),
            ),
      ],
    );
  }
}
