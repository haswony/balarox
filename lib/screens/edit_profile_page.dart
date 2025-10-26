import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../services/database_service.dart';
import '../services/profile_update_service.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EditProfilePage({super.key, required this.userData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _handleController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  bool _isLoading = false;
  bool _isCheckingHandle = false;
  String? _handleError;

  @override
  void initState() {
    super.initState();
    _displayNameController.text = widget.userData['displayName'] ?? '';
    _handleController.text = widget.userData['handle'] ?? '';
    _bioController.text = widget.userData['bio'] ?? '';
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _handleController.dispose();
    _bioController.dispose();
    super.dispose();
  }



  bool _isValidHandle(String handle) {
    final RegExp handleRegex = RegExp(r'^[a-z0-9_]+$');
    return handleRegex.hasMatch(handle) && handle.isNotEmpty;
  }

  Future<void> _checkHandleAvailability(String handle) async {
    if (handle.isEmpty || !_isValidHandle(handle)) {
      setState(() {
        _handleError = null;
        _isCheckingHandle = false;
      });
      return;
    }

    setState(() {
      _isCheckingHandle = true;
      _handleError = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final isAvailable = await DatabaseService.isHandleAvailable(
        handle.toLowerCase(),
        currentUserId: currentUser?.uid,
      );

      if (mounted) {
        setState(() {
          _handleError = isAvailable ? null : 'اسم المستخدم مستخدم بالفعل';
          _isCheckingHandle = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _handleError = 'خطأ في التحقق من توفر اسم المستخدم';
          _isCheckingHandle = false;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_isLoading || _isCheckingHandle) return;

    final displayName = _displayNameController.text.trim();
    final handle = _handleController.text.trim();

    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'يرجى إدخال الاسم',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      return;
    }

    if (handle.isEmpty || !_isValidHandle(handle)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'اسم المستخدم يجب أن يحتوي على أحرف إنجليزية وأرقام وشرطة سفلية فقط',
            style: GoogleFonts.cairo(),
          ),
        ),
      );
      return;
    }

    if (_handleError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _handleError!,
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // فحص نهائي لتوفر الـ handle قبل الحفظ
      final isAvailable = await DatabaseService.isHandleAvailable(
        handle.toLowerCase(),
        currentUserId: currentUser.uid,
      );

      if (!isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'اسم المستخدم مستخدم بالفعل',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // تحديث البيانات في Firestore
      await DatabaseService.updateUserInFirestore(
        userId: currentUser.uid,
        data: {
          'displayName': displayName,
          'handle': handle.toLowerCase(),
          'bio': _bioController.text.trim(),
        },
      );

      // إرسال إشعار بتحديث الاسم
      ProfileUpdateService().notifyDisplayNameUpdate(currentUser.uid);

      if (mounted) {
        Navigator.pop(context, true); // إرجاع true للإشارة إلى نجاح التحديث
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديث الملف الشخصي بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('خطأ في حفظ التغييرات: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ في حفظ التغييرات',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
          'تعديل الملف الشخصي',
          style: GoogleFonts.cairo(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveChanges,
            child: _isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.blue,
              ),
            )
                : Text(
              'حفظ',
              style: GoogleFonts.cairo(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // حقل الاسم
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: 'الاسم',
                labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
                hintText: 'أدخل اسمك',
                hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),

            const SizedBox(height: 16),

            // حقل اسم المستخدم
            TextField(
              controller: _handleController,
              onChanged: (value) {
                // تأخير التحقق لتجنب الاستعلامات المتكررة
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_handleController.text == value) {
                    _checkHandleAvailability(value);
                  }
                });
              },
              decoration: InputDecoration(
                labelText: 'اسم المستخدم',
                labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
                hintText: 'username',
                hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                prefixText: '@',
                prefixStyle: GoogleFonts.cairo(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
                suffixIcon: _isCheckingHandle
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : _handleError == null && _handleController.text.isNotEmpty && _isValidHandle(_handleController.text)
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : _handleError != null
                    ? const Icon(Icons.error, color: Colors.red)
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _handleError != null ? Colors.red : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _handleError != null ? Colors.red : Colors.blue,
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 16),

            // حقل السيرة الذاتية
            TextField(
              controller: _bioController,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: 'السيرة الذاتية',
                labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
                hintText: 'اكتب شيئاً عن نفسك...',
                hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.blue, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),

            const SizedBox(height: 40),

            // معلومات إضافية
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'معلومات الحساب',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'رقم الهاتف: ',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        widget.userData['phoneNumber'] ?? 'غير محدد',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
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
}