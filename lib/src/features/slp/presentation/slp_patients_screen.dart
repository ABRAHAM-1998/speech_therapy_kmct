import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

class SLPPatientsScreen extends StatelessWidget {
  const SLPPatientsScreen({super.key});

  // Mock Data
  final List<Map<String, dynamic>> _patients = const [
    {
      'id': '1',
      'fullName': 'John Doe',
      'age': 45,
      'gender': 'Male',
      'condition': 'Post-Stroke Aphasia',
      'status': 'Active',
      'lastSession': '2 hours ago',
    },
    {
      'id': '2',
      'fullName': 'Emily Smith',
      'age': 8,
      'gender': 'Female',
      'condition': 'Articulation Disorder',
      'status': 'Active',
      'lastSession': 'Yesterday',
    },
    {
      'id': '3',
      'fullName': 'Michael Brown',
      'age': 62,
      'gender': 'Male',
      'condition': 'Dysarthria',
      'status': 'Pending Review',
      'lastSession': '3 days ago',
    },
    {
      'id': '4',
      'fullName': 'Sarah Wilson',
      'age': 29,
      'gender': 'Female',
      'condition': 'Stuttering',
      'status': 'Improved',
      'lastSession': '1 week ago',
    },
  ];

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
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _patients.length,
        itemBuilder: (context, index) {
          final patient = _patients[index];
          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.teal.shade100,
                child: Text(
                  patient['fullName'][0],
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ),
              title: Text(
                patient['fullName'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const SizedBox(height: 4),
                   Text("${patient['condition']} • ${patient['age']} yrs"),
                   const SizedBox(height: 4),
                   Row(
                     children: [
                       Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                       const SizedBox(width: 4),
                       Text("Last seen: ${patient['lastSession']}", style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                     ],
                   )
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              onTap: () {
                context.push('/patient_details', extra: patient);
              },
            ),
          ).animate().fadeIn(delay: (index * 100).ms).slideX();
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.person_add),
        label: const Text('Add Patient'),
      ),
    );
  }
}
