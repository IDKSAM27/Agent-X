import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';

class VoiceService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final Logger _logger = Logger();

  bool _isListening = false;
  bool _isInitialized = false;

  // Callback for when speech is recognized
  Function(String)? onResult;
  // Callback for listening status changes
  Function(bool)? onListeningStateChanged;

  bool get isListening => _isListening;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize TTS
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);

      // Initialize STT
      // Note: actual initialization happens on first listen usually, but we can check availability
      bool available = await _speech.initialize(
        onStatus: (status) {
          _logger.i('Speech status: $status');
          if (status == 'listening') {
            _isListening = true;
            onListeningStateChanged?.call(true);
          } else if (status == 'notListening' || status == 'done') {
            _isListening = false;
            onListeningStateChanged?.call(false);
          }
        },
        onError: (errorNotification) {
          _logger.e('Speech error: $errorNotification');
          _isListening = false;
          onListeningStateChanged?.call(false);
        },
      );

      if (available) {
        _isInitialized = true;
        _logger.i('VoiceService initialized successfully');
      } else {
        _logger.w('Speech recognition not available');
      }
    } catch (e) {
      _logger.e('Error initializing VoiceService: $e');
    }
  }

  Future<bool> startListening() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Request permissions if not granted
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        _logger.w('Microphone permission denied');
        return false;
      }
    }

    if (_speech.isAvailable) {
      _speech.listen(
        onResult: (result) {
          if (result.finalResult) {
            onResult?.call(result.recognizedWords);
          }
        },
        listenFor: Duration(seconds: 30),
        pauseFor: Duration(seconds: 3),
        partialResults: true,
        localeId: "en_US",
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );
      return true;
    } else {
      _logger.w('Speech recognition not available');
      return false;
    }
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      onListeningStateChanged?.call(false);
    }
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
  }
}
