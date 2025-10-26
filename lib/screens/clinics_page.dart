import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/doctor.dart';
import '../services/doctor_service.dart';
import 'doctor_booking_page.dart';
import '../widgets/shimmer_widget.dart';

class ClinicsPage extends StatefulWidget {
  const ClinicsPage({super.key});

  @override
  State<ClinicsPage> createState() => _ClinicsPageState();
}

class _ClinicsPageState extends State<ClinicsPage> {
  List<Doctor> _doctors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDoctors();
  }

  Future<void> _loadDoctors() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final doctors = await DoctorService.getActiveDoctors();
      if (mounted) {
        setState(() {
          _doctors = doctors;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل الأطباء: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshDoctors() async {
    await _loadDoctors();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _refreshDoctors,
        child: _isLoading
            ? _buildLoadingView()
            : _doctors.isEmpty
                ? _buildEmptyView()
                : _buildDoctorsList(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      itemBuilder: (context, index) {
        return const ClinicCardShimmer();
      },
    );
  }

  Widget _buildEmptyView() {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(
                Icons.local_hospital_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد عيادات متاحة حالياً',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'سيتم عرض العيادات المتاحة هنا',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDoctorsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _doctors.length,
      itemBuilder: (context, index) {
        final doctor = _doctors[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          child: _buildDoctorItem(doctor),
        );
      },
    );
  }

  Widget _buildDoctorItem(Doctor doctor) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DoctorBookingPage(doctor: doctor),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صورة الطبيب مربعة
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey[100],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: doctor.imageUrl.isNotEmpty
                    ? Image.network(
                        doctor.imageUrl,
                        fit: BoxFit.cover,
                        width: 120,
                        height: 120,
                      )
                    : Icon(
                        Icons.local_hospital,
                        size: 40,
                        color: Colors.grey[400],
                      ),
              ),
            ),

            const SizedBox(width: 16),

            // معلومات الطبيب بجانب الصورة
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
                  ),

                  const SizedBox(height: 4),

                  // التخصص
                  Text(
                    doctor.specialty,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: Colors.blue[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // الموقع
                  if (doctor.location != null && doctor.location!.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            doctor.location!,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 8),

                  // أوقات العمل
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_convertTo12Hour(doctor.openTime)} - ${_convertTo12Hour(doctor.closeTime)}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _convertTo12Hour(String time24) {
    final parts = time24.split(':');
    int hour = int.parse(parts[0]);
    final minute = parts[1];
    
    if (hour == 0) {
      return '12:$minute ص';
    } else if (hour < 12) {
      return '$hour:$minute ص';
    } else if (hour == 12) {
      return '12:$minute ظ';
    } else {
      return '${hour - 12}:$minute م';
    }
  }
  
}