import 'package:flutter/material.dart';

import 'src/kdrop_controller.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = KdropController();
  controller.load();
  runApp(KdropApp(controller: controller));
}

class KdropApp extends StatelessWidget {
  const KdropApp({super.key, required this.controller});

  final KdropController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kdrop',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (!controller.isReady) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!controller.isOnboarded) return OnboardingScreen(controller: controller);
          return HomeScreen(controller: controller);
        },
      ),
    );
  }
}
