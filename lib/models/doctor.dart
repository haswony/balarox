import 'package:cloud_firestore/cloud_firestore.dart';

class Doctor {
  final String id;
  final String name;
  final String specialty;
  final String? location;
  final String imageUrl;
  final String? clinicImageUrl;
  final String? certificateImageUrl; // صورة الشهادة الطبية
  final String openTime;
  final String closeTime;
  final bool isActive;
  final DateTime createdAt;
  final String userId; // معرف الطبيب كمستخدم
  final String status; // pending, approved, rejected
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;

  Doctor({
    required this.id,
    required this.name,
    required this.specialty,
    this.location,
    required this.imageUrl,
    this.clinicImageUrl,
    this.certificateImageUrl,
    required this.openTime,
    required this.closeTime,
    this.isActive = true,
    required this.createdAt,
    required this.userId,
    this.status = 'pending',
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  });

  factory Doctor.fromFirestore(Map<String, dynamic> data, String id) {
    DateTime createdAt;
    try {
      if (data['createdAt'] is int) {
        // If it's stored as milliseconds timestamp
        createdAt = DateTime.fromMillisecondsSinceEpoch(data['createdAt']);
      } else if (data['createdAt'] != null) {
        // If it's a Firestore Timestamp
        createdAt = data['createdAt'].toDate();
      } else {
        createdAt = DateTime.now();
      }
    } catch (e) {
      createdAt = DateTime.now();
    }
    
    DateTime? reviewedAt;
    try {
      if (data['reviewedAt'] != null) {
        reviewedAt = (data['reviewedAt'] as Timestamp).toDate();
      }
    } catch (e) {
      reviewedAt = null;
    }

    return Doctor(
      id: id,
      name: data['name'] ?? '',
      specialty: data['specialty'] ?? '',
      location: data['location'],
      imageUrl: data['imageUrl'] ?? '',
      clinicImageUrl: data['clinicImageUrl'],
      certificateImageUrl: data['certificateImageUrl'],
      openTime: data['openTime'] ?? '08:00',
      closeTime: data['closeTime'] ?? '18:00',
      isActive: data['isActive'] ?? true,
      createdAt: createdAt,
      userId: data['userId'] ?? '',
      status: data['status'] ?? 'pending',
      reviewedAt: reviewedAt,
      reviewedBy: data['reviewedBy'],
      rejectionReason: data['rejectionReason'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'specialty': specialty,
      'location': location,
      'imageUrl': imageUrl,
      'clinicImageUrl': clinicImageUrl,
      'certificateImageUrl': certificateImageUrl,
      'openTime': openTime,
      'closeTime': closeTime,
      'isActive': isActive,
      'createdAt': createdAt, // Firestore will automatically convert DateTime to Timestamp
      'userId': userId,
      'status': status,
      'reviewedAt': reviewedAt,
      'reviewedBy': reviewedBy,
      'rejectionReason': rejectionReason,
    };
  }

  Doctor copyWith({
    String? id,
    String? name,
    String? specialty,
    String? location,
    String? imageUrl,
    String? clinicImageUrl,
    String? certificateImageUrl,
    String? openTime,
    String? closeTime,
    bool? isActive,
    DateTime? createdAt,
    String? userId,
    String? status,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? rejectionReason,
  }) {
    return Doctor(
      id: id ?? this.id,
      name: name ?? this.name,
      specialty: specialty ?? this.specialty,
      location: location ?? this.location,
      imageUrl: imageUrl ?? this.imageUrl,
      clinicImageUrl: clinicImageUrl ?? this.clinicImageUrl,
      certificateImageUrl: certificateImageUrl ?? this.certificateImageUrl,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}
