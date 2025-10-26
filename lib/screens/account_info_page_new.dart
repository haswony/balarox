
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
            fontSize: 22,
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.contact_phone,
                              size: 24,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'معلومات الاتصال',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.phone,
                                size: 20,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'رقم الهاتف',
                                    style: GoogleFonts.cairo(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatPhoneNumber(user?.phoneNumber),
                                    style: GoogleFonts.cairo(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // حالة التوثيق
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: _isVerified ? Colors.green[50] : Colors.orange[50],
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: _isVerified 
                            ? Colors.green.withOpacity(0.05) 
                            : Colors.orange.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _isVerified 
                              ? Colors.green[100] 
                              : Colors.orange[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.verified_user,
                            size: 28,
                            color: _isVerified 
                              ? Colors.green[700] 
                              : Colors.orange[700],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.verified_user,
                                    size: 22,
                                    color: _isVerified ? Colors.green[700] : Colors.orange[700],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'حالة التوثيق',
                                    style: GoogleFonts.cairo(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isVerified 
                                  ? 'تم توثيق حسابك بنجاح' 
                                  : 'لم يتم توثيق حسابك بعد',
                                style: GoogleFonts.cairo(
                                  fontSize: 15,
                                  color: _isVerified 
                                    ? Colors.green[700] 
                                    : Colors.orange[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isVerified)
                          Icon(
                            Icons.check_circle,
                            size: 28,
                            color: Colors.green[600],
                          ),
                      ],
                    ),
                  ),

                  // معلومات إضافية
                  if (_userData != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 24,
                                color: Colors.blue[700],
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'معلومات إضافية',
                                style: GoogleFonts.cairo(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          if (_userData?['username'] != null) ...[
                            _buildInfoRow(
                              icon: Icons.person,
                              title: 'اسم المستخدم',
                              value: _userData!['username'],
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_userData?['bio'] != null) ...[
                            _buildInfoRow(
                              icon: Icons.info,
                              title: 'نبذة عني',
                              value: _userData!['bio'],
                            ),
                            const SizedBox(height: 16),
                          ],

                          _buildInfoRow(
                            icon: Icons.calendar_today,
                            title: 'تاريخ الانضمام',
                            value: _formatDate(_userData?['createdAt'] ?? user?.metadata.creationTime),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // أزرار الإجراءات
                  Container(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue[700]!,
                                Colors.blue[500]!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blue[700],
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
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
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.orange[600]!,
                                  Colors.orange[400]!,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/verification');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.orange[600],
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
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
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.blue[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
