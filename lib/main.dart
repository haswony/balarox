
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/login_page.dart';
import 'screens/home_page.dart';
import 'services/preload_service.dart';
import 'services/database_service.dart';
import 'services/user_presence_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تعيين لون شريط الحالة والشريط السفلي إلى الأبيض
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, // شريط الحالة شفاف
    statusBarIconBrightness: Brightness.dark, // أيقونات شريط الحالة داكنة
    statusBarBrightness: Brightness.light, // خلفية شريط الحالة فاتحة
    systemNavigationBarColor: Colors.white, // الشريط السفلي أبيض
    systemNavigationBarIconBrightness: Brightness.dark, // أيقونات الشريط السفلي داكنة
  ));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize notification service
  await NotificationService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: MaterialApp(
        title: 'بلدروز',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A5F),
            brightness: Brightness.light,
          ),
          textTheme: GoogleFonts.cairoTextTheme(),
          useMaterial3: true,
          // تعيين لون AppBar الافتراضي
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            ),
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // مسح الكاش عند بدء التطبيق لضمان تحديث البيانات
    _clearCacheOnAppStart();
    // التحميل المسبق للبيانات
    _preloadDataIfNeeded();
  }

  /// مسح الكاش عند بدء التطبيق لتجنب مشاكل البيانات القديمة
  Future<void> _clearCacheOnAppStart() async {
    try {
      // مسح جميع الكاش عند بدء التطبيق
      DatabaseService.clearAllCache();
      PreloadService.reset();

      // مسح SharedPreferences للبيانات المؤقتة
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      print('تم مسح الكاش عند بدء التطبيق');
    } catch (e) {
      print('خطأ في مسح الكاش عند البدء: $e');
    }
  }

  Future<void> _preloadDataIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // تحميل البيانات مسبقاً إذا كان المستخدم مسجل دخول
      await PreloadService.preloadData();

      // تهيئة خدمة حضور المستخدم
      await UserPresenceService.instance.initialize();

      // تحميل بيانات المستخدم مسبقاً للأدوار مع إعادة المحاولة في حالة الخطأ
      await _loadUserDataWithRetry(user.uid);

      // حذف الإعلانات المنتهية تلقائياً عند بدء التطبيق
      _deleteExpiredProductsIfNeeded();
    }
  }

  /// تحميل بيانات المستخدم مع إعادة المحاولة في حالة الخطأ
  Future<void> _loadUserDataWithRetry(String userId) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // تحميل بيانات المستخدم الأساسية
        await DatabaseService.getUserFromFirestore(userId);

        // تحميل صلاحيات المستخدم
        await DatabaseService.isAdmin(userId);
        await DatabaseService.isSuperAdmin(userId);

        // تحديث آخر ظهور للمستخدم
        await DatabaseService.updateLastSeen();

        print('تم تحميل بيانات المستخدم بنجاح');
        return; // نجح التحميل، خروج من الحلقة
      } catch (e) {
        retryCount++;
        print('خطأ في التحميل المسبق لبيانات المستخدم (المحاولة $retryCount): $e');

        if (retryCount < maxRetries) {
          // انتظار قبل إعادة المحاولة
          await Future.delayed(Duration(seconds: retryCount));
        }
      }
    }

    print('فشل في تحميل بيانات المستخدم بعد $maxRetries محاولات');
  }

  Future<void> _deleteExpiredProductsIfNeeded() async {
    try {
      // تشغيل حذف الإعلانات المنتهية مرة واحدة يومياً
      final prefs = await SharedPreferences.getInstance();
      final lastCleanup = prefs.getString('last_cleanup_date');
      final today = DateTime.now().toIso8601String().split('T')[0];

      if (lastCleanup != today) {
        final updatedCount = await DatabaseService.updateExpiredProductsStatus();
        await prefs.setString('last_cleanup_date', today);
        print('تم تحديث حالة $updatedCount إعلان إلى expired');
      }
    } catch (e) {
      print('خطأ في عملية التنظيف التلقائي: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }

        if (snapshot.hasData) {
          final user = snapshot.data!;
          // تحميل بيانات المستخدم بشكل متزامن مع إعادة المحاولة
          _loadUserDataOnLogin(user.uid);
          return const HomePage();
        }

        return const LoginPage();
      },
    );
  }

  /// تحميل بيانات المستخدم عند تسجيل الدخول
  Future<void> _loadUserDataOnLogin(String userId) async {
    try {
      // تحديث آخر ظهور للمستخدم
      await DatabaseService.updateLastSeen();

      // تحميل البيانات الأساسية للمستخدم
      await DatabaseService.getUserFromFirestore(userId);

      // تحميل صلاحيات المستخدم
      await DatabaseService.isAdmin(userId);
      await DatabaseService.isSuperAdmin(userId);

      // تحديث حالة الحظر للمستخدمين الآخرين
      await _refreshBlockStatus();

      print('تم تحميل بيانات المستخدم عند تسجيل الدخول');
    } catch (e) {
      print('خطأ في تحميل بيانات المستخدم عند تسجيل الدخول: $e');
    }
  }

  /// تحديث حالة الحظر للمستخدمين الآخرين
  Future<void> _refreshBlockStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // مسح كاش الحظر للحصول على أحدث البيانات
      DatabaseService.clearAllCache();

      print('تم تحديث حالة الحظر');
    } catch (e) {
      print('خطأ في تحديث حالة الحظر: $e');
    }
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E3A5F),
              Color(0xFF2E5984),
              Color(0xFF4A7BA7),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.phone_android,
                  size: 50,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'بلدروز',
                style: GoogleFonts.cairo(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
