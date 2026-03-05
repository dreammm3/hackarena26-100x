import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/usage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// In-app Session Tracker (works on Web + Mobile)
// ─────────────────────────────────────────────────────────────────────────────
class SessionTracker {
  static final SessionTracker _instance = SessionTracker._();
  SessionTracker._();
  static SessionTracker get instance => _instance;

  // Tracks active session start times keyed by merchant name
  final Map<String, DateTime> _activeSessions = {};
  // Total minutes accumulated this session (persistent in prefs)
  Map<String, int> _sessionMinutes = {};

  void startSession(String merchant) {
    _activeSessions[merchant] = DateTime.now();
  }

  void endSession(String merchant) {
    if (_activeSessions.containsKey(merchant)) {
      final elapsed = DateTime.now().difference(_activeSessions[merchant]!).inSeconds;
      final minutes = (elapsed / 60).ceil();
      _sessionMinutes[merchant] = (_sessionMinutes[merchant] ?? 0) + minutes;
      _activeSessions.remove(merchant);
    }
  }

  int getCurrentMinutes(String merchant) {
    int stored = _sessionMinutes[merchant] ?? 0;
    if (_activeSessions.containsKey(merchant)) {
      final elapsed = DateTime.now().difference(_activeSessions[merchant]!).inSeconds;
      stored += (elapsed / 60).ceil();
    }
    return stored;
  }

  Map<String, int> get allCurrentMinutes {
    final result = Map<String, int>.from(_sessionMinutes);
    _activeSessions.forEach((merchant, start) {
      final elapsed = DateTime.now().difference(start).inSeconds;
      result[merchant] = (result[merchant] ?? 0) + (elapsed / 60).ceil();
    });
    return result;
  }

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final saved = prefs.getString('session_$today');
    if (saved != null) {
      final decoded = jsonDecode(saved) as Map<String, dynamic>;
      _sessionMinutes = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    }
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString('session_$today', jsonEncode(allCurrentMinutes));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permission Page (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
class UsagePermissionPage extends StatefulWidget {
  final VoidCallback onPermissionGranted;
  const UsagePermissionPage({super.key, required this.onPermissionGranted});

  @override
  State<UsagePermissionPage> createState() => _UsagePermissionPageState();
}

class _UsagePermissionPageState extends State<UsagePermissionPage> {
  final ScreenTimeService _service = ScreenTimeService();
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    bool granted = await _service.hasUsagePermission();
    if (granted && mounted) {
      widget.onPermissionGranted();
    } else {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(title: const Text("Permission Required"), backgroundColor: Colors.transparent),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_clock, size: 60, color: Color(0xFFFF0266)),
            const SizedBox(height: 20),
            const Text("Screen Time Access", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text("We need to see which apps you use to identify 'Ghost' subscriptions. Data stays on-device.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await _service.requestUsagePermission();
                  Future.delayed(const Duration(seconds: 1), _checkStatus);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF0266), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text("GRANT ACCESS", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main Screen Time Dashboard
// ─────────────────────────────────────────────────────────────────────────────
class ScreenTimeDashboard extends StatefulWidget {
  final List<dynamic> subscriptions;
  const ScreenTimeDashboard({super.key, this.subscriptions = const []});

  @override
  State<ScreenTimeDashboard> createState() => _ScreenTimeDashboardState();
}

class _ScreenTimeDashboardState extends State<ScreenTimeDashboard> with SingleTickerProviderStateMixin {
  final ScreenTimeService _service = ScreenTimeService();
  late TabController _tabController;
  Timer? _liveTimer;

  // Processed data
  Map<String, int> _todayMinutes = {};
  Map<String, List<int>> _weeklyData = {}; // merchant → 7 day values
  List<String> _weekLabels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initData();
    // Refresh live data every 30 seconds for real-time updates
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refreshLiveSession();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _liveTimer?.cancel();
    SessionTracker.instance.saveToPrefs();
    super.dispose();
  }

  Future<void> _initData() async {
    await SessionTracker.instance.loadFromPrefs();
    await _loadData();
  }

  Future<void> _loadData() async {
    // Generate week labels
    _weekLabels = List.generate(7, (i) {
      final date = DateTime.now().subtract(Duration(days: 6 - i));
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];
    });

    if (kIsWeb) {
      // Web: STRICT mode - show only in-app session data, no mocks.
      final sessionMins = SessionTracker.instance.allCurrentMinutes;
      final Map<String, List<int>> sessionData = {};
      
      for (var entry in sessionMins.entries) {
        sessionData[entry.key] = [...List.filled(6, 0), entry.value];
      }

      _weeklyData = sessionData;
      _todayMinutes = sessionMins;
    } else {
      // Native: use real Android UsageStats
      final now = DateTime.now();
      final Map<String, List<int>> weekData = {};
      
      for (int day = 6; day >= 0; day--) {
        final dayStart = DateTime(now.year, now.month, now.day - day);
        final dayEnd = dayStart.add(const Duration(days: 1));
        final usageList = await _service.getAppUsage(startTime: dayStart, endTime: dayEnd);
        
        for (var usage in usageList) {
          final pkg = usage['packageName']?.toString() ?? '';
          final merchantName = ScreenTimeService.packageToMerchantMap[pkg];
          if (merchantName != null) {
            final mins = ((usage['totalTimeInForeground'] ?? 0) / (1000 * 60)).toInt();
            weekData.putIfAbsent(merchantName, () => List.filled(7, 0));
            weekData[merchantName]![6 - day] = mins;
          }
        }
      }

      _weeklyData = weekData;
      _todayMinutes = Map.fromEntries(weekData.entries.map((e) => MapEntry(e.key, e.value.last)));
    }

    if (mounted) setState(() => _loading = false);
  }

  void _refreshLiveSession() {
    if (kIsWeb) {
      final sessionMins = SessionTracker.instance.allCurrentMinutes;
      for (var entry in sessionMins.entries) {
        if (_weeklyData.containsKey(entry.key)) {
          // Update today's live count (index 6)
          final base = _weeklyData[entry.key]![6];
          _weeklyData[entry.key]![6] = base;
        }
      }
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Screen Time", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () { setState(() => _loading = true); _loadData(); },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFF0266),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: "Today"),
            Tab(text: "7-Day Chart"),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF0266)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTodayTab(),
                _buildWeeklyTab(),
              ],
            ),
    );
  }

