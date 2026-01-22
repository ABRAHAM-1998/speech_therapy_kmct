import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';

class SLPListScreen extends StatelessWidget {
  const SLPListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Speech Specialist')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'SLP')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                   const SizedBox(height: 16),
                   Text('No Specialists Found Yet', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final slpName = data['fullName'] ?? 'Dr. Specialist';
              final slpEmail = data['email'] ?? 'No Email';
              final slpImage = data['profileImage'] ?? 'https://i.pravatar.cc/150?u=${docs[index].id}';
              final slpId = docs[index].id;
              
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(slpImage),
                    radius: 28,
                  ),
                  title: Text(slpName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text(slpEmail, overflow: TextOverflow.ellipsis),
                       const SizedBox(height: 4),
                       Row(
                         mainAxisSize: MainAxisSize.min, 
                         children: [
                           const Icon(Icons.star, size: 14, color: Colors.amber),
                           const SizedBox(width: 4),
                           Expanded(
                             child: Text(
                               '4.9 (20 reviews)', 
                               style: Theme.of(context).textTheme.bodySmall,
                               overflow: TextOverflow.ellipsis,
                             ),
                           )
                         ],
                       )
                    ],
                  ),
                  onTap: () {
                    context.push('/specialist_profile', extra: {
                      'slpData': data,
                      'slpId': slpId,
                    });
                  },
                  trailing: IconButton.filled(
                    onPressed: () async {
                      // Initiate Call
                      try {
                        final auth = FirebaseAuth.instance;
                        final user = auth.currentUser;
                        if (user == null) return;
                        
                        final myName = user.displayName ?? user.email ?? 'Patient';
                        final myImage = user.photoURL ?? 'https://i.pravatar.cc/150?u=${user.uid}';

                        final roomId = await context.read<CallProvider>().initiateCall(
                          calleeId: slpId,
                          callerName: myName,
                          callerImage: myImage,
                        );

                        if (context.mounted) {
                          context.push('/video_call', extra: {
                             'roomId': roomId,
                             'isCaller': true,
                             'userId': slpId, // Remote User: The SLP
                             'userName': slpName, // Remote Name: The SLP
                             'userImage': slpImage,
                          });
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
                      }
                    },
                    icon: const Icon(Icons.videocam),
                    tooltip: 'Connect',
                  ),
                ),
              ).animate().fadeIn(delay: (index * 100).ms).slideX();
            },
          );
        },
      ),
    );
  }
}
