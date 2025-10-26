import 'package:cloud_firestore/cloud_firestore.dart';

enum BookingStatus {
  pending,
  approved,
  rejected,
  completed,
  cancelled
}

class Booking {
  final String id;
  final String doctorId;
  final String doctorName;
  final String patientName;
  final String patientPhone;
  final String? patientUserId; // معرف المستخدم إذا كان مسجل دخول
  final DateTime appointmentDate;
  final String appointmentTime;
  final String? notes;
  final BookingStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Booking({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.patientName,
    required this.patientPhone,
    this.patientUserId,
    required this.appointmentDate,
    required this.appointmentTime,
    this.notes,
    this.status = BookingStatus.pending,
    required this.createdAt,
    this.updatedAt,
  });

  factory Booking.fromFirestore(Map<String, dynamic> data, String id) {
    return Booking(
      id: id,
      doctorId: data['doctorId'] ?? '',
      doctorName: data['doctorName'] ?? '',
      patientName: data['patientName'] ?? '',
      patientPhone: data['patientPhone'] ?? '',
      patientUserId: data['patientUserId'],
      appointmentDate: (data['appointmentDate'] as Timestamp).toDate(),
      appointmentTime: data['appointmentTime'] ?? '',
      notes: data['notes'],
      status: _statusFromString(data['status'] ?? 'pending'),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null 
          ? (data['updatedAt'] as Timestamp).toDate() 
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'doctorId': doctorId,
      'doctorName': doctorName,
      'patientName': patientName,
      'patientPhone': patientPhone,
      'patientUserId': patientUserId,
      'appointmentDate': Timestamp.fromDate(appointmentDate),
      'appointmentTime': appointmentTime,
      'notes': notes,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  static BookingStatus _statusFromString(String status) {
    switch (status) {
      case 'pending':
        return BookingStatus.pending;
      case 'approved':
        return BookingStatus.approved;
      case 'rejected':
        return BookingStatus.rejected;
      case 'completed':
        return BookingStatus.completed;
      case 'cancelled':
        return BookingStatus.cancelled;
      default:
        return BookingStatus.pending;
    }
  }

  String get statusInArabic {
    switch (status) {
      case BookingStatus.pending:
        return 'في الانتظار';
      case BookingStatus.approved:
        return 'مقبول';
      case BookingStatus.rejected:
        return 'مرفوض';
      case BookingStatus.completed:
        return 'مكتمل';
      case BookingStatus.cancelled:
        return 'ملغي';
    }
  }

  Booking copyWith({
    String? id,
    String? doctorId,
    String? doctorName,
    String? patientName,
    String? patientPhone,
    String? patientUserId,
    DateTime? appointmentDate,
    String? appointmentTime,
    String? notes,
    BookingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Booking(
      id: id ?? this.id,
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      patientName: patientName ?? this.patientName,
      patientPhone: patientPhone ?? this.patientPhone,
      patientUserId: patientUserId ?? this.patientUserId,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      appointmentTime: appointmentTime ?? this.appointmentTime,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper method to check if booking is on a specific date
  bool isOnDate(DateTime date) {
    return appointmentDate.year == date.year &&
           appointmentDate.month == date.month &&
           appointmentDate.day == date.day;
  }

  // Helper method to check if booking is in the future
  bool isFuture() {
    final now = DateTime.now();
    final appointmentDateTime = DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
      int.parse(appointmentTime.split(':')[0]),
      int.parse(appointmentTime.split(':')[1]),
    );
    return appointmentDateTime.isAfter(now);
  }
}