import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/database_service.dart';
import 'auction_page.dart';
import 'dart:async';

class AuctionsListPage extends StatefulWidget {
  const AuctionsListPage({Key? key}) : super(key: key);

  @override
  State<AuctionsListPage> createState() => _AuctionsListPageState();
}

class _AuctionsListPageState extends State<AuctionsListPage> {
  List<Map<String, dynamic>> _auctions = [];
  List<Map<String, dynamic>> _filteredAuctions = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  StreamSubscription? _auctionsSubscription;
  String _selectedFilter = 'الكل';

  final List<String> _filterOptions = [
    'الكل',
    'ينتهي قريباً',
    'جديدة',
    'الأكثر عروضاً',
  ];

  // متغيرات شريط الأقسام
  String _selectedCategory = 'الكل';
  final List<String> _categories = [
    'الكل',
    'مركبات',
    'إلكترونيات',
    'أثاث ومنزل',
    'أزياء وملابس',
    'رياضة ولياقة',
    'كتب وهوايات',
    'عقارات',
    'أخرى'
  ];

  @override
  void initState() {
    super.initState();
    _setupRealTimeAuctionsListener();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _auctionsSubscription?.cancel();
    super.dispose();
  }

  void _setupRealTimeAuctionsListener() {
    final now = Timestamp.now();

    _auctionsSubscription = FirebaseFirestore.instance
        .collection('products')
        .where('status', isEqualTo: 'active')
        .where('isAuction', isEqualTo: true)
        .where('auctionStatus', isEqualTo: 'active')
        .where('auctionEndTime', isGreaterThan: now)
        .orderBy('auctionEndTime')
        .limit(50)
        .snapshots()
        .listen((snapshot) async {
      if (mounted) {
        List<Map<String, dynamic>> auctions = [];

        for (var doc in snapshot.docs) {
          final auctionData = doc.data();
          auctionData['id'] = doc.id;

          // جلب بيانات البائع
          try {
            final userData = await DatabaseService.getUserFromFirestore(auctionData['userId']);
            auctionData['userDisplayName'] = userData?['displayName'] ?? '';
            auctionData['userPhone'] = userData?['phoneNumber'] ?? '';
            auctionData['userProfileImage'] = userData?['profileImageUrl'] ?? '';
          } catch (e) {
            auctionData['userDisplayName'] = '';
            auctionData['userPhone'] = '';
            auctionData['userProfileImage'] = '';
          }

          auctions.add(auctionData);
        }

        setState(() {
          _auctions = auctions;
          _filteredAuctions = _applyFilter(auctions);
          _isLoading = false;
        });
      }
    });
  }

  void _startRefreshTimer() {
    // تقليل تكرار التحديث لأن البيانات تأتي real-time الآن
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        // إعادة إعداد المستمع للتأكد من عدم انقطاع الاتصال
        _auctionsSubscription?.cancel();
        _setupRealTimeAuctionsListener();
      }
    });
  }

  Future<void> _loadAuctions() async {
    // إعادة إعداد المستمع للحصول على أحدث البيانات
    _auctionsSubscription?.cancel();
    _setupRealTimeAuctionsListener();
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> auctions) {
    switch (_selectedFilter) {
      case 'ينتهي قريباً':
        return auctions.where((auction) {
          final endTime = (auction['auctionEndTime'] as Timestamp).toDate();
          final difference = endTime.difference(DateTime.now());
          return difference.inHours <= 24 && difference.inSeconds > 0;
        }).toList()..sort((a, b) {
          final aEndTime = (a['auctionEndTime'] as Timestamp).toDate();
          final bEndTime = (b['auctionEndTime'] as Timestamp).toDate();
          return aEndTime.compareTo(bEndTime);
        });
      case 'جديدة':
        return auctions.where((auction) {
          final startTime = (auction['auctionStartTime'] as Timestamp).toDate();
          final difference = DateTime.now().difference(startTime);
          return difference.inHours <= 24;
        }).toList()..sort((a, b) {
          final aStartTime = (a['auctionStartTime'] as Timestamp).toDate();
          final bStartTime = (b['auctionStartTime'] as Timestamp).toDate();
          return bStartTime.compareTo(aStartTime);
        });
      case 'الأكثر عروضاً':
        return auctions.toList()..sort((a, b) {
          final aBids = a['auctionBidsCount'] ?? 0;
          final bBids = b['auctionBidsCount'] ?? 0;
          return bBids.compareTo(aBids);
        });
      default:
        return auctions.toList()..sort((a, b) {
          final aEndTime = (a['auctionEndTime'] as Timestamp).toDate();
          final bEndTime = (b['auctionEndTime'] as Timestamp).toDate();
          return aEndTime.compareTo(bEndTime);
        });
    }
  }

  void _changeFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
      _filteredAuctions = _applyFilter(_auctions);
    });
  }

  String _formatTimeRemaining(DateTime endTime) {
    final now = DateTime.now();
    final difference = endTime.difference(now);

    if (difference.isNegative) return 'انتهت';

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;

    if (days > 0) {
      return '$days يوم';
    } else if (hours > 0) {
      return '$hours ساعة';
    } else {
      return '$minutes دقيقة';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'المزايدات النشطة',
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
        actions: [
          IconButton(
            onPressed: _loadAuctions,
            icon: const Icon(Icons.refresh, color: Colors.black),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط الفلترة
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filterOptions.length,
              itemBuilder: (context, index) {
                final filter = _filterOptions[index];
                final isSelected = _selectedFilter == filter;
                return GestureDetector(
                  onTap: () => _changeFilter(filter),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.grey[100],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        filter,
                        style: GoogleFonts.cairo(
                          color: isSelected ? Colors.white : Colors.grey[700],
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // المحتوى الرئيسي
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredAuctions.isEmpty
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
                              _auctions.isEmpty
                                  ? 'لا توجد مزايدات نشطة حالياً'
                                  : 'لا توجد مزايدات تطابق الفلتر المحدد',
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAuctions,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredAuctions.length,
                          itemBuilder: (context, index) {
                            final auction = _filteredAuctions[index];
                            return _buildAuctionCard(auction);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionCard(Map<String, dynamic> auction) {
    final endTime = (auction['auctionEndTime'] as Timestamp).toDate();
    final isActive = DateTime.now().isBefore(endTime);
    final currentPrice = auction['auctionCurrentPrice'] ?? auction['auctionStartPrice'];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AuctionPage(product: auction),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // صورة المنتج
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                  ),
                  child: auction['imageUrls']?.isNotEmpty == true
                      ? Image.network(
                          auction['imageUrls'][0],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.inventory_2_outlined,
                              color: Colors.grey[400],
                              size: 40,
                            );
                          },
                        )
                      : Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.grey[400],
                          size: 40,
                        ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // معلومات المنتج
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auction['title'] ?? '',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    
                    Row(
                      children: [
                        Icon(
                          Icons.gavel,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$currentPrice د.ع',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    Text(
                      'عدد العروض: ${auction['auctionBidsCount'] ?? 0}',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isActive ? Colors.red[50] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isActive ? _formatTimeRemaining(endTime) : 'انتهت',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isActive ? Colors.red : Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              
              // سهم الانتقال
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
