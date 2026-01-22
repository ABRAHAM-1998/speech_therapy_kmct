import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';

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

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 800;
              if (isDesktop) {
                 return GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 400,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 24,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) => _buildSLPCard(context, docs[index], index, true),
                 );
              } else {
                 return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) => _buildSLPCard(context, docs[index], index, false),
                 );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildSLPCard(BuildContext context, DocumentSnapshot doc, int index, bool isGrid) {
      final data = doc.data() as Map<String, dynamic>;
      final slpName = data['fullName'] ?? 'Dr. Specialist';
      final slpEmail = data['email'] ?? 'No Email';
      final slpImage = data['profileImage'] ?? 'https://i.pravatar.cc/150?u=${doc.id}';
      final slpId = doc.id;

      final cardContent = isGrid 
        ? Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
                CircleAvatar(backgroundImage: NetworkImage(slpImage), radius: 40),
                const SizedBox(height: 16),
                Text(slpName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                Text(slpEmail, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                       onPressed: () => context.push('/specialist_profile', extra: {'slpData': data, 'slpId': slpId}),
                       child: const Text("Profile"),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                        onPressed: () => _initiateCall(context, slpId, slpName, slpImage),
                        icon: const Icon(Icons.videocam),
                        label: const Text("Call"),
                    )
                  ],
                )
             ],
          ),
        )
        : ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(backgroundImage: NetworkImage(slpImage), radius: 28),
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
              onTap: () => context.push('/specialist_profile', extra: {'slpData': data, 'slpId': slpId}),
              trailing: IconButton.filled(
                onPressed: () => _initiateCall(context, slpId, slpName, slpImage),
                icon: const Icon(Icons.videocam),
                tooltip: 'Connect',
              ),
           );

      return Card(
        elevation: isGrid ? 4 : 2,
        margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
         child: cardContent,
      ).animate().fadeIn(delay: (index * 100).ms).slideY(begin: 0.1, end: 0);
  }

  Future<void> _initiateCall(BuildContext context, String slpId, String slpName, String slpImage) async {
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
           'userId': slpId,
           'userName': slpName,
           'userImage': slpImage,
        });
      }
    } catch (e) {
      if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
    }
  }
}
