import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/notification_service.dart';

import 'dart:io';

class DatabaseService {
  // Firestore instance for NoSQL database
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Realtime Database instance
  static final rtdb.FirebaseDatabase _realtimeDb = rtdb.FirebaseDatabase.instance;
  
  // Firebase Auth instance
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache للبيانات لتسريع الاستجابة
  static final Map<String, Map<String, dynamic>> _userCache = {};
  static List<Map<String, dynamic>>? _productsCache;
  static DateTime? _productsCacheTime;
  static List<Map<String, dynamic>>? _storiesCache;
  static DateTime? _storiesCacheTime;
  static List<String>? _categoriesCache;
  static DateTime? _categoriesCacheTime;
  static const Duration _cacheTimeout = Duration(minutes: 30); // كاش أطول للمنتجات
  static const Duration _storiesCacheTimeout = Duration(minutes: 10); // أطول كاش للقصص
  static const Duration _categoriesCacheTimeout = Duration(hours: 2); // كاش أطول للفئات

  // كاش حالة الحظر للاستجابة الفورية
  static final Map<String, bool> _blockStatusCache = {};

  // كاش الأدوار للاستجابة الفورية
  static final Map<String, String> _roleCache = {};
  static final Map<String, bool> _adminStatusCache = {};
  static final Map<String, bool> _superAdminStatusCache = {};

  // دالة عامة لمسح كاش المستخدم من الخارج
  static void clearUserCache(String userId) {
    _userCache.remove(userId);
    // مسح كاش القصص أيضاً لتحديث الصورة في القصص
    _storiesCache = null;
    _storiesCacheTime = null;
    // مسح كاش المنتجات لتحديث صورة البائع
    _productsCache = null;
    _productsCacheTime = null;
    print('تم مسح كاش المستخدم $userId');
  }

  // دالة مسح جميع الكاش
  static void clearAllCache() {
    _userCache.clear();
    _productsCache = null;
    _productsCacheTime = null;
    _storiesCache = null;
    _storiesCacheTime = null;
    _categoriesCache = null;
    _categoriesCacheTime = null;
    _blockStatusCache.clear();
    _roleCache.clear();
    _adminStatusCache.clear();
    _superAdminStatusCache.clear();
    print('تم مسح جميع الكاش');
  }

