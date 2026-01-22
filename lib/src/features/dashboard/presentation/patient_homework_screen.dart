import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_therapy/src/features/slp/data/homework_repository.dart';
import 'package:go_router/go_router.dart';


class PatientHomeworkScreen extends StatelessWidget {
  const PatientHomeworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Login required')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Assignments')),
      body: StreamBuilder<QuerySnapshot>(
        stream: HomeworkRepository().getHomeworkForPatient(userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Error loading assignments'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                  const SizedBox(height: 16),
                  Text('All caught up!', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('No pending assignments.', style: TextStyle(color: Colors.grey)),
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
              final id = data['id'];
              final status = data['status'];
              final isCompleted = status == 'completed';

              return Card(
                elevation: isCompleted ? 0 : 4,
                color: isCompleted ? Colors.grey.shade100 : Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCompleted ? Colors.grey : Colors.orange,
                    child: Icon(
                      _getIconForType(data['type']),
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    data['title'],
                    style: TextStyle(
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                      color: isCompleted ? Colors.grey : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(data['description']),
                  trailing: isCompleted
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : ElevatedButton(
                          onPressed: () {
                             if (data['type'] == 'voice_practice') {
                               context.push('/voice_practice');
                             } else if (data['type'] == 'articulation' || data['type'] == 'reading') {
                               context.push('/live_therapy', extra: {'exerciseTitle': data['title']});
                             } else {
                               _showDetails(context, data);
                             }
                          },
                          child: const Text('Start'),
                        ),
                  onLongPress: !isCompleted ? () => _markComplete(context, id) : null,
                ),
              ).animate().slideX(delay: (index * 50).ms);
            },
          );
        },
      ),
    );
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'voice_practice': return Icons.graphic_eq;
      case 'reading': return Icons.menu_book;
      case 'articulation': return Icons.mic;
      default: return Icons.assignment;
    }
  }

  void _showDetails(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['title']),
        content: Text(data['description']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _markComplete(context, data['id']);
            },
            child: const Text('Mark Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _markComplete(BuildContext context, String id) async {
    await HomeworkRepository().completeHomework(id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as complete! Good job!')));
    }
  }
}
