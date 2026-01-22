import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:speech_therapy/src/features/slp/presentation/slp_patients_screen.dart';
import 'package:speech_therapy/src/features/slp/presentation/slp_appointments_screen.dart';

class SLPDashboard extends StatefulWidget {
  const SLPDashboard({super.key});

  @override
  State<SLPDashboard> createState() => _SLPDashboardState();
}

class _SLPDashboardState extends State<SLPDashboard> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Start listening for calls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callProvider = context.read<CallProvider>();
      callProvider.listenForIncomingCalls();
      callProvider.addListener(_onCallStateChanged);
    });
  }

  @override
  void dispose() {
    context.read<CallProvider>().removeListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (!mounted) return;
    final callProvider = context.read<CallProvider>();
    if (callProvider.hasIncomingCall) {
       final isAlreadyIncoming = GoRouterState.of(context).uri.toString() == '/incoming_call';
       if (!isAlreadyIncoming) {
       if (!isAlreadyIncoming) {
         final data = callProvider.incomingCallData;
         context.push('/incoming_call', extra: {
           'callerId': data?['callerId'],
           'callerName': data?['callerName'],
           'roomId': data?['roomId'],
         });
       }
       }
    }
  }
  
  // Pages
  final List<Widget> _pages = const [
     SLPHomeTab(),
     SLPPatientsScreen(),
     SLPAppointmentsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
           NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Patients',
          ),
           NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
        ],
      ),
    );
  }
}

class SLPHomeTab extends StatelessWidget {
  const SLPHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SLP Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.headset_mic,
              size: 80,
              color: Colors.teal,
            ).animate().scale(duration: 600.ms),
            const SizedBox(height: 24),
            Text(
              'Welcome Back, Specialist',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
             const SizedBox(height: 8),
            Text(
              user?.email ?? '',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            SelectableText(
              'ID: ${user?.uid}', 
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 48),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Waiting for incoming calls...'),
                    const SizedBox(height: 8),
                    Text(
                      'You will be notified when a patient calls.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                         final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                           try {
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending Test Signal...')));
                             // Simulate remote call writing to OUR incoming node
                             await context.read<CallProvider>().initiateCall(
                               calleeId: user.uid,
                               callerName: "Self Test",
                               callerImage: "",
                             );
                             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signal Sent! Waiting for Listener...')));
                           } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test Failed: $e'), backgroundColor: Colors.red));
                           }
                        }
                      },
                      icon: const Icon(Icons.bug_report),
                      label: const Text("Test Ring (Call Self)"),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
          ],
        ),
      ),
    );
  }
}
