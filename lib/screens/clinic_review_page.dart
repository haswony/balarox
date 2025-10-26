import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/doctor.dart';
import '../services/doctor_service.dart';
import '../services/database_service.dart';

class ClinicReviewPage extends StatefulWidget {
  const ClinicReviewPage({super.key});

  @override
  State<ClinicReviewPage> createState() => _ClinicReviewPageState();
}

class _ClinicReviewPageState extends State<ClinicReviewPage> {
  List<Doctor> _pendingDoctors = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      Navigator.pop(context);
      return;
    }

    // التحقق من صلاحيات المشرف
    final isAdmin = await DatabaseService.isAdmin(currentUser.uid);
    if (!isAdmin) {
      Navigator.pop(context);
      return;
    }

    setState(() {
      _isAdmin = true;
    });

    _loadPendingDoctors();
  }

  Future<void> _loadPendingDoctors() async {
    try {
      final doctors = await DoctorService.getPendingDoctors();
      setState(() {
        _pendingDoctors = doctors;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('خطأ في تحميل طلبات المراجعة: $e');
    }
  }

  Future<void> _approveDoctor(String doctorId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      await DoctorService.approveDoctor(doctorId, currentUser.uid);

      _showSuccessSnackBar('تم قبول العيادة ونشرها');
      _loadPendingDoctors(); // إعادة تحميل القائمة
    } catch (e) {
      _showErrorSnackBar('خطأ في قبول العيادة: $e');
    }
  }

  Future<void> _rejectDoctor(String doctorId) async {
    final reasonController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'رفض العيادة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'يرجى كتابة سبب الرفض:',
              style: GoogleFonts.cairo(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: 'سبب الرفض...',
                hintStyle: GoogleFonts.cairo(),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, reasonController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('رفض', style: GoogleFonts.cairo(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final currentUser = FirebaseAuth.instance.currentUser!;
        await DoctorService.rejectDoctor(doctorId, currentUser.uid, result);

        _showSuccessSnackBar('تم رفض العيادة');
        _loadPendingDoctors(); // إعادة تحميل القائمة
      } catch (e) {
        _showErrorSnackBar('خطأ في رفض العيادة: $e');
      }
    }
  }

  void _showDoctorDetails(Doctor doctor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'تفاصيل العيادة',
                      style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // صورة الطبيب
                      if (doctor.imageUrl.isNotEmpty) ...[
                        Center(
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              image: DecorationImage(
                                image: NetworkImage(doctor.imageUrl),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // اسم الطبيب
                      Text(
                        doctor.name,
                        style: GoogleFonts.cairo(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // التخصص
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          doctor.specialty,
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.blue[800],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // الموقع
                      if (doctor.location != null && doctor.location!.isNotEmpty) ...[
                        Text(
                          'الموقع',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          doctor.location!,
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // أوقات العمل
                      Text(
                        'أوقات العمل',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'من ${doctor.openTime} إلى ${doctor.closeTime}',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // صورة العيادة
                      if (doctor.clinicImageUrl != null && doctor.clinicImageUrl!.isNotEmpty) ...[
                        Text(
                          'صورة العيادة',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            image: DecorationImage(
                              image: NetworkImage(doctor.clinicImageUrl!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // صورة الشهادة الطبية
                      if (doctor.certificateImageUrl != null && doctor.certificateImageUrl!.isNotEmpty) ...[
                        Text(
                          'صورة الشهادة الطبية',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[200]!, width: 2),
                            image: DecorationImage(
                              image: NetworkImage(doctor.certificateImageUrl!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'يجب التحقق من صحة الشهادة الطبية قبل الموافقة',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: Colors.orange[600],
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                      ],

                      // أزرار الإجراءات
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _approveDoctor(doctor.id);
                              },
                              icon: const Icon(Icons.check, color: Colors.white),
                              label: Text(
                                'قبول العيادة',
                                style: GoogleFonts.cairo(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _rejectDoctor(doctor.id);
                              },
                              icon: const Icon(Icons.close, color: Colors.white),
                              label: Text(
                                'رفض العيادة',
                                style: GoogleFonts.cairo(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'طلبات مراجعة العيادات',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingDoctors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد طلبات مراجعة للعيادات',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPendingDoctors,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingDoctors.length,
                    itemBuilder: (context, index) {
                      final doctor = _pendingDoctors[index];
                      return _buildDoctorCard(doctor);
                    },
                  ),
                ),
    );
  }

  Widget _buildDoctorCard(Doctor doctor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showDoctorDetails(doctor),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // صورة الطبيب
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[200],
                ),
                child: doctor.imageUrl.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          doctor.imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.person,
                              color: Colors.grey[400],
                              size: 30,
                            );
                          },
                        ),
                      )
                    : Icon(
                        Icons.person,
                        color: Colors.grey[400],
                        size: 30,
                      ),
              ),
              const SizedBox(width: 16),

              // تفاصيل الطبيب
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اسم الطبيب
                    Text(
                      doctor.name,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // التخصص
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Text(
                        doctor.specialty,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // أوقات العمل
                    Text(
                      'من ${doctor.openTime} إلى ${doctor.closeTime}',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),

              // أزرار الإجراءات
              Column(
                children: [
                  // زر التفاصيل
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => _showDoctorDetails(doctor),
                      icon: Icon(
                        Icons.visibility,
                        size: 18,
                        color: Colors.blue[600],
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // زر الموافقة
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => _approveDoctor(doctor.id),
                      icon: Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.green[600],
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // زر الرفض
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => _rejectDoctor(doctor.id),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.red[600],
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
