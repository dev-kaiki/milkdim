import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tema único dos apps MilkDim (Material 3, Noto Sans do pacote, cores de [MdColors]).
ThemeData buildMilkdimTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: MdColors.primary,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFBE8CF),
    onPrimaryContainer: MdColors.primaryStrong,
    secondary: MdColors.primaryStrong,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFBE8CF),
    onSecondaryContainer: MdColors.primaryStrong,
    tertiary: MdColors.accent,
    onTertiary: MdColors.text,
    error: MdColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFFF8E1DF),
    onErrorContainer: MdColors.danger,
    surface: MdColors.surface,
    onSurface: MdColors.text,
    onSurfaceVariant: MdColors.textMuted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFFBFAF8),
    surfaceContainer: MdColors.background,
    surfaceContainerHigh: Color(0xFFF1EEEA),
    surfaceContainerHighest: Color(0xFFEBE7E1),
    outline: MdColors.border,
    outlineVariant: MdColors.border,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: MdColors.text,
    onInverseSurface: Colors.white,
    inversePrimary: MdColors.accent,
    surfaceTint: Colors.transparent,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: mdFontFamily,
    scaffoldBackgroundColor: MdColors.background,
  );

  final tt = _textTheme(base.textTheme);

  final fieldShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(MdRadius.field),
  );
  final botaoTexto = tt.labelLarge!.copyWith(
    fontSize: 15,
    fontWeight: FontWeight.w700,
  );
  const botaoMin = Size(64, 48);
  const botaoPadding = EdgeInsets.symmetric(horizontal: MdSpace.xl, vertical: MdSpace.md);

  final botaoPrincipal = FilledButton.styleFrom(
    backgroundColor: MdColors.primaryFill,
    foregroundColor: Colors.white,
    disabledBackgroundColor: MdColors.border,
    disabledForegroundColor: MdColors.textMuted,
    minimumSize: botaoMin,
    padding: botaoPadding,
    shape: fieldShape,
    textStyle: botaoTexto,
    elevation: 0,
  );

  OutlineInputBorder contorno(Color cor, [double largura = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(MdRadius.field),
        borderSide: BorderSide(color: cor, width: largura),
      );

  final indicadorNav = WidgetStateProperty.resolveWith<IconThemeData>(
    (s) => IconThemeData(
      color: s.contains(WidgetState.selected) ? MdColors.primaryStrong : MdColors.textMuted,
    ),
  );

  return base.copyWith(
    textTheme: tt,
    primaryTextTheme: base.primaryTextTheme,
    iconTheme: const IconThemeData(color: MdColors.text),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: MdColors.primary,
      selectionColor: MdColors.primary.withValues(alpha: 0.3),
      selectionHandleColor: MdColors.primary,
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: MdColors.surface,
      foregroundColor: MdColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: tt.titleLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      iconTheme: const IconThemeData(color: MdColors.primaryStrong),
      actionsIconTheme: const IconThemeData(color: MdColors.primaryStrong),
      shape: const Border(bottom: BorderSide(color: MdColors.border)),
    ),

    filledButtonTheme: FilledButtonThemeData(style: botaoPrincipal),
    // As telas atuais usam muito ElevatedButton: mesmo visual do FilledButton.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: botaoPrincipal.copyWith(
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MdColors.primaryStrong,
        backgroundColor: MdColors.surface,
        disabledForegroundColor: MdColors.textMuted,
        side: const BorderSide(color: MdColors.border),
        minimumSize: botaoMin,
        padding: botaoPadding,
        shape: fieldShape,
        textStyle: botaoTexto,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MdColors.primaryStrong,
        minimumSize: const Size(48, 44),
        shape: fieldShape,
        textStyle: botaoTexto,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: MdColors.primaryFill,
      foregroundColor: Colors.white,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MdRadius.card)),
      extendedTextStyle: botaoTexto,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MdColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: MdSpace.lg, vertical: 14),
      border: contorno(MdColors.border),
      enabledBorder: contorno(MdColors.border),
      disabledBorder: contorno(MdColors.border.withValues(alpha: 0.6)),
      focusedBorder: contorno(MdColors.primary, 2),
      errorBorder: contorno(MdColors.danger),
      focusedErrorBorder: contorno(MdColors.danger, 2),
      labelStyle: tt.bodyLarge!.copyWith(color: MdColors.textMuted),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) {
        final cor = s.contains(WidgetState.error)
            ? MdColors.danger
            : s.contains(WidgetState.focused)
                ? MdColors.primaryStrong
                : MdColors.textMuted;
        return tt.bodyLarge!.copyWith(color: cor);
      }),
      hintStyle: tt.bodyLarge!.copyWith(color: MdColors.textMuted),
      helperStyle: tt.bodySmall,
      errorStyle: tt.bodySmall!.copyWith(color: MdColors.danger),
      prefixIconColor: MdColors.textMuted,
      suffixIconColor: MdColors.textMuted,
    ),

    cardTheme: CardThemeData(
      color: MdColors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MdRadius.card),
        side: const BorderSide(color: MdColors.border),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: MdColors.surface,
      selectedColor: MdColors.primarySoft,
      disabledColor: MdColors.background,
      checkmarkColor: MdColors.primaryStrong,
      side: const BorderSide(color: MdColors.border),
      shape: const StadiumBorder(),
      labelStyle: tt.labelLarge!.copyWith(color: MdColors.text, fontWeight: FontWeight.w600),
      secondaryLabelStyle:
          tt.labelLarge!.copyWith(color: MdColors.primaryStrong, fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: MdSpace.sm, vertical: MdSpace.xs),
      iconTheme: const IconThemeData(color: MdColors.textMuted, size: 18),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: MdColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MdRadius.dialog)),
      titleTextStyle: tt.titleLarge!.copyWith(fontWeight: FontWeight.w700),
      contentTextStyle: tt.bodyLarge!.copyWith(color: MdColors.text),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: MdColors.text,
      contentTextStyle: tt.bodyMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      actionTextColor: MdColors.accent,
      closeIconColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MdRadius.field)),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: MdColors.textMuted,
      textColor: MdColors.text,
      titleTextStyle: tt.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
      subtitleTextStyle: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
      leadingAndTrailingTextStyle: tt.bodyMedium!.copyWith(color: MdColors.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: MdSpace.lg),
      minVerticalPadding: MdSpace.sm,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MdRadius.field)),
      selectedColor: MdColors.primaryStrong,
      selectedTileColor: MdColors.primarySoft,
    ),

    dividerTheme: const DividerThemeData(color: MdColors.border, thickness: 1, space: 1),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: MdColors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: MdColors.primarySoft,
      iconTheme: indicadorNav,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? tt.labelMedium!.copyWith(color: MdColors.primaryStrong, fontWeight: FontWeight.w700)
            : tt.labelMedium!.copyWith(color: MdColors.textMuted),
      ),
    ),

    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: MdColors.surface,
      elevation: 0,
      useIndicator: true,
      indicatorColor: MdColors.primarySoft,
      selectedIconTheme: const IconThemeData(color: MdColors.primaryStrong),
      unselectedIconTheme: const IconThemeData(color: MdColors.textMuted),
      selectedLabelTextStyle:
          tt.labelLarge!.copyWith(color: MdColors.primaryStrong, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: tt.labelLarge!.copyWith(color: MdColors.textMuted),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: MdColors.primaryStrong,
      unselectedLabelColor: MdColors.textMuted,
      indicatorColor: MdColors.primary,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: MdColors.border,
      labelStyle: tt.titleSmall!.copyWith(fontWeight: FontWeight.w700),
      unselectedLabelStyle: tt.titleSmall!.copyWith(fontWeight: FontWeight.w500),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: MdColors.primary,
      linearTrackColor: MdColors.primarySoft,
      circularTrackColor: Colors.transparent,
      refreshBackgroundColor: MdColors.surface,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? MdColors.primary : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: MdColors.textMuted, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? MdColors.primary : MdColors.textMuted,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : MdColors.textMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? MdColors.primary : MdColors.background,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? MdColors.primary : MdColors.border,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: MdColors.surface,
      modalBackgroundColor: MdColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: MdColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MdRadius.dialog)),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: MdColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MdRadius.field),
        side: const BorderSide(color: MdColors.border),
      ),
      textStyle: tt.bodyLarge,
      labelTextStyle: WidgetStatePropertyAll(tt.bodyLarge),
    ),

    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(MdColors.surface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
      ),
    ),

    datePickerTheme: DatePickerThemeData(
      backgroundColor: MdColors.surface,
      surfaceTintColor: Colors.transparent,
      headerForegroundColor: MdColors.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MdRadius.dialog)),
      todayBorder: const BorderSide(color: MdColors.primary),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: MdColors.text,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: tt.bodySmall!.copyWith(color: Colors.white),
    ),
  );
}

