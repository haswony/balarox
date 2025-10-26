import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'home_page.dart';
import '../services/database_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _isLoading = false;
  bool _otpSent = false;
  String _verificationId = '';

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _formatIraqiPhoneNumber(String phoneNumber) {
    // Remove any non-digit characters
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // If it starts with 964, it's already formatted
    if (cleaned.startsWith('964')) {
      return '+$cleaned';
    }

    // If it starts with 0, remove it and add 964
    if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }

    // Add Iraq country code
    return '+964$cleaned';
  }

  bool _isValidIraqiPhoneNumber(String phoneNumber) {
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // Check if it's a valid Iraqi phone number format
    if (cleaned.startsWith('964')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.startsWith('0')) {
      cleaned = cleaned.substring(1);
    }

    // Iraqi mobile numbers start with 7 and are 10 digits total
    return cleaned.startsWith('7') && cleaned.length == 10;
  }

  Future<void> _sendOTP() async {
    if (!_isValidIraqiPhoneNumber(_phoneController.text)) {
      _showErrorSnackBar('يرجى إدخال رقم هاتف عراقي صحيح');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      String formattedPhone = _formatIraqiPhoneNumber(_phoneController.text);

      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // تعطيل التحقق التلقائي - سيتم التحقق يدوياً فقط
          print('تم استلام التحقق التلقائي ولكن سيتم تجاهله');
        },
        verificationFailed: (FirebaseAuthException e) {
          String errorMessage = 'خطأ في التحقق';

          if (e.code == 'captcha-check-failed') {
            errorMessage = 'فشل في التحقق الأمني. يرجى المحاولة مرة أخرى.';
          } else if (e.code == 'invalid-phone-number') {
            errorMessage = 'رقم الهاتف غير صحيح. يرجى التأكد من الرقم.';
          } else if (e.code == 'too-many-requests') {
            errorMessage = 'تم إرسال طلبات كثيرة. يرجى الانتظار قليلاً.';
          } else if (e.code == 'app-not-authorized') {
            errorMessage = 'التطبيق غير مصرح له. يرجى المحاولة لاحقاً.';
          } else {
            errorMessage = 'خطأ في التحقق: ${e.message ?? e.code}';
          }

          _showErrorSnackBar(errorMessage);
          setState(() {
            _isLoading = false;
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
            _isLoading = false;
          });
          _showSuccessSnackBar('تم إرسال رمز التحقق إلى هاتفك');
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      String errorMessage = 'حدث خطأ غير متوقع';

      if (e.toString().contains('captcha') || e.toString().contains('CAPTCHA')) {
        errorMessage = 'مشكلة في التحقق الأمني. يرجى إعادة تشغيل التطبيق والمحاولة مرة أخرى.';
      } else if (e.toString().contains('network')) {
        errorMessage = 'مشكلة في الاتصال. تأكد من الإنترنت والمحاولة مرة أخرى.';
      } else {
        errorMessage = 'حدث خطأ: $e';
      }

      _showErrorSnackBar(errorMessage);
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.length != 6) {
      _showErrorSnackBar('يرجى إدخال رمز التحقق المكون من 6 أرقام');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: _otpController.text,
      );

      await _auth.signInWithCredential(credential);

      // تسجيل المستخدم في قاعدة البيانات
      try {
        await DatabaseService.registerCurrentUser();
      } catch (e) {
        print('خطأ في تسجيل المستخدم في قاعدة البيانات: $e');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } catch (e) {
      _showErrorSnackBar('رمز التحقق غير صحيح');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(color: Colors.white),
          textAlign: TextAlign.right,
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(color: Colors.white),
          textAlign: TextAlign.right,
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              // Logo Section
              Container(
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.phone_android,
                        size: 50,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'بلدروز',
                      style: GoogleFonts.cairo(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'تسجيل الدخول بالهاتف',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 50),

              // Form Section
              if (!_otpSent) ...[
                // Phone Number Section
                Text(
                  'رقم الهاتف العراقي',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: '07XX XXX XXXX',
                    hintStyle: GoogleFonts.cairo(
                      color: Colors.grey[400],
                    ),
                    prefixIcon: Icon(
                      Icons.phone,
                      color: Colors.grey[600],
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Helper text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text(
                    '💡 إذا ظهر خطأ في التحقق، أعد تشغيل التطبيق وحاول مرة أخرى',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: Colors.orange[700],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),

                const SizedBox(height: 20),

                // Send OTP Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : Text(
                      'إرسال رمز التحقق',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // OTP Section
                Text(
                  'رمز التحقق',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                Text(
                  'أدخل الرمز المرسل إلى ${_phoneController.text}',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Text(
                    '💡 ستحتاج لإدخال الرمز يدوياً من رسالة SMS',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: Colors.blue[700],
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: GoogleFonts.cairo(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 8,
                    color: Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: '123456',
                    hintStyle: GoogleFonts.cairo(
                      color: Colors.grey[400],
                      letterSpacing: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOTP,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : Text(
                      'تأكيد',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Back Button
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _otpSent = false;
                        _otpController.clear();
                      });
                    },
                    child: Text(
                      'العودة لتغيير رقم الهاتف',
                      style: GoogleFonts.cairo(
                        color: Colors.blue[600],
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 40),

              // Footer
              Text(
                'تطبيق بلدروز',
                style: GoogleFonts.cairo(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}