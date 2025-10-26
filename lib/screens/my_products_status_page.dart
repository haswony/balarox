import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/shimmer_widget.dart';

class MyProductsStatusPage extends StatefulWidget {
  const MyProductsStatusPage({super.key});

  @override
  State<MyProductsStatusPage> createState() => _MyProductsStatusPageState();
}

class _MyProductsStatusPageState extends State<MyProductsStatusPage> {
  List<Map<String, dynamic>> _pendingProducts = [];
  List<Map<String, dynamic>> _rejectedProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyProducts();
  }

  Future<void> _loadMyProducts() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // جلب المنتجات المعلقة
      final pendingSnapshot = await FirebaseFirestore.instance
          .collection('pending_products')
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get();

      // جلب المنتجات المرفوضة
      final rejectedSnapshot = await FirebaseFirestore.instance
          .collection('pending_products')
          .where('userId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'rejected')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        _pendingProducts = pendingSnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        _rejectedProducts = rejectedSnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'حالة إعلاناتي',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blue,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Container(
                    color: Colors.blue,
                    child: TabBar(
                      indicatorColor: Colors.white,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      tabs: [
                        Tab(
                          text: 'في الانتظار (${_pendingProducts.length})',
                        ),
                        Tab(
                          text: 'مرفوضة (${_rejectedProducts.length})',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildPendingTab(),
                        _buildRejectedTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPendingTab() {
    if (_pendingProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.schedule,
                size: 48,
                color: Colors.orange[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'لا توجد إعلانات في الانتظار',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جميع إعلاناتك تمت مراجعتها',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyProducts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingProducts.length,
        itemBuilder: (context, index) {
          final product = _pendingProducts[index];
          return _buildProductCard(product, isPending: true);
        },
      ),
    );
  }

  Widget _buildRejectedTab() {
    if (_rejectedProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle,
                size: 48,
                color: Colors.green[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'رائع! لا توجد إعلانات مرفوضة',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جميع إعلاناتك تم قبولها',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyProducts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rejectedProducts.length,
        itemBuilder: (context, index) {
          final product = _rejectedProducts[index];
          return _buildProductCard(product, isPending: false);
        },
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product, {required bool isPending}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showProductDetails(product, isPending: isPending),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // صورة المنتج
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[100],
                ),
                child: Stack(
                  children: [
                    // الصورة الرئيسية
                    product['imageUrls']?.isNotEmpty == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: product['imageUrls'][0],
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => ShimmerWidget(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey[400],
                                  size: 30,
                                ),
                              ),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.grey[400],
                              size: 30,
                            ),
                          ),

                    // عدد الصور
                    if (product['imageUrls']?.length > 1)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${product['imageUrls'].length}',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // مؤشر حالة المنتج
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPending ? Colors.orange : Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isPending ? Icons.schedule : Icons.close,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),

              // تفاصيل المنتج
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // عنوان المنتج
                    Text(
                      product['title'] ?? '',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // حالة المنتج
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPending ? Colors.orange[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isPending ? Colors.orange[200]! : Colors.red[200]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPending ? Icons.schedule : Icons.error_outline,
                            size: 14,
                            color: isPending ? Colors.orange[700] : Colors.red[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPending ? 'في انتظار المراجعة' : 'مرفوض',
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: isPending ? Colors.orange[700] : Colors.red[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // الفئة والسعر
                    Row(
                      children: [
                        // الفئة
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Text(
                            product['category'] ?? '',
                            style: GoogleFonts.cairo(
                              fontSize: 10,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        // مؤشر المزاد
                        if (product['isAuction'] == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.purple[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.purple[200]!),
                            ),
                            child: Text(
                              'مزاد',
                              style: GoogleFonts.cairo(
                                fontSize: 9,
                                color: Colors.purple[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],

                        const Spacer(),

                        // السعر
                        Text(
                          '${product['price']} د.ع',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[600],
                          ),
                        ),
                      ],
                    ),

                    // سبب الرفض (مختصر)
                    if (!isPending && product['rejectionReason']?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 12,
                              color: Colors.red[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                product['rejectionReason'],
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  color: Colors.red[600],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // سهم للتفاصيل
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProductDetails(Map<String, dynamic> product, {required bool isPending}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      'تفاصيل الإعلان',
                      style: GoogleFonts.cairo(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPending ? Colors.orange[100] : Colors.red[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPending ? Icons.schedule : Icons.error_outline,
                            size: 16,
                            color: isPending ? Colors.orange[700] : Colors.red[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPending ? 'في الانتظار' : 'مرفوض',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: isPending ? Colors.orange[700] : Colors.red[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // صور المنتج
                      if (product['imageUrls']?.isNotEmpty == true) ...[
                        Container(
                          height: 250,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.grey[100],
                          ),
                          child: PageView.builder(
                            itemCount: product['imageUrls'].length,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  image: DecorationImage(
                                    image: NetworkImage(product['imageUrls'][index]),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // عنوان المنتج
                      Text(
                        product['title'] ?? '',
                        style: GoogleFonts.cairo(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // السعر والفئة
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Text(
                              product['category'] ?? '',
                              style: GoogleFonts.cairo(
                                fontSize: 14,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (product['isAuction'] == true) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.purple[50],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.purple[200]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.gavel,
                                    size: 16,
                                    color: Colors.purple[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'مزاد',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: Colors.purple[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${product['price']} د.ع',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // الوصف
                      if (product['description']?.isNotEmpty == true) ...[
                        Text(
                          'الوصف',
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            product['description'],
                            style: GoogleFonts.cairo(
                              fontSize: 15,
                              height: 1.6,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // تفاصيل إضافية
                      _buildDetailSection('تفاصيل الإعلان', [
                        _buildDetailItem('الحالة', product['condition'] ?? 'غير محدد'),
                        _buildDetailItem('الموقع', product['location'] ?? 'غير محدد'),
                        _buildDetailItem('قابل للتفاوض', product['isNegotiable'] == true ? 'نعم' : 'لا'),
                      ]),

                      // سبب الرفض (للمنتجات المرفوضة)
                      if (!isPending && product['rejectionReason']?.isNotEmpty == true) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red[600],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'سبب الرفض',
                                    style: GoogleFonts.cairo(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                product['rejectionReason'],
                                style: GoogleFonts.cairo(
                                  fontSize: 14,
                                  color: Colors.red[600],
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
