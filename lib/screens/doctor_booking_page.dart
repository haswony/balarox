import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/doctor.dart';
import '../models/booking.dart';
import '../services/doctor_service.dart';

class DoctorBookingPage extends StatefulWidget {
  final Doctor doctor;

  const DoctorBookingPage({super.key, required this.doctor});

  @override
  State<DoctorBookingPage> createState() => _DoctorBookingPageState();
}

class _DoctorBookingPageState extends State<DoctorBookingPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _selectedDate;
  String? _selectedTime;
  List<String> _availableTimeSlots = [];
  bool _isLoading = false;
  Doctor? _currentDoctor;

  @override
  void initState() {
    super.initState();
    _currentDoctor = widget.doctor;
    _generateTimeSlots();
    _setTomorrowAsMinDate();
    _loadUserData();
    _loadLatestDoctorData();
  }

  Future<void> _loadLatestDoctorData() async {
    try {
      final latestDoctor = await DoctorService.getDoctorById(widget.doctor.id);
      if (latestDoctor != null && mounted) {
        setState(() {
          _currentDoctor = latestDoctor;
        });
        _generateTimeSlots();
      }
    } catch (e) {
      print('خطأ في تحميل بيانات الطبيب: $e');
    }
  }

  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      setState(() {
        _phoneController.text = currentUser.phoneNumber ?? '';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _setTomorrowAsMinDate() {
    setState(() {
      _selectedDate = DateTime.now().add(const Duration(days: 1));
    });
    _checkAvailableSlots();
  }

  void _generateTimeSlots() {
    if (_currentDoctor != null) {
      _availableTimeSlots = DoctorService.generateAvailableTimeSlots(
        _currentDoctor!.openTime,
        _currentDoctor!.closeTime,
        intervalMinutes: 30,
      );
    }
  }

  Future<void> _checkAvailableSlots() async {
    if (_selectedDate == null) return;
    setState(() {});
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
    
    return '${days[date.weekday % 7]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedTime = null;
      });
      _checkAvailableSlots();
    }
  }

  Future<void> _confirmBooking() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى اختيار التاريخ والوقت', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      
      final isAvailable = await DoctorService.isTimeSlotAvailable(
        _currentDoctor!.id,
        _selectedDate!,
        _selectedTime!,
      );

      if (!isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('هذا الموعد غير متاح، يرجى اختيار موعد آخر', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      final booking = Booking(
        id: '',
        doctorId: _currentDoctor!.id,
        doctorName: _currentDoctor!.name,
        patientName: _nameController.text.trim(),
        patientPhone: _phoneController.text.trim(),
        patientUserId: currentUser?.uid,
        appointmentDate: _selectedDate!,
        appointmentTime: _selectedTime!,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        status: BookingStatus.pending,
        createdAt: DateTime.now(),
      );

      final bookingId = await DoctorService.createBooking(booking);

      if (bookingId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال طلب الحجز بنجاح ✓', style: GoogleFonts.cairo()),
            backgroundColor: Colors.green,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء إرسال الحجز', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('خطأ في تأكيد الحجز: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء إرسال الحجز', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'حجز موعد',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDoctorHeader(),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateSection(),
                  const SizedBox(height: 30),
                  _buildTimeSection(),
                  const SizedBox(height: 30),
                  _buildPatientForm(),
                  const SizedBox(height: 30),
                  _buildConfirmButton(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoctorHeader() {
    if (_currentDoctor == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // صورة الطبيب الدائرية
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[300]!, width: 2),
              ),
              child: ClipOval(
                child: _currentDoctor!.imageUrl.isNotEmpty
                    ? Image.network(
                        _currentDoctor!.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.grey[400],
                        ),
                      )
                    : Icon(
                        Icons.person,
                        size: 60,
                        color: Colors.grey[400],
                      ),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // معلومات الطبيب
          Column(
            children: [
              Text(
                'د. ${_currentDoctor!.name}',
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _currentDoctor!.specialty,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // الموقع
              if (_currentDoctor!.location != null && _currentDoctor!.location!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_on, size: 16, color: Colors.red[600]),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _currentDoctor!.location!,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              
              // ساعات العمل - تحديث فوري
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.blue[600]),
                  const SizedBox(width: 6),
                  Text(
                    'من ${_convertTo12Hour(_currentDoctor!.openTime)} إلى ${_convertTo12Hour(_currentDoctor!.closeTime)}',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        
          // صورة العيادة
          if (_currentDoctor!.clinicImageUrl?.isNotEmpty ?? false) ...[
            const SizedBox(height: 20),
            Text(
              'العيادة',
              style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _currentDoctor!.clinicImageUrl!,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 150,
                  color: Colors.grey[200],
                  child: Center(
                    child: Icon(
                      Icons.local_hospital,
                      size: 50,
                      color: Colors.grey[400],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اختر التاريخ',
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _selectDate,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.blue[600], size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedDate != null
                        ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                        : 'اضغط لاختيار التاريخ',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: _selectedDate != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSection() {
    if (_selectedDate == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اختر الوقت',
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        _availableTimeSlots.isEmpty
            ? Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'لا توجد مواعيد متاحة في هذا التاريخ',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              )
            : Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _availableTimeSlots.map((time) {
                  final isSelected = _selectedTime == time;
                  final arabicTime = _convertTo12Hour(time);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedTime = time;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.black : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        arabicTime,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildPatientForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'بيانات المريض',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          
          // الاسم
          TextFormField(
            controller: _nameController,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'الاسم الكامل',
              labelStyle: GoogleFonts.cairo(color: Colors.grey[700]),
              hintText: 'أدخل اسمك الكامل',
              hintStyle: GoogleFonts.cairo(color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.black, width: 2),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
            style: GoogleFonts.cairo(fontSize: 15),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'يرجى إدخال الاسم';
              }
              return null;
            },
          ),
          
          const SizedBox(height: 16),
          
          // رقم الهاتف
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.phone, size: 20, color: Colors.black),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _phoneController.text.isNotEmpty
                        ? _phoneController.text
                        : 'رقم الهاتف',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // الملاحظات
          TextFormField(
            controller: _notesController,
            textAlign: TextAlign.right,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'ملاحظات (اختياري)',
              labelStyle: GoogleFonts.cairo(color: Colors.grey[700]),
              hintText: 'أضف أي ملاحظات...',
              hintStyle: GoogleFonts.cairo(color: Colors.grey[400]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.black, width: 2),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
            style: GoogleFonts.cairo(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _confirmBooking,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'تأكيد الحجز',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}