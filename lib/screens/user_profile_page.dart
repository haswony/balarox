import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../services/database_service.dart';
import 'product_detail_page.dart';
import 'story_viewer_page.dart';
import 'followers_page.dart';
import '../widgets/shimmer_widget.dart';
import 'chat_page.dart';
import 'verification_details_page.dart';
import 'package:flutter_svg/flutter_svg.dart';

class UserProfilePage extends StatefulWidget {
  final String userId;
  final String? initialDisplayName;
  final String? initialHandle;
  final String? initialProfileImage;
  final bool? initialIsVerified;
  final Map<String, dynamic>? featuredProduct; // المنتج المميز للعرض
  
  const UserProfilePage({
    super.key,
    required this.userId,
    this.initialDisplayName,
    this.initialHandle,
    this.initialProfileImage,
    this.initialIsVerified,
    this.featuredProduct,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> 
    with TickerProviderStateMixin {
  
  String _displayName = '';
  String _handle = '';
  String _profileImageUrl = '';
  String _bio = '';
  bool _isDataLoaded = false;
  bool _isVerified = false;
  late TabController _tabController;
  List<Map<String, dynamic>> _userReviews = [];
  StreamSubscription<QuerySnapshot>? _reviewsSubscription;
  double _averageRating = 0.0;
  int _totalReviews = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  int _postsCount = 0;
  List<Map<String, dynamic>> _userProducts = [];
  StreamSubscription<QuerySnapshot>? _productsSubscription;
  StreamSubscription<DocumentSnapshot>? _userDataSubscription;
  StreamSubscription<QuerySnapshot>? _followersSubscription;
  StreamSubscription<QuerySnapshot>? _followingSubscription;
  StreamSubscription<QuerySnapshot>? _blockStatusSubscription;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  bool _isBlocked = false;
  bool _isBlockLoading = false;

  // كاش لمعلومات المستخدمين في التقييمات
  Map<String, Map<String, dynamic>> _usersCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // إضافة مستمع للتبويبات لإعادة بناء المحتوى
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          // إعادة بناء المحتوى عند تغيير التبويب
        });
      }
    });

    // استخدام البيانات الأولية إذا كانت متوفرة
    if (widget.initialDisplayName != null) {
      _displayName = widget.initialDisplayName!;
    }
    if (widget.initialHandle != null) {
      _handle = widget.initialHandle!;
    }
    if (widget.initialProfileImage != null) {
      _profileImageUrl = widget.initialProfileImage!;
    }
    if (widget.initialIsVerified != null) {
      _isVerified = widget.initialIsVerified!;
    }
    
    _loadUserData();
    
    // فحص حالة الحظر فوراً عند تحميل الصفحة
    _checkBlockStatusImmediately();
    
    // إرسال رسالة تلقائية إذا تم الدخول من منتج
    if (widget.featuredProduct != null) {
      _sendInterestedMessage();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _productsSubscription?.cancel();
    _userDataSubscription?.cancel();
    _followersSubscription?.cancel();
    _followingSubscription?.cancel();
    _blockStatusSubscription?.cancel();
    _reviewsSubscription?.cancel();
    super.dispose();
  }

  void _setupProductsListener() {
    _productsSubscription = FirebaseFirestore.instance
        .collection('products')
        .where('userId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) {
      final userProducts = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
      
      if (mounted) {
        setState(() {
          _userProducts = userProducts;
          _postsCount = userProducts.length;
        });
      }
    });
  }

  void _setupUserDataListener() {
    _userDataSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final userData = snapshot.data()!;

        // إضافة المستخدم للكاش فوراً
        _usersCache[widget.userId] = userData;

        setState(() {
          _displayName = userData['displayName'] ?? '';
          _handle = userData['handle'] ?? '';
          _profileImageUrl = userData['profileImageUrl'] ?? '';
          _bio = userData['bio'] ?? '';
          _isVerified = userData['isVerified'] ?? false;
        });
      }
    });
  }

  void _setupFollowStatusListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // مستمع لحالة المتابعة في الوقت الفعلي
    FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: currentUser.uid)
        .where('followedUserId', isEqualTo: widget.userId)
        .snapshots()
        .listen((snapshot) {
      // تحديث فقط إذا لم تكن هناك عمليات معلقة
      if (mounted && _pendingOperations == 0) {
        setState(() {
          _isFollowing = snapshot.docs.isNotEmpty;
        });
      }
    });
  }

  void _setupBlockStatusListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // مستمع لحالة الحظر في الوقت الفعلي - أكثر استجابة
    _blockStatusSubscription = FirebaseFirestore.instance
        .collection('blocks')
        .where('blockerUserId', isEqualTo: currentUser.uid)
        .where('blockedUserId', isEqualTo: widget.userId)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (mounted) {
        final wasBlocked = _isBlocked;
        final isNowBlocked = snapshot.docs.isNotEmpty;
        
        setState(() {
          _isBlocked = isNowBlocked;
        });
        
        // إذا تم الحظر للتو، تحديث العدادات فوراً
        if (!wasBlocked && isNowBlocked) {
          // مسح كاش المنتجات لإخفائها فوراً
          DatabaseService.clearAllCache();
          // تحديث العدادات فوراً
          _updateFollowCounts();
        }
      }
    });

    // مستمع إضافي لأي تغييرات في الحظر تؤثر على هذا المستخدم
    FirebaseFirestore.instance
        .collection('blocks')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (mounted) {
        // تحديث العدادات عند أي تغيير في الحظر
        _updateFollowCounts();
      }
    });
  }

  void _updateFollowCounts() async {
    try {
      final results = await Future.wait([
        DatabaseService.getFollowersCount(widget.userId),
        DatabaseService.getFollowingCount(widget.userId),
      ]);
      
      if (mounted) {
        setState(() {
          _followersCount = results[0];
          _followingCount = results[1];
        });
      }
    } catch (e) {
      print('خطأ في تحديث عدادات المتابعة: $e');
    }
  }

  void _setupFollowersListener() {
    _followersSubscription = FirebaseFirestore.instance
        .collection('follows')
        .where('followedUserId', isEqualTo: widget.userId)
        .snapshots()
        .listen((snapshot) async {
      // تحديث فقط إذا لم تكن هناك عمليات معلقة
      if (mounted && _pendingOperations == 0) {
        // حساب العدد مع استثناء المحظورين
        final count = await DatabaseService.getFollowersCount(widget.userId);
        setState(() {
          _followersCount = count;
        });
      }
    });
  }

  void _setupFollowingListener() {
    _followingSubscription = FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: widget.userId)
        .snapshots()
        .listen((snapshot) async {
      if (mounted) {
        // حساب العدد مع استثناء المحظورين
        final count = await DatabaseService.getFollowingCount(widget.userId);
        setState(() {
          _followingCount = count;
        });
      }
    });
  }

  Future<void> _checkFollowStatus() async {
    final isFollowing = await DatabaseService.isFollowing(widget.userId);
    if (mounted) {
      setState(() {
        _isFollowing = isFollowing;
      });
    }
  }

  Future<void> _checkBlockStatus() async {
    final isBlocked = await DatabaseService.isUserBlocked(widget.userId);
    if (mounted) {
      setState(() {
        _isBlocked = isBlocked;
      });
    }
  }

  Future<void> _checkBlockStatusImmediately() async {
    try {
      // فحص فوري لحالة الحظر قبل إعداد المستمعات
      final isBlocked = await DatabaseService.isUserBlocked(widget.userId);
      if (mounted) {
        setState(() {
          _isBlocked = isBlocked;
        });
      }
    } catch (e) {
      print('خطأ في فحص حالة الحظر الفوري: $e');
    }
  }

  Future<void> _toggleBlock() async {
    if (_isBlockLoading) return;
    
    setState(() {
      _isBlockLoading = true;
    });

    try {
      if (_isBlocked) {
        await DatabaseService.unblockUser(widget.userId);
        // تحديث فوري للحالة بدون رسالة
        setState(() {
          _isBlocked = false;
        });
      } else {
        // تحديث فوري للحالة قبل الحظر
        setState(() {
          _isBlocked = true;
        });
        
        await DatabaseService.blockUser(widget.userId);
        
        // العودة للصفحة السابقة بعد الحظر
        Navigator.pop(context);
        return;
      }
    } catch (e) {
      // إعادة الحالة السابقة في حالة الخطأ
      setState(() {
        _isBlocked = !_isBlocked;
      });
      _showErrorSnackBar('خطأ في تحديث حالة الحظر: $e');
    } finally {
      setState(() {
        _isBlockLoading = false;
      });
    }
  }


  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // متغير لتتبع آخر عملية
  bool _lastFollowState = false;
  int _pendingOperations = 0;

  Future<void> _toggleFollow() async {
    // منع النقرات المتعددة أثناء المعالجة
    if (_pendingOperations > 0) return;
    
    if (_isFollowing) {
      // إذا كان يتابع، نعرض شيت التأكيد
      _showUnfollowConfirmationSheet();
    } else {
      // إذا لم يكن يتابع، نتابع مباشرة
      _pendingOperations++;
      
      // حفظ الحالة الحالية
      final previousFollowState = _isFollowing;
      final previousCount = _followersCount;
      
      // تحديث فوري للواجهة
      setState(() {
        _isFollowing = true;
        _followersCount = previousCount + 1;
        _isFollowLoading = true;
      });

      try {
        await DatabaseService.followUser(widget.userId);
        // تحديث الحالة الأخيرة المعروفة
        _lastFollowState = true;
      } catch (e) {
        // إعادة الحالة السابقة في حالة الخطأ فقط
        if (mounted) {
          setState(() {
            _isFollowing = previousFollowState;
            _followersCount = previousCount;
          });
        }
        _showErrorSnackBar('خطأ في المتابعة: $e');
      } finally {
        _pendingOperations--;
        if (mounted) {
          setState(() {
            _isFollowLoading = false;
          });
        }
      }
    }
  }

  void _showUnfollowConfirmationSheet() {
    // منع النقرات المتعددة
    if (_pendingOperations > 0) return;
    
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
              backgroundImage: _profileImageUrl.isNotEmpty
                  ? NetworkImage(_profileImageUrl)
                  : null,
              backgroundColor: Colors.grey[300],
              child: _profileImageUrl.isEmpty
                  ? Icon(Icons.person, size: 40, color: Colors.grey[600])
                  : null,
            ),
            
            const SizedBox(height: 16),
            
            // اسم المستخدم
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _displayName.isNotEmpty ? _displayName : _handle,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                if (_isVerified) ...[
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
                  
                  // منع النقرات المتعددة
                  if (_pendingOperations > 0) return;
                  _pendingOperations++;
                  
                  // حفظ الحالة الحالية
                  final previousFollowState = _isFollowing;
                  final previousCount = _followersCount;
                  
                  // تحديث فوري للواجهة
                  setState(() {
                    _isFollowing = false;
                    _followersCount = previousCount > 0 ? previousCount - 1 : 0;
                    _isFollowLoading = true;
                  });

                  try {
                    await DatabaseService.unfollowUser(widget.userId);
                    // تحديث الحالة الأخيرة المعروفة
                    _lastFollowState = false;
                  } catch (e) {
                    // إعادة الحالة السابقة في حالة الخطأ فقط
                    if (mounted) {
                      setState(() {
                        _isFollowing = previousFollowState;
                        _followersCount = previousCount;
                      });
                    }
                    _showErrorSnackBar('خطأ في إلغاء المتابعة: $e');
                  } finally {
                    _pendingOperations--;
                    if (mounted) {
                      setState(() {
                        _isFollowLoading = false;
                      });
                    }
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

  void _navigateToFollowersPage(String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowersPage(
          userId: widget.userId,
          title: title,
        ),
      ),
    );
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    if (_isDataLoaded && !forceRefresh) return;
    
    try {
      // إعداد مستمعي البيانات في الوقت الفعلي
      _setupProductsListener();
      _setupUserDataListener();
      _setupFollowersListener();
      _setupFollowingListener();
      _setupFollowStatusListener();
      _setupReviewsListener();

      // تحميل البيانات الأخرى بشكل متوازي
      final results = await Future.wait([
        DatabaseService.getUserFromFirestore(widget.userId),
        DatabaseService.getFollowersCount(widget.userId),
        DatabaseService.getFollowingCount(widget.userId),
      ]);
      
      final userData = results[0] as Map<String, dynamic>?;
      final followersCount = results[1] as int;
      final followingCount = results[2] as int;
      
      if (userData != null && mounted) {
        setState(() {
          _displayName = userData['displayName'] ?? '';
          _handle = userData['handle'] ?? '';
          _profileImageUrl = userData['profileImageUrl'] ?? '';
          _bio = userData['bio'] ?? '';
          _isVerified = userData['isVerified'] ?? false;
          _followersCount = followersCount;
          _followingCount = followingCount;
          _isDataLoaded = true;
        });
      }

      // فحص حالة المتابعة والحظر - الحظر أولاً لأنه أهم
      await _checkBlockStatus();
      await _checkFollowStatus();
    } catch (e) {
      print('خطأ في تحميل بيانات المستخدم: $e');
    }
  }

  void _navigateToStoryViewer() {
    // يمكن إضافة منطق لعرض قصص المستخدم هنا
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: () => _loadUserData(forceRefresh: true),
        child: CustomScrollView(
          slivers: [
            // App Bar - Always visible when scrolling
            SliverAppBar(
              backgroundColor: Colors.white,
              elevation: 0.5,
              floating: false,
              snap: false,
              pinned: true, // Keep the app bar visible
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.black),
              ),
              title: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VerificationDetailsPage(
                        userId: widget.userId,
                        handle: _handle.isNotEmpty ? _handle : (widget.initialHandle ?? ''),
                        displayName: _displayName,
                        profileImageUrl: _profileImageUrl,
                        isVerified: _isVerified,
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    // إظهار القفل فقط للمستخدم الحالي
                    if (FirebaseAuth.instance.currentUser?.uid == widget.userId) ...[
                      Icon(Icons.lock_outline, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _handle.isNotEmpty ? _handle : (widget.initialHandle ?? ''),
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    if (_isVerified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ],
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey[400],
                      size: 20,
                    ),
                  ],
                ),
              ),
              actions: [
                // Only show menu for other users, not for current user
                if (FirebaseAuth.instance.currentUser?.uid != widget.userId)
                  IconButton(
                    onPressed: _showOptionsBottomSheet,
                    icon: const Icon(Icons.more_vert, color: Colors.black),
                  ),
              ],
            ),
            
            // Profile Content
            SliverToBoxAdapter(
              child: !_isDataLoaded
                ? const ProfileShimmer()
                : Padding(
                    padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.04),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        
                        // Profile Header
                        Row(
                          children: [
                            // Profile Picture
                            Container(
                              width: screenWidth * 0.22,
                              height: screenWidth * 0.22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.grey[300]!, width: 1),
                              ),
                              child: ClipOval(
                                child: _profileImageUrl.isNotEmpty
                                    ? Image.network(
                                        _profileImageUrl,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, progress) {
                                          if (progress == null) return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.grey[400],
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return Container(
                                            color: Colors.grey[200],
                                            child: Icon(
                                              Icons.person,
                                              size: screenWidth * 0.1,
                                              color: Colors.grey[400],
                                            ),
                                          );
                                        },
                                      )
                                    : Container(
                                        color: Colors.grey[200],
                                        child: Icon(
                                          Icons.person,
                                          size: screenWidth * 0.1,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                              ),
                            ),
                            
                            const SizedBox(width: 20),
                            
                            // Stats
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildStatColumn(_postsCount.toString(), 'منشور'),
                                  GestureDetector(
                                    onTap: () => _navigateToFollowersPage('المتابعون'),
                                    child: _buildStatColumn(_followersCount.toString(), 'متابع'),
                                  ),
                                  GestureDetector(
                                    onTap: () => _navigateToFollowersPage('يتابع'),
                                    child: _buildStatColumn(_followingCount.toString(), 'يتابع'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Name
                        if (_displayName.isNotEmpty)
                          Text(
                            _displayName,
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),

                        const SizedBox(height: 8),

                        // Bio display
                        if (_bio.isNotEmpty)
                          Text(
                            _bio,
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: Colors.black87,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),

                        const SizedBox(height: 20),
                        
                        // المنتج المميز إذا كان موجود
                        _buildFeaturedProduct(),
                        
                        // Action Buttons
                        if (!_isBlocked) // إخفاء الأزرار إذا كان المستخدم محظور
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _pendingOperations > 0 ? null : _toggleFollow,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isFollowing ? Colors.grey[200] : Colors.blue,
                                    foregroundColor: _isFollowing ? Colors.black : Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  child: _isFollowLoading
                                      ? SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              _isFollowing ? Colors.black : Colors.white,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          _isFollowing ? 'يتابع' : 'متابعة',
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () async {
                                    try {
                                      // إنشاء أو الحصول على محادثة
                                      final chatId = await DatabaseService.createOrGetChat(widget.userId);
                                      
                                      // الانتقال إلى صفحة الدردشة
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ChatPage(
                                            chatId: chatId,
                                            otherUserId: widget.userId,
                                            otherUserName: _displayName.isNotEmpty ? _displayName : _handle,
                                            otherUserImage: _profileImageUrl,
                                            isVerified: _isVerified,
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      _showErrorSnackBar('خطأ في بدء المحادثة: $e');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[200],
                                    foregroundColor: Colors.black,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  child: Text(
                                    'رسالة',
                                    style: GoogleFonts.cairo(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          // رسالة عندما يكون المستخدم محظور
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Text(
                              'تم حظر هذا المستخدم',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cairo(
                                color: Colors.red[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
            ),
            
            // Tabs
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!, width: 0.5),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: Colors.black,
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.grey[600],
                  tabs: const [
                    Tab(icon: Icon(Icons.grid_on)),
                    Tab(icon: Icon(Icons.play_arrow)),
                    Tab(icon: Icon(Icons.star)),
                  ],
                ),
              ),
            ),
            
            // No TabBarView - we'll handle tab switching manually

            // Show videos tab content
            if (_tabController.index == 1)
              SliverToBoxAdapter(
                child: Container(
                  height: 300,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لم ينشر أي فيديوهات بعد',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Show reviews tab content
            if (_tabController.index == 2) ...[
              _buildReviewsHeader(),
              _buildReviewsList(),
            ],

            // Show all posts as one unified grid when in posts tab
            if (_tabController.index == 0)
              !_isDataLoaded
                  ? SliverPadding(
                      padding: const EdgeInsets.all(2),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                          childAspectRatio: 1,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                              ),
                            );
                          },
                          childCount: 9,
                        ),
                      ),
                    )
                  : _userProducts.isEmpty
                      ? SliverToBoxAdapter(
   child: Container(
     height: 200,
     child: Center(
       child: Column(
         mainAxisAlignment: MainAxisAlignment.center,
         children: [
           Icon(
             Icons.inventory_2_outlined,
             size: 64,
             color: Colors.grey[400],
           ),
           const SizedBox(height: 16),
           Text(
             'لم ينشر أي إعلانات بعد',
             style: GoogleFonts.cairo(
               fontSize: 16,
               color: Colors.grey[600],
               fontWeight: FontWeight.w600,
             ),
           ),
         ],
       ),
     ),
   ),
 )
                      : SliverPadding(
                          padding: const EdgeInsets.all(2),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 2,
                              mainAxisSpacing: 2,
                              childAspectRatio: 1,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                if (index >= _userProducts.length) return null;
                                final product = _userProducts[index];
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ProductDetailPage(product: product),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      image: product['imageUrls']?.isNotEmpty == true
                                          ? DecorationImage(
                                              image: NetworkImage(product['imageUrls'][0]),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                      color: product['imageUrls']?.isEmpty == true
                                          ? Colors.grey[200] : null,
                                    ),
                                    child: product['imageUrls']?.isEmpty == true
                                        ? Icon(
                                            Icons.inventory_2_outlined,
                                            color: Colors.grey[400],
                                            size: 40,
                                          )
                                        : null,
                                  ),
                                );
                              },
                              childCount: _userProducts.length, // Show ALL posts in one grid
                            ),
                          ),
                        ),

          ],
        ),
      ),
    );
  }

  Future<void> _sendInterestedMessage() async {
    if (widget.featuredProduct == null) return;
    
    try {
      // إنشاء أو الحصول على محادثة
      final chatId = await DatabaseService.createOrGetChat(widget.userId);
      
      // إرسال رسالة تلقائية مع معلومات المنتج
      await DatabaseService.startChatFromProduct(
        productId: widget.featuredProduct!['id'],
        sellerId: widget.userId,
        productTitle: widget.featuredProduct!['title'] ?? '',
        productPrice: widget.featuredProduct!['price'],
        productLocation: widget.featuredProduct!['location'],
        productImageUrl: widget.featuredProduct!['imageUrls']?.isNotEmpty == true
            ? widget.featuredProduct!['imageUrls'][0]
            : null,
      );
    } catch (e) {
      print('خطأ في إرسال رسالة الاهتمام: $e');
    }
  }

  Widget _buildFeaturedProduct() {
    if (widget.featuredProduct == null) return const SizedBox.shrink();
    
    final product = widget.featuredProduct!;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان القسم مع تأثير بصري محسن
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                // أيقونة نجمة مع تأثير متدرج
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.amber[400]!, Colors.orange[400]!],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                
                // نص "منتج مميز"
                Text(
                  'منتج مميز',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                const Spacer(),
                
                // مؤشر الرسالة المرسلة
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green[200]!, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 14,
                        color: Colors.green[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'تم الإرسال',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // المنتج بتصميم حديث بدون كارد
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white,
                  Colors.grey[50]!,
                ],
              ),
              border: Border.all(
                color: Colors.grey[200]!,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // صورة المنتج مع تأثيرات بصرية
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Container(
                        height: screenWidth * 0.55,
                        width: double.infinity,
                        child: product['imageUrls']?.isNotEmpty == true
                            ? Stack(
                                children: [
                                  Image.network(
                                    product['imageUrls'][0],
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.grey[300]!, Colors.grey[200]!],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.image_outlined,
                                          size: 80,
                                          color: Colors.grey[500],
                                        ),
                                      );
                                    },
                                  ),
                                  // تأثير تدرج خفيف في الأسفل
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 60,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withOpacity(0.1),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.grey[300]!, Colors.grey[200]!],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 80,
                                  color: Colors.grey[500],
                                ),
                              ),
                      ),
                    ),
                    
                    // شارة "مميز" في الزاوية
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.purple[400]!, Colors.pink[400]!],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'مميز',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // معلومات المنتج مع تخطيط محسن
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // العنوان مع تحسينات تايبوغرافية
                      Text(
                        product['title'] ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // السعر مع تصميم جذاب
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green[400]!, Colors.teal[400]!],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.attach_money_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            Text(
                              '${product['price']} د.ع',
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // الموقع مع تصميم محسن
                      if (product['location']?.isNotEmpty == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue[100]!, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 16,
                                color: Colors.blue[600],
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  product['location'],
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 14,
            color: Colors.black,
          ),
        ),
      ],
    );
  }



  void _showOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // مؤشر السحب
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // خيار الحظر
            ListTile(
              onTap: () {
                Navigator.pop(context);
                _showBlockConfirmationSheet();
              },
              leading: null,
              title: Text(
                _isBlocked ? 'إلغاء حظر المستخدم' : 'حظر المستخدم',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
            ),
            
            const Divider(height: 1),
            
            // خيار الإبلاغ
            ListTile(
              onTap: () {
                Navigator.pop(context);
                _showReportBottomSheet();
              },
              leading: null,
              title: Text(
                'الإبلاغ',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.red,
                ),
              ),
            ),
            
            // مساحة آمنة للأجهزة ذات الحواف المنحنية
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _showBlockConfirmationSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // مؤشر السحب
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // صورة المستخدم
            CircleAvatar(
              radius: 50,
              backgroundImage: _profileImageUrl.isNotEmpty
                  ? NetworkImage(_profileImageUrl)
                  : null,
              backgroundColor: Colors.grey[200],
              child: _profileImageUrl.isEmpty
                  ? Icon(Icons.person, size: 50, color: Colors.grey[400])
                  : null,
            ),
            
            const SizedBox(height: 20),
            
            // رسالة التأكيد
            Text(
              _isBlocked ? 'إلغاء حظر' : 'حظر',
              style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // اسم المستخدم
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '@${_handle.isNotEmpty ? _handle : widget.initialHandle ?? ''}',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                if (_isVerified) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.verified,
                    color: Colors.blue,
                    size: 18,
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 16),
            
            // خط فاصل
            Container(
              height: 1,
              color: Colors.grey[200],
            ),
            
            const SizedBox(height: 16),
            
            // نص توضيحي
            Text(
              _isBlocked
                  ? 'سيتمكن هذا المستخدم من متابعتك ورؤية منشوراتك مرة أخرى'
                  : 'لن يتمكن هذا المستخدم من رؤية منشوراتك أو متابعتك',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 24),
            
            // أزرار الإجراء
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey[300]!),
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
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _toggleBlock();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isBlocked ? Colors.blue : Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _isBlocked ? 'إلغاء الحظر' : 'حظر',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            // مساحة آمنة
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  void _showReportBottomSheet() {
    String selectedReason = '';
    final reasons = [
      'محتوى غير لائق',
      'انتحال شخصية',
      'احتيال أو نصب',
      'محتوى مزعج أو سبام',
      'خطاب كراهية أو تنمر',
      'محتوى عنيف أو مؤذي',
      'معلومات مضللة',
      'أخرى',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        'الإبلاغ عن المستخدم',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Subtitle
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'لماذا تريد الإبلاغ عن هذا الحساب؟',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Reasons list
              ...reasons.map((reason) => ListTile(
                onTap: () {
                  setModalState(() {
                    selectedReason = reason;
                  });
                },
                leading: Radio<String>(
                  value: reason,
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setModalState(() {
                      selectedReason = value!;
                    });
                  },
                  activeColor: Colors.blue,
                ),
                title: Text(
                  reason,
                  style: GoogleFonts.cairo(fontSize: 15),
                ),
              )).toList(),
              // Submit button
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: selectedReason.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(context);
                          await _submitReport(selectedReason);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'إرسال البلاغ',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    try {
      await DatabaseService.reportUser(
        reportedUserId: widget.userId,
        reason: reason,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إرسال البلاغ وسيتم مراجعته',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل إرسال البلاغ',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _setupReviewsListener() {
    _reviewsSubscription = FirebaseFirestore.instance
        .collection('reviews')
        .where('reviewedUserId', isEqualTo: widget.userId)
        .snapshots()
        .listen((snapshot) async {
      final reviews = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      if (mounted) {
        // تحميل معلومات المستخدمين فوراً
        await _loadReviewersData(reviews);

        // حساب متوسط التقييم
        double totalRating = 0;
        for (var review in reviews) {
          totalRating += (review['rating'] ?? 0).toDouble();
        }

        setState(() {
          _userReviews = reviews;
          _totalReviews = reviews.length;
          _averageRating = reviews.isNotEmpty ? totalRating / reviews.length : 0.0;
        });
      }
    });
  }

  Future<void> _loadReviewersData(List<Map<String, dynamic>> reviews) async {
    final userIds = reviews
        .map((review) => review['reviewerUserId'] as String?)
        .where((id) => id != null && !_usersCache.containsKey(id))
        .cast<String>()
        .toSet();

    if (userIds.isNotEmpty) {
      try {
        final futures = userIds.map((userId) =>
            DatabaseService.getUserFromFirestore(userId));
        final users = await Future.wait(futures);

        for (int i = 0; i < userIds.length; i++) {
          final userId = userIds.elementAt(i);
          final userData = users[i];
          if (userData != null) {
            _usersCache[userId] = userData;
          }
        }
      } catch (e) {
        print('خطأ في تحميل بيانات المستخدمين: $e');
      }
    }
  }

  Widget _buildReviewsHeader() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final canAddReview = currentUserId != null && currentUserId != widget.userId;

    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(
            bottom: BorderSide(color: Colors.grey[200]!),
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _averageRating.toStringAsFixed(1),
                  style: GoogleFonts.cairo(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStarRating(_averageRating, size: 24),
                    const SizedBox(height: 4),
                    Text(
                      '$_totalReviews تقييم',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (canAddReview) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddReviewDialog(),
                icon: const Icon(Icons.rate_review, size: 20),
                label: Text(
                  'إضافة تقييم',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReviewsList() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final canAddReview = currentUserId != null && currentUserId != widget.userId;

    if (_userReviews.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          height: 300,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'لا توجد تقييمات بعد',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (canAddReview) ...[
                  const SizedBox(height: 8),
                  Text(
                    'كن أول من يقيم هذا المستخدم',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final review = _userReviews[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildReviewCard(review),
          );
        },
        childCount: _userReviews.length,
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final reviewerData = _usersCache[review['reviewerUserId']];

    return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[100]!, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reviewer info
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // صورة المعلق قابلة للضغط
                  GestureDetector(
                    onTap: () {
                      if (review['reviewerUserId'] != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfilePage(
                              userId: review['reviewerUserId'],
                              initialDisplayName: reviewerData?['displayName'],
                              initialHandle: reviewerData?['handle'],
                              initialProfileImage: reviewerData?['profileImageUrl'],
                              initialIsVerified: reviewerData?['isVerified'],
                            ),
                          ),
                        );
                      }
                    },
                    child: CircleAvatar(
                      radius: 22,
                      backgroundImage: reviewerData?['profileImageUrl'] != null
                          ? NetworkImage(reviewerData!['profileImageUrl'])
                          : null,
                      backgroundColor: Colors.grey[200],
                      child: reviewerData?['profileImageUrl'] == null
                          ? Icon(Icons.person, size: 22, color: Colors.grey[500])
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // اسم المعلق قابل للضغط
                        GestureDetector(
                          onTap: () {
                            if (review['reviewerUserId'] != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfilePage(
                                    userId: review['reviewerUserId'],
                                    initialDisplayName: reviewerData?['displayName'],
                                    initialHandle: reviewerData?['handle'],
                                    initialProfileImage: reviewerData?['profileImageUrl'],
                                    initialIsVerified: reviewerData?['isVerified'],
                                  ),
                                ),
                              );
                            }
                          },
                          child: Row(
                            children: [
                              Text(
                                reviewerData?['displayName'] ?? 'مستخدم',
                                style: GoogleFonts.cairo(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              if (reviewerData?['isVerified'] == true) ...[
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.verified,
                                  size: 15,
                                  color: Colors.blue,
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Handle
                        if (reviewerData?['handle'] != null)
                          Text(
                            '@${reviewerData!['handle']}',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        const SizedBox(height: 4),
                        // النجوم والتاريخ
                        Row(
                          children: [
                            _buildStarRating(review['rating']?.toDouble() ?? 0, size: 14),
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(review['createdAt']),
                              style: GoogleFonts.cairo(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Review comment
              if (review['comment'] != null && review['comment'].toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 54),
                  child: Text(
                    review['comment'],
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
  }

  Widget _buildStarRating(double rating, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star, color: Colors.amber, size: size);
        } else if (index < rating) {
          return Icon(Icons.star_half, color: Colors.amber, size: size);
        } else {
          return Icon(Icons.star_border, color: Colors.grey[400], size: size);
        }
      }),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else {
      return '';
    }
    
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays > 30) {
      return 'منذ ${(difference.inDays / 30).floor()} شهر';
    } else if (difference.inDays > 0) {
      return 'منذ ${difference.inDays} يوم';
    } else if (difference.inHours > 0) {
      return 'منذ ${difference.inHours} ساعة';
    } else if (difference.inMinutes > 0) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else {
      return 'الآن';
    }
  }

  void _showAddReviewDialog() {
    double selectedRating = 0;
    final commentController = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // مؤشر السحب
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                
                // العنوان
                Text(
                  'تقييم المستخدم',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // معلومات المستخدم
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundImage: _profileImageUrl.isNotEmpty
                            ? NetworkImage(_profileImageUrl)
                            : null,
                        backgroundColor: Colors.grey[200],
                        child: _profileImageUrl.isEmpty
                            ? Icon(Icons.person, size: 35, color: Colors.grey[500])
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _displayName.isNotEmpty ? _displayName : _handle,
                                  style: GoogleFonts.cairo(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (_isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.verified,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                ],
                              ],
                            ),
                            if (_handle.isNotEmpty)
                              Text(
                                '@$_handle',
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // خط فاصل
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  color: Colors.grey[200],
                ),
                
                const SizedBox(height: 24),
                
                // النجوم
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Text(
                        'كيف كانت تجربتك؟',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) {
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                selectedRating = index + 1.0;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: Icon(
                                index < selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: index < selectedRating ? Colors.amber : Colors.grey[400],
                                size: 40,
                              ),
                            ),
                          );
                        }),
                      ),
                      if (selectedRating > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          selectedRating == 5 ? 'ممتاز!' :
                          selectedRating == 4 ? 'جيد جداً' :
                          selectedRating == 3 ? 'جيد' :
                          selectedRating == 2 ? 'مقبول' : 'ضعيف',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: selectedRating >= 4 ? Colors.green :
                                   selectedRating == 3 ? Colors.orange : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // حقل التعليق
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أضف تعليقاً (اختياري)',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: commentController,
                        maxLines: 4,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: 'شارك تجربتك مع هذا المستخدم...',
                          hintStyle: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // أزرار الإجراء
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: Colors.grey[300]!),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: selectedRating > 0
                              ? () async {
                                  Navigator.pop(context);
                                  await _submitReview(selectedRating, commentController.text);
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            disabledBackgroundColor: Colors.grey[300],
                          ),
                          child: Text(
                            'إرسال التقييم',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // مساحة آمنة
                SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitReview(double rating, String comment) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      
      // Check if user already reviewed
      final existingReview = await FirebaseFirestore.instance
          .collection('reviews')
          .where('reviewedUserId', isEqualTo: widget.userId)
          .where('reviewerUserId', isEqualTo: currentUser.uid)
          .get();
      
      if (existingReview.docs.isNotEmpty) {
        _showErrorSnackBar('لقد قمت بتقييم هذا المستخدم مسبقاً');
        return;
      }
      
      await FirebaseFirestore.instance.collection('reviews').add({
        'reviewedUserId': widget.userId,
        'reviewerUserId': currentUser.uid,
        'rating': rating,
        'comment': comment.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // إضافة معلومات المستخدم الحالي للكاش فوراً
      if (!_usersCache.containsKey(currentUser.uid)) {
        final currentUserData = await DatabaseService.getUserFromFirestore(currentUser.uid);
        if (currentUserData != null) {
          _usersCache[currentUser.uid] = currentUserData;
        }
      }

      _showSuccessSnackBar('تم إضافة التقييم بنجاح');
    } catch (e) {
      _showErrorSnackBar('خطأ في إضافة التقييم: $e');
    }
  }

}
