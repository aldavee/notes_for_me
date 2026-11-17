import 'package:material_ui/material_ui.dart';
import 'package:notes_for_me/core/presentation/navigation/adaptive_page_route.dart';
import 'package:notes_for_me/core/theme/theme_service.dart';
import 'package:notes_for_me/features/notes/presentation/home_screen.dart';
import 'package:notes_for_me/features/security/presentation/biometric_lock_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ThemeService.instance.initialize();
  runApp(const NotesForMeApp());
}

class NotesForMeApp extends StatelessWidget {
  const NotesForMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F46E5),
      primary: const Color(0xFF4338CA),
      secondary: const Color(0xFFD97706),
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      primary: const Color(0xFF818CF8),
      secondary: const Color(0xFFFBBF24),
      brightness: Brightness.dark,
    );

    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) => MaterialApp(
        title: 'Notes For Me',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeService.instance.themeMode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: lightScheme,
          scaffoldBackgroundColor: const Color(0xFFF8FAFC),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.windows: DesktopFadePageTransitionsBuilder(),
              TargetPlatform.linux: DesktopFadePageTransitionsBuilder(),
              TargetPlatform.macOS: DesktopFadePageTransitionsBuilder(),
            },
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: darkScheme,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.windows: DesktopFadePageTransitionsBuilder(),
              TargetPlatform.linux: DesktopFadePageTransitionsBuilder(),
              TargetPlatform.macOS: DesktopFadePageTransitionsBuilder(),
            },
          ),
        ),
        home: const BiometricLockGate(
          child: HomeScreen(),
        ),
      ),
    );
  }
}
