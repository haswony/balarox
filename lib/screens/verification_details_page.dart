import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VerificationDetailsPage extends StatefulWidget {
  final String userId;
  final String handle;
  final String? displayName;
  final String? profileImageUrl;
  final bool isVerified;

  const VerificationDetailsPage({
    super.key,
    required this.userId,
    required this.handle,
    this.displayName,
    this.profileImageUrl,
    required this.isVerified,
  });

  @override
  State<VerificationDetailsPage> createState() => _VerificationDetailsPageState();
}

class _VerificationDetailsPageState extends State<VerificationDetailsPage> {
  DateTime? _joinDate;
  DateTime? _verificationDate;
  bool _isLoading = true;
  bool _hideVerificationHistory = false;

  @override
  void initState() {
    super.initState();
    _loadAccountDetails();
  }

  Future<void> _loadAccountDetails() async {
    try {
      // جلب بيانات المستخدم من Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;

        setState(() {
          // تاريخ الانضمام
          if (userData['createdAt'] != null) {
            _joinDate = (userData['createdAt'] as Timestamp).toDate();
          }

          // تاريخ التوثيق
          if (userData['verifiedAt'] != null) {
            _verificationDate = (userData['verifiedAt'] as Timestamp).toDate();
          }

          // إخفاء تاريخ التوثيق
          _hideVerificationHistory = userData['hideVerificationHistory'] ?? false;

          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل تفاصيل الحساب: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not available';

    // تنسيق التاريخ
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: Text(
          'حول هذا الحساب',
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),

            // صورة الحساب
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty
                    ? Image.network(
                  widget.profileImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: Icon(
                        Icons.person,
                        size: 50,
                        color: Colors.grey[400],
                      ),
                    );
                  },
                )
                    : Container(
                  color: Colors.grey[200],
                  child: Icon(
                    Icons.person,
                    size: 50,
                    color: Colors.grey[400],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Handle مع علامة التوثيق
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '@${widget.handle}',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                if (widget.isVerified) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.verified,
                    color: Colors.blue,
                    size: 22,
                  ),
                ],
              ],
            ),

            if (widget.displayName != null && widget.displayName!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.displayName!,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],

            const SizedBox(height: 30),

            // خط فاصل
            Container(
              height: 1,
              color: Colors.grey[300],
            ),

            // معلومات الحساب
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // تاريخ الانضمام
                  _buildInfoRow(
                    icon: Icons.calendar_today_outlined,
                    title: 'تاريخ الانضمام',
                    value: _formatDate(_joinDate),
                    iconColor: Colors.black,
                  ),

                  const SizedBox(height: 20),

                  // تاريخ التوثيق
                  if (widget.isVerified && !_hideVerificationHistory) ...[
                    _buildInfoRow(
                      icon: Icons.verified_outlined,
                      title: 'تاريخ التوثيق',
                      value: _formatDate(_verificationDate),
                      iconColor: Colors.blue,
                    ),

                    const SizedBox(height: 20),
                  ],

                  // نوع الحساب
                  _buildInfoRow(
                    icon: Icons.person_outline,
                    title: 'نوع الحساب',
                    value: widget.isVerified ? 'Verified Account' : 'Regular Account',
                    iconColor: Colors.black,
                  ),
                ],
              ),
            ),

            // خط فاصل
            Container(
              height: 1,
              color: Colors.grey[300],
            ),


            // ملاحظة في الأسفل
            Container(
              padding: const EdgeInsets.all(20),
              child: widget.isVerified
                  ? RichText(
                      text: TextSpan(
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(text: 'This account has been verified because it represents a prominent personality, a well-known brand, or provides original and ethical content that does not violate community standards. This account has been verified by '),
                          TextSpan(
                            text: 'Reno Inc',
                            style: TextStyle(color: Colors.blue),
                          ),
                          TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    )
                  : Column(
                      children: [
                        Text(
                          'This account is not verified yet.',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.grey[600],
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Prominent and active accounts can apply for verification.',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: Colors.grey[500],
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            color: Colors.black,
            size: 22,
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
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}