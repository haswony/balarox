import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  // رفع صورة الطبيب إلى Firebase Storage
  static Future<String?> uploadDoctorImage(File imageFile) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // إنشاء مسار فريد للصورة
      final fileName = 'doctor_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('doctors').child(fileName);

      // رفع الصورة
      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;

      // الحصول على رابط التحميل
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('خطأ في رفع صورة الطبيب: $e');
      return null;
    }
  }
  
  // رفع صورة العيادة إلى Firebase Storage
  static Future<String?> uploadClinicImage(File imageFile) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
  
      // إنشاء مسار فريد للصورة
      final fileName = 'clinic_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('clinics').child(fileName);
  
      // رفع الصورة
      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;
  
      // الحصول على رابط التحميل
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('خطأ في رفع صورة العيادة: $e');
      return null;
    }
  }
  
  // حذف صورة الطبيب من Firebase Storage
  static Future<bool> deleteDoctorImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
      return true;
    } catch (e) {
      print('خطأ في حذف صورة الطبيب: $e');
      return false;
    }
  }

  // رفع صورة عامة
  static Future<String?> uploadImage(File imageFile, String folderName) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      final fileName = '${folderName}_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child(folderName).child(fileName);

      final uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask;

      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print('خطأ في رفع الصورة: $e');
      return null;
    }
  }
}