  Widget _buildTodayTab() {
    final totalMinutes = _todayMinutes.values.fold(0, (a, b) => a + b);
    final sortedEntries = _todayMinutes.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Live banner
        if (kIsWeb)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 20),
                    SizedBox(width: 8),
                    Text("System Tracking Limited on Web", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  "Browsers block access to other apps for privacy. To track 'Real-Time' usage of Netflix, Spotify, etc., please install the native Android APK.",
                  style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                SizedBox(width: 6),
                Text("LIVE • Native System Tracking Active", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),

        // Total summary card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF6200EE), Color(0xFFBB86FC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: const Color(0xFF6200EE).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Column(
            children: [
              const Text("TOTAL TODAY", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text(
                "${totalMinutes ~/ 60}h ${totalMinutes % 60}m",
                style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text("${sortedEntries.length} subscription apps tracked", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text("Per App Breakdown", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        if (sortedEntries.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Text("No usage data yet today", style: TextStyle(color: Colors.white38)))),

        ...sortedEntries.map((entry) => _buildUsageTile(entry.key, entry.value, totalMinutes)),
      ],
    );
  }

  Widget _buildUsageTile(String merchant, int minutes, int total) {
    final double pct = total > 0 ? minutes / total : 0;
    final bool isGhost = minutes < 5;
    final Color statusColor = isGhost ? Colors.redAccent : (minutes > 60 ? Colors.orangeAccent : Colors.greenAccent);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isGhost ? Colors.redAccent.withOpacity(0.3) : Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(isGhost ? Icons.visibility_off_outlined : Icons.play_circle_outline, color: statusColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(merchant, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(isGhost ? "⚠️ Ghost Alert — very low usage" : "${(pct * 100).toStringAsFixed(0)}% of today's screen time", style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              Text(
                "${minutes}m",
                style: TextStyle(color: statusColor, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyTab() {
    if (_weeklyData.isEmpty) {
      return const Center(child: Text("No weekly data available", style: TextStyle(color: Colors.white38)));
    }
    final sortedApps = _weeklyData.keys.toList()
      ..sort((a, b) => _weeklyData[b]!.reduce((x, y) => x + y).compareTo(_weeklyData[a]!.reduce((x, y) => x + y)));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("7-Day Usage Overview", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text("${_weekLabels.first} — ${_weekLabels.last}", style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 24),
        ...sortedApps.map((app) => _buildMiniBarChart(app, _weeklyData[app]!)),
      ],
    );
  }

  Widget _buildMiniBarChart(String appName, List<int> data) {
    final maxVal = data.reduce(max).toDouble();
    final total = data.reduce((a, b) => a + b);
    final avg = total / data.length;
    final isLowUsage = avg < 10;
    final barColor = isLowUsage ? Colors.redAccent : const Color(0xFF7B61FF);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isLowUsage ? Colors.redAccent.withOpacity(0.25) : Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(appName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              Row(
                children: [
                  if (isLowUsage)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Text("GHOST", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  Text("Avg: ${avg.toStringAsFixed(0)}m", style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Bar chart
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final val = data[i];
                final barH = maxVal > 0 ? (val / maxVal) * 70 : 0.0;
                final isToday = i == 6;
                final color = isToday ? const Color(0xFFFF0266) : barColor;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isToday)
                          Text("${val}m", style: const TextStyle(color: Color(0xFFFF0266), fontSize: 9, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        AnimatedContainer(
                          duration: Duration(milliseconds: 300 + (i * 50)),
                          curve: Curves.easeOut,
                          height: max(4, barH),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                            gradient: isToday
                                ? const LinearGradient(colors: [Color(0xFFFF0266), Color(0xFFFF6B6B)], begin: Alignment.bottomCenter, end: Alignment.topCenter)
                                : LinearGradient(colors: [color.withOpacity(0.5), color], begin: Alignment.bottomCenter, end: Alignment.topCenter),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_weekLabels[i], style: TextStyle(color: isToday ? Colors.white : Colors.white38, fontSize: 10, fontWeight: isToday ? FontWeight.bold : FontWeight.normal)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
