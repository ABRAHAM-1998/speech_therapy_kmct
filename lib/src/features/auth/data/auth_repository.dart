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
      String email, String password) async {
    try {
      final UserCredential userCredential =
          await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
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
}
