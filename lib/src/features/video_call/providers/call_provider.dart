import 'package:flutter/material.dart';

class CallProvider extends ChangeNotifier {
  bool _isInCall = false;

  bool get isInCall => _isInCall;

  void startCall() {
    _isInCall = true;
    notifyListeners();
  }

  void endCall() {
    _isInCall = false;
    notifyListeners();
  }
}
