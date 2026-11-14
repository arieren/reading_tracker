import 'package:material_ui/material_ui.dart';

ThemeData readingTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF35685A),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFA1D3BD) : const Color(0xFF35685A),
        onPrimary: dark ? const Color(0xFF12382B) : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF2C493D)
            : const Color(0xFFDCECE1),
        onPrimaryContainer: dark
            ? const Color(0xFFDCECE1)
            : const Color(0xFF234437),
        secondaryContainer: dark
            ? const Color(0xFF343F38)
            : const Color(0xFFE8EDE5),
        onSecondaryContainer: dark
            ? const Color(0xFFDCE6DB)
            : const Color(0xFF344D3F),
        tertiary: dark ? const Color(0xFFE7B899) : const Color(0xFF996648),
        surface: dark ? const Color(0xFF181C1A) : const Color(0xFFFAF9F5),
        surfaceContainerLow: dark
            ? const Color(0xFF202622)
            : const Color(0xFFFFFEFA),
        surfaceContainer: dark
            ? const Color(0xFF292F2B)
            : const Color(0xFFF0F0E9),
        outlineVariant: dark
            ? const Color(0xFF3C4740)
            : const Color(0xFFDEE3DA),
      );
  final base = ThemeData(colorScheme: scheme, brightness: brightness);
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: rounded.copyWith(side: BorderSide(color: scheme.outlineVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        minimumSize: const Size(48, 48),
        shape: rounded,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: rounded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: rounded,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: rounded,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
