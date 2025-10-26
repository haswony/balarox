import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ImageCompressionService {
  /// ضغط الصورة لتصبح بحجم أقصى 100KB مع الحفاظ على الجودة
  static Future<Uint8List?> compressImageToMaxSize(
    Uint8List imageBytes, {
    int maxSizeKB = 100,
    int minWidth = 800,
    int minHeight = 800,
    int quality = 90,
  }) async {
    try {
      // الحصول على حجم الصورة الأصلي
      final originalSize = imageBytes.length / 1024; // KB

      // إذا كانت الصورة أصغر من الحد الأقصى، لا نحتاج للضغط
      if (originalSize <= maxSizeKB) {
        return imageBytes;
      }

      print('ضغط الصورة: الحجم الأصلي = ${originalSize.toStringAsFixed(2)} KB');

      // محاولة ضغط الصورة تدريجياً حتى تصل للحجم المطلوب
      Uint8List? compressedBytes = imageBytes;
      int currentQuality = quality;
      int currentMaxSizeKB = maxSizeKB;

      // محاولة أولى بالجودة العالية
      compressedBytes = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: currentQuality,
      );

      double compressedSize = compressedBytes.length / 1024;

      // إذا لم نصل للحجم المطلوب، نستمر في تقليل الجودة
      while (compressedSize > currentMaxSizeKB && currentQuality > 50) {
        currentQuality -= 10;

        compressedBytes = await FlutterImageCompress.compressWithList(
          imageBytes,
          minWidth: minWidth,
          minHeight: minHeight,
          quality: currentQuality,
        );

        compressedSize = compressedBytes.length / 1024;
        print('محاولة ضغط: جودة = $currentQuality, حجم = ${compressedSize.toStringAsFixed(2)} KB');
      }

      // إذا لم نصل للحجم المطلوب بعد، نحاول تقليل الأبعاد
      if (compressedSize > currentMaxSizeKB) {
        int currentMinWidth = minWidth;
        int currentMinHeight = minHeight;

        while (compressedSize > currentMaxSizeKB &&
               currentMinWidth > 400 &&
               currentMinHeight > 400) {
          currentMinWidth = (currentMinWidth * 0.9).round();
          currentMinHeight = (currentMinHeight * 0.9).round();

          compressedBytes = await FlutterImageCompress.compressWithList(
            imageBytes,
            minWidth: currentMinWidth,
            minHeight: currentMinHeight,
            quality: currentQuality,
          );

          compressedSize = compressedBytes.length / 1024;
          print('محاولة ضغط: أبعاد = ${currentMinWidth}x$currentMinHeight, حجم = ${compressedSize.toStringAsFixed(2)} KB');
        }
      }

      print('النتيجة النهائية: حجم = ${compressedSize.toStringAsFixed(2)} KB');

      return compressedBytes;
    } catch (e) {
      print('خطأ في ضغط الصورة: $e');
      // في حالة الخطأ، نرجع الصورة الأصلية
      return imageBytes;
    }
  }

  /// ضغط الصورة من ملف
  static Future<Uint8List?> compressImageFile(
    File imageFile, {
    int maxSizeKB = 100,
    int minWidth = 800,
    int minHeight = 800,
    int quality = 90,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return await compressImageToMaxSize(
        bytes,
        maxSizeKB: maxSizeKB,
        minWidth: minWidth,
        minHeight: minHeight,
        quality: quality,
      );
    } catch (e) {
      print('خطأ في قراءة ملف الصورة: $e');
      return null;
    }
  }

  /// ضغط سريع للصور الكبيرة جداً
  static Future<Uint8List?> quickCompressForLargeImages(
    Uint8List imageBytes, {
    int maxSizeKB = 200,
  }) async {
    return await compressImageToMaxSize(
      imageBytes,
      maxSizeKB: maxSizeKB,
      minWidth: 1200,
      minHeight: 1200,
      quality: 80,
    );
  }
}