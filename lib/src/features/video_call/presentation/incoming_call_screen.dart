import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';

class IncomingCallScreen extends StatelessWidget {
  final String? callerId;
  final String? callerName;
  final String? roomId;

  const IncomingCallScreen({
    super.key,
    this.callerId,
    this.callerName,
    this.roomId,
  });

  @override
  Widget build(BuildContext context) {
    final callProvider = context.watch<CallProvider>();
    final data = callProvider.incomingCallData;

    // Use passed data or fallback to provider data
    final displayCallerName = callerName ?? data?['callerName'] ?? 'Unknown Caller';
    final displayCallerImage = data?['callerImage'] ?? 'https://i.pravatar.cc/150';

    if (data == null && callerId == null) { // If neither has data, close
      // Call ended or cancelled
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pop();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Column(
              children: [
                const SizedBox(height: 40),
                Text(
                  'Incoming Call...',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white70),
                ).animate().fadeIn(),
                const SizedBox(height: 24),
                CircleAvatar(
                  radius: 64,
                  backgroundImage: NetworkImage(displayCallerImage),
                ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                const SizedBox(height: 16),
                Text(
                  displayCallerName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 200.ms),
              ],
            ),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  context: context,
                  icon: Icons.call_end,
                  color: Colors.redAccent,
                  label: 'Decline',
                  onTap: () async {
                    await callProvider.rejectCall();
                    if (context.mounted) context.pop();
                  },
                ),
                _buildActionButton(
                  context: context,
                  icon: Icons.videocam,
                  color: Colors.greenAccent,
                  label: 'Accept',
                  onTap: () async {
                    final roomId = await callProvider.acceptCall();
                    if (context.mounted && roomId != null) {
                      context.pop(); // Close incoming screen
                      context.push('/video_call', extra: {
                        'roomId': roomId,
                        'isCaller': false, // Callee is NOT caller
                        'userId': callerId ?? data?['callerId'] ?? 'unknown_caller', // The OTHER person
                        'userName': displayCallerName, // The OTHER person's name
                        'userImage': displayCallerImage,
                      });
                    }
                  },
                ),
              ],
            ).animate().slideY(begin: 1, end: 0, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                 BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 5),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 16)),
      ],
    );
  }
}
