import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pip_view/pip_view.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
// import 'package:sevenzeronine_clouds/NOTIFICATION/fcm_service.dart';
// import 'package:sevenzeronine_clouds/NOTIFICATION/fcm_service.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:speech_therapy/src/features/ai/services/gemini_service.dart';
import 'package:speech_therapy/src/features/ai/services/face_detector_service.dart';
import 'package:speech_therapy/src/features/ai/services/ml_service.dart';
import 'package:record/record.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:speech_therapy/src/features/video_call/presentation/widgets/face_landmark_overlay.dart';
import 'package:speech_therapy/src/features/video_call/presentation/widgets/clinical_sidebar.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;
  final bool isCaller;
  final String userName;
  final String userId;
  final String? userImage;

  static GlobalKey<State<VideoCallScreen>>? currentKey;

  const VideoCallScreen({
    super.key,
    required this.roomId,
    required this.isCaller,
    required this.userId,
    required this.userName,
    this.userImage,
  });

  @override
  State<VideoCallScreen> createState() => VideoCallScreenState();
}

class VideoCallScreenState extends State<VideoCallScreen> with WidgetsBindingObserver {
  Offset _localVideoPosition = const Offset(20, 100);
  bool _isAppPip = false;
  bool _isLandscape = false;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  bool _micMuted = false;
  bool _cameraOff = false;
  bool _usingFrontCamera = true;

  Timer? _callTimer;
  int _callDurationSeconds = 0;

  bool _isConnecting = true;
  String _debugStatus = 'Init...'; // VISIBLE DEBUG STATUS

  static const _pipChannel = MethodChannel('com.sevenzeronine.clouds/pip');
  StreamSubscription<DatabaseEvent>? _roomSub;
  StreamSubscription<DatabaseEvent>? _answerSub; 
  StreamSubscription<DatabaseEvent>? _callerCandidatesSub;
  StreamSubscription<DatabaseEvent>? _calleeCandidatesSub;
  StreamSubscription<DatabaseEvent>? _offerSub;
  bool _viewSwapped = false; 
  
  bool _controlsVisible = true;

  // AI Stats State
  Timer? _aiTimer;
  Map<String, dynamic> _remoteAiStats = {};
  StreamSubscription<DatabaseEvent>? _aiStatsSub;

  // Offline AI State
  final AudioRecorder _audioRecorder = AudioRecorder();
  final List<double> _audioBuffer = [];
  double _lipGap = 0.0; // Real-time audio driven gap
  double _verticalDistance = 0.0;
  StreamSubscription<Uint8List>? _audioSub;

  // Snapshot Based Face Tracking
  Timer? _snapshotTimer;
  FaceAnalysisResult? _videoFaceResult;
  bool _isProcessingSnapshot = false;

