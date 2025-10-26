import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/database_service.dart';
import '../widgets/shimmer_widget.dart';
import 'product_detail_page.dart';
import 'user_profile_page.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  List<Map<String, dynamic>> _favoriteProducts = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final favorites = await DatabaseService.getUserFavorites();
      if (mounted) {
        setState(() {
          _favoriteProducts = favorites;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل المفضلة: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshFavorites() async {
    setState(() {
      _isRefreshing = true;
    });

    try {
      final favorites = await DatabaseService.getUserFavorites();
      if (mounted) {
        setState(() {
          _favoriteProducts = favorites;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      print('خطأ في تحديث المفضلة: $e');
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(String productId) async {
    try {
      final isFavorite = await DatabaseService.toggleFavorite(productId);
      if (!isFavorite) {
        // إزالة المنتج من القائمة المحلية
        setState(() {
          _favoriteProducts.removeWhere((product) => product['id'] == productId);
        });
      }
    } catch (e) {
      print('خطأ في تبديل المفضلة: $e');
      // إعادة تحميل المفضلة في حالة الخطأ
      _loadFavorites();
    }
  }

  String _getAuctionTimeRemaining(Map<String, dynamic> product) {
    if (product['auctionEndTime'] == null) return '';

    try {
      final endTime = (product['auctionEndTime'] as Timestamp).toDate();
      final now = DateTime.now();
      final difference = endTime.difference(now);

      if (difference.isNegative) return 'انتهت';

      final days = difference.inDays;
      final hours = difference.inHours % 24;
      final minutes = difference.inMinutes % 60;

      if (days > 0) {
        return 'باقي $days يوم';
      } else if (hours > 0) {
        return 'باقي $hours ساعة';
      } else if (minutes > 0) {
        return 'باقي $minutes دقيقة';
      } else {
        return 'ينتهي قريباً';
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailPage(product: product),
          ),
        );
      },
      onLongPress: () {
        // الانتقال لملف المستخدم مع عرض المنتج
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfilePage(
              userId: product['userId'],
              initialDisplayName: product['userDisplayName'],
              initialProfileImage: product['userProfileImage'],
              featuredProduct: product,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // صورة المنتج
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                child: product['imageUrls']?.isNotEmpty == true
                    ? CachedNetworkImage(
                  imageUrl: product['imageUrls'][0],
                  fit: BoxFit.cover,
                  placeholder: (context, url) => ShimmerWidget(
                    child: Container(
                      color: Colors.grey[100],
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[100],
                    child: Icon(Icons.shopping_bag_outlined,
                        color: Colors.grey[400], size: 40),
                  ),
                )
                    : Container(
                  color: Colors.grey[100],
                  child: Icon(Icons.shopping_bag_outlined,
                      color: Colors.grey[400], size: 40),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // معلومات المنتج
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // العنوان
                  Text(
                    product['title'] ?? '',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // السعر أو معلومات المزايدة
                  if (product['isAuction'] == true) ...[
                    // عرض معلومات المزايدة
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'مزايدة',
                            style: GoogleFonts.cairo(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${product['auctionCurrentPrice'] ?? product['auctionStartPrice']} د.ع',
                            style: GoogleFonts.cairo(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // عرض حالة المزايدة
                    if (product['auctionStatus'] == 'active') ...[
                      const SizedBox(height: 2),
                      Text(
                        _getAuctionTimeRemaining(product),
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          color: Colors.red[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ] else ...[
                    // عرض السعر العادي
                    Text(
                      '${product['price']} د.ع',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],

                  const SizedBox(height: 2),

                  // الموقع
                  Text(
                    product['location'] ?? '',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'المفضلة',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refreshFavorites,
            icon: const Icon(Icons.refresh, color: Colors.black),
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _refreshFavorites,
        child: _isLoading && !_isRefreshing
            ? Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: 8,
            itemBuilder: (context, index) => const ProductShimmer(),
          ),
        )
            : _favoriteProducts.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_border,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد إعلانات مفضلة',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'اضغط على القلب في صفحة التفاصيل لإضافة الإعلانات المفضلة',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
            : Padding(
          padding: const EdgeInsets.all(8),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _favoriteProducts.length,
            itemBuilder: (context, index) {
              final product = _favoriteProducts[index];
              return Stack(
                children: [
                  _buildProductCard(product),
                  // زر إزالة من المفضلة
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => _toggleFavorite(product['id']),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.red,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}