/// Escala do Material 3 com títulos em w700, cor [MdColors.text] e nada abaixo de 13 px
/// em texto de leitura (labelSmall fica em 12).
TextTheme _textTheme(TextTheme base) {
  final t = base.apply(bodyColor: MdColors.text, displayColor: MdColors.text);
  const titulo = FontWeight.w700;
  return t.copyWith(
    displayLarge: t.displayLarge!.copyWith(fontWeight: titulo),
    displayMedium: t.displayMedium!.copyWith(fontWeight: titulo),
    displaySmall: t.displaySmall!.copyWith(fontWeight: titulo),
    headlineLarge: t.headlineLarge!.copyWith(fontWeight: titulo),
    headlineMedium: t.headlineMedium!.copyWith(fontWeight: titulo),
    headlineSmall: t.headlineSmall!.copyWith(fontWeight: titulo),
    titleLarge: t.titleLarge!.copyWith(fontWeight: titulo),
    titleMedium: t.titleMedium!.copyWith(fontWeight: titulo),
    titleSmall: t.titleSmall!.copyWith(fontWeight: titulo),
    bodyLarge: t.bodyLarge!.copyWith(fontSize: 16),
    bodyMedium: t.bodyMedium!.copyWith(fontSize: 14),
    bodySmall: t.bodySmall!.copyWith(fontSize: 13, color: MdColors.textMuted),
    labelLarge: t.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    labelMedium: t.labelMedium!.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
    labelSmall: t.labelSmall!.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
  );
}
