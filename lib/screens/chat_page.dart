import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import 'chat_image_viewer_page.dart';
import 'user_profile_page.dart';

class ChatPage extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String otherUserImage;
  final bool isVerified;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserImage,
    this.isVerified = false,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _messagesSubscription;
  StreamSubscription<QuerySnapshot>? _blockStatusSubscription;
  StreamSubscription<DocumentSnapshot>? _typingSubscription;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _isBlocked = false;
  bool _isOtherUserTyping = false;
  String _otherUserHandle = '';

  // متغيرات الرد على الرسائل
  Map<String, dynamic>? _replyToMessage;

  // متغيرات تعديل الرسائل
  Map<String, dynamic>? _editingMessage;
  final TextEditingController _editMessageController = TextEditingController();

  Timer? _typingTimer;

  // متغيرات التسجيل الصوتي
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  String? _recordingPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  // متغيرات تشغيل الصوت
  Map<String, bool> _playingStates = {};
  Map<String, Duration> _currentPositions = {};
  Map<String, Duration> _totalDurations = {};
  StreamSubscription<Duration>? _currentPositionSubscription;

  @override
  void initState() {
    super.initState();
    _loadOtherUserData();
    _setupMessagesListener();
    _setupBlockStatusListener();
    _setupTypingListener();
    _markMessagesAsRead();
    _checkBlockStatus();

    // تحديث حالة المستخدم إلى متصل
    _updateUserOnlineStatus(true);

    // إضافة مستمع لتغييرات حقل الإدخال
    _messageController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    // إرسال حالة الكتابة إلى قاعدة البيانات
    if (_messageController.text.isNotEmpty) {
      _sendTypingStatus(true);
      // إعادة تعيين المؤقت
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _sendTypingStatus(false);
      });
    } else {
      _sendTypingStatus(false);
      _typingTimer?.cancel();
    }
  }

  Future<void> _sendTypingStatus(bool isTyping) async {
    try {
      await _firestore.collection('chats').doc(widget.chatId).set({
        'typing_${currentUserId}': isTyping,
      }, SetOptions(merge: true));
    } catch (e) {
      print('خطأ في إرسال حالة الكتابة: $e');
    }
  }

  void _setupTypingListener() {
    _typingSubscription = _firestore.collection('chats').doc(widget.chatId).snapshots().listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>?;
        if (data != null) {
          final isTyping = data['typing_${widget.otherUserId}'] ?? false;
          if (mounted) {
            setState(() {
              _isOtherUserTyping = isTyping;
            });
          }
        }
      }
    });
  }

  Future<void> _loadOtherUserData() async {
    try {
      final userData = await DatabaseService.getUserFromFirestore(widget.otherUserId);
      if (mounted) {
        setState(() {
          _otherUserHandle = userData?['handle'] ?? '';
        });
      }
    } catch (e) {
      print('خطأ في تحميل بيانات المستخدم: $e');
    }
  }

  @override
  void dispose() {
    // تحديث حالة المستخدم إلى غير متصل
    _updateUserOnlineStatus(false);

    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSubscription?.cancel();
    _blockStatusSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();

    // إيقاف التسجيل والتشغيل
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _currentPositionSubscription?.cancel();

    super.dispose();
  }

  // تحديث حالة الاتصال للمستخدم الحالي
  Future<void> _updateUserOnlineStatus(bool isOnline) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
          'isOnline': isOnline,
          'lastSeen': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        print('خطأ في تحديث حالة الاتصال: $e');
      }
    }
  }

  // عرض حالة الاتصال للمستخدم الآخر
  Widget _buildOnlineStatus() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Text(
            'غير متصل',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          );
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final isOnline = userData['isOnline'] ?? false;
        final lastSeen = userData['lastSeen'] as Timestamp?;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isOnline ? 'متصل الآن' : _formatLastSeen(lastSeen),
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: isOnline ? Colors.green[600] : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  // تنسيق وقت آخر ظهور
  String _formatLastSeen(Timestamp? lastSeen) {
    if (lastSeen == null) {
      return 'غير متصل';
    }

    final now = DateTime.now();
    final lastSeenDate = lastSeen.toDate();
    final difference = now.difference(lastSeenDate);

    if (difference.inMinutes < 1) {
      return 'منذ قليل';
    } else if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    } else if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    } else if (difference.inDays < 7) {
      return 'منذ ${difference.inDays} أيام';
    } else {
      return 'غير متصل مؤخراً';
    }
  }

  void _setupMessagesListener() {
    _messagesSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      // تحديث فوري للرسائل بدون انتظار
      final messages = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // تصفية الرسائل المحذوفة من قبل المستخدم الحالي
      final filteredMessages = messages.where((message) {
        final deletedFor = List<String>.from(message['deletedFor'] ?? []);
        return !deletedFor.contains(currentUserId);
      }).toList();

      if (mounted) {
        setState(() {
          _messages = filteredMessages;
          _isLoading = false;
        });

        // تمييز الرسائل كمقروءة بشكل غير متزامن لتجنب التأخير
        _markMessagesAsReadAsync();

        // التمرير للأسفل فوراً عند وصول رسالة جديدة
        if (filteredMessages.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
      }
    }, onError: (error) {
      print('خطأ في stream الرسائل: $error');
      // في حالة الخطأ، حاول إعادة الاتصال
      if (mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _setupMessagesListener();
          }
        });
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'unreadCount_$currentUserId': 0,
      });
    } catch (e) {
      print('خطأ في تمييز الرسائل كمقروءة: $e');
    }
  }

  // تمييز الرسائل كمقروءة بشكل غير متزامن لتجنب التأخير
  void _markMessagesAsReadAsync() {
    // تشغيل العملية في الخلفية بدون انتظار
    Future.microtask(() async {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({
          'unreadCount_$currentUserId': 0,
        });
      } catch (e) {
        print('خطأ في تمييز الرسائل كمقروءة: $e');
      }
    });
  }

  void _setupBlockStatusListener() {
    // مستمع لحالة الحظر في الوقت الفعلي
    _blockStatusSubscription = FirebaseFirestore.instance
        .collection('blocks')
        .where('blockerUserId', isEqualTo: currentUserId)
        .where('blockedUserId', isEqualTo: widget.otherUserId)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _isBlocked = snapshot.docs.isNotEmpty;
        });
      }
    });

    // مستمع إضافي للتحقق من كوني محظور من الطرف الآخر
    FirebaseFirestore.instance
        .collection('blocks')
        .where('blockerUserId', isEqualTo: widget.otherUserId)
        .where('blockedUserId', isEqualTo: currentUserId)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
      if (mounted) {
        final isBlockedByOther = snapshot.docs.isNotEmpty;
        setState(() {
          _isBlocked = _isBlocked || isBlockedByOther;
        });
      }
    });
  }

  Future<void> _checkBlockStatus() async {
    try {
      final isBlocked = await DatabaseService.isUserBlocked(widget.otherUserId);
      final isBlockedBy = await DatabaseService.isBlockedByUser(widget.otherUserId);

      if (mounted) {
        setState(() {
          _isBlocked = isBlocked || isBlockedBy;
        });
      }
    } catch (e) {
      print('خطأ في فحص حالة الحظر: $e');
    }
  }

  void _setReplyMessage(Map<String, dynamic> message) {
    setState(() {
      _replyToMessage = {
        'id': message['id'],
        'senderId': message['senderId'],
        'content': message['content'],
        'type': message['type'] ?? 'text',
      };
    });
  }

  void _clearReply() {
    setState(() {
      _replyToMessage = null;
    });
  }

  // دالة لعرض خيارات الرسالة عند الضغط المطول (بنمط انستغرام)
  void _showMessageOptions(Map<String, dynamic> message, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // مؤشر السحب
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // عنوان الخيارات
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'خيارات الرسالة',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const Divider(height: 1),
            // خيار الرد على الرسالة
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _setReplyMessage(message);
                },
                child: Row(
                  children: [
                    const Icon(
                      Icons.reply,
                      color: Colors.black,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'رد على الرسالة',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // خيار تعديل الرسالة (يظهر فقط للمستخدم صاحب الرسالة)
            if (isMe)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _startEditingMessage(message);
                  },
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit,
                        color: Colors.black,
                        size: 24,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'تعديل الرسالة',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // زر الإلغاء
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'إلغاء',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // دالة لفتح واجهة تعديل الرسالة (بنمط انستغرام)
  void _startEditingMessage(Map<String, dynamic> message) {
    // التحقق من أن الرسالة تابعة للمستخدم الحالي
    if (message['senderId'] != currentUserId) return;

    setState(() {
      _editingMessage = message;
      _editMessageController.text = message['content'] ?? '';
    });

    // فتح نافذة حوار لتعديل الرسالة بنمط انستغرام
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: MediaQuery.of(context).viewInsets, // هذا يحل مشكلة تغطية الكيبورد
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // مؤشر السحب
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // عنوان التعديل
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    // زر الإلغاء
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _editingMessage = null;
                          _editMessageController.clear();
                        });
                      },
                      child: Text(
                        'إلغاء',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'تعديل الرسالة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // زر الحفظ
                    TextButton(
                      onPressed: () async {
                        if (_editMessageController.text.trim().isNotEmpty) {
                          Navigator.pop(context);
                          await _updateMessage(_editMessageController.text.trim());
                        }
                      },
                      child: Text(
                        'حفظ',
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // حقل إدخال النص
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _editMessageController,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالتك الجديدة...',
                      hintStyle: GoogleFonts.cairo(
                        color: Colors.grey[500],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                    maxLines: 5,
                    minLines: 1,
                    textAlign: TextAlign.right,
                    autofocus: true,
                  ),
                ),
              ),
              // معلومات التعديل
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.grey[500],
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'سيظهر للجميع أنك قمت بتعديل الرسالة',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // دالة لتحديث الرسالة في Firestore
  Future<void> _updateMessage(String newContent) async {
    if (_editingMessage == null) return;

    try {
      final messageId = _editingMessage!['id'];
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'content': newContent,
        'isEdited': true,
        'editedAt': FieldValue.serverTimestamp(),
      });

      // تحديث آخر رسالة في المحادثة إذا كانت هذه هي آخر رسالة
      final chatDoc = await _firestore.collection('chats').doc(widget.chatId).get();
      if (chatDoc.exists) {
        final chatData = chatDoc.data() as Map<String, dynamic>;
        final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;
        final messageTime = _editingMessage!['timestamp'] as Timestamp?;

        if (lastMessageTime != null && messageTime != null) {
          final lastMessageDateTime = lastMessageTime.toDate();
          final messageDateTime = messageTime.toDate();

          // إذا كانت هذه هي آخر رسالة (بتسامح 5 ثوانٍ)
          if (lastMessageDateTime.difference(messageDateTime).inSeconds.abs() <= 5) {
            await _firestore.collection('chats').doc(widget.chatId).update({
              'lastMessage': newContent,
            });
          }
        }
      }

      setState(() {
        _editingMessage = null;
        _editMessageController.clear();
      });
    } catch (e) {
      _showError('خطأ في تعديل الرسالة: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      final message = _messageController.text.trim();
      _messageController.clear();

      // التحقق مما إذا كانت المحادثة قد تم حذفها من قبل المستخدم الحالي
      final chatDoc = await _firestore.collection('chats').doc(widget.chatId).get();
      bool needsReactivation = false;

      if (chatDoc.exists) {
        final chatData = chatDoc.data() as Map<String, dynamic>;
        final deletedFor = List<String>.from(chatData['deletedFor'] ?? []);

        // إذا كان المستخدم الحالي قد حذف المحادثة، نحتاج إلى إعادة تفعيلها
        if (deletedFor.contains(currentUserId)) {
          needsReactivation = true;
        }
      } else {
        // إذا لم توجد المحادثة، هذا أمر غير متوقع لكن نتعامل معه
        // سنعيد إنشاء المحادثة
      }

      if (needsReactivation) {
        // إعادة تفعيل المحادثة الحالية بإزالة المستخدم الحالي من قائمة المحذوفة
        await _firestore.collection('chats').doc(widget.chatId).update({
          'deletedFor': FieldValue.arrayRemove([currentUserId])
        });
      }

      // إرسال الرسالة إلى المحادثة الحالية
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'senderId': currentUserId,
        'content': message,
        'type': 'text',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        if (_replyToMessage != null) 'replyTo': {
          'messageId': _replyToMessage!['id'],
          'senderId': _replyToMessage!['senderId'],
          'content': _replyToMessage!['content'],
          'type': _replyToMessage!['type'] ?? 'text',
        },
      });

      // تحديث آخر رسالة في المحادثة
      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': message,
        'lastMessageType': 'text',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
      });

      // حفظ الإشعار في قاعدة البيانات (سيتم إرسال إشعار FCM بواسطة Firebase Functions)
      // Removed for normal chat messages

      _replyToMessage = null; // مسح الرد بعد الإرسال
      _scrollToBottom();

      // إيقاف حالة الكتابة بعد الإرسال
      _sendTypingStatus(false);
      _typingTimer?.cancel();
    } catch (e) {
      _showError('خطأ في إرسال الرسالة: $e');
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _sendImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        // رفع الصورة وإرسالها مرة واحدة فقط
        final imageUrl = await DatabaseService.uploadChatImage(File(image.path));

        // التحقق مما إذا كانت المحادثة قد تم حذفها من قبل المستخدم الحالي
        final chatDoc = await _firestore.collection('chats').doc(widget.chatId).get();
        bool needsReactivation = false;

        if (chatDoc.exists) {
          final chatData = chatDoc.data() as Map<String, dynamic>;
          final deletedFor = List<String>.from(chatData['deletedFor'] ?? []);

          // إذا كان المستخدم الحالي قد حذف المحادثة، نحتاج إلى إعادة تفعيلها
          if (deletedFor.contains(currentUserId)) {
            needsReactivation = true;
          }
        }

        if (needsReactivation) {
          // إعادة تفعيل المحادثة الحالية بإزالة المستخدم الحالي من قائمة المحذوفة
          await _firestore.collection('chats').doc(widget.chatId).update({
            'deletedFor': FieldValue.arrayRemove([currentUserId])
          });
        }

        // إرسال الرسالة إلى المحادثة الحالية
        await _firestore
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .add({
          'senderId': currentUserId,
          'content': 'صورة',
          'type': 'image',
          'imageUrl': imageUrl,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          if (_replyToMessage != null) 'replyTo': {
            'messageId': _replyToMessage!['id'],
            'senderId': _replyToMessage!['senderId'],
            'content': _replyToMessage!['content'],
            'type': _replyToMessage!['type'] ?? 'text',
          },
        });

        // تحديث آخر رسالة في المحادثة
        await _firestore.collection('chats').doc(widget.chatId).update({
          'lastMessage': 'صورة',
          'lastMessageType': 'image',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
        });

        _replyToMessage = null; // مسح الرد بعد الإرسال
        _scrollToBottom();
      }
    } catch (e) {
      _showError('خطأ في إرسال الصورة: $e');
    }
  }

  Future<void> _sendLocation() async {
    try {
      // إرسال موقع وهمي للاختبار فورياً
      final locationData = {
        'latitude': 33.3152,
        'longitude': 44.3661,
      };

      // التحقق مما إذا كانت المحادثة قد تم حذفها من قبل المستخدم الحالي
      final chatDoc = await _firestore.collection('chats').doc(widget.chatId).get();
      bool needsReactivation = false;

      if (chatDoc.exists) {
        final chatData = chatDoc.data() as Map<String, dynamic>;
        final deletedFor = List<String>.from(chatData['deletedFor'] ?? []);

        // إذا كان المستخدم الحالي قد حذف المحادثة، نحتاج إلى إعادة تفعيلها
        if (deletedFor.contains(currentUserId)) {
          needsReactivation = true;
        }
      }

      if (needsReactivation) {
        // إعادة تفعيل المحادثة الحالية بإزالة المستخدم الحالي من قائمة المحذوفة
        await _firestore.collection('chats').doc(widget.chatId).update({
          'deletedFor': FieldValue.arrayRemove([currentUserId])
        });
      }

      // إرسال الرسالة إلى المحادثة الحالية
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'senderId': currentUserId,
        'content': 'موقع بغداد',
        'type': 'location',
        'location': locationData,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        if (_replyToMessage != null) 'replyTo': {
          'messageId': _replyToMessage!['id'],
          'senderId': _replyToMessage!['senderId'],
          'content': _replyToMessage!['content'],
          'type': _replyToMessage!['type'] ?? 'text',
        },
      });

      // تحديث آخر رسالة في المحادثة
      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': 'موقع بغداد',
        'lastMessageType': 'location',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
      });

      _replyToMessage = null; // مسح الرد بعد الإرسال
      _scrollToBottom();
    } catch (e) {
      _showError('خطأ في إرسال الموقع: $e');
    }
  }

  Future<void> _sendPhoneNumber() async {
    final TextEditingController phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'إرسال رقم هاتف',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'أدخل رقم الهاتف',
            hintStyle: GoogleFonts.cairo(),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () async {
              final phone = phoneController.text.trim();
              if (phone.isNotEmpty) {
                Navigator.pop(context);

                // التحقق مما إذا كانت المحادثة قد تم حذفها من قبل المستخدم الحالي
                final chatDoc = await _firestore.collection('chats').doc(widget.chatId).get();
                bool needsReactivation = false;

                if (chatDoc.exists) {
                  final chatData = chatDoc.data() as Map<String, dynamic>;
                  final deletedFor = List<String>.from(chatData['deletedFor'] ?? []);

                  // إذا كان المستخدم الحالي قد حذف المحادثة، نحتاج إلى إعادة تفعيلها
                  if (deletedFor.contains(currentUserId)) {
                    needsReactivation = true;
                  }
                }

                if (needsReactivation) {
                  // إعادة تفعيل المحادثة الحالية بإزالة المستخدم الحالي من قائمة المحذوفة
                  await _firestore.collection('chats').doc(widget.chatId).update({
                    'deletedFor': FieldValue.arrayRemove([currentUserId])
                  });
                }

                // إرسال الرسالة إلى المحادثة الحالية
                await _firestore
                    .collection('chats')
                    .doc(widget.chatId)
                    .collection('messages')
                    .add({
                  'senderId': currentUserId,
                  'content': '📞 $phone',
                  'type': 'phone',
                  'timestamp': FieldValue.serverTimestamp(),
                  'isRead': false,
                  if (_replyToMessage != null) 'replyTo': {
                    'messageId': _replyToMessage!['id'],
                    'senderId': _replyToMessage!['senderId'],
                    'content': _replyToMessage!['content'],
                    'type': _replyToMessage!['type'] ?? 'text',
                  },
                });

                // تحديث آخر رسالة في المحادثة
                await _firestore.collection('chats').doc(widget.chatId).update({
                  'lastMessage': '📞 $phone',
                  'lastMessageType': 'phone',
                  'lastMessageTime': FieldValue.serverTimestamp(),
                  'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
                });

                // حفظ الإشعار في قاعدة البيانات (سيتم إرسال إشعار FCM بواسطة Firebase Functions)
                // Removed for normal chat messages

                _replyToMessage = null; // مسح الرد بعد الإرسال
                _scrollToBottom();
              }
            },
            child: Text('إرسال', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  // بدء تسجيل الصوت
  Future<void> _startVoiceRecording() async {
    try {
      // التحقق من الصلاحيات
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        _showError('لا توجد صلاحية للوصول إلى الميكروفون');
        return;
      }

      // إنشاء مسار التسجيل
      final directory = Directory.systemTemp;
      _recordingPath = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // بدء التسجيل
      await _audioRecorder.start(
        const RecordConfig(),
        path: _recordingPath!,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // عرض واجهة التسجيل
      _showRecordingDialog();
    } catch (e) {
      _showError('خطأ في بدء التسجيل: $e');
    }
  }

  // إيقاف التسجيل وإرسال الرسالة
  Future<void> _stopVoiceRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();

      if (path != null && _recordingDuration.inSeconds >= 1) {
        // رفع الملف الصوتي
        final audioUrl = await DatabaseService.uploadVoiceMessage(File(path));

        // إرسال الرسالة الصوتية
        await _sendVoiceMessage(audioUrl, _recordingDuration);
      }

      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
        _recordingPath = null;
      });
    } catch (e) {
      _showError('خطأ في إيقاف التسجيل: $e');
    }
  }

  // إيقاف التسجيل مع المدة من الحوار
  Future<void> _stopVoiceRecordingWithDuration(Duration duration) async {
    try {
      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();

      if (path != null && duration.inSeconds >= 1) {
        // رفع الملف الصوتي
        final audioUrl = await DatabaseService.uploadVoiceMessage(File(path));

        // إرسال الرسالة الصوتية
        await _sendVoiceMessage(audioUrl, duration);
      }

      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
        _recordingPath = null;
      });
    } catch (e) {
      _showError('خطأ في إيقاف التسجيل: $e');
    }
  }

  // إلغاء التسجيل
  Future<void> _cancelVoiceRecording() async {
    try {
      await _audioRecorder.stop();
      _recordingTimer?.cancel();

      // حذف الملف المؤقت إذا كان موجوداً
      if (_recordingPath != null && File(_recordingPath!).existsSync()) {
        File(_recordingPath!).deleteSync();
      }

      setState(() {
        _isRecording = false;
        _recordingDuration = Duration.zero;
        _recordingPath = null;
      });
    } catch (e) {
      print('خطأ في إلغاء التسجيل: $e');
    }
  }

  // عرض نافذة التسجيل
  void _showRecordingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RecordingDialog(
        onCancel: () {
          Navigator.pop(context);
          _cancelVoiceRecording();
        },
        onStop: (duration) {
          Navigator.pop(context);
          _stopVoiceRecordingWithDuration(duration);
        },
      ),
    );
  }

  // إرسال الرسالة الصوتية
  Future<void> _sendVoiceMessage(String audioUrl, Duration duration) async {
    try {
      // التحقق مما إذا كانت المحادثة قد تم حذفها من قبل المستخدم الحالي
      final chatDoc = await _firestore.collection('chats').doc(widget.chatId).get();
      bool needsReactivation = false;

      if (chatDoc.exists) {
        final chatData = chatDoc.data() as Map<String, dynamic>;
        final deletedFor = List<String>.from(chatData['deletedFor'] ?? []);

        // إذا كان المستخدم الحالي قد حذف المحادثة، نحتاج إلى إعادة تفعيلها
        if (deletedFor.contains(currentUserId)) {
          needsReactivation = true;
        }
      }

      if (needsReactivation) {
        // إعادة تفعيل المحادثة الحالية بإزالة المستخدم الحالي من قائمة المحذوفة
        await _firestore.collection('chats').doc(widget.chatId).update({
          'deletedFor': FieldValue.arrayRemove([currentUserId])
        });
      }

      // إرسال الرسالة إلى المحادثة الحالية
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
        'senderId': currentUserId,
        'content': 'رسالة صوتية',
        'type': 'voice',
        'audioUrl': audioUrl,
        'duration': duration.inSeconds,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        if (_replyToMessage != null) 'replyTo': {
          'messageId': _replyToMessage!['id'],
          'senderId': _replyToMessage!['senderId'],
          'content': _replyToMessage!['content'],
          'type': _replyToMessage!['type'] ?? 'text',
        },
      });

      // تحديث آخر رسالة في المحادثة
      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': 'رسالة صوتية',
        'lastMessageType': 'voice',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
      });

      _replyToMessage = null; // مسح الرد بعد الإرسال
      _scrollToBottom();
    } catch (e) {
      _showError('خطأ في إرسال الرسالة الصوتية: $e');
    }
  }

  // تشغيل/إيقاف الرسالة الصوتية
  Future<void> _toggleVoicePlayback(String messageId, String audioUrl, int durationSeconds) async {
    final isPlaying = _playingStates[messageId] ?? false;

    if (isPlaying) {
      // إيقاف التشغيل
      await _audioPlayer.stop();
      _currentPositionSubscription?.cancel();
      setState(() {
        _playingStates[messageId] = false;
        _currentPositions[messageId] = Duration.zero;
      });
    } else {
      // إيقاف أي تشغيل آخر
      await _audioPlayer.stop();
      _currentPositionSubscription?.cancel();

      // إعادة تعيين حالة جميع الرسائل الأخرى
      setState(() {
        for (final key in _playingStates.keys) {
          _playingStates[key] = false;
          _currentPositions[key] = Duration.zero;
        }
      });

      // بدء التشغيل
      try {
        await _audioPlayer.play(UrlSource(audioUrl));

        setState(() {
          _playingStates[messageId] = true;
          _totalDurations[messageId] = Duration(seconds: durationSeconds);
          _currentPositions[messageId] = Duration.zero;
        });

        // إلغاء المستمع السابق وإنشاء مستمع جديد
        _currentPositionSubscription?.cancel();
        _currentPositionSubscription = _audioPlayer.onPositionChanged.listen((position) {
          if (mounted) {
            setState(() {
              _currentPositions[messageId] = position;
            });
          }
        });

        // مستمع لانتهاء التشغيل
        _audioPlayer.onPlayerComplete.listen((event) {
          if (mounted) {
            setState(() {
              _playingStates[messageId] = false;
              _currentPositions[messageId] = Duration.zero;
            });
            _currentPositionSubscription?.cancel();
          }
        });
      } catch (e) {
        _showError('خطأ في تشغيل الصوت: $e');
      }
    }
  }

  // تنسيق المدة الزمنية
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo(color: Colors.white)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'إرسال',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAttachmentOption(
                  icon: Icons.photo,
                  label: 'صورة',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(context);
                    _sendImage();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.mic,
                  label: 'صوت',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _startVoiceRecording();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.location_on,
                  label: 'موقع',
                  color: Colors.green,
                  onTap: () {
                    Navigator.pop(context);
                    _sendLocation();
                  },
                ),
                _buildAttachmentOption(
                  icon: Icons.phone,
                  label: 'هاتف',
                  color: Colors.orange,
                  onTap: () {
                    Navigator.pop(context);
                    _sendPhoneNumber();
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final isMe = message['senderId'] == currentUserId;
    final messageType = message['type'] ?? 'text';

    return Dismissible(
      key: Key(message['id'] ?? DateTime.now().millisecondsSinceEpoch.toString()),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        _setReplyMessage(message);
        return false; // لا نريد حذف الرسالة، فقط الرد عليها
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(
          Icons.reply,
          color: Colors.grey[600],
          size: 24,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(
          Icons.reply,
          color: Colors.grey[600],
          size: 24,
        ),
      ),
      child: GestureDetector(
        onLongPress: () {
          _showMessageOptions(message, isMe);
        },
        child: _buildMessageContent(message, messageType, isMe),
      ),
    );
  }

  Widget _buildMessageContent(Map<String, dynamic> message, String messageType, bool isMe) {
    // للصور وردود القصص: عرض خاص
    if (messageType == 'image' || messageType == 'story_reply') {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: EdgeInsets.only(
            top: 4,
            bottom: 4,
            left: isMe ? 50 : 16,
            right: isMe ? 16 : 50,
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // عرض الرسالة المردود عليها إن وجدت
              if (message['replyTo'] != null) _buildReplyPreview(message['replyTo'], isMe),
              _buildActualMessageContent(message, messageType, isMe),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatMessageTime(message['timestamp']),
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (message['isEdited'] == true)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        'معدلة',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // للرسائل الأخرى: عرض مع كارد
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isMe ? 50 : 16,
          right: isMe ? 16 : 50,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عرض الرسالة المردود عليها إن وجدت
            if (message['replyTo'] != null) _buildReplyPreview(message['replyTo'], isMe),
            _buildActualMessageContent(message, messageType, isMe),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatMessageTime(message['timestamp']),
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: isMe ? Colors.white70 : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 6),
                if (message['isEdited'] == true)
                  Text(
                    'معدلة',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: isMe ? Colors.white70 : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview(Map<String, dynamic> replyTo, bool isMe) {
    final replyType = replyTo['type'] ?? 'text';
    final replySenderId = replyTo['senderId'];
    final isReplyFromMe = replySenderId == currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.2)
            : Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
        border: Border(
          right: BorderSide(
            color: isMe ? Colors.white : Colors.blue,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isReplyFromMe ? 'أنت' : widget.otherUserName,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isMe ? Colors.white : Colors.blue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _getReplyPreviewText(replyTo),
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: isMe ? Colors.white70 : Colors.grey[700],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _getReplyPreviewText(Map<String, dynamic> replyTo) {
    final type = replyTo['type'] ?? 'text';
    switch (type) {
      case 'image':
        return '📷 صورة';
      case 'location':
        return '📍 موقع';
      case 'phone':
        return '📞 رقم هاتف';
      case 'voice':
        return '🎵 رسالة صوتية';
      default:
        return replyTo['content'] ?? '';
    }
  }

  Widget _buildActualMessageContent(Map<String, dynamic> message, String type, bool isMe) {
    switch (type) {
      case 'story_reply':
        final storyData = message['storyData'] as Map<String, dynamic>?;
        if (storyData != null) {
          return Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // بطاقة القصة المردود عليها بتصميم Instagram
              Container(
                width: 250,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.purple.shade400,
                      Colors.pink.shade400,
                      Colors.orange.shade400,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(2),
                child: Container(
                  decoration: BoxDecoration(
                    color: isMe ? Colors.blue.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      // صورة القصة
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                        child: Stack(
                          children: [
                            Image.network(
                              storyData['imageUrl'] ?? '',
                              width: double.infinity,
                              height: 140,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: double.infinity,
                                  height: 140,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.image, color: Colors.grey, size: 40),
                                );
                              },
                            ),
                            // تراكب داكن مع أيقونة القصة
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withOpacity(0.5),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // معلومات صاحب القصة
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundImage: storyData['userProfileImage']?.isNotEmpty == true
                                        ? NetworkImage(storyData['userProfileImage'])
                                        : null,
                                    child: storyData['userProfileImage']?.isEmpty != false
                                        ? const Icon(Icons.person, size: 16, color: Colors.white)
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      storyData['userDisplayName'] ?? 'قصة',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'قصة',
                                          style: GoogleFonts.cairo(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // نص القصة إن وجد
                      if (storyData['caption']?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            storyData['caption'],
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // نص الرد
              Container(
                constraints: const BoxConstraints(maxWidth: 250),
                child: Text(
                  message['content'] ?? '',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: isMe ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          );
        }
        return Text(
          message['content'] ?? '',
          style: GoogleFonts.cairo(
            fontSize: 16,
            color: isMe ? Colors.white : Colors.black87,
          ),
        );

      case 'image':
        return GestureDetector(
          onTap: () {
            // فتح الصورة في عارض الصور الكامل المخصص للدردشة
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatImageViewerPage(imageUrl: message['imageUrl'] ?? ''),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              message['imageUrl'] ?? '',
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Icon(Icons.error, color: Colors.grey),
                );
              },
            ),
          ),
        );

      case 'product':
        final product = message['product'] as Map<String, dynamic>?;
        if (product != null) {
          return Container(
            width: 250,
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // شارة "أنا مهتم" في الأعلى
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isMe
                          ? [Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.7)]
                          : [Colors.blue[400]!, Colors.blue[600]!],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (isMe ? Colors.white : Colors.blue).withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: 16,
                        color: isMe ? Colors.blue[600] : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'أنا مهتم بهذا الاعلان',
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          color: isMe ? Colors.blue[700] : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // صورة المنتج
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    child: product['imageUrl']?.isNotEmpty == true
                        ? Image.network(
                      product['imageUrl'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.grey[300]!, Colors.grey[200]!],
                            ),
                          ),
                          child: Icon(
                            Icons.image_outlined,
                            size: 40,
                            color: Colors.grey[500],
                          ),
                        );
                      },
                    )
                        : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.grey[300]!, Colors.grey[200]!],
                        ),
                      ),
                      child: Icon(
                        Icons.image_outlined,
                        size: 40,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // العنوان
                Text(
                  product['title'] ?? '',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isMe ? Colors.white : Colors.black87,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 4),

                // السعر
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isMe
                          ? [Colors.white.withOpacity(0.9), Colors.white.withOpacity(0.7)]
                          : [Colors.green[400]!, Colors.teal[400]!],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (isMe ? Colors.white : Colors.green).withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    '${product['price']} د.ع',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isMe ? Colors.green[700] : Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 4),

                // الموقع
                if (product['location']?.isNotEmpty == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withOpacity(0.2)
                          : Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMe
                            ? Colors.white.withOpacity(0.3)
                            : Colors.blue[100]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 12,
                          color: isMe ? Colors.white70 : Colors.blue[600],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            product['location'],
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              color: isMe ? Colors.white70 : Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }
        break;

      case 'location':
        final location = message['location'] as Map<String, dynamic>?;
        if (location != null) {
          return GestureDetector(
            onTap: () async {
              final lat = location['latitude'];
              final lng = location['longitude'];
              final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
              if (await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.2) : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on,
                    color: isMe ? Colors.white : Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'موقع جغرافي',
                    style: GoogleFonts.cairo(
                      color: isMe ? Colors.white : Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        break;

      case 'phone':
        return GestureDetector(
          onTap: () async {
            final phone = message['content'];
            final url = 'tel:$phone';
            if (await canLaunchUrl(Uri.parse(url))) {
              await launchUrl(Uri.parse(url));
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withOpacity(0.2) : Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.phone,
                  color: isMe ? Colors.white : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  message['content'] ?? '',
                  style: GoogleFonts.cairo(
                    color: isMe ? Colors.white : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );

      case 'voice':
        final messageId = message['id'] ?? '';
        final audioUrl = message['audioUrl'] ?? '';
        final durationSeconds = message['duration'] ?? 0;
        final isPlaying = _playingStates[messageId] ?? false;
        final currentPosition = _currentPositions[messageId] ?? Duration.zero;
        final totalDuration = _totalDurations[messageId] ?? Duration(seconds: durationSeconds);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // زر التشغيل/الإيقاف
            GestureDetector(
              onTap: () => _toggleVoicePlayback(messageId, audioUrl, durationSeconds),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isMe ? Colors.white.withOpacity(0.2) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isMe ? Colors.white.withOpacity(0.3) : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: isMe ? Colors.white : const Color(0xFF0084FF),
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // تمثيل الموجة الصوتية (Instagram-style)
            SizedBox(
              height: 32,
              width: 150,
              child: Stack(
                children: [
                  // خلفية الموجة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(25, (index) {
                      final progress = totalDuration.inMilliseconds > 0
                          ? currentPosition.inMilliseconds / totalDuration.inMilliseconds
                          : 0.0;
                      final isActive = index / 25 <= progress;

                      // إنشاء أطوال مختلفة لكل رسالة باستخدام messageId
                      final messageSeed = messageId.hashCode.abs();
                      final height = 4.0 + ((messageSeed + index * 17) % 20) * 0.8;

                      return Container(
                        width: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 0.5),
                        height: height,
                        decoration: BoxDecoration(
                          color: isMe
                              ? (isActive ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.4))
                              : (isActive ? const Color(0xFF0084FF) : Colors.grey[400]!),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        );

      default:
        return Text(
          message['content'] ?? '',
          style: GoogleFonts.cairo(
            color: isMe ? Colors.white : Colors.black87,
            fontSize: 16,
          ),
        );
    }

    return const SizedBox.shrink();
  }

  String _formatMessageTime(dynamic timestamp) {
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
      return '${messageTime.hour}:${messageTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${messageTime.day}/${messageTime.month} ${messageTime.hour}:${messageTime.minute.toString().padLeft(2, '0')}';
    }
  }

  // Widget مؤشر الكتابة (Instagram-style)
  Widget _buildTypingIndicator() {
    if (!_isOtherUserTyping) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(
          left: 16,
          right: 50,
          bottom: 8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.otherUserName} يكتب',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(width: 8),
            // نقاط التحميل المتحركة
            _TypingDotsAnimation(),
          ],
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
        elevation: 1,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfilePage(
                      userId: widget.otherUserId,
                      initialDisplayName: widget.otherUserName,
                      initialHandle: _otherUserHandle,
                      initialProfileImage: widget.otherUserImage,
                      initialIsVerified: widget.isVerified,
                    ),
                  ),
                );
              },
              child: CircleAvatar(
                radius: 18,
                backgroundImage: widget.otherUserImage.isNotEmpty
                    ? NetworkImage(widget.otherUserImage)
                    : null,
                child: widget.otherUserImage.isEmpty
                    ? Icon(Icons.person, size: 18, color: Colors.grey[600])
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfilePage(
                            userId: widget.otherUserId,
                            initialDisplayName: widget.otherUserName,
                            initialHandle: _otherUserHandle,
                            initialProfileImage: widget.otherUserImage,
                            initialIsVerified: widget.isVerified,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.otherUserName,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified,
                            color: Colors.blue,
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ),
                  // عرض حالة الاتصال مع Firebase
                  _buildOnlineStatus(),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              // يمكن إضافة المزيد من الخيارات هنا
            },
            icon: const Icon(Icons.more_vert, color: Colors.black),
          ),
        ],
      ),
      body: Column(
        children: [
          // قائمة الرسائل
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'ابدأ المحادثة',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length + (_isOtherUserTyping ? 1 : 0),
              itemBuilder: (context, index) {
                // عرض مؤشر الكتابة في أعلى القائمة
                if (_isOtherUserTyping && index == 0) {
                  return _buildTypingIndicator();
                }

                // تعديل الفهرس لحساب مؤشر الكتابة
                final messageIndex = _isOtherUserTyping ? index - 1 : index;
                return _buildMessage(_messages[messageIndex]);
              },
            ),
          ),

          // شريط الرد إذا كان موجود
          if (_replyToMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 40,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'رد على ${_replyToMessage!['senderId'] == currentUserId ? 'نفسك' : widget.otherUserName}',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getReplyPreviewText(_replyToMessage!),
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _clearReply,
                    icon: Icon(
                      Icons.close,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),

          // شريط إدخال الرسالة أو رسالة الحظر
          _isBlocked
              ? Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              border: Border(
                top: BorderSide(color: Colors.red[200]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.block,
                  color: Colors.red[600],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'لا يمكن إرسال رسائل إلى هذا المستخدم',
                    style: GoogleFonts.cairo(
                      color: Colors.red[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Icon(
                  Icons.block,
                  color: Colors.red[600],
                  size: 24,
                ),
              ],
            ),
          )
              : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey[200]!, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: _isBlocked ? null : _showAttachmentOptions,
                  icon: Icon(
                    Icons.add,
                    color: _isBlocked ? Colors.grey[400] : Colors.grey,
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isBlocked ? Colors.grey[200] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isBlocked,
                      decoration: InputDecoration(
                        hintText: _isBlocked ? 'المراسلة معطلة' : 'اكتب رسالة...',
                        hintStyle: GoogleFonts.cairo(
                          color: _isBlocked ? Colors.grey[500] : Colors.grey[600],
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      style: GoogleFonts.cairo(),
                      maxLines: null,
                      textAlign: TextAlign.right,
                      onSubmitted: (_) => _isBlocked ? null : _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: _isBlocked ? Colors.grey[400] : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _isBlocked ? null : _sendMessage,
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Widget نقاط التحميل المتحركة (Instagram-style)
class _TypingDotsAnimation extends StatefulWidget {
  @override
  _TypingDotsAnimationState createState() => _TypingDotsAnimationState();
}

class _TypingDotsAnimationState extends State<_TypingDotsAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller1;
  late AnimationController _controller2;
  late AnimationController _controller3;

  @override
  void initState() {
    super.initState();

    _controller1 = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _controller2 = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _controller3 = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // تشغيل الرسوم المتحركة
    _startAnimation();
  }

  void _startAnimation() {
    // تشغيل النقاط بالتتابع
    _controller1.repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 100), () {
      _controller2.repeat(reverse: true);
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      _controller3.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _controller1,
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 4),
        FadeTransition(
          opacity: _controller2,
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 4),
        FadeTransition(
          opacity: _controller3,
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

// Widget نافذة التسجيل الصوتي
class RecordingDialog extends StatefulWidget {
  final VoidCallback onCancel;
  final Function(Duration) onStop;

  const RecordingDialog({
    super.key,
    required this.onCancel,
    required this.onStop,
  });

  @override
  _RecordingDialogState createState() => _RecordingDialogState();
}

class _RecordingDialogState extends State<RecordingDialog> {
  Duration _duration = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration += const Duration(seconds: 1);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.red,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.mic,
            color: Colors.white,
            size: 60,
          ),
          const SizedBox(height: 16),
          Text(
            'جاري التسجيل...',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatDuration(_duration),
            style: GoogleFonts.cairo(
              color: Colors.white70,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // زر الإلغاء
              ElevatedButton(
                onPressed: widget.onCancel,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white24,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(16),
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              // زر الإيقاف والإرسال
              ElevatedButton(
                onPressed: () => widget.onStop(_duration),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(20),
                ),
                child: const Icon(
                  Icons.send,
                  color: Colors.red,
                  size: 30,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}