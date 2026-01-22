import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:speech_therapy/src/features/slp/presentation/slp_patients_screen.dart';
import 'package:speech_therapy/src/features/slp/presentation/slp_appointments_screen.dart';
import 'package:speech_therapy/src/core/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class SLPDashboard extends StatefulWidget {
  const SLPDashboard({super.key});

  @override
  State<SLPDashboard> createState() => _SLPDashboardState();
}

class _SLPDashboardState extends State<SLPDashboard> {
  int _currentIndex = 0;
  String? _lastHandledRoomId;

  @override
  void initState() {
    super.initState();
    // Start listening for calls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final callProvider = context.read<CallProvider>();
      callProvider.listenForIncomingCalls();
      callProvider.addListener(_onCallStateChanged);
    });
  }

  @override
  void dispose() {
    // context.read<CallProvider>().removeListener(_onCallStateChanged); // Safe to omit if provider persists
    super.dispose();
  }

  void _onCallStateChanged() async {
    if (!mounted) return;
    final callProvider = context.read<CallProvider>();
    
    // Reset if no call
    if (!callProvider.hasIncomingCall) {
       _lastHandledRoomId = null;
       return;
    }

    final data = callProvider.incomingCallData;
    final incomingRoomId = data?['roomId'];
    
    // Prevent duplicate handling for same room
    if (incomingRoomId == null || _lastHandledRoomId == incomingRoomId) {
       return;
    }

    await Future.delayed(const Duration(seconds: 2));
    
    // Re-check validity after delay
    if (!mounted || !callProvider.hasIncomingCall) return;
    final currentData = callProvider.incomingCallData;
    if (currentData == null || currentData['roomId'] != incomingRoomId) return;
    
    // Check if we are already on that screen (double safety)
    final isAlreadyIncoming = GoRouterState.of(context).uri.toString() == '/incoming_call';
    if (isAlreadyIncoming) return;

    // Mark as handled
    _lastHandledRoomId = incomingRoomId;

    context.push('/incoming_call', extra: {
      'callerId': data?['callerId'],
      'callerName': data?['callerName'],
      'roomId': incomingRoomId,
    });
  }
  
  // Pages
  final List<Widget> _pages = const [
     SLPHomeTab(),
     SLPPatientsScreen(),
     SLPAppointmentsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return _DesktopLayout(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              body: _pages[_currentIndex],
            );
          } else {
            return _MobileLayout(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) => setState(() => _currentIndex = index),
              body: _pages[_currentIndex],
            );
          }
        },
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  const _MobileLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
           NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Patients',
          ),
           NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Schedule',
          ),
        ],
      ),
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;

  const _DesktopLayout({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NavigationRail(
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelType: NavigationRailLabelType.all,
          leading: const Padding(
             padding: EdgeInsets.symmetric(vertical: 24),
             child: Icon(Icons.medical_services_outlined, color: AppTheme.secondaryColor, size: 32),
          ),
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: Text('Home'),
            ),
             NavigationRailDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: Text('Patients'),
            ),
             NavigationRailDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today),
              label: Text('Schedule'),
            ),
          ],
           trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                     await FirebaseAuth.instance.signOut();
                     if(context.mounted) context.go('/login');
                  },
                ),
              ),
            ),
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: body),
      ],
    );
  }
}

class SLPHomeTab extends StatelessWidget {
  const SLPHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('SLP Dashboard'),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Text(
              'Overview',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Stats Row
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    title: "Total Patients",
                    icon: Icons.people,
                    color: Colors.blue,
                    stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'Patient').snapshots(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    context,
                    title: "Upcoming Appts",
                    icon: Icons.calendar_today,
                    color: Colors.orange,
                    stream: FirebaseFirestore.instance
                        .collection('appointments')
                        .where('slpId', isEqualTo: user?.uid)
                        .where('status', isEqualTo: 'upcoming')
                        .snapshots(),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Activity Chart Section
            Text(
              'Patient Activity Trends',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              height: 250, // Slightly taller for the chart
              padding: const EdgeInsets.only(right: 24, left: 12, top: 24, bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0,4))
                ]
              ),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          const style = TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey,
                          );
                          Widget text;
                          switch (value.toInt()) {
                            case 0: text = const Text('Mon', style: style); break;
                            case 1: text = const Text('Tue', style: style); break;
                            case 2: text = const Text('Wed', style: style); break;
                            case 3: text = const Text('Thu', style: style); break;
                            case 4: text = const Text('Fri', style: style); break;
                            case 5: text = const Text('Sat', style: style); break;
                            case 6: text = const Text('Sun', style: style); break;
                            default: text = const Text('', style: style);
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: text,
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: 6,
                  minY: 0,
                  maxY: 6,
                  lineBarsData: [
                    LineChartBarData(
                      spots: const [
                        FlSpot(0, 3),
                        FlSpot(1, 1),
                        FlSpot(2, 4),
                        FlSpot(3, 2),
                        FlSpot(4, 5),
                        FlSpot(5, 3),
                        FlSpot(6, 4),
                      ],
                      isCurved: true,
                      gradient: const LinearGradient(
                        colors: [Colors.blueAccent, Colors.purpleAccent],
                      ),
                      barWidth: 5,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            Colors.blueAccent.withValues(alpha: 0.3),
                            Colors.purpleAccent.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn().slideY(begin: 0.1, end: 0),

            const SizedBox(height: 32),

            // Quick Actions
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildActionCard(
                  context,
                  title: "Add Training Data",
                  subtitle: "Upload voice samples",
                  icon: Icons.graphic_eq,
                  color: Colors.purple,
                  onTap: () {
                     // Placeholder action
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Training Data Upload Module - Coming Soon")));
                  },
                ),
                _buildActionCard(
                  context,
                  title: "Assign Homework",
                  subtitle: "Create new tasks",
                  icon: Icons.assignment_add,
                  color: Colors.teal,
                  onTap: () {
                     // Need to select a patient first, so maybe redirect to Patient list or show generic dialog
                     // For now, redirect to patient list as it's the logical flow
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a patient from the 'Patients' tab first.")));
                  },
                ),
                 _buildActionCard(
                  context,
                  title: "Generate Report",
                  subtitle: "Monthly summaries",
                  icon: Icons.summarize,
                  color: Colors.indigo,
                  onTap: () {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Report Generation - Coming Soon")));
                  },
                ),
              ],
            ),
            
             const SizedBox(height: 32),
             
             // Test Call
            Center(
               child: TextButton.icon(
                 onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                       try {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sending Test Signal...')));
                         await context.read<CallProvider>().initiateCall(
                           calleeId: user.uid,
                           callerName: "Self Test",
                           callerImage: "",
                         );
                       } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test Failed: $e'), backgroundColor: Colors.red));
                       }
                    }
                 },
                 icon: const Icon(Icons.bug_report, size: 16),
                 label: const Text("Debug: Test Call Signal"),
               ),
             ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, {required String title, required IconData icon, required Color color, required Stream<QuerySnapshot> stream}) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
             border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
             boxShadow: [
               BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0,4))
             ]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                count.toString(),
                style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              Text(
                title,
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ],
          ),
        );
      },
    );
  }



  Widget _buildActionCard(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color color, required VoidCallback onTap}) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const Spacer(),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    ).animate().scale();
  }
}
