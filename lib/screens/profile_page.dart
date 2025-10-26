import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Add this import for kIsWeb
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'add_story_page.dart';
import 'edit_profile_page.dart';
import 'followers_page.dart';
import 'settings_page.dart';
import '../services/database_service.dart';
import '../services/profile_update_service.dart';
import 'product_detail_page.dart';
import 'user_profile_page.dart';
import '../widgets/shimmer_widget.dart';
import 'verification_details_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  String _displayName = '';
  String _handle = '';
  String _profileImageUrl = '';
  String _bio = '';
  File? _profileImage;
  Uint8List? _profileImageBytes; // For web compatibility
  bool _isDataLoaded = false;
  bool _isVerified = false;
  final ImagePicker _picker = ImagePicker();
  late TabController _tabController;
  int _followersCount = 0;
  int _followingCount = 0;
  int _postsCount = 0;
  List<Map<String, dynamic>> _userProducts = [];
  StreamSubscription<QuerySnapshot>? _productsSubscription;
  StreamSubscription<DocumentSnapshot>? _userDataSubscription;
  StreamSubscription<QuerySnapshot>? _followersSubscription;
  StreamSubscription<QuerySnapshot>? _followingSubscription;

  // متغيرات التقييمات
  List<Map<String, dynamic>> _userReviews = [];
  StreamSubscription<QuerySnapshot>? _reviewsSubscription;
  double _averageRating = 0.0;
  int _totalReviews = 0;
  Map<String, Map<String, dynamic>> _usersCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Listen to tab changes to rebuild the UI
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {});
      }
    });

    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _productsSubscription?.cancel();
    _userDataSubscription?.cancel();
    _followersSubscription?.cancel();
    _followingSubscription?.cancel();
    _reviewsSubscription?.cancel();
    super.dispose();
  }

  void _setupProductsListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _productsSubscription = FirebaseFirestore.instance
        .collection('products')
        .where('userId', isEqualTo: currentUser.uid)
        .where('status', isEqualTo: 'active') // عرض المنتجات النشطة فقط
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
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _userDataSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final userData = snapshot.data()!;
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

  void _setupFollowersListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _followersSubscription = FirebaseFirestore.instance
        .collection('follows')
        .where('followedUserId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _followersCount = snapshot.docs.length;
        });
      }
    });
  }

  void _setupFollowingListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _followingSubscription = FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _followingCount = snapshot.docs.length;
        });
      }
    });
  }

  Future<void> _loadUserData({bool forceRefresh = false}) async {
    if (_isDataLoaded && !forceRefresh) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // إعداد مستمعي البيانات في الوقت الفعلي
      _setupProductsListener();
      _setupUserDataListener();
      _setupFollowersListener();
      _setupFollowingListener();
      _setupReviewsListener();

      // تحميل البيانات الأخرى بشكل متوازي
      final results = await Future.wait([
        DatabaseService.getUserFromFirestore(currentUser.uid),
        DatabaseService.getFollowersCount(currentUser.uid),
        DatabaseService.getFollowingCount(currentUser.uid),
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
    } catch (e) {
      print('خطأ في تحميل بيانات المستخدم: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 95,
      );

      if (image != null) {
        setState(() {
          _profileImage = File(image.path);
          _profileImageBytes = null; // Reset bytes
          // For web compatibility, we also store the bytes
          image.readAsBytes().then((bytes) {
            setState(() {
              _profileImageBytes = bytes;
            });
          });
        });

        await _uploadImageToFirebase(File(image.path));
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في اختيار الصورة: $e');
    }
  }

  Future<void> _pickAndUploadImage() async {
    await _pickImage();
  }

  Future<void> _uploadImageToFirebase(File imageFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child(user.uid)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      // Always use bytes for web compatibility
      Uint8List imageBytes;
      if (_profileImageBytes != null) {
        imageBytes = _profileImageBytes!;
      } else {
        // Read bytes from file if not already available
        imageBytes = await imageFile.readAsBytes();
      }

      final uploadTask = ref.putData(imageBytes);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      await DatabaseService.updateUserInFirestore(
        userId: user.uid,
        data: {'profileImageUrl': downloadUrl},
      );

      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
          _profileImage = null;
          _profileImageBytes = null; // Clear bytes after upload
        });
      }

      // مسح الكاش لتحديث الصورة في جميع الأماكن
      DatabaseService.clearUserCache(user.uid);

      // إرسال إشعار لتحديث الصورة في جميع الصفحات
      ProfileUpdateService().notifyProfileImageUpdate(user.uid);

      // إرسال إشعار لتحديث الاسم أيضًا للتأكد من التحديث في جميع الصفحات
      ProfileUpdateService().notifyDisplayNameUpdate(user.uid);

      _showSuccessSnackBar('تم تحديث الصورة بنجاح');
    } catch (e) {
      _showErrorSnackBar('خطأ في رفع الصورة: $e');
    }
  }

  Future<void> _navigateToEditProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userData = {
      'displayName': _displayName,
      'handle': _handle,
      'profileImageUrl': _profileImageUrl,
      'bio': _bio,
      'phoneNumber': currentUser.phoneNumber ?? '',
    };

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(userData: userData),
      ),
    );

    if (result == true) {
      _loadUserData(forceRefresh: true);
    }
  }

  void _navigateToFollowersPage(String title) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowersPage(
          userId: currentUser.uid,
          title: title,
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

  String get _getUserPhoneNumber {
    final user = FirebaseAuth.instance.currentUser;
    return user?.phoneNumber ?? '';
  }

  void _showSettingsBottomSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
              automaticallyImplyLeading: false,
              title: GestureDetector(
                onTap: () {
                  final currentUser = FirebaseAuth.instance.currentUser;
                  if (currentUser != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VerificationDetailsPage(
                          userId: currentUser.uid,
                          handle: _handle.isNotEmpty ? _handle : 'المستخدم',
                          displayName: _displayName,
                          profileImageUrl: _profileImageUrl,
                          isVerified: _isVerified,
                        ),
                      ),
                    );
                  }
                },
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _handle.isNotEmpty ? _handle : 'المستخدم',
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
                IconButton(
                  onPressed: _showSettingsBottomSheet,
                  icon: const Icon(Icons.menu, color: Colors.black),
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
                        GestureDetector(
                          onTap: _pickAndUploadImage,
                          child: Stack(
                            children: [
                              Container(
                                width: screenWidth * 0.22,
                                height: screenWidth * 0.22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.grey[300]!, width: 1),
                                ),
                                child: ClipOval(
                                  child: _profileImage != null
                                      ? (_profileImageBytes != null
                                      ? Image.memory(_profileImageBytes!, fit: BoxFit.cover)
                                      : Image.file(_profileImage!, fit: BoxFit.cover))
                                      : _profileImageUrl.isNotEmpty
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
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
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

                    // Name and Bio
                    if (_displayName.isNotEmpty)
                      Text(
                        _displayName,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),

                    const SizedBox(height: 4),

                    if (_getUserPhoneNumber.isNotEmpty)
                      Text(
                        _getUserPhoneNumber,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
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

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _navigateToEditProfile,
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
                              'تعديل الملف الشخصي',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _navigateToAddStory,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: Text(
                              'إضافة قصة',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                    Tab(icon: Icon(Icons.star_outline)),
                  ],
                ),
              ),
            ),

            // Empty space for tab content - posts will be shown directly below tabs
            SliverToBoxAdapter(
              child: SizedBox(
                height: 0, // No space - posts start immediately after tabs
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    Container(), // Posts shown below
                    Container(), // Videos placeholder
                    Container(), // Reviews placeholder
                  ],
                ),
              ),
            ),

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
               child: SizedBox(
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
                          'لم تنشر أي فيديوهات بعد',
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
          ],
        ),
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

  void _setupReviewsListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _reviewsSubscription = FirebaseFirestore.instance
        .collection('reviews')
        .where('reviewedUserId', isEqualTo: currentUser.uid)
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
          ],
        ),
      ),
    );
  }

  Widget _buildReviewsList() {
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reviewer info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _navigateToUserProfile(review['reviewerUserId']),
                child: CircleAvatar(
                  radius: 24,
                  backgroundImage: reviewerData?['profileImageUrl'] != null
                      ? NetworkImage(reviewerData!['profileImageUrl'])
                      : null,
                  backgroundColor: Colors.grey[200],
                  child: reviewerData?['profileImageUrl'] == null
                      ? Icon(Icons.person, size: 24, color: Colors.grey[500])
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اسم المستخدم والتوثيق
                    GestureDetector(
                      onTap: () => _navigateToUserProfile(review['reviewerUserId']),
                      child: Row(
                        children: [
                          Text(
                            reviewerData?['displayName'] ?? 'مستخدم',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                          if (reviewerData?['isVerified'] == true) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.verified,
                              size: 16,
                              color: Colors.blue,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),

                    // التقييم والوقت
                    Row(
                      children: [
                        _buildStarRating(review['rating']?.toDouble() ?? 0.0),
                        const Spacer(),
                        Text(
                          _getTimeAgo(review['createdAt']),
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

          // التعليق
          if (review['comment']?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
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
        return Icon(
          index < rating.floor()
              ? Icons.star
              : index < rating
              ? Icons.star_half
              : Icons.star_border,
          size: size,
          color: Colors.amber,
        );
      }),
    );
  }

  void _navigateToUserProfile(String userId) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || userId == currentUser.uid) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          userId: userId,
          initialDisplayName: _usersCache[userId]?['displayName'],
        ),
      ),
    );
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime dateTime;
    if (timestamp is Timestamp) {
      dateTime = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      return '';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return months == 1 ? 'منذ شهر' : 'منذ $months أشهر';
    } else if (difference.inDays > 0) {
      return difference.inDays == 1 ? 'منذ يوم' : 'منذ ${difference.inDays} أيام';
    } else if (difference.inHours > 0) {
      return difference.inHours == 1 ? 'منذ ساعة' : 'منذ ${difference.inHours} ساعات';
    } else if (difference.inMinutes > 0) {
      return difference.inMinutes == 1 ? 'منذ دقيقة' : 'منذ ${difference.inMinutes} دقائق';
    } else {
      return 'الآن';
    }
  }

  Future<void> _navigateToAddStory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // التحقق من حد إضافة القصص
    final storyLimitCheck = await DatabaseService.checkUserStoryLimit(user.uid);
    
    if (!storyLimitCheck['canAddStory']) {
      _showStoryLimitDialog(storyLimitCheck);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddStoryPage(),
      ),
    );
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
}