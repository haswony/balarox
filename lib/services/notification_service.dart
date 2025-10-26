import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/product_detail_page.dart';

// Top-level function for background message handling
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
  print('Handling a background message: ${message.messageId}');
  print('Background message data: ${message.data}');
  print('Background message notification: ${message.notification?.title}');

  // Handle background notifications here
  // For product expiration notifications, we just need to ensure they show in the system tray
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Initialize notification service
  Future<void> initialize() async {
    try {
      await _setupNotificationsBasedOnPreference();
    } catch (e) {
      print('Error initializing notification service: $e');
    }
  }

  // Setup notifications based on current preference
  Future<void> _setupNotificationsBasedOnPreference() async {
    // Check if notifications are enabled
    final prefs = await SharedPreferences.getInstance();
    final notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;

    if (!notificationsEnabled) {
      print('Notifications are disabled by user preference');
      // Remove FCM token if it exists
      if (_auth.currentUser != null) {
        await _firestore.collection('users').doc(_auth.currentUser!.uid).update({
          'fcmToken': FieldValue.delete(),
        });
      }
      return;
    }

    // Request permission for notifications
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');

      // Get the FCM token
      String? token = await _firebaseMessaging.getToken();
      print('FCM Token: $token');

      // Save token to user document
      if (token != null && _auth.currentUser != null) {
        await _firestore.collection('users').doc(_auth.currentUser!.uid).set({
          'fcmToken': token
        }, SetOptions(merge: true));
      }

      // Handle token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        print('New FCM Token: $newToken');
        if (_auth.currentUser != null) {
          await _firestore.collection('users').doc(_auth.currentUser!.uid).set({
            'fcmToken': newToken
          }, SetOptions(merge: true));
        }
      });

      // Set the background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle tap on notification when app is terminated
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } else {
      print('User declined or has not accepted permission');
    }
  }

  // Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    print('Foreground message received: ${message.notification?.title}');
    // Handle the message while app is in foreground
    _handleNotification(message);
  }

  // Handle notification tap
  void _handleNotification(RemoteMessage message) {
    final data = message.data;
    final type = data['type'];

    if (type == 'product_expired') {
      // Handle product expiration notification
      _handleProductExpirationNotification(data);
    }
    // Add other notification types here as needed
  }

  // Handle product expiration notification
  void _handleProductExpirationNotification(Map<String, dynamic> data) {
    final productId = data['productId'];
    print('Product expired notification for product: $productId');
    // You can add specific logic here if needed when user taps on expiration notification
  }

  // Save notification to Firestore (the actual FCM sending is handled by Firebase Functions)
  Future<void> saveNotification({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': title,
        'body': body,
        'data': data ?? {},
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving notification: $e');
    }
  }

  // Update notification settings and handle FCM token accordingly
  Future<void> updateNotificationSettings(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', enabled);

      // Re-setup notifications based on new preference
      await _setupNotificationsBasedOnPreference();

      print('Notification settings updated: ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      print('Error updating notification settings: $e');
    }
  }
}