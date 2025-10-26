import 'dart:async';

/// مدير مركزي لإدارة جميع الاشتراكات في التطبيق
/// يساعد في منع تسرب الذاكرة وإلغاء جميع الاشتراكات عند الحاجة
class StreamManager {
  static final StreamManager _instance = StreamManager._internal();
  factory StreamManager() => _instance;
  static StreamManager get instance => _instance;
  
  StreamManager._internal();

  // قائمة جميع الاشتراكات النشطة
  final List<StreamSubscription> _subscriptions = [];

  /// إضافة اشتراك جديد للإدارة
  void addSubscription(StreamSubscription subscription) {
    _subscriptions.add(subscription);
  }

  /// إلغاء جميع الاشتراكات
  Future<void> cancelAll() async {
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (e) {
        print('خطأ في إلغاء الاشتراك: $e');
      }
    }
    _subscriptions.clear();
  }

  /// إلغاء اشتراك محدد
  Future<void> cancelSubscription(StreamSubscription subscription) async {
    try {
      await subscription.cancel();
      _subscriptions.remove(subscription);
    } catch (e) {
      print('خطأ في إلغاء الاشتراك المحدد: $e');
    }
  }

  /// الحصول على عدد الاشتراكات النشطة
  int get activeSubscriptionsCount => _subscriptions.length;

  /// التحقق من وجود اشتراكات نشطة
  bool get hasActiveSubscriptions => _subscriptions.isNotEmpty;
}