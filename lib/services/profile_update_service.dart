import 'dart:async';

class ProfileUpdateService {
  static final ProfileUpdateService _instance = ProfileUpdateService._internal();
  factory ProfileUpdateService() => _instance;
  ProfileUpdateService._internal();

  // Stream controller للإشعار بتحديث الصورة
  final _profileImageUpdateController = StreamController<String>.broadcast();
  
  // Stream controller للإشعار بتحديث الاسم
  final _displayNameUpdateController = StreamController<String>.broadcast();
  
  // Stream للاستماع للتحديثات
  Stream<String> get profileImageUpdates => _profileImageUpdateController.stream;
  Stream<String> get displayNameUpdates => _displayNameUpdateController.stream;

  // دالة لإرسال إشعار بتحديث الصورة
  void notifyProfileImageUpdate(String userId) {
    _profileImageUpdateController.add(userId);
  }
  
  // دالة لإرسال إشعار بتحديث الاسم
  void notifyDisplayNameUpdate(String userId) {
    _displayNameUpdateController.add(userId);
  }

  // تنظيف الموارد
  void dispose() {
    _profileImageUpdateController.close();
    _displayNameUpdateController.close();
  }
}