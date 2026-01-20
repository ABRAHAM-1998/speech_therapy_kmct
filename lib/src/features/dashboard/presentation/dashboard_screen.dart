import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome Back,',
              style: Theme.of(context).textTheme.titleMedium,
            ).animate().fadeIn(),
            Text(
              user?.email ?? 'User',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ).animate().fadeIn(delay: 200.ms),

            const SizedBox(height: 32),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildActionCard(
                  context,
                  title: 'Start Therapy',
                  subtitle: 'Daily exercises',
                  icon: Icons.mic,
                  color: Colors.blueAccent,
                  onTap: () {
                    // Navigate to Therapy Session
                  },
                ).animate().scale(delay: 300.ms),

                _buildActionCard(
                  context,
                  title: 'Virtual Trainer',
                  subtitle: 'Real-time feedback',
                  icon: Icons.face_retouching_natural,
                  color: const Color(0xFF03DAC6),
                  onTap: () {
                     // Navigate to Virtual Trainer
                  },
                ).animate().scale(delay: 400.ms),

                _buildActionCard(
                  context,
                  title: 'Progress',
                  subtitle: 'View statistics',
                  icon: Icons.bar_chart,
                  color: Colors.purpleAccent,
                  onTap: () {
                     // Navigate to Stats
                  },
                ).animate().scale(delay: 500.ms),
                
                 _buildActionCard(
                  context,
                  title: 'Community',
                  subtitle: 'Join peers',
                  icon: Icons.people_outline,
                  color: Colors.orangeAccent,
                  onTap: () {
                     // Navigate to Community
                  },
                ).animate().scale(delay: 600.ms),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
