
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_profile_page.dart';
import '../services/database_service.dart';

class AccountInfoPage extends StatefulWidget {
  const AccountInfoPage({super.key});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  bool _isVerified = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'غير متوفر';
    if (date is Timestamp) {
      return date.toDate().toString().substring(0, 10);
    } else if (date is DateTime) {
      return date.toString().substring(0, 10);
    }
    return 'غير متوفر';
  }

  String _formatPhoneNumber(String? phone) {
    if (phone == null || phone.isEmpty) return 'غير متوفر';
    // إزالة الكود الدولي إذا كان موجودًا
    if (phone.startsWith('+964')) {
      return phone.substring(4);
    } else if (phone.startsWith('00964')) {
      return phone.substring(5);
    }
    return phone;
  }

  Future<void> _loadUserData() async {
    if (user == null) return;

    try {
      final userData = await DatabaseService.getUserFromFirestore(user!.uid);
      final isVerified = userData?['isVerified'] ?? false;

      if (mounted) {
        setState(() {
          _userData = userData;
          _isVerified = isVerified;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل بيانات المستخدم: $e');
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
          'معلومات الحساب',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قسم معلومات الاتصال
            const SizedBox(height: 12),
            Text(
              'معلومات الاتصال',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.phone,
                  size: 24,
                  color: Colors.black,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _formatPhoneNumber(user?.phoneNumber),
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(color: Colors.grey[200], thickness: 1),
            const SizedBox(height: 24),

            // حالة التوثيق
            Text(
              'حالة التوثيق',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.verified_user,
                  size: 24,
                  color: Colors.black,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _isVerified
                        ? 'تم توثيق حسابك بنجاح'
                        : 'لم يتم توثيق حسابك بعد',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(color: Colors.grey[200], thickness: 1),
            const SizedBox(height: 24),

            // معلومات إضافية
            if (_userData != null) ...[
              Text(
                'معلومات إضافية',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 20),

              if (_userData?['username'] != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: 24,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'اسم المستخدم',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userData!['username'],
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              if (_userData?['bio'] != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.info,
                      size: 24,
                      color: Colors.black,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'نبذة عني',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _userData!['bio'],
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 24,
                    color: Colors.black,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تاريخ الانضمام',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(_userData?['createdAt'] ?? user?.metadata.creationTime),
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: Colors.grey[200], thickness: 1),
              const SizedBox(height: 24),
            ],

            // أزرار الإجراءات
            Text(
              'الإجراءات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditProfilePage(
                        userData: _userData ?? {},
                      ),
                    ),
                  ).then((_) {
                    _loadUserData(); // إعادة تحميل البيانات بعد العودة
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'تعديل الملف الشخصي',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (!_isVerified)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/verification');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'طلب التوثيق',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }



}
