import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

// CONSTANTS FOR PATHS - SINGLE SOURCE OF TRUTH
const String PATH_CALL_REQUESTS = 'call_requests';
const String PATH_VIDEO_ROOMS = 'video_rooms';

class CallProvider extends ChangeNotifier {
  StreamSubscription<DatabaseEvent>? _incomingCallSub;
  Map<String, dynamic>? _incomingCallData;
  String? _currentCallKey;

  Map<String, dynamic>? get incomingCallData => _incomingCallData;
  bool get hasIncomingCall => _incomingCallData != null;

  final FirebaseDatabase _db = FirebaseDatabase.instance;

  /// Starts listening for incoming calls for the current user.
  /// Path: call_requests/{myUserId}
  void listenForIncomingCalls() {
    final user = FirebaseAuth.instance.currentUser;
    debugPrint('🔥 CallProvider: Listening for calls for User: ${user?.uid}');
    
    if (user == null) {
      debugPrint('⚠️ CallProvider: User is null, cannot listen.');
      return;
    }

    _incomingCallSub?.cancel();

    final myRequestsRef = _db.ref('$PATH_CALL_REQUESTS/${user.uid}');
    
    _incomingCallSub = myRequestsRef.onValue.listen((event) {
      debugPrint('🔥 CallProvider: Event on $PATH_CALL_REQUESTS/${user.uid}');
      
      if (event.snapshot.exists && event.snapshot.value != null) {
        try {
          if (event.snapshot.children.isEmpty) {
             _clearIncoming();
             return;
          }

          final firstChild = event.snapshot.children.first;
          final data = Map<String, dynamic>.from(firstChild.value as Map);
          
          // TIMESTAMP CHECK
          final timestamp = data['timestamp'];
          if (timestamp != null) {
             final now = DateTime.now().millisecondsSinceEpoch;
             final diff = now - (timestamp as num).toInt();
             
             // If call is older than 60 seconds (60000ms), ignore and remove
             if (diff > 60000) {
                debugPrint('⚠️ CallProvider: Stale call detected (Age: ${diff}ms). Removing...');
                firstChild.ref.remove();
                _clearIncoming();
                return;
             }
          }
          
          _currentCallKey = firstChild.key;
          _incomingCallData = data;
          
          debugPrint('✅ CallProvider: Incoming Call Detected! From: ${data['callerName']}');
          notifyListeners();

        } catch (e) {
          debugPrint('❌ CallProvider: Error parsing incoming data: $e');
        }
      } else {
        _clearIncoming();
      }
    }, onError: (e) {
      debugPrint('❌ CallProvider: Listener Error: $e');
    });
  }
  
  void _clearIncoming() {
    if (_incomingCallData != null) {
       debugPrint('ℹ️ CallProvider: Incoming call cleared/ended.');
       _incomingCallData = null;
       _currentCallKey = null;
       notifyListeners();
    }
  }

  /// Initiates a call to a target user.
  /// Writes to: call_requests/{calleeId}/{newRequestId}
  /// Returns: roomId (which is consistent with requestId or generated)
  Future<String> initiateCall({
    required String calleeId,
    required String callerName,
    required String callerImage,
  }) async {
    final callerId = FirebaseAuth.instance.currentUser?.uid;
    if (callerId == null) throw Exception('User not logged in');

    // Generate a unique Room ID for this session
    final roomId = '${callerId}_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint('🔥 CallProvider: Initiating call to $calleeId. Room: $roomId');

    final callData = {
      'roomId': roomId,
      'callerId': callerId,
      'callerName': callerName,
      'callerImage': callerImage,
      'type': 'video', 
      'status': 'ringing',
      'timestamp': ServerValue.timestamp,
    };

    // Write to Callee's "call_requests"
    try {
      await _db.ref('$PATH_CALL_REQUESTS/$calleeId/$roomId').set(callData).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw 'Database Write Timed Out! Check Internet/Firewall.';
        },
      );
      debugPrint('✅ CallProvider: Signal Sent Successfully to $PATH_CALL_REQUESTS/$calleeId/$roomId');
    } catch (e) {
      debugPrint('❌ CallProvider: Write Failed: $e');
      rethrow;
    }
    
    return roomId;
  }

  /// Accepted call: remove request so it stops ringing on other devices (if any)
  Future<String?> acceptCall() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _incomingCallData == null || _currentCallKey == null) return null;

    final roomId = _incomingCallData!['roomId'];
    debugPrint('🔥 CallProvider: Accepting Call. Joining Room: $roomId');

    // Remove the request to stop ringing
    try {
      await _db.ref('$PATH_CALL_REQUESTS/${user.uid}/$_currentCallKey').remove();
    } catch (e) {
      debugPrint('⚠️ CallProvider: Failed to remove call request on accept: $e');
    }

    _clearIncoming();
    return roomId;
  }

  /// Rejects the incoming call.
  Future<void> rejectCall() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentCallKey == null) return;
    
    debugPrint('🔥 CallProvider: Rejecting Call.');
    try {
      await _db.ref('$PATH_CALL_REQUESTS/${user.uid}/$_currentCallKey').remove();
    } catch (e) {
      debugPrint('⚠️ CallProvider: Failed to remove call request on reject: $e');
    }
    _clearIncoming();
  }

  /// Ends the current call connection locally/cleanup
  void endCall() {
    _clearIncoming();
  }

  @override
  void dispose() {
    _incomingCallSub?.cancel();
    super.dispose();
  }
}
