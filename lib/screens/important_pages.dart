import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'my_products_status_page.dart'; // Relative import
import 'my_ads_page.dart';
import 'favorites_page.dart';

class ImportantPages extends StatefulWidget {
  const ImportantPages({super.key});

  @override
  State<ImportantPages> createState() => _ImportantPagesState();
}

class _ImportantPagesState extends State<ImportantPages> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'الصفحات المهمة',
          style: GoogleFonts.cairo(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قسم الإعلانات
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'الإعلانات',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),

             _buildSettingItem(
               icon: Icons.pending_actions,
               title: 'حالة إعلاناتي',
               subtitle: 'تتبع حالة الإعلانات المرسلة للمراجعة',
               onTap: () {
                 Navigator.push(
                   context,
                   MaterialPageRoute(
                     builder: (context) => const MyProductsStatusPage(),
                   ),
                 );
               },
               iconColor: Colors.black,
             ),

            _buildSettingItem(
              icon: Icons.campaign,
              title: 'إعلاناتي',
              subtitle: 'إدارة إعلاناتك النشطة والمنتهية',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyAdsPage(),
                  ),
                );
              },
              iconColor: Colors.black,
            ),

            _buildSettingItem(
              icon: Icons.favorite,
              title: 'المفضلة',
              subtitle: 'الإعلانات التي أضفتها للمفضلة',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FavoritesPage(),
                  ),
                );
              },
              iconColor: Colors.black,
            ),
            
          ],
        ),
      ),
    );
  }
  
  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor ?? Colors.black87),
      ),
      title: Text(
        title,
        style: GoogleFonts.cairo(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.cairo(
          fontSize: 14,
          color: Colors.grey[600],
        ),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Colors.grey,
      ),
      splashColor: Colors.transparent,
      onTap: onTap,
    );
  }
}