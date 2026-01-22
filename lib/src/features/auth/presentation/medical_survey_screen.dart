import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_therapy/src/features/auth/data/auth_repository.dart';
import 'package:flutter_animate/flutter_animate.dart';

class MedicalSurveyScreen extends StatefulWidget {
  const MedicalSurveyScreen({super.key});

  @override
  State<MedicalSurveyScreen> createState() => _MedicalSurveyScreenState();
}

class _MedicalSurveyScreenState extends State<MedicalSurveyScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _historyController = TextEditingController();
  
  String _gender = 'Male';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _historyController.dispose();
    super.dispose();
  }

  Future<void> _submitSurvey() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);

    try {
      final data = {
        'fullName': _nameController.text.trim(),
        'age': int.tryParse(_ageController.text) ?? 0,
        'gender': _gender,
        'contactNumber': _phoneController.text.trim(),
        'medicalHistory': _historyController.text.trim(),
        'isProfileComplete': true,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      await AuthRepository().saveUserProfile(data);
      
      if (mounted) {
         context.go('/dashboard'); 
      }
    } catch (e) {
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error saving profile: $e'), backgroundColor: Colors.red),
         );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Your Profile')),
      body: Center(
        child: ConstrainedBox(
           constraints: const BoxConstraints(maxWidth: 600),
           child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Help us personalize your therapy by providing some basic details.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Please enter your name' : null,
                  ).animate().fadeIn(delay: 100.ms),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ageController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Age',
                            prefixIcon: Icon(Icons.calendar_today),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            prefixIcon: Icon(Icons.people),
                            border: OutlineInputBorder(),
                          ),
                          items: ['Male', 'Female', 'Other']
                              .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                              .toList(),
                          onChanged: (v) => setState(() => _gender = v!),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 16),
    
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact Number',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Please enter contact number' : null,
                  ).animate().fadeIn(delay: 300.ms),
                  const SizedBox(height: 16),
    
                  TextFormField(
                    controller: _historyController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Medical History / Speech Issues',
                      alignLabelWithHint: true,
                      prefixIcon: Icon(Icons.history_edu),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.length < 10 ? 'Please describe briefly' : null,
                  ).animate().fadeIn(delay: 400.ms),
                  const SizedBox(height: 32),
    
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submitSurvey,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _isSubmitting 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save & Continue', style: TextStyle(fontSize: 18)),
                  ).animate().fadeIn(delay: 500.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
