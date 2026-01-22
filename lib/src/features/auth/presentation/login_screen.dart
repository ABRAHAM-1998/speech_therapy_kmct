import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speech_therapy/src/features/auth/data/auth_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await AuthRepository().signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login Successful!')),
        );
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login Failed. Check credentials.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _DesktopLayout(
              emailController: _emailController,
              passwordController: _passwordController,
              isLoading: _isLoading,
              onLogin: _login,
            );
          } else {
            return _MobileLayout(
              emailController: _emailController,
              passwordController: _passwordController,
              isLoading: _isLoading,
              onLogin: _login,
            );
          }
        },
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onLogin;

  const _MobileLayout({
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundColor == const Color(0xFF0F172A) // Check if dark theme
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
                _buildHeader(context),
                const SizedBox(height: 48),
                _LoginForm(
                  emailController: emailController,
                  passwordController: passwordController,
                  isLoading: isLoading,
                  onLogin: onLogin,
                ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2, end: 0),
                const SizedBox(height: 24),
                _buildRegisterLink(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onLogin;

  const _DesktopLayout({
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.onLogin,
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
                // Abstract Shapes via Circles
                Positioned(
                  top: -100,
                  left: -100,
                  child: Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -150,
                  right: -100,
                  child: Container(
                    width: 500,
                    height: 500,
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
                        Icons.graphic_eq, // Or a dedicated logo image
                        size: 120,
                        color: Colors.white,
                      ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),
                      const SizedBox(height: 32),
                      Text(
                        'Speech AI Trainer',
                        style: GoogleFonts.outfit(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ).animate().fadeIn(delay: 200.ms).slideX(),
                      const SizedBox(height: 16),
                      Text(
                        'Your dedicated partner in speech rehabilitation.',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          color: Colors.white70,
                        ),
                      ).animate().fadeIn(delay: 400.ms),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right Side - Form
        Expanded(
          flex: 4,
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
               child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome Back',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          fontSize: 32,
                        ),
                      ).animate().fadeIn(delay: 400.ms),
                      const SizedBox(height: 8),
                      Text(
                        'Please enter your details to sign in.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 48),
                      _LoginForm(
                         emailController: emailController,
                         passwordController: passwordController,
                         isLoading: isLoading,
                         onLogin: onLogin
                      ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.1, end: 0),
                      const SizedBox(height: 32),
                      Center(child: _buildRegisterLink(context)),
                    ],
                  ),
               ),
            ),
          ),
        ),
      ],
    );
  }
}

Widget _buildHeader(BuildContext context) {
  return Column(
    children: [
      const Icon(
        Icons.graphic_eq,
        size: 80,
        color: AppTheme.secondaryColor,
      ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
      const SizedBox(height: 24),
      Text(
        'Speech AI Trainer',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onBackground,
        ),
      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3, end: 0),
      const SizedBox(height: 8),
      Text(
        'Your Personal Speech Companion',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ).animate().fadeIn(delay: 400.ms),
    ],
  );
}

Widget _buildRegisterLink(BuildContext context) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        "Don't have an account?",
        style: TextStyle(color: AppTheme.textSecondary),
      ),
      TextButton(
        onPressed: () => context.push('/register'),
        child: const Text('Create Account'),
      ),
    ],
  );
}

class _LoginForm extends StatelessWidget {
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onLogin;

  const _LoginForm({
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: emailController,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: const InputDecoration(
            labelText: 'Email Address',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: passwordController,
          obscureText: true,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
         Align(
          alignment: Alignment.centerRight,
           child: TextButton(
            onPressed: () {}, // Forgot password placeholder
            child: const Text('Forgot Password?'),
           ),
         ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: isLoading ? null : onLogin,
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Sign In'),
          ),
        ),
      ],
    );
  }
}
