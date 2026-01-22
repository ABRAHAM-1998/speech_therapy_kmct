import 'package:flutter/material.dart';
import 'package:speech_therapy/src/features/auth/data/auth_repository.dart';
import 'package:speech_therapy/src/features/dashboard/presentation/patient_dashboard.dart';
import 'package:speech_therapy/src/features/dashboard/presentation/slp_dashboard.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _userRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final role = await AuthRepository().getUserRole();
    if (mounted) {
      setState(() {
        _userRole = role;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_userRole == 'SLP') {
      return const SLPDashboard();
    }

    // Default to Patient Dashboard if role is Patient or unknown/null
    return const PatientDashboard();
  }
}
