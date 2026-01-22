import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/slp/data/appointment_repository.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';

class PatientAppointmentsScreen extends StatelessWidget {
  const PatientAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view appointments.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Appointments'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: AppointmentRepository().getAppointmentsForPatient(userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.calendar_today_outlined, size: 64, color: Colors.grey),
                   const SizedBox(height: 16),
                   Text(
                    'No upcoming appointments.',
                    style: Theme.of(context).textTheme.titleMedium,
                   ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final dateStr = data['dateTime'] as String;
              final dateTime = DateTime.parse(dateStr);
              final slpName = data['slpName'] ?? 'Specialist';
              final status = data['status'] ?? 'upcoming';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    child: Icon(Icons.calendar_month, color: Theme.of(context).primaryColor),
                  ),
                  title: Text(
                    slpName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('EEE, MMM d • h:mm a').format(dateTime),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                       Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: status == 'upcoming' ? Colors.blue.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: status == 'upcoming' ? Colors.blue.shade800 : Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: status == 'upcoming'
                      ? IconButton(
                          icon: const Icon(Icons.videocam, color: Colors.green),
                          onPressed: () async {
                             // Initiate Call Logic
                             try {
                               final slpId = data['slpId'];
                               if (slpId == null) throw 'SLP ID missing in appointment';
                               
                               final myName = FirebaseAuth.instance.currentUser?.displayName ?? 'Patient';
                               final myImage = FirebaseAuth.instance.currentUser?.photoURL ?? 'https://i.pravatar.cc/150';

                               final roomId = await context.read<CallProvider>().initiateCall(
                                  calleeId: slpId,
                                  callerName: myName,
                                  callerImage: myImage,
                               );

                               if (context.mounted) {
                                 context.push('/video_call', extra: {
                                    'roomId': roomId,
                                    'isCaller': true,
                                    'userId': slpId, 
                                    'userName': slpName, 
                                    'userImage': null, // Can fetch if needed
                                 });
                               }
                             } catch (e) {
                               if (context.mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
                               }
                             }
                          },
                        )
                      : null,
                ),
              ).animate().fadeIn(delay: (index * 100).ms).slideX();
            },
          );
        },
      ),
    );
  }
}
