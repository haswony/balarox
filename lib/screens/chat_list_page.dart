import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../services/database_service.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  StreamSubscription<QuerySnapshot>? _chatsSubscription;
  List<Map<String, dynamic>> _allChats = [];
  List<Map<String, dynamic>> _friendsChats = [];
  List<Map<String, dynamic>> _othersChats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setupChatsListener();
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }

  void _setupChatsListener() {
    _chatsSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .listen((snapshot) async {
      List<Map<String, dynamic>> chats = [];

      for (var doc in snapshot.docs) {
        final chatData = doc.data() as Map<String, dynamic>;
        chatData['id'] = doc.id;

        // الحصول على معلومات المستخدم الآخر
        final participants = List<String>.from(chatData['participants'] ?? []);
        final otherUserId = participants.firstWhere(
              (id) => id != currentUserId,
          orElse: () => '',
        );

        if (otherUserId.isNotEmpty) {
          final otherUserData = await DatabaseService.getUserFromFirestore(otherUserId);
          if (otherUserData != null) {
            chatData['otherUser'] = otherUserData;
            chatData['otherUserId'] = otherUserId;
            chats.add(chatData);
          }
        }
      }

      // فصل المحادثات إلى أصدقاء وأخرون
      await _separateChats(chats);

      if (mounted) {
        setState(() {
          _allChats = chats;
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _separateChats(List<Map<String, dynamic>> chats) async {
    List<Map<String, dynamic>> friends = [];
    List<Map<String, dynamic>> others = [];

    // التحقق من كل محادثة لمعرفة ما إذا كانت مع صديق (تباع متبادلة) أو مع آخر
    for (var chat in chats) {
      final otherUserId = chat['otherUserId'];
      if (otherUserId != null) {
        final isMutual = await DatabaseService.isMutualFollow(otherUserId);
        if (isMutual) {
          friends.add(chat);
        } else {
          others.add(chat);
        }
      }
    }

    setState(() {
      _friendsChats = friends;
      _othersChats = others;
    });
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime messageTime;
    if (timestamp is Timestamp) {
      messageTime = timestamp.toDate();
    } else {
      messageTime = timestamp;
    }

    final now = DateTime.now();
    final difference = now.difference(messageTime);

    if (difference.inMinutes < 1) {
      return 'الآن';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}د';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}س';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}ي';
    } else {
      return '${messageTime.day}/${messageTime.month}';
    }
  }

  String _getMessagePreview(Map<String, dynamic> chat) {
    final lastMessage = chat['lastMessage'] ?? '';
    final messageType = chat['lastMessageType'] ?? 'text';

    switch (messageType) {
      case 'image':
        return '📷 صورة';
      case 'location':
        return '📍 موقع';
      case 'phone':
        return '📞 رقم هاتف';
      default:
        return lastMessage.length > 30
            ? '${lastMessage.substring(0, 30)}...'
            : lastMessage;
    }
  }

  Widget _buildOnlineStatusIndicator(String userId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final isOnline = userData['isOnline'] ?? false;

        return Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatItem(Map<String, dynamic> chat) {
    final otherUser = chat['otherUser'] as Map<String, dynamic>;
    final unreadCount = chat['unreadCount_$currentUserId'] ?? 0;

    return Dismissible(
      key: Key(chat['id']),
      direction: DismissDirection.endToStart, // سحب من اليمين إلى اليسار
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        // عرض رسالة تأكيد الحذف
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(
                'حذف المحادثة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              content: Text(
                'هل أنت متأكد من حذف هذه المحادثة؟ سيتم حذف جميع الرسائل نهائياً.',
                style: GoogleFonts.cairo(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'إلغاء',
                    style: GoogleFonts.cairo(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    'حذف',
                    style: GoogleFonts.cairo(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
      onDismissed: (direction) async {
        try {
          // حذف المحادثة من Firebase
          await DatabaseService.deleteChat(chat['id']);

          // إزالة المحادثة من القائمة المحلية
          setState(() {
            _allChats.removeWhere((c) => c['id'] == chat['id']);
            _friendsChats.removeWhere((c) => c['id'] == chat['id']);
            _othersChats.removeWhere((c) => c['id'] == chat['id']);
          });
        } catch (e) {
          // في حالة فشل الحذف، أعد المحادثة إلى القائمة
          setState(() {
            _allChats.add(chat);
            _separateChats(_allChats);
          });

          // عرض رسالة خطأ
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'فشل في حذف المحادثة: $e',
                  style: GoogleFonts.cairo(color: Colors.white),
                ),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
      },
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                chatId: chat['id'],
                otherUserId: chat['otherUserId'],
                otherUserName: otherUser['displayName'] ?? otherUser['handle'] ?? 'مستخدم',
                otherUserImage: otherUser['profileImageUrl'] ?? '',
                isVerified: otherUser['isVerified'] ?? false,
              ),
            ),
          );
        },
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // صورة المستخدم
              Stack(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: otherUser['profileImageUrl']?.isNotEmpty == true
                        ? NetworkImage(otherUser['profileImageUrl'])
                        : null,
                    child: otherUser['profileImageUrl']?.isEmpty != false
                        ? Icon(Icons.person, size: 28, color: Colors.grey[600])
                        : null,
                  ),
                  // مؤشر حالة الاتصال
                  _buildOnlineStatusIndicator(chat['otherUserId']),
                ],
              ),

              const SizedBox(width: 12),

              // معلومات المحادثة
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            otherUser['displayName']?.isNotEmpty == true
                                ? otherUser['displayName']
                                : '@${otherUser['handle'] ?? 'مستخدم'}',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (otherUser['isVerified'] == true) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            color: Colors.blue,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getMessagePreview(chat),
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: unreadCount > 0 ? Colors.black87 : Colors.grey[600],
                        fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // الوقت وعدد الرسائل غير المقروءة
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatTime(chat['lastMessageTime']),
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: unreadCount > 0 ? Colors.blue : Colors.grey[500],
                      fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (unreadCount > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
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
        title: Text(
          'الرسائل',
          style: GoogleFonts.cairo(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _allChats.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allChats.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد محادثات بعد',
              style: GoogleFonts.cairo(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ابدأ محادثة جديدة من صفحة المنتج',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      )
          : SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قسم الأصدقاء
            if (_friendsChats.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'الأصدقاء',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _friendsChats.length,
                itemBuilder: (context, index) {
                  return _buildChatItem(_friendsChats[index]);
                },
              ),
            ],

            // قسم الآخرين
            if (_othersChats.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'الآخرون',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _othersChats.length,
                itemBuilder: (context, index) {
                  return _buildChatItem(_othersChats[index]);
                },
              ),
            ],

            // في حالة عدم وجود أي من القسمين
            if (_friendsChats.isEmpty && _othersChats.isEmpty && !_isLoading) ...[
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا توجد محادثات بعد',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ابدأ محادثة جديدة من صفحة المنتج',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}