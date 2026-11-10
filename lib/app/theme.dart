import 'package:flutter/material.dart';

const kPrimary = Color(0xFF6C4CF1);
const kGreen = Color(0xFF3CC84B);
const kBlue = Color(0xFF1E8EF7);
const kOrange = Color(0xFFFFA41B);
const kViolet = Color(0xFF8B5CF6);
const kRed = Color(0xFFEF4444);
// Зелёная гамма раздела «Активность».
const kActGreen = Color(0xFF2E9E34);
const kActLime = Color(0xFF8ED14B);
const kActDeep = Color(0xFF1E7A2E);

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: kPrimary, brightness: b);
  // Поверхность всплывающих окон совпадает с карточками приложения.
  final card = dark ? const Color(0xFF1C1C26) : Colors.white;
  final soft = dark ? const Color(0xFF262633) : const Color(0xFFF1EEFC);
  final sheetShape = const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)));
  final dialogShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(32));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF101017) : const Color(0xFFF5F5FB),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: kPrimary, width: 2)),
      filled: true,
      fillColor: dark ? const Color(0xFF1C1C26) : Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1A1A23) : Colors.white,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? kPrimary : null)),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? kPrimary : null)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          foregroundColor: dark ? kViolet : kPrimary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: dialogShape,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface, height: 1.25),
      contentTextStyle:
          TextStyle(fontSize: 15, color: scheme.onSurfaceVariant, height: 1.4),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: card,
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant.withOpacity(0.35),
      shape: sheetShape,
      clipBehavior: Clip.antiAlias,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: dialogShape,
      headerBackgroundColor: kPrimary,
      headerForegroundColor: Colors.white,
      todayBorder: const BorderSide(color: kPrimary),
      confirmButtonStyle: TextButton.styleFrom(foregroundColor: dark ? kViolet : kPrimary),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: card,
      shape: dialogShape,
      hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      hourMinuteColor: soft,
      dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      dialBackgroundColor: soft,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2E2E3D) : const Color(0xFF26263A),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
