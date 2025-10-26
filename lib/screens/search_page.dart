import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'product_detail_page.dart';
import 'user_profile_page.dart';
import '../services/database_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/shimmer_widget.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  String _currentQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _currentQuery = query.trim();
    });

    try {
      List<Map<String, dynamic>> results = [];
      
      if (_tabController.index == 0) {
        // البحث في الإعلانات
        final products = await DatabaseService.getProducts(limit: 100);
        results = products.where((product) {
          final title = (product['title'] ?? '').toString().toLowerCase();
          final description = (product['description'] ?? '').toString().toLowerCase();
          final category = (product['category'] ?? '').toString().toLowerCase();
          final location = (product['location'] ?? '').toString().toLowerCase();
          final searchTerm = query.toLowerCase();
          
          return title.contains(searchTerm) ||
                 description.contains(searchTerm) ||
                 category.contains(searchTerm) ||
                 location.contains(searchTerm);
        }).toList();
      } else {
        // البحث في المستخدمين
        results = await _searchUsers(query);
      }

      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      print('خطأ في البحث: $e');
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    try {
      // البحث بالـ handle
      final usersQuery = await DatabaseService.getUsersByHandle(query);
      return usersQuery;
    } catch (e) {
      print('خطأ في البحث عن المستخدمين: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: Container(
          height: 40,
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: _tabController.index == 0 ? 'ابحث عن إعلانات...' : 'ابحث بالـ @handle...',
              hintStyle: GoogleFonts.cairo(color: Colors.grey[600]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: Colors.blue),
              ),
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            ),
            style: GoogleFonts.cairo(),
            textAlign: TextAlign.right,
            onChanged: (value) {
              if (value.trim().isEmpty) {
                setState(() {
                  _searchResults = [];
                  _hasSearched = false;
                });
              }
            },
            onSubmitted: _performSearch,
          ),
        ),
      ),
      body: Column(
        children: [
          // Tab Bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              onTap: (index) {
                if (_currentQuery.isNotEmpty) {
                  _performSearch(_currentQuery);
                }
              },
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey[600],
              labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              unselectedLabelStyle: GoogleFonts.cairo(),
              indicatorColor: Colors.blue,
              tabs: const [
                Tab(text: 'الإعلانات'),
                Tab(text: 'الأشخاص'),
              ],
            ),
          ),
          
          // Search Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? _buildSearchSuggestions()
                    : _searchResults.isEmpty
                        ? _buildNoResults()
                        : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSuggestions() {
    final suggestions = _tabController.index == 0
        ? ['مركبات', 'إلكترونيات', 'أثاث ومنزل', 'أزياء وملابس']
        : ['@ahmad', '@sara', '@mohammed', '@fatima'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tabController.index == 0 ? 'اقتراحات البحث في الإعلانات:' : 'أمثلة على البحث:',
            style: GoogleFonts.cairo(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((suggestion) {
              return GestureDetector(
                onTap: () {
                  _searchController.text = suggestion;
                  _performSearch(suggestion);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Text(
                    suggestion,
                    style: GoogleFonts.cairo(
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _tabController.index == 0 ? Icons.search_off : Icons.person_search,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد نتائج',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tabController.index == 0
                ? 'جرب البحث بكلمات أخرى في الإعلانات'
                : 'تأكد من كتابة الـ @handle بشكل صحيح',
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_tabController.index == 0) {
      return _buildAdResults();
    } else {
      return _buildUserResults();
    }
  }

  Widget _buildAdResults() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final product = _searchResults[index];
        return _buildAdCard(product);
      },
    );
  }

  Widget _buildUserResults() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildAdCard(Map<String, dynamic> product) {
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
         // الانتقال لملف المستخدم مع عرض الإعلان
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
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صورة الإعلان
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Container(
                  width: double.infinity,
                  child: product['imageUrls']?.isNotEmpty == true
                      ? CachedNetworkImage(
                          imageUrl: product['imageUrls'][0],
                          fit: BoxFit.cover,
                          placeholder: (context, url) => ShimmerWidget(
                            child: Container(
                              color: Colors.grey[300],
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.image, color: Colors.grey, size: 40),
                          ),
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Icon(Icons.image, color: Colors.grey, size: 40),
                        ),
                ),
              ),
            ),
            
            // معلومات الإعلان
            Container(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product['title'] ?? '',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${product['price']} د.ع',
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          product['location'] ?? '',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    return InkWell(
      onTap: () {
        // الانتقال لصفحة الملف الشخصي للمستخدم
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfilePage(
              userId: user['id'],
              initialDisplayName: user['displayName'],
              initialHandle: user['handle'],
              initialProfileImage: user['profileImageUrl'],
              initialIsVerified: user['isVerified'],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // صورة المستخدم
            CircleAvatar(
              radius: 25,
              backgroundImage: user['profileImageUrl']?.isNotEmpty == true
                  ? NetworkImage(user['profileImageUrl'])
                  : null,
              child: user['profileImageUrl']?.isEmpty != false
                  ? Icon(Icons.person, size: 25, color: Colors.grey[600])
                  : null,
            ),
            const SizedBox(width: 15),
            
            // معلومات المستخدم
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        user['displayName']?.isNotEmpty == true
                            ? user['displayName']
                            : '@${user['handle']}',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      if (user['isVerified'] == true) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user['handle']}',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            // سهم للتنقل
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}