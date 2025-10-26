import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_product_page.dart';
import 'add_story_page.dart';
import '../services/database_service.dart';

class AddContentPage extends StatelessWidget {
  final VoidCallback? onNavigateToHome;

  const AddContentPage({super.key, this.onNavigateToHome});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'إضافة محتوى',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 40),
            
            // عنوان ترحيبي
            Text(
              'ماذا تريد أن تضيف؟',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 50),
            
            // بطاقة إضافة منتج
            _buildAddCard(
              context: context,
              icon: Icons.inventory_2,
              iconColor: Colors.black,
              title: 'إضافة إعلان',
              subtitle: 'بيع أو عرض منتج للمزايدة',
              onTap: () => _navigateToAddProduct(context),
            ),
            
            const Divider(height: 1),
            
            // بطاقة إضافة قصة
            _buildAddCard(
              context: context,
              icon: Icons.add_photo_alternate,
              iconColor: Colors.black,
              title: 'إضافة قصة',
              subtitle: 'شارك لحظة مميزة تختفي بعد 24 ساعة',
              onTap: () => _navigateToAddStory(context),
            ),
            
            const Spacer(),
            
            // نصائح سريعة
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: Colors.black,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tip: Add clear photos and a detailed description to attract more buyers',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAddCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor,
        size: 32,
      ),
      title: Text(
        title,
        style: GoogleFonts.cairo(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.cairo(
          fontSize: 14,
          color: Colors.grey[600],
          height: 1.3,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: iconColor,
        size: 20,
      ),
      onTap: onTap,
    );
  }

  void _navigateToAddProduct(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddProductPage()),
    );

    if (result == true && context.mounted) {
      // الانتقال إلى الصفحة الرئيسية بطريقة سلسة
      onNavigateToHome?.call();
    }
  }

  void _navigateToAddStory(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // التحقق من حد إضافة القصص
    final storyLimitCheck = await DatabaseService.checkUserStoryLimit(user.uid);
    
    if (!storyLimitCheck['canAddStory']) {
      _showStoryLimitDialog(context, storyLimitCheck);
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddStoryPage()),
    );

    if (result == true && context.mounted) {
      // الانتقال إلى الصفحة الرئيسية بطريقة سلسة
      onNavigateToHome?.call();
    }
  }

  void _showStoryLimitDialog(BuildContext context, Map<String, dynamic> limitCheck) {
    final remainingSeconds = limitCheck['remainingTime'] as int;
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    
    String timeMessage;
    if (hours > 0) {
      timeMessage = '$hours ساعة و $minutes دقيقة';
    } else {
      timeMessage = '$minutes دقيقة';
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Container();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          ),
          child: FadeTransition(
            opacity: animation,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Container(
                width: 260,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الرسالة الرئيسية
                    Text(
                      'يمكنك إضافة قصة واحدة فقط كل 24 ساعة',
                      style: GoogleFonts.cairo(
                        fontSize: 15,
                        color: Colors.black,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    
                    // الوقت المتبقي
                    Text(
                      'الوقت المتبقي: $timeMessage',
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: Colors.black54,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    
                    // خط فاصل
                    Container(
                      height: 0.5,
                      color: Colors.black12,
                    ),
                    const SizedBox(height: 12),
                    
                    // زر الإغلاق - نص فقط بدون تأثير
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'حسناً',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
