import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../services/image_compression_service.dart';
import '../services/image_watermark_service.dart';

class EditProductPage extends StatefulWidget {
  final String pendingProductId;
  final Map<String, dynamic> productData;

  const EditProductPage({
    super.key,
    required this.pendingProductId,
    required this.productData,
  });

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
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

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProductData();
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

  void _loadProductData() {
    final data = widget.productData;
    _titleController.text = data['title'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _priceController.text = data['price'] ?? '';
    _locationController.text = data['location'] ?? '';
    _selectedCategory = data['category'] ?? 'مركبات';
    _selectedCondition = data['condition'] ?? 'جديد';
    _isNegotiable = data['isNegotiable'] ?? false;

    // Load existing images if any
    final imageUrls = List<String>.from(data['imageUrls'] ?? []);
    // Note: For editing, we keep existing images and allow adding new ones
    // Existing images are handled separately in the UI
  }

  Future<void> _loadCategories() async {
    final categories = await DatabaseService.getCategories();
    setState(() {
      _categories = categories;
      if (_categories.isNotEmpty && !_categories.contains(_selectedCategory)) {
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

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      // First check if the product still exists
      final productDoc = await FirebaseFirestore.instance
          .collection('pending_products')
          .doc(widget.pendingProductId)
          .get();

      if (!productDoc.exists) {
        throw Exception('الإعلان غير متوفر للتعديل. قد يكون قد تم حذفه أو قبوله.');
      }

      // Combine existing and new images
      List<String> allImageUrls = List<String>.from(widget.productData['imageUrls'] ?? []);

      // Upload new images if any
      if (_selectedImages.isNotEmpty) {
        final newImageUrls = await _uploadImages();
        allImageUrls.addAll(newImageUrls);
      }

      // Update the pending product
      await DatabaseService.updatePendingProduct(widget.pendingProductId, {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'price': _priceController.text.trim(),
        'location': _locationController.text.trim(),
        'imageUrls': allImageUrls,
        'condition': _selectedCondition,
        'isNegotiable': _isNegotiable,
      });

      if (mounted) {
        _showSuccessSnackBar('تم تحديث إعلانك بنجاح. سيتم مراجعته مرة أخرى.');
        Navigator.pop(context, true); // إرجاع true للإشارة إلى النجاح
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في تحديث المنتج: $e');
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
          'تعديل الإعلان',
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

  Widget _buildImageContent() {
    final existingImages = List<String>.from(widget.productData['imageUrls'] ?? []);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'صور الإعلان',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'يمكنك إضافة صور إضافية (الحد الأقصى 5 صور إجمالاً)',
          style: GoogleFonts.cairo(
            fontSize: 16,
            color: Colors.black,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // Show existing images
        if (existingImages.isNotEmpty) ...[
          Text(
            'الصور الحالية:',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: existingImages.length,
            itemBuilder: (context, index) {
              return Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: NetworkImage(existingImages[index]),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
        ],
        // Add new images section
        Text(
          'إضافة صور جديدة:',
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: _selectedImages.length + (existingImages.length + _selectedImages.length < 5 ? 1 : 0),
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
              value: (_currentPage + 1) / 2,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
            ),
          ),
          const SizedBox(height: 4),
          // Step text
          Text(
            'تعديل الإعلان (${_currentPage + 1}/2)',
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
              child: _currentPage == 1
                  ? ElevatedButton(
                onPressed: _isLoading ? null : _updateProduct,
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
                  'تحديث',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
                  : ElevatedButton(
                onPressed: _selectedImages.isNotEmpty
                    ? () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedImages.isNotEmpty ? Colors.black : Colors.grey,
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