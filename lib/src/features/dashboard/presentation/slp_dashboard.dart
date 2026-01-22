import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:speech_therapy/src/features/slp/presentation/slp_patients_screen.dart';
import 'package:speech_therapy/src/features/slp/presentation/slp_appointments_screen.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class SLPDashboard extends StatefulWidget {
  const SLPDashboard({super.key});

  @override
  State<SLPDashboard> createState() => _SLPDashboardState();
}

class _SLPDashboardState extends State<SLPDashboard> {
  int _currentIndex = 0;
  String? _lastHandledRoomId;

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
    // context.read<CallProvider>().removeListener(_onCallStateChanged); // Safe to omit if provider persists
    super.dispose();
  }

  void _onCallStateChanged() async {
    if (!mounted) return;
    final callProvider = context.read<CallProvider>();
    
    // Reset if no call
    if (!callProvider.hasIncomingCall) {
       _lastHandledRoomId = null;
       return;
    }

    final data = callProvider.incomingCallData;
    final incomingRoomId = data?['roomId'];
    
    // Prevent duplicate handling for same room
    if (incomingRoomId == null || _lastHandledRoomId == incomingRoomId) {
       return;
    }

    await Future.delayed(const Duration(seconds: 2));
    
    // Re-check validity after delay
    if (!mounted || !callProvider.hasIncomingCall) return;
    final currentData = callProvider.incomingCallData;
    if (currentData == null || currentData['roomId'] != incomingRoomId) return;
    
    // Check if we are already on that screen (double safety)
    final isAlreadyIncoming = GoRouterState.of(context).uri.toString() == '/incoming_call';
    if (isAlreadyIncoming) return;

    // Mark as handled
    _lastHandledRoomId = incomingRoomId;

    context.push('/incoming_call', extra: {
      'callerId': data?['callerId'],
      'callerName': data?['callerName'],
      'roomId': incomingRoomId,
    });
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _DesktopLayout(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              body: _pages[_currentIndex],
            );
          } else {
            return _MobileLayout(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              body: _pages[_currentIndex],
            );
          }
        },
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  const _MobileLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
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

class _DesktopLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  const _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NavigationRail(
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelType: NavigationRailLabelType.all,
          leading: const Padding(
             padding: EdgeInsets.symmetric(vertical: 24),
             child: Icon(Icons.medical_services_outlined, color: AppTheme.secondaryColor, size: 32),
          ),
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: Text('Home'),
            ),
             NavigationRailDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: Text('Patients'),
            ),
             NavigationRailDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today),
              label: Text('Schedule'),
            ),
          ],
           trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                     await FirebaseAuth.instance.signOut();
                     if(context.mounted) context.go('/login');
                  },
                ),
              ),
            ),
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: body),
      ],
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
          // On mobile, logout is in Appbar. On desktop, it is in NavRail.
          // We can keep it here for mobile, or conditionally hide it.
          // For simplicity, we keep it if not desktop (although here we don't strictly know without MediaQuery)
          // But since _DesktopLayout manages its own Logout, we might duplicates.
          // Let's assume on Desktop, the AppBar is still shown by this Scaffold inside the body.
          // We can hide actions if on Desktop ideally.
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headset_mic,
                  size: 64,
                  color: AppTheme.primaryColor,
                ).animate().scale(duration: 600.ms),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome Back, Specialist',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold
                ),
              ),
               const SizedBox(height: 8),
              Text(
                user?.email ?? '',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.textSecondary
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                'ID: ${user?.uid}', 
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(height: 48),
              
              Container(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 24),
                        Text(
                           'Online & Ready',
                           style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Waiting for incoming patient calls...',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 32),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
