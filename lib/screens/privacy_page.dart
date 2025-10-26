import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../services/database_service.dart';
import 'user_profile_page.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;
  StreamSubscription<QuerySnapshot>? _blockedUsersSubscription;

  @override
  void initState() {
    super.initState();
    _setupBlockedUsersListener();
  }

  @override
  void dispose() {
    _blockedUsersSubscription?.cancel();
    super.dispose();
  }

  void _setupBlockedUsersListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    _blockedUsersSubscription = FirebaseFirestore.instance
        .collection('blocks')
        .where('blockerUserId', isEqualTo: currentUser.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) async {
      List<Map<String, dynamic>> blockedUsers = [];
      
      for (var doc in snapshot.docs) {
        final blockData = doc.data();
        final blockedUserId = blockData['blockedUserId'];
        final userData = await DatabaseService.getUserFromFirestore(blockedUserId);
        if (userData != null) {
          userData['id'] = blockedUserId;
          userData['blockId'] = doc.id;
          userData['blockedAt'] = blockData['createdAt'];
          blockedUsers.add(userData);
        }
      }

      if (mounted) {
        setState(() {
          _blockedUsers = blockedUsers;
          _isLoading = false;
        });
      }
    });
  }


  Future<void> _unblockUser(String userId, String displayName) async {
    try {
      await DatabaseService.unblockUser(userId);
      
      // إزالة المستخدم من القائمة محلياً
      setState(() {
        _blockedUsers.removeWhere((user) => user['id'] == userId);
      });
      
      _showSuccessSnackBar('تم إلغاء حظر $displayName');
    } catch (e) {
      _showErrorSnackBar('خطأ في إلغاء الحظر: $e');
    }
  }

  void _showUnblockDialog(String userId, String displayName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'إلغاء الحظر',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'هل أنت متأكد من إلغاء حظر $displayName؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                color: Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _unblockUser(userId, displayName);
            },
            child: Text(
              'إلغاء الحظر',
              style: GoogleFonts.cairo(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          'المحظورون',
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
            
            // قسم المحظورين
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'المحظورون',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const Spacer(),
                  if (_blockedUsers.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_blockedUsers.length}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_blockedUsers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.block,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد حسابات محظورة',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'عندما تحظر شخصاً، سيظهر هنا',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _blockedUsers.length,
                itemBuilder: (context, index) {
                  final user = _blockedUsers[index];
                  return _buildBlockedUserItem(user);
                },
              ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }


  Widget _buildBlockedUserItem(Map<String, dynamic> user) {
    final displayName = user['displayName']?.isNotEmpty == true
        ? user['displayName']
        : '@${user['handle'] ?? 'مستخدم'}';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        splashColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () {
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
          child: CircleAvatar(
            radius: 25,
            backgroundImage: user['profileImageUrl']?.isNotEmpty == true
                ? NetworkImage(user['profileImageUrl'])
                : null,
            child: user['profileImageUrl']?.isEmpty != false
                ? Icon(Icons.person, size: 25, color: Colors.grey[600])
                : null,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        subtitle: user['handle']?.isNotEmpty == true
            ? Text(
                '@${user['handle']}',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              )
            : null,
        trailing: TextButton(
          onPressed: () => _showUnblockDialog(user['id'], displayName),
          style: TextButton.styleFrom(
            foregroundColor: Colors.blue,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.blue[200]!),
            ),
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
          ),
          child: Text(
            'إلغاء الحظر',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}