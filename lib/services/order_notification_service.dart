import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class OrderNotificationService {
  OrderNotificationService._();

  static const _channelId = 'orders';
  static const _channelName = 'Orders';
  static final _local = FlutterLocalNotificationsPlugin();
  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static StreamSubscription<String>? _tokenSubscription;
  static CollectionReference<Map<String, dynamic>>? _tokenCollection;
  static DocumentReference<Map<String, dynamic>>? _tokenDocument;
  static String? _currentToken;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Customer orders and assigned workshop tasks.',
            importance: Importance.high,
          ),
        );
  }

  static Future<void> startForUser({
    required String storeId,
    required String uid,
  }) async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        Firebase.apps.isEmpty) {
      return;
    }
    await stop();

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var attempt = 0; attempt < 12; attempt++) {
        if (await messaging.getAPNSToken() != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    _tokenCollection = FirebaseFirestore.instance.collection(
      'stores/$storeId/members/$uid/tokens',
    );
    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await _saveToken(token);
    }

    _tokenSubscription = messaging.onTokenRefresh.listen(_saveToken);
    _messageSubscription = FirebaseMessaging.onMessage.listen(_showForeground);
  }

  static Future<void> stop() async {
    await _messageSubscription?.cancel();
    await _tokenSubscription?.cancel();
    _messageSubscription = null;
    _tokenSubscription = null;
    if (_tokenDocument != null && _currentToken != null) {
      await _tokenDocument!.delete().catchError((_) {});
    }
    _tokenCollection = null;
    _tokenDocument = null;
    _currentToken = null;
  }

  static Future<void> _saveToken(String token) async {
    final collection = _tokenCollection;
    if (collection == null || token.isEmpty) return;
    if (_currentToken != null && _currentToken != token) {
      await _tokenDocument?.delete().catchError((_) {});
    }
    final document = collection.doc(Uri.encodeComponent(token));
    _tokenDocument = document;
    _currentToken = token;
    await document.set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: notification.title ?? 'New jewellery order',
      body: notification.body ?? 'A new order was placed.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Notifications for new customer orders.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }
}
