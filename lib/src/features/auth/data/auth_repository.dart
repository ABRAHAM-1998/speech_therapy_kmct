import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthRepository {
  final FirebaseAuth _firebaseAuth;

  AuthRepository({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  Future<UserCredential?> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      final UserCredential userCredential =
          await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Error signing in: ${e.message}');
      rethrow;
    }
  }

  Future<UserCredential?> createUserWithEmailAndPassword(
      String email, String password, {String role = 'Patient', String? fullName, String? phoneNumber}) async {
    try {
      final UserCredential userCredential =
          await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Save Initial Profile with Role and details
      if (userCredential.user != null) {
        // Update Auth Profile
        if (fullName != null) {
           await userCredential.user!.updateDisplayName(fullName);
        }

        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'email': email,
          'role': role,
          'fullName': fullName ?? '',
          'phoneNumber': phoneNumber ?? '',
          'isProfileComplete': false, // Still might need medical survey
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      debugPrint('Error creating user: ${e.message}');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
  }

  Future<void> saveUserProfile(Map<String, dynamic> data) async {
    final user = _firebaseAuth.currentUser;
    if (user != null) {
       await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
         data,
         SetOptions(merge: true),
       );
    }
  }

  Future<bool> isProfileComplete() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return false;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      return doc.exists && (doc.data()?['isProfileComplete'] == true);
    } catch (e) {
      debugPrint('Error checking profile: $e');
      return false;
    }
  }
  Future<String?> getUserRole() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        return doc.data()?['role'] as String?;
      }
      return null; 
    } catch (e) {
      debugPrint('Error fetching user role: $e');
      return null;
    }
  }
}