  // دالة مسح كاش المستخدم الحالي فقط (للاستخدام عند تسجيل الدخول)
  static void clearCurrentUserCache() {
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      _userCache.remove(currentUser.uid);
      _roleCache.remove(currentUser.uid);
      _adminStatusCache.remove(currentUser.uid);
      _superAdminStatusCache.remove(currentUser.uid);
      print('تم مسح كاش المستخدم الحالي ${currentUser.uid}');
    }
  }

  // دوال للحصول على عدد المتابعين والمتابعين مع استثناء المحظورين
  static Future<int> getFollowersCount(String userId) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('follows')
          .where('followedUserId', isEqualTo: userId)
          .get();
      
      // فلترة المتابعين المحظورين
      List<Map<String, dynamic>> followers = [];
      for (var doc in querySnapshot.docs) {
        final followData = doc.data();
        final followerUserId = followData['followerUserId'];
        followers.add({'id': followerUserId});
      }
      
      final filteredFollowers = await filterBlockedUsers(followers);
      return filteredFollowers.length;
    } catch (e) {
      print('خطأ في حساب المتابعين: $e');
      return 0;
    }
  }

  static Future<int> getFollowingCount(String userId) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('follows')
          .where('followerUserId', isEqualTo: userId)
          .get();
      
      // فلترة المتابعين المحظورين
      List<Map<String, dynamic>> following = [];
      for (var doc in querySnapshot.docs) {
        final followData = doc.data();
        final followedUserId = followData['followedUserId'];
        following.add({'id': followedUserId});
      }
      
      final filteredFollowing = await filterBlockedUsers(following);
      return filteredFollowing.length;
    } catch (e) {
      print('خطأ في حساب المتابعين: $e');
      return 0;
    }
  }

  // دوال المتابعة
  static Future<void> followUser(String targetUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('المستخدم غير مسجل الدخول');

      await _firestore.collection('follows').add({
        'followerUserId': currentUser.uid,
        'followedUserId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // إنشاء إشعار للمستخدم المُتابَع
      await _firestore.collection('notifications').add({
        'userId': targetUserId, // المستخدم الذي سيستقبل الإشعار
        'fromUserId': currentUser.uid, // المستخدم الذي قام بالمتابعة
        'type': 'follow',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // مسح الكاش لتحديث العدادات
      _userCache.clear();
    } catch (e) {
      throw Exception('خطأ في المتابعة: $e');
    }
  }

  static Future<void> unfollowUser(String targetUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('المستخدم غير مسجل الدخول');

      final querySnapshot = await _firestore
          .collection('follows')
          .where('followerUserId', isEqualTo: currentUser.uid)
          .where('followedUserId', isEqualTo: targetUserId)
          .get();

      for (var doc in querySnapshot.docs) {
        await doc.reference.delete();
      }

      // مسح الكاش لتحديث العدادات
      _userCache.clear();
    } catch (e) {
      throw Exception('خطأ في إلغاء المتابعة: $e');
    }
  }

  static Future<bool> isFollowing(String targetUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final querySnapshot = await _firestore
          .collection('follows')
          .where('followerUserId', isEqualTo: currentUser.uid)
          .where('followedUserId', isEqualTo: targetUserId)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('خطأ في فحص المتابعة: $e');
      return false;
    }
  }

  // دالة للتحقق من المتابعة المتبادلة
  static Future<bool> isMutualFollow(String userId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // التحقق مما إذا كان المستخدم الحالي يتبع المستخدم الآخر
      final currentUserFollowing = await isFollowing(userId);
      if (!currentUserFollowing) return false;

      // التحقق مما إذا كان المستخدم الآخر يتبع المستخدم الحالي
      final querySnapshot = await _firestore
          .collection('follows')
          .where('followerUserId', isEqualTo: userId)
          .where('followedUserId', isEqualTo: currentUser.uid)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('خطأ في فحص المتابعة المتبادلة: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('follows')
          .where('followedUserId', isEqualTo: userId)
          .get();

      List<Map<String, dynamic>> followers = [];
      for (var doc in querySnapshot.docs) {
        final followData = doc.data();
        final followerUserId = followData['followerUserId'];
        final userData = await getUserFromFirestore(followerUserId);
        if (userData != null) {
          userData['id'] = followerUserId;
          followers.add(userData);
        }
      }

      // فلترة المستخدمين المحظورين
      return await filterBlockedUsers(followers);
    } catch (e) {
      print('خطأ في جلب المتابعين: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('follows')
          .where('followerUserId', isEqualTo: userId)
          .get();

      List<Map<String, dynamic>> following = [];
      for (var doc in querySnapshot.docs) {
        final followData = doc.data();
        final followedUserId = followData['followedUserId'];
        final userData = await getUserFromFirestore(followedUserId);
        if (userData != null) {
          userData['id'] = followedUserId;
          following.add(userData);
        }
      }

      // فلترة المستخدمين المحظورين
      return await filterBlockedUsers(following);
    } catch (e) {
      print('خطأ في جلب المتابعين: $e');
      return [];
    }
  }

  // ===== BLOCKING METHODS =====
  
  /// حظر مستخدم
  static Future<void> blockUser(String targetUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('المستخدم غير مسجل الدخول');
      
      if (currentUser.uid == targetUserId) {
        throw Exception('لا يمكنك حظر نفسك');
      }

      // إضافة الحظر إلى قاعدة البيانات
      await _firestore.collection('blocks').add({
        'blockerUserId': currentUser.uid,
        'blockedUserId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // إزالة المتابعة المتبادلة وتحديث العدادات
      await _removeFollowRelationshipWithCountUpdate(currentUser.uid, targetUserId);

      // تحديث كاش الحظر فوراً
      if (currentUser != null) {
        _blockStatusCache[targetUserId] = true;
      }
      
      // مسح جميع الكاش لتحديث البيانات فوراً
      clearAllCache();
    } catch (e) {
      throw Exception('خطأ في حظر المستخدم: $e');
    }
  }

  /// إلغاء حظر مستخدم
  static Future<void> unblockUser(String targetUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('المستخدم غير مسجل الدخول');

      final querySnapshot = await _firestore
          .collection('blocks')
          .where('blockerUserId', isEqualTo: currentUser.uid)
          .where('blockedUserId', isEqualTo: targetUserId)
          .get();

      for (var doc in querySnapshot.docs) {
        await doc.reference.delete();
      }

      // تحديث كاش الحظر فوراً
      if (currentUser != null) {
        _blockStatusCache[targetUserId] = false;
      }
      
      // مسح الكاش لتحديث البيانات
      _userCache.clear();
      // مسح كاش القصص لإظهار القصص فوراً عند إلغاء الحظر
      _storiesCache = null;
      _storiesCacheTime = null;
      // مسح كاش المنتجات لإظهار منتجات المستخدم فوراً عند إلغاء الحظر
      _productsCache = null;
      _productsCacheTime = null;
    } catch (e) {
      throw Exception('خطأ في إلغاء حظر المستخدم: $e');
    }
  }

  /// فحص ما إذا كان المستخدم محظور مع كاش فوري
  static Future<bool> isUserBlocked(String targetUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      // التحقق من الكاش أولاً للاستجابة الفورية
      if (_blockStatusCache.containsKey(targetUserId)) {
        return _blockStatusCache[targetUserId]!;
      }

      final querySnapshot = await _firestore
          .collection('blocks')
          .where('blockerUserId', isEqualTo: currentUser.uid)
          .where('blockedUserId', isEqualTo: targetUserId)
          .get();

      final isBlocked = querySnapshot.docs.isNotEmpty;
      
      // حفظ النتيجة في الكاش
      _blockStatusCache[targetUserId] = isBlocked;
      
      return isBlocked;
    } catch (e) {
      print('خطأ في فحص حالة الحظر: $e');
      // إرجاع القيمة من الكاش إن وجدت
      return _blockStatusCache[targetUserId] ?? false;
    }
  }

  /// فحص ما إذا كان المستخدم الحالي محظور من قبل مستخدم آخر
  static Future<bool> isBlockedByUser(String otherUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final querySnapshot = await _firestore
          .collection('blocks')
          .where('blockerUserId', isEqualTo: otherUserId)
          .where('blockedUserId', isEqualTo: currentUser.uid)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('خطأ في فحص حالة الحظر: $e');
      return false;
    }
  }

  /// فحص ما إذا كان الـ handle متاح أم مستخدم من قبل مستخدم آخر
  static Future<bool> isHandleAvailable(String handle, {String? currentUserId}) async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('handle', isEqualTo: handle.toLowerCase())
          .get();

      // إذا لم يوجد أي مستخدم بهذا الـ handle، فهو متاح
      if (querySnapshot.docs.isEmpty) {
        return true;
      }

      // إذا كان هناك مستخدم واحد فقط وهو المستخدم الحالي، فالـ handle متاح له
      if (currentUserId != null && querySnapshot.docs.length == 1) {
        return querySnapshot.docs.first.id == currentUserId;
      }

      // في جميع الحالات الأخرى، الـ handle غير متاح
      return false;
    } catch (e) {
      print('خطأ في فحص توفر الـ handle: $e');
      return false;
    }
  }

  /// الحصول على قائمة المستخدمين المحظورين
  static Future<List<Map<String, dynamic>>> getBlockedUsers() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return [];

      final querySnapshot = await _firestore
          .collection('blocks')
          .where('blockerUserId', isEqualTo: currentUser.uid)
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> blockedUsers = [];
      for (var doc in querySnapshot.docs) {
        final blockData = doc.data();
        final blockedUserId = blockData['blockedUserId'];
        final userData = await getUserFromFirestore(blockedUserId);
        if (userData != null) {
          userData['id'] = blockedUserId;
          userData['blockId'] = doc.id;
          userData['blockedAt'] = blockData['createdAt'];
          blockedUsers.add(userData);
        }
      }

      return blockedUsers;
    } catch (e) {
      print('خطأ في جلب المستخدمين المحظورين: $e');
      return [];
    }
  }

  /// إزالة علاقة المتابعة المتبادلة عند الحظر مع تحديث العدادات
  static Future<void> _removeFollowRelationshipWithCountUpdate(String currentUserId, String targetUserId) async {
    try {
      // إزالة متابعة المستخدم الحالي للمستخدم المستهدف
      final followingQuery = await _firestore
          .collection('follows')
          .where('followerUserId', isEqualTo: currentUserId)
          .where('followedUserId', isEqualTo: targetUserId)
          .get();

      for (var doc in followingQuery.docs) {
        await doc.reference.delete();
      }

      // إزالة متابعة المستخدم المستهدف للمستخدم الحالي
      final followersQuery = await _firestore
          .collection('follows')
          .where('followerUserId', isEqualTo: targetUserId)
          .where('followedUserId', isEqualTo: currentUserId)
          .get();

      for (var doc in followersQuery.docs) {
        await doc.reference.delete();
      }

      // مسح الكاش لضمان تحديث العدادات فوراً
      _userCache.clear();
    } catch (e) {
      print('خطأ في إزالة علاقة المتابعة: $e');
    }
  }

  /// إزالة علاقة المتابعة المتبادلة عند الحظر (الدالة القديمة للتوافق)
  static Future<void> _removeFollowRelationship(String currentUserId, String targetUserId) async {
    await _removeFollowRelationshipWithCountUpdate(currentUserId, targetUserId);
  }

  /// فلترة المستخدمين المحظورين من قائمة
  static Future<List<Map<String, dynamic>>> filterBlockedUsers(List<Map<String, dynamic>> users) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return users;

      // الحصول على قائمة المستخدمين المحظورين
      final blockedUsersQuery = await _firestore
          .collection('blocks')
          .where('blockerUserId', isEqualTo: currentUser.uid)
          .get();

      final blockedUserIds = blockedUsersQuery.docs
          .map((doc) => doc.data()['blockedUserId'] as String)
          .toSet();

      // الحصول على قائمة المستخدمين الذين حظروا المستخدم الحالي
      final blockingUsersQuery = await _firestore
          .collection('blocks')
          .where('blockedUserId', isEqualTo: currentUser.uid)
          .get();

      final blockingUserIds = blockingUsersQuery.docs
          .map((doc) => doc.data()['blockerUserId'] as String)
          .toSet();

      // فلترة المستخدمين
      return users.where((user) {
        final userId = user['id'] ?? user['userId'];
        return !blockedUserIds.contains(userId) && !blockingUserIds.contains(userId);
      }).toList();
    } catch (e) {
      print('خطأ في فلترة المستخدمين المحظورين: $e');
      return users;
    }
  }

  // Get current user
  static User? get currentUser => _auth.currentUser;

  // ===== FIRESTORE METHODS (NoSQL Database) =====
  
  /// إضافة مستخدم جديد إلى Firestore
  static Future<void> addUserToFirestore({
    required String userId,
    required String phoneNumber,
    String? displayName,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      // تحديد الدور بناءً على رقم الهاتف
      final role = phoneNumber == '+9647712010242' ? 'super_admin' : 'user';

      await _firestore.collection('users').doc(userId).set({
        'phoneNumber': phoneNumber,
        'displayName': displayName ?? '',
        'handle': '',
        'profileImageUrl': '',
        'role': role,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'isActive': true,
        'hideVerificationHistory': false,
        ...?additionalData,
      });
    } catch (e) {
      throw Exception('خطأ في إضافة المستخدم: $e');
    }
  }

  /// الحصول على بيانات المستخدم من Firestore مع Cache
  static Future<Map<String, dynamic>?> getUserFromFirestore(String userId) async {
    try {
      // التحقق من الـ cache أولاً
      if (_userCache.containsKey(userId)) {
        return _userCache[userId];
      }

      DocumentSnapshot doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        final userData = doc.data() as Map<String, dynamic>?;
        if (userData != null) {
          // حفظ البيانات في الـ cache
          _userCache[userId] = userData;
        }
        return userData;
      }
      return null;
    } catch (e) {
      // في حالة الخطأ، إرجاع البيانات من الـ cache إن وجدت
      if (_userCache.containsKey(userId)) {
        return _userCache[userId];
      }
      throw Exception('خطأ في استرجاع بيانات المستخدم: $e');
    }
  }

  /// تحديث بيانات المستخدم في Firestore مع تحديث الـ Cache
  static Future<void> updateUserInFirestore({
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // تحديث الـ cache محلياً
      if (_userCache.containsKey(userId)) {
        _userCache[userId]!.addAll(data);
      }

      // تحديث كاش الأدوار إذا تم تحديث الدور
      if (data.containsKey('role')) {
        final newRole = data['role'];
        _roleCache[userId] = newRole;
        _adminStatusCache[userId] = newRole == 'admin' || newRole == 'super_admin';
        _superAdminStatusCache[userId] = newRole == 'super_admin';
      }
    } catch (e) {
      throw Exception('خطأ في تحديث بيانات المستخدم: $e');
    }
  }

  /// تحديث حقول محددة للمستخدم (للمشرفين فقط)
  static Future<void> updateUserFieldsByAdmin({
    required String userId,
    required Map<String, dynamic> data,
    required String adminId,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByAdminId': adminId,
      });
      
      // تحديث الـ cache محلياً
      if (_userCache.containsKey(userId)) {
        _userCache[userId]!.addAll(data);
      }
      
      // إرسال إشعار للمستخدم
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': 'admin_update',
        'title': 'تحديث من المشرف',
        'body': 'تم تحديث معلومات حسابك من قبل المشرف',
        'data': data.keys.toList(),
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('خطأ في تحديث بيانات المستخدم من قبل المشرف: $e');
    }
  }

  /// إضافة منشور جديد
  static Future<String> addPost({
    required String title,
    required String content,
    String? imageUrl,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      DocumentReference docRef = await _firestore.collection('posts').add({
        'title': title,
        'content': content,
        'imageUrl': imageUrl,
        'authorId': user.uid,
        'authorPhone': user.phoneNumber,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': 0,
        'comments': 0,
        'isActive': true,
        ...?additionalData,
      });

      return docRef.id;
    } catch (e) {
      throw Exception('خطأ في إضافة المنشور: $e');
    }
  }

  /// الحصول على المنشورات
  static Stream<QuerySnapshot> getPostsStream({
    int limit = 20,
    String? authorId,
  }) {
    Query query = _firestore
        .collection('posts')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (authorId != null) {
      query = query.where('authorId', isEqualTo: authorId);
    }

    return query.snapshots();
  }

  // ===== STORIES METHODS =====
  
  /// إضافة قصة جديدة
  static Future<void> addStory({
    required String userId,
    required String imageUrl,
    String caption = '',
    Map<String, dynamic>? textOverlay,
  }) async {
    try {
      Map<String, dynamic> storyData = {
        'userId': userId,
        'imageUrl': imageUrl,
        'caption': caption,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
        'viewers': [], // لا نضيف المستخدم تلقائياً ليظهر اللون الأحمر
      };
      
      // إضافة النص المخصص إذا كان موجوداً
      if (textOverlay != null) {
        storyData['textOverlay'] = textOverlay;
      }
      
      await _firestore.collection('stories').add(storyData);
      
      // مسح الـ cache بعد إضافة القصة
      _userCache.clear();
      _storiesCache = null;
      _storiesCacheTime = null;
      
    } catch (e) {
      throw Exception('خطأ في إضافة القصة: $e');
    }
  }

  /// إضافة قصة جديدة مع النصوص المخصصة
  static Future<void> addStoryWithTextOverlays({
    required String userId,
    required String imageUrl,
    String caption = '',
    List<Map<String, dynamic>>? textOverlays,
    bool isVideo = false, // Added video flag
  }) async {
    try {
      Map<String, dynamic> storyData = {
        'userId': userId,
        'imageUrl': imageUrl,
        'caption': caption,
        'isVideo': isVideo, // Store video flag
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
        'viewers': [], // لا نضيف المستخدم تلقائياً ليظهر اللون الأحمر
      };
      
      // إضافة النصوص المخصصة إذا كانت موجودة
      if (textOverlays != null && textOverlays.isNotEmpty) {
        storyData['textOverlays'] = textOverlays;
      }
      
      await _firestore.collection('stories').add(storyData);
      
      // مسح الـ cache بعد إضافة القصة
      _userCache.clear();
      _storiesCache = null;
      _storiesCacheTime = null;
      
    } catch (e) {
      throw Exception('خطأ في إضافة القصة: $e');
    }
  }

  /// التحقق من آخر قصة للمستخدم وإذا كان يمكنه إضافة قصة جديدة
  static Future<Map<String, dynamic>> checkUserStoryLimit(String userId) async {
    try {
      // جلب آخر قصة للمستخدم
      final querySnapshot = await _firestore
          .collection('stories')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        // لا توجد قصص سابقة، يمكن إضافة قصة
        return {
          'canAddStory': true,
          'remainingTime': 0,
          'lastStoryTime': null,
        };
      }

      final lastStory = querySnapshot.docs.first.data();
      final lastStoryTime = (lastStory['createdAt'] as Timestamp).toDate();
      final now = DateTime.now();
      final timeDifference = now.difference(lastStoryTime);
      
      // التحقق من مرور 24 ساعة
      const Duration limitDuration = Duration(hours: 24);
      final canAdd = timeDifference >= limitDuration;
      
      // حساب الوقت المتبقي
      final remainingTime = canAdd ? 0 : (limitDuration - timeDifference).inSeconds;
      
      return {
        'canAddStory': canAdd,
        'remainingTime': remainingTime,
        'lastStoryTime': lastStoryTime,
        'timeDifference': timeDifference.inHours,
      };
    } catch (e) {
      print('خطأ في التحقق من حد القصص: $e');
      // في حالة الخطأ، نسمح بإضافة قصة لتجنب حظر المستخدم
      return {
        'canAddStory': true,
        'remainingTime': 0,
        'lastStoryTime': null,
        'error': e.toString(),
      };
    }
  }

  /// جلب القصص النشطة مجمعة حسب المستخدم مع cache محسّن
  static Future<List<Map<String, dynamic>>> getActiveStories() async {
    try {
      // التحقق من الـ cache
      if (_storiesCache != null &&
          _storiesCacheTime != null &&
          DateTime.now().difference(_storiesCacheTime!) < _storiesCacheTimeout) {
        return _storiesCache!;
      }

      // تبسيط الاستعلام لتجنب مشاكل الفهرسة
      final querySnapshot = await _firestore
          .collection('stories')
          .where('expiresAt', isGreaterThan: Timestamp.fromDate(DateTime.now()))
          .orderBy('createdAt', descending: true)
          .limit(100) // زيادة الحد لتحسين الأداء
          .get();

      final now = DateTime.now();
      
      // فلترة القصص النشطة محلياً
      List<Map<String, dynamic>> activeStories = [];
      for (var doc in querySnapshot.docs) {
        final storyData = doc.data();
        // التحقق من أن الحقل موجود وله قيمة قبل المحاولة لتحويله
        final expiresAtObj = storyData['expiresAt'];
        if (expiresAtObj != null) {
          final expiresAt = (expiresAtObj as Timestamp).toDate();
          
          // التحقق من أن القصة لم تنته صلاحيتها
          if (expiresAt.isAfter(now)) {
            storyData['id'] = doc.id;
            activeStories.add(storyData);
          }
        }
      }

      // تجميع القصص النشطة حسب المستخدم
      Map<String, List<Map<String, dynamic>>> userStories = {};
      
      for (var storyData in activeStories) {
        final userId = storyData['userId'];
        if (!userStories.containsKey(userId)) {
          userStories[userId] = [];
        }
        userStories[userId]!.add(storyData);
      }
      
      // فلترة المستخدمين المحظورين
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        // الحصول على قائمة المستخدمين المحظورين
        final blockedUsersQuery = await _firestore
            .collection('blocks')
            .where('blockerUserId', isEqualTo: currentUser.uid)
            .get();

        final blockedUserIds = blockedUsersQuery.docs
            .map((doc) => doc.data()['blockedUserId'] as String)
            .toSet();

        // الحصول على قائمة المستخدمين الذين حظروا المستخدم الحالي
        final blockingUsersQuery = await _firestore
            .collection('blocks')
            .where('blockedUserId', isEqualTo: currentUser.uid)
            .get();

        final blockingUserIds = blockingUsersQuery.docs
            .map((doc) => doc.data()['blockerUserId'] as String)
            .toSet();

        // إزالة قصص المستخدمين المحظورين
        userStories.removeWhere((userId, stories) =>
            blockedUserIds.contains(userId) || blockingUserIds.contains(userId));
      }
      
      // تحضير القائمة النهائية
      List<Map<String, dynamic>> groupedStories = [];
      
      for (var userId in userStories.keys) {
        final userStoriesList = userStories[userId]!;
        final userData = await getUserFromFirestore(userId);
        
        // التحقق من أن المستخدم الحالي قد شاهد جميع القصص
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        bool hasUnseenStories = false;
        
        if (currentUserId != null) {
          // إذا كان هذا هو المستخدم الحالي، تحقق من المشاهدة أيضاً
          for (var story in userStoriesList) {
            List<dynamic> viewers = story['viewers'] ?? [];
            if (!viewers.contains(currentUserId)) {
              hasUnseenStories = true;
              break;
            }
          }
        } else {
          // إذا لم يكن مسجل دخول، اعتبر جميع القصص غير مشاهدة
          hasUnseenStories = true;
        }
        
        // التحقق من أن الحقل موجود وله قيمة قبل استخدامه
        final createdAtObj = userStoriesList.first['createdAt'];
        final latestStoryTime = createdAtObj != null ? createdAtObj : Timestamp.fromDate(DateTime.now());
        
        groupedStories.add({
          'userId': userId,
          'userDisplayName': userData?['displayName'] ?? '',
          'userProfileImage': userData?['profileImageUrl'] ?? '',
          'stories': userStoriesList,
          'hasUnseenStories': hasUnseenStories,
          'latestStoryTime': latestStoryTime,
        });
      }
      
      // ترتيب حسب وجود قصص غير مشاهدة أولاً، ثم حسب الوقت
      groupedStories.sort((a, b) {
        if (a['hasUnseenStories'] && !b['hasUnseenStories']) return -1;
        if (!a['hasUnseenStories'] && b['hasUnseenStories']) return 1;
        
        // التحقق من أن الحقول موجودة وليست فارغة قبل المقارنة
        final timeA = a['latestStoryTime'];
        final timeB = b['latestStoryTime'];
        
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1;
        if (timeB == null) return -1;
        
        return (timeB as Timestamp).compareTo(timeA as Timestamp);
      });
      
      // حفظ في الـ cache
      _storiesCache = groupedStories;
      _storiesCacheTime = DateTime.now();
      
      return groupedStories;
    } catch (e) {
      print('خطأ في جلب القصص: $e');
      // في حالة الخطأ، إرجاع البيانات من الـ cache إن وجدت
      if (_storiesCache != null) {
        return _storiesCache!;
      }
      return [];
    }
  }

  /// تحديث مشاهدي القصة
  static Future<void> markStoryAsViewed(String storyId, String userId) async {
    try {
      await _firestore.collection('stories').doc(storyId).update({
        'viewers': FieldValue.arrayUnion([userId])
      });
      
      // مسح الـ cache بعد التحديث
      _userCache.clear();
      
    } catch (e) {
      print('خطأ في تحديث مشاهدي القصة: $e');
    }
  }

  /// تمييز عدة قصص كمشاهدة
  static Future<void> markMultipleStoriesAsViewed(List<String> storyIds, String userId) async {
    try {
      if (storyIds.isEmpty) return;
      
      final batch = _firestore.batch();
      
      for (String storyId in storyIds) {
        final storyRef = _firestore.collection('stories').doc(storyId);
        batch.update(storyRef, {
          'viewers': FieldValue.arrayUnion([userId])
        });
      }
      
      await batch.commit();
      
      // مسح الـ cache بعد التحديث
      _userCache.clear();
      
    } catch (e) {
      print('خطأ في تمييز القصص كمشاهد: $e');
    }
  }

  /// جلب مشاهدي القصة
  static Future<List<Map<String, dynamic>>> getStoryViewers(String storyId) async {
    try {
      // جلب بيانات القصة أولاً للحصول على قائمة المشاهدين
      final storyDoc = await _firestore.collection('stories').doc(storyId).get();
      
      if (!storyDoc.exists) {
        return [];
      }
      
      final storyData = storyDoc.data()!;
      final viewersIds = List<String>.from(storyData['viewers'] ?? []);
      
      if (viewersIds.isEmpty) {
        return [];
      }
      
      // جلب بيانات المستخدمين المشاهدين
      List<Map<String, dynamic>> viewers = [];
      
      for (String userId in viewersIds) {
        final userData = await getUserFromFirestore(userId);
        if (userData != null) {
          userData['id'] = userId;
          viewers.add(userData);
        }
      }
      
      return viewers;
    } catch (e) {
      print('خطأ في جلب مشاهدي القصة: $e');
      return [];
    }
  }

  /// جلب مشاهدي جميع قصص المستخدم مع معلومات إضافية
  static Future<List<Map<String, dynamic>>> getUserStoryViewers(List<String> storyIds) async {
    try {
      if (storyIds.isEmpty) {
        return [];
      }
      
      Set<String> uniqueViewerIds = {};
      List<Map<String, dynamic>> allViewers = [];
      Map<String, DateTime> viewerLastSeen = {};
      
      // جلب مشاهدي كل قصة
      for (String storyId in storyIds) {
        final storyDoc = await _firestore.collection('stories').doc(storyId).get();
        
        if (storyDoc.exists) {
          final storyData = storyDoc.data()!;
          final viewersIds = List<String>.from(storyData['viewers'] ?? []);
          final createdAt = (storyData['createdAt'] as Timestamp).toDate();
          
          for (String userId in viewersIds) {
            if (!uniqueViewerIds.contains(userId)) {
              uniqueViewerIds.add(userId);
              final userData = await getUserFromFirestore(userId);
              if (userData != null) {
                userData['id'] = userId;
                allViewers.add(userData);
                viewerLastSeen[userId] = createdAt;
              }
            } else if (viewerLastSeen.containsKey(userId)) {
              // تحديث تاريخ آخر مشاهدة إذا كانت القصة أحدث
              final currentLastSeen = viewerLastSeen[userId]!;
              if (createdAt.isAfter(currentLastSeen)) {
                viewerLastSeen[userId] = createdAt;
              }
            }
          }
        }
      }
      
      // إضافة معلومات إضافية لكل مشاهد
      for (var viewer in allViewers) {
        final userId = viewer['id'];
        if (viewerLastSeen.containsKey(userId)) {
          viewer['lastSeen'] = viewerLastSeen[userId];
        }
      }
      
      return allViewers;
    } catch (e) {
      print('خطأ في جلب مشاهدي قصص المستخدم: $e');
      return [];
    }
  }

  /// جلب عدد مشاهدي القصة
  static Future<int> getStoryViewersCount(String storyId) async {
    try {
      final storyDoc = await _firestore.collection('stories').doc(storyId).get();

      if (!storyDoc.exists) {
        return 0;
      }

      final storyData = storyDoc.data()!;
      final viewersIds = List<String>.from(storyData['viewers'] ?? []);

      return viewersIds.length;
    } catch (e) {
      print('خطأ في جلب عدد مشاهدي القصة: $e');
      return 0;
    }
  }

  /// حذف قصة
  static Future<void> deleteStory(String storyId) async {
    try {
      await _firestore.collection('stories').doc(storyId).delete();

      // مسح الـ cache بعد الحذف
      _storiesCache = null;
      _storiesCacheTime = null;
    } catch (e) {
      print('خطأ في حذف القصة: $e');
      throw Exception('خطأ في حذف القصة: $e');
    }
  }

  /// جلب عدد منشورات المستخدم (المنتجات)
  static Future<int> getUserPostsCount(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection('products')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .get();

      return querySnapshot.docs.length;
    } catch (e) {
      print('خطأ في جلب عدد منشورات المستخدم: $e');
      return 0;
    }
  }

  /// إضافة المستخدم كمشاهد لقصصه الخاصة (لحل مشكلة القصص القديمة)
  static Future<void> markOwnStoriesAsViewed(String userId) async {
    try {
      final now = DateTime.now();
      final querySnapshot = await _firestore
          .collection('stories')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      final batch = _firestore.batch();
      
      for (var doc in querySnapshot.docs) {
        final storyData = doc.data();
        // التحقق من أن الحقل موجود وله قيمة قبل المحاولة لتحويله
        final expiresAtObj = storyData['expiresAt'];
        if (expiresAtObj != null) {
          final expiresAt = (expiresAtObj as Timestamp).toDate();
          
          // التحقق من أن القصة لم تنته صلاحيتها
          if (expiresAt.isAfter(now)) {
            List<dynamic> viewers = storyData['viewers'] ?? [];
            if (!viewers.contains(userId)) {
              batch.update(doc.reference, {
                'viewers': FieldValue.arrayUnion([userId])
              });
            }
          }
        }
      }
      
      await batch.commit();
      _userCache.clear();
      
    } catch (e) {
      print('خطأ في تحديث قصص المستخدم: $e');
    }
  }

  /// البحث عن المستخدمين بالـ handle
  static Future<List<Map<String, dynamic>>> getUsersByHandle(String query) async {
    try {
      final searchTerm = query.toLowerCase().replaceAll('@', '');
      
      final querySnapshot = await _firestore
          .collection('users')
          .where('handle', isGreaterThanOrEqualTo: searchTerm)
          .where('handle', isLessThanOrEqualTo: searchTerm + '\uf8ff')
          .limit(20)
          .get();

      List<Map<String, dynamic>> users = [];
      for (var doc in querySnapshot.docs) {
        final userData = doc.data();
        userData['id'] = doc.id;
        users.add(userData);
      }
      
      // فلترة المستخدمين المحظورين
      return await filterBlockedUsers(users);
    } catch (e) {
      print('خطأ في البحث عن المستخدمين: $e');
      return [];
    }
  }

  // ===== PRODUCTS METHODS =====
  
  /// إضافة منتج جديد
  static Future<void> addProduct({
    required String userId,
    required String title,
    required String description,
    required String category,
    required String price,
    required String location,
    required List<String> imageUrls,
    String condition = 'جديد',
    bool isNegotiable = false,
    bool isAuction = false,
    String? auctionStartPrice,
    int? auctionDurationHours,
  }) async {
    try {
      final now = DateTime.now();
      final expireDate = now.add(const Duration(seconds: 30)); // 30 seconds for testing
      
      Map<String, dynamic> productData = {
        'userId': userId,
        'title': title,
        'description': description,
        'category': category,
        'price': price,
        'location': location,
        'imageUrls': imageUrls,
        'condition': condition,
        'isNegotiable': isNegotiable,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(expireDate),
        'status': 'active', // active, expired
        'isActive': true,
        'views': 0,
        'isAuction': isAuction,
      };

      // إضافة بيانات المزاد إذا كان المنتج مزاد
      if (isAuction && auctionStartPrice != null && auctionDurationHours != null) {
        final now = DateTime.now();
        final endTime = now.add(Duration(hours: auctionDurationHours));

        productData.addAll({
          'auctionStartPrice': auctionStartPrice,
          'auctionCurrentPrice': auctionStartPrice,
          'auctionStartTime': FieldValue.serverTimestamp(),
          'auctionEndTime': Timestamp.fromDate(endTime),
          'auctionDurationHours': auctionDurationHours,
          'auctionStatus': 'active', // active, ended, cancelled
          'auctionBidsCount': 0,
          'auctionHighestBidderId': null,
          'auctionWinnerId': null,
        });
      }

      await _firestore.collection('products').add(productData);
      
      // مسح cache المنتجات بعد إضافة منتج جديد
      _productsCache = null;
      _productsCacheTime = null;
    } catch (e) {
      throw Exception('خطأ في إضافة المنتج: $e');
    }
  }

  /// إرسال منتج للمراجعة من قبل الإدارة
  static Future<void> submitProductForReview({
    required String userId,
    required String title,
    required String description,
    required String category,
    required String price,
    required String location,
    required List<String> imageUrls,
    String condition = 'جديد',
    bool isNegotiable = false,
    bool isAuction = false,
    String? auctionStartPrice,
    int? auctionDurationHours,
  }) async {
    try {
      final now = DateTime.now();
      final expireDate = now.add(const Duration(seconds: 30)); // 30 seconds for testing
      
      Map<String, dynamic> productData = {
        'userId': userId,
        'title': title,
        'description': description,
        'category': category,
        'price': price,
        'location': location,
        'imageUrls': imageUrls,
        'condition': condition,
        'isNegotiable': isNegotiable,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(expireDate),
        'status': 'pending', // pending, active, expired, approved, rejected
        'isActive': false, // غير نشط حتى الموافقة
        'views': 0,
        'isAuction': isAuction,
        'reviewedAt': null,
        'reviewedBy': null,
        'rejectionReason': null,
      };

      // إضافة بيانات المزاد إذا كان المنتج مزاد
      if (isAuction && auctionStartPrice != null && auctionDurationHours != null) {
        productData.addAll({
          'auctionStartPrice': auctionStartPrice,
          'auctionCurrentPrice': auctionStartPrice,
          'auctionDurationHours': auctionDurationHours,
          'auctionStatus': 'pending', // pending, active, ended, cancelled
          'auctionBidsCount': 0,
          'auctionHighestBidderId': null,
          'auctionWinnerId': null,
        });
      }

      // حفظ في مجموعة منفصلة للمراجعة
      await _firestore.collection('pending_products').add(productData);

    } catch (e) {
      throw Exception('خطأ في إرسال المنتج للمراجعة: $e');
    }
  }

  /// جلب المنتجات المعلقة للمراجعة (للمشرفين فقط)
  static Future<List<Map<String, dynamic>>> getPendingProducts() async {
    try {
      final snapshot = await _firestore
          .collection('pending_products')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('خطأ في جلب المنتجات المعلقة: $e');
    }
  }

  /// موافقة على منتج من قبل المشرف
  static Future<void> approveProduct(String pendingProductId, String adminId) async {
    try {
      // جلب بيانات المنتج المعلق
      final pendingDoc = await _firestore
          .collection('pending_products')
          .doc(pendingProductId)
          .get();

      if (!pendingDoc.exists) {
        throw Exception('المنتج غير موجود');
      }

      final productData = pendingDoc.data()!;

      // تحديث بيانات المنتج للنشر
      final now = DateTime.now();
      final expireDate = now.add(const Duration(days: 10)); // 10 days for production

      productData['isActive'] = true;
      productData['status'] = 'active'; // تغيير من approved إلى active
      productData['expireAt'] = Timestamp.fromDate(expireDate);
      productData['reviewedAt'] = FieldValue.serverTimestamp();
      productData['reviewedBy'] = adminId;
      // تحديث تاريخ النشر إلى وقت الموافقة
      productData['createdAt'] = FieldValue.serverTimestamp();

      // إذا كان مزاد، تحديث أوقات المزاد
      if (productData['isAuction'] == true) {
        final now = DateTime.now();
        final durationHours = productData['auctionDurationHours'] ?? 24;
        final endTime = now.add(Duration(hours: durationHours));

        productData['auctionStartTime'] = FieldValue.serverTimestamp();
        productData['auctionEndTime'] = Timestamp.fromDate(endTime);
        productData['auctionStatus'] = 'active';
      }

      // نقل المنتج إلى مجموعة المنتجات الرئيسية
      final newProductRef = await _firestore.collection('products').add(productData);

      // حذف إشعارات الرفض السابقة لهذا المنتج
      final rejectionNotifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: productData['userId'])
          .where('type', isEqualTo: 'product_rejected')
          .where('pendingProductId', isEqualTo: pendingProductId)
          .get();

      final batch = _firestore.batch();
      for (var doc in rejectionNotifications.docs) {
        batch.delete(doc.reference);
      }

      // إرسال إشعار مفصل للمستخدم
      await _firestore.collection('notifications').add({
        'userId': productData['userId'],
        'type': 'product_approved',
        'title': 'تم قبول إعلانك',
        'body': 'تم قبول إعلانك "${productData['title']}" ونشره في التطبيق',
        'productId': newProductRef.id,
        'productData': {
          'id': newProductRef.id,
          'title': productData['title'],
          'description': productData['description'],
          'price': productData['price'],
          'imageUrl': productData['imageUrls']?.isNotEmpty == true ? productData['imageUrls'][0] : null,
          'category': productData['category'],
          'location': productData['location'],
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // حذف المنتج من المعلقة
      await _firestore.collection('pending_products').doc(pendingProductId).delete();

      // تنفيذ حذف الإشعارات
      if (rejectionNotifications.docs.isNotEmpty) {
        await batch.commit();
      }

      // مسح cache المنتجات
      _productsCache = null;
      _productsCacheTime = null;

    } catch (e) {
      throw Exception('خطأ في الموافقة على المنتج: $e');
    }
  }

  /// رفض منتج من قبل المشرف
  static Future<void> rejectProduct(String pendingProductId, String adminId, String reason) async {
    try {
      // جلب بيانات المنتج أولاً
      final pendingDoc = await _firestore
          .collection('pending_products')
          .doc(pendingProductId)
          .get();

      if (pendingDoc.exists) {
        final productData = pendingDoc.data()!;

        // إرسال إشعار مفصل للمستخدم
        await _firestore.collection('notifications').add({
          'userId': productData['userId'],
          'type': 'product_rejected',
          'title': 'تم رفض إعلانك',
          'body': 'تم رفض إعلانك "${productData['title']}"',
          'rejectionReason': reason,
          'pendingProductId': pendingProductId,
          'productData': {
            'id': pendingProductId,
            'title': productData['title'],
            'description': productData['description'],
            'price': productData['price'],
            'imageUrl': productData['imageUrls']?.isNotEmpty == true ? productData['imageUrls'][0] : null,
            'category': productData['category'],
            'location': productData['location'],
          },
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _firestore.collection('pending_products').doc(pendingProductId).update({
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        'rejectionReason': reason,
      });
    } catch (e) {
      throw Exception('خطأ في رفض المنتج: $e');
    }
  }

  /// التحقق من صلاحيات المشرف
  static Future<bool> isAdmin(String userId) async {
    try {
      // التحقق من الكاش أولاً
      if (_adminStatusCache.containsKey(userId)) {
        return _adminStatusCache[userId]!;
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        _adminStatusCache[userId] = false;
        return false;
      }

      final userData = userDoc.data()!;
      final role = userData['role'] ?? 'user';
      final phoneNumber = userData['phoneNumber'] ?? '';

      // التحقق من الدور أو رقم الهاتف كاحتياطي للمستخدمين القدامى
      final isAdmin = role == 'admin' || role == 'super_admin' || phoneNumber == '+9647712010242';

      // حفظ في الكاش
      _adminStatusCache[userId] = isAdmin;
      return isAdmin;
    } catch (e) {
      return false;
    }
  }

  /// التحقق من صلاحيات المشرف الرئيسي
  static Future<bool> isSuperAdmin(String userId) async {
    try {
      // التحقق من الكاش أولاً
      if (_superAdminStatusCache.containsKey(userId)) {
        return _superAdminStatusCache[userId]!;
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        _superAdminStatusCache[userId] = false;
        return false;
      }

      final userData = userDoc.data()!;
      final role = userData['role'] ?? 'user';
      final phoneNumber = userData['phoneNumber'] ?? '';

      // التحقق من الدور الرئيسي أو رقم الهاتف كاحتياطي للمستخدمين القدامى
      final isSuperAdmin = role == 'super_admin' || phoneNumber == '+9647712010242';

      // حفظ في الكاش
      _superAdminStatusCache[userId] = isSuperAdmin;
      return isSuperAdmin;
    } catch (e) {
      return false;
    }
  }

  /// الحصول على دور المستخدم
  static Future<String> getUserRole(String userId) async {
    try {
      // التحقق من الكاش أولاً
      if (_roleCache.containsKey(userId)) {
        return _roleCache[userId]!;
      }

      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        _roleCache[userId] = 'user';
        return 'user';
      }

      final userData = userDoc.data()!;
      final role = userData['role'] ?? 'user';

      // حفظ في الكاش
      _roleCache[userId] = role;
      return role;
    } catch (e) {
      return 'user';
    }
  }

  /// الحصول على صلاحيات المستخدم
  static Future<Map<String, dynamic>> getUserPermissions(String userId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        return {};
      }

      final userData = userDoc.data()!;
      final permissions = userData['permissions'] ?? {};

      // إذا كان المستخدم مشرف رئيسي، أعطه جميع الصلاحيات
      final role = userData['role'] ?? 'user';
      final phoneNumber = userData['phoneNumber'] ?? '';
      if (role == 'super_admin' || phoneNumber == '+9647712010242') {
        return {
          'users': true,
          'reports': true,
          'statistics': true,
          'verification': true,
        };
      }

      return Map<String, dynamic>.from(permissions);
    } catch (e) {
      print('خطأ في جلب صلاحيات المستخدم: $e');
      return {};
    }
  }

  /// ترقية مستخدم إلى مشرف
  static Future<void> promoteToAdmin(String userId, String adminId) async {
    try {
      // التحقق من أن الطالب هو مشرف رئيسي
      final isSuper = await isSuperAdmin(adminId);
      if (!isSuper) {
        throw Exception('ليس لديك صلاحية للقيام بهذا الإجراء');
      }

      // إضافة الصلاحيات الافتراضية للمشرف الجديد
      final defaultPermissions = {
        'users': true,
        'reports': false,
        'statistics': true,
        'verification': false,
      };

      await updateUserInFirestore(
        userId: userId,
        data: {
          'role': 'admin',
          'permissions': defaultPermissions,
        },
      );
    } catch (e) {
      throw Exception('خطأ في ترقية المستخدم: $e');
    }
  }

  /// إزالة صلاحيات المشرف
  static Future<void> demoteFromAdmin(String userId, String adminId) async {
    try {
      // التحقق من أن الطالب هو مشرف رئيسي
      final isSuper = await isSuperAdmin(adminId);
      if (!isSuper) {
        throw Exception('ليس لديك صلاحية للقيام بهذا الإجراء');
      }

      await updateUserInFirestore(
        userId: userId,
        data: {'role': 'user'},
      );

      // مسح الكاش للمستخدم المُنزل رتبته
      _roleCache.remove(userId);
      _adminStatusCache.remove(userId);
      _superAdminStatusCache.remove(userId);
    } catch (e) {
      throw Exception('خطأ في إزالة صلاحيات المشرف: $e');
    }
  }

  /// جلب قائمة المشرفين
  static Future<List<Map<String, dynamic>>> getAdmins() async {
    try {
      final querySnapshot = await _firestore
          .collection('users')
          .where('role', whereIn: ['admin', 'super_admin'])
          .get();

      List<Map<String, dynamic>> admins = [];
      for (var doc in querySnapshot.docs) {
        final userData = doc.data();
        userData['id'] = doc.id;
        admins.add(userData);
      }

      return admins;
    } catch (e) {
      print('خطأ في جلب قائمة المشرفين: $e');
      return [];
    }
  }

  /// إرسال إشعار للمستخدم
  static Future<void> _sendNotificationToUser(
    String userId,
    String title,
    String body,
    String type,
  ) async {
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // فشل في إرسال الإشعار - لا نريد أن يؤثر على العملية الأساسية
      print('خطأ في إرسال الإشعار: $e');
    }
  }

  /// جلب المنتجات مع cache للأداء الأفضل
  static Future<List<Map<String, dynamic>>> getProducts({
    String? category,
    int limit = 20,
    bool includeExpired = false, // إضافة معامل لتضمين المنتجات المنتهية أم لا
  }) async {
    try {
      // التحقق من الـ cache للمنتجات العامة (بدون فلترة)
      if (category == null || category.isEmpty) {
        if (_productsCache != null &&
            _productsCacheTime != null &&
            DateTime.now().difference(_productsCacheTime!) < _cacheTimeout) {
          List<Map<String, dynamic>> cachedProducts = _productsCache!.take(limit).toList();
          
          // فلترة المنتجات المنتهية دائماً إلا إذا كان includeExpired true
          // الآن هذا يتم على مستوى قاعدة البيانات
          if (!includeExpired) {
            cachedProducts = cachedProducts.where((product) => 
              product['status'] == 'active').toList();
          }
          
          // فلترة منتجات المستخدمين المحظورين
          return await _filterBlockedUsersProducts(cachedProducts);
        }
      }

      Query query = _firestore
          .collection('products')
          .where('isActive', isEqualTo: true)
          .where('status', isEqualTo: 'active') // عرض المنتجات النشطة فقط
          .orderBy('createdAt', descending: true);

      if (category != null && category.isNotEmpty) {
        query = query.where('category', isEqualTo: category);
      }

      final querySnapshot = await query.limit(limit).get();

      List<Map<String, dynamic>> products = [];
      for (var doc in querySnapshot.docs) {
        final productData = doc.data() as Map<String, dynamic>;
        productData['id'] = doc.id;
        
        // تخطي المنتجات المنتهية - سبق فلترتها في الاستعلام
        // إضافة معلومات المستخدم فقط
        
        // الحصول على بيانات المستخدم
        final userData = await getUserFromFirestore(productData['userId']);
        productData['userDisplayName'] = userData?['displayName'] ?? '';
        productData['userPhone'] = userData?['phoneNumber'] ?? '';
        productData['userProfileImage'] = userData?['profileImageUrl'] ?? '';
        
        products.add(productData);
      }
      
      // فلترة منتجات المستخدمين المحظورين
      products = await _filterBlockedUsersProducts(products);
      
      // حفظ في الـ cache للمنتجات العامة فقط
      if (category == null || category.isEmpty) {
        _productsCache = products;
        _productsCacheTime = DateTime.now();
      }
      
      return products;
    } catch (e) {
      print('خطأ في جلب المنتجات: $e');
      return [];
    }
  }
  
  /// جلب المنتجات المنتهية الصلاحية لمستخدم معين (الآن ترجع قائمة فارغة لأن المنتجات المنتهية تحذف تلقائياً)
  static Future<List<Map<String, dynamic>>> getExpiredProducts({
    required String userId,
    int limit = 20,
  }) async {
    // لا توجد منتجات منتهية لأنها تحذف تلقائياً
    return [];
  }
  
  /// جلب المنتجات النشطة لمستخدم معين
  static Future<List<Map<String, dynamic>>> getUserActiveProducts({
    required String userId,
    int limit = 20,
  }) async {
    try {
      Query query = _firestore
          .collection('products')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(limit);

      final querySnapshot = await query.get();

      List<Map<String, dynamic>> products = [];
      for (var doc in querySnapshot.docs) {
        final productData = doc.data() as Map<String, dynamic>;
        productData['id'] = doc.id;
        
        // الحصول على بيانات المستخدم
        final userData = await getUserFromFirestore(productData['userId']);
        productData['userDisplayName'] = userData?['displayName'] ?? '';
        productData['userPhone'] = userData?['phoneNumber'] ?? '';
        productData['userProfileImage'] = userData?['profileImageUrl'] ?? '';
        
        products.add(productData);
      }
      
      return products;
    } catch (e) {
      print('خطأ في جلب منتجات المستخدم النشطة: $e');
      return [];
    }
  }
  
  /// فلترة منتجات المستخدمين المحظورين
  static Future<List<Map<String, dynamic>>> _filterBlockedUsersProducts(List<Map<String, dynamic>> products) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return products;

      // الحصول على قائمة المستخدمين المحظورين
      final blockedUsersQuery = await _firestore
          .collection('blocks')
          .where('blockerUserId', isEqualTo: currentUser.uid)
          .get();

      final blockedUserIds = blockedUsersQuery.docs
          .map((doc) => doc.data()['blockedUserId'] as String)
          .toSet();

      // الحصول على قائمة المستخدمين الذين حظروا المستخدم الحالي
      final blockingUsersQuery = await _firestore
          .collection('blocks')
          .where('blockedUserId', isEqualTo: currentUser.uid)
          .get();

      final blockingUserIds = blockingUsersQuery.docs
          .map((doc) => doc.data()['blockerUserId'] as String)
          .toSet();

      // فلترة المنتجات
      return products.where((product) {
        final userId = product['userId'];
        return !blockedUserIds.contains(userId) && !blockingUserIds.contains(userId);
      }).toList();
    } catch (e) {
      print('خطأ في فلترة منتجات المستخدمين المحظورين: $e');
      return products;
    }
  }
  
  /// حذف الإعلانات المنتهية تلقائياً (بعد 1 دقيقة)
  static Future<int> deleteExpiredProducts() async {
    try {
      final now = DateTime.now();
      final oneMinuteAgo = now.subtract(const Duration(minutes: 1));

      final querySnapshot = await _firestore
          .collection('products')
          .where('createdAt', isLessThan: Timestamp.fromDate(oneMinuteAgo))
          .get();

      int deletedCount = 0;

      // حذف كل منتج منتهي
      for (var doc in querySnapshot.docs) {
        try {
          await doc.reference.delete();
          deletedCount++;
        } catch (e) {
          print('خطأ في حذف المنتج ${doc.id}: $e');
        }
      }

      // مسح الكاش بعد الحذف
      _productsCache = null;
      _productsCacheTime = null;

      print('تم حذف $deletedCount منتج منتهي الصلاحية');
      return deletedCount;
    } catch (e) {
      print('خطأ في حذف المنتجات المنتهية: $e');
      return 0;
    }
  }
  
  /// حذف المنتجات المنتهية تلقائياً
  static Future<int> updateExpiredProductsStatus() async {
    try {
      final now = DateTime.now();

      // البحث عن المنتجات التي انتهت صلاحيتها ولكن مازالت active
      final querySnapshot = await _firestore
          .collection('products')
          .where('status', isEqualTo: 'active')
          .where('expireAt', isLessThan: Timestamp.fromDate(now))
          .get();

      int deletedCount = 0;
      WriteBatch batch = _firestore.batch();

      // حذف كل منتج منتهي
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
        deletedCount++;
      }

      // تنفيذ جميع الحذف
      if (deletedCount > 0) {
        await batch.commit();
      }

      // مسح الكاش بعد الحذف
      _productsCache = null;
      _productsCacheTime = null;

      print('تم حذف $deletedCount منتج منتهي الصلاحية');
      return deletedCount;
    } catch (e) {
      print('خطأ في حذف المنتجات المنتهية: $e');
      return 0;
    }
  }
  
  /// تجديد منتج منتهي الصلاحية وإعادة تفعيله
  static Future<void> renewProduct(String productId) async {
    try {
      final now = DateTime.now();
      final newExpireDate = now.add(const Duration(days: 10)); // 10 days for production
      
      await _firestore.collection('products').doc(productId).update({
        'status': 'active',
        'expireAt': Timestamp.fromDate(newExpireDate),
        'renewedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(), // تحديث تاريخ الإنشاء للعرض في المقدمة
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // مسح الكاش بعد التجديد
      _productsCache = null;
      _productsCacheTime = null;
      
      print('تم تجديد المنتج $productId بنجاح');
    } catch (e) {
      print('خطأ في تجديد المنتج: $e');
      throw Exception('خطأ في تجديد المنتج: $e');
    }
  }

  // ==================== وظائف المزايدة ====================

  /// تحويل منتج موجود إلى مزاد
  static Future<void> convertProductToAuction({
    required String productId,
    required String startPrice,
    required int durationHours,
  }) async {
    try {
      final now = DateTime.now();
      final endTime = now.add(Duration(hours: durationHours));

      await _firestore.collection('products').doc(productId).update({
        'isAuction': true,
        'auctionStartPrice': startPrice,
        'auctionCurrentPrice': startPrice,
        'auctionStartTime': FieldValue.serverTimestamp(),
        'auctionEndTime': Timestamp.fromDate(endTime),
        'auctionDurationHours': durationHours,
        'auctionStatus': 'active',
        'auctionBidsCount': 0,
        'auctionHighestBidderId': null,
        'auctionWinnerId': null,
      });

      // مسح الكاش
      _productsCache = null;
      _productsCacheTime = null;
    } catch (e) {
      throw Exception('خطأ في تحويل المنتج إلى مزاد: $e');
    }
  }

  /// تقديم عرض في المزاد
  static Future<void> placeBid({
    required String productId,
    required String bidderId,
    required String bidAmount,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      // التحقق من صحة المزاد
      final productDoc = await _firestore.collection('products').doc(productId).get();
      if (!productDoc.exists) throw Exception('المنتج غير موجود');

      final productData = productDoc.data()!;
      if (productData['isAuction'] != true) throw Exception('هذا المنتج ليس مزاد');
      if (productData['auctionStatus'] != 'active') throw Exception('المزاد غير نشط');

      // منع البائع من المزايدة على منتجه
      if (productData['userId'] == bidderId) {
        throw Exception('لا يمكنك المزايدة على منتجك الخاص');
      }

      // التحقق من انتهاء وقت المزاد
      final endTime = (productData['auctionEndTime'] as Timestamp).toDate();
      if (DateTime.now().isAfter(endTime)) {
        throw Exception('انتهى وقت المزاد');
      }

      // التحقق من أن المستخدم لم يقدم عرض من قبل
      final existingBid = await _firestore
          .collection('products')
          .doc(productId)
          .collection('bids')
          .where('bidderId', isEqualTo: bidderId)
          .limit(1)
          .get();

      if (existingBid.docs.isNotEmpty) {
        throw Exception('لقد قدمت عرضاً من قبل، لا يمكن تقديم عرض آخر');
      }

      // التحقق من أن العرض أعلى من السعر الحالي
      final currentPrice = double.parse(productData['auctionCurrentPrice']);
      final newBid = double.parse(bidAmount);
      if (newBid <= currentPrice) {
        throw Exception('يجب أن يكون العرض أعلى من السعر الحالي');
      }

      // إضافة العرض إلى مجموعة العروض
      await _firestore
          .collection('products')
          .doc(productId)
          .collection('bids')
          .add({
        'bidderId': bidderId,
        'bidderPhone': user.phoneNumber,
        'amount': bidAmount,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // تحديث بيانات المزاد
      await _firestore.collection('products').doc(productId).update({
        'auctionCurrentPrice': bidAmount,
        'auctionHighestBidderId': bidderId,
        'auctionBidsCount': FieldValue.increment(1),
      });

      // مسح الكاش
      _productsCache = null;
      _productsCacheTime = null;

      // إرسال إشعار للبائع والمزايدين الآخرين
      await _sendBidNotifications(productId, bidderId, bidAmount, productData);
    } catch (e) {
      throw Exception('خطأ في تقديم العرض: $e');
    }
  }

  /// إرسال إشعارات المزايدة
  static Future<void> _sendBidNotifications(
    String productId,
    String newBidderId,
    String bidAmount,
    Map<String, dynamic> productData,
  ) async {
    try {
      final productTitle = productData['title'] ?? 'منتج';
      final sellerId = productData['userId'];

      // إشعار البائع
      if (sellerId != newBidderId) {
        await _firestore.collection('notifications').add({
          'userId': sellerId,
          'type': 'new_bid',
          'title': 'عرض جديد على مزايدتك',
          'body': 'تم تقديم عرض بقيمة $bidAmount د.ع على "$productTitle"',
          'data': {
            'productId': productId,
            'productTitle': productTitle,
            'bidAmount': bidAmount,
            'bidderId': newBidderId,
          },
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // إشعار المزايدين الآخرين
      final bidsSnapshot = await _firestore
          .collection('products')
          .doc(productId)
          .collection('bids')
          .get();

      Set<String> notifiedBidders = {newBidderId, sellerId};

      for (var bidDoc in bidsSnapshot.docs) {
        final bidData = bidDoc.data();
        final bidderId = bidData['bidderId'];

        if (!notifiedBidders.contains(bidderId)) {
          await _firestore.collection('notifications').add({
            'userId': bidderId,
            'type': 'outbid',
            'title': 'تم تجاوز عرضك',
            'body': 'تم تقديم عرض أعلى بقيمة $bidAmount د.ع على "$productTitle"',
            'data': {
              'productId': productId,
              'productTitle': productTitle,
              'bidAmount': bidAmount,
              'newBidderId': newBidderId,
            },
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          notifiedBidders.add(bidderId);
        }
      }
    } catch (e) {
      print('خطأ في إرسال إشعارات المزايدة: $e');
    }
  }

  /// جلب عروض المزاد
  static Future<List<Map<String, dynamic>>> getAuctionBids(String productId) async {
    try {
      final bidsSnapshot = await _firestore
          .collection('products')
          .doc(productId)
          .collection('bids')
          .orderBy('timestamp', descending: true)
          .get();

      List<Map<String, dynamic>> bids = [];
      for (var doc in bidsSnapshot.docs) {
        final bidData = doc.data();
        bidData['id'] = doc.id;

        // جلب بيانات المزايد
        final bidderData = await getUserFromFirestore(bidData['bidderId']);
        bidData['bidderDisplayName'] = bidderData?['displayName'] ?? 'مستخدم';
        bidData['bidderProfileImage'] = bidderData?['profileImageUrl'] ?? '';

        bids.add(bidData);
      }

      return bids;
    } catch (e) {
      print('خطأ في جلب عروض المزاد: $e');
      return [];
    }
  }

  /// إنهاء المزاد وتحديد الفائز
  static Future<void> endAuction(String productId) async {
    try {
      final productDoc = await _firestore.collection('products').doc(productId).get();
      if (!productDoc.exists) return;

      final productData = productDoc.data()!;
      if (productData['auctionStatus'] != 'active') return;

      String? winnerId = productData['auctionHighestBidderId'];

      await _firestore.collection('products').doc(productId).update({
        'auctionStatus': 'ended',
        'auctionWinnerId': winnerId,
        'auctionEndedAt': FieldValue.serverTimestamp(),
      });

      // إرسال إشعارات انتهاء المزايدة
      await _sendAuctionEndNotifications(productId, productData, winnerId);

      // مسح الكاش
      _productsCache = null;
      _productsCacheTime = null;
    } catch (e) {
      print('خطأ في إنهاء المزاد: $e');
    }
  }

  /// إرسال إشعارات انتهاء المزايدة
  static Future<void> _sendAuctionEndNotifications(
    String productId,
    Map<String, dynamic> productData,
    String? winnerId,
  ) async {
    try {
      final productTitle = productData['title'] ?? 'منتج';
      final sellerId = productData['userId'];
      final finalPrice = productData['auctionCurrentPrice'] ?? productData['auctionStartPrice'];

      // إشعار البائع
      await _firestore.collection('notifications').add({
        'userId': sellerId,
        'type': 'auction_ended',
        'title': 'انتهت مزايدتك',
        'body': winnerId != null
            ? 'انتهت مزايدة "$productTitle" بسعر $finalPrice د.ع'
            : 'انتهت مزايدة "$productTitle" بدون عروض',
        'data': {
          'productId': productId,
          'productTitle': productTitle,
          'finalPrice': finalPrice,
          'winnerId': winnerId,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // إشعار الفائز
      if (winnerId != null) {
        await _firestore.collection('notifications').add({
          'userId': winnerId,
          'type': 'auction_won',
          'title': 'مبروك! فزت بالمزايدة',
          'body': 'فزت بمزايدة "$productTitle" بسعر $finalPrice د.ع',
          'data': {
            'productId': productId,
            'productTitle': productTitle,
            'finalPrice': finalPrice,
            'sellerId': sellerId,
          },
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // إشعار المزايدين الآخرين
      final bidsSnapshot = await _firestore
          .collection('products')
          .doc(productId)
          .collection('bids')
          .get();

      Set<String> notifiedUsers = {sellerId};
      if (winnerId != null) notifiedUsers.add(winnerId);

      for (var bidDoc in bidsSnapshot.docs) {
        final bidData = bidDoc.data();
        final bidderId = bidData['bidderId'];

        if (!notifiedUsers.contains(bidderId)) {
          await _firestore.collection('notifications').add({
            'userId': bidderId,
            'type': 'auction_lost',
            'title': 'انتهت المزايدة',
            'body': 'انتهت مزايدة "$productTitle" بسعر $finalPrice د.ع',
            'data': {
              'productId': productId,
              'productTitle': productTitle,
              'finalPrice': finalPrice,
              'winnerId': winnerId,
            },
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          notifiedUsers.add(bidderId);
        }
      }
    } catch (e) {
      print('خطأ في إرسال إشعارات انتهاء المزايدة: $e');
    }
  }

  /// جلب المزايدات النشطة
  static Future<List<Map<String, dynamic>>> getActiveAuctions({int limit = 20}) async {
    try {
      final now = Timestamp.now();
      final querySnapshot = await _firestore
          .collection('products')
          .where('status', isEqualTo: 'active')
          .where('isAuction', isEqualTo: true)
          .where('auctionStatus', isEqualTo: 'active')
          .where('auctionEndTime', isGreaterThan: now)
          .orderBy('auctionEndTime')
          .limit(limit)
          .get();

      List<Map<String, dynamic>> auctions = [];
      for (var doc in querySnapshot.docs) {
        final auctionData = doc.data();
        auctionData['id'] = doc.id;

        // جلب بيانات البائع
        final userData = await getUserFromFirestore(auctionData['userId']);
        auctionData['userDisplayName'] = userData?['displayName'] ?? '';
        auctionData['userPhone'] = userData?['phoneNumber'] ?? '';
        auctionData['userProfileImage'] = userData?['profileImageUrl'] ?? '';

        auctions.add(auctionData);
      }

      return auctions;
    } catch (e) {
      print('خطأ في جلب المزايدات النشطة: $e');
      return [];
    }
  }

  /// مراقبة وإنهاء المزايدات المنتهية تلقائياً
  static Future<void> checkAndEndExpiredAuctions() async {
    try {
      final now = Timestamp.now();
      final expiredAuctions = await _firestore
          .collection('products')
          .where('isAuction', isEqualTo: true)
          .where('auctionStatus', isEqualTo: 'active')
          .where('auctionEndTime', isLessThanOrEqualTo: now)
          .get();

      for (var doc in expiredAuctions.docs) {
        await endAuction(doc.id);
      }

      print('تم فحص وإنهاء ${expiredAuctions.docs.length} مزايدة منتهية');
    } catch (e) {
      print('خطأ في فحص المزايدات المنتهية: $e');
    }
  }

  /// جلب فئات المنتجات
  static Future<List<String>> getCategories() async {
    // التحقق من الكاش أولاً
    if (_categoriesCache != null && 
        _categoriesCacheTime != null && 
        DateTime.now().difference(_categoriesCacheTime!) < _categoriesCacheTimeout) {
      return _categoriesCache!;
    }
    
    // الفئات الثابتة
    final categories = [
      'مركبات',
      'إلكترونيات',
      'أثاث ومنزل',
      'أزياء وملابس',
      'رياضة ولياقة',
      'كتب وهوايات',
      'وظائف',
      'خدمات',
      'عقارات',
      'أخرى'
    ];
    
    // حفظ في الكاش
    _categoriesCache = categories;
    _categoriesCacheTime = DateTime.now();
    
    return categories;
  }

  // ===== REALTIME DATABASE METHODS =====

  /// إضافة مستخدم إلى Realtime Database
  static Future<void> addUserToRealtimeDB({
    required String userId,
    required String phoneNumber,
    String? displayName,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      rtdb.DatabaseReference ref = _realtimeDb.ref('users/$userId');
      await ref.set({
        'phoneNumber': phoneNumber,
        'displayName': displayName ?? '',
        'createdAt': rtdb.ServerValue.timestamp,
        'lastSeen': rtdb.ServerValue.timestamp,
        'isOnline': true,
        ...?additionalData,
      });
    } catch (e) {
      throw Exception('خطأ في إضافة المستخدم إلى قاعدة البيانات: $e');
    }
  }

  /// الحصول على بيانات المستخدم من Realtime Database
  static Future<Map<String, dynamic>?> getUserFromRealtimeDB(String userId) async {
    try {
      rtdb.DatabaseReference ref = _realtimeDb.ref('users/$userId');
      rtdb.DataSnapshot snapshot = await ref.get();
      
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      throw Exception('خطأ في استرجاع بيانات المستخدم: $e');
    }
  }

  /// تحديث حالة المستخدم (متصل/غير متصل)
  static Future<void> updateUserStatus({
    required String userId,
    required bool isOnline,
  }) async {
    try {
      rtdb.DatabaseReference ref = _realtimeDb.ref('users/$userId');
      await ref.update({
        'isOnline': isOnline,
        'lastSeen': rtdb.ServerValue.timestamp,
      });
    } catch (e) {
      throw Exception('خطأ في تحديث حالة المستخدم: $e');
    }
  }

  /// إرسال رد على قصة
  static Future<void> sendStoryReply({
    required String chatId,
    required String message,
    required Map<String, dynamic> storyData,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // إضافة الرسالة مع معلومات القصة
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': user.uid,
        'content': message,
        'type': 'story_reply',
        'storyData': storyData,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // تحديث آخر رسالة
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': '📸 رد على قصة: $message',
        'lastMessageType': 'story_reply',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount_${storyData['userId']}': FieldValue.increment(1),
      });
    } catch (e) {
      print('خطأ في إرسال رد القصة: $e');
      throw e;
    }
  }

  /// الإبلاغ عن مستخدم
  static Future<void> reportUser({
    required String reportedUserId,
    required String reason,
    String? details,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('يجب تسجيل الدخول');

      await _firestore.collection('reports').add({
        'type': 'user',
        'reportedUserId': reportedUserId,
        'reporterUserId': user.uid,
        'reason': reason,
        'details': details,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('خطأ في إرسال البلاغ: $e');
      throw e;
    }
  }

  /// الإبلاغ عن منتج
  static Future<void> reportProduct({
    required String productId,
    required String productOwnerId,
    required String reason,
    String? details,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('يجب تسجيل الدخول');

      await _firestore.collection('reports').add({
        'type': 'product',
        'productId': productId,
        'productOwnerId': productOwnerId,
        'reporterUserId': user.uid,
        'reason': reason,
        'details': details,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('خطأ في إرسال البلاغ: $e');
      throw e;
    }
  }

  /// الحصول على البلاغات للمشرف
  static Future<List<Map<String, dynamic>>> getReports({String? status}) async {
    try {
      Query query = _firestore.collection('reports');
      
      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }
      
      final snapshot = await query
          .orderBy('createdAt', descending: true)
          .get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('خطأ في جلب البلاغات: $e');
      return [];
    }
  }

  /// تحديث حالة البلاغ
  static Future<void> updateReportStatus(String reportId, String status) async {
    try {
      await _firestore.collection('reports').doc(reportId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('خطأ في تحديث حالة البلاغ: $e');
      throw e;
    }
  }

  /// حذف منتج من قبل المشرف
  static Future<void> deleteProductByAdmin(String productId) async {
    try {
      await _firestore.collection('products').doc(productId).delete();
    } catch (e) {
      print('خطأ في حذف المنتج: $e');
      throw e;
    }
  }

  /// حذف حساب مستخدم من قبل المشرف
  static Future<void> deleteUserByAdmin(String userId) async {
    try {
      // استدعاء Cloud Function لحذف المستخدم نهائياً
      final callable = FirebaseFunctions.instance.httpsCallable('permanentlyDeleteUser');
      final result = await callable.call(<String, dynamic>{
        'userId': userId,
      });
      
      if (result.data['success'] == true) {
        // مسح الكاش
        clearUserCache(userId);
        print('تم حذف المستخدم نهائياً');
      } else {
        throw Exception('فشل في حذف المستخدم نهائياً');
      }
    } catch (e) {
      print('خطأ في حذف المستخدم نهائياً: $e');
      throw Exception('فشل في حذف المستخدم نهائياً: $e');
    }
  }
  /// إرسال رسالة في المحادثة مع فحص الحظر
  static Future<void> sendMessage({
    required String chatId,
    required String message,
    String? imageUrl,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      // الحصول على معلومات المحادثة للتحقق من المشاركين
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      if (chatDoc.exists) {
        final participants = List<String>.from(chatDoc.data()?['participants'] ?? []);
        final otherUserId = participants.firstWhere((id) => id != user.uid, orElse: () => '');
        
        if (otherUserId.isNotEmpty) {
          // فحص حالة الحظر
          final isBlocked = await isUserBlocked(otherUserId);
          final isBlockedBy = await isBlockedByUser(otherUserId);
          
          if (isBlocked || isBlockedBy) {
            throw Exception('لا يمكن إرسال رسائل إلى هذا المستخدم');
          }
        }
      }

      rtdb.DatabaseReference ref = _realtimeDb.ref('chats/$chatId/messages');
      await ref.push().set({
        'senderId': user.uid,
        'senderPhone': user.phoneNumber,
        'message': message,
        'imageUrl': imageUrl,
        'timestamp': rtdb.ServerValue.timestamp,
        'isRead': false,
      });

      // تحديث آخر رسالة في المحادثة
      await _realtimeDb.ref('chats/$chatId').update({
        'lastMessage': message,
        'lastMessageTime': rtdb.ServerValue.timestamp,
        'lastSenderId': user.uid,
      });
    } catch (e) {
      throw Exception('خطأ في إرسال الرسالة: $e');
    }
  }

  /// الاستماع للرسائل في المحادثة
  static Stream<rtdb.DatabaseEvent> getChatMessagesStream(String chatId) {
    return _realtimeDb
        .ref('chats/$chatId/messages')
        .orderByChild('timestamp')
        .onValue;
  }

  // ===== UTILITY METHODS =====

  /// تسجيل المستخدم الحالي في قواعد البيانات
  static Future<void> registerCurrentUser() async {
    final user = currentUser;
    if (user == null) return;

    try {
      // التحقق من وجود المستخدم في Firestore أولاً
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      
      if (!userDoc.exists) {
        // إنشاء مستخدم جديد بالقيم الافتراضية
        await _firestore.collection('users').doc(user.uid).set({
          'phoneNumber': user.phoneNumber ?? '',
          'displayName': '',
          'handle': '',
          'profileImageUrl': '',
          'isVerified': false,
          'createdAt': FieldValue.serverTimestamp(),
          'lastSeen': FieldValue.serverTimestamp(),
          'isActive': true,
        });
      } else {
        final userData = userDoc.data()!;
        Map<String, dynamic> updateData = {
          'phoneNumber': user.phoneNumber ?? '',
          'lastSeen': FieldValue.serverTimestamp(),
          'isActive': true,
        };

        // التأكد من وجود تاريخ الانضمام - استخدم تاريخ إنشاء الحساب من Firebase Auth إذا لم يكن موجوداً
        if (userData['createdAt'] == null && user.metadata.creationTime != null) {
          updateData['createdAt'] = Timestamp.fromDate(user.metadata.creationTime!);
        }

        await _firestore.collection('users').doc(user.uid).set(
          updateData,
          SetOptions(merge: true)
        );
      }

      // إضافة إلى Realtime Database
      await addUserToRealtimeDB(
        userId: user.uid,
        phoneNumber: user.phoneNumber ?? '',
      );
    } catch (e) {
      print('خطأ في تسجيل المستخدم: $e');
    }
  }

  /// تحديث آخر ظهور للمستخدم
  static Future<void> updateLastSeen() async {
    final user = currentUser;
    if (user == null) return;

    // تحديث في Firestore
    await updateUserInFirestore(
      userId: user.uid,
      data: {'lastSeen': FieldValue.serverTimestamp()},
    );

    // تحديث في Realtime Database
    await updateUserStatus(userId: user.uid, isOnline: true);
  }

  /// تسجيل خروج المستخدم من قواعد البيانات
  static Future<void> signOutUser() async {
    final user = currentUser;
    if (user != null) {
      // تحديث حالة المستخدم قبل تسجيل الخروج
      await updateUserStatus(userId: user.uid, isOnline: false);
    }
  }

  // ===== CHAT METHODS =====

  /// رفع صورة للدردشة
  static Future<String> uploadChatImage(File imageFile) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      final fileName = 'chat_images/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child(fileName);

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      throw Exception('خطأ في رفع الصورة: $e');
    }
  }

  /// رفع رسالة صوتية للدردشة
  static Future<String> uploadVoiceMessage(File audioFile) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      final fileName = 'voice_messages/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      final ref = FirebaseStorage.instance.ref().child(fileName);

      final uploadTask = ref.putFile(audioFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      throw Exception('خطأ في رفع الرسالة الصوتية: $e');
    }
  }

  /// إنشاء محادثة جديدة أو الحصول على محادثة موجودة
  static Future<String> createOrGetChat(String otherUserId) async {
    try {
      final currentUserId = currentUser?.uid;
      if (currentUserId == null) throw Exception('المستخدم غير مسجل الدخول');

      // البحث عن محادثة موجودة
      final existingChat = await _firestore
          .collection('chats')
          .where('participants', arrayContains: currentUserId)
          .get();

      for (var doc in existingChat.docs) {
        final participants = List<String>.from(doc.data()['participants'] ?? []);
        if (participants.contains(otherUserId)) {
          return doc.id;
        }
      }

      // إنشاء محادثة جديدة
      final chatRef = await _firestore.collection('chats').add({
        'participants': [currentUserId, otherUserId],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageType': 'text',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount_$currentUserId': 0,
        'unreadCount_$otherUserId': 0,
      });

      return chatRef.id;
    } catch (e) {
      throw Exception('خطأ في إنشاء المحادثة: $e');
    }
  }

  /// بدء محادثة من صفحة المنتج
  static Future<String> startChatFromProduct({
    required String productId,
    required String sellerId,
    required String productTitle,
    String? productPrice,
    String? productLocation,
    String? productImageUrl,
  }) async {
    try {
      final chatId = await createOrGetChat(sellerId);
      
      // التحقق من وجود رسالة إعلان سابقة لنفس المنتج
      final existingMessages = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('type', isEqualTo: 'product')
          .where('product.id', isEqualTo: productId)
          .limit(1)
          .get();

      // إذا لم توجد رسالة سابقة لهذا المنتج، أرسل رسالة جديدة
      if (existingMessages.docs.isEmpty) {
        // إعداد بيانات المنتج للرسالة
        final productData = {
          'id': productId,
          'title': productTitle,
          'price': productPrice ?? '',
          'location': productLocation ?? '',
          'imageUrl': productImageUrl ?? '',
        };
        
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        
        // إرسال رسالة تلقائية مع معلومات المنتج
        await _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .add({
          'senderId': currentUserId,
          'content': 'مرحباً، أنا مهتم بهذا الإعلان',
          'type': 'product',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'product': productData,
        });

        // تحديث آخر رسالة
        await _firestore.collection('chats').doc(chatId).update({
          'lastMessage': 'مرحباً، أنا مهتم بهذا الإعلان',
          'lastMessageType': 'product',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount_$sellerId': FieldValue.increment(1),
        });
        
        // حفظ الإشعار في قاعدة البيانات (سيتم إرسال إشعار FCM بواسطة Firebase Functions)
        if (currentUserId != null) {
          // جلب اسم المستخدم الحالي
          final userDoc = await _firestore.collection('users').doc(currentUserId).get();
          String userName = 'مستخدم';
          if (userDoc.exists && userDoc.data() != null) {
            userName = userDoc.data()!['displayName'] ?? 'مستخدم';
          }
          
          // حفظ الإشعار في قاعدة البيانات
          await NotificationService().saveNotification(
            userId: sellerId,
            title: 'طلب شراء جديد',
            body: '$userName يريد شراء إعلانك "$productTitle"',
            data: {
              'type': 'new_message',
              'chatId': chatId,
              'productId': productId,
              'senderId': currentUserId,
            },
          );
        }
      }

      return chatId;
    } catch (e) {
      throw Exception('خطأ في بدء المحادثة: $e');
    }
  }

  // ===== RATINGS & REVIEWS METHODS =====
  
  /// إضافة تقييم ومراجعة للبائع
  static Future<void> addReview({
    required String sellerId,
    required String productId,
    required double rating,
    required String comment,
    String? buyerName,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');
      
      // التحقق من عدم وجود تقييم سابق لنفس المنتج
      final existingReview = await _firestore
          .collection('reviews')
          .where('buyerId', isEqualTo: user.uid)
          .where('productId', isEqualTo: productId)
          .get();
      
      if (existingReview.docs.isNotEmpty) {
        throw Exception('لقد قمت بتقييم هذا المنتج مسبقاً');
      }
      
      // إضافة التقييم
      await _firestore.collection('reviews').add({
        'sellerId': sellerId,
        'buyerId': user.uid,
        'buyerName': buyerName ?? 'مستخدم',
        'productId': productId,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
        'isVerifiedPurchase': true,
      });
      
      // تحديث متوسط التقييم للبائع
      await _updateSellerRating(sellerId);
      
    } catch (e) {
      throw Exception('خطأ في إضافة التقييم: $e');
    }
  }
  
  /// تحديث متوسط تقييم البائع
  static Future<void> _updateSellerRating(String sellerId) async {
    try {
      // جلب جميع التقييمات للبائع
      final reviews = await _firestore
          .collection('reviews')
          .where('sellerId', isEqualTo: sellerId)
          .get();
      
      if (reviews.docs.isEmpty) {
        await _firestore.collection('users').doc(sellerId).update({
          'averageRating': 0.0,
          'totalReviews': 0,
        });
        return;
      }
      
      // حساب المتوسط
      double totalRating = 0;
      for (var doc in reviews.docs) {
        totalRating += (doc.data()['rating'] as num).toDouble();
      }
      
      double averageRating = totalRating / reviews.docs.length;
      
      // تحديث بيانات البائع
      await _firestore.collection('users').doc(sellerId).update({
        'averageRating': double.parse(averageRating.toStringAsFixed(1)),
        'totalReviews': reviews.docs.length,
      });
      
      // مسح الكاش
      _userCache.remove(sellerId);
      
    } catch (e) {
      print('خطأ في تحديث تقييم البائع: $e');
    }
  }
  
  /// جلب تقييمات البائع
  static Future<List<Map<String, dynamic>>> getSellerReviews(String sellerId) async {
    try {
      final reviews = await _firestore
          .collection('reviews')
          .where('sellerId', isEqualTo: sellerId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      
      List<Map<String, dynamic>> reviewsList = [];
      for (var doc in reviews.docs) {
        final reviewData = doc.data();
        reviewData['id'] = doc.id;
        
        // جلب معلومات المشتري
        final buyerData = await getUserFromFirestore(reviewData['buyerId']);
        reviewData['buyerProfileImage'] = buyerData?['profileImageUrl'] ?? '';
        reviewData['buyerDisplayName'] = buyerData?['displayName'] ?? reviewData['buyerName'] ?? 'مستخدم';
        
        reviewsList.add(reviewData);
      }
      
      return reviewsList;
    } catch (e) {
      print('خطأ في جلب التقييمات: $e');
      return [];
    }
  }
  
  /// التحقق من إمكانية التقييم
  static Future<bool> canReviewProduct(String productId, String sellerId) async {
    try {
      final user = currentUser;
      if (user == null) return false;
      
      // التحقق من عدم وجود تقييم سابق
      final existingReview = await _firestore
          .collection('reviews')
          .where('buyerId', isEqualTo: user.uid)
          .where('productId', isEqualTo: productId)
          .get();
      
      return existingReview.docs.isEmpty;
    } catch (e) {
      print('خطأ في التحقق من إمكانية التقييم: $e');
      return false;
    }
  }

  // ===== RECOMMENDATIONS METHODS =====
  
  /// جلب المنتجات الموصى بها للمستخدم
  static Future<List<Map<String, dynamic>>> getRecommendedProducts({
    int limit = 10,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        // إذا لم يكن مسجل دخول، أظهر المنتجات الأحدث
        return await getProducts(limit: limit);
      }
      
      // جلب تاريخ المشاهدة والتفاعل للمستخدم
      final userInteractions = await _getUserInteractions(user.uid);
      
      // استخراج الفئات المفضلة
      Set<String> preferredCategories = {};
      Set<String> viewedProductIds = {};
      
      for (var interaction in userInteractions) {
        if (interaction['category'] != null) {
          preferredCategories.add(interaction['category']);
        }
        if (interaction['productId'] != null) {
          viewedProductIds.add(interaction['productId']);
        }
      }
      
      List<Map<String, dynamic>> recommendations = [];
      
      // إذا كان هناك فئات مفضلة
      if (preferredCategories.isNotEmpty) {
        for (String category in preferredCategories) {
          final categoryProducts = await getProducts(
            category: category,
            limit: limit ~/ preferredCategories.length + 2,
          );
          
          // فلترة المنتجات المشاهدة مسبقاً
          final newProducts = categoryProducts.where((product) =>
            !viewedProductIds.contains(product['id']) &&
            product['userId'] != user.uid // استبعاد منتجات المستخدم نفسه
          ).toList();
          
          recommendations.addAll(newProducts);
        }
      }
      
      // إذا لم تكن هناك توصيات كافية، أضف منتجات عشوائية
      if (recommendations.length < limit) {
        final randomProducts = await getProducts(limit: limit * 2);
        
        for (var product in randomProducts) {
          if (recommendations.length >= limit) break;
          
          if (!viewedProductIds.contains(product['id']) &&
              product['userId'] != user.uid &&
              !recommendations.any((r) => r['id'] == product['id'])) {
            recommendations.add(product);
          }
        }
      }
      
      // خلط التوصيات وإرجاع العدد المطلوب
      recommendations.shuffle();
      return recommendations.take(limit).toList();
      
    } catch (e) {
      print('خطأ في جلب التوصيات: $e');
      // في حالة الخطأ، أرجع منتجات عادية
      return await getProducts(limit: limit);
    }
  }
  
  /// تسجيل تفاعل المستخدم مع منتج
  static Future<void> recordProductInteraction({
    required String productId,
    required String interactionType, // 'view', 'like', 'message', 'call'
    String? category,
  }) async {
    try {
      final user = currentUser;
      if (user == null) return;
      
      await _firestore.collection('user_interactions').add({
        'userId': user.uid,
        'productId': productId,
        'interactionType': interactionType,
        'category': category,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
    } catch (e) {
      print('خطأ في تسجيل التفاعل: $e');
    }
  }
  
  /// جلب تفاعلات المستخدم
  static Future<List<Map<String, dynamic>>> _getUserInteractions(String userId) async {
    try {
      final interactions = await _firestore
          .collection('user_interactions')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();
      
      return interactions.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      print('خطأ في جلب التفاعلات: $e');
      return [];
    }
  }
  
  /// جلب المنتجات المشابهة
  static Future<List<Map<String, dynamic>>> getSimilarProducts({
    required String productId,
    required String category,
    int limit = 6,
  }) async {
    try {
      final products = await getProducts(category: category, limit: limit + 1);

      // فلترة المنتج الحالي
      return products.where((p) => p['id'] != productId).take(limit).toList();

    } catch (e) {
      print('خطأ في جلب المنتجات المشابهة: $e');
      return [];
    }
  }

  /// حذف محادثة كاملة مع جميع الرسائل
  static Future<void> deleteChat(String chatId) async {
    try {
      final chatRef = _firestore.collection('chats').doc(chatId);

      // حذف جميع الرسائل في المجموعة الفرعية
      final messagesSnapshot = await chatRef.collection('messages').get();
      final batch = _firestore.batch();

      for (var messageDoc in messagesSnapshot.docs) {
        batch.delete(messageDoc.reference);
      }

      // تنفيذ حذف الرسائل
      if (messagesSnapshot.docs.isNotEmpty) {
        await batch.commit();
      }

      // حذف المحادثة نفسها
      await chatRef.delete();

      print('تم حذف المحادثة $chatId بنجاح');
    } catch (e) {
      print('خطأ في حذف المحادثة: $e');
      throw Exception('خطأ في حذف المحادثة: $e');
    }
  }

  /// تحديث منتج معلق (للتعديل)
  static Future<void> updatePendingProduct(String pendingProductId, Map<String, dynamic> data) async {
    try {
      // جلب بيانات المنتج للحصول على معرف المستخدم
      final productDoc = await _firestore.collection('pending_products').doc(pendingProductId).get();
      if (!productDoc.exists) {
        throw Exception('المنتج غير موجود');
      }

      final productData = productDoc.data()!;
      final userId = productData['userId'];

      // حذف إشعارات الرفض السابقة لهذا المنتج
      final rejectionNotifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'product_rejected')
          .where('pendingProductId', isEqualTo: pendingProductId)
          .get();

      final batch = _firestore.batch();
      for (var doc in rejectionNotifications.docs) {
        batch.delete(doc.reference);
      }

      // تحديث المنتج
      await _firestore.collection('pending_products').doc(pendingProductId).update({
        ...data,
        'status': 'pending', // إعادة تعيين الحالة للمراجعة
        'updatedAt': FieldValue.serverTimestamp(),
        // مسح حقول المراجعة لإعادة المراجعة
        'reviewedAt': null,
        'reviewedBy': null,
        'rejectionReason': null,
      });

      // تنفيذ حذف الإشعارات
      if (rejectionNotifications.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      throw Exception('خطأ في تحديث المنتج المعلق: $e');
    }
  }

  // ===== FAVORITES METHODS =====

  /// إضافة منتج للمفضلة
  static Future<void> addToFavorites(String productId) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      // التحقق من عدم وجود المنتج في المفضلة مسبقاً
      final existingFavorite = await _firestore
          .collection('user_favorites')
          .where('userId', isEqualTo: user.uid)
          .where('productId', isEqualTo: productId)
          .get();

      if (existingFavorite.docs.isNotEmpty) {
        throw Exception('المنتج موجود في المفضلة بالفعل');
      }

      await _firestore.collection('user_favorites').add({
        'userId': user.uid,
        'productId': productId,
        'addedAt': FieldValue.serverTimestamp(),
      });

    } catch (e) {
      throw Exception('خطأ في إضافة المنتج للمفضلة: $e');
    }
  }

  /// إزالة منتج من المفضلة
  static Future<void> removeFromFavorites(String productId) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      final querySnapshot = await _firestore
          .collection('user_favorites')
          .where('userId', isEqualTo: user.uid)
          .where('productId', isEqualTo: productId)
          .get();

      for (var doc in querySnapshot.docs) {
        await doc.reference.delete();
      }

    } catch (e) {
      throw Exception('خطأ في إزالة المنتج من المفضلة: $e');
    }
  }

  /// التحقق من وجود منتج في المفضلة
  static Future<bool> isProductInFavorites(String productId) async {
    try {
      final user = currentUser;
      if (user == null) return false;

      final querySnapshot = await _firestore
          .collection('user_favorites')
          .where('userId', isEqualTo: user.uid)
          .where('productId', isEqualTo: productId)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print('خطأ في التحقق من المفضلة: $e');
      return false;
    }
  }

  /// جلب المنتجات المفضلة للمستخدم
  static Future<List<Map<String, dynamic>>> getUserFavorites({int limit = 50}) async {
    try {
      final user = currentUser;
      if (user == null) return [];

      final favoritesSnapshot = await _firestore
          .collection('user_favorites')
          .where('userId', isEqualTo: user.uid)
          .orderBy('addedAt', descending: true)
          .limit(limit)
          .get();

      List<Map<String, dynamic>> favoriteProducts = [];

      for (var favoriteDoc in favoritesSnapshot.docs) {
        final favoriteData = favoriteDoc.data();
        final productId = favoriteData['productId'];

        // جلب بيانات المنتج
        final productDoc = await _firestore.collection('products').doc(productId).get();
        if (productDoc.exists) {
          final productData = productDoc.data() as Map<String, dynamic>;
          productData['id'] = productId;

          // جلب بيانات البائع
          final userData = await getUserFromFirestore(productData['userId']);
          productData['userDisplayName'] = userData?['displayName'] ?? '';
          productData['userPhone'] = userData?['phoneNumber'] ?? '';
          productData['userProfileImage'] = userData?['profileImageUrl'] ?? '';

          favoriteProducts.add(productData);
        }
      }

      // فلترة منتجات المستخدمين المحظورين
      return await _filterBlockedUsersProducts(favoriteProducts);
    } catch (e) {
      print('خطأ في جلب المفضلة: $e');
      return [];
    }
  }

  /// تبديل حالة المفضلة (إضافة أو إزالة)
  static Future<bool> toggleFavorite(String productId) async {
    try {
      final isFavorite = await isProductInFavorites(productId);
      if (isFavorite) {
        await removeFromFavorites(productId);
        return false; // أصبح غير مفضل
      } else {
        await addToFavorites(productId);
        return true; // أصبح مفضل
      }
    } catch (e) {
      throw Exception('خطأ في تبديل حالة المفضلة: $e');
    }
  }

  /// إرسال طلب باقة إعلان للمراجعة
  static Future<void> submitPackageRequest({
    required String userId,
    required String package,
    required String title,
    required String description,
    required String category,
    required String price,
    required String location,
    required List<String> imageUrls,
    String condition = 'جديد',
    bool isNegotiable = false,
  }) async {
    try {
      await _firestore.collection('package_requests').add({
        'userId': userId,
        'package': package,
        'title': title,
        'description': description,
        'category': category,
        'price': price,
        'location': location,
        'imageUrls': imageUrls,
        'condition': condition,
        'isNegotiable': isNegotiable,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'reviewedAt': null,
        'reviewedBy': null,
      });

      // إرسال إشعار للمشرفين
      await _firestore.collection('notifications').add({
        'userId': 'admin', // إشعار عام للمشرفين
        'type': 'package_request',
        'title': 'طلب باقة إعلان جديد',
        'body': 'طلب باقة $package لإعلان "$title"',
        'data': {
          'userId': userId,
          'package': package,
          'title': title,
        },
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('خطأ في إرسال طلب الباقة: $e');
    }
  }

  /// جلب طلبات الباقات للمشرفين
  static Future<List<Map<String, dynamic>>> getPackageRequests() async {
    try {
      final snapshot = await _firestore
          .collection('package_requests')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      List<Map<String, dynamic>> requests = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;

        // جلب بيانات المستخدم
        final userData = await getUserFromFirestore(data['userId']);
        data['userDisplayName'] = userData?['displayName'] ?? 'مستخدم';
        data['userHandle'] = userData?['handle'] ?? '';
        data['userProfileImage'] = userData?['profileImageUrl'] ?? '';

        requests.add(data);
      }

      return requests;
    } catch (e) {
      throw Exception('خطأ في جلب طلبات الباقات: $e');
    }
  }

  /// موافقة على طلب باقة وإنشاء الإعلان
  static Future<void> approvePackageRequest(String requestId, String adminId) async {
    try {
      final requestDoc = await _firestore.collection('package_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        throw Exception('الطلب غير موجود');
      }

      final requestData = requestDoc.data()!;
      final userId = requestData['userId'];
      final package = requestData['package'];

      // حساب تاريخ الانتهاء بناءً على الباقة
      int days;
      if (package == '30 يوم') days = 30;
      else if (package == '60 يوم') days = 60;
      else if (package == '180 يوم') days = 180;
      else days = 10; // افتراضي

      final now = DateTime.now();
      final expireDate = now.add(Duration(days: days));

      // إنشاء الإعلان
      Map<String, dynamic> productData = {
        'userId': userId,
        'title': requestData['title'],
        'description': requestData['description'],
        'category': requestData['category'],
        'price': requestData['price'],
        'location': requestData['location'],
        'imageUrls': requestData['imageUrls'],
        'condition': requestData['condition'],
        'isNegotiable': requestData['isNegotiable'],
        'createdAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(expireDate),
        'status': 'active',
        'isActive': true,
        'views': 0,
        'package': package,
      };

      await _firestore.collection('products').add(productData);

      // تحديث الطلب
      await _firestore.collection('package_requests').doc(requestId).update({
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
      });

      // إرسال إشعار للمستخدم
      await _firestore.collection('notifications').add({
        'userId': userId,
        'type': 'package_approved',
        'title': 'تم قبول طلب الباقة',
        'body': 'تم قبول طلب باقة $package ونشر إعلانك',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // مسح الكاش
      _productsCache = null;
      _productsCacheTime = null;
    } catch (e) {
      throw Exception('خطأ في الموافقة على الطلب: $e');
    }
  }

  /// رفض طلب باقة
  static Future<void> rejectPackageRequest(String requestId, String adminId, String reason) async {
    try {
      final requestDoc = await _firestore.collection('package_requests').doc(requestId).get();
      if (requestDoc.exists) {
        final requestData = requestDoc.data()!;
        final userId = requestData['userId'];

        await _firestore.collection('package_requests').doc(requestId).update({
          'status': 'rejected',
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewedBy': adminId,
          'rejectionReason': reason,
        });

        // إرسال إشعار للمستخدم
        await _firestore.collection('notifications').add({
          'userId': userId,
          'type': 'package_rejected',
          'title': 'تم رفض طلب الباقة',
          'body': 'تم رفض طلب باقة ${requestData['package']}',
          'rejectionReason': reason,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('خطأ في رفض الطلب: $e');
    }
  }
}
