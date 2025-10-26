import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_service.dart';
import 'user_profile_page.dart';
import 'edit_product_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
    _loadNotifications().then((_) {
      // تحديد جميع الإشعارات كمقروءة عند فتح الصفحة
      _markAllAsRead();
    });
  }

  Future<void> _loadNotificationPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      });
    } catch (e) {
      print('خطأ في تحميل إعدادات الإشعارات: $e');
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: currentUser.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      List<Map<String, dynamic>> notifications = [];
      for (var doc in querySnapshot.docs) {
        // Fix: Properly cast the data
        final notificationData = doc.data() as Map<String, dynamic>;
        notificationData['id'] = doc.id;

        // جلب بيانات المستخدم الذي أرسل الإشعار
        if (notificationData['fromUserId'] != null) {
          final fromUserData = await DatabaseService.getUserFromFirestore(
              notificationData['fromUserId']
          );
          notificationData['fromUserData'] = fromUserData;
        }

        notifications.add(notificationData);
      }

      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل الإشعارات: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});
    } catch (e) {
      print('خطأ في تحديد الإشعار كمقروء: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final batch = FirebaseFirestore.instance.batch();
      final querySnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: currentUser.uid)
          .where('isRead', isEqualTo: false)
          .get();

      for (var doc in querySnapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }

      await batch.commit();
      print('تم تحديد جميع الإشعارات كمقروءة');
    } catch (e) {
      print('خطأ في تحديد جميع الإشعارات كمقروءة: $e');
    }
  }

  Future<void> _deleteAllNotifications() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final batch = FirebaseFirestore.instance.batch();
      final querySnapshot = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حذف جميع الإشعارات',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.green,
        ),
      );

      // إعادة تحميل الإشعارات
      _loadNotifications();
    } catch (e) {
      print('خطأ في حذف جميع الإشعارات: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ في حذف الإشعارات',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _followBack(String userId) async {
    try {
      // استخدام DatabaseService.followUser بدلاً من الكود المباشر
      await DatabaseService.followUser(userId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم رد المتابعة بنجاح',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.green,
        ),
      );

      // تحديث الإشعارات
      _loadNotifications();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ في رد المتابعة',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _checkIfFollowing(String targetUserId) async {
    try {
      // استخدام DatabaseService.isFollowing للتحقق من المتابعة
      return await DatabaseService.isFollowing(targetUserId);
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'الإشعارات',
          style: GoogleFonts.cairo(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text(
                        'تأكيد الحذف',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: Text(
                        'هل أنت متأكد من حذف جميع الإشعارات؟\nلا يمكن التراجع عن هذا الإجراء.',
                        style: GoogleFonts.cairo(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'إلغاء',
                            style: GoogleFonts.cairo(
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _deleteAllNotifications();
                          },
                          child: Text(
                            'حذف',
                            style: GoogleFonts.cairo(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              tooltip: 'حذف جميع الإشعارات',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_notificationsEnabled
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_off,
              size: 60,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'الإشعارات معطلة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'يمكنك تفعيل الإشعارات من قسم الإعدادات',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'انتقل إلى الإعدادات > الحساب > الإشعارات لتفعيلها',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: Colors.grey[400],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      )
          : _notifications.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 60,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد إشعارات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadNotifications,
        child: ListView.builder(
          itemCount: _notifications.length,
          itemBuilder: (context, index) {
            final notification = _notifications[index];
            return _buildNotificationItem(notification);
          },
        ),
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notification) {
    // تحويل البيانات بشكل آمن
    final fromUserDataRaw = notification['fromUserData'];
    final Map<String, dynamic> fromUserData = fromUserDataRaw != null && fromUserDataRaw is Map
        ? Map<String, dynamic>.from(fromUserDataRaw)
        : <String, dynamic>{};

    final type = notification['type'] ?? '';
    final isRead = notification['isRead'] ?? false;
    final createdAt = notification['createdAt'] as Timestamp?;

    // تحويل productData بشكل آمن
    Map<String, dynamic>? productData;
    final productDataRaw = notification['productData'];
    if (productDataRaw != null && productDataRaw is Map) {
      productData = Map<String, dynamic>.from(productDataRaw);
    }

    // تحديد الصورة الرئيسية بناءً على نوع الإشعار
    Widget leadingWidget;
    if (type == 'product_approved' || type == 'product_rejected') {
      // عرض صورة المنتج للإشعارات المتعلقة بالمنتجات
      leadingWidget = GestureDetector(
        onTap: () => _handleProductNotificationTap(notification),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[200],
          ),
          child: productData?['imageUrl'] != null
              ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              productData!['imageUrl'],
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.shopping_bag,
                color: Colors.grey[600],
              ),
            ),
          )
              : Icon(
            Icons.shopping_bag,
            color: Colors.grey[600],
          ),
        ),
      );
    } else {
      // عرض صورة المستخدم للإشعارات الأخرى
      leadingWidget = GestureDetector(
        onTap: () {
          if (notification['fromUserId'] != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfilePage(userId: notification['fromUserId']),
              ),
            );
          }
        },
        child: CircleAvatar(
          radius: 25,
          backgroundImage: fromUserData['profileImageUrl']?.isNotEmpty == true
              ? NetworkImage(fromUserData['profileImageUrl'])
              : null,
          child: fromUserData['profileImageUrl']?.isEmpty != false
              ? Icon(Icons.person, size: 25, color: Colors.grey[600])
              : null,
        ),
      );
    }

    return Container(
      color: isRead ? Colors.white : Colors.blue[50],
      child: ListTile(
        leading: leadingWidget,
        title: _buildNotificationTitle(notification, type, fromUserData),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (type == 'product_rejected' && notification['rejectionReason'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'السبب: ${notification['rejectionReason']}',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.red[600],
                  ),
                ),
              ),
            if (createdAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _getTimeAgo(createdAt.toDate()),
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
          ],
        ),
        trailing: _buildNotificationTrailing(type, notification),
        onTap: () {
          if (!isRead) {
            _markAsRead(notification['id']);
          }

          // التنقل بناءً على نوع الإشعار
          if (type == 'product_approved' || type == 'product_rejected') {
            _handleProductNotificationTap(notification);
          } else if (notification['fromUserId'] != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserProfilePage(userId: notification['fromUserId']),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildNotificationTitle(Map<String, dynamic> notification, String type, Map<String, dynamic> fromUserData) {
    if (type == 'product_approved' || type == 'product_rejected') {
      return Text(
        notification['title'] ?? '',
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          color: type == 'product_approved' ? Colors.green[700] : Colors.red[700],
          fontSize: 14,
        ),
      );
    } else {
      return RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: fromUserData['displayName'] ?? 'مستخدم',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: Colors.black,
                fontSize: 14,
              ),
            ),
            TextSpan(
              text: _getNotificationText(type),
              style: GoogleFonts.cairo(
                color: Colors.black87,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget? _buildNotificationTrailing(String type, Map<String, dynamic> notification) {
    if (type == 'follow') {
      return FutureBuilder<bool>(
        future: _checkIfFollowing(notification['fromUserId']),
        builder: (context, snapshot) {
          final isFollowing = snapshot.data ?? false;

          if (isFollowing) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'يتابع',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            );
          }

          return ElevatedButton(
            onPressed: () => _followBack(notification['fromUserId']),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              minimumSize: Size.zero,
            ),
            child: Text(
              'رد المتابعة',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      );
    } else if (type == 'product_rejected') {
      return GestureDetector(
        onTap: () => _handleProductNotificationTap(notification),
        child: Icon(
          Icons.edit_outlined,
          color: Colors.orange,
          size: 24,
        ),
      );
    } else if (type == 'product_approved') {
      return Icon(
        Icons.check_circle_outline,
        color: Colors.green,
        size: 24,
      );
    }
    return null;
  }

  void _handleProductNotificationTap(Map<String, dynamic> notification) {
    final type = notification['type'];

    // تحويل productData بشكل آمن
    Map<String, dynamic>? productData;
    final productDataRaw = notification['productData'];
    if (productDataRaw != null && productDataRaw is Map) {
      productData = Map<String, dynamic>.from(productDataRaw);
    }

    if (type == 'product_rejected' && notification['pendingProductId'] != null) {
      // الانتقال إلى صفحة تعديل المنتج المرفوض
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditProductPage(
            pendingProductId: notification['pendingProductId'],
            productData: productData ?? {},
          ),
        ),
      );
    } else if (type == 'product_approved' && notification['productId'] != null) {
      // لا نعرض أي رسالة للمنتجات المقبولة
      // يمكن إضافة انتقال إلى صفحة المنتج إذا لزم الأمر في المستقبل
    }
  }

  String _getNotificationText(String type) {
    switch (type) {
      case 'follow':
        return ' بدأ متابعتك';
      case 'like':
        return ' أعجب بمنشورك';
      case 'comment':
        return ' علق على منشورك';
      case 'product_approved':
        return 'تم قبول إعلانك';
      case 'product_rejected':
        return 'تم رفض إعلانك';
      case 'new_bid':
        return 'عرض جديد على مزايدتك';
      case 'outbid':
        return 'تم تجاوز عرضك';
      case 'auction_won':
        return 'فزت بالمزايدة';
      case 'auction_lost':
        return 'انتهت المزايدة';
      case 'auction_ended':
        return 'انتهت مزايدتك';
      default:
        return ' تفاعل معك';
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return 'منذ ${difference.inDays} ${difference.inDays == 1 ? 'يوم' : 'أيام'}';
    } else if (difference.inHours > 0) {
      return 'منذ ${difference.inHours} ${difference.inHours == 1 ? 'ساعة' : 'ساعات'}';
    } else if (difference.inMinutes > 0) {
      return 'منذ ${difference.inMinutes} ${difference.inMinutes == 1 ? 'دقيقة' : 'دقائق'}';
    } else {
      return 'الآن';
    }
  }
}