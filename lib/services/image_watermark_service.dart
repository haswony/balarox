import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageWatermarkService {
  static img.Image? _watermarkImage;

  /// تحميل صورة العلامة المائية (الشعار) مرة واحدة
  static Future<void> _loadWatermark() async {
    if (_watermarkImage != null) return;

    try {
      final ByteData data = await rootBundle.load('assets/icon/baladruz.png');
      final Uint8List bytes = data.buffer.asUint8List();
      _watermarkImage = img.decodeImage(bytes);
    } catch (e) {
      print('خطأ في تحميل العلامة المائية: $e');
    }
  }

  /// إضافة علامة مائية للصورة
  static Future<Uint8List?> addWatermark(Uint8List imageBytes) async {
    try {
      await _loadWatermark();
      if (_watermarkImage == null) {
        print('لم يتم العثور على العلامة المائية');
        return imageBytes; // إرجاع الصورة الأصلية إذا لم نجد العلامة المائية
      }

      // فك تشفير الصورة الأصلية
      img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) {
        print('خطأ في فك تشفير الصورة الأصلية');
        return imageBytes;
      }

      // نسخ الصورة الأصلية
      img.Image watermarkedImage = img.copyResize(originalImage,
          width: originalImage.width, height: originalImage.height);

      // حساب حجم العلامة المائية (نسبة من حجم الصورة الأصلية)
      int watermarkWidth = (originalImage.width * 0.15).round(); // 15% من عرض الصورة
      int watermarkHeight = (watermarkWidth * _watermarkImage!.height / _watermarkImage!.width).round();

      // تغيير حجم العلامة المائية
      img.Image resizedWatermark = img.copyResize(_watermarkImage!,
          width: watermarkWidth, height: watermarkHeight);

      // إضافة شفافية للعلامة المائية
      resizedWatermark = img.colorOffset(resizedWatermark,
          alpha: -150); // جعلها شبه شفافة

      // موقع العلامة المائية في الزاوية العلوية اليمنى
      int x = originalImage.width - watermarkWidth - 20; // 20 بكسل من الحافة
      int y = 20; // 20 بكسل من الأعلى

      // رسم العلامة المائية على الصورة
      img.compositeImage(watermarkedImage, resizedWatermark,
          dstX: x, dstY: y);

      // تشفير الصورة مرة أخرى إلى bytes
      return Uint8List.fromList(img.encodeJpg(watermarkedImage, quality: 90));
    } catch (e) {
      print('خطأ في إضافة العلامة المائية: $e');
      return imageBytes; // إرجاع الصورة الأصلية في حالة الخطأ
    }
  }
}