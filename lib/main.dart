import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const ReveilApp());
}

class ReveilApp extends StatelessWidget {
  const ReveilApp({super.key});

  static const _seed = Color(0xFF3D5AFE);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Réveil',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: _seed),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
      ),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeScreen(),
    );
  }
}
