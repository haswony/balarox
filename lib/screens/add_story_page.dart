import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Add this import for kIsWeb
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

import '../services/database_service.dart';
import '../services/image_compression_service.dart';
import '../services/image_watermark_service.dart';

class AddStoryPage extends StatefulWidget {
  const AddStoryPage({super.key});

  @override
  State<AddStoryPage> createState() => _AddStoryPageState();
}

class _AddStoryPageState extends State<AddStoryPage> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _textOverlayController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final TransformationController _transformationController = TransformationController();
  
  File? _selectedMedia;
  Uint8List? _selectedMediaBytes; // For web compatibility
  bool _isLoading = false;
  bool _showTextEditor = false;
  
  // إعدادات النص المخصص
  List<TextOverlay> _textOverlays = [];
  int? _selectedTextIndex;
  Color _currentTextColor = Colors.white;
  Color _currentBackgroundColor = Colors.black.withOpacity(0.5);
  double _currentFontSize = 24.0;
  
  // إعدادات التكبير والتصغير
  double _scale = 1.0;
  double _previousScale = 1.0;

  @override
  void dispose() {
    _captionController.dispose();
    _textOverlayController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );

      if (image != null) {
        setState(() {
          _selectedMedia = File(image.path);
          _selectedMediaBytes = null; // Reset bytes
          // For web compatibility, we also store the bytes
          image.readAsBytes().then((bytes) {
            setState(() {
              _selectedMediaBytes = bytes;
            });
          });
          _textOverlays.clear();
          _selectedTextIndex = null;
          _transformationController.value = Matrix4.identity();
        });
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في اختيار الصورة: $e');
    }
  }


  Future<void> _takePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 70,
      );

      if (image != null) {
        setState(() {
          _selectedMedia = File(image.path);
          _selectedMediaBytes = null; // Reset bytes
          // For web compatibility, we also store the bytes
          image.readAsBytes().then((bytes) {
            setState(() {
              _selectedMediaBytes = bytes;
            });
          });
          _textOverlays.clear();
          _selectedTextIndex = null;
          _transformationController.value = Matrix4.identity();
        });
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في التقاط الصورة: $e');
    }
  }


  void _addTextOverlay() {
    setState(() {
      _showTextEditor = true;
      _textOverlayController.clear();
      _selectedTextIndex = null;
      // إعادة تعيين الألوان للقيم الافتراضية
      _currentTextColor = Colors.white;
      _currentBackgroundColor = Colors.black.withOpacity(0.5);
      _currentFontSize = 24.0;
    });
  }

  void _saveTextOverlay() {
    if (_textOverlayController.text.trim().isNotEmpty) {
      setState(() {
        _textOverlays.add(TextOverlay(
          text: _textOverlayController.text.trim(),
          x: 0.5,
          y: 0.5,
          color: _currentTextColor,
          backgroundColor: _currentBackgroundColor,
          fontSize: _currentFontSize,
        ));
        _showTextEditor = false;
        _textOverlayController.clear();
      });
    }
  }

  void _editTextOverlay(int index) {
    final overlay = _textOverlays[index];
    setState(() {
      _selectedTextIndex = index;
      _textOverlayController.text = overlay.text;
      _currentTextColor = overlay.color;
      _currentBackgroundColor = overlay.backgroundColor;
      _currentFontSize = overlay.fontSize;
      _showTextEditor = true;
    });
  }

  void _updateTextOverlay() {
    if (_selectedTextIndex != null && _textOverlayController.text.trim().isNotEmpty) {
      setState(() {
        _textOverlays[_selectedTextIndex!] = _textOverlays[_selectedTextIndex!].copyWith(
          text: _textOverlayController.text.trim(),
          color: _currentTextColor,
          backgroundColor: _currentBackgroundColor,
          fontSize: _currentFontSize,
        );
        _showTextEditor = false;
        _selectedTextIndex = null;
        _textOverlayController.clear();
      });
    }
  }

  void _deleteTextOverlay(int index) {
    setState(() {
      _textOverlays.removeAt(index);
      if (_selectedTextIndex == index) {
        _selectedTextIndex = null;
        _showTextEditor = false;
      }
    });
  }

  void _updateTextPosition(int index, Offset position, Size containerSize) {
    setState(() {
      _textOverlays[index] = _textOverlays[index].copyWith(
        x: (position.dx / containerSize.width).clamp(0.0, 1.0),
        y: (position.dy / containerSize.height).clamp(0.0, 1.0),
      );
    });
  }

  Future<String> _uploadMedia() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');
    if (_selectedMedia == null) throw Exception('لم يتم اختيار وسائط');

    // For images, always use putData for web compatibility
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final extension = 'jpg';

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('stories')
        .child(user.uid)
        .child('$timestamp.$extension');

    // Always use bytes for images to ensure web compatibility
    Uint8List imageBytes;
    if (_selectedMediaBytes != null) {
      imageBytes = _selectedMediaBytes!;
    } else {
      // Read bytes from file if not already available
      imageBytes = await _selectedMedia!.readAsBytes();
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
    return await uploadTask.ref.getDownloadURL();
  }

  Future<void> _publishStory() async {
    if (_selectedMedia == null) {
      _showErrorSnackBar('يرجى اختيار وسائط للقصة');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('المستخدم غير مسجل الدخول');

      // التحقق من حد إضافة القصص (قصة واحدة كل 24 ساعة)
      final storyLimitCheck = await DatabaseService.checkUserStoryLimit(user.uid);
      
      if (!storyLimitCheck['canAddStory']) {
        final remainingSeconds = storyLimitCheck['remainingTime'] as int;
        final hours = remainingSeconds ~/ 3600;
        final minutes = (remainingSeconds % 3600) ~/ 60;
        
        String timeMessage;
        if (hours > 0) {
          timeMessage = '$hours ساعة و $minutes دقيقة';
        } else {
          timeMessage = '$minutes دقيقة';
        }
        
        setState(() {
          _isLoading = false;
        });
        
        _showErrorSnackBar('يمكنك إضافة قصة واحدة فقط كل 24 ساعة\nالوقت المتبقي: $timeMessage');
        return;
      }

      // رفع الوسائط
      final mediaUrl = await _uploadMedia();

      // تحضير بيانات النصوص
      final textOverlaysData = _textOverlays.map((overlay) => {
        'text': overlay.text,
        'x': overlay.x,
        'y': overlay.y,
        'color': overlay.color.value,
        'backgroundColor': overlay.backgroundColor.value,
        'fontSize': overlay.fontSize,
      }).toList();

      await DatabaseService.addStoryWithTextOverlays(
        userId: user.uid,
        imageUrl: mediaUrl,
        caption: _captionController.text.trim(),
        textOverlays: textOverlaysData,
        isVideo: false,
      );

      Navigator.pop(context, true);
    } catch (e) {
      _showErrorSnackBar('خطأ في نشر القصة: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMediaSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'اختر وسائط للقصة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 20),

            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: Text(
                'التقاط صورة',
                style: GoogleFonts.cairo(fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: Text(
                'اختيار صورة من المعرض',
                style: GoogleFonts.cairo(fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'إضافة قصة',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else if (_selectedMedia != null)
            TextButton(
              onPressed: _publishStory,
              child: Text(
                'نشر',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          _selectedMedia == null ? _buildMediaSelector() : _buildStoryEditor(),
          if (_showTextEditor) _buildTextEditor(),
        ],
      ),
    );
  }

  Widget _buildMediaSelector() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 80,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 20),
          Text(
            'اختر وسائط لقصتك',
            style: GoogleFonts.cairo(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'ستختفي القصة بعد 24 ساعة',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _showMediaSourceDialog,
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(
              'إضافة محتوى',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryEditor() {
    return Column(
      children: [
        // منطقة الوسائط مع النصوص
        Expanded(
          child: Container(
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final aspectRatio = 9 / 16; // نسبة Instagram Stories
                final containerHeight = constraints.maxHeight;
                final containerWidth = constraints.maxWidth;
                
                // حساب الأبعاد المناسبة للقصة
                double storyWidth, storyHeight;
                if (containerWidth / containerHeight > aspectRatio) {
                  storyHeight = containerHeight;
                  storyWidth = storyHeight * aspectRatio;
                } else {
                  storyWidth = containerWidth;
                  storyHeight = storyWidth / aspectRatio;
                }

                return Center(
                  child: Container(
                    width: storyWidth,
                    height: storyHeight,
                    child: Stack(
                      children: [
                        // الصورة
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: InteractiveViewer(
                              transformationController: _transformationController,
                              minScale: 0.5,
                              maxScale: 3.0,
                              child: _selectedMediaBytes != null
                                  ? Image.memory(
                                      _selectedMediaBytes!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    )
                                  : Image.file(
                                      _selectedMedia!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                            ),
                          ),
                        ),
                        
                        // النصوص المضافة
                        ..._textOverlays.asMap().entries.map((entry) {
                          final index = entry.key;
                          final overlay = entry.value;
                          
                          return Positioned(
                            left: overlay.x * storyWidth - 50,
                            top: overlay.y * storyHeight - 20,
                            child: GestureDetector(
                              onPanUpdate: (details) {
                                final newPosition = Offset(
                                  overlay.x * storyWidth + details.delta.dx,
                                  overlay.y * storyHeight + details.delta.dy,
                                );
                                _updateTextPosition(index, newPosition, Size(storyWidth, storyHeight));
                              },
                              onTap: () => _editTextOverlay(index),
                              onLongPress: () => _deleteTextOverlay(index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: overlay.backgroundColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  overlay.text,
                                  style: GoogleFonts.cairo(
                                    color: overlay.color,
                                    fontSize: overlay.fontSize,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                        
                        // أزرار التحكم
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Column(
                            children: [
                              FloatingActionButton.small(
                                onPressed: _showMediaSourceDialog,
                                backgroundColor: Colors.black54,
                                heroTag: "change_media",
                                child: const Icon(Icons.edit, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              FloatingActionButton.small(
                                onPressed: _addTextOverlay,
                                backgroundColor: Colors.black54,
                                heroTag: "add_text",
                                child: const Icon(Icons.text_fields, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        
        // حقل التعليق
        Container(
          color: Colors.black,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _captionController,
                textAlign: TextAlign.right,
                maxLength: 200,
                maxLines: 2,
                style: GoogleFonts.cairo(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'أضف تعليق (اختياري)...',
                  hintStyle: GoogleFonts.cairo(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[600]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[600]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                  filled: true,
                  fillColor: Colors.grey[900],
                  contentPadding: const EdgeInsets.all(16),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              
              // نصائح
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '💡 اضغط على النص لتعديله، اضغط مطولاً لحذفه',
                        style: GoogleFonts.cairo(
                          color: Colors.grey[300],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextEditor() {
    return Container(
      color: Colors.black87,
      child: Column(
        children: [
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              _selectedTextIndex != null ? 'تعديل النص' : 'إضافة نص',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            leading: IconButton(
              onPressed: () {
                setState(() {
                  _showTextEditor = false;
                  _selectedTextIndex = null;
                  _textOverlayController.clear();
                });
              },
              icon: const Icon(Icons.close, color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: _selectedTextIndex != null ? _updateTextOverlay : _saveTextOverlay,
                child: Text(
                  'حفظ',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // معاينة النص
                  Container(
                    width: double.infinity,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _currentBackgroundColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _textOverlayController.text.isEmpty ? 'معاينة النص' : _textOverlayController.text,
                          style: GoogleFonts.cairo(
                            color: _currentTextColor,
                            fontSize: _currentFontSize * 0.6, // تصغير المعاينة
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // حقل النص
                  TextField(
                    controller: _textOverlayController,
                    textAlign: TextAlign.center,
                    maxLength: 50, // تقليل الحد الأقصى
                    maxLines: 2, // تقليل عدد الأسطر
                    autofocus: true,
                    onChanged: (value) => setState(() {}),
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'اكتب نصك هنا...',
                      hintStyle: GoogleFonts.cairo(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[600]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[600]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blue),
                      ),
                      filled: true,
                      fillColor: Colors.grey[800],
                      counterText: '',
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // حجم النص مع عرض القيمة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'حجم النص',
                        style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_currentFontSize.round()}',
                        style: GoogleFonts.cairo(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _currentFontSize,
                    min: 14.0,
                    max: 32.0,
                    divisions: 9,
                    activeColor: Colors.blue,
                    inactiveColor: Colors.grey[600],
                    onChanged: (value) {
                      setState(() {
                        _currentFontSize = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // ألوان النص
                  Text(
                    'لون النص',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildColorOption(Colors.white, true),
                      _buildColorOption(Colors.black, true),
                      _buildColorOption(Colors.red, true),
                      _buildColorOption(Colors.blue, true),
                      _buildColorOption(Colors.green, true),
                      _buildColorOption(Colors.yellow, true),
                      _buildColorOption(Colors.purple, true),
                      _buildColorOption(Colors.orange, true),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // ألوان الخلفية
                  Text(
                    'لون الخلفية',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildColorOption(Colors.transparent, false),
                      _buildColorOption(Colors.black.withOpacity(0.7), false),
                      _buildColorOption(Colors.white.withOpacity(0.7), false),
                      _buildColorOption(Colors.red.withOpacity(0.7), false),
                      _buildColorOption(Colors.blue.withOpacity(0.7), false),
                      _buildColorOption(Colors.green.withOpacity(0.7), false),
                      _buildColorOption(Colors.yellow.withOpacity(0.7), false),
                      _buildColorOption(Colors.purple.withOpacity(0.7), false),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorOption(Color color, bool isTextColor) {
    final isSelected = isTextColor
        ? _currentTextColor == color
        : _currentBackgroundColor == color;
        
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isTextColor) {
            _currentTextColor = color;
          } else {
            _currentBackgroundColor = color;
          }
        });
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color == Colors.transparent ? Colors.grey[800] : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.grey[600]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: color == Colors.transparent
            ? Icon(Icons.format_color_reset, color: Colors.white, size: 14)
            : isSelected
                ? Icon(Icons.check, color: color == Colors.white ? Colors.black : Colors.white, size: 16)
                : null,
      ),
    );
  }

}

// فئة لتمثيل النص المضاف على الصورة
class TextOverlay {
  final String text;
  final double x;
  final double y;
  final Color color;
  final Color backgroundColor;
  final double fontSize;

  TextOverlay({
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    required this.backgroundColor,
    required this.fontSize,
  });

  TextOverlay copyWith({
    String? text,
    double? x,
    double? y,
    Color? color,
    Color? backgroundColor,
    double? fontSize,
  }) {
    return TextOverlay(
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontSize: fontSize ?? this.fontSize,
    );
  }
}