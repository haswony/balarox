import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/database_service.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> with TickerProviderStateMixin {
  TabController? _tabController;
  List<Map<String, dynamic>> _verificationRequests = [];
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _packageRequests = [];
  bool _isLoading = true;
  Map<String, dynamic> _userPermissions = {};

  @override
  void initState() {
    super.initState();
    _loadPermissionsAndSetup();
  }

  Future<void> _loadPermissionsAndSetup() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        _userPermissions = await DatabaseService.getUserPermissions(currentUser.uid);
      }

      // حساب عدد التبويبات المسموح بها
      int tabCount = 0;
      if (_userPermissions['verification'] == true) tabCount++;
      if (_userPermissions['reports'] == true) tabCount++;
      if (_userPermissions['users'] == true) tabCount++;
      if (_userPermissions['statistics'] == true) tabCount++;
      // Always allow package requests for admins
      tabCount++;

      // إذا لم تكن هناك صلاحيات، أعطِ الحد الأدنى
      if (tabCount == 0) {
        tabCount = 5; // افتراضياً للمشرف الرئيسي
      }

      _tabController = TabController(length: tabCount, vsync: this);
      _loadData();
    } catch (e) {
      print('خطأ في تحميل الصلاحيات: $e');
      _tabController = TabController(length: 4, vsync: this);
      _loadData();
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // تحميل طلبات التوثيق
      final verificationSnapshot = await FirebaseFirestore.instance
          .collection('verification_requests')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      // تحميل جميع المستخدمين
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .get();

      // تحميل البلاغات المعلقة
      final reports = await DatabaseService.getReports(status: 'pending');

      // تحميل طلبات الباقات
      final packageRequests = await DatabaseService.getPackageRequests();

      if (mounted) {
        setState(() {
          _verificationRequests = verificationSnapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

          _allUsers = usersSnapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

          _reports = reports;
          _packageRequests = packageRequests;
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

  Future<void> _approveVerification(String requestId, String userId) async {
    try {
      // تحديث طلب التوثيق
      await FirebaseFirestore.instance
          .collection('verification_requests')
          .doc(requestId)
          .update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      // تحديث المستخدم ليصبح موثق
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'isVerified': true,
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      // مسح الكاش لضمان تحديث البيانات فوراً
      DatabaseService.clearUserCache(userId);

      _showSuccessSnackBar('تم قبول طلب التوثيق بنجاح');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في قبول طلب التوثيق: $e');
    }
  }

  Future<void> _rejectVerification(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('verification_requests')
          .doc(requestId)
          .update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': FirebaseAuth.instance.currentUser?.uid,
      });

      _showSuccessSnackBar('تم رفض طلب التوثيق');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في رفض طلب التوثيق: $e');
    }
  }

  Future<void> _toggleUserVerification(String userId, bool isVerified) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({
        'isVerified': !isVerified,
        'verifiedAt': !isVerified ? FieldValue.serverTimestamp() : FieldValue.delete(),
      });

      // مسح الكاش لضمان تحديث البيانات فوراً
      DatabaseService.clearUserCache(userId);

      _showSuccessSnackBar(
        !isVerified ? 'تم توثيق المستخدم' : 'تم إلغاء توثيق المستخدم'
      );
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في تحديث حالة التوثيق: $e');
    }
  }

  // Method to show edit user dialog for supervisors
  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final TextEditingController joinDateController = TextEditingController(
      text: user['createdAt'] != null ? _formatDate(user['createdAt']) : ''
    );
    
    final TextEditingController verificationDateController = TextEditingController(
      text: user['verifiedAt'] != null ? _formatDate(user['verifiedAt']) : ''
    );
    
    DateTime? selectedJoinDate = user['createdAt'] is Timestamp 
        ? user['createdAt'].toDate() 
        : DateTime.now();
        
    DateTime? selectedVerificationDate = user['verifiedAt'] is Timestamp 
        ? user['verifiedAt'].toDate() 
        : null;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              'تعديل بيانات المستخدم',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'اسم المستخدم: ${user['displayName'] ?? 'غير محدد'}',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  
                  // Join Date Field
                  Text(
                    'تاريخ الانضمام:',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: joinDateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'اختر تاريخ الانضمام',
                      hintStyle: GoogleFonts.cairo(),
                      suffixIcon: const Icon(Icons.calendar_today),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedJoinDate ?? DateTime.now(),
                        firstDate: DateTime(2000), // Allow dates from year 2000
                        lastDate: DateTime(2100), // Allow dates up to year 2100
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.blue,
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: Colors.black,
                              ),
                              textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          selectedJoinDate = picked;
                          joinDateController.text = '${picked.day}/${picked.month}/${picked.year}';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Verification Date Field
                  Text(
                    'تاريخ التوثيق:',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: verificationDateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'اختر تاريخ التوثيق',
                      hintStyle: GoogleFonts.cairo(),
                      suffixIcon: const Icon(Icons.verified),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedVerificationDate ?? DateTime.now(),
                        firstDate: DateTime(2000), // Allow dates from year 2000
                        lastDate: DateTime(2100), // Allow dates up to year 2100
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Colors.blue,
                                onPrimary: Colors.white,
                                surface: Colors.white,
                                onSurface: Colors.black,
                              ),
                              textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          selectedVerificationDate = picked;
                          verificationDateController.text = '${picked.day}/${picked.month}/${picked.year}';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Hide Verification History Toggle
                  Row(
                    children: [
                      Text(
                        'إخفاء تاريخ التوثيق:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Switch(
                        value: user['hideVerificationHistory'] ?? false,
                        onChanged: (value) {
                          setState(() {
                            user['hideVerificationHistory'] = value;
                          });
                        },
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.cairo(color: Colors.grey[700]),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  // Update user data
                  try {
                    Map<String, dynamic> updateData = {};
                    
                    if (selectedJoinDate != null) {
                      updateData['createdAt'] = Timestamp.fromDate(selectedJoinDate!);
                    }
                    
                    if (selectedVerificationDate != null) {
                      updateData['verifiedAt'] = Timestamp.fromDate(selectedVerificationDate!);
                    }

                    // Add hide verification history toggle
                    updateData['hideVerificationHistory'] = user['hideVerificationHistory'] ?? false;

                    final currentUser = FirebaseAuth.instance.currentUser;
                    if (currentUser != null) {
                      await DatabaseService.updateUserFieldsByAdmin(
                        userId: user['id'],
                        data: updateData,
                        adminId: currentUser.uid,
                      );
                      
                      _showSuccessSnackBar('تم تحديث بيانات المستخدم بنجاح');
                      Navigator.pop(context);
                      _loadData(); // Refresh data
                    }
                  } catch (e) {
                    _showErrorSnackBar('خطأ في تحديث البيانات: $e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'حفظ',
                  style: GoogleFonts.cairo(color: Colors.white),
                ),
              ),
            ],
          );
        },
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

  // قائمة بالتبويبات المسموح بها
  List<Map<String, dynamic>> _getAllowedTabs() {
    List<Map<String, dynamic>> allowedTabs = [];

    if (_userPermissions['verification'] == true) {
      allowedTabs.add({
        'key': 'verification',
        'icon': Icons.verified_user,
        'title': 'التوثيق',
        'badge': _verificationRequests.length,
        'badgeColor': Colors.orange,
      });
    }

    if (_userPermissions['reports'] == true) {
      allowedTabs.add({
        'key': 'reports',
        'icon': Icons.flag,
        'title': 'البلاغات',
        'badge': _reports.length,
        'badgeColor': Colors.red,
      });
    }

    if (_userPermissions['users'] == true) {
      allowedTabs.add({
        'key': 'users',
        'icon': Icons.people,
        'title': 'المستخدمون',
        'badge': 0,
        'badgeColor': Colors.blue,
      });
    }

    if (_userPermissions['statistics'] == true || _userPermissions.isEmpty) {
      allowedTabs.add({
        'key': 'statistics',
        'icon': Icons.analytics,
        'title': 'الإحصائيات',
        'badge': 0,
        'badgeColor': Colors.blue,
      });
    }

    // Always add package requests tab
    allowedTabs.add({
      'key': 'packages',
      'icon': Icons.shopping_cart,
      'title': 'الباقات',
      'badge': _packageRequests.length,
      'badgeColor': Colors.green,
    });

    // إذا لم تكن هناك صلاحيات محددة، أظهر جميع التبويبات (للمشرف الرئيسي)
    if (allowedTabs.isEmpty) {
      allowedTabs = [
        {
          'key': 'verification',
          'icon': Icons.verified_user,
          'title': 'التوثيق',
          'badge': _verificationRequests.length,
          'badgeColor': Colors.orange,
        },
        {
          'key': 'reports',
          'icon': Icons.flag,
          'title': 'البلاغات',
          'badge': _reports.length,
          'badgeColor': Colors.red,
        },
        {
          'key': 'users',
          'icon': Icons.people,
          'title': 'المستخدمون',
          'badge': 0,
          'badgeColor': Colors.blue,
        },
        {
          'key': 'statistics',
          'icon': Icons.analytics,
          'title': 'الإحصائيات',
          'badge': 0,
          'badgeColor': Colors.blue,
        },
        {
          'key': 'packages',
          'icon': Icons.shopping_cart,
          'title': 'الباقات',
          'badge': _packageRequests.length,
          'badgeColor': Colors.green,
        },
      ];
    }

    return allowedTabs;
  }

  // قائمة بالمحتويات المسموح بها
  List<Widget> _getAllowedTabViews() {
    List<Widget> allowedViews = [];

    if (_userPermissions['verification'] == true || _userPermissions.isEmpty) {
      allowedViews.add(_buildVerificationRequestsTab());
    }

    if (_userPermissions['reports'] == true || _userPermissions.isEmpty) {
      allowedViews.add(_buildReportsTab());
    }

    if (_userPermissions['users'] == true || _userPermissions.isEmpty) {
      allowedViews.add(_buildUsersTab());
    }

    if (_userPermissions['statistics'] == true || _userPermissions.isEmpty) {
      allowedViews.add(_buildStatisticsTab());
    }

    // Always add packages tab
    allowedViews.add(_buildPackagesTab());

    return allowedViews;
  }

  @override
  Widget build(BuildContext context) {
    // إذا لم يتم تهيئة TabController بعد، أظهر شاشة التحميل
    if (_tabController == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'لوحة تحكم المشرف',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.black),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final allowedTabs = _getAllowedTabs();
    final allowedViews = _getAllowedTabViews();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'لوحة تحكم المشرف',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController!,
              indicatorColor: Colors.blue,
              indicatorWeight: 3,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey[600],
              labelStyle: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              unselectedLabelStyle: GoogleFonts.cairo(
                fontSize: 14,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: allowedTabs.map((tab) {
                return Tab(
                  height: 60,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(tab['icon'], size: 24),
                          if (tab['badge'] > 0)
                            Positioned(
                              right: -8,
                              top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: tab['badgeColor'],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                child: Text(
                                  '${tab['badge']}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tab['title'],
                        style: GoogleFonts.cairo(fontSize: 12),
                        maxLines: 1,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController!,
              children: allowedViews,
            ),
    );
  }

  Widget _buildVerificationRequestsTab() {
    if (_verificationRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد طلبات توثيق جديدة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _verificationRequests.length,
        itemBuilder: (context, index) {
          final request = _verificationRequests[index];
          return _buildVerificationRequestCard(request);
        },
      ),
    );
  }

  Widget _buildVerificationRequestCard(Map<String, dynamic> request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: request['userProfileImage']?.isNotEmpty == true
                      ? NetworkImage(request['userProfileImage'])
                      : null,
                  backgroundColor: Colors.grey[300],
                  child: request['userProfileImage']?.isEmpty != false
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['userDisplayName'] ?? 'مستخدم',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        request['userHandle'] ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            if (request['reason']?.isNotEmpty == true) ...[
              Text(
                'سبب طلب التوثيق:',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                request['reason'],
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            if (request['idImageUrl']?.isNotEmpty == true) ...[
              Text(
                'صورة الهوية:',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showImageDialog(request['idImageUrl']),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      request['idImageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[100],
                          child: const Icon(Icons.error, color: Colors.red),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _approveVerification(request['id'], request['userId']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'قبول',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _rejectVerification(request['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'رفض',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _allUsers.length,
        itemBuilder: (context, index) {
          final user = _allUsers[index];
          return _buildUserCard(user);
        },
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isVerified = user['isVerified'] ?? false;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            CircleAvatar(
              backgroundImage: user['profileImageUrl']?.isNotEmpty == true
                  ? NetworkImage(user['profileImageUrl'])
                  : null,
              backgroundColor: Colors.grey[300],
              radius: 25,
              child: user['profileImageUrl']?.isEmpty != false
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
            const SizedBox(width: 12),
            // Info column - expanded to take available space
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          user['displayName'] ?? 'مستخدم',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isVerified)
                        const Icon(
                          Icons.verified,
                          color: Colors.blue,
                          size: 18,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatContact(user),
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (user['createdAt'] != null)
                    Text(
                      'انضمام: ${_formatDate(user['createdAt'])}',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Buttons column
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                  onPressed: () => _showEditUserDialog(user),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red, size: 20),
                  onPressed: () => _showDeleteUserConfirmationDialog(user),
                  tooltip: 'حذف',
                ),
                Switch(
                  value: isVerified,
                  onChanged: (value) => _toggleUserVerification(user['id'], isVerified),
                  activeColor: Colors.blue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsTab() {
    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد بلاغات جديدة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          return _buildReportCard(report);
        },
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final isUserReport = report['type'] == 'user';
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس البطاقة - نوع البلاغ والتاريخ
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isUserReport
                        ? [Colors.orange[400]!, Colors.orange[600]!]
                        : [Colors.purple[400]!, Colors.purple[600]!],
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: (isUserReport ? Colors.orange : Colors.purple).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isUserReport ? Icons.person : Icons.inventory_2,
                        size: 18,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isUserReport ? 'بلاغ عن مستخدم' : 'بلاغ عن منتج',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(report['createdAt']),
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
            
            // قسم السبب
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[100]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'سبب البلاغ',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    report['reason'] ?? 'غير محدد',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.red[800],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            
            // التفاصيل الإضافية إن وجدت
            if (report['details']?.isNotEmpty == true) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'تفاصيل إضافية',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report['details'],
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 20),
            
            // أزرار الإجراءات - تصميم محسن
            Column(
              children: [
                // الصف الأول من الأزرار
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleReport(report, 'resolved'),
                        icon: const Icon(Icons.check_circle, size: 20),
                        label: Text(
                          'تم المعالجة',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _handleReport(report, 'dismissed'),
                        icon: const Icon(Icons.close, size: 20),
                        label: Text(
                          'رفض البلاغ',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          side: BorderSide(color: Colors.grey[300]!, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // زر الحذف
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isUserReport
                      ? () async {
                          try {
                            // Fetch user data to pass to the confirmation dialog
                            final userData = await DatabaseService.getUserFromFirestore(report['reportedUserId']);
                            final user = {
                              'id': report['reportedUserId'],
                              'displayName': userData?['displayName'] ?? 'مستخدم'
                            };
                            _showDeleteUserConfirmationDialog(user);
                          } catch (e) {
                            // If we can't fetch user data, still show the dialog with basic info
                            final user = {
                              'id': report['reportedUserId'],
                              'displayName': 'مستخدم'
                            };
                            _showDeleteUserConfirmationDialog(user);
                          }
                        }
                      : () {
                          // Show product deletion confirmation
                          _showDeleteProductConfirmationDialog(
                            report['productId'], 
                            report['productTitle'] ?? 'منتج'
                          );
                        },
                    icon: Icon(
                      isUserReport ? Icons.person_remove : Icons.delete_forever,
                      size: 20,
                    ),
                    label: Text(
                      isUserReport ? 'حذف المستخدم نهائياً' : 'حذف المنتج نهائياً',
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleReport(Map<String, dynamic> report, String status) async {
    try {
      await DatabaseService.updateReportStatus(report['id'], status);
      _showSuccessSnackBar('تم تحديث حالة البلاغ');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في تحديث البلاغ: $e');
    }
  }

  Future<void> _deleteUser(String userId) async {
    try {
      await DatabaseService.deleteUserByAdmin(userId);
      _showSuccessSnackBar('تم حذف المستخدم');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في حذف المستخدم: $e');
    }
  }
  
  // Method to show confirmation dialog before deleting a user
  Future<void> _showDeleteUserConfirmationDialog(Map<String, dynamic> user) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'تأكيد حذف المستخدم',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في حذف المستخدم "${user['displayName'] ?? 'مستخدم'}" نهائياً؟\n\n'
          'سيتم حذف:\n'
          '• حساب المستخدم من قاعدة البيانات\n'
          '• جميع منتجاته وقصصه\n'
          '• جميع متابعاته ومتابعيه\n'
          '• جميع إشعاراته وبلاغاته\n'
          '• حسابه من Firebase Authentication\n\n'
          'هذا الإجراء لا يمكن التراجع عنه!',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(color: Colors.grey[700]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteUser(user['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'حذف نهائياً',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProduct(String productId) async {
    try {
      await DatabaseService.deleteProductByAdmin(productId);
      _showSuccessSnackBar('تم حذف المنتج');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في حذف المنتج: $e');
    }
  }
  
  // Method to show confirmation dialog before deleting a product
  Future<void> _showDeleteProductConfirmationDialog(String productId, String productTitle) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'تأكيد حذف المنتج',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في حذف المنتج "$productTitle" نهائياً؟\n\n'
          'هذا الإجراء لا يمكن التراجع عنه!',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(color: Colors.grey[700]),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteProduct(productId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'حذف نهائياً',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else {
      date = timestamp;
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatContact(Map<String, dynamic> user) {
    final String? handle = user['handle'];
    final String? phone = user['phoneNumber'];
    if (handle != null && handle.isNotEmpty) {
      return handle;
    }
    if (phone != null && phone.isNotEmpty) {
      return phone;
    }
    return '';
  }

  Widget _buildStatisticsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildStatCard('إجمالي المستخدمين', _allUsers.length.toString(), Icons.people),
          const SizedBox(height: 16),
          _buildStatCard('طلبات التوثيق المعلقة', _verificationRequests.length.toString(), Icons.pending),
          const SizedBox(height: 16),
          _buildStatCard('البلاغات المعلقة', _reports.length.toString(), Icons.flag, Colors.orange),
          const SizedBox(height: 16),
          _buildStatCard('طلبات الباقات المعلقة', _packageRequests.length.toString(), Icons.shopping_cart, Colors.green),
          const SizedBox(height: 16),
          _buildStatCard('المستخدمون الموثقون',
            _allUsers.where((u) => u['isVerified'] == true).length.toString(),
            Icons.verified_user),
        ],
      ),
    );
  }

  Widget _buildPackagesTab() {
    if (_packageRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد طلبات باقات جديدة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _packageRequests.length,
        itemBuilder: (context, index) {
          final request = _packageRequests[index];
          return _buildPackageRequestCard(request);
        },
      ),
    );
  }

  Widget _buildPackageRequestCard(Map<String, dynamic> request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: request['userProfileImage']?.isNotEmpty == true
                      ? NetworkImage(request['userProfileImage'])
                      : null,
                  backgroundColor: Colors.grey[300],
                  child: request['userProfileImage']?.isEmpty != false
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request['userDisplayName'] ?? 'مستخدم',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        request['userHandle'] ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'الباقة المطلوبة: ${request['package']}',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'عنوان الإعلان: ${request['title']}',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'الوصف: ${request['description']}',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[700],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _approvePackageRequest(request['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'قبول',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _rejectPackageRequest(request['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'رفض',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approvePackageRequest(String requestId) async {
    try {
      await DatabaseService.approvePackageRequest(requestId, FirebaseAuth.instance.currentUser!.uid);
      _showSuccessSnackBar('تم قبول طلب الباقة ونشر الإعلان');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في قبول طلب الباقة: $e');
    }
  }

  Future<void> _rejectPackageRequest(String requestId) async {
    try {
      await DatabaseService.rejectPackageRequest(requestId, FirebaseAuth.instance.currentUser!.uid, 'تم رفض الطلب من قبل المشرف');
      _showSuccessSnackBar('تم رفض طلب الباقة');
      _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في رفض طلب الباقة: $e');
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, [Color? color]) {
    final cardColor = color ?? Colors.blue;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cardColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cardColor, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.cairo(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text('صورة الهوية', style: GoogleFonts.cairo()),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
              ),
              Expanded(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(Icons.error, color: Colors.red, size: 50),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
