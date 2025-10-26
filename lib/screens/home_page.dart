import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'profile_page.dart';
import 'add_product_page.dart';
import 'add_story_page.dart';
import 'add_content_page.dart';
import 'product_detail_page.dart';
import 'story_viewer_page.dart';
import 'search_page.dart';
import 'login_page.dart';
import 'notifications_page.dart';
import 'my_ads_page.dart';
import 'chat_list_page.dart';
import 'guidance_page.dart';

import 'user_profile_page.dart';
import '../services/database_service.dart';
import '../services/profile_update_service.dart';
import '../services/stream_manager.dart';
import '../widgets/shimmer_widget.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  late List<Widget> _pages;

  // طريقة للتنقل إلى التبويب الأول من الخارج
  void navigateToHome() {
    setState(() {
      _currentIndex = 0;
    });
  }

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomePageContent(),
      AddContentPage(onNavigateToHome: navigateToHome), // صفحة الإضافة الجديدة
      const GuidancePage(), // صفحة الإرشاد الطبي
      const ProfilePage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Colors.white, // تغيير لون شريط التنقل السفلي إلى الأبيض
        selectedItemColor: Colors.blue, // تغيير لون العنصر المحدد إلى الأزرق فقط
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.cairo(),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        items: [
          BottomNavigationBarItem(
            icon: _buildHomeIcon(),
            label: 'الرئيسية',
          ),
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.transparent,
              ),
              child: _buildAddIcon(),
            ),
            label: 'إضافة',
          ),
          BottomNavigationBarItem(
            icon: _buildGuidanceIcon(),
            label: 'الإرشاد',
          ),
          BottomNavigationBarItem(
            icon: _buildProfileIcon(),
            label: 'حسابي',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeIcon() {
    final isSelected = _currentIndex == 0;
    return SvgPicture.asset(
      'assets/icons/home.svg',
      height: 20,
      width: 20,
      colorFilter: ColorFilter.mode(
        isSelected ? Colors.blue : Colors.grey,
        BlendMode.srcIn,
      ),
    );
  }

  Widget _buildAddIcon() {
    final isSelected = _currentIndex == 1;
    return SvgPicture.asset(
      'assets/icons/add.svg',
      height: 24,
      width: 24,
      colorFilter: ColorFilter.mode(
        isSelected ? Colors.blue : Colors.grey,
        BlendMode.srcIn,
      ),
    );
  }

  Widget _buildGuidanceIcon() {
    final isSelected = _currentIndex == 2;
    return Icon(
      Icons.local_hospital,
      size: 24,
      color: isSelected ? Colors.blue : Colors.grey,
    );
  }

  Widget _buildProfileIcon() {
    final isSelected = _currentIndex == 3;
    return SvgPicture.asset(
      'assets/icons/profile.svg',
      height: 24,
      width: 24,
      colorFilter: ColorFilter.mode(
        isSelected ? Colors.blue : Colors.grey,
        BlendMode.srcIn,
      ),
    );
  }


  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'تسجيل الخروج',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          textAlign: TextAlign.right,
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
          style: GoogleFonts.cairo(),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('تسجيل الخروج', style: GoogleFonts.cairo(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      // إلغاء جميع الاشتراكات المركزية
      await StreamManager.instance.cancelAll();

      // تحديث حالة المستخدم في قاعدة البيانات
      await DatabaseService.signOutUser();

      // مسح الكاش على مستوى الخدمة
      DatabaseService.clearAllCache();

    } catch (e) {
      print('خطأ في عملية تسجيل الخروج: $e');
    }

    // تسجيل الخروج من Firebase Auth
    await FirebaseAuth.instance.signOut();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }




}

