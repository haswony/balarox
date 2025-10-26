import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/database_service.dart';

class AdminManagementPage extends StatefulWidget {
  const AdminManagementPage({super.key});

  @override
  State<AdminManagementPage> createState() => _AdminManagementPageState();
}

class _AdminManagementPageState extends State<AdminManagementPage> {
  List<Map<String, dynamic>> _admins = [];
  bool _isLoading = true;
  final TextEditingController _handleController = TextEditingController();
  Map<String, dynamic> _editingPermissions = {};

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final admins = await DatabaseService.getAdmins();

      // تحميل الصلاحيات لكل مشرف
      for (var admin in admins) {
        final permissions = await DatabaseService.getUserPermissions(admin['id']);
        admin['permissions'] = permissions;
      }

      if (mounted) {
        setState(() {
          _admins = admins;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل المشرفين: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _addAdmin() async {
    final handle = _handleController.text.trim();
    if (handle.isEmpty) {
      _showErrorSnackBar('يرجى إدخال اسم المستخدم');
      return;
    }

    try {
      // البحث عن المستخدم بالـ handle
      final users = await DatabaseService.getUsersByHandle(handle);
      if (users.isEmpty) {
        _showErrorSnackBar('لم يتم العثور على مستخدم بهذا الاسم');
        return;
      }

      final user = users.first;
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // التحقق من أن المستخدم ليس مشرفاً بالفعل
      final userRole = await DatabaseService.getUserRole(user['id']);
      if (userRole == 'admin' || userRole == 'super_admin') {
        _showErrorSnackBar('هذا المستخدم مشرف بالفعل');
        return;
      }

      // ترقية المستخدم
      await DatabaseService.promoteToAdmin(user['id'], currentUser.uid);

      // مسح الكاش للمستخدم الجديد
      DatabaseService.clearUserCache(user['id']);

      _handleController.clear();
      _showSuccessSnackBar('تم إضافة المشرف بنجاح');
      _loadAdmins();
    } catch (e) {
      _showErrorSnackBar('خطأ في إضافة المشرف: $e');
    }
  }

  Future<void> _removeAdmin(String adminId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      await DatabaseService.demoteFromAdmin(adminId, currentUser.uid);
      _showSuccessSnackBar('تم إزالة المشرف بنجاح');
      _loadAdmins();
    } catch (e) {
      _showErrorSnackBar('خطأ في إزالة المشرف: $e');
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
        title: Text(
          'إدارة المشرفين',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAdmins,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // قسم إضافة مشرف جديد
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إضافة مشرف جديد',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _handleController,
                              decoration: InputDecoration(
                                hintText: 'أدخل اسم المستخدم (handle)',
                                hintStyle: GoogleFonts.cairo(),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                prefixIcon: const Icon(Icons.person_search),
                              ),
                              style: GoogleFonts.cairo(),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _addAdmin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  'إضافة مشرف',
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
                    ),

                    const SizedBox(height: 24),

                    // قسم قائمة المشرفين
                    Text(
                      'قائمة المشرفين',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_admins.isEmpty)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.admin_panel_settings_outlined,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا يوجد مشرفون',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _admins.length,
                        itemBuilder: (context, index) {
                          final admin = _admins[index];
                          final role = admin['role'] ?? 'user';
                          final isSuperAdmin = role == 'super_admin';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundImage: admin['profileImageUrl']?.isNotEmpty == true
                                            ? NetworkImage(admin['profileImageUrl'])
                                            : null,
                                        backgroundColor: Colors.grey[300],
                                        radius: 25,
                                        child: admin['profileImageUrl']?.isEmpty != false
                                            ? const Icon(Icons.person, color: Colors.grey)
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    admin['displayName'] ?? 'مستخدم',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isSuperAdmin) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red[100],
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: Text(
                                                      'رئيسي',
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 12,
                                                        color: Colors.red[800],
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ] else ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.blue[100],
                                                      borderRadius: BorderRadius.circular(10),
                                                    ),
                                                    child: Text(
                                                      'مشرف',
                                                      style: GoogleFonts.cairo(
                                                        fontSize: 12,
                                                        color: Colors.blue[800],
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            Text(
                                              admin['handle'] ?? admin['phoneNumber'] ?? '',
                                              style: GoogleFonts.cairo(
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!isSuperAdmin) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () => _showEditPermissionsDialog(admin),
                                          tooltip: 'تعديل الصلاحيات',
                                          iconSize: 20,
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove_circle,
                                            color: Colors.red,
                                          ),
                                          onPressed: () => _showRemoveAdminDialog(admin),
                                          tooltip: 'إزالة المشرف',
                                          iconSize: 20,
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  void _showRemoveAdminDialog(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'إزالة المشرف',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من رغبتك في إزالة "${admin['displayName'] ?? 'هذا المشرف'}" من قائمة المشرفين؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _removeAdmin(admin['id']);
            },
            child: Text(
              'إزالة',
              style: GoogleFonts.cairo(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditPermissionsDialog(Map<String, dynamic> admin) {
    _editingPermissions = Map<String, dynamic>.from(admin['permissions'] ?? {
      'users': true,
      'reports': false,
      'statistics': true,
      'verification': false,
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'تعديل صلاحيات المشرف',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المشرف: ${admin['displayName'] ?? 'غير محدد'}',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildPermissionSwitch('صلاحية إدارة المستخدمين', 'users', setState),
                _buildPermissionSwitch('صلاحية مراجعة البلاغات', 'reports', setState),
                _buildPermissionSwitch('صلاحية عرض الإحصائيات', 'statistics', setState),
                _buildPermissionSwitch('صلاحية مراجعة التوثيق', 'verification', setState),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await DatabaseService.updateUserFieldsByAdmin(
                    userId: admin['id'],
                    data: {'permissions': _editingPermissions},
                    adminId: FirebaseAuth.instance.currentUser!.uid,
                  );
                  Navigator.pop(context);
                  _showSuccessSnackBar('تم تحديث الصلاحيات بنجاح');
                  _loadAdmins();
                } catch (e) {
                  _showErrorSnackBar('خطأ في تحديث الصلاحيات: $e');
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
        ),
      ),
    );
  }

  Widget _buildPermissionSwitch(String title, String permissionKey, StateSetter setState) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.cairo(fontSize: 14),
            ),
          ),
          Switch(
            value: _editingPermissions[permissionKey] ?? false,
            onChanged: (value) {
              setState(() {
                _editingPermissions[permissionKey] = value;
              });
            },
            activeColor: Colors.blue,
          ),
        ],
      ),
    );
  }
}