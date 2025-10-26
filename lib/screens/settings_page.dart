import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'login_page.dart';
import 'verification_request_page.dart';
import 'admin_panel_page.dart';
import 'admin_products_page.dart';
import 'admin_management_page.dart';
import 'clinic_review_page.dart';
// Removed my_products_status_page import
import 'privacy_page.dart';
import 'terms_of_use_page.dart';
import 'privacy_policy_page.dart';
import 'about_page.dart';
import 'account_info_page.dart';
import 'important_pages.dart'; // Added import for important pages
import 'notification_settings_page.dart';
import '../services/database_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isVerified = false;
  bool _isAdmin = false;
  bool _isSuperAdmin = false;
  bool _isLoading = true;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
    _setupUserListener();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
  }

  void _setupUserListener() {
    if (user == null) return;

    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final userData = snapshot.data()!;
        final role = userData['role'] ?? 'user';
        final phoneNumber = userData['phoneNumber'] ?? '';
        final isVerified = userData['isVerified'] ?? false;

        // التحقق من الصلاحيات
        final isMainAdmin = phoneNumber == '+9647712010242';
        final isAdmin = role == 'admin' || role == 'super_admin' || isMainAdmin;
        final isSuperAdmin = role == 'super_admin' || isMainAdmin;

        setState(() {
          _isVerified = isVerified;
          _isAdmin = isAdmin;
          _isSuperAdmin = isSuperAdmin;
        });
      }
    });
  }

  Future<void> _checkUserStatus() async {
    if (user == null) return;

    try {
      // التحقق من حالة التوثيق
      final userData = await DatabaseService.getUserFromFirestore(user!.uid);
      final isVerified = userData?['isVerified'] ?? false;

      // التحقق من صلاحيات المشرف مع fallback فوري للمشرف الرئيسي
      final phoneNumber = user!.phoneNumber ?? '';
      final isMainAdmin = phoneNumber == '+9647712010242';

      // إذا كان المشرف الرئيسي، لا نحتاج لانتظار قاعدة البيانات
      if (isMainAdmin) {
        if (mounted) {
          setState(() {
            _isVerified = isVerified;
            _isAdmin = true;
            _isSuperAdmin = true;
            _isLoading = false;
          });
        }
        return;
      }

      // التحقق من صلاحيات المشرف للمستخدمين العاديين مع استخدام الكاش
      final isAdmin = await DatabaseService.isAdmin(user!.uid);
      final isSuperAdmin = await DatabaseService.isSuperAdmin(user!.uid);

      if (mounted) {
        setState(() {
          _isVerified = isVerified;
          _isAdmin = isAdmin || isSuperAdmin;
          _isSuperAdmin = isSuperAdmin;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في التحقق من حالة المستخدم: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'الإعدادات',
          style: GoogleFonts.cairo(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قسم الحساب
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'الحساب',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            
            _buildSettingItem(
              icon: Icons.person_outline,
              title: 'معلومات الحساب',
              subtitle: 'رقم الهاتف والبريد الإلكتروني',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountInfoPage(),
                  ),
                );
              },
            ),
            
            _buildSettingItem(
              icon: Icons.lock_outline,
              title: 'الخصوصية',
              subtitle: 'إعدادات الخصوصية والأمان',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrivacyPage(),
                  ),
                );
              },
            ),
            
            _buildSettingItem(
              icon: Icons.notifications_outlined,
              title: 'الإشعارات',
              subtitle: 'إدارة الإشعارات',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationSettingsPage(),
                  ),
                );
              },
            ),
            
            // طلب التوثيق (إذا لم يكن موثق)
            if (!_isVerified && !_isLoading)
              _buildSettingItem(
                icon: Icons.verified_user,
                title: 'طلب التوثيق',
                subtitle: 'احصل على العلامة الزرقاء',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const VerificationRequestPage(),
                    ),
                  );
                },
              ),

            // قسم الصفحات المهمة
            _buildSettingItem(
              icon: Icons.star_outline,
              title: 'الصفحات المهمة',
              subtitle: 'الوصول السريع للصفحات المهمة',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ImportantPages(),
                  ),
                );
              },
            ),

            // إدارة المشرفين (للمشرف الرئيسي فقط)
            if (_isSuperAdmin)
              _buildSettingItem(
                icon: Icons.manage_accounts,
                title: 'إدارة المشرفين',
                subtitle: 'إضافة وإزالة المشرفين',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminManagementPage(),
                    ),
                  );
                },
              ),

            // لوحة تحكم المشرف (للمشرف فقط)
            if (_isAdmin) ...[
              _buildSettingItem(
                icon: Icons.admin_panel_settings,
                title: 'لوحة تحكم المشرف',
                subtitle: 'إدارة التطبيق والمستخدمين',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminPanelPage(),
                    ),
                  );
                },
              ),
              _buildSettingItem(
                icon: Icons.inventory_2,
                title: 'إدارة المنتجات',
                subtitle: 'مراجعة وموافقة المنتجات المعلقة',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminProductsPage(),
                    ),
                  );
                },
              ),
              _buildSettingItem(
                icon: Icons.local_hospital,
                title: 'طلبات مراجعة العيادات',
                subtitle: 'مراجعة وموافقة العيادات المعلقة',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ClinicReviewPage(),
                    ),
                  );
                },
              ),
            ],
            
             const Divider(height: 32),
            
            // قسم المساعدة
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'المساعدة والدعم',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            
            _buildSettingItem(
              icon: Icons.help_outline,
              title: 'مركز المساعدة',
              subtitle: 'الأسئلة الشائعة والدعم',
              onTap: () async {
                final Uri whatsappUrl = Uri.parse('whatsapp://send?phone=9647712010242');
                if (await canLaunchUrl(whatsappUrl)) {
                  await launchUrl(whatsappUrl);
                } else {
                  final Uri webUrl = Uri.parse('https://wa.me/9647712010242');
                  await launchUrl(webUrl);
                }
              },
            ),
            
            _buildSettingItem(
              icon: Icons.info_outline,
              title: 'حول التطبيق',
              subtitle: 'معلومات التطبيق والإصدار',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutPage(),
                  ),
                );
              },
            ),
            
            _buildSettingItem(
              icon: Icons.privacy_tip_outlined,
              title: 'سياسة الخصوصية',
              subtitle: 'اقرأ سياسة الخصوصية',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrivacyPolicyPage(),
                  ),
                );
              },
            ),
            
            _buildSettingItem(
              icon: Icons.description_outlined,
              title: 'الشروط والأحكام',
              subtitle: 'شروط الاستخدام',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TermsOfUsePage(),
                  ),
                );
              },
            ),
            
            const Divider(height: 32),
            
            // زر تسجيل الخروج
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _showLogoutDialog,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    splashFactory: NoSplash.splashFactory,
                  ),
                  child: Text(
                    'تسجيل الخروج',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            
            // معلومات الحساب
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'تم تسجيل الدخول كـ',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.phoneNumber ?? 'غير معروف',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'الإصدار 1.0.2',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.black),
      ),
      title: Text(
        title,
        style: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.cairo(
          fontSize: 14,
          color: Colors.grey[600],
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey,
      ),
      splashColor: Colors.transparent,
      onTap: onTap,
    );
  }
  
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'تسجيل الخروج',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'هل أنت متأكد من تسجيل الخروج؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                color: Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              }
            },
            child: Text(
              'تسجيل الخروج',
              style: GoogleFonts.cairo(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
