import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/database_service.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_profile_page.dart';

class AuctionPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const AuctionPage({Key? key, required this.product}) : super(key: key);

  @override
  State<AuctionPage> createState() => _AuctionPageState();
}

class _AuctionPageState extends State<AuctionPage> {
  final TextEditingController _bidController = TextEditingController();
  List<Map<String, dynamic>> _bids = [];
  bool _isLoading = false;
  Timer? _timer;
  Duration _timeRemaining = Duration.zero;
  StreamSubscription? _productSubscription;
  StreamSubscription? _bidsSubscription;
  Map<String, dynamic>? _currentProduct;
  bool _userHasBid = false;


  // Cache لبيانات المستخدمين لتحسين الأداء
  final Map<String, Map<String, dynamic>> _usersCache = {};
  Map<String, dynamic>? _auctionOwnerData;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    _calculateTimeRemaining(); // حساب الوقت المتبقي فوراً
    _loadUserBidStatusFromCache(); // تحميل حالة المستخدم من cache فوراً
    _loadAuctionOwnerData(); // تحميل بيانات صاحب المزاد
    _setupRealTimeListeners(); // إعداد المستمعين المباشرين
    _startTimer();


  }

  @override
  void dispose() {
    _timer?.cancel();
    _productSubscription?.cancel();
    _bidsSubscription?.cancel();
    _bidController.dispose();
    super.dispose();
  }

  void _setupRealTimeListeners() {
    final user = FirebaseAuth.instance.currentUser;

    // مستمع تحديثات المنتج (السعر الحالي، حالة المزاد، إلخ)
    _productSubscription = FirebaseFirestore.instance
        .collection('products')
        .doc(widget.product['id'])
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _currentProduct = snapshot.data()!;
          _currentProduct!['id'] = snapshot.id;
        });
        _calculateTimeRemaining();
      }
    });

    // مستمع تحديثات العروض المباشرة
    _bidsSubscription = FirebaseFirestore.instance
        .collection('products')
        .doc(widget.product['id'])
        .collection('bids')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) async {
      if (mounted) {
        List<Map<String, dynamic>> bids = [];

        for (var doc in snapshot.docs) {
          final bidData = doc.data();
          bidData['id'] = doc.id;

          // جلب بيانات المزايد مع cache للأداء
          final bidderId = bidData['bidderId'];
          if (_usersCache.containsKey(bidderId)) {
            // استخدام البيانات من cache
            final cachedUser = _usersCache[bidderId]!;
            bidData['bidderDisplayName'] = cachedUser['displayName'] ?? 'مستخدم';
            bidData['bidderProfileImage'] = cachedUser['profileImageUrl'] ?? '';
          } else {
            // جلب البيانات وحفظها في cache
            try {
              final bidderData = await DatabaseService.getUserFromFirestore(bidderId);
              if (bidderData != null) {
                _usersCache[bidderId] = bidderData;
                bidData['bidderDisplayName'] = bidderData['displayName'] ?? 'مستخدم';
                bidData['bidderProfileImage'] = bidderData['profileImageUrl'] ?? '';
              } else {
                bidData['bidderDisplayName'] = 'مستخدم';
                bidData['bidderProfileImage'] = '';
              }
            } catch (e) {
              bidData['bidderDisplayName'] = 'مستخدم';
              bidData['bidderProfileImage'] = '';
            }
          }

          bids.add(bidData);
        }

        final newUserHasBid = user != null && bids.any((bid) => bid['bidderId'] == user.uid);

        setState(() {
          _bids = bids;
          // التحقق من حالة المستخدم الحالي
          _userHasBid = newUserHasBid;
          _isLoading = false;
        });

        // حفظ حالة المستخدم في cache
        _saveUserBidStatusToCache(newUserHasBid);
      }
    });
  }

  void _startTimer() {
    _calculateTimeRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _calculateTimeRemaining();
        if (_timeRemaining.inSeconds <= 0) {
          _timer?.cancel();
          _endAuction();
        }
      }
    });
  }

  void _calculateTimeRemaining() {
    if (_currentProduct == null) return;

    final endTime = (_currentProduct!['auctionEndTime'] as Timestamp).toDate();
    final now = DateTime.now();

    setState(() {
      _timeRemaining = endTime.isAfter(now) ? endTime.difference(now) : Duration.zero;
    });
  }

  // تحميل حالة المستخدم من cache محلي
  Future<void> _loadUserBidStatusFromCache() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'user_bid_${widget.product['id']}_${user.uid}';
      final hasBid = prefs.getBool(cacheKey) ?? false;

      if (mounted) {
        setState(() {
          _userHasBid = hasBid;
        });
      }
    } catch (e) {
      // في حالة فشل تحميل cache، سيتم التحقق عبر Firebase
    }
  }

  // حفظ حالة المستخدم في cache محلي
  Future<void> _saveUserBidStatusToCache(bool hasBid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'user_bid_${widget.product['id']}_${user.uid}';
      await prefs.setBool(cacheKey, hasBid);
    } catch (e) {
      // تجاهل أخطاء cache
    }
  }

  // تحميل بيانات صاحب المزاد
  Future<void> _loadAuctionOwnerData() async {
    try {
      final ownerData = await DatabaseService.getUserFromFirestore(widget.product['userId']);
      if (mounted && ownerData != null) {
        setState(() {
          _auctionOwnerData = ownerData;
        });
      }
    } catch (e) {
      // تجاهل أخطاء تحميل بيانات المالك
    }
  }



  Future<void> _placeBid() async {
    if (_bidController.text.trim().isEmpty) {
      _showErrorSnackBar('يرجى إدخال مبلغ العرض');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showErrorSnackBar('يجب تسجيل الدخول أولاً');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await DatabaseService.placeBid(
        productId: widget.product['id'],
        bidderId: user.uid,
        bidAmount: _bidController.text.trim(),
      );

      // تحديث الحالة فوراً وحفظها في cache
      setState(() {
        _userHasBid = true;
        _isLoading = false;
      });

      // حفظ الحالة في cache فوراً
      _saveUserBidStatusToCache(true);

      _bidController.clear();
      // البيانات ستتحدث تلقائياً عبر real-time streams
      _showSuccessSnackBar('تم تقديم العرض بنجاح!');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _endAuction() async {
    try {
      await DatabaseService.endAuction(widget.product['id']);
      if (mounted) {
        _showSuccessSnackBar('انتهت المزايدة!');
      }
    } catch (e) {
      print('خطأ في إنهاء المزاد: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatTimeRemaining() {
    if (_timeRemaining.inSeconds <= 0) return 'انتهت';

    final days = _timeRemaining.inDays;
    final hours = _timeRemaining.inHours % 24;
    final minutes = _timeRemaining.inMinutes % 60;
    final seconds = _timeRemaining.inSeconds % 60;

    if (days > 0) {
      return '$days يوم';
    } else if (hours > 0) {
      return '$hours ساعة';
    } else if (minutes > 0) {
      return '$minutes دقيقة';
    } else {
      return '$seconds ثانية';
    }
  }

  @override
  Widget build(BuildContext context) {
    // استخدام بيانات المنتج الأولية مباشرة، ثم التحديث عبر streams
    final product = _currentProduct ?? widget.product;

    final isAuctionActive = product['auctionStatus'] == 'active' && _timeRemaining.inSeconds > 0;
    final currentPrice = product['auctionCurrentPrice'] ?? product['auctionStartPrice'];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'مزايدة',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
      ),
      body: Column(
        children: [
          // معلومات المنتج والمزايدة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['title'] ?? '',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'السعر الحالي',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$currentPrice د.ع',
                            style: GoogleFonts.cairo(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'الوقت المتبقي',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatTimeRemaining(),
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isAuctionActive ? Colors.red : Colors.grey,
                            ),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // معلومات صاحب المزاد
                if (_auctionOwnerData != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: _auctionOwnerData!['profileImageUrl']?.isNotEmpty == true
                              ? NetworkImage(_auctionOwnerData!['profileImageUrl'])
                              : null,
                          child: _auctionOwnerData!['profileImageUrl']?.isEmpty != false
                              ? Icon(Icons.person, color: Colors.grey[600])
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'صاحب المزاد',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _auctionOwnerData!['displayName'] ?? 'مستخدم',
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.verified_user,
                          color: Colors.blue[600],
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Text(
                  'عدد العروض: ${product['auctionBidsCount'] ?? 0}',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // قسم تقديم العرض (يظهر فقط إذا كان المزاد نشط والمستخدم ليس البائع ولم يقدم عرض من قبل)
          if (isAuctionActive &&
              product['userId'] != FirebaseAuth.instance.currentUser?.uid &&
              !_userHasBid)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bidController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        hintText: 'أدخل عرضك',
                        hintStyle: GoogleFonts.cairo(color: Colors.grey),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      style: GoogleFonts.cairo(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _placeBid,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'عرض',
                            style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),

          // رسالة توضيحية إذا لم يستطع المستخدم المزايدة
          if (isAuctionActive &&
              (product['userId'] == FirebaseAuth.instance.currentUser?.uid || _userHasBid))
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                border: Border.all(color: Colors.orange[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      product['userId'] == FirebaseAuth.instance.currentUser?.uid
                          ? 'لا يمكنك المزايدة على منتجك الخاص'
                          : 'أنت مقدم عرض في هذه المزايدة',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // قائمة العروض
          Expanded(
            child: Column(
              children: [
                // رسالة توضيحية لصاحب المزاد
                if (product['userId'] == FirebaseAuth.instance.currentUser?.uid && _bids.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'اضغط على أي عرض لعرض ملف المزايد الشخصي',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: _bids.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.gavel,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد عروض بعد',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              'كن أول من يقدم عرضاً!',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _bids.length,
                        itemBuilder: (context, index) {
                          final bid = _bids[index];
                          final isHighest = index == 0;
                          final isAuctionOwner = product['userId'] == FirebaseAuth.instance.currentUser?.uid;

                          return GestureDetector(
                            onTap: isAuctionOwner ? () {
                              // السماح لصاحب المزاد بالانتقال لصفحة المزايد
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserProfilePage(
                                    userId: bid['bidderId'],
                                    initialDisplayName: bid['bidderDisplayName'] ?? 'مستخدم',
                                    initialProfileImage: bid['bidderProfileImage'] ?? '',
                                  ),
                                ),
                              );
                            } : null,
                            child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isHighest ? Colors.green[50] : Colors.white,
                              border: Border.all(
                                color: isHighest ? Colors.green : Colors.grey[300]!,
                                width: isHighest ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              // إضافة ظل للإشارة إلى إمكانية النقر لصاحب المزاد
                              boxShadow: isAuctionOwner ? [
                                BoxShadow(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ] : null,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundImage: bid['bidderProfileImage']?.isNotEmpty == true
                                          ? NetworkImage(bid['bidderProfileImage'])
                                          : null,
                                      child: bid['bidderProfileImage']?.isEmpty != false
                                          ? Icon(Icons.person, color: Colors.grey[600], size: 18)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  bid['bidderDisplayName'] ?? 'مستخدم',
                                                  style: GoogleFonts.cairo(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isHighest) ...[
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    'أعلى عرض',
                                                    style: GoogleFonts.cairo(
                                                      fontSize: 8,
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${bid['amount']} د.ع',
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: isHighest ? Colors.green : Colors.black,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (bid['timestamp'] != null)
                                                Text(
                                                  _formatBidTime(bid['timestamp']),
                                                  style: GoogleFonts.cairo(
                                                    fontSize: 11,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBidTime(Timestamp timestamp) {
    final bidTime = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(bidTime);

    if (difference.inMinutes < 1) {
      return 'الآن';
    } else if (difference.inHours < 1) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inDays < 1) {
      return 'منذ ${difference.inHours} ساعة';
    } else {
      return 'منذ ${difference.inDays} يوم';
    }
  }
}
