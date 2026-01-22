import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SLPPatientsScreen extends StatelessWidget {
  const SLPPatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Patients'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.filter_list)),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'Patient')
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
                    const Icon(Icons.group_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('No patients found', style: Theme.of(context).textTheme.titleMedium),
                 ],
               ),
             );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 900;
              
              if (isDesktop) {
                 return GridView.builder(
                   padding: const EdgeInsets.all(24),
                   gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                     crossAxisCount: 3,
                     crossAxisSpacing: 24,
                     mainAxisSpacing: 24,
                     childAspectRatio: 2.2,
                   ),
                   itemCount: docs.length,
                   itemBuilder: (context, index) {
                     return _buildPatientCard(context, docs[index], index);
                   },
                 );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  return _buildPatientCard(context, docs[index], index);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.person_add),
        label: const Text('Add Patient'),
      ),
    );
  }

  Widget _buildPatientCard(BuildContext context, DocumentSnapshot doc, int index) {
     final data = doc.data() as Map<String, dynamic>;
     final patientName = data['fullName'] ?? 'Unknown Patient';
     final patientEmail = data['email'] ?? '';
     final patientId = doc.id;
     final condition = data['condition'] ?? 'No diagnosis';
     final age = data['age']?.toString() ?? '--'; 

     return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          context.push('/patient_details', extra: {
            ...data,
            'id': patientId,
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row( // Using Row even for grid to keep consistent 'ListTile-like' structure inside the card
            children: [
               CircleAvatar(
                radius: 28,
                backgroundColor: Colors.teal.shade100,
                child: Text(
                  (patientName.isNotEmpty ? patientName[0] : '?').toUpperCase(),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      patientName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                     const SizedBox(height: 4),
                     Text("$condition • $age yrs", style: const TextStyle(fontSize: 13, color: Colors.grey)),
                     const SizedBox(height: 4),
                     Row(
                       children: [
                         Icon(Icons.email_outlined, size: 14, color: Colors.grey[600]),
                         const SizedBox(width: 4),
                         Expanded(child: Text(patientEmail, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
                       ],
                     )
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: (index * 50).ms).slideX();
  }
}
