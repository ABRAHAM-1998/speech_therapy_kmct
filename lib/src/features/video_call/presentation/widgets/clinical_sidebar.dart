
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClinicalSidebar extends StatefulWidget {
  final String roomId;
  final String patientId;
  final String patientName;
  final Map<String, dynamic> aiStats;

  const ClinicalSidebar({
    super.key,
    required this.roomId,
    required this.patientId,
    required this.patientName,
    required this.aiStats,
  });

  @override
  State<ClinicalSidebar> createState() => _ClinicalSidebarState();
}

class _ClinicalSidebarState extends State<ClinicalSidebar> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _assessmentController = TextEditingController();
  bool _isSavingNote = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _notesController.dispose();
    _assessmentController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (_notesController.text.isEmpty) return;
    setState(() => _isSavingNote = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Save to a private sub-collection or realtime node for the SLP
        await FirebaseDatabase.instance
            .ref('users/${widget.patientId}/clinical_notes')
            .push()
            .set({
          'authorId': user.uid,
          'text': _notesController.text,
          'timestamp': ServerValue.timestamp,
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Note saved successfully')),
          );
          _notesController.clear();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error saving note: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingNote = false);
    }
  }

  Future<void> _sendAssessmentTask() async {
     if (_assessmentController.text.isEmpty) return;
     
     try {
       await FirebaseDatabase.instance
           .ref('video_rooms/${widget.roomId}/active_task')
           .set({
         'text': _assessmentController.text,
         'timestamp': ServerValue.timestamp,
         'type': 'reading',
       });
       
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task sent to patient')),
          );
        }
     } catch (e) {
       debugPrint('Error sending task: $e');
     }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          _buildHeader(),
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.cyanAccent,
            labelColor: Colors.cyanAccent,
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(icon: Icon(Icons.person_outline), text: "Info"),
              Tab(icon: Icon(Icons.assignment_outlined), text: "Tasks"),
              Tab(icon: Icon(Icons.edit_note), text: "Notes"),
              Tab(icon: Icon(Icons.analytics_outlined), text: "AI"),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInfoTab(),
                _buildAssessmentTab(),
                _buildNotesTab(),
                _buildAITab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.black26,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.cyanAccent,
            child: Text(widget.patientName.isNotEmpty ? widget.patientName[0] : 'P'),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.patientName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  "Patient ID: ${widget.patientId.substring(0, 5)}...",
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        _InfoCard(title: "Diagnosis", value: "Apraxia of Speech"),
        _InfoCard(title: "Age", value: "34 years"),
        _InfoCard(title: "Next Session", value: "Jan 25, 2026"),
        _InfoCard(title: "Goals", value: "Improve articulation of /r/ and /s/ sounds."),
      ],
    );
  }

  Widget _buildAssessmentTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Assign Reading Task", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Enter text for the patient to read aloud. It will appear on their screen.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            controller: _assessmentController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "E.g. The quick brown fox jumps over the lazy dog.",
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text("Send to Patient"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan,
                foregroundColor: Colors.black,
              ),
              onPressed: _sendAssessmentTask,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _notesController,
              expands: true,
              maxLines: null,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter clinical observations...",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSavingNote 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.save),
              label: const Text("Save Clinical Note"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: _isSavingNote ? null : _saveNote,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAITab() {
    final lipScore = ((widget.aiStats['lipAccuracy'] as num?) ?? 0.0).toDouble();
    final pronScore = ((widget.aiStats['pronunciation'] as num?) ?? 0.0).toDouble();
    final feedback = widget.aiStats['feedback'] as String? ?? 'No analysis yet...';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatCard(title: "Real-time Feedback", content: feedback, isHighlight: true),
        const SizedBox(height: 16),
        const Text("Metrics", style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _MetricBar(label: "Lip Accuracy", value: lipScore, color: Colors.blueAccent),
        const SizedBox(height: 12),
        _MetricBar(label: "Pronunciation", value: pronScore, color: Colors.greenAccent),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  const _InfoCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String content;
  final bool isHighlight;
  const _StatCard({required this.title, required this.content, this.isHighlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isHighlight ? Colors.cyan.withOpacity(0.1) : Colors.white10,
        border: isHighlight ? Border.all(color: Colors.cyanAccent.withOpacity(0.3)) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: isHighlight ? Colors.cyanAccent : Colors.white54),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: isHighlight ? Colors.cyanAccent : Colors.white54, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
        ],
      ),
    );
  }
}

class _MetricBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MetricBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
             Text("${(value * 100).toInt()}%", style: TextStyle(color: color, fontWeight: FontWeight.bold)),
           ],
         ),
         const SizedBox(height: 6),
         LinearProgressIndicator(
           value: value,
           backgroundColor: Colors.white12,
           valueColor: AlwaysStoppedAnimation(color),
           minHeight: 6,
           borderRadius: BorderRadius.circular(3),
         ),
      ],
    );
  }
}
