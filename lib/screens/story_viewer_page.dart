import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/database_service.dart';
import '../services/profile_update_service.dart';
import 'chat_page.dart';
import 'user_profile_page.dart'; // Added import for user profile page
import 'package:video_player/video_player.dart';
// Added imports for caching and video compression
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
// Added import for story cache service
import '../services/story_cache_service.dart';
import 'package:url_launcher/url_launcher.dart';

class StoryViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> userStoryGroups;
  final int initialIndex;

  const StoryViewerPage({
    super.key,
    required this.userStoryGroups,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with TickerProviderStateMixin {

  PageController _userPageController = PageController();
  PageController _storyPageController = PageController();

  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  Timer? _autoAdvanceTimer;

  int _currentUserIndex = 0;
  int _currentStoryIndex = 0;
  bool _isPaused = false;
  StreamSubscription? _profileUpdateSubscription;
  StreamSubscription? _displayNameUpdateSubscription; // Added for name updates
  Map<String, String> _updatedProfileImages = {};
  Map<String, String> _updatedDisplayNames = {}; // Added for name updates

  // متغيرات الرد على القصة
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _isReplying = false;

  // متغيرات الإعجاب
  bool _isLiked = false;
  bool _showHeartAnimation = false;

  // متغيرات عرض المشاهدين
  List<Map<String, dynamic>> _storyViewers = [];
  bool _isLoadingViewers = false;
  bool _isViewersSheetOpen = false; // Added to track if viewer sheet is open

  // Video controllers for stories with preloading
  Map<String, VideoPlayerController> _videoControllers = {};
  Map<String, bool> _videoInitialized = {};
  bool _isVideoPlaying = true;

  // Video progress tracking
  Timer? _videoProgressTimer;
  bool _isTrackingVideoProgress = false;

  // New variables for hiding UI elements on long press
  bool _hideUIElements = false;
  late AnimationController _uiFadeController;
  late Animation<double> _uiFadeAnimation;

  // Variable for zoom state
  bool _isZoomed = false;

  // Flag to prevent rapid transitions
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _currentUserIndex = widget.initialIndex;
    _userPageController = PageController(initialPage: widget.initialIndex);

    _progressController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );

    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_progressController);

    // Initialize UI fade animation
    _uiFadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _uiFadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(_uiFadeController);

    // Preload videos for current user
    _preloadVideosForUser(_currentUserIndex);

    _startStoryTimer();

    // الاستماع لتحديثات الصورة الشخصية
    _profileUpdateSubscription = ProfileUpdateService().profileImageUpdates.listen((userId) {
      // تحديث صورة المستخدم في القصص
      _updateUserProfileImage(userId);
    });

    // الاستماع لتحديثات الاسم
    _displayNameUpdateSubscription = ProfileUpdateService().displayNameUpdates.listen((userId) {
      // تحديث اسم المستخدم في القصص
      _updateUserDisplayName(userId);
    });

    // تعيين شريط الحالة للوضع الداكن
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // الاستماع لحالة لوحة المفاتيح
    _replyFocusNode.addListener(() {
      setState(() {
        _isReplying = _replyFocusNode.hasFocus;
      });
      if (_replyFocusNode.hasFocus) {
        _pauseStory();
      } else {
        _resumeStory();
      }
    });
  }

  // Preload videos for better real-time experience with improved caching
  Future<void> _preloadVideosForUser(int userIndex) async {
    if (userIndex >= widget.userStoryGroups.length) return;

    final userStories = List<Map<String, dynamic>>.from(
        widget.userStoryGroups[userIndex]['stories'] ?? []
    );

    // Preload video controllers for video stories
    for (var story in userStories) {
      if (story['isVideo'] == true && !_videoControllers.containsKey(story['id'])) {
        try {
          // Pre-cache the video file using our custom cache service for faster loading
          await StoryCacheService().preloadStoryMedia(story['imageUrl'], isVideo: true);

          final controller = VideoPlayerController.network(story['imageUrl']);
          _videoControllers[story['id']] = controller;

          // Initialize in background
          controller.initialize().then((_) {
            if (mounted) {
              // Move setState to post-frame callback to avoid calling it during build
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _videoInitialized[story['id']] = true;
                  });
                  controller.setLooping(false); // Don't loop, we'll handle transitions

                  // Add listener for video completion
                  controller.addListener(() {
                    if (controller.value.isInitialized &&
                        controller.value.position >= controller.value.duration &&
                        !_isPaused) {
                      // Video completed, move to next story
                      _handleVideoCompletion();
                    }
                  });

                  // Auto-play if this is the current story
                  if (_currentUserIndex == userIndex &&
                      _currentStoryIndex < userStories.length &&
                      userStories[_currentStoryIndex]['id'] == story['id']) {
                    controller.play();
                    setState(() {
                      _isVideoPlaying = true;
                    });
                    // Start progress animation with video duration
                    _startVideoProgress(controller.value.duration.inMilliseconds);
                  }
                }
              });
            }
          }).catchError((error) {
            print('Error initializing video: $error');
            // Mark as initialized even on error to prevent infinite loading
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _videoInitialized[story['id']] = true;
                  });
                }
              });
            }
          });
        } catch (e) {
          print('Error creating video controller: $e');
          // Mark as initialized even on error to prevent infinite loading
          if (mounted) {
            setState(() {
              _videoInitialized[story['id']] = true;
            });
          }
        }
      }
    }

    // Preload neighboring users' videos for seamless transitions
    _preloadNeighborUserVideos(userIndex);
  }

  // Preload videos for neighboring users to ensure smooth transitions
  Future<void> _preloadNeighborUserVideos(int currentUserIndex) async {
    // Preload next user's videos
    if (currentUserIndex + 1 < widget.userStoryGroups.length) {
      final nextUserStories = List<Map<String, dynamic>>.from(
          widget.userStoryGroups[currentUserIndex + 1]['stories'] ?? []
      );

      for (var story in nextUserStories) {
        if (story['isVideo'] == true && !_videoControllers.containsKey(story['id'])) {
          try {
            // Just cache the video file without initializing the controller yet
            StoryCacheService().preloadStoryMedia(story['imageUrl'], isVideo: true);
          } catch (e) {
            print('Error pre-caching next user video: $e');
          }
        }
      }
    }

    // Preload previous user's videos (if not the first user)
    if (currentUserIndex > 0) {
      final prevUserStories = List<Map<String, dynamic>>.from(
          widget.userStoryGroups[currentUserIndex - 1]['stories'] ?? []
      );

      for (var story in prevUserStories) {
        if (story['isVideo'] == true && !_videoControllers.containsKey(story['id'])) {
          try {
            // Just cache the video file without initializing the controller yet
            StoryCacheService().preloadStoryMedia(story['imageUrl'], isVideo: true);
          } catch (e) {
            print('Error pre-caching previous user video: $e');
          }
        }
      }
    }
  }

  Future<void> _updateUserProfileImage(String userId) async {
    final userData = await DatabaseService.getUserFromFirestore(userId);
    if (userData != null && mounted) {
      setState(() {
        _updatedProfileImages[userId] = userData['profileImageUrl'] ?? '';
      });
    }
  }

  // Added method to update user display name
  Future<void> _updateUserDisplayName(String userId) async {
    final userData = await DatabaseService.getUserFromFirestore(userId);
    if (userData != null && mounted) {
      setState(() {
        _updatedDisplayNames[userId] = userData['displayName'] ?? '';
      });
    }
  }

  @override
  void dispose() {
    // إعادة شريط الحالة للوضع العادي
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    _userPageController.dispose();
    _storyPageController.dispose();
    _progressController.dispose();
    _autoAdvanceTimer?.cancel();
    _profileUpdateSubscription?.cancel();
    _displayNameUpdateSubscription?.cancel(); // Added for name updates
    _replyController.dispose();
    _replyFocusNode.dispose();

    // Dispose all video controllers
    _videoControllers.values.forEach((controller) => controller.dispose());
    _videoControllers.clear();
    _videoInitialized.clear();

    _videoProgressTimer?.cancel();

    _uiFadeController.dispose();

    super.dispose();
  }

  // Start progress animation with specific duration
  void _startVideoProgress(int durationMs) {
    _autoAdvanceTimer?.cancel();
    _progressController.stop();
    _progressController.reset();

    // For videos, we'll manually track progress instead of using AnimationController
    _startVideoProgressTracking(durationMs);
  }

  // Manual progress tracking for videos
  void _startVideoProgressTracking(int durationMs) {
    _isTrackingVideoProgress = true;
    _videoProgressTimer?.cancel();

    // Update progress every 50ms for smooth animation
    _videoProgressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final currentStory = _getCurrentStory();
      if (currentStory != null && currentStory['isVideo'] == true) {
        final controller = _videoControllers[currentStory['id']];
        if (controller != null &&
            controller.value.isInitialized &&
            controller.value.duration.inMilliseconds > 0) {

          final progress = controller.value.position.inMilliseconds /
              controller.value.duration.inMilliseconds;

          // Update the progress animation manually
          _progressController.animateTo(
            progress,
            duration: const Duration(milliseconds: 50),
            curve: Curves.linear,
          );

          // Check if video completed
          if (progress >= 1.0 && !_isPaused) {
            _handleVideoCompletion();
          }
        }
      } else {
        // Not a video, stop tracking
        timer.cancel();
        _isTrackingVideoProgress = false;
      }
    });
  }

  // Start default progress animation (for images)
  void _startDefaultProgress() {
    _videoProgressTimer?.cancel();
    _isTrackingVideoProgress = false;
    _autoAdvanceTimer?.cancel();
    _progressController.stop();
    _progressController.reset();

    // Reset to default 5 seconds
    _progressController.duration = const Duration(seconds: 5);
    _progressController.forward();

    // Set timer to advance to next story
    _autoAdvanceTimer = Timer(const Duration(seconds: 5), () {
      if (!_isPaused && mounted && !_isTransitioning) {
        _nextStory();
      }
    });
  }

  void _startStoryTimer() {
    final currentStory = _getCurrentStory();
    if (currentStory != null && currentStory['isVideo'] == true) {
      // For videos, start with video duration if available
      final controller = _videoControllers[currentStory['id']];
      if (controller != null && controller.value.isInitialized) {
        _startVideoProgress(controller.value.duration.inMilliseconds);
      } else {
        // Fallback to default if video not ready
        _startDefaultProgress();
      }
    } else {
      // For images, use default timer
      _startDefaultProgress();
    }
  }

  void _pauseStory() {
    setState(() {
      _isPaused = true;
    });
    _progressController.stop();
    _autoAdvanceTimer?.cancel();
    _videoProgressTimer?.cancel();

    // Pause video if current story is video
    final currentStory = _getCurrentStory();
    if (currentStory != null && currentStory['isVideo'] == true) {
      final controller = _videoControllers[currentStory['id']];
      if (controller != null && controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
        setState(() {
          _isVideoPlaying = false;
        });
      }
    }
  }

  void _resumeStory() {
    setState(() {
      _isPaused = false;
    });

    final currentStory = _getCurrentStory();
    if (currentStory != null && currentStory['isVideo'] == true) {
      // Resume video
      final controller = _videoControllers[currentStory['id']];
      if (controller != null && controller.value.isInitialized && !controller.value.isPlaying) {
        controller.play();
        setState(() {
          _isVideoPlaying = true;
        });
        // Resume progress tracking
        _startVideoProgressTracking(controller.value.duration.inMilliseconds);
      }
    } else {
      // Resume image timer
      final remainingTime = Duration(
        milliseconds: ((1.0 - _progressController.value) * 5000).round(),
      );

      _progressController.forward();

      _autoAdvanceTimer = Timer(remainingTime, () {
        if (!_isPaused && mounted && !_isTransitioning) {
          _nextStory();
        }
      });
    }
  }

  void _handleVideoCompletion() {
    // Video finished playing, move to next story
    if (!_isPaused && mounted && !_isTransitioning) {
      _nextStory();
    }
  }

  void _nextStory() {
    // Prevent rapid transitions
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
    });

    // Reset transition flag after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTransitioning = false;
        });
      }
    });

    final currentUserStories = _getCurrentUserStories();

    if (_currentStoryIndex < currentUserStories.length - 1) {
      setState(() {
        _currentStoryIndex++;
      });
      _storyPageController.jumpToPage(_currentStoryIndex);
      _markCurrentStoryAsViewed();
      _startStoryTimer();
    } else {
      _nextUser();
    }
  }

  void _previousStory() {
    // Prevent rapid transitions
    if (_isTransitioning) return;

    setState(() {
      _isTransitioning = true;
    });

    // Reset transition flag after a short delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTransitioning = false;
        });
      }
    });

    if (_currentStoryIndex > 0) {
      setState(() {
        _currentStoryIndex--;
      });
      _storyPageController.jumpToPage(_currentStoryIndex);
      _startStoryTimer();
    } else {
      _previousUser();
    }
  }

  void _nextUser() {
    // Stop any ongoing timers
    _autoAdvanceTimer?.cancel();
    _videoProgressTimer?.cancel();
    _progressController.stop();

    // تمييز جميع قصص المستخدم الحالي كمشاهدة قبل الانتقال
    _markAllUserStoriesAsViewed();

    if (_currentUserIndex < widget.userStoryGroups.length - 1) {
      setState(() {
        _currentUserIndex++;
        _currentStoryIndex = 0;
      });

      // Preload videos for the next user
      _preloadVideosForUser(_currentUserIndex);

      _userPageController.jumpToPage(_currentUserIndex);
      _storyPageController = PageController();
      _markCurrentStoryAsViewed();
      _startStoryTimer();
    } else {
      // تمييز جميع قصص المستخدم الحالي كمشاهدة قبل الإغلاق
      _markAllUserStoriesAsViewed();
      // انتظار قصير قبل الإغلاق للتأكد من حفظ البيانات
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          Navigator.pop(context, widget.userStoryGroups);
        }
      });
    }
  }

  void _previousUser() {
    // Stop any ongoing timers
    _autoAdvanceTimer?.cancel();
    _videoProgressTimer?.cancel();
    _progressController.stop();

    if (_currentUserIndex > 0) {
      setState(() {
        _currentUserIndex--;
        _currentStoryIndex = 0;
      });

      // Preload videos for the previous user
      _preloadVideosForUser(_currentUserIndex);

      _userPageController.jumpToPage(_currentUserIndex);
      _storyPageController = PageController();
      _startStoryTimer();
      // إعادة تعيين حالة الإعجاب
      setState(() {
        _isLiked = false;
      });
    } else {
      // تمييز جميع قصص المستخدم الحالي كمشاهدة قبل الإغلاق
      _markAllUserStoriesAsViewed();
      // انتظار قريد قبل الإغلاق للتأكد من حفظ البيانات
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _markCurrentStoryAsViewed() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null) {
      final currentStory = _getCurrentStory();
      if (currentStory != null) {
        // تمييز القصة كمشاهدة سواء كانت للمستخدم الحالي أو لآخرين
        DatabaseService.markStoryAsViewed(currentStory['id'], currentUserId);

        // تحديث فوري للحالة المحلية لإخفاء الدائرة الحمراء
        _updateLocalStoryViewState(currentStory['id'], currentUserId);
      }
    }
  }

  void _updateLocalStoryViewState(String storyId, String userId) {
    // تحديث حالة المشاهدة محلياً في البيانات
    for (var userGroup in widget.userStoryGroups) {
      List<Map<String, dynamic>> stories = userGroup['stories'] ?? [];
      for (var story in stories) {
        if (story['id'] == storyId) {
          List<dynamic> viewers = List.from(story['viewers'] ?? []);
          if (!viewers.contains(userId)) {
            viewers.add(userId);
            story['viewers'] = viewers;
          }

          // إعادة حساب hasUnseenStories للمستخدم
          bool hasUnseenStories = false;
          for (var storyInGroup in stories) {
            List<dynamic> storyViewers = storyInGroup['viewers'] ?? [];
            if (!storyViewers.contains(userId)) {
              hasUnseenStories = true;
              break;
            }
          }
          userGroup['hasUnseenStories'] = hasUnseenStories;
          break;
        }
      }
    }
  }

  void _markAllUserStoriesAsViewed() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null) {
      final userStories = _getCurrentUserStories();
      final storyIds = userStories.map((story) => story['id'] as String).toList();
      if (storyIds.isNotEmpty) {
        DatabaseService.markMultipleStoriesAsViewed(storyIds, currentUserId);

        // تحديث فوري للحالة المحلية
        for (String storyId in storyIds) {
          _updateLocalStoryViewState(storyId, currentUserId);
        }
      }
    }
  }

  List<Map<String, dynamic>> _getCurrentUserStories() {
    if (_currentUserIndex < widget.userStoryGroups.length) {
      return List<Map<String, dynamic>>.from(
          widget.userStoryGroups[_currentUserIndex]['stories'] ?? []
      );
    }
    return [];
  }

  Map<String, dynamic>? _getCurrentStory() {
    final stories = _getCurrentUserStories();
    if (_currentStoryIndex < stories.length) {
      return stories[_currentStoryIndex];
    }
    return null;
  }

  Future<void> _sendStoryReply() async {
    final message = _replyController.text.trim();
    if (message.isEmpty) return;

    final currentStory = _getCurrentStory();
    final userStoryGroup = widget.userStoryGroups[_currentUserIndex];

    if (currentStory == null || userStoryGroup == null) return;

    try {
      // إنشاء أو الحصول على محادثة
      final chatId = await DatabaseService.createOrGetChat(userStoryGroup['userId']);

      // إرسال رد القصة
      await DatabaseService.sendStoryReply(
        chatId: chatId,
        message: message,
        storyData: {
          'id': currentStory['id'],
          'imageUrl': currentStory['imageUrl'],
          'caption': currentStory['caption'],
          'userId': userStoryGroup['userId'],
          'userDisplayName': userStoryGroup['userDisplayName'],
          'userProfileImage': userStoryGroup['userProfileImage'],
        },
      );

      _replyController.clear();
      _replyFocusNode.unfocus();

      // عرض رسالة نجاح
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إرسال ردك على القصة',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل إرسال الرد',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _likeStory() async {
    final currentStory = _getCurrentStory();
    final userStoryGroup = widget.userStoryGroups[_currentUserIndex];

    if (currentStory == null || userStoryGroup == null) return;

    // عرض أنيميشن القلب
    setState(() {
      _isLiked = true;
      _showHeartAnimation = true;
    });

    // إخفاء الأنيميشن بعد ثانية
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showHeartAnimation = false;
        });
      }
    });

    try {
      // إنشاء أو الحصول على محادثة
      final chatId = await DatabaseService.createOrGetChat(userStoryGroup['userId']);

      // إرسال إعجاب بالقصة
      await DatabaseService.sendStoryReply(
        chatId: chatId,
        message: '❤️ أعجب بقصتك',
        storyData: {
          'id': currentStory['id'],
          'imageUrl': currentStory['imageUrl'],
          'caption': currentStory['caption'],
          'userId': userStoryGroup['userId'],
          'userDisplayName': userStoryGroup['userDisplayName'],
          'userProfileImage': userStoryGroup['userProfileImage'],
        },
      );
    } catch (e) {
      print('خطأ في إرسال الإعجاب: $e');
    }
  }

  Future<void> _contactUser() async {
    final userStoryGroup = widget.userStoryGroups[_currentUserIndex];
    final userData = await DatabaseService.getUserFromFirestore(userStoryGroup['userId']);
    final phoneNumber = userData?['phoneNumber'];

    if (phoneNumber != null && phoneNumber.isNotEmpty) {
      final uri = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'لا يمكن إجراء المكالمة',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'رقم الهاتف غير متوفر',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Method to toggle UI elements visibility with animation
  void _toggleUIElements(bool hide) {
    setState(() {
      _hideUIElements = hide;
    });

    if (hide) {
      _uiFadeController.forward();
    } else {
      _uiFadeController.reverse();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTapDown: (details) {
          // Only pause if not replying, viewer sheet is not open, and not zoomed
          if (!_isReplying && !_isViewersSheetOpen && !_isZoomed) {
            _pauseStory();
          }
        },
        onTapUp: (details) {
          // Only handle tap if not replying, viewer sheet is not open, and not zoomed
          if (!_isReplying && !_isViewersSheetOpen && !_isZoomed) {
            final screenWidth = MediaQuery.of(context).size.width;
            if (details.localPosition.dx < screenWidth / 3) {
              // النقر على الجانب الأيسر - القصة السابقة
              _previousStory();
            } else if (details.localPosition.dx > screenWidth * 2 / 3) {
              // النقر على الجانب الأيمن - القصة التالية
              _markCurrentStoryAsViewed();
              _nextStory();
            } else {
              // النقر في الوسط - استكمال التشغيل
              _markCurrentStoryAsViewed();
              _resumeStory();
            }
          }
        },
        onTapCancel: () {
          // Only resume if not replying, viewer sheet is not open, and not zoomed
          if (!_isReplying && !_isViewersSheetOpen && !_isZoomed) {
            _resumeStory();
          }
        },
        onLongPressStart: (details) {
          // Only pause if not replying, viewer sheet is not open, and not zoomed
          if (!_isReplying && !_isViewersSheetOpen && !_isZoomed) {
            _pauseStory();
            _toggleUIElements(true); // Hide UI elements on long press
          }
        },
        onLongPressEnd: (details) {
          // Only resume if not replying, viewer sheet is not open, and not zoomed
          if (!_isReplying && !_isViewersSheetOpen && !_isZoomed) {
            _resumeStory();
            _toggleUIElements(false); // Show UI elements when releasing
          }
        },
        child: PageView.builder(
          controller: _userPageController,
          itemCount: widget.userStoryGroups.length,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            // Prevent rapid page changes
            if (_isTransitioning) return;

            setState(() {
              _isTransitioning = true;
              _currentUserIndex = index;
              _currentStoryIndex = 0;
            });

            // Reset transition flag after a short delay
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) {
                setState(() {
                  _isTransitioning = false;
                });
              }
            });

            _storyPageController = PageController();
            _markCurrentStoryAsViewed();
            _startStoryTimer();
            // إعادة تعيين حالة الإعجاب
            setState(() {
              _isLiked = false;
            });
          },
          itemBuilder: (context, userIndex) {
            final userStoryGroup = widget.userStoryGroups[userIndex];
            final stories = List<Map<String, dynamic>>.from(
                userStoryGroup['stories'] ?? []
            );

            // التحقق إذا كان المستخدم الحالي هو صاحب القصة
            final isStoryOwner = userStoryGroup['userId'] == FirebaseAuth.instance.currentUser?.uid;

            return Stack(
              children: [
                // Story Content
                PageView.builder(
                  controller: _storyPageController,
                  itemCount: stories.length,
                  physics: const NeverScrollableScrollPhysics(), // انتقال سلس
                  onPageChanged: (storyIndex) {
                    // Prevent rapid page changes
                    if (_isTransitioning) return;

                    setState(() {
                      _isTransitioning = true;
                      _currentStoryIndex = storyIndex;
                      _isLiked = false; // إعادة تعيين حالة الإعجاب
                    });

                    // Reset transition flag after a short delay
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) {
                        setState(() {
                          _isTransitioning = false;
                        });
                      }
                    });

                    _markCurrentStoryAsViewed();
                    _startStoryTimer();
                  },
                  itemBuilder: (context, storyIndex) {
                    final story = stories[storyIndex];
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final aspectRatio = 9 / 16; // نسبة Instagram Stories
                        final containerHeight = constraints.maxHeight;
                        final containerWidth = constraints.maxWidth;

                        // حساب الأبعاد المناسبة للقصة
                        double storyWidth, storyHeight;
                        if (containerWidth / containerHeight > aspectRatio) {
                          storyHeight = containerHeight;
                          storyWidth = storyHeight * aspectRatio;
                        } else {
                          storyWidth = containerWidth;
                          storyHeight = storyWidth / aspectRatio;
                        }

                        return Center(
                          child: Container(
                            width: storyWidth,
                            height: storyHeight,
                            child: Stack(
                              children: [
                                // الصورة أو الفيديو
                                Positioned.fill(
                                  child: story['isVideo'] == true
                                      ? _buildVideoStory(story)
                                      : _buildImageStory(story),
                                ),

                                // النصوص المخصصة إذا كانت موجودة
                                if (story['textOverlays'] != null)
                                  ...((story['textOverlays'] as List<dynamic>).map((textOverlay) {
                                    return Positioned(
                                      left: (textOverlay['x'] ?? 0.5) * storyWidth - 50,
                                      top: (textOverlay['y'] ?? 0.5) * storyHeight - 20,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Color(textOverlay['backgroundColor'] ?? 0x80000000),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          textOverlay['text'] ?? '',
                                          style: GoogleFonts.cairo(
                                            color: Color(textOverlay['color'] ?? 0xFFFFFFFF),
                                            fontSize: (textOverlay['fontSize'] ?? 24).toDouble(),
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    );
                                  }).toList()),

                                // دعم النص المخصص القديم للتوافق مع القصص السابقة
                                if (story['textOverlay'] != null && story['textOverlays'] == null)
                                  Positioned(
                                    left: (story['textOverlay']['x'] ?? 0.5) * storyWidth - 100,
                                    top: (story['textOverlay']['y'] ?? 0.5) * storyHeight - 50,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Color(story['textOverlay']['backgroundColor'] ?? 0x80000000),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        story['textOverlay']['text'] ?? '',
                                        style: GoogleFonts.cairo(
                                          color: Color(story['textOverlay']['textColor'] ?? 0xFFFFFFFF),
                                          fontSize: (story['textOverlay']['fontSize'] ?? 16).toDouble(),
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // Progress Bars - محسنة مع أنيميشن أفضل
                Positioned(
                  top: 50,
                  left: 8,
                  right: 8,
                  child: AnimatedOpacity(
                    opacity: (!_hideUIElements && !_isZoomed) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      children: stories.asMap().entries.map((entry) {
                        int index = entry.key;
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: Colors.white.withOpacity(0.3),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: AnimatedBuilder(
                                animation: _progressAnimation,
                                builder: (context, child) {
                                  double progress = 0.0;
                                  if (index < _currentStoryIndex) {
                                    progress = 1.0;
                                  } else if (index == _currentStoryIndex) {
                                    progress = _progressAnimation.value;
                                  }

                                  return LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.transparent,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // User Info Header (restored to original)
                Positioned(
                  top: 60,
                  left: 16,
                  right: 16,
                  child: AnimatedOpacity(
                    opacity: (!_hideUIElements && !_isZoomed) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      children: [
                        // Optimized profile image to prevent flickering
                        Builder(
                            builder: (context) {
                              final profileImageUrl = _updatedProfileImages[userStoryGroup['userId']] ?? userStoryGroup['userProfileImage'];
                              return CircleAvatar(
                                radius: 20,
                                backgroundImage: profileImageUrl?.isNotEmpty == true
                                    ? NetworkImage(profileImageUrl)
                                    : null,
                                child: profileImageUrl?.isEmpty != false
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              );
                            }
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StreamBuilder<Map<String, dynamic>?>(
                                stream: _getUserDataStream(userStoryGroup['userId']),
                                builder: (context, snapshot) {
                                  if (snapshot.hasData && snapshot.data != null) {
                                    final userData = snapshot.data!;
                                    final displayName = userData['displayName'] as String?;

                                    return Text(
                                      displayName?.isNotEmpty == true
                                          ? displayName!
                                          : 'مستخدم',
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    );
                                  }

                                  return Text(
                                    _updatedDisplayNames[userStoryGroup['userId']]?.isNotEmpty == true
                                        ? _updatedDisplayNames[userStoryGroup['userId']]!
                                        : (userStoryGroup['userDisplayName']?.isNotEmpty == true
                                        ? userStoryGroup['userDisplayName']
                                        : 'مستخدم'),
                                    style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.7),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              Text(
                                _getTimeAgo(stories[_currentStoryIndex]['createdAt']),
                                style: GoogleFonts.cairo(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // إضافة زر عرض المشاهدين لصاحب القصة
                        if (isStoryOwner) ...[
                          IconButton(
                            onPressed: () => _showStoryViewers(userStoryGroup['stories']),
                            icon: const Icon(
                              Icons.visibility,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // أيقونة القائمة المنسدلة
                          IconButton(
                            onPressed: () => _showStoryOptionsMenu(),
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // أنيميشن القلب عند الإعجاب
                if (_showHeartAnimation)
                  Positioned.fill(
                    child: Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 800),
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value < 0.5
                                ? 1.0 + (value * 2)
                                : 2.0 - ((value - 0.5) * 2),
                            child: Opacity(
                              opacity: value < 0.7 ? 1.0 : 1.0 - ((value - 0.7) * 3.33),
                              child: Icon(
                                Icons.favorite,
                                color: Colors.red,
                                size: 100,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // Story Caption
                if (stories[_currentStoryIndex]['caption']?.isNotEmpty == true)
                  Positioned(
                    bottom: isStoryOwner ? 20 : 100, // Adjust position based on whether it's the owner
                    left: 16,
                    right: 16,
                    child: AnimatedOpacity(
                      opacity: (!_hideUIElements && !_isZoomed) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          stories[_currentStoryIndex]['caption'] ?? '',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),

                // Instagram-style message input at bottom (only for non-owners)
                if (!isStoryOwner)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      opacity: (!_hideUIElements && !_isZoomed) ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom > 0
                              ? MediaQuery.of(context).viewInsets.bottom
                              : MediaQuery.of(context).padding.bottom,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.3),
                              Colors.black.withOpacity(0.5),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.5),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _replyController,
                                          focusNode: _replyFocusNode,
                                          style: GoogleFonts.cairo(
                                            color: Colors.white,
                                            fontSize: 16,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: userStoryGroup['userId'] == FirebaseAuth.instance.currentUser?.uid
                                                ? 'أضف تعليقاً على قصتك...'
                                                : 'أرسل رسالة إلى ${userStoryGroup['userDisplayName'] ?? 'المستخدم'}',
                                            hintStyle: GoogleFonts.cairo(
                                              color: Colors.white.withOpacity(0.6),
                                              fontSize: 14,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 12,
                                            ),
                                          ),
                                          textAlign: TextAlign.right,
                                          onSubmitted: (_) => _sendStoryReply(),
                                        ),
                                      ),
                                      if (_replyController.text.isNotEmpty)
                                        IconButton(
                                          onPressed: _sendStoryReply,
                                          icon: const Icon(
                                            Icons.send,
                                            color: Colors.white,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (userStoryGroup['userId'] != FirebaseAuth.instance.currentUser?.uid) ...[
                                const SizedBox(width: 12),
                                // أيقونة الإعجاب مع أنيميشن
                                GestureDetector(
                                  onTap: _likeStory,
                                  child: AnimatedScale(
                                    scale: _isLiked ? 1.2 : 1.0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      _isLiked ? Icons.favorite : Icons.favorite_border,
                                      color: _isLiked ? Colors.red : Colors.white,
                                      size: 28,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // أيقونة الاتصال
                                GestureDetector(
                                  onTap: _contactUser,
                                  child: Icon(
                                    Icons.phone,
                                    color: Colors.white,
                                    size: 28,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Helper method to initialize video controller for a story with better preloading
  Future<void> _initializeVideoController(Map<String, dynamic> story) async {
    if (story['isVideo'] == true && !_videoControllers.containsKey(story['id'])) {
      try {
        // Pre-cache the video using CacheManager for faster loading
        await DefaultCacheManager().downloadFile(story['imageUrl']);

        final controller = VideoPlayerController.network(story['imageUrl']);
        _videoControllers[story['id']] = controller;

        await controller.initialize();
        controller.setLooping(false); // Don't loop, we'll handle transitions

        // Add listener for video state changes
        controller.addListener(() {
          if (mounted) {
            // Check if video completed
            if (controller.value.isInitialized &&
                controller.value.position >= controller.value.duration &&
                !_isPaused) {
              // Video completed, move to next story
              _handleVideoCompletion();
            }
          }
        });

        if (mounted) {
          // Move setState to post-frame callback to avoid calling it during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _videoInitialized[story['id']] = true;
              });

              // Auto-play if this is the current story
              final currentStory = _getCurrentStory();
              if (currentStory != null && currentStory['id'] == story['id']) {
                controller.play();
                setState(() {
                  _isVideoPlaying = true;
                });
                // Start progress animation with video duration
                _startVideoProgress(controller.value.duration.inMilliseconds);
              }
            }
          });
        }
      } catch (e) {
        print('Error initializing video controller: $e');
        // Even if initialization fails, mark as initialized to prevent infinite loading
        if (mounted) {
          setState(() {
            _videoInitialized[story['id']] = true;
          });
        }
      }
    }

    // استكمال القصة بعد انتهاء عملية الحذف
    _resumeStory();
  }

  // Optimized video story builder with preloading, zoom/pan, and no loading indicator
  Widget _buildVideoStory(Map<String, dynamic> story) {
    final controller = _videoControllers[story['id']];

    if (controller == null) {
      // If controller doesn't exist, create it now
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_videoControllers.containsKey(story['id'])) {
          _initializeVideoController(story);
        }
      });

      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(), // Empty widget instead of loading indicator
        ),
      );
    }

    // Fix: Properly handle nullable boolean
    final isInitialized = _videoInitialized[story['id']] ?? false;
    if (!isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(), // Empty widget instead of loading indicator
        ),
      );
    }

    if (!controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(), // Empty widget instead of loading indicator
        ),
      );
    }

    // Auto-play when widget is built if it's the current story
    // Move setState to post-frame callback to avoid calling it during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final currentStory = _getCurrentStory();
        if (currentStory != null && currentStory['id'] == story['id']) {
          if (controller.value.isInitialized && !controller.value.isPlaying) {
            controller.play();
            controller.setLooping(false);
            // Update state safely
            setState(() {
              _isVideoPlaying = true;
            });
            // Start progress tracking
            _startVideoProgress(controller.value.duration.inMilliseconds);
          }
        }
      }
    });

    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 3.0,
      onInteractionUpdate: (details) {
        if (details.scale > 1.2 && !_isZoomed) {
          setState(() {
            _isZoomed = true;
          });
          _pauseStory();
        } else if (details.scale < 0.9 && _isZoomed) {
          setState(() {
            _isZoomed = false;
          });
          _resumeStory();
        }
      },
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: controller.value.size.width,
          height: controller.value.size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  // Optimized image story builder with caching, zoom/pan, and no loading indicator
  Widget _buildImageStory(Map<String, dynamic> story) {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 3.0,
      onInteractionUpdate: (details) {
        if (details.scale > 1.2 && !_isZoomed) {
          setState(() {
            _isZoomed = true;
          });
          _pauseStory();
        } else if (details.scale < 0.9 && _isZoomed) {
          setState(() {
            _isZoomed = false;
          });
          _resumeStory();
        }
      },
      child: CachedNetworkImage(
        imageUrl: story['imageUrl'] ?? '',
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => Container(
          color: Colors.black,
          child: const Center(
            child: SizedBox(), // Empty widget instead of loading indicator
          ),
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[800],
          child: const Center(
            child: Icon(
              Icons.error,
              color: Colors.white,
              size: 50,
            ),
          ),
        ),
        cacheManager: DefaultCacheManager(),
      ),
    );
  }

  String _getTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime storyTime;
    if (timestamp is DateTime) {
      storyTime = timestamp;
    } else {
      storyTime = timestamp.toDate();
    }

    final now = DateTime.now();
    final difference = now.difference(storyTime);

    if (difference.inHours < 1) {
      return '${difference.inMinutes}د';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}س';
    } else {
      return '${difference.inDays}ي';
    }
  }

  // Stream للحصول على بيانات المستخدم بشكل ديناميكي
  Stream<Map<String, dynamic>?> _getUserDataStream(String userId) async* {
    // أولاً نرجع القيمة المخزنة مؤقتاً إذا كانت متوفرة
    if (_updatedDisplayNames.containsKey(userId) && _updatedDisplayNames[userId]!.isNotEmpty) {
      yield {
        'displayName': _updatedDisplayNames[userId],
      };
    }

    // ثم نجلب البيانات من قاعدة البيانات
    try {
      final userData = await DatabaseService.getUserFromFirestore(userId);
      if (userData != null) {
        yield userData;
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }
  }

  // دالة لعرض قائمة المشاهدين
  Future<void> _showStoryViewers(List<dynamic> stories) async {
    // Pause the story when opening the viewer list
    _pauseStory();

    setState(() {
      _isLoadingViewers = true;
      _isViewersSheetOpen = true; // Mark the sheet as open
    });

    try {
      // جلب معرفات القصص
      final storyIds = List<String>.from(stories.map((story) => story['id'] as String));

      // جلب المشاهدين
      final viewers = await DatabaseService.getUserStoryViewers(storyIds);

      setState(() {
        _storyViewers = viewers;
        _isLoadingViewers = false;
      });

      // عرض قائمة المشاهدين في زرقة من الأسفل
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) {
          return _buildViewersBottomSheet();
        },
      ).whenComplete(() {
        // Resume the story when the viewer list is closed
        if (mounted) {
          setState(() {
            _isViewersSheetOpen = false; // Mark the sheet as closed
          });
          _resumeStory();
        }
      });
    } catch (e) {
      setState(() {
        _isLoadingViewers = false;
        _isViewersSheetOpen = false; // Mark the sheet as closed on error
      });

      // Resume the story on error
      _resumeStory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error loading viewers',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // بناء واجهة قائمة المشاهدين
  Widget _buildViewersBottomSheet() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // مقبض السحب
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // عنوان القائمة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Story Viewers',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_storyViewers.length} viewers',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // قائمة المشاهدين
          Expanded(
            child: _isLoadingViewers
                ? const Center(child: CircularProgressIndicator())
                : _storyViewers.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_off,
                    size: 60,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No viewers yet',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Share your story to get more views',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _storyViewers.length,
              itemBuilder: (context, index) {
                final viewer = _storyViewers[index];
                return _buildViewerItem(viewer);
              },
            ),
          ),
        ],
      ),
    );
  }

  // بناء عنصر المشاهد
  Widget _buildViewerItem(Map<String, dynamic> viewer) {
    return FutureBuilder<int>(
        future: DatabaseService.getUserPostsCount(viewer['id']),
        builder: (context, snapshot) {
          final postsCount = snapshot.data ?? 0;
          final lastSeen = viewer['lastSeen'] as DateTime?;
          final lastSeenText = lastSeen != null ? _getTimeAgoEnglish(lastSeen) : '';
          final postsText = postsCount == 1 ? '1 post' : '$postsCount posts';
          final isVerified = viewer['isVerified'] as bool? ?? false;

          return InkWell(
            onTap: () {
              // الانتقال إلى صفحة الملف الشخصي للمشاهد
              Navigator.pop(context); // إغلاق الـ bottom sheet
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfilePage(userId: viewer['id']),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  // صورة الملف الشخصي
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundImage: viewer['profileImageUrl'] != null && viewer['profileImageUrl'].isNotEmpty
                            ? NetworkImage(viewer['profileImageUrl'])
                            : null,
                        child: viewer['profileImageUrl'] == null || viewer['profileImageUrl'].isEmpty
                            ? const Icon(Icons.person, size: 25)
                            : null,
                      ),
                      // شارة التحقق للمستخدمين الموثقين
                      if (isVerified)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                BorderSide(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 15),

                  // اسم المستخدم وعدد المنشورات وآخر مشاهدة
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              viewer['displayName'] ?? 'User',
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isVerified) ...[
                              const SizedBox(width: 5),
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
                          '$postsText${lastSeenText.isNotEmpty ? ' • $lastSeenText ago' : ''}',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // أيقونة الانتقال
                  const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          );
        }
    );
  }

  // دالة للحصول على الوقت المنقضي بالإنجليزي
  String _getTimeAgoEnglish(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime storyTime;
    if (timestamp is DateTime) {
      storyTime = timestamp;
    } else {
      storyTime = timestamp.toDate();
    }

    final now = DateTime.now();
    final difference = now.difference(storyTime);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h';
    } else {
      return '${difference.inDays}d';
    }
  }

  // دالة لعرض قائمة خيارات القصة
  void _showStoryOptionsMenu() async {
    // إيقاف القصة عند فتح القائمة
    _pauseStory();

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // خيار حذف القصة
              ListTile(
                title: Center(
                  child: Text(
                    'حذف القصة',
                    style: GoogleFonts.cairo(
                      color: Colors.red,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context, 'delete'); // إغلاق القائمة مع إشارة الحذف
                },
              ),
            ],
          ),
        );
      },
    );

    // استكمال القصة عند إغلاق القائمة فقط إذا لم يتم اختيار الحذف
    if (result != 'delete') {
      _resumeStory();
    } else {
      // إذا تم اختيار الحذف، ابدأ عملية الحذف
      _deleteCurrentStory();
    }
  }

  // دالة لحذف القصة الحالية
  void _deleteCurrentStory() async {
    final currentStory = _getCurrentStory();
    if (currentStory == null) return;

    // إيقاف القصة أثناء رسالة التأكيد
    _pauseStory();

    // عرض رسالة تأكيد الحذف
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.8),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // عنوان
                Text(
                  'حذف القصة',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // وصف
                Text(
                  'هل أنت متأكد من حذف هذه القصة؟',
                  style: GoogleFonts.cairo(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // أزرار
                Row(
                  children: [
                    // زر إلغاء
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(color: Colors.white.withOpacity(0.3)),
                          ),
                        ),
                        child: Text(
                          'إلغاء',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // زر حذف
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: Text(
                          'حذف',
                          style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    // إذا أكد المستخدم الحذف
    if (shouldDelete == true) {
      // حذف فوري من البيانات المحلية لتجربة سلسة
      final userStories = widget.userStoryGroups[_currentUserIndex]['stories'] as List<Map<String, dynamic>>;
      final storyIndex = userStories.indexWhere((story) => story['id'] == currentStory['id']);

      if (storyIndex != -1) {
        // Dispose video controller for the deleted story
        if (_videoControllers.containsKey(currentStory['id'])) {
          _videoControllers[currentStory['id']]!.dispose();
          _videoControllers.remove(currentStory['id']);
          _videoInitialized.remove(currentStory['id']);
        }

        // إزالة القصة من البيانات المحلية فوراً
        userStories.removeAt(storyIndex);

        // تعديل فهرس القصة الحالية إذا لزم الأمر
        if (_currentStoryIndex > storyIndex) {
          // إذا كانت القصة المحذوفة قبل القصة الحالية، قلل الفهرس
          _currentStoryIndex--;
        } else if (_currentStoryIndex == storyIndex) {
          // إذا كانت القصة المحذوفة هي الحالية
          if (_currentStoryIndex >= userStories.length) {
            // إذا كانت الأخيرة، انتقل إلى السابقة
            _currentStoryIndex = userStories.length - 1;
          }
          // إذا كانت في الوسط، تبقى نفس الفهرس (الذي أصبح القصة التالية)
        }

        // الانتقال إلى القصة التالية أو السابقة
        if (userStories.isNotEmpty) {
          // إعادة تحديث الواجهة فوراً
          setState(() {});

          // إعادة تهيئة PageController للقصص لضمان التنقل الصحيح
          _storyPageController = PageController(initialPage: _currentStoryIndex);

          _startStoryTimer();
        } else {
          // إذا لم تعد هناك قصص، الانتقال إلى المستخدم التالي أو إغلاق
          _nextUser();
        }
      }

      // حذف من قاعدة البيانات في الخلفية (لا يؤثر على تجربة المستخدم)
      DatabaseService.deleteStory(currentStory['id']).catchError((e) {
        // في حالة فشل الحذف من قاعدة البيانات، أعد إضافة القصة محلياً
        if (mounted) {
          userStories.insert(storyIndex, currentStory);
          setState(() {});
        }

        // عرض رسالة خطأ
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'فشل في حذف القصة',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      });
    } else {
      // إذا ألغى المستخدم، استكمل القصة فوراً
      _resumeStory();
    }
  }

}