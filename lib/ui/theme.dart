import 'package:flutter/material.dart';

/// "Wine & Gold" palette: deep wine, burnished gold and midnight navy on
/// warm ivory paper. Solid colours and fine gold rules rather than glossy
/// gradients and glows, for a classic, hand-set feel.
class Royal {
  /// Darkest wine: app bars, navigation.
  static const deep = Color(0xFF2B0716);

  /// Wine: primary colour (buttons, your chat bubbles, headers).
  static const purple = Color(0xFF6E1233);

  /// Lighter wine for accents.
  static const violet = Color(0xFF9B2B4E);

  /// Rose: primary colour in dark mode (readable on dark wine).
  static const lavender = Color(0xFFE9A8BB);

  /// Midnight navy: dashboard header card and secondary accents.
  static const navy = Color(0xFF0F2742);

  static const gold = Color(0xFFC9A13B);
  static const goldLight = Color(0xFFEBD293);
  static const ivory = Color(0xFFF8F1E5);
  static const ink = Color(0xFF231218);
  static const nightSurface = Color(0xFF170810);
  static const nightCard = Color(0xFF26101A);

  /// Money in / out colours that work on light and dark backgrounds.
  static Color income(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFF93D3AE)
      : const Color(0xFF2D6A4F);
  static Color spend(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFFFF9A9A)
      : const Color(0xFFA4161A);

  /// Kept as "gradients" for existing call sites, but deliberately flat.
  static const gradient = LinearGradient(colors: [deep, deep]);
  static const goldGradient = LinearGradient(colors: [gold, gold]);

  static const chartColors = [
    Color(0xFF6E1233), // wine
    Color(0xFFC9A13B), // gold
    Color(0xFF0F2742), // navy
    Color(0xFFD9566F), // rose
    Color(0xFF2E6F73), // teal
    Color(0xFF7D4E9E), // plum
    Color(0xFFB8682E), // copper
    Color(0xFF5E7A3A), // olive
    Color(0xFF4F6D8F), // slate blue
    Color(0xFF8C7B6B), // taupe
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
    surfaceContainerLowest: dark
        ? const Color(0xFF10050B)
        : const Color(0xFFFFFCF6),
    surfaceContainerLow: dark ? Royal.nightCard : const Color(0xFFFFFAF1),
    surfaceContainer: dark ? const Color(0xFF2E1420) : const Color(0xFFF3EADB),
    surfaceContainerHigh: dark
        ? const Color(0xFF381927)
        : const Color(0xFFEEE3D0),
    surfaceContainerHighest: dark
        ? const Color(0xFF431E2F)
        : const Color(0xFFE7DAC3),
  );
  final goldHairline = Royal.gold.withValues(alpha: dark ? 0.35 : 0.45);

  // Palatino-style serif everywhere (TeX Gyre Pagella, bundled in
  // assets/fonts so it looks the same on every platform).
  final text = Typography.material2021(platform: TargetPlatform.android).black
      .apply(
        fontFamily: 'Pagella',
        bodyColor: dark ? const Color(0xFFF6EBDD) : Royal.ink,
        displayColor: dark ? const Color(0xFFF6EBDD) : Royal.ink,
      );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Pagella',
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
        fontFamily: 'Pagella',
        color: Royal.goldLight,
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
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: goldHairline, width: 0.8),
      ),
    ),
    dividerTheme: DividerThemeData(color: goldHairline, thickness: 0.6),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      side: BorderSide(color: goldHairline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(
        fontFamily: 'Pagella',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(
          fontFamily: 'Pagella',
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontFamily: 'Pagella', fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontFamily: 'Pagella', fontSize: 15),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Royal.gold,
      foregroundColor: Royal.ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: const TextStyle(fontFamily: 'Pagella'),
      labelStyle: const TextStyle(fontFamily: 'Pagella'),
      helperStyle: const TextStyle(fontFamily: 'Pagella'),
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: goldHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: goldHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
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
      contentTextStyle: TextStyle(fontFamily: 'Pagella', color: Colors.white),
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

  /// A gold coin with a fine inner ring and a wine ₹, like a seal.
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Royal.gold,
      ),
      padding: EdgeInsets.all(size * 0.07),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Royal.deep, width: size * 0.025),
        ),
        alignment: Alignment.center,
        child: Text(
          '₹',
          style: TextStyle(
            fontFamily: 'Pagella',
            fontSize: size * 0.48,
            color: Royal.purple,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
