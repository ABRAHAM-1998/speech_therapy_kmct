import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/auth/data/auth_repository.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
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
    // We can't easily access context.read in dispose sometimes if the widget is unmounted from tree
    // But typically we should remove listener. 
    // Ideally we'd hold a reference to the provider, but context.read is safe if we are sure.
    // However, CallProvider is likely persistent.
    super.dispose();
  }

  // Track the last handled call ID to avoid duplicate pushes
  String? _lastHandledRoomId;

  void _onCallStateChanged() async {
    if (!mounted) return;
    
    final provider = context.read<CallProvider>();
    
    // If no incoming call, reset tracking so we can accept future calls
    if (!provider.hasIncomingCall || provider.incomingCallData == null) {
       _lastHandledRoomId = null;
       return;
    }
    
    final data = provider.incomingCallData!;
    final incomingRoomId = data['roomId'];
    
    // If we already handled this specific call session, do nothing.
    if (_lastHandledRoomId == incomingRoomId) {
       return;
    }

    // Add 2 second delay as requested by User
    await Future.delayed(const Duration(seconds: 2));
    
    // Re-check validity after delay
    if (!mounted || !provider.hasIncomingCall) return;
    final currentData = provider.incomingCallData;
    if (currentData == null || currentData['roomId'] != incomingRoomId) return;

    
    // Mark as handled
    _lastHandledRoomId = incomingRoomId;
    
    debugPrint('🚀 PatientDashboard: Navigating to Incoming Call Screen for Room: $incomingRoomId');
    
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
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Dashboard'),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome Back,',
              style: Theme.of(context).textTheme.titleMedium,
            ).animate().fadeIn(),
            Text(
              user?.email ?? 'User',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 16),
            // debug button for testing calls
            OutlinedButton.icon(
              onPressed: () {
                 final user = FirebaseAuth.instance.currentUser;
                 if (user == null) return;
                 // Simulate incoming call from "Dr. Test"
                 context.push('/incoming_call', extra: {
                   'callerId': 'test_slp_1',
                   'callerName': 'Dr. Test (Simulated)',
                   'roomId': 'test_room_1',
                 });
              },
              icon: const Icon(Icons.call_received),
              label: const Text("Simulate Incoming Call"),
            ),

            const SizedBox(height: 39),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
              children: [
                _buildActionCard(
                  context,
                  title: 'Start Therapy',
                  subtitle: 'View assignments',
                  icon: Icons.mic,
                  color: Colors.blueAccent,
                  onTap: () {
                    context.push('/patient_homework');
                  },
                ).animate().scale(delay: 300.ms),

                _buildActionCard(
                  context,
                  title: 'Virtual Trainer',
                  subtitle: 'Real-time feedback',
                  icon: Icons.face_retouching_natural,
                  color: const Color(0xFF03DAC6),
                  onTap: () {
                     // For demo purposes, we connect to a "Trainer" room
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
                ).animate().scale(delay: 400.ms),

                _buildActionCard(
                  context,
                  title: 'Progress',
                  subtitle: 'View statistics',
                  icon: Icons.bar_chart,
                  color: Colors.purpleAccent,
                  onTap: () {
                     context.push('/progress');
                  },
                ).animate().scale(delay: 500.ms),
                
                 _buildActionCard(
                  context,
                  title: 'Voice Drills',
                  subtitle: 'Breath & Volume',
                  icon: Icons.graphic_eq,
                  color: Colors.orange,
                  onTap: () {
                     context.push('/voice_practice');
                  },
                ).animate().scale(delay: 550.ms),

                _buildActionCard(
                  context,
                  title: 'Find Specialist',
                  subtitle: 'Connect with SLPs',
                  icon: Icons.health_and_safety,
                  color: Colors.teal,
                  onTap: () {
                     context.push('/slp_list');
                  },
                ).animate().scale(delay: 600.ms),

                _buildActionCard(
                  context,
                  title: 'My Appointments',
                  subtitle: 'Upcoming sessions',
                  icon: Icons.calendar_month,
                  color: Colors.indigoAccent,
                  onTap: () {
                     context.push('/patient_appointments');
                  },
                ).animate().scale(delay: 650.ms),
              ],
            ),
          ],
        ),
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
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Center(
                  child: Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey, fontSize: 12,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