class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _stories = [];
  List<String> _categories = [];
  String _selectedCategory = '';
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _hasUnreadNotifications = false;
  StreamSubscription? _profileUpdateSubscription;
  StreamSubscription<QuerySnapshot>? _productsSubscription;
  Timer? _expirationTimer;
  Timer? _uiUpdateTimer;

  @override
  void initState() {
    super.initState();
    _loadData();

    // الاستماع لتحديثات الصورة الشخصية
    _profileUpdateSubscription = ProfileUpdateService().profileImageUpdates.listen((userId) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid == userId) {
        _loadData();
      }
    });

    // تسجيل الاشتراك في StreamManager
    if (_profileUpdateSubscription != null) {
      StreamManager.instance.addSubscription(_profileUpdateSubscription!);
    }

    // بدء مؤقت تحديث حالة المنتجات المنتهية (كل ثانية للتحديث الفوري)
    _expirationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      DatabaseService.updateExpiredProductsStatus();
    });

    // مؤقت لفلترة المنتجات المنتهية في الواجهة فوراً
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _checkAndRemoveExpiredProducts();
      }
    });
  }



  /// إلغاء جميع الاشتراكات المحلية
  Future<void> _cancelAllSubscriptions() async {
    try {
      await _profileUpdateSubscription?.cancel();
      await _productsSubscription?.cancel();
      _expirationTimer?.cancel();
      _uiUpdateTimer?.cancel();
      _profileUpdateSubscription = null;
      _productsSubscription = null;
      _expirationTimer = null;
      _uiUpdateTimer = null;
    } catch (e) {
      print('خطأ في إلغاء الاشتراكات المحلية: $e');
    }
  }

  void _checkAndRemoveExpiredProducts() {
    final now = DateTime.now();
    bool hasExpiredProducts = false;

    // فحص المنتجات وإزالة المنتهية فوراً
    List<Map<String, dynamic>> activeProducts = [];

    for (var product in _products) {
      bool isExpired = false;

      // فحص انتهاء الصلاحية بناءً على expireAt
      if (product['expireAt'] != null) {
        final expireAt = (product['expireAt'] as Timestamp).toDate();
        isExpired = now.isAfter(expireAt);
      }

      if (!isExpired) {
        activeProducts.add(product);
      } else {
        hasExpiredProducts = true;
      }
    }

    // تحديث الواجهة إذا وجدت منتجات منتهية
    if (hasExpiredProducts && activeProducts.length != _products.length) {
      setState(() {
        _products = activeProducts;
      });
    }
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    super.dispose();
  }

  Future<void> _checkUnreadNotifications() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: currentUser.uid)
          .where('isRead', isEqualTo: false)
          .limit(1)
          .get();

      if (mounted) {
        setState(() {
          _hasUnreadNotifications = querySnapshot.docs.isNotEmpty;
        });
      }
    } catch (e) {
      print('خطأ في التحقق من الإشعارات: $e');
    }
  }

  void _setupProductsListener() {
    // إلغاء الاستماع السابق إن وجد
    _productsSubscription?.cancel();

    Query query = FirebaseFirestore.instance
        .collection('products')
        .where('status', isEqualTo: 'active') // عرض المنتجات النشطة فقط
        .orderBy('createdAt', descending: true);

    // إضافة فلتر الفئة إذا كانت محددة
    if (_selectedCategory.isNotEmpty && _selectedCategory != 'الكل') {
      query = query.where('category', isEqualTo: _selectedCategory);
    }

    _productsSubscription = query.snapshots().listen((snapshot) {
      if (mounted) {
        final products = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          return data;
        }).toList();

        setState(() {
          _products = products;
        });
      }
    }, onError: (error) {
      print('خطأ في الاستماع للمنتجات: $error');
    });

    // تسجيل الاشتراك في StreamManager
    if (_productsSubscription != null) {
      StreamManager.instance.addSubscription(_productsSubscription!);
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      // إعداد الاستماع للمنتجات أولاً
      _setupProductsListener();

      final results = await Future.wait([
        DatabaseService.getCategories(),
        DatabaseService.getActiveStories(),
        if (currentUser != null) DatabaseService.getUserFromFirestore(currentUser.uid),
      ]);

      final categories = results[0] as List<String>;
      final stories = results[1] as List<Map<String, dynamic>>;
      final userData = results.length > 2 ? results[2] as Map<String, dynamic>? : null;

      // إضافة قصة المستخدم الحالي في المقدمة
      List<Map<String, dynamic>> finalStories = [];

      if (currentUser != null) {
        // البحث عن قصص المستخدم الحالي
        final currentUserStories = stories.where((story) =>
        story['userId'] == currentUser.uid).toList();

        if (currentUserStories.isNotEmpty) {
          // إضافة قصص المستخدم الحالي في المقدمة مع التحقق من المشاهدة
          finalStories.addAll(currentUserStories);
        } else {
          // إضافة بطاقة "إضافة قصة" للمستخدم الحالي
          finalStories.add({
            'userId': currentUser.uid,
            'userDisplayName': userData?['displayName'] ?? 'أنت',
            'userProfileImage': userData?['profileImageUrl'] ?? '',
            'stories': [],
            'hasUnseenStories': false,
            'isAddStory': true, // علامة خاصة لبطاقة إضافة القصة
          });
        }

        // إضافة باقي القصص (باستثناء قصص المستخدم الحالي)
        final otherStories = stories.where((story) =>
        story['userId'] != currentUser.uid).toList();
        finalStories.addAll(otherStories);
      } else {
        finalStories = stories;
      }

      // التحقق من الإشعارات غير المقروءة
      await _checkUnreadNotifications();

      if (mounted) {
        setState(() {
          _categories = ['الكل', ...categories];
          _stories = finalStories;
          _isLoading = false;
        });
      }

    } catch (e) {
      print('خطأ في تحميل البيانات: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshDataSilently() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      final results = await Future.wait([
        DatabaseService.getCategories(),
        DatabaseService.getActiveStories(),
        if (currentUser != null) DatabaseService.getUserFromFirestore(currentUser.uid),
      ]);

      final categories = results[0] as List<String>;
      final stories = results[1] as List<Map<String, dynamic>>;
      final userData = results.length > 2 ? results[2] as Map<String, dynamic>? : null;

      // إضافة قصة المستخدم الحالي في المقدمة
      List<Map<String, dynamic>> finalStories = [];

      if (currentUser != null) {
        // البحث عن قصص المستخدم الحالي
        final currentUserStories = stories.where((story) =>
        story['userId'] == currentUser.uid).toList();

        if (currentUserStories.isNotEmpty) {
          // إضافة قصص المستخدم الحالي في المقدمة مع التحقق من المشاهدة
          finalStories.addAll(currentUserStories);
        } else {
          // إضافة بطاقة "إضافة قصة" للمستخدم الحالي
          finalStories.add({
            'userId': currentUser.uid,
            'userDisplayName': userData?['displayName'] ?? 'أنت',
            'userProfileImage': userData?['profileImageUrl'] ?? '',
            'stories': [],
            'hasUnseenStories': false,
            'isAddStory': true, // علامة خاصة لبطاقة إضافة القصة
          });
        }

        // إضافة باقي القصص (باستثناء قصص المستخدم الحالي)
        final otherStories = stories.where((story) =>
        story['userId'] != currentUser.uid).toList();
        finalStories.addAll(otherStories);
      } else {
        finalStories = stories;
      }

      // التحقق من الإشعارات غير المقروءة
      await _checkUnreadNotifications();

      if (mounted) {
        setState(() {
          _categories = ['الكل', ...categories];
          _stories = finalStories;
          // لا نغير _isLoading هنا لتجنب إظهار الشيمر
        });
      }

    } catch (e) {
      print('خطأ في تحديث البيانات بصمت: $e');
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _selectedCategory = '';
      _isRefreshing = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      final results = await Future.wait([
        DatabaseService.getCategories(),
        DatabaseService.getActiveStories(),
        if (currentUser != null) DatabaseService.getUserFromFirestore(currentUser.uid),
      ]);

      final categories = results[0] as List<String>;
      final stories = results[1] as List<Map<String, dynamic>>;
      final userData = results.length > 2 ? results[2] as Map<String, dynamic>? : null;

      // إضافة قصة المستخدم الحالي في المقدمة
      List<Map<String, dynamic>> finalStories = [];

      if (currentUser != null) {
        // البحث عن قصص المستخدم الحالي
        final currentUserStories = stories.where((story) =>
        story['userId'] == currentUser.uid).toList();

        if (currentUserStories.isNotEmpty) {
          // إضافة قصص المستخدم الحالي في المقدمة مع التحقق من المشاهدة
          finalStories.addAll(currentUserStories);
        } else {
          // إضافة بطاقة "إضافة قصة" للمستخدم الحالي
          finalStories.add({
            'userId': currentUser.uid,
            'userDisplayName': userData?['displayName'] ?? 'أنت',
            'userProfileImage': userData?['profileImageUrl'] ?? '',
            'stories': [],
            'hasUnseenStories': false,
            'isAddStory': true, // علامة خاصة لبطاقة إضافة القصة
          });
        }

        // إضافة باقي القصص (باستثناء قصص المستخدم الحالي)
        final otherStories = stories.where((story) =>
        story['userId'] != currentUser.uid).toList();
        finalStories.addAll(otherStories);
      } else {
        finalStories = stories;
      }

      // التحقق من الإشعارات غير المقروءة
      await _checkUnreadNotifications();

      if (mounted) {
        setState(() {
          _categories = ['الكل', ...categories];
          _stories = finalStories;
          _isRefreshing = false;
        });
      }

    } catch (e) {
      print('خطأ في تحديث البيانات: $e');
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _filterByCategory(String category) async {
    setState(() {
      _selectedCategory = category;
    });

    // إعادة إعداد الاستماع مع الفلتر الجديد
    _setupProductsListener();
  }

  String _getAuctionTimeRemaining(Map<String, dynamic> product) {
    if (product['auctionEndTime'] == null) return '';

    try {
      final endTime = (product['auctionEndTime'] as Timestamp).toDate();
      final now = DateTime.now();
      final difference = endTime.difference(now);

      if (difference.isNegative) return 'انتهت';

      final days = difference.inDays;
      final hours = difference.inHours % 24;
      final minutes = difference.inMinutes % 60;

      if (days > 0) {
        return 'باقي $days يوم';
      } else if (hours > 0) {
        return 'باقي $hours ساعة';
      } else if (minutes > 0) {
        return 'باقي $minutes دقيقة';
      } else {
        return 'ينتهي قريباً';
      }
    } catch (e) {
      return '';
    }
  }

  void _navigateToAddStory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // التحقق من حد إضافة القصص
    final storyLimitCheck = await DatabaseService.checkUserStoryLimit(user.uid);
    
    if (!storyLimitCheck['canAddStory']) {
      _showStoryLimitDialog(storyLimitCheck);
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddStoryPage()),
    );
    if (result == true) {
      // تحديث الصفحة الرئيسية
      _refreshData();
    }
  }

  void _showStoryLimitDialog(Map<String, dynamic> limitCheck) {
    final remainingSeconds = limitCheck['remainingTime'] as int;
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    
    String timeMessage;
    if (hours > 0) {
      timeMessage = '$hours ساعة و $minutes دقيقة';
    } else {
      timeMessage = '$minutes دقيقة';
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Container();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          ),
          child: FadeTransition(
            opacity: animation,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Container(
                width: 260,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الرسالة الرئيسية
                    Text(
                      'يمكنك إضافة قصة واحدة فقط كل 24 ساعة',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        color: Colors.black,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    
                    // الوقت المتبقي
                    Text(
                      'الوقت المتبقي: $timeMessage',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    
                    // خط فاصل
                    Container(
                      height: 0.5,
                      color: Colors.black12,
                    ),
                    const SizedBox(height: 12),
                    
                    // زر الإغلاق - نص فقط بدون تأثير
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'حسناً',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'بلدروز',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchPage()),
              );
            },
            icon: const Icon(Icons.search, color: Colors.black),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ChatListPage()),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.black),
          ),
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsPage()),
              );
              // تحديث حالة الإشعارات غير المقروءة بعد العودة من صفحة الإشعارات
              _checkUnreadNotifications();
            },
            icon: Stack(
              children: [
                const Icon(Icons.notifications_outlined, color: Colors.black),
                if (_hasUnreadNotifications)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: CustomScrollView(
          slivers: [
            // Stories Section
            SliverToBoxAdapter(
              child: Container(
                height: 110,
                color: Colors.white,
                child: _isLoading && _stories.isEmpty
                    ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: 5,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: const StoryShimmer(),
                    );
                  },
                )
                    : _stories.isNotEmpty
                    ? ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _stories.length,
                  itemBuilder: (context, index) {
                    final storyGroup = _stories[index];
                    return _buildStoryItem(storyGroup, index);
                  },
                )
                    : const SizedBox.shrink(),
              ),
            ),

            // Categories Filter - Sticky Header
            SliverPersistentHeader(
              pinned: true,
              delegate: _CategoriesHeaderDelegate(
                categories: _categories,
                selectedCategory: _selectedCategory,
                isLoading: _isLoading,
                onCategorySelected: _filterByCategory,
              ),
            ),

            // Products Grid
            (_isLoading && !_isRefreshing)
                ? SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                delegate: SliverChildBuilderDelegate(
                      (context, index) => const ProductShimmer(),
                  childCount: 8,
                ),
              ),
            )
                : _products.isEmpty
                ? SliverToBoxAdapter(
             child: Container(
               padding: const EdgeInsets.all(40),
               child: Column(
                 children: [
                   Icon(
                     Icons.inventory_2_outlined,
                     size: 64,
                     color: Colors.grey[400],
                   ),
                   const SizedBox(height: 16),
                   Text(
                     _selectedCategory.isEmpty || _selectedCategory == 'الكل'
                         ? 'لا توجد إعلانات بهذا القسم'
                         : 'لا توجد إعلانات في قسم $_selectedCategory',
                     style: GoogleFonts.cairo(
                       fontSize: 16,
                       color: Colors.grey[600],
                       fontWeight: FontWeight.w600,
                     ),
                     textAlign: TextAlign.center,
                   ),
                   const SizedBox(height: 8),
                   Text(
                     'كن أول من ينشر إعلاناً في هذا القسم',
                     style: GoogleFonts.cairo(
                       fontSize: 14,
                       color: Colors.grey[500],
                     ),
                     textAlign: TextAlign.center,
                   ),
                 ],
               ),
             ),
           )
                : SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final product = _products[index];
                    return _buildProductCard(product);
                  },
                  childCount: _products.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryItem(Map<String, dynamic> storyGroup, int index) {
    final hasUnseenStories = storyGroup['hasUnseenStories'] ?? false;
    final isAddStory = storyGroup['isAddStory'] ?? false;
    final currentUser = FirebaseAuth.instance.currentUser;
    final isCurrentUser = currentUser?.uid == storyGroup['userId'];

    // للمستخدم الحالي: دائرة حمراء إذا كان لديه قصص غير مشاهدة
    // للمستخدمين الآخرين: دائرة حمراء إذا لم يشاهد قصصهم
    final showRedCircle = isCurrentUser
        ? (!isAddStory && hasUnseenStories) // له قصص + غير مشاهدة
        : hasUnseenStories; // إذا لم يشاهد قصص الآخرين

    return GestureDetector(
      onTap: () {
        if (isAddStory) {
          // إذا كانت بطاقة إضافة قصة، انتقل لصفحة إضافة القصة
          _navigateToAddStory();
        } else {
          // إذا كانت قصة عادية، انتقل لعرض القصص
          final storiesForViewer = _stories.where((s) => s['isAddStory'] != true).toList();

          // البحث عن الفهرس الصحيح للمستخدم المحدد في قائمة العارض
          int viewerIndex = 0;
          final targetUserId = storyGroup['userId'];

          // البحث عن الفهرس الصحيح بناءً على userId
          for (int i = 0; i < storiesForViewer.length; i++) {
            if (storiesForViewer[i]['userId'] == targetUserId) {
              viewerIndex = i;
              break;
            }
          }

          // Debug: التأكد من العثور على المستخدم الصحيح
          if (viewerIndex == 0 && storiesForViewer.isNotEmpty && storiesForViewer[0]['userId'] != targetUserId) {
            print('تحذير: لم يتم العثور على المستخدم المطلوب، سيبدأ من الأول');
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StoryViewerPage(
                userStoryGroups: storiesForViewer,
                initialIndex: viewerIndex,
              ),
            ),
          ).then((updatedStoryGroups) {
            // إذا تم إرجاع بيانات محدثة من StoryViewer، استخدمها فوراً
            if (updatedStoryGroups != null && mounted) {
              setState(() {
                // تحديث القصص المحلية بالبيانات المحدثة
                final updatedGroups = updatedStoryGroups as List<Map<String, dynamic>>;

                // دمج البيانات المحدثة مع القصص الحالية
                for (var updatedGroup in updatedGroups) {
                  final userId = updatedGroup['userId'];
                  final storyIndex = _stories.indexWhere((story) => story['userId'] == userId);
                  if (storyIndex != -1) {
                    _stories[storyIndex] = updatedGroup;
                  }
                }
              });
            }

            // تحديث البيانات بصمت بعد العودة من Stories بدون إظهار شيمر
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) {
                _refreshDataSilently();
              }
            });
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: showRedCircle
                        ? const LinearGradient(
                      colors: [Colors.purple, Colors.pink, Colors.orange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                        : null,
                    border: Border.all(
                      color: showRedCircle
                          ? Colors.white
                          : Colors.grey[300]!,
                      width: 2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipOval(
                      child: storyGroup['userProfileImage']?.isNotEmpty == true
                          ? Image.network(
                        storyGroup['userProfileImage'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.person, color: Colors.grey),
                          );
                        },
                      )
                          : Container(
                        color: Colors.grey[300],
                        child: const Icon(Icons.person, color: Colors.grey),
                      ),
                    ),
                  ),
                ),

                // أيقونة الإضافة للمستخدم الحالي بدون قصص
                if (isAddStory)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 70,
              child: Text(
                isCurrentUser
                    ? (isAddStory ? 'قصتك' : 'أنت')
                    : (storyGroup['userDisplayName']?.isNotEmpty == true
                    ? storyGroup['userDisplayName']
                    : 'مستخدم'),
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailPage(product: product),
          ),
        );
      },
      onLongPress: () {
        // الانتقال لملف المستخدم مع عرض المنتج
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfilePage(
              userId: product['userId'],
              initialDisplayName: product['userDisplayName'],
              initialProfileImage: product['userProfileImage'],
              featuredProduct: product,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // صورة المنتج
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                child: product['imageUrls']?.isNotEmpty == true
                    ? CachedNetworkImage(
                  imageUrl: product['imageUrls'][0],
                  fit: BoxFit.cover,
                  placeholder: (context, url) => ShimmerWidget(
                    child: Container(
                      color: Colors.grey[100],
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[100],
                    child: Icon(Icons.shopping_bag_outlined,
                        color: Colors.grey[400], size: 40),
                  ),
                )
                    : Container(
                  color: Colors.grey[100],
                  child: Icon(Icons.shopping_bag_outlined,
                      color: Colors.grey[400], size: 40),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // معلومات المنتج
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // العنوان
                  Text(
                    product['title'] ?? '',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // السعر أو معلومات المزايدة
                  if (product['isAuction'] == true) ...[
                    // عرض معلومات المزايدة
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'مزايدة',
                            style: GoogleFonts.cairo(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${product['auctionCurrentPrice'] ?? product['auctionStartPrice']} د.ع',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // عرض حالة المزايدة
                    if (product['auctionStatus'] == 'active') ...[
                      const SizedBox(height: 2),
                      Text(
                        _getAuctionTimeRemaining(product),
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          color: Colors.red[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ] else ...[
                    // عرض السعر العادي
                    Text(
                      '${product['price']} د.ع',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],

                  const SizedBox(height: 2),

                  // الموقع
                  Text(
                    product['location'] ?? '',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// Delegate للشريط الثابت للأقسام
class _CategoriesHeaderDelegate extends SliverPersistentHeaderDelegate {
  final List<String> categories;
  final String selectedCategory;
  final bool isLoading;
  final Function(String) onCategorySelected;

  _CategoriesHeaderDelegate({
    required this.categories,
    required this.selectedCategory,
    required this.isLoading,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isLoading && categories.isEmpty
            ? ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 6,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(right: 6),
              width: 80,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(14),
              ),
            );
          },
        )
            : ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            final isSelected = selectedCategory == category;
            return GestureDetector(
              onTap: () => onCategorySelected(category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.grey[100],
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    category,
                    style: GoogleFonts.cairo(
                      color: isSelected ? Colors.white : Colors.grey[700],
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  double get maxExtent => 52.0;

  @override
  double get minExtent => 52.0;

  @override
  bool shouldRebuild(covariant _CategoriesHeaderDelegate oldDelegate) {
    return categories != oldDelegate.categories ||
        selectedCategory != oldDelegate.selectedCategory ||
        isLoading != oldDelegate.isLoading;
  }
}