import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class AppointmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Books a new appointment.
  Future<void> bookAppointment({
    required String patientId,
    required String patientName,
    required String slpId,
    required String slpName,
    required DateTime dateTime,
  }) async {
    final id = const Uuid().v4();
    
    await _firestore.collection('appointments').doc(id).set({
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'slpId': slpId,
      'slpName': slpName,
      'dateTime': dateTime.toIso8601String(),
      'status': 'upcoming',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get appointments for a specific SLP.
  Stream<QuerySnapshot> getAppointmentsForSLP(String slpId) {
    return _firestore
        .collection('appointments')
        .where('slpId', isEqualTo: slpId)
        .orderBy('dateTime', descending: false)
        .snapshots();
  }

  /// Get appointments for a specific Patient.
  Stream<QuerySnapshot> getAppointmentsForPatient(String patientId) {
    return _firestore
        .collection('appointments')
        .where('patientId', isEqualTo: patientId)
        .orderBy('dateTime', descending: false)
        .snapshots();
  }

  /// Update appointment status (e.g., cancel, complete)
  Future<void> updateStatus(String id, String status) async {
    await _firestore.collection('appointments').doc(id).update({'status': status});
  }
}
