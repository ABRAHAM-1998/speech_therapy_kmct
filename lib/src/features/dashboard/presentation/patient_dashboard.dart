import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/auth/data/auth_repository.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:speech_therapy/src/features/slp/data/appointment_repository.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  int _selectedIndex = 0; // For NavigationRail/Bar

  @override
  void initState() {
    super.initState();
    _checkProfile();
    
    // Listen for incoming calls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callProvider = context.read<CallProvider>();
      callProvider.listenForIncomingCalls();
      callProvider.addListener(_onCallStateChanged);
    });
  }

  @override
  void dispose() {
    // Ideally remove listener if possible or rely on provider cleanup
    super.dispose();
  }

  // Track the last handled call ID to avoid duplicate pushes
  String? _lastHandledRoomId;

  void _onCallStateChanged() async {
    if (!mounted) return;
    
    final provider = context.read<CallProvider>();
    
    if (!provider.hasIncomingCall || provider.incomingCallData == null) {
       _lastHandledRoomId = null;
       return;
    }
    
    final data = provider.incomingCallData!;
    final incomingRoomId = data['roomId'];
    
    if (_lastHandledRoomId == incomingRoomId) {
       return;
    }

    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted || !provider.hasIncomingCall) return;
    final currentData = provider.incomingCallData;
    if (currentData == null || currentData['roomId'] != incomingRoomId) return;

    _lastHandledRoomId = incomingRoomId;
    
    context.push('/incoming_call', extra: {
      'callerId': data['callerId'],
      'callerName': data['callerName'],
      'callerImage': data['callerImage'],
      'roomId': incomingRoomId,
    });
  }

  Future<void> _checkProfile() async {
    final isComplete = await AuthRepository().isProfileComplete();
    if (!isComplete && mounted) {
      context.go('/medical_survey');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _DesktopLayout(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              body: _buildDashboardContent(context, true),
            );
          } else {
            return _MobileLayout(
              selectedIndex: _selectedIndex, // Keeping bottom nav logic if we want multiple tabs later
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              body: _buildDashboardContent(context, false),
            );
          }
        },
      ),
    );
  }

  Widget _buildDashboardContent(BuildContext context, bool isDesktop) {
     final user = FirebaseAuth.instance.currentUser;
     
     return SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? 32.0 : 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isDesktop) ...[
               const SizedBox(height: 32), // Spacer for mobile status bar if not using AppBar
            ],
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome Back,',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ).animate().fadeIn(),
                     Text(
                      user?.email ?? 'User', // Could extract name if available
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onBackground,
                          ),
                    ).animate().fadeIn(delay: 200.ms),
                  ],
                ),
                 CircleAvatar(
                   radius: 24,
                   backgroundColor: AppTheme.primaryColor,
                   child: Text(
                     (user?.email?[0] ?? 'U').toUpperCase(),
                     style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                   ),
                 ),
              ],
            ),

            const SizedBox(height: 32),
            
            // Quick Simulation Button
             Container(
               padding: const EdgeInsets.all(16),
               decoration: BoxDecoration(
                 color: Theme.of(context).colorScheme.surface,
                 borderRadius: BorderRadius.circular(16),
                 border: Border.all(color: AppTheme.surfaceColorLight),
               ),
               child: Row(
                 children: [
                   const Icon(Icons.bug_report, color: Colors.amber),
                   const SizedBox(width: 16),
                   const Expanded(child: Text("Test incoming call simulation")),
                   TextButton(
                      onPressed: () {
                         final user = FirebaseAuth.instance.currentUser;
                         if (user == null) return;
                         context.push('/incoming_call', extra: {
                           'callerId': 'test_slp_1',
                           'callerName': 'Simulated Dr.',
                           'roomId': 'test_room_1',
                         });
                      },
                      child: const Text("Simulate"),
                   )
                 ],
               ),
             ),

            const SizedBox(height: 32),
            
             // Next Appointment Card
              StreamBuilder<QuerySnapshot>(
                stream: AppointmentRepository().getAppointmentsForPatient(user?.uid ?? ''),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  
                  final docs = snapshot.data!.docs;
                  final now = DateTime.now();
                  
                  // Find next upcoming appointment
                  Map<String, dynamic>? nextAppt;
                  for (var doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final dateStr = data['dateTime'] as String?;
                    if (dateStr == null) continue;
                    
                    final date = DateTime.tryParse(dateStr);
                    final status = data['status'];
                    
                    if (date != null && date.isAfter(now) && status == 'upcoming') {
                      nextAppt = data;
                      break; // Since it's ordered by date, the first future one is the next one
                    }
                  }

                  if (nextAppt == null) return const SizedBox.shrink();

                  final date = DateTime.parse(nextAppt['dateTime']);
                  final slpName = nextAppt['slpName'] ?? 'Specialist';
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 32.0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                           BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.calendar_month, color: Colors.white),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Next Session",
                                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                                  ),
                                  Text(
                                    slpName,
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              if (date.difference(now).inMinutes < 15) // Show Join button if within 15 mins
                                ElevatedButton.icon(
                                  onPressed: () async {
                                     // Join Call
                                      try {
                                       final slpId = nextAppt?['slpId'];
                                       final myName = user?.displayName ?? 'Patient';
                                       final myImage = user?.photoURL ?? 'https://i.pravatar.cc/150';
                                       
                                       // We can just join/initiate. If SLP is already there, it joins.
                                       final roomId = await context.read<CallProvider>().initiateCall(
                                            calleeId: slpId, 
                                            callerName: myName, // We are calling/joining
                                            callerImage: myImage,
                                       );
                                       
                                       if(context.mounted) {
                                          context.push('/video_call', extra: {
                                            'roomId': roomId,
                                            'isCaller': true, 
                                            'userId': slpId,
                                            'userName': slpName,
                                          });
                                       }
                                     } catch(e) {
                                       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to join: $e")));
                                     }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: AppTheme.primaryColor,
                                  ),
                                  icon: const Icon(Icons.videocam),
                                  label: const Text("Join Now"),
                                )
                            ],
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                               _buildInfoChip(Icons.access_time, DateFormat('h:mm a').format(date)),
                               _buildInfoChip(Icons.event_available, DateFormat('EEE, MMM d').format(date)),
                               _buildInfoChip(Icons.video_camera_front, "Video Call"),
                            ],
                          )
                        ],
                      ),
                    ).animate().fadeIn().slideY(begin: 0.2, end: 0),
                  );
                },
              ),

             Text(
              "Your Activities",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: isDesktop ? 4 : 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.0,
              children: [
                _buildActionCard(
                  context,
                  title: 'Start Therapy',
                  subtitle: 'Daily exercises',
                  icon: Icons.mic,
                  color: AppTheme.primaryColor,
                  onTap: () => context.push('/patient_homework'),
                  delay: 0,
                ),
                _buildActionCard(
                  context,
                  title: 'Virtual Trainer',
                  subtitle: 'AI Feedback',
                  icon: Icons.face_retouching_natural,
                  color: AppTheme.secondaryColor,
                  onTap: () {
                     context.push(
                       '/video_call',
                       extra: {
                         'roomId': 'trainer_room_1',
                         'isCaller': true,
                         'userId': 'trainer_123',
                         'userName': 'Virtual Trainer',
                         'userImage': 'https://i.pravatar.cc/150?u=trainer_123',
                       },
                     );
                  },
                   delay: 100,
                ),
                _buildActionCard(
                  context,
                  title: 'Progress',
                  subtitle: 'View Stats',
                  icon: Icons.bar_chart,
                  color: Colors.purple,
                  onTap: () => context.push('/progress'),
                   delay: 200,
                ),
                _buildActionCard(
                  context,
                  title: 'Voice Drills',
                  subtitle: 'Breath Work',
                  icon: Icons.graphic_eq,
                  color: Colors.orange,
                  onTap: () => context.push('/voice_practice'),
                   delay: 300,
                ),
                 _buildActionCard(
                  context,
                  title: 'Find Specialist',
                  subtitle: 'Connect w/ SLP',
                  icon: Icons.health_and_safety,
                  color: Colors.teal,
                  onTap: () => context.push('/slp_list'),
                   delay: 400,
                ),
                _buildActionCard(
                  context,
                  title: 'Appointments',
                  subtitle: 'Schedule',
                  icon: Icons.calendar_month,
                  color: Colors.blueAccent,
                  onTap: () => context.push('/patient_appointments'),
                   delay: 500,
                ),
              ],
            ),
          ],
        ),
     );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required int delay,
  }) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black26,
      borderOnForeground: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        hoverColor: color.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
               Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: delay)).scale(delay: Duration(milliseconds: delay));
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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
            child: Icon(Icons.graphic_eq, color: AppTheme.primaryColor, size: 32),
          ),
          destinations: const [
             NavigationRailDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: Text('Home'),
            ),
             NavigationRailDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: Text('Settings'),
            ),
            // Add more sidebar items as needed (e.g. Logout)
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
      appBar: AppBar(
        title: const Text('Dashboard'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
           IconButton(
            icon: const Icon(Icons.logout),
             onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if(context.mounted) context.go('/login');
             },
           )
        ],
      ),
      body: body,
      // We can add BottomNavigationBar here if we want multiple root tabs on mobile
    );
  }
}
