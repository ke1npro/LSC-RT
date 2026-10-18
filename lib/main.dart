import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/di/app_providers.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/main_scaffold.dart';

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error al inicializar cámaras: $e');
  }

  runApp(const LscApp());
}

class LscApp extends StatelessWidget {
  const LscApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: AppProviders.buildProviders(_cameras),
      child: MaterialApp(
        title: 'LSC RT',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainScaffold(),
      ),
    );
  }
}
