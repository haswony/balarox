import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'شروط الاستخدام',
          style: GoogleFonts.cairo(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'آخر تحديث: 25 أكتوبر 2025',
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'مرحباً بك في تطبيق بلدروز',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'تطبيق بلدروز هو تطبيق تجاري محلي يهدف إلى خدمة محافظة ديالى فقط. يساعد التطبيق الأشخاص في البيع والشراء داخل المحافظة، مما يعزز الاقتصاد المحلي ويسهل التبادل التجاري بين السكان.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'شروط الاستخدام',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              '1. القبول بالشروط',
              'باستخدام تطبيق بلدروز، أنت توافق على الالتزام بهذه الشروط والأحكام. إذا كنت لا توافق، يرجى عدم استخدام التطبيق.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '2. الاستخدام المحدود',
              'التطبيق مخصص للاستخدام داخل محافظة ديالى فقط. يُمنع استخدامه خارج هذه المنطقة الجغرافية.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '3. مسؤوليات المستخدم',
              '- يجب تقديم معلومات دقيقة وصحيحة عند التسجيل أو إضافة المنتجات.\n- الالتزام بالقوانين المحلية والأخلاقيات في جميع المعاملات.\n- عدم نشر محتوى غير قانوني أو مسيء.\n- الحفاظ على سرية حسابك وكلمة المرور.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '4. مسؤوليات التطبيق',
              '- يوفر التطبيق منصة للبيع والشراء، لكنه لا يتحمل مسؤولية المعاملات بين المستخدمين.\n- يحق للتطبيق تعديل أو إزالة المحتوى الذي ينتهك الشروط.\n- لا يضمن التطبيق دقة المعلومات المقدمة من المستخدمين.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '5. الخصوصية',
              'نحن نحترم خصوصيتك ونلتزم بحماية بياناتك الشخصية وفقاً لسياسة الخصوصية الخاصة بنا.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '6. الأنشطة المحظورة',
              '- بيع أو شراء منتجات غير قانونية.\n- الاحتيال أو الخداع.\n- إساءة استخدام المنصة لأغراض غير مشروعة.\n- انتهاك حقوق الملكية الفكرية.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '7. إنهاء الاستخدام',
              'يحق للتطبيق إنهاء حسابك إذا انتهكت هذه الشروط، دون إشعار مسبق.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '8. التعديلات',
              'نحتفظ بالحق في تعديل هذه الشروط في أي وقت. سيتم إخطار المستخدمين بالتغييرات.',
            ),
            const SizedBox(height: 24),
            _buildSection(
              '9. الاتصال',
              'لأي استفسارات، يرجى الاتصال بنا عبر البريد الإلكتروني أو من خلال التطبيق.',
            ),
            const SizedBox(height: 32),
            Text(
              'شكراً لاستخدام تطبيق بلدروز. نتمنى لك تجربة ممتعة ومفيدة.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: GoogleFonts.cairo(
            fontSize: 16,
            color: Colors.black,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}