import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../services/database_service.dart';
import '../widgets/shimmer_widget.dart';
import 'user_profile_page.dart';
import 'profile_page.dart';

class FollowersPage extends StatefulWidget {
  final String userId;
  final String title;
  
  const FollowersPage({
    super.key,
    required this.userId,
    required this.title,
  });

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> 
    with TickerProviderStateMixin {
  
  late TabController _tabController;
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];
  StreamSubscription<QuerySnapshot>? _followersSubscription;
  StreamSubscription<QuerySnapshot>? _followingSubscription;
  Map<String, StreamSubscription<QuerySnapshot>?> _followStatusSubscriptions = {};
  bool _isLoading = true;
  Map<String, bool> _followingStatus = {};
  Map<String, bool> _followingLoading = {};
  bool _isInitialized = false;
  int _followersCount = 0;
  int _followingCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // تحديد التبويب الافتراضي بناءً على العنوان
    if (widget.title == 'يتابع') {
      _tabController.index = 1;
    }
    
    _setupListeners();
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _followersSubscription?.cancel();
    _followingSubscription?.cancel();
    // إلغاء جميع مستمعات حالة المتابعة
    for (var subscription in _followStatusSubscriptions.values) {
      subscription?.cancel();
    }
    _followStatusSubscriptions.clear();
    super.dispose();
  }

  void _setupListeners() {
    // مستمع المتابعين
    _followersSubscription = FirebaseFirestore.instance
        .collection('follows')
        .where('followedUserId', isEqualTo: widget.userId)
        .snapshots()
        .listen((snapshot) async {
      // تحديث العداد فورياً
      if (mounted) {
        setState(() {
          _followersCount = snapshot.docs.length;
        });
      }
      
      if (!_isInitialized) return; // تجاهل التحديثات قبل التهيئة
      
      List<Map<String, dynamic>> followers = [];
      for (var doc in snapshot.docs) {
        final followData = doc.data();
        final followerUserId = followData['followerUserId'];
        final userData = await DatabaseService.getUserFromFirestore(followerUserId);
        if (userData != null) {
          userData['id'] = followerUserId;
          followers.add(userData);
        }
      }
      
      if (mounted) {
        setState(() {
          _followers = followers;
        });
      }
    });

    // مستمع المتابعين
    _followingSubscription = FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: widget.userId)
        .snapshots()
        .listen((snapshot) async {
      // تحديث العداد فورياً
      if (mounted) {
        setState(() {
          _followingCount = snapshot.docs.length;
        });
      }
      
      if (!_isInitialized) return; // تجاهل التحديثات قبل التهيئة
      
      List<Map<String, dynamic>> following = [];
      for (var doc in snapshot.docs) {
        final followData = doc.data();
        final followedUserId = followData['followedUserId'];
        final userData = await DatabaseService.getUserFromFirestore(followedUserId);
        if (userData != null) {
          userData['id'] = followedUserId;
          following.add(userData);
        }
      }
      
      if (mounted) {
        setState(() {
          _following = following;
        });
      }
    });
  }

  Future<void> _loadInitialData() async {
    if (_isInitialized) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // تحميل البيانات والحالة معاً
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final results = await Future.wait([
        DatabaseService.getFollowers(widget.userId),
        DatabaseService.getFollowing(widget.userId),
      ]);
      
      final followers = results[0];
      final following = results[1];
      
      // تحميل حالة المتابعة لجميع المستخدمين
      Map<String, bool> followingStatus = {};
      Set<String> allUserIds = {};
      
      for (var follower in followers) {
        if (follower['id'] != currentUser.uid) {
          allUserIds.add(follower['id']);
        }
      }
      
      for (var followingUser in following) {
        if (followingUser['id'] != currentUser.uid) {
          allUserIds.add(followingUser['id']);
        }
      }
      
      // تحميل حالة المتابعة بشكل متوازي
      final followStatusFutures = allUserIds.map((userId) async {
        final isFollowing = await DatabaseService.isFollowing(userId);
        return MapEntry(userId, isFollowing);
      });
      
      final followStatusResults = await Future.wait(followStatusFutures);
      for (var entry in followStatusResults) {
        followingStatus[entry.key] = entry.value;
      }
      
      if (mounted) {
        setState(() {
          _followers = followers;
          _following = following;
          _followingStatus = followingStatus;
          _followersCount = followers.length;
          _followingCount = following.length;
          _isLoading = false;
          _isInitialized = true;
        });
        
        // إعداد مستمعات للتحديثات المستقبلية
        for (String userId in allUserIds) {
          _setupFollowStatusListener(userId);
        }
      }
    } catch (e) {
      print('خطأ في تحميل البيانات: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkFollowingStatus() async {
    // هذه الدالة لم تعد مطلوبة لأن التحميل يتم في _loadInitialData
    return;
  }

  void _setupFollowStatusListener(String targetUserId) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // إلغاء المستمع السابق إن وجد
    _followStatusSubscriptions[targetUserId]?.cancel();

    // إعداد مستمع جديد
    _followStatusSubscriptions[targetUserId] = FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: currentUser.uid)
        .where('followedUserId', isEqualTo: targetUserId)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _followingStatus[targetUserId] = snapshot.docs.isNotEmpty;
        });
      }
    });
  }

  Future<void> _toggleFollow(String userId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || userId == currentUser.uid) return;
    
    if (_followingLoading[userId] == true) return;
    
    final isCurrentlyFollowing = _followingStatus[userId] ?? false;
    
    if (isCurrentlyFollowing) {
      // إذا كان يتابع، نعرض شيت التأكيد
      _showUnfollowConfirmationSheet(userId);
    } else {
      // إذا لم يكن يتابع، نتابع مباشرة مع تحديث فوري
      setState(() {
        _followingStatus[userId] = true;
        _followingLoading[userId] = true;
      });

      try {
        await DatabaseService.followUser(userId);
      } catch (e) {
        // إعادة الحالة السابقة في حالة الخطأ
        setState(() {
          _followingStatus[userId] = false;
        });
        _showErrorSnackBar('خطأ في المتابعة: $e');
      } finally {
        setState(() {
          _followingLoading[userId] = false;
        });
      }
    }
  }

  void _showUnfollowConfirmationSheet(String userId) {
    // البحث عن بيانات المستخدم
    Map<String, dynamic>? userData;
    for (var follower in _followers) {
      if (follower['id'] == userId) {
        userData = follower;
        break;
      }
    }
    if (userData == null) {
      for (var following in _following) {
        if (following['id'] == userId) {
          userData = following;
          break;
        }
      }
    }
    
    if (userData == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // مؤشر السحب
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // صورة المستخدم
            CircleAvatar(
              radius: 40,
              backgroundImage: userData?['profileImageUrl']?.isNotEmpty == true
                  ? NetworkImage(userData!['profileImageUrl'])
                  : null,
              backgroundColor: Colors.grey[300],
              child: userData?['profileImageUrl']?.isEmpty != false
                  ? Icon(Icons.person, size: 40, color: Colors.grey[600])
                  : null,
            ),
            
            const SizedBox(height: 16),
            
            // اسم المستخدم
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  userData?['displayName']?.isNotEmpty == true
                      ? userData!['displayName']
                      : userData?['handle'] ?? 'مستخدم',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                if (userData?['isVerified'] == true) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.verified,
                    color: Colors.blue,
                    size: 20,
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'هل تريد إلغاء متابعة هذا الحساب؟',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // زر إلغاء المتابعة
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context); // إغلاق الشيت
                  
                  // تحديث فوري للواجهة
                  setState(() {
                    _followingStatus[userId] = false;
                    _followingLoading[userId] = true;
                  });

                  try {
                    await DatabaseService.unfollowUser(userId);
                  } catch (e) {
                    // إعادة الحالة السابقة في حالة الخطأ
                    setState(() {
                      _followingStatus[userId] = true;
                    });
                    _showErrorSnackBar('خطأ في إلغاء المتابعة: $e');
                  } finally {
                    setState(() {
                      _followingLoading[userId] = false;
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'إلغاء المتابعة',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // زر الإلغاء
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ),
            
            // مساحة آمنة للأجهزة ذات الحواف المنحنية
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.cairo(),
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'المتابعون ($_followersCount)',
                    style: GoogleFonts.cairo(fontSize: 14),
                  ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    'يتابع ($_followingCount)',
                    style: GoogleFonts.cairo(fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const FollowersShimmer()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFollowersList(),
                _buildFollowingList(),
              ],
            ),
    );
  }

  Widget _buildFollowersList() {
    if (_followers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا يوجد متابعون بعد',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _followers.length,
      itemBuilder: (context, index) {
        final follower = _followers[index];
        return _buildUserCard(follower);
      },
    );
  }

  Widget _buildFollowingList() {
    if (_following.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا يتابع أحداً بعد',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _following.length,
      itemBuilder: (context, index) {
        final following = _following[index];
        return _buildUserCard(following);
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isCurrentUser = currentUser?.uid == user['id'];
    final isFollowing = _followingStatus[user['id']] ?? false;
    final isLoading = _followingLoading[user['id']] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: () {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser?.uid == user['id']) {
            // إذا كان المستخدم ينقر على حسابه الشخصي، اذهب إلى ProfilePage
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ProfilePage(),
              ),
            );
          } else {
            // إذا كان ينقر على حساب مستخدم آخر، اذهب إلى UserProfilePage
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfilePage(
                  userId: user['id'],
                  initialDisplayName: user['displayName'],
                  initialHandle: user['handle'],
                  initialProfileImage: user['profileImageUrl'],
                ),
              ),
            );
          }
        },
        child: Row(
          children: [
            // صورة المستخدم
            CircleAvatar(
              radius: 25,
              backgroundImage: user['profileImageUrl']?.isNotEmpty == true
                  ? NetworkImage(user['profileImageUrl'])
                  : null,
              backgroundColor: Colors.grey[300],
              child: user['profileImageUrl']?.isEmpty != false
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            
            const SizedBox(width: 12),
            
            // معلومات المستخدم
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // الاسم مع علامة التوثيق
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user['displayName']?.isNotEmpty == true
                              ? user['displayName']
                              : user['handle']?.isNotEmpty == true
                                  ? user['handle']
                                  : 'مستخدم',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user['isVerified'] == true) ...[
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.verified,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  
                  // الهاندل
                  if (user['handle']?.isNotEmpty == true)
                    Text(
                      user['handle'],
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            
            // زر المتابعة
            if (!isCurrentUser)
              ElevatedButton(
                onPressed: () => _toggleFollow(user['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFollowing ? Colors.grey[200] : Colors.blue,
                  foregroundColor: isFollowing ? Colors.black : Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  minimumSize: const Size(80, 32),
                ),
                child: Text(
                  isFollowing ? 'يتابع' : 'متابعة',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}