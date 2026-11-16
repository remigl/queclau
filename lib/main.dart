import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const ReveilApp());
}

class ReveilApp extends StatelessWidget {
  const ReveilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Réveil',
      debugShowCheckedModeBanner: false,
      // Toujours sombre : la sphère lumineuse se détache sur fond noir.
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4F7CFF),
        brightness: Brightness.dark,
      ),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomeScreen(),
    );
  }
}
