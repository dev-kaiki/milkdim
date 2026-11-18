import 'package:flutter/material.dart';

const Color milkdimYellow     = Color(0xFFFFE066);
const Color milkdimOrange     = Color(0xFFE38A1D);
const Color milkdimWhite      = Color(0xFFFFFFFF);
const Color milkdimGrey       = Color(0xFFF7F7F7);
const Color milkdimDarkOrange = Color(0xFFC06617);

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light);

  final scheme = ColorScheme.fromSeed(
    seedColor: milkdimOrange,
    brightness: Brightness.light,
  ).copyWith(
    primary: milkdimOrange,
    onPrimary: milkdimWhite,
    secondary: milkdimYellow,
    onSecondary: milkdimDarkOrange,
    background: milkdimGrey,
    onBackground: Colors.black87,
    surface: milkdimWhite,
    onSurface: Colors.black87,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,

    // tipografia
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: milkdimDarkOrange,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: milkdimOrange,
      ),
    ),

    // AppBar amarela / título laranja
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: milkdimYellow,
      foregroundColor: milkdimOrange,
      titleTextStyle: TextStyle(
        color: milkdimOrange,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        letterSpacing: 1.05,
      ),
      iconTheme: IconThemeData(color: milkdimOrange),
    ),

    // Cards brancos arredondados (usar CardThemeData)
    cardTheme: CardThemeData(
      color: milkdimWhite,
      elevation: 2.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    ),

    // Inputs (busca/formulários)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: milkdimWhite,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
      prefixIconColor: milkdimOrange,
      suffixIconColor: milkdimOrange,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: milkdimYellow, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: milkdimYellow, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: milkdimOrange, width: 2.2),
      ),
    ),

    // Botões
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: milkdimOrange,
        side: const BorderSide(color: milkdimOrange, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: milkdimOrange,
      foregroundColor: milkdimWhite,
      elevation: 3,
    ),

    // Lista/Divisores
    listTileTheme: const ListTileThemeData(
      iconColor: milkdimOrange,
      textColor: Colors.black87,
    ),
    dividerTheme: const DividerThemeData(thickness: 0.7, space: 0),

    // Navegação inferior
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: milkdimYellow,
      selectedItemColor: milkdimOrange,
      unselectedItemColor: milkdimOrange.withOpacity(0.55),
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
    ),

    // Chips (status / ativo)
    chipTheme: base.chipTheme.copyWith(
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
      selectedColor: milkdimOrange.withOpacity(.15),
      side: BorderSide(color: milkdimOrange.withOpacity(.35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),

    // Snackbars
    snackBarTheme: SnackBarThemeData(
      backgroundColor: milkdimOrange,
      contentTextStyle: const TextStyle(
        color: milkdimWhite,
        fontWeight: FontWeight.w600,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
