// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
              'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_NEW_WEB_API_KEY',
    appId: 'YOUR_NEW_WEB_APP_ID',
    messagingSenderId: 'YOUR_NEW_SENDER_ID',
    projectId: 'YOUR_NEW_PROJECT_ID',
    authDomain: 'YOUR_NEW_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_NEW_PROJECT_ID.appspot.com',
    measurementId: 'YOUR_NEW_MEASUREMENT_ID',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_NEW_ANDROID_API_KEY',
    appId: 'YOUR_NEW_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_NEW_SENDER_ID',
    projectId: 'YOUR_NEW_PROJECT_ID',
    storageBucket: 'YOUR_NEW_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_NEW_IOS_API_KEY',
    appId: 'YOUR_NEW_IOS_APP_ID',
    messagingSenderId: 'YOUR_NEW_SENDER_ID',
    projectId: 'YOUR_NEW_PROJECT_ID',
    storageBucket: 'YOUR_NEW_PROJECT_ID.appspot.com',
    iosBundleId: 'com.yourcompany.agentXAssistant', // Change this
  );
}
