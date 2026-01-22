import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_therapy/src/features/slp/data/homework_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PatientDetailScreen extends StatelessWidget {
  final Map<String, dynamic> patient;

  const PatientDetailScreen({super.key, required this.patient});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(patient['fullName']),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade800, Colors.teal.shade400],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.person, size: 80, color: Colors.white24),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader("Patient Info"),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              _buildInfoRow('Age', "${patient['age']?.toString() ?? '--'} years"),
                              const Divider(),
                              _buildInfoRow('Gender', patient['gender'] ?? 'Unknown'),
                              const Divider(),
                              _buildInfoRow('Condition', patient['condition'] ?? 'No diagnosis'),
                              const Divider(),
                              _buildInfoRow('Status', patient['status'] ?? 'Active'),
                            ],
                          ),
                        ),
                      ).animate().fadeIn().slideY(begin: 0.1, end: 0),
    
                      const SizedBox(height: 24),
                      _buildSectionHeader("Medical History / Notes"),
                       Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            "Patient shows signs of ${patient['condition'] ?? 'their condition'}. Recommended daily exercises focusing on articulation and rhythm. Progress has been steady.",
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                        ),
                      ).animate().fadeIn(delay: 200.ms),
    
                      const SizedBox(height: 24),
                      _buildSectionHeader("Actions"),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                 // Initiate Video Call
                                 context.push(
                                   '/video_call',
                                   extra: {
                                     'roomId': 'room_${patient['id']}', 
                                     'isCaller': true,
                                     'userId': patient['id'],
                                     'userName': patient['fullName'],
                                     'userImage': 'https://i.pravatar.cc/150?u=${patient['id']}', 
                                   },
                                 );
                              },
                              icon: const Icon(Icons.videocam),
                              label: const Text("Call"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                context.push('/live_therapy', extra: {'exerciseTitle': 'General Session'});
                              },
                              icon: const Icon(Icons.auto_awesome),
                              label: const Text("Start Therapy"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showHomeworkDialog(context),
                              icon: const Icon(Icons.assignment_add),
                              label: const Text("Homework"),
                               style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                 foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(delay: 400.ms),
                      
                      const SizedBox(height: 24),
                      
                       _buildSectionHeader("Assigned Homework (Active)"),
                      StreamBuilder<QuerySnapshot>(
                        stream: HomeworkRepository().getHomeworkForPatient(patient['id']),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                             return const Card(
                               child: Padding(
                                 padding: EdgeInsets.all(16.0),
                                 child: Text("No active homework assignments."),
                               ),
                             );
                          }
                          
                          final docs = snapshot.data!.docs;
                          return Card(
                            child: Column(
                              children: docs.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                return Column(
                                  children: [
                                    ListTile(
                                      leading: Icon(
                                        data['type'] == 'voice_practice' ? Icons.graphic_eq : Icons.assignment,
                                        color: Colors.orange,
                                      ),
                                      title: Text(data['title']),
                                      subtitle: Text(data['description']),
                                      trailing: data['status'] == 'completed' 
                                          ? const Icon(Icons.check_circle, color: Colors.green)
                                          : const Icon(Icons.pending_outlined, color: Colors.orange),
                                    ),
                                    const Divider(height: 1),
                                  ],
                                );
                              }).toList(),
                            ),
                          ).animate().fadeIn(delay: 500.ms);
                        },
                      ),
                      
                      const SizedBox(height: 24),
                      _buildSectionHeader("Recent Sessions"),
                      // Mock Session History
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 3,
                        itemBuilder: (context, index) {
                          return ListTile(
                             leading: const Icon(Icons.history),
                             title: Text("Session #${3-index}"),
                             subtitle: Text("Date: 2024-01-2${index+5}"),
                             trailing: const Text("Completed", style: TextStyle(color: Colors.green)),
                          );
                        },
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showHomeworkDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Assign Homework"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text("Volume Control Game"),
              onTap: () => _assignHomework(context, 'Volume Control Game', 'Practice breath control', 'voice_practice'),
            ),
             ListTile(
              leading: const Icon(Icons.mic),
              title: const Text("Articulation: 'R' Sound"),
              onTap: () => _assignHomework(context, "Articulation: 'R' Sound", "Practice rolling R words", 'articulation'),
            ),
             ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text("Reading: The North Wind"),
               onTap: () => _assignHomework(context, "Reading: The North Wind", "Read aloud and record", 'reading'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ],
      ),
    );
  }

  Future<void> _assignHomework(BuildContext context, String title, String description, String type) async {
     Navigator.pop(context);
     final slpId = FirebaseAuth.instance.currentUser?.uid;
     if (slpId == null) return;

     await HomeworkRepository().assignHomework(
       patientId: patient['id'],
       slpId: slpId,
       title: title,
       description: description,
       type: type,
     );

     if (context.mounted) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Assigned: $title")));
     }
  }
}
