import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class HomeworkRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Assigns new homework to a patient.
  Future<void> assignHomework({
    required String patientId,
    required String slpId,
    required String title,
    required String description,
    required String type, // 'voice_practice', 'articulation', etc.
  }) async {
    final id = const Uuid().v4();
    
    await _firestore.collection('homework').doc(id).set({
      'id': id,
      'patientId': patientId,
      'slpId': slpId,
      'title': title,
      'description': description,
      'type': type,
      'status': 'assigned', // assigned, completed
      'assignedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get active homework for a specific Patient.
  Stream<QuerySnapshot> getHomeworkForPatient(String patientId) {
    return _firestore
        .collection('homework')
        .where('patientId', isEqualTo: patientId)
        .orderBy('assignedAt', descending: true)
        .snapshots();
  }

  /// Mark homework as completed.
  Future<void> completeHomework(String homeworkId) async {
    await _firestore.collection('homework').doc(homeworkId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
  }
}
