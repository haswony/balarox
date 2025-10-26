import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/database_service.dart';
import '../services/profile_update_service.dart';
import '../widgets/product_detail_shimmer.dart';
import '../widgets/rating_widget.dart';
import 'image_viewer_page.dart';
import 'user_profile_page.dart';
import 'chat_page.dart';
import 'auction_page.dart';

class ProductDetailPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  PageController _pageController = PageController();
  int _currentImageIndex = 0;
  StreamSubscription? _profileUpdateSubscription;
  StreamSubscription<DocumentSnapshot>? _publisherDataSubscription;
  Map<String, dynamic>? _publisherData;
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;
  bool _canReview = false;
  bool _isFavorite = false;
  bool _isFavoriteLoading = false;
  Timer? _autoSlideTimer;
  bool _isUserInteracting = false;

  String _formatDate(dynamic date) {
    if (date == null) return 'غير متوفر';
    if (date is Timestamp) {
      return date.toDate().toString().substring(0, 10);
    } else if (date is DateTime) {
      return date.toString().substring(0, 10);
    }
    return 'غير متوفر';
  }

  @override
  void initState() {
    super.initState();
    _loadPublisherData();
    _setupPublisherDataListener();
    _checkCanReview();
    _checkFavoriteStatus();
    _startAutoSlide();

    // تسجيل مشاهدة المنتج للتوصيات
    DatabaseService.recordProductInteraction(
      productId: widget.product['id'] ?? '',
      interactionType: 'view',
      category: widget.product['category'],
    );



    // الاستماع لتحديثات الصورة الشخصية
    _profileUpdateSubscription = ProfileUpdateService().profileImageUpdates.listen((userId) {
      if (widget.product['userId'] == userId) {
        // إعادة تحميل بيانات البائع عند تحديث صورته
        _loadPublisherData();
      }
    });
  }

  void _setupPublisherDataListener() {
    if (widget.product['userId'] != null) {
      _publisherDataSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(widget.product['userId'])
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          setState(() {
            _publisherData = snapshot.data()!;
          });
        }
      });
    }
  }



  Future<void> _checkFollowStatus() async {
    if (widget.product['userId'] != null) {
      final isFollowing = await DatabaseService.isFollowing(widget.product['userId']);
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_isFollowLoading || widget.product['userId'] == null) return;

    setState(() {
      _isFollowLoading = true;
    });

    try {
      if (_isFollowing) {
        await DatabaseService.unfollowUser(widget.product['userId']);
      } else {
        await DatabaseService.followUser(widget.product['userId']);
      }

      setState(() {
        _isFollowing = !_isFollowing;
      });
    } catch (e) {
      _showErrorSnackBar('خطأ في تحديث المتابعة: $e');
    } finally {
      setState(() {
        _isFollowLoading = false;
      });
    }
  }

  Future<void> _checkCanReview() async {
    if (widget.product['id'] != null && widget.product['userId'] != null) {
      final canReview = await DatabaseService.canReviewProduct(
        widget.product['id'],
        widget.product['userId'],
      );
      if (mounted) {
        setState(() {
          _canReview = canReview;
        });
      }
    }
  }

  Future<void> _loadPublisherData() async {
    if (widget.product['userId'] != null) {
      final userData = await DatabaseService.getUserFromFirestore(widget.product['userId']);
      if (mounted && userData != null) {
        setState(() {
          _publisherData = userData;
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkFavoriteStatus() async {
    if (widget.product['id'] != null) {
      final isFavorite = await DatabaseService.isProductInFavorites(widget.product['id']);
      if (mounted) {
        setState(() {
          _isFavorite = isFavorite;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isFavoriteLoading || widget.product['id'] == null) return;

    setState(() {
      _isFavoriteLoading = true;
    });

    try {
      final newFavoriteStatus = await DatabaseService.toggleFavorite(widget.product['id']);
      setState(() {
        _isFavorite = newFavoriteStatus;
      });
    } catch (e) {
      _showErrorSnackBar('خطأ في تحديث المفضلة: $e');
    } finally {
      setState(() {
        _isFavoriteLoading = false;
      });
    }
  }

  void _startAutoSlide() {
    final imageUrls = List<String>.from(widget.product['imageUrls'] ?? []);
    if (imageUrls.length <= 1) return; // لا حاجة للتلقائي إذا كانت صورة واحدة فقط

    _autoSlideTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isUserInteracting && mounted) {
        final nextPage = _currentImageIndex + 1;
        // إذا وصلنا للنهاية، نعود للبداية فوراً بدون animation
        if (nextPage >= imageUrls.length) {
          _pageController.jumpToPage(0);
        } else {
          _pageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      }
    });
  }

  void _stopAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
  }

  @override
  void dispose() {
    _stopAutoSlide();
    _pageController.dispose();
    _profileUpdateSubscription?.cancel();
    _publisherDataSubscription?.cancel();
    super.dispose();
  }

  Widget _buildAuctionInfo(Map<String, dynamic> product) {
    final currentPrice = product['auctionCurrentPrice'] ?? product['auctionStartPrice'];
    final endTime = product['auctionEndTime'] != null
        ? (product['auctionEndTime'] as Timestamp).toDate()
        : null;
    final isActive = product['auctionStatus'] == 'active' &&
        endTime != null &&
        DateTime.now().isBefore(endTime);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.gavel,
              color: Colors.orange,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'مزايدة',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$currentPrice د.ع',
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.green : Colors.grey,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        const SizedBox(height: 4),
        Text(
          isActive ? 'السعر الحالي' : 'انتهت المزايدة',
          style: GoogleFonts.cairo(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        if (isActive && endTime != null) ...[
          const SizedBox(height: 8),
          Text(
            'ينتهي في: ${_formatTimeRemaining(endTime)}',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'عدد العروض: ${product['auctionBidsCount'] ?? 0}',
          style: GoogleFonts.cairo(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),


      ],
    );
  }

  String _formatTimeRemaining(DateTime endTime) {
    final now = DateTime.now();
    final difference = endTime.difference(now);

    if (difference.isNegative) return 'انتهت';

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;

    if (days > 0) {
      return '$days يوم $hours ساعة';
    } else if (hours > 0) {
      return '$hours ساعة $minutes دقيقة';
    } else {
      return '$minutes دقيقة';
    }
  }

  // Function to format product posting time in English
  String _formatProductPostingTime(Timestamp timestamp) {
    final postTime = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(postTime);

    final days = difference.inDays;
    final hours = difference.inHours;
    final minutes = difference.inMinutes;
    final weeks = (days / 7).floor();
    final months = (days / 30).floor();
    final years = (days / 365).floor();

    if (years > 0) {
      return '$years year${years > 1 ? 's' : ''} ago';
    } else if (months > 0) {
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (weeks > 0) {
      return '$weeks week${weeks > 1 ? 's' : ''} ago';
    } else if (days > 0) {
      return '$days day${days > 1 ? 's' : ''} ago';
    } else if (hours > 0) {
      return '$hours hour${hours > 1 ? 's' : ''} ago';
    } else if (minutes > 0) {
      return '$minutes minute${minutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      _showErrorSnackBar('لا يمكن إجراء المكالمة');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.black),
          ),
        ),
        body: const ProductDetailShimmer(),
      );
    }

    final product = widget.product;
    final imageUrls = List<String>.from(product['imageUrls'] ?? []);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // App Bar مع الصور
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: Colors.white,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            actions: [
              IconButton(
                onPressed: _isFavoriteLoading ? null : _toggleFavorite,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: _showMoreOptions,
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.more_vert, color: Colors.white),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                children: [
                  // الصور
                  GestureDetector(
                    onPanDown: (_) {
                      _isUserInteracting = true;
                      _stopAutoSlide();
                    },
                    onPanEnd: (_) {
                      _isUserInteracting = false;
                      _startAutoSlide();
                    },
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentImageIndex = index;
                        });
                        // إعادة تشغيل العرض التلقائي من الموقع الجديد عند التفاعل اليدوي
                        if (_isUserInteracting) {
                          _stopAutoSlide();
                          _startAutoSlide();
                        }
                      },
                      itemCount: imageUrls.length,
                      itemBuilder: (context, index) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ImageViewerPage(
                                  imageUrls: imageUrls,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          },
                          child: Hero(
                            tag: 'product_image_$index',
                            child: Image.network(
                              imageUrls[index],
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  color: Colors.grey[100],
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                          : null,
                                      strokeWidth: 2,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[100],
                                  child: Icon(Icons.image_not_supported,
                                      size: 64, color: Colors.grey[400]),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // مؤشر الصور
                  if (imageUrls.length > 1)
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: imageUrls.asMap().entries.map((entry) {
                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                entry.key,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _currentImageIndex == entry.key
                                    ? Colors.white
                                    : Colors.white54,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // تفاصيل المنتج
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // السعر والعنوان
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // عرض معلومات المزايدة أو السعر العادي
                                if (product['isAuction'] == true) ...[
                                  _buildAuctionInfo(product),
                                ] else ...[
                                  Text(
                                    '${product['price']} د.ع',
                                    style: GoogleFonts.cairo(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              product['title'] ?? '',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                    ],
                  ),

                  // معلومات أساسية
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInfoRow('الفئة', product['category'] ?? ''),
                        const Divider(height: 16),
                        _buildInfoRow('الحالة', product['condition'] ?? ''),
                        const Divider(height: 16),
                        _buildInfoRow('الموقع', product['location'] ?? ''),
                        const Divider(height: 16),
                        _buildInfoRow('قابل للتفاوض', product['isNegotiable'] == true ? 'نعم' : 'لا'),

                        // Add product posting time in English with green color
                        if (product['createdAt'] != null) ...[
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Posted',
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                              Text(
                                _formatProductPostingTime(product['createdAt']),
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // معلومات المزايدة إذا كان مزايدة
                        if (product['isAuction'] == true) ...[
                          const Divider(height: 16),

                          // كلمة مزايدة
                          Row(
                            children: [
                              Icon(
                                Icons.gavel,
                                color: Colors.orange,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'مزايدة',
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          // تاريخ الانتهاء إذا كان نشط
                          if (product['auctionEndTime'] != null) ...[
                            Builder(
                              builder: (context) {
                                final endTime = product['auctionEndTime']?.toDate();
                                final isActive = endTime != null && endTime.isAfter(DateTime.now());

                                if (isActive && endTime != null) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _formatTimeRemaining(endTime),
                                            style: GoogleFonts.cairo(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.red,
                                            ),
                                            textAlign: TextAlign.left,
                                          ),
                                        ),
                                        Text(
                                          'ينتهي في',
                                          style: GoogleFonts.cairo(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'انتهت',
                                            style: GoogleFonts.cairo(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey,
                                            ),
                                            textAlign: TextAlign.left,
                                          ),
                                        ),
                                        Text(
                                          'حالة المزايدة',
                                          style: GoogleFonts.cairo(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                          ],

                          const SizedBox(height: 8),

                          // عدد العروض
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${product['auctionBidsCount'] ?? 0}',
                                    style: GoogleFonts.cairo(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                ),
                                Text(
                                  'عدد العروض',
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // الوصف
                  Text(
                    'الوصف',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      product['description'] ?? '',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // معلومات المعلن
                  Text(
                    'المعلن',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: GestureDetector(
                      onTap: () {
                        if (widget.product['userId'] != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfilePage(
                                userId: widget.product['userId'],
                                initialDisplayName: _publisherData?['displayName'] ?? product['userDisplayName'],
                                initialHandle: _publisherData?['handle'] ?? product['userHandle'],
                                initialProfileImage: _publisherData?['profileImageUrl'] ?? product['userProfileImage'],
                              ),
                            ),
                          );
                        }
                      },
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundImage: (_publisherData?['profileImageUrl'] ?? product['userProfileImage'])?.isNotEmpty == true
                                ? NetworkImage(_publisherData?['profileImageUrl'] ?? product['userProfileImage'])
                                : null,
                            child: (_publisherData?['profileImageUrl'] ?? product['userProfileImage'])?.isEmpty != false
                                ? Icon(Icons.person, size: 30, color: Colors.grey[600])
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      (_publisherData?['displayName'] ?? product['userDisplayName'])?.isNotEmpty == true
                                          ? (_publisherData?['displayName'] ?? product['userDisplayName'])
                                          : 'البائع',
                                      style: GoogleFonts.cairo(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                    if (_publisherData?['isVerified'] == true) ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.verified,
                                        color: Colors.blue,
                                        size: 18,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // عرض التقييم إذا كان موجوداً
                                if (_publisherData?['averageRating'] != null &&
                                    (_publisherData?['averageRating'] ?? 0) > 0) ...[
                                  RatingWidget(
                                    rating: (_publisherData?['averageRating'] ?? 0.0).toDouble(),
                                    totalReviews: _publisherData?['totalReviews'] ?? 0,
                                    size: 16,
                                  ),
                                ] else ...[
                                  Text(
                                    'منضم منذ ${_formatDate(_publisherData?['createdAt'])}',
                                    style: GoogleFonts.cairo(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
                        ],
                      ),
                    ),
                  ),

                  // زر إضافة تقييم إذا كان متاحاً
                  /* if (_canReview &&
                      widget.product['userId'] != FirebaseAuth.instance.currentUser?.uid) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showReviewDialog,
                        icon: const Icon(Icons.star_outline, color: Colors.white),
                        label: Text(
                          'قيّم البائع',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber[700],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ], */

                  const SizedBox(height: 100), // مساحة للأزرار السفلية
                ],
              ),
            ),
          ),
        ],
      ),

      // الأزرار السفلية
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          children: [
            // زر المزايدة (يظهر فقط للمزايدات النشطة)
            if (widget.product['isAuction'] == true) ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AuctionPage(product: widget.product),
                      ),
                    );
                  },
                  icon: const Icon(Icons.gavel, color: Colors.white),
                  label: Text(
                    'مزايدة',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],

            // زر الرسالة
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (widget.product['userId'] != null &&
                      widget.product['userId'] != FirebaseAuth.instance.currentUser?.uid) {
                    try {
                      // تسجيل تفاعل الرسالة للتوصيات
                      DatabaseService.recordProductInteraction(
                        productId: widget.product['id'] ?? '',
                        interactionType: 'message',
                        category: widget.product['category'],
                      );

                      // بدء محادثة من المنتج
                      final chatId = await DatabaseService.startChatFromProduct(
                        productId: widget.product['id'] ?? '',
                        sellerId: widget.product['userId'],
                        productTitle: widget.product['title'] ?? 'منتج',
                        productPrice: widget.product['price'] ?? '',
                        productLocation: widget.product['location'] ?? '',
                        productImageUrl: (widget.product['imageUrls'] as List?)?.isNotEmpty == true
                            ? widget.product['imageUrls'][0]
                            : '',
                      );

                      // الانتقال إلى صفحة الدردشة
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatPage(
                            chatId: chatId,
                            otherUserId: widget.product['userId'],
                            otherUserName: (_publisherData?['displayName'] ?? widget.product['userDisplayName'])?.isNotEmpty == true
                                ? (_publisherData?['displayName'] ?? widget.product['userDisplayName'])
                                : 'البائع',
                            otherUserImage: _publisherData?['profileImageUrl'] ?? widget.product['userProfileImage'] ?? '',
                            isVerified: _publisherData?['isVerified'] ?? false,
                          ),
                        ),
                      );
                    } catch (e) {
                      _showErrorSnackBar('خطأ في بدء المحادثة: $e');
                    }
                  }
                },
                icon: const Icon(Icons.message, color: Colors.white),
                label: Text(
                  'رسالة',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, // Changed to blue for better visibility
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // زر الاتصال
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  // تسجيل تفاعل الاتصال للتوصيات
                  DatabaseService.recordProductInteraction(
                    productId: widget.product['id'] ?? '',
                    interactionType: 'call',
                    category: widget.product['category'],
                  );

                  // البحث عن رقم الهاتف من بيانات المنشر أو المنتج
                  String? phoneNumber;

                  if (_publisherData?['phoneNumber']?.isNotEmpty == true) {
                    phoneNumber = _publisherData!['phoneNumber'];
                  } else if (product['userPhone']?.isNotEmpty == true) {
                    phoneNumber = product['userPhone'];
                  }

                  if (phoneNumber?.isNotEmpty == true) {
                    _makePhoneCall(phoneNumber!);
                  } else {
                    _showErrorSnackBar('رقم الهاتف غير متوفر');
                  }
                },
                icon: const Icon(Icons.phone, color: Colors.white),
                label: Text(
                  'اتصال',
                  style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Kept green but made it more prominent
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // شريط السحب
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // خيار الإبلاغ
            ListTile(
              leading: const Icon(
                Icons.flag_outlined,
                color: Colors.red,
                size: 28,
              ),
              title: Text(
                'الإبلاغ عن المنتج',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog();
              },
            ),
            const Divider(height: 1),
            // خيار المشاركة
            ListTile(
              leading: const Icon(
                Icons.share_outlined,
                color: Colors.blue,
                size: 28,
              ),
              title: Text(
                'مشاركة المنتج',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                // يمكن إضافة وظيفة المشاركة هنا
              },
            ),
            const Divider(height: 1),
            // خيار النسخ
            ListTile(
              leading: const Icon(
                Icons.link_outlined,
                color: Colors.green,
                size: 28,
              ),
              title: Text(
                'نسخ الرابط',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'تم نسخ الرابط',
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    String selectedReason = '';
    final reasons = [
      'منتج مزيف أو مقلد',
      'سعر غير منطقي',
      'وصف مضلل',
      'صور غير حقيقية',
      'منتج محظور أو غير قانوني',
      'احتيال أو نصب',
      'محتوى غير لائق',
      'أخرى',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    Expanded(
                      child: Text(
                        'الإبلاغ عن المنتج',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Subtitle
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'لماذا تريد الإبلاغ عن هذا المنتج؟',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Reasons list
              ...reasons.map((reason) => ListTile(
                onTap: () {
                  setModalState(() {
                    selectedReason = reason;
                  });
                },
                leading: Radio<String>(
                  value: reason,
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setModalState(() {
                      selectedReason = value!;
                    });
                  },
                  activeColor: Colors.blue,
                ),
                title: Text(
                  reason,
                  style: GoogleFonts.cairo(fontSize: 15),
                ),
              )).toList(),
              // Submit button
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: selectedReason.isEmpty
                      ? null
                      : () async {
                    Navigator.pop(context);
                    await _submitReport(selectedReason);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'إرسال البلاغ',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport(String reason) async {
    try {
      await DatabaseService.reportProduct(
        productId: widget.product['id'] ?? '',
        productOwnerId: widget.product['userId'] ?? '',
        reason: reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إرسال البلاغ وسيتم مراجعته',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل إرسال البلاغ',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }


}