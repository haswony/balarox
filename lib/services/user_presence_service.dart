import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class UserPresenceService {
  static UserPresenceService? _instance;
  static UserPresenceService get instance => _instance ??= UserPresenceService._();
  
  UserPresenceService._();
  
  bool _isInitialized = false;
  
  /// تهيئة خدمة حضور المستخدم
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    // تسجيل المستخدم كمتصل عند بدء التطبيق
    await setUserOnline();
    
    // إعداد استماع تغيير حالة التطبيق
    _setupAppLifecycleListener();
    
    // إعداد استماع تغيير اتصال الشبكة
    _setupNetworkListener();
    
    _isInitialized = true;
  }
  
  /// تسجيل المستخدم كمتصل
  Future<void> setUserOnline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('تم تحديث حالة المستخدم: متصل');
    } catch (e) {
      print('خطأ في تحديث حالة الاتصال: $e');
    }
  }
  
  /// تسجيل المستخدم كغير متصل
  Future<void> setUserOffline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('تم تحديث حالة المستخدم: غير متصل');
    } catch (e) {
      print('خطأ في تحديث حالة عدم الاتصال: $e');
    }
  }
  
  /// إعداد استماع دورة حياة التطبيق
  void _setupAppLifecycleListener() {
    SystemChannels.lifecycle.setMessageHandler((msg) async {
      if (msg?.contains('paused') ?? false) {
        // التطبيق في الخلفية
        await setUserOffline();
      } else if (msg?.contains('resumed') ?? false) {
        // التطبيق نشط مرة أخرى
        await setUserOnline();
      } else if (msg?.contains('detached') ?? false) {
        // التطبيق مغلق
        await setUserOffline();
      }
      return null;
    });
  }
  
  /// إعداد استماع حالة الشبكة (يمكن تطويرها لاحقاً)
  void _setupNetworkListener() {
    // يمكن إضافة استماع حالة الاتصال بالإنترنت هنا
  }
  
  /// الحصول على حالة مستخدم معين
  Stream<DocumentSnapshot> getUserPresenceStream(String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots();
  }
  
  /// فحص إذا كان المستخدم متصل
  Future<bool> isUserOnline(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (!doc.exists) return false;
      
      final data = doc.data() as Map<String, dynamic>? ?? {};
      return data['isOnline'] ?? false;
    } catch (e) {
      print('خطأ في فحص حالة المستخدم: $e');
      return false;
    }
  }
  
  /// الحصول على وقت آخر ظهور للمستخدم
  Future<DateTime?> getLastSeen(String userId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (!doc.exists) return null;
      
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final timestamp = data['lastSeen'] as Timestamp?;
      
      return timestamp?.toDate();
    } catch (e) {
      print('خطأ في الحصول على آخر ظهور: $e');
      return null;
    }
  }
  
  /// تنسيق وقت آخر ظهور بشكل قابل للقراءة
  String formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) {
      return 'غير متصل';
    }

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'منذ قليل';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else if (difference.inDays < 7) {
      return 'منذ ${difference.inDays} أيام';
    } else {
      return 'غير متصل مؤخراً';
    }
  }
  
  /// تنظيف الموارد
  void dispose() {
    setUserOffline();
    _isInitialized = false;
  }
}
