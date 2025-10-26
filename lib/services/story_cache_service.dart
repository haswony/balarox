import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class StoryCacheService {
  static final StoryCacheService _instance = StoryCacheService._internal();
  factory StoryCacheService() => _instance;
  StoryCacheService._internal();

  // Custom cache manager for stories with longer cache duration
  static const _cacheKey = 'story_cache';
  
  // Cache configuration for stories
  static const _maxCacheObjects = 100;
  static const _maxCacheAge = Duration(days: 7);
  
  Future<void> preloadStoryMedia(String url, {bool isVideo = false}) async {
    try {
      // Preload media using the default cache manager
      await DefaultCacheManager().downloadFile(url);
    } catch (e) {
      print('Error preloading story media: $e');
    }
  }

  Future<File?> getCachedFile(String url) async {
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(url);
      return fileInfo?.file;
    } catch (e) {
      print('Error getting cached file: $e');
      return null;
    }
  }

  Future<void> clearStoryCache() async {
    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      print('Error clearing story cache: $e');
    }
  }
  
  // Method to check if media is already cached
  Future<bool> isMediaCached(String url) async {
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(url);
      return fileInfo != null;
    } catch (e) {
      return false;
    }
  }
}