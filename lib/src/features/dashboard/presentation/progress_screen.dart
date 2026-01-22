import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: Text("Please login to view progress.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Progress"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('assessments')
            .where('userId', isEqualTo: user.uid)
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.show_chart, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text("No progress recorded yet.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  const Text("Start your first therapy session to track your progress!", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/live_therapy', extra: {'exerciseTitle': 'First Session'}),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text("Start Therapy Now"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            );
          }

          // Prepare Data for Chart (Chronological)
          // We need to reverse for chart (Oldest -> Newest)
          final chronologicalDocs = docs.reversed.toList();
          
          List<FlSpot> spots = [];
          for (int i = 0; i < chronologicalDocs.length; i++) {
             final data = chronologicalDocs[i].data() as Map<String, dynamic>;
             final open = data['avg_lip_openness'];
             double val = 0.0;
             if (open is num) val = open.toDouble();
             spots.add(FlSpot(i.toDouble(), val));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Lip Mobility Trend (Pixels)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                
                // CHART
                Container(
                  height: 250,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24)
                  ),
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      titlesData: FlTitlesData(
                        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // Hide X axis dates for simplicity
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (val, meta)=> Text(val.toInt().toString(), style: const TextStyle(fontSize: 10)))),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: Colors.cyanAccent,
                          barWidth: 3,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                const Text("Validation History", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                // LIST
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final ts = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
                    final disorder = data['disorder'] ?? 'Unknown';
                    final severity = data['severity'] ?? 'N/A';
                    final openness = data['avg_lip_openness']?.toString() ?? '0';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: severity == 'None' ? Colors.green : (severity == 'Severe' ? Colors.red : Colors.orange),
                          child: Icon(severity == 'None' ? Icons.check : Icons.warning_amber, color: Colors.white),
                        ),
                        title: Text(disorder, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('MMM d, y • h:mm a').format(ts)),
                        trailing: Column(
                           mainAxisAlignment: MainAxisAlignment.center,
                           crossAxisAlignment: CrossAxisAlignment.end,
                           children: [
                             Text("O: ${double.tryParse(openness)?.toStringAsFixed(1)} px", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                             Text(severity, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                           ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
