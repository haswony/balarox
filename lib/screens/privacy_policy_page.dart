import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'سياسة الخصوصية',
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
              'مرحباً بك في بلدروز',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'باستخدام تطبيقنا، أنت توافق على الامتثال لشروط الاستخدام وسياسة الخصوصية الخاصة بنا. يرجى قراءتها بعناية.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'بالوصول إلى التطبيق أو استخدامه، أنت تقبل جميع الشروط والأحكام. إذا لم توافق، يرجى عدم استخدام التطبيق.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'يوفر بلدروز خدمات لشراء وبيع المنتجات، وجدولة المواعيد مع المتخصصين بما في ذلك الأطباء، وتلقي الإرشادات. أنت توافق على استخدام التطبيق بمسؤولية وبشكل قانوني.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'يجب على المستخدمين عدم نشر معلومات كاذبة أو مضللة أو ضارة، أو الانخراط في أنشطة غير قانونية، أو مضايقة أو تهديد المستخدمين الآخرين، أو محاولة تعطيل خدمات التطبيق أو أمانه.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'جميع عمليات الشراء والبيع أو جدولة المواعيد تتم بين المستخدمين ومقدمي الخدمات. بلدروز غير مسؤول عن أي نزاعات أو خسائر أو أضرار تنشأ عن هذه المعاملات.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'أنت تحتفظ بملكية المحتوى الذي تنشره لكنك تمنح بلدروز ترخيصاً لاستخدامه لتقديم الخدمات. نحتفظ بالحق في إزالة المحتوى الذي ينتهك هذه الشروط.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'نحن نجمع ونستخدم بياناتك وفقاً لسياسة الخصوصية الخاصة بنا. باستخدام التطبيق، أنت توافق على جمع واستخدام معلوماتك.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'بلدروز غير مسؤول عن أي أضرار مباشرة أو غير مباشرة ناتجة عن استخدام التطبيق، بما في ذلك الخسائر المالية أو المشكلات الصحية.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'قد نحدث هذه الشروط في أي وقت. استمرار استخدام التطبيق يشكل قبولاً للشروط المحدثة.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'باستخدام بلدروز، أنت تقر بأنك قد قرأت وفهمت ووافقت على هذه الشروط.',
              style: GoogleFonts.cairo(
                fontSize: 16,
                color: Colors.black,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}