import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/doctor.dart';
import '../models/booking.dart';
import '../services/doctor_service.dart';
import '../widgets/shimmer_widget.dart';
import 'add_doctor_page.dart';
import 'edit_doctor_page.dart';

class DoctorDashboardPage extends StatefulWidget {
  const DoctorDashboardPage({super.key});

  @override
  State<DoctorDashboardPage> createState() => _DoctorDashboardPageState();
}

class _DoctorDashboardPageState extends State<DoctorDashboardPage> 
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Doctor> _myDoctors = [];
  List<Booking> _allBookings = [];
  List<Booking> _pendingBookings = [];
  List<Booking> _approvedBookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // جلب الأطباء التابعين للمستخدم الحالي
      final doctors = await DoctorService.getCurrentUserDoctors();
      
      // جلب جميع الحجوزات للأطباء التابعين للمستخدم
      final bookings = await DoctorService.getCurrentUserDoctorBookings();

      if (mounted) {
        setState(() {
          _myDoctors = doctors;
          _allBookings = bookings;
          
          // تصنيف الحجوزات
          _pendingBookings = bookings.where((b) => b.status == BookingStatus.pending).toList();
          _approvedBookings = bookings.where((b) => b.status == BookingStatus.approved).toList();
          
          // ترتيب الحجوزات بحسب التاريخ
          _pendingBookings.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
          _approvedBookings.sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
          
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل بيانات لوحة التحكم: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshData() async {
    await _loadDashboardData();
  }

  String _convertTo12Hour(String time24) {
    final parts = time24.split(':');
    int hour = int.parse(parts[0]);
    final minute = parts[1];
    
    if (hour == 0) {
      return '12:$minute صباحاً';
    } else if (hour < 12) {
      return '$hour:$minute صباحاً';
    } else if (hour == 12) {
      return '12:$minute ظهراً';
    } else {
      return '${hour - 12}:$minute مساءً';
    }
  }

  String _getArabicDate(DateTime date) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    
    final days = [
      'الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'
    ];
    
    return '${days[date.weekday % 7]}, ${date.day} ${months[date.month - 1]}';
  }

  Future<void> _updateBookingStatus(Booking booking, BookingStatus newStatus) async {
    try {
      final success = await DoctorService.updateBookingStatus(booking.id, newStatus);

      if (success) {
        // تحديث الحالة محلياً
        setState(() {
          final index = _allBookings.indexWhere((b) => b.id == booking.id);
          if (index != -1) {
            _allBookings[index] = booking.copyWith(
              status: newStatus,
              updatedAt: DateTime.now(),
            );
          }

          // إعادة تصنيف الحجوزات
          _pendingBookings = _allBookings.where((b) => b.status == BookingStatus.pending).toList();
          _approvedBookings = _allBookings.where((b) => b.status == BookingStatus.approved).toList();
        });

        String message;
        Color backgroundColor;

        switch (newStatus) {
          case BookingStatus.approved:
            message = 'تم قبول الحجز بنجاح';
            backgroundColor = Colors.green;
            break;
          case BookingStatus.rejected:
            message = 'تم رفض الحجز';
            backgroundColor = Colors.red;
            break;
          case BookingStatus.completed:
            message = 'تم إكمال الموعد بنجاح';
            backgroundColor = Colors.blue;
            break;
          case BookingStatus.cancelled:
            message = 'تم إلغاء الحجز';
            backgroundColor = Colors.grey;
            break;
          default:
            message = 'تم تحديث حالة الحجز';
            backgroundColor = Colors.blue;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: backgroundColor,
          ),
        );
      }
    } catch (e) {
      print('خطأ في تحديث حالة الحجز: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء تحديث الحجز',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteClinic(Doctor doctor) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'تأكيد الحذف النهائي',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'هل أنت متأكد من حذف عيادة "${doctor.name}" نهائياً؟\n\nسيتم حذف جميع بيانات العيادة والحجوزات المتعلقة بها من قاعدة البيانات ولن يمكن استعادتها.',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(
                  color: Colors.grey[600],
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: Text(
                'حذف نهائياً',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        // Show loading dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text(
                    'جاري حذف العيادة نهائياً...',
                    style: GoogleFonts.cairo(),
                  ),
                ],
              ),
            );
          },
        );

        // Delete the clinic permanently
        final success = await DoctorService.permanentlyDeleteDoctor(doctor.id);

        // Close loading dialog
        Navigator.of(context).pop();

        if (success) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم حذف العيادة نهائياً بنجاح',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Refresh the dashboard data
          await _loadDashboardData();
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'فشل في حذف العيادة. حاول مرة أخرى.',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        // Close loading dialog if still open
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء الحذف. حاول مرة أخرى.',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'لوحة تحكم الطبيب',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.blue,
          indicatorWeight: 3,
          labelStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          unselectedLabelStyle: GoogleFonts.cairo(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          tabs: [
            Tab(
              text: 'معلقة (${_pendingBookings.length})',
            ),
            Tab(
              text: 'مقبولة (${_approvedBookings.length})',
            ),
            Tab(
              text: 'الإحصائيات',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? _buildLoadingView()
          : _myDoctors.isEmpty
              ? _buildNoDoctorsView()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPendingBookings(),
                    _buildApprovedBookings(),
                    _buildStatistics(),
                  ],
                ),
      floatingActionButton: _myDoctors.isEmpty ? FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddDoctorPage(),
            ),
          );
          if (result == true) {
            _loadDashboardData(); // تحديث البيانات بعد إضافة طبيب جديد
          }
        },
        backgroundColor: Colors.blue,
        child: const Icon(
          Icons.add,
          color: Colors.white,
        ),
      ) : null,
    );
  }

  Widget _buildLoadingView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: const BookingCardShimmer(),
        );
      },
    );
  }

  Widget _buildNoDoctorsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_hospital_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد عيادات مسجلة',
            style: GoogleFonts.cairo(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'يجب إضافة عيادة أولاً لاستقبال الحجوزات',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingBookings() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: _pendingBookings.isEmpty
          ? _buildEmptyBookings('لا توجد حجوزات معلقة', 'الحجوزات المعلقة ستظهر هنا')
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _pendingBookings.length,
              itemBuilder: (context, index) {
                final booking = _pendingBookings[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: _buildPendingBookingCard(booking),
                );
              },
            ),
    );
  }

  Widget _buildApprovedBookings() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: _approvedBookings.isEmpty
          ? _buildEmptyBookings('لا توجد حجوزات مقبولة', 'الحجوزات المقبولة ستظهر هنا')
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _approvedBookings.length,
              itemBuilder: (context, index) {
                final booking = _approvedBookings[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: _buildApprovedBookingCard(booking),
                );
              },
            ),
    );
  }

  Widget _buildStatistics() {
    final totalBookings = _allBookings.length;
    final pendingCount = _pendingBookings.length;
    final approvedCount = _approvedBookings.length;
    final rejectedCount = _allBookings.where((b) => b.status == BookingStatus.rejected).length;
    final completedCount = _allBookings.where((b) => b.status == BookingStatus.completed).length;

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // إجمالي الإحصائيات
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'إجمالي الحجوزات',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$totalBookings',
                    style: GoogleFonts.cairo(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // تفاصيل الإحصائيات
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildStatItem('معلقة', pendingCount, Colors.orange, Icons.pending_actions),
                _buildStatItem('مقبولة', approvedCount, Colors.green, Icons.check_circle),
                _buildStatItem('مرفوضة', rejectedCount, Colors.red, Icons.cancel),
                _buildStatItem('مكتملة', completedCount, Colors.blue, Icons.done_all),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // معلومات الأطباء
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'عياداتي (${_myDoctors.length})',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 15),
                  ..._myDoctors.map((doctor) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'د. ${doctor.name}',
                                    style: GoogleFonts.cairo(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    doctor.specialty,
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  color: Colors.black,
                                  onPressed: () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => EditDoctorPage(doctor: doctor),
                                      ),
                                    );
                                    if (result == true) {
                                      _loadDashboardData();
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18),
                                  color: Colors.red,
                                  onPressed: () => _deleteClinic(doctor),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 16, color: Colors.blue[600]),
                            const SizedBox(width: 6),
                            Text(
                              'من ${_convertTo12Hour(doctor.openTime)} إلى ${_convertTo12Hour(doctor.closeTime)}',
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (doctor.location != null && doctor.location!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 16, color: Colors.red[600]),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  doctor.location!,
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: GoogleFonts.cairo(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyBookings(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingBookingCard(Booking booking) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // معلومات المريض
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.patientName,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          booking.patientPhone,
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'جديد',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[700],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // تفاصيل الموعد
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                           size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 6),
                      Text(
                        '${booking.appointmentDate.day}/${booking.appointmentDate.month}/${booking.appointmentDate.year}',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.access_time,
                           size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 6),
                      Text(
                        _convertTo12Hour(booking.appointmentTime),
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // الملاحظات
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.note, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      booking.notes!,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // أزرار القرار
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _updateBookingStatus(booking, BookingStatus.rejected),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'رفض',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _updateBookingStatus(booking, BookingStatus.approved),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'قبول',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedBookingCard(Booking booking) {
    final isFuture = booking.isFuture();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // معلومات المريض
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.patientName,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          booking.patientPhone,
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isFuture ? Colors.green[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isFuture ? 'قادم' : 'انتهى',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isFuture ? Colors.green[700] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // تفاصيل الموعد
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                           size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 6),
                      Text(
                        '${booking.appointmentDate.day}/${booking.appointmentDate.month}/${booking.appointmentDate.year}',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.access_time,
                           size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 6),
                      Text(
                        _convertTo12Hour(booking.appointmentTime),
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // الملاحظات
          if (booking.notes != null && booking.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.note, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      booking.notes!,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // زر إكمال للمواعيد المستقبلية
          if (isFuture) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _updateBookingStatus(booking, BookingStatus.completed),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  'تم إكمال الموعد',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Widget for Booking Card Shimmer Loading
class BookingCardShimmer extends StatelessWidget {
  const BookingCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ShimmerWidget(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 150,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 60,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
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
}