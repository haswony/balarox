import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Add this import for kIsWeb
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';

class VerificationRequestPage extends StatefulWidget {
  const VerificationRequestPage({super.key});

  @override
  State<VerificationRequestPage> createState() => _VerificationRequestPageState();
}

class _VerificationRequestPageState extends State<VerificationRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _reasonController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final PageController _pageController = PageController();

  File? _idImage;
  Uint8List? _idImageBytes; // For web compatibility
  File? _additionalImage;
  Uint8List? _additionalImageBytes; // For web compatibility
  bool _isLoading = false;
  bool _hasExistingRequest = false;
  bool _isAlreadyVerified = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _checkExistingRequest();
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page?.round() ?? 0;
      });
    });
    _reasonController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingRequest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // فحص إذا كان المستخدم موثق بالفعل
      final userData = await DatabaseService.getUserFromFirestore(user.uid);
      if (userData?['isVerified'] == true) {
        if (mounted) {
          setState(() {
            _hasExistingRequest = true;
            _isAlreadyVerified = true;
          });
        }
        return;
      }

      // فحص الطلبات المعلقة
      final existingRequest = await FirebaseFirestore.instance
          .collection('verification_requests')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (mounted) {
        setState(() {
          _hasExistingRequest = existingRequest.docs.isNotEmpty;
          _isAlreadyVerified = false;
        });
      }
    } catch (e) {
      print('خطأ في التحقق من الطلبات الموجودة: $e');
    }
  }

  Future<void> _pickIdImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 95,
      );

      if (image != null) {
        setState(() {
          _idImage = File(image.path);
          _idImageBytes = null; // Reset bytes
          // For web compatibility, we also store the bytes
          image.readAsBytes().then((bytes) {
            setState(() {
              _idImageBytes = bytes;
            });
          });
        });
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في اختيار الصورة: $e');
    }
  }

  Future<void> _pickAdditionalImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 95,
      );

      if (image != null) {
        setState(() {
          _additionalImage = File(image.path);
          _additionalImageBytes = null; // Reset bytes
          // For web compatibility, we also store the bytes
          image.readAsBytes().then((bytes) {
            setState(() {
              _additionalImageBytes = bytes;
            });
          });
        });
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في اختيار الصورة: $e');
    }
  }

  Future<String> _uploadIdImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');
    if (_idImage == null) throw Exception('لم يتم اختيار صورة الهوية');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('verification_ids')
        .child(user.uid)
        .child('$timestamp.jpg');

    // Always use bytes for web compatibility
    Uint8List imageBytes;
    if (_idImageBytes != null) {
      imageBytes = _idImageBytes!;
    } else {
      // Read bytes from file if not already available
      imageBytes = await _idImage!.readAsBytes();
    }

    final uploadTask = await storageRef.putData(imageBytes);
    return await uploadTask.ref.getDownloadURL();
  }

  Future<String?> _uploadAdditionalImage() async {
    if (_additionalImage == null) return null;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('verification_additional')
        .child(user.uid)
        .child('$timestamp.jpg');

    // Always use bytes for web compatibility
    Uint8List imageBytes;
    if (_additionalImageBytes != null) {
      imageBytes = _additionalImageBytes!;
    } else {
      // Read bytes from file if not already available
      imageBytes = await _additionalImage!.readAsBytes();
    }

    final uploadTask = await storageRef.putData(imageBytes);
    return await uploadTask.ref.getDownloadURL();
  }

  Future<void> _submitVerificationRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idImage == null) {
      _showErrorSnackBar('يرجى إضافة صورة الهوية');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      // الحصول على بيانات المستخدم
      final userData = await DatabaseService.getUserFromFirestore(user.uid);

      // رفع صورة الهوية
      final idImageUrl = await _uploadIdImage();

      // رفع صورة إضافية إذا كانت موجودة
      final additionalImageUrl = await _uploadAdditionalImage();

      // إنشاء طلب التوثيق
      await FirebaseFirestore.instance.collection('verification_requests').add({
        'userId': user.uid,
        'userDisplayName': userData?['displayName'] ?? '',
        'userHandle': userData?['handle'] ?? '',
        'userProfileImage': userData?['profileImageUrl'] ?? '',
        'reason': _reasonController.text.trim(),
        'idImageUrl': idImageUrl,
        'additionalImageUrl': additionalImageUrl,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      Navigator.pop(context, true);
      _showSuccessSnackBar('تم إرسال طلب التوثيق بنجاح! سيتم مراجعته قريباً.');
    } catch (e) {
      _showErrorSnackBar('خطأ في إرسال طلب التوثيق: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  bool _isCurrentPageValid() {
    switch (_currentPage) {
      case 0:
        final text = _reasonController.text.trim();
        return text.isNotEmpty && text.length >= 20;
      case 1:
        return _idImage != null;
      case 2:
        return true; // Additional is optional
      default:
        return false;
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildReasonPage() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'لماذا تريد التوثيق؟',
                    style: GoogleFonts.cairo(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'اشرح سبب طلبك للتوثيق بتفصيل',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 4,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText: 'مثل: شخصية عامة، صاحب عمل معروف، إلخ',
                      hintStyle: GoogleFonts.cairo(color: Colors.grey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                    style: GoogleFonts.cairo(color: Colors.black),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'يرجى إدخال سبب طلب التوثيق';
                      }
                      if (value!.length < 20) {
                        return 'يجب أن يكون السبب أكثر تفصيلاً (20 حرف على الأقل)';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIdPage() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'أضف هويتك',
                  style: GoogleFonts.cairo(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'ارفع صورة واضحة من هويتك الشخصية',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: _pickIdImage,
                  child: Container(
                    width: double.infinity,
                    height: _idImage != null ? 300 : 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _idImage != null
                        ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _idImageBytes != null
                                    ? Image.memory(
                                        _idImageBytes!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      )
                                    : Image.file(
                                        _idImage!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _idImage = null;
                                    _idImageBytes = null;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate,
                                size: 50,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'اضغط لإضافة صورة الهوية',
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdditionalPage() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'وثيقة إضافية (اختياري)',
                  style: GoogleFonts.cairo(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'يمكنك إضافة وثيقة إضافية لدعم طلبك',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: _pickAdditionalImage,
                  child: Container(
                    width: double.infinity,
                    height: _additionalImage != null ? 300 : 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _additionalImage != null
                        ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _additionalImageBytes != null
                                    ? Image.memory(
                                        _additionalImageBytes!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      )
                                    : Image.file(
                                        _additionalImage!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: double.infinity,
                                      ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _additionalImage = null;
                                    _additionalImageBytes = null;
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate,
                                size: 50,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'اضغط لإضافة وثيقة إضافية',
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index ? Colors.black : Colors.grey[300],
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // Buttons
          Row(
            children: [
              if (_currentPage > 0)
                Expanded(
                  child: TextButton(
                    onPressed: _previousPage,
                    child: Text(
                      'السابق',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              if (_currentPage > 0) const SizedBox(width: 16),
              Expanded(
                child: _currentPage == 2
                    ? ElevatedButton(
                        onPressed: _isLoading ? null : _submitVerificationRequest,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'إرسال الطلب',
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      )
                    : ElevatedButton(
                        onPressed: _isCurrentPageValid() ? _nextPage : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isCurrentPageValid() ? Colors.black : Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: Text(
                          'التالي',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasExistingRequest) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'طلب التوثيق',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.black),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Icon(
                    _isAlreadyVerified ? Icons.verified : Icons.pending,
                    size: 60,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isAlreadyVerified
                      ? 'حسابك موثق بالفعل'
                      : 'طلب التوثيق قيد المراجعة',
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _isAlreadyVerified
                      ? 'تم توثيق حسابك بنجاح! يمكنك رؤية علامة التوثيق بجانب اسمك.'
                      : 'لديك طلب توثيق قيد المراجعة حالياً. سيتم إشعارك بالنتيجة قريباً.',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: Text(
                    'العودة',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'طلب التوثيق',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Disable swipe
              children: [
                _buildReasonPage(),
                _buildIdPage(),
                _buildAdditionalPage(),
              ],
            ),
          ),
          _buildBottomNavigation(),
        ],
      ),
    );
  }
}