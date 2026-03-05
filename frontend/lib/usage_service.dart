import 'package:usage_stats/usage_stats.dart';
import 'package:intl/intl.dart';
import 'usage_db.dart';
import 'dart:io';

class UsageService {
  static final Map<String, String> packageToMerchantMap = {
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

  static Future<bool> checkPermission() async {
    if (Platform.isAndroid) {
      bool? isGranted = await UsageStats.checkUsagePermission();
      return isGranted ?? false;
    }
    return true; // Not applicable for non-Android
  }

  static Future<void> syncUsageStats() async {
    if (!Platform.isAndroid) return;

    DateTime now = DateTime.now();
    DateTime startOfDay = DateTime(now.year, now.month, now.day);
    DateTime endOfDay = now;

    List<UsageInfo> usageStats = await UsageStats.queryUsageStats(startOfDay, endOfDay);
    String dateStr = DateFormat('yyyy-MM-dd').format(now);

    for (var info in usageStats) {
      String pkg = info.packageName ?? '';
      if (packageToMerchantMap.containsKey(pkg)) {
        int totalTimeInForeground = int.parse(info.totalTimeInForeground ?? '0');
        int minutes = totalTimeInForeground ~/ (1000 * 60);
        
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

  static Future<List<Map<String, dynamic>>> getTodayStats() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return await UsageDatabase.instance.getUsageForDate(today);
  }

  static Future<Map<String, double>> getWeeklyAverage() async {
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
}
