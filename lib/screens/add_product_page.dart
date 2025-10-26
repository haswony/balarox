import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_service.dart';
import '../services/image_compression_service.dart';
import '../services/image_watermark_service.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  List<File> _selectedImages = [];
  List<Uint8List> _selectedImageBytes = []; // For web compatibility
  File? _selectedVideo;
  String _selectedCategory = 'مركبات';
  String _selectedCondition = 'جديد';
  bool _isNegotiable = false;
  bool _isLoading = false;

  int _currentPage = 0;
  final PageController _pageController = PageController();

  List<String> _categories = [];
  final List<String> _conditions = ['جديد', 'مستعمل', 'قديم'];
  final List<String> _packages = ['30 يوم', '60 يوم', '180 يوم'];
  String? _selectedPackage;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final categories = await DatabaseService.getCategories();
    setState(() {
      _categories = categories;
      if (_categories.isNotEmpty) {
        _selectedCategory = _categories.first;
      }
    });
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= 5) {
      _showErrorSnackBar('يمكنك إضافة 5 صور كحد أقصى');
      return;
    }

    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );

      if (images.isNotEmpty) {
        setState(() {
          for (var image in images) {
            if (_selectedImages.length < 5) {
              _selectedImages.add(File(image.path));
              // For web compatibility, we also store the bytes
              image.readAsBytes().then((bytes) {
                setState(() {
                  _selectedImageBytes.add(bytes);
                });
              });
            }
          }
        });
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في اختيار الصور: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        setState(() {
          _selectedVideo = File(video.path);
        });
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في اختيار الفيديو: $e');
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _selectedImageBytes.removeAt(index);
    });
  }

  Future<List<String>> _uploadImages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');

    List<String> imageUrls = [];
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < _selectedImages.length; i++) {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('products')
          .child(user.uid)
          .child('$timestamp-$i.jpg');

      // Upload using bytes for web compatibility
      Uint8List? imageBytes;
      if (i < _selectedImageBytes.length) {
        imageBytes = _selectedImageBytes[i];
      } else {
        // Fallback to file if bytes are not available
        imageBytes = await _selectedImages[i].readAsBytes();
      }

      // ضغط الصورة لتصبح بحد أقصى 100KB مع الحفاظ على الجودة
      final compressedBytes = await ImageCompressionService.compressImageToMaxSize(
        imageBytes,
        maxSizeKB: 100,
        minWidth: 800,
        minHeight: 800,
        quality: 90,
      );

      // استخدام الصورة المضغوطة إذا نجح الضغط
      final finalBytes = compressedBytes ?? imageBytes;

      // إضافة العلامة المائية
      final watermarkedBytes = await ImageWatermarkService.addWatermark(finalBytes);

      final uploadTask = await storageRef.putData(watermarkedBytes ?? finalBytes);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      imageUrls.add(downloadUrl);
    }

    return imageUrls;
  }

  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedImages.isEmpty) {
      _showErrorSnackBar('يرجى إضافة صورة واحدة على الأقل');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      // رفع الصور
      final imageUrls = await _uploadImages();

      if (_selectedPackage != null) {
        // إرسال طلب الباقة
        await DatabaseService.submitPackageRequest(
          userId: user.uid,
          package: _selectedPackage!,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          category: _selectedCategory,
          price: _priceController.text.trim(),
          location: _locationController.text.trim(),
          imageUrls: imageUrls,
          condition: _selectedCondition,
          isNegotiable: _isNegotiable,
        );

        // إنشاء رسالة واتساب
        final userData = await DatabaseService.getUserFromFirestore(user.uid);
        final displayName = userData?['displayName'] ?? 'مستخدم';
        final phoneNumber = userData?['phoneNumber'] ?? '';

        final prices = {'30 يوم': '15 دولار', '60 يوم': '30 دولار', '180 يوم': '80 دولار'};
        final packagePrice = prices[_selectedPackage!] ?? '';

        final message = 'مرحباً، أريد شراء باقة $_selectedPackage (السعر: $packagePrice) لإعلاني.\n\n'
            'معلوماتي:\n'
            'الاسم: $displayName\n'
            'الهاتف: $phoneNumber\n\n'
            'تفاصيل الإعلان:\n'
            'العنوان: ${_titleController.text.trim()}\n'
            'الوصف: ${_descriptionController.text.trim()}\n'
            'الفئة: $_selectedCategory\n'
            'السعر: ${_priceController.text.trim()}\n'
            'الموقع: ${_locationController.text.trim()}\n'
            'الحالة: $_selectedCondition\n'
            'قابل للتفاوض: ${_isNegotiable ? 'نعم' : 'لا'}\n\n'
            'يرجى تأكيد الطلب وإرسال رابط الدفع.';

        // فك تشفير الرقم مع رمز البلد للعراق
        final whatsappUrl = 'https://wa.me/9647712010242?text=${Uri.encodeComponent(message)}';

        final uri = Uri.parse(whatsappUrl);
        if (await launchUrl(uri)) {
          // Success
        } else {
          _showErrorSnackBar('لا يمكن فتح واتساب');
        }

        if (mounted) {
          _showSuccessSnackBar('تم إرسال طلب الباقة. يرجى التواصل عبر واتساب للدفع.');
          Navigator.pop(context, true);
        }
      } else {
        // إرسال المنتج للمراجعة (مجاني)
        await DatabaseService.submitProductForReview(
          userId: user.uid,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          category: _selectedCategory,
          price: _priceController.text.trim(),
          location: _locationController.text.trim(),
          imageUrls: imageUrls,
          condition: _selectedCondition,
          isNegotiable: _isNegotiable,
        );

        if (mounted) {
          _showSuccessSnackBar('تم إرسال المنتج للمراجعة. سيتم نشره بعد موافقة الإدارة.');
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في نشر المنتج: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'إضافة إعلان',
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
        actions: null,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page;
                });
              },
              children: [
                _buildImagePage(),
                _buildDetailsPage(),
                _buildPackagePage(),
              ],
            ),
          ),
          _buildBottomNavigation(),
        ],
      ),
    );
  }

  Widget _buildImagePage() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildImageContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsPage() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildDetailsContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildPackagePage() {
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildPackageContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'أضف صور الإعلان',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'يمكنك إضافة حتى 5 صور (الحد الأقصى)',
          style: GoogleFonts.cairo(
            fontSize: 16,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _selectedImages.length + (_selectedImages.length < 5 ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _selectedImages.length) {
              return GestureDetector(
                onTap: _pickImages,
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate,
                          color: Colors.grey[600], size: 30),
                      const SizedBox(height: 4),
                      Text(
                        'إضافة صورة',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            } else {
              return Container(
                height: 100,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _selectedImageBytes.length > index
                          ? Image.memory(
                        _selectedImageBytes[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      )
                          : Image.file(
                        _selectedImages[index],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
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
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildDetailsContent() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'تفاصيل الإعلان',
            style: GoogleFonts.cairo(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // عنوان الإعلان
          _buildTextFormField(
            controller: _titleController,
            label: 'عنوان الإعلان',
            hint: 'أدخل عنوان الإعلان',
            maxLength: 20,
            validator: (value) {
              if (value?.isEmpty ?? true) {
                return 'يرجى إدخال عنوان الإعلان';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // الفئة
          Text(
            'الفئة',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: _categories.map((category) {
              return DropdownMenuItem(
                value: category,
                child: Text(
                  category,
                  style: GoogleFonts.cairo(),
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCategory = value!;
              });
            },
          ),
          const SizedBox(height: 16),
          // السعر
          _buildTextFormField(
            controller: _priceController,
            label: 'السعر',
            hint: 'أدخل السعر',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (value) {
              if (value?.isEmpty ?? true) {
                return 'يرجى إدخال السعر';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // الحالة
          Text(
            'الحالة',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCondition,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: _conditions.map((condition) {
              return DropdownMenuItem(
                value: condition,
                child: Text(
                  condition,
                  style: GoogleFonts.cairo(),
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedCondition = value!;
              });
            },
          ),
          const SizedBox(height: 16),
          // قابل للتفاوض
          Row(
            children: [
              Text(
                'قابل للتفاوض',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              Checkbox(
                value: _isNegotiable,
                onChanged: (value) {
                  setState(() {
                    _isNegotiable = value ?? false;
                  });
                },
              ),
              const SizedBox(width: 8),
              Text(
                'نعم',
                style: GoogleFonts.cairo(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // الموقع
          _buildTextFormField(
            controller: _locationController,
            label: 'الموقع',
            hint: 'أدخل موقع الإعلان',
            validator: (value) {
              if (value?.isEmpty ?? true) {
                return 'يرجى إدخال الموقع';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // الوصف
          _buildTextFormField(
            controller: _descriptionController,
            label: 'الوصف',
            hint: 'أدخل وصف تفصيلي للإعلان',
            maxLines: 4,
            validator: (value) {
              if (value?.isEmpty ?? true) {
                return 'يرجى إدخال وصف الإعلان';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPackageContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'اختر باقة الإعلان',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // Free option with Instagram-like styling
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _selectedPackage == null ? Colors.blue[600] : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _selectedPackage == null ? Colors.blue[600]! : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: ListTile(
            leading: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedPackage == null ? Colors.white : Colors.grey[400]!,
                  width: 2,
                ),
                color: _selectedPackage == null ? Colors.white : Colors.transparent,
              ),
              child: _selectedPackage == null
                  ? Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue,
                      ),
                    )
                  : null,
            ),
            title: Text(
              '10 أيام',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _selectedPackage == null ? Colors.white : Colors.black87,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'مجاني',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _selectedPackage == null ? Colors.white : Colors.green[600],
                  ),
                ),
                if (_selectedPackage == null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check, color: Colors.white, size: 20),
                  ),
              ],
            ),
            onTap: () {
              setState(() {
                _selectedPackage = null;
              });
            },
          ),
        ),
        // Package options with Instagram-like styling
        ..._packages.asMap().entries.map((entry) {
          final index = entry.key;
          final package = entry.value;
          final prices = {'30 يوم': '15 دولار', '60 يوم': '30 دولار', '180 يوم': '80 دولار'};
          final price = prices[package] ?? '';
          final isSelected = _selectedPackage == package;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue[600] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.blue[600]! : Colors.grey[300]!,
                width: 2,
              ),
            ),
            child: ListTile(
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.grey[400]!,
                    width: 2,
                  ),
                  color: isSelected ? Colors.white : Colors.transparent,
                ),
                child: isSelected
                    ? Container(
                        margin: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                        ),
                      )
                    : null,
              ),
              title: Text(
                package,
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    price,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.green[600],
                    ),
                  ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.check, color: Colors.white, size: 20),
                    ),
                ],
              ),
              onTap: () {
                setState(() {
                  _selectedPackage = package;
                });
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress indicator
          SizedBox(
            height: 4,
            child: LinearProgressIndicator(
              value: (_currentPage + 1) / 3,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
            ),
          ),
          const SizedBox(height: 4),
          // Step text
          Text(
            'إضافة إعلان (${_currentPage + 1}/3)',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          // Buttons
          Row(
            children: [
              if (_currentPage > 0)
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Text(
                      'السابق',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              if (_currentPage > 0) const SizedBox(width: 12),
              Expanded(
                child: _currentPage == 2
                    ? ElevatedButton(
                  onPressed: _isLoading ? null : _submitProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : Text(
                    _selectedPackage != null ? 'الذهاب إلى واتساب' : 'نشر',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
                    : ElevatedButton(
                  onPressed: _currentPage == 0 ? (_selectedImages.isNotEmpty ? () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  } : null) : () {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentPage == 0 ? (_selectedImages.isNotEmpty ? Colors.black : Colors.grey) : Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    'التالي',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
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

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.cairo(color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          style: GoogleFonts.cairo(),
          validator: validator,
        ),
      ],
    );
  }
}
