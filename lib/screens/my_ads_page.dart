import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'product_detail_page.dart';
import '../services/database_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/shimmer_widget.dart';

class MyAdsPage extends StatefulWidget {
  const MyAdsPage({super.key});

  @override
  State<MyAdsPage> createState() => _MyAdsPageState();
}

class _MyAdsPageState extends State<MyAdsPage> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _activeAds = [];
  bool _isLoading = true;
  Timer? _timer;
  StreamSubscription<QuerySnapshot>? _adsSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadMyAds();
    _startTimer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _timer?.cancel();
    _adsSubscription?.cancel();
    super.dispose();
  }

  void _startTimer() {
    // بدء مؤقت لتحديث حالة المنتجات المنتهية (كل ثانية للتحديث الفوري)
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        DatabaseService.updateExpiredProductsStatus().then((_) {
          // إعادة تحميل البيانات بعد تحديث الحالة
          _loadUserProducts();
        });
      }
    });
  }
  

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // إعادة تحميل البيانات عند العودة للصفحة
    _loadMyAds();
  }

  void _setupRealtimeListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // إلغاء الاشتراك السابق
    _adsSubscription?.cancel();
    
    // تحميل المنتجات باستخدام الدوال الجديدة
    _loadUserProducts();
  }
  
  Future<void> _loadUserProducts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // تحميل المنتجات النشطة فقط
      final activeProducts = await DatabaseService.getUserActiveProducts(userId: user.uid);

      if (mounted) {
        setState(() {
          _activeAds = activeProducts;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('خطأ في تحميل منتجات المستخدم: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMyAds() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    
    // إعداد المستمع للتحديثات الفورية
    _setupRealtimeListener();
  }



  Future<void> _deleteAd(String productId) async {
    // حذف فوري من الواجهة أولاً
    setState(() {
      _activeAds.removeWhere((ad) => ad['id'] == productId);
    });

    try {
      // حذف من قاعدة البيانات
      await FirebaseFirestore.instance
          .collection('products')
          .doc(productId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حذف الإعلان بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // في حالة الخطأ، إعادة تحميل البيانات لاستعادة الحالة الصحيحة
      _loadUserProducts();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء حذف الإعلان',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'إعلاناتي',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildAdsGrid(_activeAds),
    );
  }

  Widget _buildAdsGrid(List<Map<String, dynamic>> ads) {
    if (ads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد إعلانات نشطة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // إعادة تحميل البيانات فوراً
        _adsSubscription?.cancel();
        await _loadUserProducts();
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(8.0),
        itemCount: ads.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildProductCard(ads[index]);
        },
      ),
    );
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
        _showProductOptions(product);
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // صورة المنتج
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 80,
                        height: 80,
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
                                      color: Colors.grey[400], size: 24),
                                ),
                              )
                            : Container(
                                color: Colors.grey[100],
                                child: Icon(Icons.shopping_bag_outlined,
                                  color: Colors.grey[400], size: 24),
                              ),
                      ),
                    ),
                    
                    // حالة الإعلان في الزاوية العلوية اليمنى
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: (product['isExpiringSoon'] == true
                              ? Colors.orange.withOpacity(0.9)
                              : Colors.green.withOpacity(0.9)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'نشط',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(width: 12),
                
                // تفاصيل المنتج
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // عنوان المنتج
                      Text(
                        product['title'] ?? 'منتج',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 2),
                      
                      // السعر
                      if (product['price'] != null)
                        Text(
                          '${product['price']} IQD',
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
              ],
            ),
            // عداد الوقت المتبقي في الزاوية السفلية اليمنى
            Positioned(
              bottom: 8,
              right: 8,
              child: _buildTimeCounter(product),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTimeCounter(Map<String, dynamic> product) {
    
    // حساب الوقت المتبقي من حقل expireAt
    if (product['expireAt'] == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.green[200]!, width: 0.5),
        ),
        child: Text(
          'نشط',
          style: GoogleFonts.cairo(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.green[600],
          ),
        ),
      );
    }
    
    final now = DateTime.now();
    final expireAt = (product['expireAt'] as Timestamp).toDate();
    final duration = expireAt.difference(now);
    
    if (duration.isNegative) {
      // هذا يجب أن لا يحدث إذا كان النظام يعمل بشكل صحيح
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.red[200]!, width: 0.5),
        ),
        child: Text(
          'انتهى',
          style: GoogleFonts.cairo(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.red[600],
          ),
        ),
      );
    }
    
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    // تحديد اللون بناءً على الوقت المتبقي
    final isExpiringSoon = duration.inSeconds < 30; // أقل من 30 ثانية
    
    Color bgColor = isExpiringSoon ? Colors.orange[50]! : Colors.green[50]!;
    Color borderColor = isExpiringSoon ? Colors.orange[200]! : Colors.green[200]!;
    Color textColor = isExpiringSoon ? Colors.orange[600]! : Colors.green[600]!;
    
    String timeText = '';
    if (days > 0) {
      timeText = '${days}d ${hours}h';
    } else if (hours > 0) {
      timeText = '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      timeText = '${minutes}m ${seconds}s';
    } else {
      timeText = '${seconds}s';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Text(
        timeText,
        style: GoogleFonts.cairo(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
  
  Widget _buildTimeUnit(String value, String unit, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          unit,
          style: GoogleFonts.cairo(
            fontSize: 9,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 2,
            offset: const Offset(0.5, 0.5),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: Colors.white,
          size: 12,
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  void _showProductOptions(Map<String, dynamic> product) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // مقبض السحب
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // عنوان المنتج
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 65,
                        height: 65,
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
                                  child: Icon(
                                    Icons.shopping_bag_outlined,
                                    color: Colors.grey[400],
                                    size: 30,
                                  ),
                                ),
                              )
                            : Container(
                                color: Colors.grey[100],
                                child: Icon(
                                  Icons.shopping_bag_outlined,
                                  color: Colors.grey[400],
                                  size: 30,
                                ),
                              ),
                      ),
                    ),
                    
                    const SizedBox(width: 15),
                    
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['title'] ?? 'منتج',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          
                          if (product['price'] != null)
                            Text(
                              '${product['price']} د.ع',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                color: Colors.green[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // قائمة الخيارات
              _buildSimpleOption(
                icon: Icons.visibility,
                title: 'عرض تفاصيل',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProductDetailPage(product: product),
                    ),
                  );
                },
              ),
              
              

              
              _buildSimpleOption(
                icon: Icons.delete,
                title: 'حذف الإعلان',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteAd(product['id']);
                },
              ),
              
              // مسافة آمنة للأسفل
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildSimpleOption({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 22,
                  ),
                ),
                
                const SizedBox(width: 16),
                
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
                
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey[400],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteAd(String productId) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'تأكيد الحذف',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'هل أنت متأكد من حذف هذا الإعلان؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'إلغاء',
                style: GoogleFonts.cairo(),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteAd(productId);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: Text(
                'حذف',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

}