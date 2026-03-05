import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../usage_db.dart';

class ScreenTimeService {
  static const MethodChannel _channel = MethodChannel('com.subvampireslayer.screentime');
  static const String _permissionKey = 'has_usage_permission';

  // Mapping system for package names to merchant names
  static const Map<String, String> packageToMerchantMap = {
    'com.netflix.mediaclient': 'Netflix',
    'com.amazon.avod.thirdpartyclient': 'Amazon Prime',
    'com.spotify.music': 'Spotify',
    'com.google.android.youtube': 'YouTube Premium',
    'com.disney.disneyplus': 'Disney+',
    'in.startv.hotstar': 'Hotstar',
    'com.apple.android.music': 'Apple Music',
    'com.gaana': 'Gaana',
    'com.jio.media.jiobeats': 'JioSaavn',
    'com.hulu': 'Hulu',
    'com.hbo.hbonow': 'HBO Max',
  };

  Future<bool> hasUsagePermission() async {
    if (kIsWeb) return true;
    try {
      final bool hasPermission = await _channel.invokeMethod('hasUsagePermission');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionKey, hasPermission);
      return hasPermission;
    } on PlatformException catch (e) {
      print("Failed to check permission: '${e.message}'.");
      return false;
    }
  }

  Future<void> requestUsagePermission() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod('requestUsagePermission');
    } on PlatformException catch (e) {
      print("Failed to request permission: '${e.message}'.");
    }
  }

  Future<void> syncUsageStatsToLocalDB() async {
    if (kIsWeb) return;
    
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    
    final usageList = await getAppUsage(startTime: startOfDay, endTime: now);
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    for (var usage in usageList) {
      String pkg = usage['packageName'] ?? '';
      if (packageToMerchantMap.containsKey(pkg)) {
        int minutes = (usage['totalTimeInForeground'] / (1000 * 60)).round();
        if (minutes > 0) {
          await UsageDatabase.instance.insertUsage(
            pkg, 
            packageToMerchantMap[pkg]!, 
            dateStr, 
            minutes
          );
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> getAppUsage({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (kIsWeb) return [];
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getAppUsage', {
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime.millisecondsSinceEpoch,
      });

      if (result != null) {
        return result.map((e) => Map<String, dynamic>.from(e)).toList();
      }
      return [];
    } on PlatformException catch (e) {
      print("Failed to get usage stats: '${e.message}'.");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTodayStats() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return await UsageDatabase.instance.getUsageForDate(today);
  }

  Future<Map<String, double>> getWeeklyAverageMap() async {
    List<Map<String, dynamic>> allStats = await UsageDatabase.instance.getAllUsage();
    Map<String, List<int>> merchantHistory = {};

    for (var stat in allStats) {
      String merchant = stat['merchant_name'];
      merchantHistory.putIfAbsent(merchant, () => []).add(stat['minutes_used'] as int);
    }

    Map<String, double> averages = {};
    merchantHistory.forEach((merchant, history) {
      double avg = history.reduce((a, b) => a + b) / history.length;
      averages[merchant] = avg;
    });

    return averages;
  }

  Future<bool> syncUsageToBackend(String backendUrl, List<Map<String, dynamic>> usageList) async {
    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/screen-time"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "usage_data": usageList.map((e) => {
            "package_name": e['packageName'],
            "app_name": e['appName'],
            "minutes_used": (e['totalTimeInForeground'] / (1000 * 60)).round(),
            "last_time_used": DateTime.fromMillisecondsSinceEpoch(e['lastTimeUsed']).toIso8601String(),
          }).toList()
        }),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print("Error syncing usage stats: $e");
      return false;
    }
  }
}
