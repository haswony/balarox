import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/doctor.dart';
import '../services/doctor_service.dart';
import '../services/storage_service.dart';

class AddDoctorPage extends StatefulWidget {
  const AddDoctorPage({super.key});

  @override
  State<AddDoctorPage> createState() => _AddDoctorPageState();
}

class _AddDoctorPageState extends State<AddDoctorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _locationController = TextEditingController();
  
  String _openTime = '08:00';
  String _closeTime = '18:00';
  bool _isLoading = false;
  File? _selectedImage;
  File? _clinicSelectedImage;
  File? _certificateSelectedImage;
  final ImagePicker _picker = ImagePicker();

  final List<String> _timeSlots = [
    '06:00', '06:30', '07:00', '07:30', '08:00', '08:30',
    '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '12:00', '12:30', '13:00', '13:30', '14:00', '14:30',
    '15:00', '15:30', '16:00', '16:30', '17:00', '17:30',
    '18:00', '18:30', '19:00', '19:30', '20:00', '20:30',
    '21:00', '21:30', '22:00'
  ];

  final List<String> _specialties = [
    'طب عام',
    'أطفال',
    'نساء وولادة',
    'قلبية',
    'عظام',
    'عيون',
    'أنف وأذن وحنجرة',
    'جلدية',
    'أسنان',
    'نفسية',
    'جراحة عامة',
    'مختبر',
    'أشعة',
    'أخرى'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _specialtyController.dispose();
    _locationController.dispose();
    super.dispose();
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

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _pickClinicImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _clinicSelectedImage = File(image.path);
      });
    }
  }

  Future<void> _pickCertificateImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() {
        _certificateSelectedImage = File(image.path);
      });
    }
  }

  Future<void> _addDoctor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('يجب تسجيل الدخول أولاً', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Check if user can add a new clinic
      final canAdd = await DoctorService.canUserAddDoctor();
      if (!canAdd) {
        final status = await DoctorService.getExistingRequestStatus();
        String message;
        if (status == 'approved') {
          message = 'لديك بالفعل عيادة معتمدة. لا يمكنك إضافة عيادة جديدة.';
        } else if (status == 'pending') {
          message = 'لديك بالفعل طلب مراجعة معلق. لا يمكنك إضافة عيادة جديدة.';
        } else if (status == 'rejected') {
          message = 'لديك طلب بالفعل والمشرف رفضه. لا يمكنك إضافة طلب جديد.';
        } else {
          message = 'لديك بالفعل طلب مراجعة أو عيادة معتمدة. لا يمكنك إضافة عيادة جديدة.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // رفع صورة الطبيب
      String imageUrl = '';
      if (_selectedImage != null) {
        final uploadedImageUrl = await StorageService.uploadDoctorImage(_selectedImage!);
        if (uploadedImageUrl != null) {
          imageUrl = uploadedImageUrl;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل في رفع صورة الطبيب', style: GoogleFonts.cairo()),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      // رفع صورة العيادة
      String clinicImageUrl = '';
      if (_clinicSelectedImage != null) {
        final uploadedClinicUrl = await StorageService.uploadDoctorImage(_clinicSelectedImage!);
        if (uploadedClinicUrl != null) {
          clinicImageUrl = uploadedClinicUrl;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل في رفع صورة العيادة', style: GoogleFonts.cairo()),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('يرجى اختيار صورة للعيادة', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // رفع صورة الشهادة الطبية
      String certificateImageUrl = '';
      if (_certificateSelectedImage != null) {
        final uploadedCertificateUrl = await StorageService.uploadDoctorImage(_certificateSelectedImage!);
        if (uploadedCertificateUrl != null) {
          certificateImageUrl = uploadedCertificateUrl;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل في رفع صورة الشهادة الطبية', style: GoogleFonts.cairo()),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('يرجى اختيار صورة الشهادة الطبية لإثبات التأهيل', style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final doctor = Doctor(
        id: '',
        name: _nameController.text.trim(),
        specialty: _specialtyController.text.trim(),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        imageUrl: imageUrl,
        clinicImageUrl: clinicImageUrl,
        certificateImageUrl: certificateImageUrl,
        openTime: _openTime,
        closeTime: _closeTime,
        isActive: true,
        createdAt: DateTime.now(),
        userId: currentUser.uid,
      );

      final success = await DoctorService.addDoctor(doctor);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال طلب إضافة العيادة للمراجعة. سيتم مراجعته من قبل المشرفين قريباً.', style: GoogleFonts.cairo()),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        final status = await DoctorService.getExistingRequestStatus();
        String message;
        if (status == 'approved') {
          message = 'لديك بالفعل عيادة معتمدة. لا يمكنك إضافة عيادة جديدة.';
        } else if (status == 'pending') {
          message = 'لديك بالفعل طلب مراجعة معلق. لا يمكنك إضافة عيادة جديدة.';
        } else if (status == 'rejected') {
          message = 'لديك طلب بالفعل والمشرف رفضه. لا يمكنك إضافة طلب جديد.';
        } else {
          message = 'حدث خطأ أثناء إرسال طلب إضافة العيادة.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message, style: GoogleFonts.cairo()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('خطأ في إضافة العيادة: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء إضافة العيادة', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'إضافة طبيب جديد',
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
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // صورة الطبيب
              Center(
                child: Column(
                  children: [
                    Text(
                      'صورة الطبيب *',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey[300]!, width: 2),
                        ),
                        child: _selectedImage != null
                            ? ClipOval(
                                child: Image.file(
                                  _selectedImage!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                Icons.add_a_photo,
                                size: 35,
                                color: Colors.grey[600],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 30),
              
              // اسم الطبيب
              Text(
                'الاسم الكامل *',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'أدخل اسم الطبيب',
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
                    return 'يرجى إدخال اسم الطبيب';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 20),
              
              // التخصص
              Text(
                'التخصص *',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _specialtyController.text.isEmpty ? null : _specialtyController.text,
                decoration: InputDecoration(
                  hintText: 'اختر التخصص',
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
                items: _specialties.map((specialty) {
                  return DropdownMenuItem(
                    value: specialty,
                    child: Text(specialty, style: GoogleFonts.cairo(fontSize: 15)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    _specialtyController.text = value;
                  }
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى اختيار التخصص';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 20),
              
              // الموقع
              Text(
                'الموقع (اختياري)',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  hintText: 'أدخل عنوان العيادة',
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
              ),
              
              const SizedBox(height: 30),
              
              // أوقات العمل
              Text(
                'أوقات العمل',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 15),
              
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'من',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _openTime,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.black, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          items: _timeSlots.map((time) {
                            return DropdownMenuItem(
                              value: time,
                              child: Text(
                                _convertTo12Hour(time),
                                style: GoogleFonts.cairo(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _openTime = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إلى',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _closeTime,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.black, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          items: _timeSlots.map((time) {
                            return DropdownMenuItem(
                              value: time,
                              child: Text(
                                _convertTo12Hour(time),
                                style: GoogleFonts.cairo(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _closeTime = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 30),
              
              // صورة العيادة
              Center(
                child: Column(
                  children: [
                    Text(
                      'صورة العيادة *',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickClinicImage,
                      child: Container(
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!, width: 2),
                          color: Colors.grey[50],
                        ),
                        child: _clinicSelectedImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _clinicSelectedImage!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_photo_alternate,
                                    size: 50,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'اضغط لإضافة صورة العيادة',
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // صورة الشهادة الطبية
              Center(
                child: Column(
                  children: [
                    Text(
                      'صورة الشهادة الطبية *',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'يجب تقديم صورة الشهادة الطبية لإثبات التأهيل',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _pickCertificateImage,
                      child: Container(
                        width: double.infinity,
                        height: 150,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!, width: 2),
                          color: Colors.grey[50],
                        ),
                        child: _certificateSelectedImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _certificateSelectedImage!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.assignment,
                                    size: 50,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'اضغط لإضافة صورة الشهادة الطبية',
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // زر الإضافة
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : () {
                    if (_selectedImage == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('يرجى اختيار صورة للطبيب', style: GoogleFonts.cairo()),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    if (_clinicSelectedImage == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('يرجى اختيار صورة للعيادة', style: GoogleFonts.cairo()),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    if (_certificateSelectedImage == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('يرجى اختيار صورة الشهادة الطبية لإثبات التأهيل', style: GoogleFonts.cairo()),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    _addDoctor();
                  },
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
                          'إضافة العيادة',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
