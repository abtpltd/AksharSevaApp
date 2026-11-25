import 'package:flutter/material.dart';

/// Colours read from baps.org: cream page, near-black text, saffron-brown links, red headings, red-orange accent.
/// The dark title-bar maroon is derived from the site's red.
const maroon = Color(0xFF4A0A0D);
const cream = Color(0xFFEFE8D6);
const ink = Color(0xFF201D1D);
const saffron = Color(0xFFAA5900);
const baps_red = Color(0xFFB5090E);
const redOrange = Color(0xFFCC2B00);
const lightSaffron = Color(0xFFE8892B);
const paleSand = Color(0xFFE8C9A0);
const line = Color(0xFFD9CFB5);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: saffron).copyWith(
    primary: saffron,
    onPrimary: Colors.white,
    secondary: redOrange,
    onSecondary: Colors.white,
    surface: cream,
    onSurface: ink,
    error: baps_red,
  );
  const bar = TextStyle(color: cream, fontSize: 18, fontWeight: FontWeight.w500);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    appBarTheme: const AppBarTheme(backgroundColor: maroon, foregroundColor: cream, surfaceTintColor: Colors.transparent, titleTextStyle: bar, iconTheme: IconThemeData(color: cream), actionsIconTheme: IconThemeData(color: cream), elevation: 0),
    tabBarTheme: const TabBarThemeData(indicatorColor: lightSaffron, labelColor: Colors.white, unselectedLabelColor: paleSand, dividerColor: Colors.transparent),
    cardTheme: CardThemeData(color: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0, margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: line))),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: redOrange, foregroundColor: Colors.white),
    drawerTheme: const DrawerThemeData(backgroundColor: cream, surfaceTintColor: Colors.transparent),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: saffron, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), minimumSize: const Size(64, 44))),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: saffron)),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Color(0xFFCFC3A5)))),
    chipTheme: ChipThemeData(backgroundColor: const Color(0xFFF3D9B8), labelStyle: const TextStyle(color: Color(0xFF7A3B00), fontSize: 12), side: BorderSide.none, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    listTileTheme: const ListTileThemeData(iconColor: saffron),
  );
}
