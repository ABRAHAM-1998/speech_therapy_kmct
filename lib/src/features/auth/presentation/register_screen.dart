import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speech_therapy/src/features/auth/data/auth_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedRole = 'Patient';
  bool _isLoading = false;

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    if (_nameController.text.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your full name')));
       return;
    }

    setState(() => _isLoading = true);

    try {
      await AuthRepository().createUserWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        role: _selectedRole,
        fullName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      );
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account Created! Welcome.')),
        );
         context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Theme.of(context).colorScheme.onBackground),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _DesktopLayout(
              nameController: _nameController,
              emailController: _emailController,
              phoneController: _phoneController,
              passwordController: _passwordController,
              confirmPasswordController: _confirmPasswordController,
              selectedRole: _selectedRole,
              onRoleChanged: (val) => setState(() => _selectedRole = val!),
              isLoading: _isLoading,
              onRegister: _register,
            );
          } else {
            return _MobileLayout(
              nameController: _nameController,
              emailController: _emailController,
              phoneController: _phoneController,
              passwordController: _passwordController,
              confirmPasswordController: _confirmPasswordController,
              selectedRole: _selectedRole,
              onRoleChanged: (val) => setState(() => _selectedRole = val!),
              isLoading: _isLoading,
              onRegister: _register,
            );
          }
        },
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final String selectedRole;
  final ValueChanged<String?> onRoleChanged;
  final bool isLoading;
  final VoidCallback onRegister;

  const _MobileLayout({
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.isLoading,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
         gradient: AppTheme.backgroundColor == const Color(0xFF0F172A)
             ? const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null,
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.person_add_alt_1_outlined,
                  size: 60,
                  color: AppTheme.secondaryColor,
                ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                
                const SizedBox(height: 16),
                
                Text(
                  'Join the Platform',
                  style: Theme.of(context).textTheme.headlineMedium,
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 32),
                
                _RegisterForm(
                  nameController: nameController,
                  emailController: emailController,
                  phoneController: phoneController,
                  passwordController: passwordController,
                  confirmPasswordController: confirmPasswordController,
                  selectedRole: selectedRole,
                  onRoleChanged: onRoleChanged,
                  isLoading: isLoading,
                  onRegister: onRegister,
                ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final String selectedRole;
  final ValueChanged<String?> onRoleChanged;
  final bool isLoading;
  final VoidCallback onRegister;

  const _DesktopLayout({
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.isLoading,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Side - Branding
         Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
            ),
             child: Stack(
              children: [
                Positioned(
                  top: -100,
                  right: -100,
                  child: Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                 Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person_add_outlined, 
                        size: 100,
                        color: Colors.white,
                      ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),
                      const SizedBox(height: 32),
                      Text(
                        'Start Your Journey',
                        style: GoogleFonts.outfit(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ).animate().fadeIn(delay: 200.ms).slideX(),
                      const SizedBox(height: 16),
                      Text(
                        'Create an account to access advanced speech therapy tools.',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          color: Colors.white70,
                        ),
                      ).animate().fadeIn(delay: 400.ms),
                    ],
                  ),
                ),
              ]
             )
          ),
         ),
        // Right Side - Form
         Expanded(
          flex: 4,
          child: Container(
             color: Theme.of(context).scaffoldBackgroundColor,
             child: Center(
                child: Container(
                   constraints: const BoxConstraints(maxWidth: 500),
                   padding: const EdgeInsets.all(48),
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                        Text(
                        'Create Account',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          fontSize: 32,
                        ),
                      ).animate().fadeIn(delay: 400.ms),
                       const SizedBox(height: 32),
                       Expanded(
                         child: SingleChildScrollView(
                           child: _RegisterForm(
                            nameController: nameController,
                            emailController: emailController,
                            phoneController: phoneController,
                            passwordController: passwordController,
                            confirmPasswordController: confirmPasswordController,
                            selectedRole: selectedRole,
                            onRoleChanged: onRoleChanged,
                            isLoading: isLoading,
                            onRegister: onRegister,
                                                   ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1, end: 0),
                         ),
                       ),
                     ],
                   )
                )
             )
          )
         )
      ],
    );
  }
}

class _RegisterForm extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final String selectedRole;
  final ValueChanged<String?> onRoleChanged;
  final bool isLoading;
  final VoidCallback onRegister;

  const _RegisterForm({
     required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.selectedRole,
    required this.onRoleChanged,
    required this.isLoading,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Full Name',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone Number (Optional)',
            prefixIcon: Icon(Icons.phone),
          ),
        ),
        const SizedBox(height: 16),
         DropdownButtonFormField<String>(
          value: selectedRole,
          decoration: const InputDecoration(
            labelText: 'I am a...',
            prefixIcon: Icon(Icons.work_outline),
          ),
          dropdownColor: Theme.of(context).colorScheme.surface,
          items: ['Patient', 'SLP']
              .map((role) => DropdownMenuItem(
                    value: role,
                    child: Text(role),
                  ))
              .toList(),
          onChanged: onRoleChanged,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: confirmPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.lock_clock_outlined),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: isLoading ? null : onRegister,
            child: isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                : const Text('Sign Up'),
          ),
        ),
      ],
    );
  }
}
