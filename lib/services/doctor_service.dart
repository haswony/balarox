import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/doctor.dart';
import '../models/booking.dart';

class DoctorService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _doctorsCollection = 'doctors';
  static const String _bookingsCollection = 'bookings';

  // الحصول على جميع الأطباء النشطين والمعتمدين
  static Future<List<Doctor>> getActiveDoctors() async {
    try {
      final querySnapshot = await _firestore
          .collection(_doctorsCollection)
          .where('isActive', isEqualTo: true)
          .where('status', isEqualTo: 'approved')
          .orderBy('name', descending: false)
          .get();

      return querySnapshot.docs
          .map((doc) => Doctor.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('خطأ في جلب الأطباء: $e');
      return [];
    }
  }

  // الحصول على طبيب معين
  static Future<Doctor?> getDoctorById(String doctorId) async {
    try {
      final docSnapshot = await _firestore
          .collection(_doctorsCollection)
          .doc(doctorId)
          .get();

      if (docSnapshot.exists) {
        return Doctor.fromFirestore(docSnapshot.data()!, docSnapshot.id);
      }
      return null;
    } catch (e) {
      print('خطأ في جلب الطبيب: $e');
      return null;
    }
  }

  // التحقق من إمكانية إضافة طبيب جديد (لا يوجد معتمد أو معلق أو مرفوض)
  static Future<bool> canUserAddDoctor() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // التحقق من الأطباء المعتمدين
      final approvedQuery = await _firestore
          .collection(_doctorsCollection)
          .where('userId', isEqualTo: currentUser.uid)
          .limit(1)
          .get();

      if (approvedQuery.docs.isNotEmpty) {
        print('User already has an approved clinic');
        return false;
      }

      // التحقق من الأطباء المعلقين فقط (لا نمنع إذا مرفوض)
      final pendingQuery = await _firestore
          .collection('pending_doctors')
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (pendingQuery.docs.isNotEmpty) {
        print('User already has a pending clinic request');
        return false;
      }

      return true;
    } catch (e) {
      print('خطأ في التحقق من إمكانية إضافة الطبيب: $e');
      return false;
    }
  }

  // الحصول على حالة الطلب الموجود (لعرض الرسالة المناسبة)
  static Future<String?> getExistingRequestStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;

      // التحقق من الأطباء المعتمدين
      final approvedQuery = await _firestore
          .collection(_doctorsCollection)
          .where('userId', isEqualTo: currentUser.uid)
          .limit(1)
          .get();

      if (approvedQuery.docs.isNotEmpty) {
        return 'approved';
      }

      // التحقق من الأطباء المعلقين فقط
      final pendingQuery = await _firestore
          .collection('pending_doctors')
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (pendingQuery.docs.isNotEmpty) {
        return 'pending';
      }

      return null;
    } catch (e) {
      print('خطأ في الحصول على حالة الطلب: $e');
      return null;
    }
  }

  // إضافة طبيب جديد (إرسال للمراجعة)
  static Future<bool> submitDoctorForReview(Doctor doctor) async {
    try {
      // التحقق من إمكانية الإضافة
      final canAdd = await canUserAddDoctor();
      if (!canAdd) {
        print('Cannot add doctor: user already has a clinic or pending request');
        return false;
      }

      // إرسال إلى مجموعة المراجعة
      await _firestore
          .collection('pending_doctors')
          .add(doctor.toFirestore());
      return true;
    } catch (e) {
      print('خطأ في إرسال الطبيب للمراجعة: $e');
      return false;
    }
  }

  // إضافة طبيب جديد (للتوافق مع الكود القديم، لكن الآن يرسل للمراجعة)
  static Future<bool> addDoctor(Doctor doctor) async {
    return await submitDoctorForReview(doctor);
  }

  // تحديث معلومات الطبيب
  static Future<bool> updateDoctor(String doctorId, Doctor doctor) async {
    try {
      await _firestore
          .collection(_doctorsCollection)
          .doc(doctorId)
          .update(doctor.toFirestore());
      return true;
    } catch (e) {
      print('خطأ في تحديث الطبيب: $e');
      return false;
    }
  }

  // حذف طبيب (تعطيل)
  static Future<bool> deactivateDoctor(String doctorId) async {
    try {
      await _firestore
          .collection(_doctorsCollection)
          .doc(doctorId)
          .update({'isActive': false});
      return true;
    } catch (e) {
      print('خطأ في تعطيل الطبيب: $e');
      return false;
    }
  }

  // حذف طبيب نهائياً من قاعدة البيانات
  static Future<bool> permanentlyDeleteDoctor(String doctorId) async {
    try {
      // أولاً، حذف جميع الحجوزات المتعلقة بهذا الطبيب
      final bookingsQuery = await _firestore
          .collection(_bookingsCollection)
          .where('doctorId', isEqualTo: doctorId)
          .get();

      // حذف جميع الحجوزات
      for (var doc in bookingsQuery.docs) {
        await doc.reference.delete();
      }

      // ثم حذف الطبيب نفسه
      await _firestore
          .collection(_doctorsCollection)
          .doc(doctorId)
          .delete();

      return true;
    } catch (e) {
      print('خطأ في حذف الطبيب نهائياً: $e');
      return false;
    }
  }

  // إنشاء حجز جديد
  static Future<String?> createBooking(Booking booking) async {
    try {
      final docRef = await _firestore
          .collection(_bookingsCollection)
          .add(booking.toFirestore());
      return docRef.id;
    } catch (e) {
      print('خطأ في إنشاء الحجز: $e');
      return null;
    }
  }

  // الحصول على حجوزات طبيب معين
  static Future<List<Booking>> getDoctorBookings(String doctorId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_bookingsCollection)
          .where('doctorId', isEqualTo: doctorId)
          .orderBy('appointmentDate', descending: false)
          .get();

      return querySnapshot.docs
          .map((doc) => Booking.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('خطأ في جلب حجوزات الطبيب: $e');
      return [];
    }
  }

  // الحصول على حجوزات المستخدم
  static Future<List<Booking>> getUserBookings(String userId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_bookingsCollection)
          .where('patientUserId', isEqualTo: userId)
          .orderBy('appointmentDate', descending: false)
          .get();

      return querySnapshot.docs
          .map((doc) => Booking.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('خطأ في جلب حجوزات المستخدم: $e');
      return [];
    }
  }

  // تحديث حالة الحجز
  static Future<bool> updateBookingStatus(String bookingId, BookingStatus status) async {
    try {
      await _firestore
          .collection(_bookingsCollection)
          .doc(bookingId)
          .update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('خطأ في تحديث حالة الحجز: $e');
      return false;
    }
  }

  // التحقق من توفر موعد
  static Future<bool> isTimeSlotAvailable(
    String doctorId,
    DateTime date,
    String time,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection(_bookingsCollection)
          .where('doctorId', isEqualTo: doctorId)
          .where('appointmentDate', isEqualTo: Timestamp.fromDate(
            DateTime(date.year, date.month, date.day)))
          .where('appointmentTime', isEqualTo: time)
          .where('status', whereIn: ['pending', 'approved'])
          .get();

      return querySnapshot.docs.isEmpty;
    } catch (e) {
      print('خطأ في التحقق من توفر الموعد: $e');
      return false;
    }
  }

  // الحصول على الأطباء للمستخدم الطبيب الحالي (المعتمدين فقط)
  static Future<List<Doctor>> getCurrentUserDoctors() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return [];

      final querySnapshot = await _firestore
          .collection(_doctorsCollection)
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'approved')
          .orderBy('createdAt', descending: false)
          .get();

      return querySnapshot.docs
          .map((doc) => Doctor.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('خطأ في جلب أطباء المستخدم الحالي: $e');
      return [];
    }
  }

  // الحصول على الحجوزات للأطباء التابعين للمستخدم الحالي (المعتمدين فقط)
  static Future<List<Booking>> getCurrentUserDoctorBookings() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return [];

      // أولاً جلب معرفات الأطباء التابعين للمستخدم الحالي والمعتمدين
      final doctorsSnapshot = await _firestore
          .collection(_doctorsCollection)
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'approved')
          .get();

      final doctorIds = doctorsSnapshot.docs.map((doc) => doc.id).toList();

      if (doctorIds.isEmpty) return [];

      // جلب الحجوزات لهذه الأطباء
      final querySnapshot = await _firestore
          .collection(_bookingsCollection)
          .where('doctorId', whereIn: doctorIds)
          .orderBy('appointmentDate', descending: false)
          .get();

      return querySnapshot.docs
          .map((doc) => Booking.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('خطأ في جلب حجوزات أطباء المستخدم: $e');
      return [];
    }
  }

  // جلب الحجوزات المعلقة للطبيب
  static Stream<List<Booking>> getPendingBookingsStream(String doctorId) {
    return _firestore
        .collection(_bookingsCollection)
        .where('doctorId', isEqualTo: doctorId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Booking.fromFirestore(doc.data(), doc.id))
            .toList());
  }

  // إنشاء مواعيد متاحة بناءً على ساعات العمل
  static List<String> generateAvailableTimeSlots(
    String openTime,
    String closeTime,
    {int intervalMinutes = 30}
  ) {
    final List<String> timeSlots = [];
    
    try {
      final openHour = int.parse(openTime.split(':')[0]);
      final openMinute = int.parse(openTime.split(':')[1]);
      final closeHour = int.parse(closeTime.split(':')[0]);
      final closeMinute = int.parse(closeTime.split(':')[1]);

      DateTime current = DateTime(2023, 1, 1, openHour, openMinute);
      final end = DateTime(2023, 1, 1, closeHour, closeMinute);

      while (current.isBefore(end)) {
        final timeString = '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}';
        timeSlots.add(timeString);
        current = current.add(Duration(minutes: intervalMinutes));
      }
    } catch (e) {
      print('خطأ في إنشاء المواعيد المتاحة: $e');
    }

    return timeSlots;
  }

  // جلب الأطباء المعلقين للمراجعة (للمشرفين فقط)
  static Future<List<Doctor>> getPendingDoctors() async {
    try {
      final querySnapshot = await _firestore
          .collection('pending_doctors')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => Doctor.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('خطأ في جلب الأطباء المعلقين: $e');
      return [];
    }
  }

  // موافقة على طبيب من قبل المشرف
  static Future<bool> approveDoctor(String pendingDoctorId, String adminId) async {
    try {
      // جلب بيانات الطبيب المعلق
      final pendingDoc = await _firestore
          .collection('pending_doctors')
          .doc(pendingDoctorId)
          .get();

      if (!pendingDoc.exists) {
        print('الطبيب غير موجود');
        return false;
      }

      final doctorData = pendingDoc.data()!;

      // تحديث بيانات الطبيب للنشر
      doctorData['isActive'] = true;
      doctorData['status'] = 'approved';
      doctorData['reviewedAt'] = FieldValue.serverTimestamp();
      doctorData['reviewedBy'] = adminId;

      // نقل الطبيب إلى مجموعة الأطباء الرئيسية
      final newDoctorRef = await _firestore
          .collection(_doctorsCollection)
          .add(doctorData);

      // حذف الطبيب من المعلقين
      await _firestore
          .collection('pending_doctors')
          .doc(pendingDoctorId)
          .delete();

      return true;
    } catch (e) {
      print('خطأ في الموافقة على الطبيب: $e');
      return false;
    }
  }

  // رفض طبيب من قبل المشرف
  static Future<bool> rejectDoctor(String pendingDoctorId, String adminId, String reason) async {
    try {
      await _firestore
          .collection('pending_doctors')
          .doc(pendingDoctorId)
          .update({
        'status': 'rejected',
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': adminId,
        'rejectionReason': reason,
      });

      return true;
    } catch (e) {
      print('خطأ في رفض الطبيب: $e');
      return false;
    }
  }
}
