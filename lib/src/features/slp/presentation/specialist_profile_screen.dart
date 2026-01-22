import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:speech_therapy/src/features/slp/presentation/book_appointment_sheet.dart';

class SpecialistProfileScreen extends StatelessWidget {
  final Map<String, dynamic> slpData;
  final String slpId;

  const SpecialistProfileScreen({
    super.key, 
    required this.slpData,
    required this.slpId,
  });

  @override
  Widget build(BuildContext context) {
    final name = slpData['fullName'] ?? 'Dr. Specialist';
    final email = slpData['email'] ?? 'Contact info hidden';
    final image = slpData['profileImage'] ?? 'https://i.pravatar.cc/150?u=$slpId';
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(name),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(image, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.teal)),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Info
                  Row(
                    children: [
                      Chip(label: const Text("Speech Therapist"), backgroundColor: Colors.teal.withValues(alpha: 0.1)),
                      const SizedBox(width: 8),
                      const Row(children: [Icon(Icons.star, size: 16, color: Colors.amber), Text(" 4.9 (24)")]),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  const Text("About", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    "Certified Speech-Language Pathologist with over 8 years of experience in treating articulation disorders and aphasia. Dedicated to helping patients achieve their communication goals through personalized therapy plans.",
                    style: TextStyle(color: Colors.grey[700], height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  
                  const Text("Specializations", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: const [
                      Chip(label: Text("Articulation")),
                      Chip(label: Text("Stuttering")),
                      Chip(label: Text("Aphasia")),
                      Chip(label: Text("Pediatric")),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Call Action
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => _initiateCall(context),
                      icon: const Icon(Icons.videocam),
                      label: const Text("Start Video Consultation"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ).animate().scale(delay: 200.ms),
                   const SizedBox(height: 16),
                   SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => BookAppointmentSheet(slpData: slpData, slpId: slpId),
                        );
                      },
                      icon: const Icon(Icons.calendar_month),
                      label: const Text("Book Appointment"),
                    ),
                  ).animate().scale(delay: 300.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initiateCall(BuildContext context) async {
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      if (user == null) return;

      final myName = user.displayName ?? user.email ?? 'Patient';
      final myImage = user.photoURL ?? 'https://i.pravatar.cc/150?u=${user.uid}';

      final roomId = await context.read<CallProvider>().initiateCall(
        calleeId: slpId,
        callerName: myName, // Send MY name
        callerImage: myImage,
      );

      if (context.mounted) {
        context.push('/video_call', extra: {
           'roomId': roomId,
           'isCaller': true,
           'userId': slpId, // Remote User ID (The SLP)
           'userName': slpData['fullName'] ?? 'Specialist', // Remote User Name
           'userImage': slpData['profileImage'],
        });
      }
    } catch (e) {
      if(context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
      }
    }
  }
}
