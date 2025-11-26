import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gen/assets.gen.dart';
import 'providers/data_provider.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/transactions_screen.dart';
import 'utils/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkMode') ?? false;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  void _updateThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DataProvider()),
        Provider<Function(ThemeMode)>.value(value: _updateThemeMode),
      ],
      child: MaterialApp(
        title: 'Spendrix',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
        routes: {
          '/setup': (context) => const SetupScreen(),
          '/home': (context) => const HomeScreen(),
          '/transactions': (context) => const TransactionsScreen(),
        },
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final setupCompleted = prefs.getBool('setupCompleted') ?? false;

    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    if (!setupCompleted) {
      Navigator.of(context).pushReplacementNamed('/setup');
    } else {
      final dataProvider = Provider.of<DataProvider>(context, listen: false);
      await dataProvider.loadAllData();
      
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                image: DecorationImage(
                  image: Assets.icon.icon.provider(),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Spendrix',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.displayLarge?.color,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Smart Money Management',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
