import 'dart:async';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// import 'package:sevenzeronine_clouds/NOTIFICATION/fcm_service.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:speech_therapy/src/features/video_call/providers/call_provider.dart';
import 'package:provider/provider.dart';

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
  final RTCVideoRenderer _screenShareRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _screenShareRemoteRenderer = RTCVideoRenderer(); 
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _screenStream;

  bool _micMuted = false;
  bool _cameraOff = false;
  bool _usingFrontCamera = true;
  bool _isScreenSharing = false;
  bool _isRemoteScreenSharing = false;

  Timer? _callTimer;
  int _callDurationSeconds = 0;

  bool _isConnecting = true;
  double _currentBrightness = 0.5;
  double _currentBitrate = 1000; 
  String _videoQuality = '720p';
  String _debugStatus = 'Init...'; // VISIBLE DEBUG STATUS

  static const _pipChannel = MethodChannel('com.sevenzeronine.clouds/pip');
  StreamSubscription<DatabaseEvent>? _roomSub;
  StreamSubscription<DatabaseEvent>? _answerSub; 
  StreamSubscription<DatabaseEvent>? _callerCandidatesSub;
  StreamSubscription<DatabaseEvent>? _calleeCandidatesSub;
  StreamSubscription<DatabaseEvent>? _offerSub;
  bool _viewSwapped = false; 

  int _webRefreshKey = 0; 
  
  bool _showScreenShareDialog = false;
  int _screenShareFps = 60;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBrightnessAndVolume();
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

  Future<void> _initBrightnessAndVolume() async {
    try {
      double brightness = await ScreenBrightness().current;
      setState(() => _currentBrightness = brightness);
    } catch (e) {
      debugPrint('Failed to get brightness: $e');
    }
  }

  Future<void> saveVideoCallToFirebase({
    required String senderId,
    required String senderName,
    required String recipientId,
    required String recipientName,
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
      'roomId': roomId,
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
      await _screenShareRemoteRenderer.initialize();
      await _screenShareRenderer.initialize();
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
        else {
           if (mounted) {
             setState(() {
                _screenShareRemoteRenderer.srcObject = remoteStream;
                _isRemoteScreenSharing = true;
             });
           }
           debugPrint('✅ Secondary Remote Stream (Screen) assigned/updated: ${remoteStream.id} (${track.kind})');
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
     try {
       final screenTracks = _screenShareRemoteRenderer.srcObject?.getTracks();
       if (screenTracks != null && screenTracks.any((t) => t.id == track.id)) {
          debugPrint('✅ Remote Screen Share Ended (Track Removed)');
          if (mounted) {
            setState(() {
               _isRemoteScreenSharing = false;
               _screenShareRemoteRenderer.srcObject = null;
            });
          }
       }
     } catch (e) {
        debugPrint('❌ Error handling remote track removal: $e');
     }
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

    final prefs = await SharedPreferences.getInstance();
    final qualityPref = prefs.getString('video_quality_pref') ?? '720p';
    final fpsPref = int.tryParse(prefs.getString('video_fps_pref') ?? '30') ?? 30;
    
    setState(() => _videoQuality = qualityPref);

    int width = 1280;
    int height = 720;
    
    if (qualityPref == '4k') { width = 3840; height = 2160; }
    else if (qualityPref == '1080p') { width = 1920; height = 1080; }
    else if (qualityPref == 'hd_plus') { width = 1600; height = 900; }
    else if (qualityPref == 'qhd') { width = 960; height = 540; }

    final Map<String, dynamic> videoConstraints = {
      'facingMode': 'user',
      'width': {'ideal': width, 'min': 320},
      'height': {'ideal': height, 'min': 240},
      'frameRate': {'ideal': fpsPref, 'max': fpsPref},
      'aspectRatio': 1.777,
    };
    
    debugPrint('🎥 Starting Call with: $qualityPref @ ${fpsPref}fps ($width x $height)');
    setState(() => _debugStatus = 'Starting Call...');

    final Map<String, dynamic> audioConstraints = {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    };

    debugPrint('🎤 Requesting User Media...');
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': videoConstraints, 
      });
      debugPrint('✅ User Media acquired: ${_localStream?.id}');
      
      // Force assign to renderer to ensure preview works
      _localRenderer.srcObject = _localStream;
      if (mounted) setState(() {});
      
      final prefs = await SharedPreferences.getInstance();
      final savedQuality = prefs.getString('video_quality_pref') ?? '720p';
      
      if (savedQuality != '720p') {
          debugPrint('⚙️ Applying saved video quality: $savedQuality');
          Future.delayed(const Duration(milliseconds: 1000), () {
             if (mounted) _switchResolution(savedQuality);
          });
      }
      
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
          int bitrate = 1500000;
          if (qualityPref == '4k') bitrate = 6000000;
          else if (qualityPref == '1080p') bitrate = 3000000;
          else if (qualityPref == 'hd_plus') bitrate = 2500000;
          else if (qualityPref == 'qhd') bitrate = 1000000;
          
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
      if (!event.snapshot.exists && mounted && !_isConnecting) {
        _endCallLocally();
      }
    });

    if (widget.isCaller) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await roomRef.child('offer').set(offer.toMap());
      _answerSub = roomRef.child('answer').onValue.listen((event) async {
        if (!event.snapshot.exists) return;
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final answer = RTCSessionDescription(data['sdp'], data['type']);

        if (_peerConnection?.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          debugPrint("📥 Received answer (Caller side)");
          if (mounted) setState(() => _debugStatus = 'Rx Answer');
          await _peerConnection!.setRemoteDescription(answer);
          debugPrint("✅ Remote description set (Caller side)");
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
          final answer = await _peerConnection!.createAnswer();
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
          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          await roomRef.child('answer').set(answer.toMap());
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

  Future<void> _setBitrate(double kbps) async {
    setState(() => _currentBitrate = kbps);
    if (_peerConnection == null) return;
    
    debugPrint('🎚️ Setting Bitrate to ${(kbps * 1000).toInt()} bps for ALL tracks');
    
    final senders = await _peerConnection!.getSenders();
    int updatedCount = 0;
    
    for (var sender in senders) {
      if (sender.track?.kind == 'video') {
         final params = sender.parameters;
         if (params.encodings == null || params.encodings!.isEmpty) {
           params.encodings = [RTCRtpEncoding(maxBitrate: (kbps * 1000).toInt())];
         } else {
           for (var encoding in params.encodings!) {
             encoding.maxBitrate = (kbps * 1000).toInt();
           }
         }
         
         await sender.setParameters(params);
         updatedCount++;
         final trackLabel = sender.track?.label ?? 'Unknown Track';
         debugPrint('   ✅ Updated Bitrate for track: $trackLabel');
      }
    }
    
    if (updatedCount == 0) {
      debugPrint('   ⚠️ No video tracks found to update bitrate.');
    }
  }

  Future<void> _switchResolution(String quality) async {
    if (_videoQuality == quality && quality != 'auto') return;

    debugPrint('🔄 Switching Resolution to: $quality');
    
    setState(() {
       _localRenderer.srcObject = null; 
    });

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
             const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
             const SizedBox(width: 15),
             Text('Switching to $quality...'),
          ]),
          duration: const Duration(seconds: 10), 
        )
      );
    }

    MediaStream? newStream;
    String finalQuality = quality;

    try {
      _localStream?.getTracks().forEach((t) => t.stop());

      if (quality == 'auto') {
         debugPrint('🔍 Auto: Probing 4K...');
         newStream = await _tryGetStream(3840, 2160);
         finalQuality = '4k';
         
         if (newStream == null) {
            debugPrint('🔍 Auto: 4K failed, probing 1080p...');
            newStream = await _tryGetStream(1920, 1080);
            finalQuality = '1080p';
         }
         if (newStream == null) {
            debugPrint('🔍 Auto: 1080p failed, probing 720p...');
            newStream = await _tryGetStream(1280, 720);
            finalQuality = '720p';
         }
         
         if (newStream == null) throw 'Could not acquire any resolution';
         
      } else {
         int width = 1280; int height = 720;
         if (quality == '4k') { width = 3840; height = 2160; }
         else if (quality == '1080p') { width = 1920; height = 1080; }
         else if (quality == 'hd_plus') { width = 1600; height = 900; }
         else if (quality == 'qhd') { width = 960; height = 540; }
         
         newStream = await _tryGetStream(width, height);
         if (newStream == null) throw 'Device does not support $quality';
      }

      final newVideoTrack = newStream.getVideoTracks().first;
      final newAudioTrack = newStream.getAudioTracks().firstOrNull;

      double newBitrate = 1500;
      if (finalQuality == '4k') newBitrate = 6000;
      else if (finalQuality == '1080p') newBitrate = 3000;
      else if (finalQuality == 'hd_plus') newBitrate = 2500;
      else if (finalQuality == 'qhd') newBitrate = 1000;
      await _setBitrate(newBitrate);

      if (_peerConnection != null) {
        final senders = await _peerConnection!.getSenders();
        final videoSender = senders.firstWhere((s) => s.track?.kind == 'video', orElse: () => throw 'No Video Sender');
        await videoSender.replaceTrack(newVideoTrack);
         
        if (newAudioTrack != null) {
           try {
             final audioSender = senders.firstWhere((s) => s.track?.kind == 'audio');
             await audioSender.replaceTrack(newAudioTrack);
           } catch (e) {
             debugPrint('⚠️ Audio track replace warning: $e');
           }
        }
      }

      setState(() {
         _localStream = newStream;
         _localRenderer.srcObject = _localStream; 
         _videoQuality = quality; 
         
         _micMuted = !(newAudioTrack?.enabled ?? true);
         _cameraOff = !newVideoTrack.enabled;
      });

      if (mounted) {
         ScaffoldMessenger.of(context).hideCurrentSnackBar();
         final settings = newVideoTrack.getSettings();
         final actualRes = '${settings['width']}x${settings['height']}';
         
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
           content: Text('✅ Switched to $finalQuality ($actualRes)'),
           backgroundColor: Colors.teal,
           duration: const Duration(seconds: 2),
         ));
      }

    } catch (e) {
       debugPrint('❌ Resolution Switch Error: $e');
       if (mounted) {
         ScaffoldMessenger.of(context).hideCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
           content: Text('Error: $e'), 
           backgroundColor: Colors.red
         ));
       }
    }
  }

  Future<MediaStream?> _tryGetStream(int width, int height) async {
    try {
      final Map<String, dynamic> constraints = {
         'audio': true,
         'video': {
            'facingMode': _usingFrontCamera ? 'user' : 'environment',
            'width': {'min': width, 'ideal': width},
            'height': {'min': height, 'ideal': height},
            'frameRate': {'ideal': 30},
         }
       };
       return await navigator.mediaDevices.getUserMedia(constraints);
    } catch (e) {
      debugPrint('⚠️ Probe failed for ${width}x$height: $e');
      return null;
    }
  }

  Future<void> _toggleScreenShare() async {
    if (_peerConnection == null) {
       debugPrint('⚠️ PeerConnection is null, cannot toggle screen share');
       return;
    }

    if (_isScreenSharing) {
      await _stopScreenShare();
    } else {
      setState(() => _showScreenShareDialog = true);
    }
  }

  Future<void> _stopScreenShare() async {
      try {
        _screenStream?.getTracks().forEach((track) => track.stop());
        _screenShareRenderer.srcObject = null;
        _screenStream = null;

        final senders = await _peerConnection?.getSenders();
        if (senders != null) {
          for (var sender in senders) {
             final track = sender.track;
             if (track == null) continue;
             
             final localVideoTracks = _localStream?.getVideoTracks() ?? [];
             final localAudioTracks = _localStream?.getAudioTracks() ?? [];
             
             final isLocalCamera = localVideoTracks.any((t) => t.id == track.id);
             final isLocalMic = localAudioTracks.any((t) => t.id == track.id);
             
             if (!isLocalCamera && !isLocalMic) {
                await _peerConnection!.removeTrack(sender);
             }
          }
        }

        try {
           final offer = await _peerConnection!.createOffer();
           await _peerConnection!.setLocalDescription(offer);
           final roomRef = FirebaseDatabase.instance.ref('VIDEO_CALLS/${widget.roomId}');
            await roomRef.child('offer').set(offer.toMap());
         } catch (e) {
            debugPrint('❌ Stop-Renegotiation failed: $e');
         }

         _screenStream?.getTracks().forEach((track) {
           track.stop();
           debugPrint('⏹️ Stopped screen track: ${track.label}');
         });
         _screenShareRenderer.srcObject = null;
         _screenStream = null;

         if (!kIsWeb && Platform.isAndroid) {
           debugPrint('🛑 Stopping Android MediaProjection service...');
           _pipChannel.invokeMethod('stopScreenShareService').catchError((e) {
              debugPrint('❌ Error stopping native service: $e');
           });
           debugPrint('✅ Android MediaProjection service stop command sent');
         }

        setState(() => _isScreenSharing = false);
      } catch (e) {
        debugPrint('❌ Error stopping screen share: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to stop screen sharing: $e')),
          );
        }
      }
  }

  Future<void> _startScreenShare(String mode) async {
       setState(() => _showScreenShareDialog = false);

       if (!kIsWeb && Platform.isAndroid) {
          debugPrint('🚀 Requesting Android Capture Permission...');
          final granted = await Helper.requestCapturePermission();
          if (granted != true) {
             debugPrint('⚠️ Screen capture permission denied');
             return;
          }
       }
       
       try {
        int targetWidth = 1280;
        int targetHeight = 720;
        
        int targetBitrate = (_currentBitrate * 1000).toInt(); 
        
        int targetFps = _screenShareFps; 
        String contentHint = 'motion';
         
        if (mode == 'detail') {
           targetWidth = 1920;
           targetHeight = 1080;
           targetFps = 15;
           contentHint = 'detail';
        } else if (mode == 'hd_plus') {
           targetWidth = 1600;
           targetHeight = 900;
           contentHint = 'motion';
        } else if (mode == 'qhd') {
           targetWidth = 960;
           targetHeight = 540;
           contentHint = 'motion';
        }
        
        if (!kIsWeb && Platform.isAndroid) {
          debugPrint('🚀 Starting Custom MediaProjection Service...');
          await _pipChannel.invokeMethod('startScreenShareService');
        }

        debugPrint('📹 Calling getDisplayMedia ($targetWidth x $targetHeight @ $targetFps fps)...');
        _screenStream = await navigator.mediaDevices.getDisplayMedia({
          'video': {
            'width': {'ideal': targetWidth},
            'height': {'ideal': targetHeight},
            'frameRate': {'ideal': targetFps, 'max': targetFps},
          },
          'audio': {
            'echoCancellation': false,
            'noiseSuppression': false,
            'autoGainControl': false,
          },
        });

        if (mounted) {
          setState(() {
            _screenShareRenderer.srcObject = _screenStream;
          });
        }

        final screenVideoTrack = _screenStream?.getVideoTracks().firstOrNull;
        if (screenVideoTrack != null) {

          final sender = await _peerConnection!.addTrack(screenVideoTrack, _screenStream!);
          debugPrint('✅ Added screen video track (Dual Stream)');
          
          try {
             final params = sender.parameters;
             
             if (contentHint == 'motion') {
                params.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
             } else {
                params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
             }
             
             if (params.encodings == null || params.encodings!.isEmpty) {
               params.encodings = [RTCRtpEncoding(maxBitrate: targetBitrate)]; 
             } else {
               params.encodings![0].maxBitrate = targetBitrate;
             }
             
             await sender.setParameters(params);
             debugPrint('🚀 Screen Share Optimized: Mode=$contentHint, ${targetBitrate ~/ 1000}kbps');
             
          } catch (e) {
             debugPrint('⚠️ Failed to optimize screen parameters: $e');
          }
        }

        final screenAudioTrack = _screenStream?.getAudioTracks().firstOrNull;
        if (screenAudioTrack != null) {
          screenAudioTrack.enabled = true;
          await _peerConnection!.addTrack(screenAudioTrack, _screenStream!);
        }

        try {
           final offer = await _peerConnection!.createOffer();
           await _peerConnection!.setLocalDescription(offer);
           final roomRef = FirebaseDatabase.instance.ref('VIDEO_CALLS/${widget.roomId}');
           await roomRef.child('answer').remove();
           await roomRef.child('offer').set(offer.toMap());
           debugPrint('✅ Start-Renegotiation offer sent');
        } catch (e) {
           debugPrint('❌ Start-Renegotiation failed: $e');
        }

        screenVideoTrack?.onEnded = () {
          if (mounted && _isScreenSharing) {
             _toggleScreenShare();
          }
        };

        setState(() => _isScreenSharing = true);
      } catch (e) {
        debugPrint('❌ Error starting screen share: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start screen sharing: $e')),
          );
        }
      }
  }


  Future<void> hangUp() async {
    try {
      final db = FirebaseDatabase.instance.ref();
      final roomRef = db.child('VIDEO_CALLS/${widget.roomId}');

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
      }

      _endCallLocally();
    } catch (e) {
      debugPrint('❌ Error while hanging up: $e');
      _endCallLocally();
    }
  }

  void _endCallLocally() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _screenStream?.getTracks().forEach((track) => track.stop());
    
    _peerConnection?.close();
    
    _roomSub?.cancel();
    _answerSub?.cancel();
    _offerSub?.cancel();
    _callerCandidatesSub?.cancel();
    _calleeCandidatesSub?.cancel();
    
    _callTimer?.cancel();
    
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
    _screenShareRenderer.dispose();
    _screenShareRemoteRenderer.dispose();
    _peerConnection?.close();
    _localStream?.dispose();
    _screenStream?.dispose();
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
    }
    
    _stopCallTimer();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
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
    RTCVideoRenderer mainRenderer;
    RTCVideoRenderer pipRenderer;
    bool isMainLocal;
    bool isPipLocal;

    if (_isRemoteScreenSharing) {
       mainRenderer = _screenShareRemoteRenderer;
       isMainLocal = false;

       if (_viewSwapped) {
         pipRenderer = _localRenderer;
         isPipLocal = true;
       } else {
         pipRenderer = _remoteRenderer; 
         isPipLocal = false;
       }
    } else if (_isScreenSharing) {
      mainRenderer = _screenShareRenderer;
      isMainLocal = false; 

      if (_viewSwapped) {
        pipRenderer = _localRenderer; 
        isPipLocal = true;
      } else {
        pipRenderer = _remoteRenderer; 
        isPipLocal = false;
      }
    } else {
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
                        key: ValueKey('pip_view_remote_${_remoteRenderer.hashCode}${kIsWeb ? "_$_webRefreshKey" : ""}'),
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
                child: RTCVideoView(
                  mainRenderer,
                  key: ValueKey('main_${mainRenderer.hashCode}${kIsWeb ? "_$_webRefreshKey" : ""}'),
                  mirror: isMainLocal && _usingFrontCamera,
                  objectFit: (isMainLocal || (!_isScreenSharing && !_isRemoteScreenSharing)) 
                      ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover 
                      : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
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
                  child: RTCVideoView(
                      pipRenderer,
                      key: ValueKey('pip_${pipRenderer.hashCode}${kIsWeb ? "_$_webRefreshKey" : ""}'),
                      mirror: isPipLocal && _usingFrontCamera,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
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
                        colors: [Colors.black.withOpacity(0.8), Colors.transparent],
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

            if (_controlsVisible) ...[
              Positioned(
                left: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Container(
                      width: 200,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: _currentBrightness,
                          onChanged: (value) async {
                            setState(() => _currentBrightness = value);
                            await ScreenBrightness().setScreenBrightness(value);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                top: 0,
                bottom: 0,
                child: Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Container(
                      width: 200,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                          activeTrackColor: Colors.teal,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.teal,
                        ),
                        child: Slider(
                          value: _currentBitrate,
                          min: 340,
                          max: 6000,
                          divisions: 100,
                          label: '${_currentBitrate.round()} kbps',
                          onChanged: (value) {
                             _setBitrate(value);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
            ],

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
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _controlsVisible ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 40, 10, 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: SafeArea(
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                             margin: const EdgeInsets.only(bottom: 20),
                             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                             decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                             ),
                             child: SingleChildScrollView(
                               scrollDirection: Axis.horizontal,
                               child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildResBtn('qhd'),
                                    const SizedBox(width: 8),
                                    _buildResBtn('720p'),
                                    const SizedBox(width: 8),
                                    _buildResBtn('hd_plus'),
                                    const SizedBox(width: 8),
                                    _buildResBtn('1080p'),
                                    const SizedBox(width: 8),
                                    _buildResBtn('4k'),
                                    const SizedBox(width: 8),
                                    _buildResBtn('auto'),
                                  ],
                               ),
                             ),
                           ),
                          
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildControlBtn(
                                icon: Icons.cameraswitch,
                                onPressed: _switchCamera,
                              ),
                              _buildControlBtn(
                                icon: _micMuted ? Icons.mic_off : Icons.mic,
                                onPressed: _toggleMute,
                                isActive: _micMuted,
                                activeColor: Colors.red,
                              ),
                              _buildControlBtn(
                                icon: Icons.call_end,
                                onPressed: hangUp,
                                color: Colors.red,
                                isLarge: true,
                              ),
    
                              _buildControlBtn(
                                icon: _cameraOff ? Icons.videocam_off : Icons.videocam,
                                onPressed: _toggleCamera,
                                isActive: _cameraOff,
                                activeColor: Colors.red,
                              ),
                              _buildControlBtn(
                                icon: _isScreenSharing ? Icons.stop_screen_share : Icons.screen_share,
                                onPressed: _toggleScreenShare,
                                isActive: _isScreenSharing,
                                activeColor: Colors.green,
                              ),
                            ],
                          ),
                        ],
                      ),
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
                                      color: Colors.black.withOpacity(0.3),
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
            
            if (_showScreenShareDialog)
              Positioned.fill(
                child: Container(
                  color: Colors.black54, 
                  child: Center(
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2C34),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Screen Share Settings',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          
                          Row(
                            children: [
                              const Text('FPS:', style: TextStyle(color: Colors.white70, fontSize: 16)),
                              const SizedBox(width: 12),
                              _buildFpsChip(30),
                              const SizedBox(width: 8),
                              _buildFpsChip(60),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Resolution',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), 
                          ),
                          const SizedBox(height: 20),
                          InkWell(
                            onTap: () => _startScreenShare('qhd'),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('qHD (Fastest)', 
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('960x540 @ 60fps (Data Saver)', style: TextStyle(color: Colors.white54, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white24),
                          InkWell(
                            onTap: () => _startScreenShare('motion'),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('720p (Standard)', 
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('1280x720 @ 60fps (Smooth)', style: TextStyle(color: Colors.white54, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white24),
                          InkWell(
                            onTap: () => _startScreenShare('hd_plus'),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('HD+ (Balanced)', 
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('1600x900 @ 60fps (Balanced)', style: TextStyle(color: Colors.white54, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                          const Divider(color: Colors.white24),
                          InkWell(
                            onTap: () => _startScreenShare('detail'),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('1080p (Sharpest)', 
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('1920x1080 @ 15fps (High Detail)', style: TextStyle(color: Colors.white54, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => setState(() => _showScreenShareDialog = false),
                              child: const Text('Cancel', style: TextStyle(color: Colors.teal)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

          ],
        ),
      ),
    );
  }

  Widget _buildResBtn(String quality) {
    String label = quality.toUpperCase();
    if (quality == 'hd_plus') label = 'HD+';
    if (quality == 'auto') label = 'AUTO';
    
    return Material(
       color: _videoQuality == quality ? Colors.teal : Colors.transparent,
       borderRadius: BorderRadius.circular(15),
       clipBehavior: Clip.antiAlias,
       child: InkWell(
         onTap: () { 
            debugPrint('🖱️ Tapped Resolution: $quality');
            _switchResolution(quality); 
         },
         child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
               borderRadius: BorderRadius.circular(15),
               border: Border.all(color: Colors.white24),
            ),
            child: Text(
              label, 
              style: TextStyle(
                color: Colors.white, 
                fontWeight: _videoQuality == quality ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
         ),
       ),
     );
  }

  Widget _buildFpsChip(int fps) {
    final isSelected = _screenShareFps == fps;
    return GestureDetector(
      onTap: () => setState(() => _screenShareFps = fps),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00A884) : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00A884) : Colors.white24,
          ),
        ),
        child: Text(
          '${fps}fps',
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.bold,
          ),
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
}
