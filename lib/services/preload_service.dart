import '../services/database_service.dart';

class PreloadService {
  static bool _isPreloaded = false;
  static bool _isPreloading = false;
  static DateTime? _lastPreloadTime;

  /// تحميل البيانات الأساسية مسبقاً
  static Future<void> preloadData() async {
    // منع التحميل المتكرر لمدة 5 دقائق
    if (_isPreloaded && _lastPreloadTime != null) {
      final timeSinceLastPreload = DateTime.now().difference(_lastPreloadTime!);
      if (timeSinceLastPreload.inMinutes < 5) {
        return;
      }
    }

    if (_isPreloading) return;

    _isPreloading = true;

    try {
      print('بدء التحميل المسبق للبيانات...');

      // تحميل البيانات بشكل متوازي وسريع
      await Future.wait([
        DatabaseService.getCategories(),
        DatabaseService.getProducts(limit: 30), // تحميل منتجات أكثر
        DatabaseService.getActiveStories(),
      ]);

      _isPreloaded = true;
      _lastPreloadTime = DateTime.now();

      print('تم التحميل المسبق للبيانات بنجاح');
    } catch (e) {
      print('خطأ في التحميل المسبق: $e');
      _isPreloaded = false; // إعادة تعيين في حالة الخطأ
    } finally {
      _isPreloading = false;
    }
  }

  /// التحقق من حالة التحميل
  static bool get isPreloaded => _isPreloaded;

  /// مسح حالة التحميل المسبق (للاستخدام عند تسجيل الخروج أو بدء التطبيق)
  static void reset() {
    _isPreloaded = false;
    _isPreloading = false;
    _lastPreloadTime = null;
    print('تم مسح حالة التحميل المسبق');
  }

  /// فرض إعادة التحميل المسبق
  static void forceReload() {
    reset();
  }
}