  void _startSnapshotTimer() {
    _snapshotTimer?.cancel();
    _snapshotTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_localStream != null && !_isProcessingSnapshot && mounted) {
        _processSnapshot();
      }
    });
  }

  Future<void> _processSnapshot() async {
    if (_localStream == null) return;
    final tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) return;
    
    _isProcessingSnapshot = true;
    try {
      final track = tracks.first;
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/snapshot_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // Capture frame from the WebRTC track
      final buffer = await track.captureFrame();
      final file = File(filePath);
      await file.writeAsBytes(buffer.asUint8List());
      
      if (await file.exists()) {
        final result = await FaceDetectorService().processFile(file);
        
        // Clean up
        await file.delete();
        
        if (mounted && result != null) {
          setState(() {
            _videoFaceResult = result;
            _lipGap = result.lipOpenness * 5.0; // Update local stats
            _verticalDistance = result.verticalDistance;
            _realLipLandmarks = result.fullContour; // Sync for remote peer
          });
        }
      }
    } catch (e) {
      debugPrint("Snapshot Error: $e");
    } finally {
      _isProcessingSnapshot = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    initRenderersAndStart();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (!kIsWeb && Platform.isAndroid) {
        _minimizeCall();
      }
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    
    final isPip = size.width < 300 || size.height < 300;
    
    if (_isAppPip != isPip) {
       setAppPipState(isPip);
    }
    
    if (!isPip) {
       final isLandscape = size.width > size.height;
       if (isLandscape != _isLandscape) {
          _isLandscape = isLandscape; 
          if (isLandscape) {
             SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          } else {
             SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          }
       }
    }
  }

  void setAppPipState(bool isPip) {
    if (_isAppPip != isPip) {
      if (mounted) setState(() => _isAppPip = isPip);
    }
  }

  Widget _buildUserImage(String? imageSource, {double size = 120}) {
    if (imageSource == null || imageSource.isEmpty) {
      return Icon(Icons.person, size: size * 0.5, color: Colors.white24);
    }

    try {
      if (imageSource.startsWith('http')) {
        return Image.network(
          imageSource,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) {
            return Icon(Icons.person, size: size * 0.5, color: Colors.white24);
          },
        );
      }
      
      return Image.memory(
        base64Decode(imageSource),
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) {
           return Icon(Icons.person, size: size * 0.5, color: Colors.white24);
        },
      );
    } catch (e) {
      return Icon(Icons.person, size: size * 0.5, color: Colors.white24);
    }
  }



  Future<void> saveVideoCallToFirebase({
    required String senderId,
    required String senderName,
    required String recipientId,
    required String recipientName,
    required String videoRoomId,
  }) async {
    if (senderId.isEmpty || recipientId.isEmpty) return;

    final ids = [senderId, recipientId]..sort();
    final roomId = ids.join('_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final message = {
      'senderId': senderId,
      'text': 'Video call started',
      'timestamp': timestamp,
      'video': true,
      'peerId': roomId,
      'status': '',
      'duration': '',
    };

    final notification = {
      'senderId': senderId,
      'text': 'Video call started',
      'timestamp': timestamp,
      'senderName': senderName,
      'video': true,
      'peerId': roomId,
      'status': '',
      'readAt': '',
      'duration': '',
    };

    final chatId = [senderId, recipientId]..sort();
    final chatKey = chatId.join('_');

    final chatRef = FirebaseDatabase.instance.ref(
      'CLOUD-CHATS/$chatKey/messages',
    );
    await chatRef.push().set(message);

    final msgKey = FirebaseDatabase.instance.ref().push().key;
    final userChatRef = FirebaseDatabase.instance.ref(
      'CHATS-DETAILS/$recipientId/$senderId',
    );

    if (msgKey != null) {
      await userChatRef.child('senderDetails').set({
        'uid': senderId,
        'name': senderName,
        'timestamp': timestamp,
      });

      await userChatRef.child('messages').child(msgKey).set(notification);
    }
    
    final callStatusRef = FirebaseDatabase.instance.ref('CALL_STATUS/$recipientId');
    await callStatusRef.set({
      'callerId': senderId,
      'callerName': senderName,
      'callerImage': '',
      'type': 'video', 
      'roomId': videoRoomId,
      'timestamp': timestamp,
    });
    
    // Also write to 'call_requests' for CallProvider compatibility
    final callRequestRef = FirebaseDatabase.instance.ref('call_requests/$recipientId/$videoRoomId');
    await callRequestRef.set({
      'roomId': videoRoomId,
      'callerId': senderId,
      'callerName': senderName,
      'callerImage': '',
      'type': 'video',
      'status': 'ringing',
      'timestamp': timestamp,
    });
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) return;

    if (Platform.isAndroid || Platform.isIOS) {
      final List<Permission> perms = [Permission.camera, Permission.microphone];
      // Android 12+ requires bluetoothConnect for headsets
      if (Platform.isAndroid) {
         // We can't easily check SDK version directly without a plugin content, but we can just request it
         // permission_handler handles SDK version checks internally usually
         perms.add(Permission.bluetoothConnect);
      }
      
      final statuses = await perms.request();
      
      if (statuses[Permission.camera] != PermissionStatus.granted ||
          statuses[Permission.microphone] != PermissionStatus.granted) {
          // Bluetooth is optional, so we don't block on it
         throw 'Camera and Microphone permissions are required.';
      }
    }
  }

  Future<void> initRenderersAndStart() async {
    try {
      debugPrint('🏁 Initializing renderers...');
      await _requestPermissions();
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      debugPrint('✅ Renderers initialized');
      
      if (kIsWeb) {
        debugPrint('🌐 Web: Waiting for renderers to settle...');
        await Future.delayed(const Duration(seconds: 2));
      }

      if (mounted) setState(() {});
      
      debugPrint('🚀 Starting call sequence...');
      await startCall();
    } catch (e) {
      debugPrint('❌ Permission or initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissions denied or initialization failed'),
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _callDurationSeconds++);
      }
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  String get _formattedCallDuration {
    final minutes = (_callDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_callDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _handleRemoteTrack(RTCTrackEvent event) {
    try {
      if (event.streams.isNotEmpty) {
        final remoteStream = event.streams[0];
        final track = event.track;
        debugPrint('📺 Remote track received: kind=${track.kind}, id=${track.id}, streamId=${remoteStream.id}');

        if (_remoteRenderer.srcObject == null || _remoteRenderer.srcObject?.id == remoteStream.id) {
           if (mounted) {
             setState(() {
               _remoteRenderer.srcObject = remoteStream;
             });
             
             if (kIsWeb) {
               Future.delayed(const Duration(milliseconds: 1000), () {
                 if (mounted) {
                   setState(() => _viewSwapped = true);
                   
                   Future.delayed(const Duration(milliseconds: 200), () {
                     if (mounted) {
                       setState(() => _viewSwapped = false);
                     }
                   });
                 }
               });
             }
           }
           debugPrint('✅ Primary Remote Stream assigned/updated: ${remoteStream.id} (${track.kind})');
        } 
        
        if (_isConnecting && mounted) {
          setState(() {
            _isConnecting = false;
            _startCallTimer();
          });
        }
      }
    } catch (e) {
       debugPrint('❌ Error handling remote track: $e');
    }
  }

  void _handleRemoteTrackRemoved(MediaStream stream, MediaStreamTrack track) {
     // No-op for now as we don't have screen share tracks
     debugPrint('Track removed: ${track.id}');
  }

  void _handleIceCandidate(RTCIceCandidate candidate) {
    final candidateMap = candidate.toMap();

    final db = FirebaseDatabase.instance.ref();
    final candidateRef =
        db
            .child('video_rooms')
            .child(widget.roomId)
            .child(widget.isCaller ? 'callerCandidates' : 'calleeCandidates')
            .push(); 

    candidateRef.set(candidateMap);
  }

  Future<void> startCall() async {
    // Artificial latency for initialization stability as requested
    await Future.delayed(const Duration(milliseconds: 1500));
    
    // Start AI Stats and Sync
    _startAIAnalysis();
    _listenToRemoteStats();

    // Demo Mode: Auto-connect if calling Virtual Trainer
    if (widget.userName == 'Virtual Trainer') {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
             _isConnecting = false;
             // We can't actually get remote video without a peer, 
             // but we can stop the "Ringing" screen to show the UI.
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Virtual Trainer Connected (Demo Mode)')),
          );
        }
      });
    }

    // Video quality hardcoded to 720p 30fps as requested
    int width = 1280;
    int height = 720;
    int fpsPref = 30;

    final Map<String, dynamic> videoConstraints = {
      'facingMode': 'user',
      'width': {'ideal': width, 'min': 320},
      'height': {'ideal': height, 'min': 240},
      'frameRate': {'ideal': fpsPref, 'max': fpsPref},
      'aspectRatio': 1.777,
    };
    
     debugPrint('🎥 Starting Call with: 720p @ 30fps');
    if (mounted) setState(() => _debugStatus = 'Starting Call...');

    final Map<String, dynamic> audioConstraints = {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    };

    debugPrint('🎤 Requesting User Media...');
    if (!mounted) return;
    
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': videoConstraints, 
      });
      
      if (!mounted) {
        _localStream?.getTracks().forEach((track) => track.stop());
        return;
      }

      debugPrint('✅ User Media acquired: ${_localStream?.id}');
      
      // Force assign to renderer to ensure preview works
      _localRenderer.srcObject = _localStream;
      if (mounted) setState(() {});
      
      // Start Offline AI Recording (Parallel to WebRTC)
      _startOfflineAudioStream();
      _startSnapshotTimer(); // Start Snapshot Face Tracking

    } catch (e) {
      debugPrint('❌ getUserMedia failed: $e');
      rethrow;
    }
    
    if (mounted) {
      setState(() {
        _localRenderer.srcObject = _localStream;
      });
    }
    _micMuted = !(_localStream?.getAudioTracks().firstOrNull?.enabled ?? true);
    _cameraOff = !(_localStream?.getVideoTracks().firstOrNull?.enabled ?? true);
    _usingFrontCamera = true;

    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(config);
    debugPrint('✅ PeerConnection created');

    if (_localStream != null) {
      debugPrint('📤 Adding local tracks to PC...');
      _localStream!.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });
    }

    final transceivers = await _peerConnection!.getTransceivers();
    for (var transceiver in transceivers) {
      if (transceiver.sender.track?.kind == 'video') {
        final params = transceiver.sender.parameters;
        if (kIsWeb) {
           debugPrint('🌐 Web: Using default encoding parameters for ${transceiver.sender.track?.id}');
        } else {
          int bitrate = 1500000; // Fixed bitrate for 720p
          
          params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
          params.encodings = [
            RTCRtpEncoding(
              maxBitrate: bitrate,
              minBitrate: 250000, 
              maxFramerate: fpsPref,
              scaleResolutionDownBy: 1.0,
            ),
          ];
          await transceiver.sender.setParameters(params);
        }
      }
    }

    _peerConnection?.onTrack = _handleRemoteTrack;
    _peerConnection?.onRemoveTrack = _handleRemoteTrackRemoved;
    _peerConnection?.onIceCandidate = _handleIceCandidate;
    
    _peerConnection?.onIceConnectionState = (state) {
      debugPrint('🔗 ICE Connection State: $state');
      if (mounted) setState(() => _debugStatus = 'ICE: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        debugPrint('⚠️ Connection quality degraded');
      }
    };

    final roomRef = FirebaseDatabase.instance.ref(
      'video_rooms/${widget.roomId}',
    );
    if (mounted) setState(() => _debugStatus = 'Room: ${widget.roomId}');

    _roomSub = roomRef.onValue.listen((event) {
      // Only end call if room is missing AND we are not just starting up (connecting)
      // This protects the Caller from hanging up before they even write the offer.
      if (!event.snapshot.exists && mounted && !_isConnecting) {
        debugPrint('🚫 Room deleted remotely. Ending call immediately.');
        _endCallLocally();
      }
    });

    if (widget.isCaller) {
      // Clear any previous answer to avoid race conditions with stale data
      await roomRef.child('answer').remove();
      
      final constraints = {
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
      };
      final offer = await _peerConnection!.createOffer(constraints);
      await _peerConnection!.setLocalDescription(offer);
      await roomRef.child('offer').set(offer.toMap());
      
      _answerSub = roomRef.child('answer').onValue.listen((event) async {
        if (!event.snapshot.exists) return; // Ignore if null (we just deleted it)
        
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        debugPrint('📥 Received answer signal (Caller side)');
        
        final answer = RTCSessionDescription(data['sdp'], data['type']);
        final currentState = _peerConnection?.signalingState;
        debugPrint('🚦 Signaling State: $currentState');

        if (currentState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          debugPrint("✅ Setting Remote Description (Answer)...");
          try {
             await _peerConnection!.setRemoteDescription(answer);
             await _peerConnection!.setRemoteDescription(answer);
             if (mounted) {
               setState(() {
                 _debugStatus = 'Rx Answer (Connected)';
                 _isConnecting = false; // Call is established, now we can listen for deletion
               });
             }
             debugPrint("✅ Remote description set successfully");
          } catch (e) {
             debugPrint("❌ Failed to set remote description: $e");
          }
        } else {
           debugPrint("⚠️ Ignoring answer because state is $currentState (not HaveLocalOffer)");
        }
      });

      _offerSub = roomRef.child('offer').onValue.listen((event) async {
        if (!event.snapshot.exists) return;
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) return;

        final offer = RTCSessionDescription(data['sdp'], data['type']);
        final currentState = _peerConnection?.signalingState;

        if (currentState == RTCSignalingState.RTCSignalingStateStable) {
          debugPrint("📥 Received renegotiation offer (Caller side)");
          await _peerConnection!.setRemoteDescription(offer);
          final constraints = {
            'offerToReceiveAudio': 1,
            'offerToReceiveVideo': 1,
          };
          final answer = await _peerConnection!.createAnswer(constraints);
          await _peerConnection!.setLocalDescription(answer);
          await roomRef.child('answer').set(answer.toMap());
          debugPrint("✅ Sent renegotiation answer (Caller side)");
        }
      });
      final currentUser = FirebaseAuth.instance.currentUser;
      _calleeCandidatesSub = roomRef
          .child('calleeCandidates')
          .onChildAdded
          .listen(_handleCandidateSnapshotRealtime);

      saveVideoCallToFirebase(
        senderId: currentUser!.uid,
        senderName: currentUser.displayName!,
        recipientId: widget.userId,
        recipientName: widget.userName,
        videoRoomId: widget.roomId,
      );
    } else {
      _offerSub = roomRef.child('offer').onValue.listen((event) async {
        if (!event.snapshot.exists) return;
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) return;

        final offer = RTCSessionDescription(data['sdp'], data['type']);
        final currentState = _peerConnection?.signalingState;

        if (currentState == RTCSignalingState.RTCSignalingStateStable ||
            currentState == null) {
          debugPrint("📥 Received offer (Callee side)");
          if (mounted) setState(() => _debugStatus = 'Rx Offer');
          await _peerConnection!.setRemoteDescription(offer);
          final constraints = {
            'offerToReceiveAudio': 1,
            'offerToReceiveVideo': 1,
          };
          final answer = await _peerConnection!.createAnswer(constraints);
          await _peerConnection!.setLocalDescription(answer);
          await roomRef.child('answer').set(answer.toMap());
          if (mounted) setState(() => _isConnecting = false); // Callee is connected once they send answer
          debugPrint("✅ Sent answer (Callee side)");
        }
      });

      _answerSub = roomRef.child('answer').onValue.listen((event) async {
        if (!event.snapshot.exists) return;
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final answer = RTCSessionDescription(data['sdp'], data['type']);

        if (_peerConnection?.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          debugPrint("📥 Received renegotiation answer (Callee side)");
          await _peerConnection!.setRemoteDescription(answer);
          if (mounted) {
            setState(() {
               _debugStatus = 'Rx Answer (Reneg)';
               _isConnecting = false; 
            });
          }
          debugPrint("✅ Remote description set (Callee side)");
        }
      });
      
      _callerCandidatesSub = roomRef
          .child('callerCandidates')
          .onChildAdded
          .listen(_handleCandidateSnapshotRealtime);
    }
  }

  void _handleCandidateSnapshotRealtime(DatabaseEvent event) {
    if (!mounted) return;

    final data = event.snapshot.value as Map<dynamic, dynamic>?;
    if (data == null) return;

    try {
      final candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      _peerConnection?.addCandidate(candidate).catchError((e) {
        debugPrint('Failed to add ICE candidate: $e');
      });
    } catch (e) {
      debugPrint('Invalid ICE candidate data: $e');
    }
  }

  void _toggleMute() {
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track != null) {
      track.enabled = !track.enabled;
      setState(() => _micMuted = !track.enabled);
    }
  }

  void _toggleCamera() {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) {
      track.enabled = !track.enabled;
      setState(() => _cameraOff = !track.enabled);
    }
  }

  void _switchCamera() {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) {
      Helper.switchCamera(track);
      setState(() => _usingFrontCamera = !_usingFrontCamera);
    }
  }








  Future<void> hangUp() async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final roomRef = db.child('video_rooms/${widget.roomId}');

      final firestore = FirebaseFirestore.instance;
      final callLogRef = firestore
          .collection('CLOUDS/CLOUDS-CALL/CALL_LOGS')
          .doc(widget.roomId);

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        final timestamp = DateTime.now();

        final msg = {
          'status': 'ended',
          'endTime': timestamp.toIso8601String(),
          'duration_seconds': _callDurationSeconds,
          'callerId': widget.isCaller ? currentUser.uid : widget.userId,
          'calleeId': widget.isCaller ? widget.userId : currentUser.uid,
          'callerName':
              widget.isCaller
                  ? (currentUser.displayName ?? currentUser.email ?? 'Unknown')
                  : widget.userName,
          'calleeName':
              widget.isCaller
                  ? widget.userName
                  : (currentUser.displayName ?? currentUser.email ?? 'Unknown'),
        };

        callLogRef.get().then((logSnapshot) {
          if (logSnapshot.exists) {
            callLogRef.update({
              'callLogs': FieldValue.arrayUnion([msg]),
            });
          } else {
            callLogRef.set({
              'roomId': widget.roomId,
              'timestamp': timestamp.toIso8601String(),
              'participants': [currentUser.uid, widget.userId],
              'callLogs': [msg],
            });
          }
        }).catchError((e) {
          debugPrint('❌ Error saving call log: $e');
        });

        roomRef.remove().catchError((e) {
          debugPrint('❌ Error removing room: $e');
        });
        
        // Also remove the call request
        FirebaseDatabase.instance.ref('call_requests/${widget.userId}/${widget.roomId}').remove();
      }

      _endCallLocally();
    } catch (e) {
      debugPrint('❌ Error while hanging up: $e');
      _endCallLocally();
    }
  }

  void _endCallLocally() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.getTracks().forEach((track) => track.stop());

    
    _peerConnection?.close();
    WakelockPlus.disable();
    _roomSub?.cancel();
    _answerSub?.cancel();
    _offerSub?.cancel();
    _callerCandidatesSub?.cancel();
    _calleeCandidatesSub?.cancel();
    _aiTimer?.cancel();
    _aiStatsSub?.cancel();
    _audioSub?.cancel();
    _audioRecorder.dispose();
    
    _callTimer?.cancel();
    
    _localStream?.dispose();
    _localRenderer.dispose();
    if (mounted) {
      Provider.of<CallProvider>(context, listen: false).endCall();
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _localRenderer.dispose();
    _remoteRenderer.dispose();

    _peerConnection?.close();
    _localStream?.dispose();
    _callTimer?.cancel();
    _roomSub?.cancel();
    _answerSub?.cancel();
    _offerSub?.cancel();
    _callerCandidatesSub?.cancel();
    _calleeCandidatesSub?.cancel();
    _calleeCandidatesSub?.cancel();
    // FCMService.clearActiveCallRoomId();
    if (widget.isCaller) {
      FirebaseDatabase.instance.ref('CALL_STATUS/${widget.userId}').remove();
      // Also remove the call request
      FirebaseDatabase.instance.ref('call_requests/${widget.userId}/${widget.roomId}').remove();
    }
    
    _stopCallTimer();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _mlCameraController?.dispose();
    _snapshotTimer?.cancel();
    super.dispose();
  }

  Future<void> _minimizeCall() async {
    debugPrint('🔘 Minimizing call. Platform Web: $kIsWeb');
    if (!kIsWeb && Platform.isAndroid) {
      try {
        debugPrint('🚀 Requesting Native Android PiP...');
        await _pipChannel.invokeMethod('enterPip');
      } catch (e) {
        debugPrint('❌ Native PiP Error: $e');
        if (!mounted) return;
        debugPrint('🔄 Falling back to in-app PiP...');
        try {
          (PIPView.of(context) as dynamic).present(widget);
        } catch (pipE) {
           debugPrint('❌ In-app PiP Error: $pipE');
        }
      }
    } else {
      if (!mounted) return;
      debugPrint('📱 Requesting in-app PiP (Web/iOS)...');
      try {
        (PIPView.of(context) as dynamic).present(widget);
      } catch (e) {
         debugPrint('❌ In-app PiP Error: $e');
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Desktop / Tablet Landscape View (> 800px)
        if (constraints.maxWidth > 800) {
          return Scaffold(
            backgroundColor: const Color(0xFF0B141B),
            body: Row(
              children: [
                Expanded(
                  flex: 7, 
                  child: _buildMobileLayout(context), // Reusing existing video stack
                ),
                Container(
                  width: 1,
                  color: Colors.white12,
                ),
                Expanded(
                  flex: 3,
                  child: ClinicalSidebar(
                    roomId: widget.roomId,
                    patientId: widget.userId,
                    patientName: widget.userName,
                    aiStats: _remoteAiStats,
                  ),
                ),
              ],
            ),
          );
        }

        // Mobile View (Default)
        return _buildMobileLayout(context);
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    RTCVideoRenderer mainRenderer;
    RTCVideoRenderer pipRenderer;
    bool isMainLocal;
    bool isPipLocal;

    if (_viewSwapped) {
      mainRenderer = _localRenderer;
      pipRenderer = _remoteRenderer;
      isMainLocal = true;
      isPipLocal = false;
    } else {
      mainRenderer = _remoteRenderer;
      pipRenderer = _localRenderer;
      isMainLocal = false;
      isPipLocal = true;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _minimizeCall();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141B),
        body: _isAppPip 
            ? Stack(
                children: [
                   Positioned.fill(
                      child: RTCVideoView(
                        _remoteRenderer,
                  key: ValueKey('pip_view_remote_${_remoteRenderer.hashCode}'),

                        mirror: false, 
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                   ),
                ],
              )
            : Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _controlsVisible = !_controlsVisible),
                child: Stack(
                  children: [
                    RTCVideoView(
                      mainRenderer,
                      key: ValueKey('main_${mainRenderer.hashCode}'),
                      mirror: isMainLocal && _usingFrontCamera,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                    if (!isMainLocal && _remoteAiStats['lip_landmarks'] != null)
                       FaceLandmarkOverlay(
                         contour: const [], 
                         measurementPoints: _remoteAiStats['lip_landmarks'] ?? [],
                         lipGap: (_remoteAiStats['lipGap'] as num?)?.toDouble() ?? 0.0,
                         verticalDistance: (_remoteAiStats['verticalDistance'] as num?)?.toDouble() ?? 0.0,
                         lipOpennessMM: (_remoteAiStats['lipOpennessMM'] as num?)?.toDouble() ?? 0.0,
                         imageWidth: (_remoteAiStats['imageWidth'] as num?)?.toDouble() ?? 0.0,
                         imageHeight: (_remoteAiStats['imageHeight'] as num?)?.toDouble() ?? 0.0,
                         rotation: (_remoteAiStats['rotation'] as num?)?.toInt() ?? 0,
                       ),
                    if (isMainLocal && _videoFaceResult != null)
                        FaceLandmarkOverlay(
                          contour: _videoFaceResult!.fullContour, 
                          measurementPoints: _videoFaceResult!.lipLandmarks,
                          lipGap: _videoFaceResult!.lipOpennessMM, 
                          verticalDistance: _videoFaceResult!.verticalDistance,
                          lipOpennessMM: _videoFaceResult!.lipOpennessMM,
                          imageWidth: _videoFaceResult!.imageWidth,
                          imageHeight: _videoFaceResult!.imageHeight,
                          rotation: _videoFaceResult!.rotation,
                          isFrontCamera: _usingFrontCamera,
                        ),


                  ],
                ),
              ),
            ),

            Positioned(
              left: _localVideoPosition.dx,
              top: _localVideoPosition.dy,
              width: 120,
              height: 160,
              child: GestureDetector(
                onTap: () => setState(() => _viewSwapped = !_viewSwapped),
                onPanUpdate: (details) {
                  setState(() {
                    _localVideoPosition += details.delta;
                    final screenSize = MediaQuery.of(context).size;
                    _localVideoPosition = Offset(
                      _localVideoPosition.dx.clamp(0.0, screenSize.width - 120),
                      _localVideoPosition.dy.clamp(0.0, screenSize.height - 160),
                    );
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RTCVideoView(
                        pipRenderer,
                        key: ValueKey('pip_${pipRenderer.hashCode}'),
                        mirror: isPipLocal && _usingFrontCamera,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                      if (isPipLocal && _videoFaceResult != null)
                        FaceLandmarkOverlay(
                          contour: _videoFaceResult!.fullContour, 
                          measurementPoints: _videoFaceResult!.lipLandmarks,
                          lipGap: _videoFaceResult!.lipOpennessMM, 
                          verticalDistance: _videoFaceResult!.verticalDistance,
                          lipOpennessMM: _videoFaceResult!.lipOpennessMM,
                          imageWidth: _videoFaceResult!.imageWidth,
                          imageHeight: _videoFaceResult!.imageHeight,
                          rotation: _videoFaceResult!.rotation,
                          isFrontCamera: _usingFrontCamera,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _controlsVisible ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 30),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 32),
                              onPressed: _minimizeCall,
                            ),
                          ),
                          Align(
                            alignment: Alignment.center,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.userName,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isConnecting
                                      ? (widget.isCaller ? 'Calling...' : 'Connecting...')
                                      : _formattedCallDuration,
                                  style: TextStyle(
                                    color: _isConnecting ? Colors.white70 : Colors.teal,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

              Positioned(
              top: 50,
              left: 10,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  color: Colors.black54,
                  child: Text(
                    _debugStatus,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 10, shadows: [
                      Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1,1))
                    ]),
                  ),
                ),
              ),
            ),
            
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _controlsVisible ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 16,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           _buildControlBtn(
                            icon: Icons.cameraswitch,
                            onPressed: _switchCamera,
                          ),
                          const SizedBox(width: 24),
                          _buildControlBtn(
                            icon: _micMuted ? Icons.mic_off : Icons.mic,
                            onPressed: _toggleMute,
                            isActive: _micMuted,
                            activeColor: Colors.red,
                          ),
                          const SizedBox(width: 24),
                          _buildControlBtn(
                            icon: Icons.call_end,
                            onPressed: hangUp,
                            color: Colors.red,
                            isLarge: true,
                          ),
                          const SizedBox(width: 24),
                          _buildControlBtn(
                            icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                            onPressed: _toggleCamera,
                            isActive: _cameraOff,
                            activeColor: Colors.red,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            if (_isConnecting)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF0B141B),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Opacity(
                          opacity: 0.2,
                          child: _buildUserImage(widget.userImage, size: 200),
                        ),
                      ),
                      
                      Align(
                        alignment: Alignment.center,
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Spacer(),
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white12, width: 4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    )
                                  ],
                                ),
                                child: ClipOval(
                                  child: _buildUserImage(widget.userImage, size: 140),
                                ),
                              ),
                              const SizedBox(height: 32),
                              Text(
                                widget.userName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const CircularProgressIndicator(color: Color(0xFF00A884)), 
                              const SizedBox(height: 20),
                              Text(
                                'Ringing...',
                                style: TextStyle(
  // AI Stats State
                                  color: Colors.white70,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 60),
                                child: GestureDetector(
                                  onTap: hangUp,
                                  child: Container(
                                    width: 75,
                                    height: 75,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.red,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 10,
                                          offset: Offset(0, 5),
                                        )
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.call_end,
                                      color: Colors.white,
                                      size: 34,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. AI Stats HUD (Overlay)
              // 3. AI Stats HUD (Overlay)
              if (!_isAppPip && _remoteAiStats.isNotEmpty)
                Positioned(
                  top: 120,
                  right: 16,
                  child: _buildAIStatsHUD(),
                ),
            ],
          ),
      ),
    );
  }



  Widget _buildControlBtn({
    required IconData icon,
    required VoidCallback onPressed,
    bool isActive = false,
    Color? color,
    Color? activeColor,
    bool isLarge = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: isLarge ? 65 : 50,
        height: isLarge ? 65 : 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? (isActive ? (activeColor ?? Colors.white) : Colors.white12),
          border: (!isActive && color == null) ? Border.all(color: Colors.white10, width: 1) : null,
        ),
        child: Icon(
          icon,
          color: (isActive && activeColor == null) ? Colors.black : Colors.white,
          size: isLarge ? 30 : 24,
        ),
      ),
    );
  }

  Widget _buildAIStatsHUD() {
      final lipScore = ((_remoteAiStats['lipAccuracy'] as num?) ?? 0.0).toDouble();
      final pronScore = ((_remoteAiStats['pronunciation'] as num?) ?? 0.0).toDouble();
      final disorder = _remoteAiStats['disorder'] as String? ?? 'Analyzing...';
      final note = _remoteAiStats['notes'] as String? ?? 'Waiting...';
      
      final offLabel = _remoteAiStats['offline_label'] as String? ?? 'Scanning...';
      final offScore = ((_remoteAiStats['offline_score'] as num?) ?? 0.0).toDouble();

      return Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                 const Icon(Icons.analytics, color: Colors.cyanAccent, size: 16),
                 const SizedBox(width: 8),
                 Expanded(
                   child: Text(
                     disorder.toUpperCase(), 
                     style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 10),
                     overflow: TextOverflow.ellipsis,
                   ),
                 ),
              ],
            ),
            const Divider(color: Colors.white24),
            Text(note, style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            _buildStatBar("Lip Move", lipScore),
            const SizedBox(height: 6),
            _buildStatBar("Speech", pronScore),
            
            // Lip Dynamics
            const Divider(color: Colors.white24, height: 16),
            _buildStatBar("Lip Opening", (_remoteAiStats['lipGap'] as num?)?.toDouble() ?? 0.0, color: Colors.cyanAccent),

            // Offline Section
            if (offLabel != 'Scanning...') ...[
               const Divider(color: Colors.white24, height: 16),
               Row(
                 children: [
                    const Icon(Icons.offline_bolt, color: Colors.orangeAccent, size: 14),
                    const SizedBox(width: 6),
                    Text(offLabel.split('(').first, style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                 ],
               ),
               const SizedBox(height: 4),
               _buildStatBar("TFLite Prob", offScore, color: Colors.orangeAccent),
            ]
          ],
        ),
      );
  }

  
  Widget _buildStatBar(String label, double val, {Color color = Colors.greenAccent}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         Row(
           mainAxisAlignment: MainAxisAlignment.spaceBetween,
           children: [
             Text(label, style: const TextStyle(color: Colors.white, fontSize: 10)),
             Text("${(val * 100).toInt()}%", style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
           ],
         ),
         const SizedBox(height: 3),
         LinearProgressIndicator(
           value: val,
           minHeight: 3,
           backgroundColor: Colors.white12,
           valueColor: AlwaysStoppedAnimation(color),
           borderRadius: BorderRadius.circular(2),
         ),
      ],
    );
  }

  void _startAIAnalysis() {
    _aiTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
       if (!mounted || _localStream == null) return;
       
       // Analyze local stream
       final isAudio = _localStream!.getAudioTracks().isNotEmpty && 
                       _localStream!.getAudioTracks().first.enabled;
                       
       final stats = await GeminiService().analyzeSession(
         isSpeaking: isAudio, 
         isFaceVisible: true,
         avgLipOpenness: _lipGap * 25.0,
       );


       // SYNC LIP GAP & LANDMARKS
       stats['lipGap'] = _lipGap;
       stats['verticalDistance'] = _verticalDistance > 0 ? _verticalDistance : (_lipGap * 25.0); 
       stats['lip_landmarks'] = _realLipLandmarks;
       
       if (_videoFaceResult != null) {
          stats['imageWidth'] = _videoFaceResult!.imageWidth;
          stats['imageHeight'] = _videoFaceResult!.imageHeight;
          stats['rotation'] = _videoFaceResult!.rotation;
          stats['lipOpennessMM'] = _videoFaceResult!.lipOpennessMM;
       }


       
       // ADD OFFLINE DIAGNOSIS
       final offlineResult = MLService().classifyAudio(_audioBuffer);
       if (offlineResult.isNotEmpty && !offlineResult.containsKey('Error') && !offlineResult.containsKey('Model Not Loaded')) {
          String bestClass = offlineResult.entries.reduce((a, b) => a.value > b.value ? a : b).key;
          stats['offline_label'] = bestClass;
          stats['offline_score'] = offlineResult[bestClass];
          

       }
       
       // Write to Firebase for the peer to see
       final currentUser = FirebaseAuth.instance.currentUser;
       if (currentUser != null) {
          FirebaseDatabase.instance
             .ref('video_rooms/${widget.roomId}/stats/${currentUser.uid}')
             .set(stats);
       }
    });
  }
  
  
  // ML Kit Parallel Analysis
  CameraController? _mlCameraController;
  final FaceDetectorService _faceDetectorService = FaceDetectorService();
  bool _isProcessingML = false;
  List<Map<String, double>> _realLipLandmarks = [];
  
  Future<void> _startOfflineAudioStream() async {
    try {
      await MLService().loadModel();
      
      // Attempt to start Parallel ML Kit Camera (Android Multi-Client supported on some devices)
      // _initMLCamera(); // DISABLED: Causes freeze on many devices due to hardware resource conflict
      
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _audioSub = stream.listen((data) {
        final byteData = data.buffer.asByteData(data.offsetInBytes, data.length);
        double sumSq = 0;
        int count = 0;

        for (var i = 0; i < data.length - 1; i += 2) {
          final sample = byteData.getInt16(i, Endian.little);
          final double val = sample / 32768.0;
          _audioBuffer.add(val);
          
          sumSq += val * val;
          count++;
        }

        // Calculate real-time Lip Gap (fallback to RMS if ML Kit not available)
        if (count > 0 && _realLipLandmarks.isEmpty) {
           double rms = sqrt(sumSq / count);
           double targetGap = (rms * 10).clamp(0.0, 1.0);
           if (mounted) {
             setState(() => _lipGap = targetGap);
           }
        }

        if (_audioBuffer.length > 16000) {
          _audioBuffer.removeRange(0, _audioBuffer.length - 16000);
        }
      });
      
      debugPrint("🎤 Video Call Offline AI Streaming Started");
    } catch (e) {
      debugPrint("❌ Video Call Offline AI Error: $e");
    }
  }

  Future<void> _initMLCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final frontCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
      
      _mlCameraController = CameraController(
        frontCamera, 
        ResolutionPreset.low, // Low res is enough for mouth tracking
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      
      await _mlCameraController!.initialize();
      _mlCameraController!.startImageStream((image) async {
         if (_isProcessingML || !mounted) return;
         _isProcessingML = true;
         
         final result = await _faceDetectorService.processImage(image, frontCamera);
         if (result != null && mounted) {
            setState(() {
              _lipGap = result.lipOpenness * 5.0; // Scaled
              _verticalDistance = result.verticalDistance;
              _realLipLandmarks = result.lipLandmarks;
            });

         }
         _isProcessingML = false;
      });
      debugPrint("📸 Parallel ML Camera Started Successfully");
    } catch (e) {
      // Very common for this to fail if WebRTC is already using the camera
      debugPrint("📸 Parallel ML Camera Failed (Expected on some devices): $e");
    }
  }


  void _listenToRemoteStats() {
    // Listen to the peer's stats. 
    // We listen to the OTHER person's stats.
    _aiStatsSub = FirebaseDatabase.instance
        .ref('video_rooms/${widget.roomId}/stats/${widget.userId}')
        .onValue
        .listen((event) {
           if (event.snapshot.exists) {
             final data = Map<String, dynamic>.from(event.snapshot.value as Map);
             if (mounted) setState(() => _remoteAiStats = data);
           }
        });
  }
}
