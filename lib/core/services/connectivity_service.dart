import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final InternetConnectionChecker _internetChecker = InternetConnectionChecker();

  StreamController<bool>? _connectivityController;
  bool _isOnline = true;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  Stream<bool> get connectivityStream {
    _connectivityController ??= StreamController<bool>.broadcast();
    return _connectivityController!.stream;
  }

  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    // Check initial connectivity
    _isOnline = await _internetChecker.hasConnection;

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
          (ConnectivityResult result) async {
        if (result != ConnectivityResult.none) {
          // Double-check with actual internet connection
          final hasInternet = await _internetChecker.hasConnection;
          _updateConnectivity(hasInternet);
        } else {
          _updateConnectivity(false);
        }
      },
    );
  }

  void _updateConnectivity(bool isConnected) {
    if (_isOnline != isConnected) {
      _isOnline = isConnected;
      _connectivityController?.add(_isOnline);
      print('🌐 Connectivity changed: ${_isOnline ? 'ONLINE' : 'OFFLINE'}');
    }
  }

  Future<bool> checkConnection() async {
    final hasConnection = await _internetChecker.hasConnection;
    _updateConnectivity(hasConnection);
    return hasConnection;
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityController?.close();
  }
}
