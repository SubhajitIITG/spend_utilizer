import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/store.dart';
import 'services/auth_service.dart';
import 'services/supabase_backend.dart';
import 'services/sync_service.dart';
import 'ui/accounts_screen.dart';
import 'ui/chat_screen.dart';
import 'ui/dashboard_screen.dart';
import 'ui/login_screen.dart';
import 'ui/transactions_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.load();

  AuthService? auth;
  if (AppConfig.cloudEnabled) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseKey,
      );
      auth = AuthService(Supabase.instance.client.auth);
    } catch (e) {
      debugPrint('Cloud disabled, Supabase init failed: $e');
    }
  }
  runApp(SpendUtilizerApp(store: store, auth: auth));
}

class SpendUtilizerApp extends StatefulWidget {
  final AppStore store;

  /// Null when cloud login/sync is not configured (offline-only mode).
  final AuthService? auth;

  const SpendUtilizerApp({super.key, required this.store, this.auth});

  @override
  State<SpendUtilizerApp> createState() => _SpendUtilizerAppState();
}

class _SpendUtilizerAppState extends State<SpendUtilizerApp> {
  late final SyncService _sync = SyncService(widget.store);
  String? _syncingFor;

  @override
  void initState() {
    super.initState();
    widget.auth?.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  /// Starts/stops sync when the user signs in or out.
  void _onAuthChanged() {
    final uid = widget.auth?.user?.id;
    if (uid == _syncingFor) return;
    _syncingFor = uid;
    if (uid == null) {
      _sync.stop();
    } else {
      _sync.start(SupabaseSyncBackend(Supabase.instance.client), uid);
    }
  }

  @override
  void dispose() {
    widget.auth?.removeListener(_onAuthChanged);
    _sync.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1E6B52);
    final auth = widget.auth;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.store),
        ChangeNotifierProvider.value(value: _sync),
        ChangeNotifierProvider<AuthService?>.value(value: auth),
      ],
      child: MaterialApp(
        title: 'Spend Utilizer',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.system,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme:
              ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: auth == null
            ? const HomeShell()
            : ListenableBuilder(
                listenable: auth,
                builder: (_, _) =>
                    auth.signedIn ? const HomeShell() : const LoginScreen(),
              ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
    (Icons.dashboard_outlined, Icons.dashboard, 'Dashboard'),
    (Icons.receipt_long_outlined, Icons.receipt_long, 'History'),
    (Icons.account_balance_outlined, Icons.account_balance, 'Accounts'),
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = [
      const ChatScreen(),
      DashboardScreen(onOpenAccounts: () => setState(() => _index = 3)),
      const TransactionsScreen(),
      const AccountsScreen(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(index: _index, children: pages);

    if (wide) {
      // Desktop / tablet: side navigation rail.
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Text('₹',
                    style: TextStyle(color: Colors.white, fontSize: 20)),
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                    icon: Icon(d.$1),
                    selectedIcon: Icon(d.$2),
                    label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
                icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
        ],
      ),
    );
  }
}
