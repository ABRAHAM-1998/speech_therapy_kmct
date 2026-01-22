import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:speech_therapy/src/features/slp/data/appointment_repository.dart';

class SLPAppointmentsScreen extends StatelessWidget {
  const SLPAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Please Log In'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appointments'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.calendar_month)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: AppointmentRepository().getAppointmentsForSLP(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
             return Center(
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                    const Icon(Icons.event_busy, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No Appointments Yet', style: Theme.of(context).textTheme.titleMedium),
                 ],
               ),
             );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final patientName = data['patientName'] ?? 'Unknown';
              final DateTime date = DateTime.tryParse(data['dateTime']) ?? DateTime.now();
              final status = data['status'] ?? 'upcoming';
              
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(DateFormat('MMM').format(date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent)),
                        Text(DateFormat('d').format(date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent)),
                      ],
                    ),
                  ),
                  title: Text(patientName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${DateFormat('h:mm a').format(date)} • Therapy Session"),
                  trailing: Chip(
                    label: Text(status.toUpperCase(), style: const TextStyle(fontSize: 10)),
                    backgroundColor: status == 'upcoming' ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                    labelStyle: TextStyle(color: status == 'upcoming' ? Colors.green : Colors.grey),
                  ),
                  onTap: () {
                     showDialog(
                       context: context,
                       builder: (ctx) => AlertDialog(
                         title: Text("Manage Appointment"),
                         content: Text("Action for $patientName at ${DateFormat('h:mm a').format(date)}"),
                         actions: [
                           if (status != 'cancelled')
                             TextButton(
                               onPressed: () async {
                                 Navigator.pop(ctx);
                                 await AppointmentRepository().updateStatus(data['id'], 'cancelled');
                               },
                               child: const Text("Cancel", style: TextStyle(color: Colors.red)),
                             ),
                           if (status != 'completed')
                             ElevatedButton(
                               onPressed: () async {
                                 Navigator.pop(ctx);
                                 await AppointmentRepository().updateStatus(data['id'], 'completed');
                               },
                               child: const Text("Mark Complete"),
                             ),
                           TextButton(
                             onPressed: () => Navigator.pop(ctx),
                             child: const Text("Close"),
                           ),
                         ],
                       ),
                     );
                  },
                ),
              ).animate().fadeIn(delay: (index * 100).ms).slideX();
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
