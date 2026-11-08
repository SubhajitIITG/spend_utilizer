import 'package:flutter/material.dart';

/// Royal palette: deep purple, gold accents, ivory backgrounds.
class Royal {
  static const deep = Color(0xFF1E0B44);
  static const purple = Color(0xFF4B2A85);
  static const violet = Color(0xFF6A43B0);
  static const lavender = Color(0xFFC9B6F2);
  static const gold = Color(0xFFD4AF37);
  static const goldLight = Color(0xFFF1D98A);
  static const ivory = Color(0xFFFBF8F3);
  static const ink = Color(0xFF1C1530);
  static const nightSurface = Color(0xFF140A29);
  static const nightCard = Color(0xFF221440);

  /// Money in / out colours that work on light and dark backgrounds.
  static Color income(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFF6FD3A0)
      : const Color(0xFF1B7F52);
  static Color spend(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFFFF8A80)
      : const Color(0xFFB3261E);

  static const gradient = LinearGradient(
    colors: [Color(0xFF1E0B44), Color(0xFF3B1C74), Color(0xFF5B34A0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const goldGradient = LinearGradient(
    colors: [Color(0xFFB8892B), Color(0xFFE9C766), Color(0xFFC79A33)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const chartColors = [
    Color(0xFF5B34A0),
    Color(0xFFD4AF37),
    Color(0xFF2A9D8F),
    Color(0xFFC0392B),
    Color(0xFF3F51B5),
    Color(0xFFD16BA5),
    Color(0xFF1B7F52),
    Color(0xFFE67E22),
    Color(0xFF8E44AD),
    Color(0xFF607D8B),
  ];
}

ThemeData royalTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Royal.purple,
    brightness: brightness,
  );
  final scheme = base.copyWith(
    primary: dark ? Royal.lavender : Royal.purple,
    onPrimary: dark ? Royal.ink : Colors.white,
    secondary: Royal.gold,
    onSecondary: Royal.ink,
    surface: dark ? Royal.nightSurface : Royal.ivory,
    surfaceContainerLowest: dark ? const Color(0xFF0F071F) : Colors.white,
    surfaceContainerLow: dark ? Royal.nightCard : Colors.white,
    surfaceContainer: dark ? const Color(0xFF26174A) : const Color(0xFFF6F1E8),
    surfaceContainerHigh: dark
        ? const Color(0xFF2C1B55)
        : const Color(0xFFF1EADF),
    surfaceContainerHighest: dark
        ? const Color(0xFF34205F)
        : const Color(0xFFEBE2D3),
  );
  final goldHairline = Royal.gold.withValues(alpha: dark ? 0.35 : 0.45);

  final text = Typography.material2021(platform: TargetPlatform.android).black
      .apply(
        bodyColor: dark ? Colors.white : Royal.ink,
        displayColor: dark ? Colors.white : Royal.ink,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Royal.deep,
      foregroundColor: Colors.white,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: goldHairline, width: 0.8),
      ),
    ),
    dividerTheme: DividerThemeData(color: goldHairline, thickness: 0.6),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide(color: goldHairline),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(
        color: dark ? Colors.white : Royal.ink,
        fontWeight: FontWeight.w500,
      ),
      selectedColor: Royal.gold.withValues(alpha: 0.25),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? Royal.gold : Royal.purple,
        foregroundColor: dark ? Royal.ink : Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Royal.gold, width: 1.2),
        foregroundColor: dark ? Royal.goldLight : Royal.purple,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Royal.gold,
      foregroundColor: Royal.ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: goldHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: goldHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Royal.gold, width: 1.6),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: goldHairline)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Royal.gold.withValues(alpha: 0.25)
              : null,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Royal.deep,
      indicatorColor: Royal.gold.withValues(alpha: 0.22),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Royal.gold
              : Colors.white.withValues(alpha: 0.7),
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: s.contains(WidgetState.selected)
              ? Royal.goldLight
              : Colors.white.withValues(alpha: 0.7),
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Royal.deep,
      indicatorColor: Royal.gold.withValues(alpha: 0.22),
      selectedIconTheme: const IconThemeData(color: Royal.gold),
      unselectedIconTheme: IconThemeData(
        color: Colors.white.withValues(alpha: 0.7),
      ),
      selectedLabelTextStyle: const TextStyle(
        color: Royal.goldLight,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.7),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Royal.deep,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// App bar with the royal gradient and a thin gold line underneath.
PreferredSizeWidget royalAppBar(
  String title, {
  List<Widget>? actions,
  Widget? leading,
}) {
  return AppBar(
    title: Text(title),
    leading: leading,
    actions: actions,
    flexibleSpace: const DecoratedBox(
      decoration: BoxDecoration(gradient: Royal.gradient),
    ),
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(1.5),
      child: SizedBox(
        height: 1.5,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: Royal.goldGradient),
        ),
      ),
    ),
  );
}

/// The gold ₹ emblem used as the app's logo.
class RoyalEmblem extends StatelessWidget {
  final double size;
  const RoyalEmblem({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: Royal.goldGradient,
        boxShadow: [
          BoxShadow(
            color: Royal.gold.withValues(alpha: 0.35),
            blurRadius: size / 3,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '₹',
        style: TextStyle(
          fontSize: size * 0.5,
          color: Royal.deep,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
