import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';
import 'package:speech_therapy/src/features/auth/presentation/login_screen.dart';

class SpeechTherapyApp extends StatelessWidget {
  const SpeechTherapyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        // Add more routes here as features are implemented
      ],
    );

    return MaterialApp.router(
      title: 'Speech Therapy AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Default to dark for premium look
      routerConfig: router,
    );
  }
}
