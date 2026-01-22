import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CallProvider extends ChangeNotifier {
  StreamSubscription<DatabaseEvent>? _incomingCallSub;
  Map<String, dynamic>? _incomingCallData;
  String? _currentCallKey;

  Map<String, dynamic>? get incomingCallData => _incomingCallData;
  bool get hasIncomingCall => _incomingCallData != null;

  /// Starts listening for incoming calls for the current user.
  void listenForIncomingCalls() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref('calls/${user.uid}/incoming');
    
    _incomingCallSub?.cancel();
    _incomingCallSub = ref.onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        // We assume the first child is the call request for simplicity
        // in a real app, might handle multiple requests
        final data = Map<String, dynamic>.from(event.snapshot.children.first.value as Map);
        _currentCallKey = event.snapshot.children.first.key;
        _incomingCallData = data;
        notifyListeners();
      } else {
        _incomingCallData = null;
        _currentCallKey = null;
        notifyListeners();
      }
    });
  }

  /// Initiates a call to a target user.
  /// Returns the roomId (which is the caller's UID in this logic, or a generated UUID).
  Future<String> initiateCall({
    required String calleeId,
    required String callerName,
    required String callerImage,
  }) async {
    final callerId = FirebaseAuth.instance.currentUser?.uid;
    if (callerId == null) throw Exception('User not logged in');

    final roomId = callerId; // Simple room ID strategy: RoomID = CallerID

    // Write to Callee's "incoming" node
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final callData = {
      'roomId': roomId,
      'callerId': callerId,
      'callerName': callerName,
      'callerImage': callerImage,
      'type': 'video', 
      'timestamp': timestamp,
    };

    await FirebaseDatabase.instance
        .ref('calls/$calleeId/incoming/$roomId')
        .set(callData);
    
    return roomId;
  }

  /// Accepts the incoming call: deletes the request and returns the room ID to join.
  Future<String?> acceptCall() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _incomingCallData == null || _currentCallKey == null) return null;

    final roomId = _incomingCallData!['roomId'];

    // Delete the incoming request to stop ringing
    await FirebaseDatabase.instance
        .ref('calls/${user.uid}/incoming/$_currentCallKey')
        .remove();

    _incomingCallData = null;
    _currentCallKey = null;
    notifyListeners();

    return roomId;
  }

  /// Rejects the incoming call.
  Future<void> rejectCall() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentCallKey == null) return;

    await FirebaseDatabase.instance
        .ref('calls/${user.uid}/incoming/$_currentCallKey')
        .remove();
    
    _incomingCallData = null;
    _currentCallKey = null;
    notifyListeners();
  }

  /// Ends the current call session locally.
  void endCall() {
    _incomingCallData = null;
    _currentCallKey = null;
    notifyListeners();
  }

  /// Cleans up listeners.
  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }
}
