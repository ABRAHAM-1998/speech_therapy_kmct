import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';
import 'package:speech_therapy/src/features/auth/data/auth_repository.dart';
import 'package:speech_therapy/src/features/auth/presentation/login_screen.dart';
import 'package:speech_therapy/src/features/auth/presentation/register_screen.dart';
import 'package:speech_therapy/src/features/dashboard/presentation/dashboard_screen.dart';
import 'package:speech_therapy/src/features/auth/presentation/medical_survey_screen.dart';
import 'package:speech_therapy/src/features/dashboard/presentation/progress_screen.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/video_call/presentation/video_call_screen.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:speech_therapy/src/features/disorder_identification/presentation/disorder_identification_screen.dart';
import 'package:speech_therapy/src/features/slp/presentation/slp_list_screen.dart';
import 'package:speech_therapy/src/features/video_call/presentation/incoming_call_screen.dart';
import 'package:speech_therapy/src/features/slp/presentation/patient_detail_screen.dart';
import 'package:speech_therapy/src/features/therapy/presentation/voice_practice_screen.dart';
import 'package:speech_therapy/src/features/slp/presentation/specialist_profile_screen.dart';
import 'package:speech_therapy/src/features/dashboard/presentation/patient_appointments_screen.dart';
import 'package:speech_therapy/src/features/dashboard/presentation/patient_homework_screen.dart';

class SpeechTherapyApp extends StatelessWidget {
  const SpeechTherapyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      initialLocation: '/login',
      refreshListenable: _GoRouterRefreshStream(AuthRepository().authStateChanges),
      redirect: (context, state) {
        final isLoggedIn = AuthRepository().currentUser != null;
        final isLoggingIn = state.uri.toString() == '/login';
        final isRegistering = state.uri.toString() == '/register';

        if (!isLoggedIn && !isLoggingIn && !isRegistering) {
            return '/login';
        }

        if (isLoggedIn && (isLoggingIn || isRegistering)) {
          return '/dashboard';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/medical_survey',
          builder: (context, state) => const MedicalSurveyScreen(),
        ),
        GoRoute(
          path: '/assessment', // Actually Disorder Identification
          builder: (context, state) => const DisorderIdentificationScreen(),
        ),
        GoRoute(
            path: '/progress',
            builder: (context, state) => const ProgressScreen()
        ),
        GoRoute(
            path: '/slp_list',
            builder: (context, state) => const SLPListScreen()
        ),
        GoRoute(
          path: '/incoming_call',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>;
            return IncomingCallScreen(
              callerId: extra['callerId'],
              callerName: extra['callerName'],
              roomId: extra['roomId'],
            );
          },
        ),
        GoRoute(
          path: '/video_call',
          builder: (context, state) {
            final extras = state.extra as Map<String, dynamic>;
            return VideoCallScreen(
              roomId: extras['roomId'],
              isCaller: extras['isCaller'],
              userId: extras['userId'],
              userName: extras['userName'],
              userImage: extras['userImage'],
            );
          },
        ),
        GoRoute(
          path: '/patient_details',
          builder: (context, state) {
            final patient = state.extra as Map<String, dynamic>;
            return PatientDetailScreen(patient: patient);
          },
        ),
        GoRoute(
          path: '/voice_practice',
          builder: (context, state) => const VoicePracticeScreen(),
        ),
        GoRoute(
          path: '/specialist_profile',
          builder: (context, state) {
             // Expecting 'slpData' and 'slpId' in extra
             final extra = state.extra as Map<String, dynamic>;
             return SpecialistProfileScreen(
               slpData: extra['slpData'],
               slpId: extra['slpId']
             );
          },
        ),
        GoRoute(
          path: '/patient_appointments',
          builder: (context, state) => const PatientAppointmentsScreen(),
        ),
        GoRoute(
          path: '/patient_homework',
          builder: (context, state) => const PatientHomeworkScreen(),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CallProvider()),
      ],
      child: MaterialApp.router(
        title: 'Speech Therapy AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark, 
        routerConfig: router,
      ),
    );
  }
}

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen(
      (dynamic _) => notifyListeners(),
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
