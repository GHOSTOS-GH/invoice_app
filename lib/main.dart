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

// Palette de l'application (bleu professionnel moderne)
const Color kPrimary = Color(0xFF2563EB);
const Color kPrimaryDark = Color(0xFF1D4ED8);
const Color kInk = Color(0xFF0F172A);
const Color kInkSoft = Color(0xFF334155);
const Color kBody = Color(0xFF64748B);
const Color kMuted = Color(0xFF94A3B8);
const Color kSurface = Color(0xFFF8FAFC);
const Color kBorder = Color(0xFFE2E8F0);
const Color kSuccess = Color(0xFF16A34A);
const Color kDanger = Color(0xFFDC2626);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  runApp(const InvoiceApp());
}

class InvoiceApp extends StatelessWidget {
  const InvoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: kPrimary,
      brightness: Brightness.light,
      surface: Colors.white,
    );

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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: base,
        scaffoldBackgroundColor: kSurface,
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          backgroundColor: Colors.white,
          foregroundColor: kInk,
          titleTextStyle: TextStyle(
            color: kInk,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shadowColor: kPrimary.withValues(alpha: 0.10),
          surfaceTintColor: Colors.transparent,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFEDF1F7)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
            side: const BorderSide(color: kPrimary, width: 1.5),
            foregroundColor: kPrimary,
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kPrimary,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          extendedPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF4F6FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kPrimary, width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kDanger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kDanger, width: 1.8),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          labelStyle: const TextStyle(color: kBody, fontSize: 14, fontWeight: FontWeight.w500),
          hintStyle: TextStyle(color: kMuted.withValues(alpha: 0.9), fontSize: 14),
          prefixIconColor: kMuted,
          suffixIconColor: kMuted,
        ),
        navigationBarTheme: NavigationBarThemeData(
          elevation: 12,
          height: 72,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          indicatorColor: kPrimary.withValues(alpha: 0.12),
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPrimary);
              }
              return const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: kMuted);
            },
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: kPrimary, size: 25);
              }
              return const IconThemeData(color: kMuted, size: 24);
            },
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          elevation: 4,
          backgroundColor: kInk,
          contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titleTextStyle: const TextStyle(color: kInk, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
          contentTextStyle: const TextStyle(color: kInkSoft, fontSize: 14, height: 1.4),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          side: const BorderSide(color: kBorder),
          backgroundColor: Colors.white,
          selectedColor: kPrimary.withValues(alpha: 0.12),
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        dividerTheme: const DividerThemeData(space: 1, thickness: 1, color: Color(0xFFF1F5F9)),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: kPrimary),
        listTileTheme: const ListTileThemeData(iconColor: kBody),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          headerBackgroundColor: kPrimary,
          headerForegroundColor: Colors.white,
        ),
      ),
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
      return const MainScreen();
    } else {
      return LoginScreen(onLoginSuccess: _onLoginSuccess);
    }
  }

  void _onLoginSuccess() => setState(() => _isAuthenticated = true);
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<_HistoryScreenWrapperState> _historyKey = GlobalKey();

  void _onInvoiceCreated() {
    setState(() => _currentIndex = 1);
    _historyKey.currentState?.refresh();
  }

  void _onInvoiceUpdated() => _historyKey.currentState?.refresh();

  @override
  Widget build(BuildContext context) {
    final screens = [
      NewInvoiceScreen(onInvoiceCreated: _onInvoiceCreated),
      _HistoryScreenWrapper(key: _historyKey, onInvoiceUpdated: _onInvoiceUpdated),
      const StatsScreen(),
      SettingsScreen(onDataRestored: _onInvoiceUpdated),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.white,
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

class _HistoryScreenWrapper extends StatefulWidget {
  final VoidCallback onInvoiceUpdated;
  const _HistoryScreenWrapper({super.key, required this.onInvoiceUpdated});
  @override
  State<_HistoryScreenWrapper> createState() => _HistoryScreenWrapperState();
}

class _HistoryScreenWrapperState extends State<_HistoryScreenWrapper> {
  final GlobalKey<HistoryScreenState> _historyScreenKey = GlobalKey();

  void refresh() => _historyScreenKey.currentState?.refreshData();

  @override
  Widget build(BuildContext context) {
    return HistoryScreen(
      key: _historyScreenKey,
      onInvoiceUpdated: widget.onInvoiceUpdated,
    );
  }
}
