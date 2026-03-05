import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/usage_service.dart';
import 'screens/ghost_address_screen.dart';
import 'screens/usage_dashboard_screen.dart';
import 'screens/home_dashboard_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/ai_chat_screen.dart';

const String syncUsageTask = "com.subvampireslayer.syncUsage";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final service = ScreenTimeService();
    await service.syncUsageStatsToLocalDB();
    
    final today = await service.getTodayStats();
    if (today.isNotEmpty) {
      await service.syncUsageToBackend("http://10.0.2.2:8000", today.map((e) => {
        'packageName': e['package_name'],
        'appName': e['merchant_name'],
        'totalTimeInForeground': (e['minutes_used'] * 60 * 1000),
        'lastTimeUsed': DateTime.now().millisecondsSinceEpoch
      }).toList());
    }
    return Future.value(true);
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
    Workmanager().registerPeriodicTask(
      "1",
      syncUsageTask,
      frequency: const Duration(hours: 4),
    );
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SubVampire Slayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6200EE),
          secondary: const Color(0xFFFF0266),
          brightness: Brightness.dark,
          surface: const Color(0xFF121212),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 32),
          bodyLarge: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF0266),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 8,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF0266), width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoggedIn = false;
  String? _userId;

  void _onLoginSuccess(String userId) {
    setState(() {
      _isLoggedIn = true;
      _userId = userId;
    });
  }

  void _onLogout() {
    setState(() {
      _isLoggedIn = false;
      _userId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return LoginPage(onLoginSuccess: _onLoginSuccess);
    }
    
    return FutureBuilder<bool>(
      future: ScreenTimeService().hasUsagePermission(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == false) {
          return UsagePermissionPage(onPermissionGranted: () => setState(() {}));
        }
        return DashboardPage(userId: _userId!, onLogout: _onLogout);
      },
    );
  }
}

class PermissionScreen extends StatelessWidget {
  final VoidCallback onGranted;
  const PermissionScreen({super.key, required this.onGranted});

  @override
  Widget build(BuildContext context) {
    final service = ScreenTimeService();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined, size: 80, color: Color(0xFFFF0266)),
            const SizedBox(height: 32),
            Text("Slay the Zombies", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            const Text(
              "To find subscriptions you're paying for but not using, we need access to your app usage statistics.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await service.requestUsagePermission();
                  onGranted();
                },
                child: const Text("GRANT ACCESS"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  final Function(String) onLoginSuccess;
  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController(text: "user@example.com");
  final TextEditingController _passwordController = TextEditingController(text: "password");
  bool _isLoading = false;
  String _errorMessage = "";

  final String backendUrl = "http://10.220.205.25:8000";

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": _emailController.text,
          "password": _passwordController.text,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        widget.onLoginSuccess(data['user_id']);
      } else {
        setState(() {
          _errorMessage = "Invalid email or password.";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error connecting to backend: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0266).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security, size: 60, color: Color(0xFFFF0266)),
                  ),
                  const SizedBox(height: 32),
                  Text("SubVampire Slayer", style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text("Kill those hidden subscriptions.", style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email_outlined)),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "Password", prefixIcon: Icon(Icons.lock_outline)),
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 40),
                  _isLoading
                      ? const CircularProgressIndicator(color: Color(0xFFFF0266))
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _login,
                            child: const Text("LOGIN", style: TextStyle(letterSpacing: 1.5, fontSize: 16)),
                          ),
                        ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text("OR", style: TextStyle(color: Colors.white.withOpacity(0.5))),
                      ),
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.3))),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final response = await http.get(Uri.parse("$backendUrl/api/email/sync"));
                          if (response.statusCode == 200) {
                            setState(() {
                              _errorMessage = "Gmail synced successfully! Now login to see results.";
                            });
                          } else {
                            setState(() {
                              _errorMessage = "Gmail sync failed: ${response.statusCode}";
                            });
                          }
                        } catch (e) {
                          setState(() {
                            _errorMessage = "Gmail sync error: $e";
                          });
                        }
                      },
                      icon: const Icon(Icons.mail_outline, color: Colors.white),
                      label: const Text("Sign in with Google", style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 0.5)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  final String userId;
  final VoidCallback onLogout;
  
  const DashboardPage({super.key, required this.userId, required this.onLogout});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final String backendUrl = "http://10.220.205.25:8000";
  List<dynamic> _subscriptions = [];
  Map<String, int> _appUsage = {}; 
  bool _isLoading = true;
  String _error = "";
  int _selectedIndex = 0;
  String _searchQuery = "";
  String _filterType = "All";

  @override
  void initState() {
    super.initState();
    _fetchSubscriptions();
    _fetchUsageData();
    
    /*
    if (!kIsWeb) {
      Workmanager().registerPeriodicTask(
        "1",
        syncUsageTask,
        frequency: const Duration(hours: 24),
        initialDelay: const Duration(minutes: 5),
      );
    }
    */
  }

  Future<void> _fetchUsageData() async {
    final service = ScreenTimeService();
    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    
    final usage = await service.getAppUsage(startTime: thirtyDaysAgo, endTime: now);
    final Map<String, int> usageMap = {};
    for (var item in usage) {
      usageMap[item['packageName']] = (item['totalTimeInForeground'] / (1000 * 60)).round();
    }
    
    setState(() {
      _appUsage = usageMap;
    });
  }

  Future<void> _fetchSubscriptions() async {
    setState(() {
      _isLoading = true;
      _error = "";
    });

    try {
      final response = await http.get(
        Uri.parse("$backendUrl/api/user/subscriptions?user_id=${widget.userId}"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _subscriptions = data['subscriptions'];
        });
      } else {
        setState(() {
          _error = "Failed to load subscriptions: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _error = "Error: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pauseSubscription(String merchantName, {int months = 1, String? untilDate}) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/subscriptions/pause?user_id=${widget.userId}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "merchant_name": merchantName,
          "duration_months": months,
          "until_date": untilDate
        }),
      );
      if (response.statusCode == 200) {
        _fetchSubscriptions();
      }
    } catch (e) {
      print("Pause error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelSubscription(String merchantName) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/subscriptions/cancel?user_id=${widget.userId}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"merchant_name": merchantName}),
      );
      if (response.statusCode == 200) {
        _fetchSubscriptions();
      }
    } catch (e) {
      print("Cancel error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncGmail() async {
    setState(() {
      _isLoading = true;
      _error = "";
    });

    try {
      final response = await http.get(Uri.parse("$backendUrl/api/email/sync"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          List<dynamic> subs = data['subscriptions'];
          _subscriptions.addAll(subs);
        });
      } else {
        setState(() {
          _error = "Failed to sync Gmail: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _error = "Error syncing Gmail: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _syncUsageTime() async {
    final service = ScreenTimeService();
    
    setState(() {
      _isLoading = true;
      _error = "";
    });

    try {
      final now = DateTime.now();
      final sixtyDaysAgo = now.subtract(const Duration(days: 60));
      
      final usage = await service.getAppUsage(startTime: sixtyDaysAgo, endTime: now);
      if (usage.isNotEmpty) {
        final success = await service.syncUsageToBackend(backendUrl, usage);
        if (success) {
           await _fetchUsageData();
           _fetchSubscriptions(); 
        } else {
           _error = "Sync to backend failed";
        }
      }
    } catch (e) {
       _error = "Usage sync error: $e";
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F1E),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF0266))),
      );
    }

    if (_error.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        body: Center(child: Text(_error, style: const TextStyle(color: Colors.redAccent))),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          HomeDashboardScreen(
            userId: widget.userId,
            subscriptions: _subscriptions,
            onLogout: widget.onLogout,
            onRefresh: _fetchSubscriptions,
          ),
          CalendarScreen(subscriptions: _subscriptions),
          _buildSubscriptionList(),
          AiChatScreen(subscriptions: _subscriptions, backendUrl: backendUrl),
          const Scaffold(backgroundColor: Color(0xFF0F0F1E), body: Center(child: Text("Settings Coming Soon", style: TextStyle(color: Colors.white)))),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFFFF0266),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: "Calendar"),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: "Subs"),
            BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: "AI"),
            BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: "Settings"),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionList() {
    final filteredSubs = _subscriptions.where((sub) {
      final merchant = sub['Merchant'].toString().toLowerCase();
      final matchesSearch = merchant.contains(_searchQuery.toLowerCase());
      
      bool matchesFilter = true;
      if (_filterType == "Habit") {
        matchesFilter = sub['Type'] == "Habit";
      } else if (_filterType == "Ghost") {
        matchesFilter = (sub['Ghost Score'] ?? 0) > 70;
      } else if (_filterType == "Needs Review") {
        matchesFilter = sub['Notes'] != "Ongoing Subscription";
      }
      
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        title: const Text("Active Subscriptions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () => _showOptimizationDialog(context),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text("Optimize", style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7B61FF),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search merchants...",
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.3), size: 20),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: ["All", "Habit", "Ghost", "Needs Review"].map((filter) {
                final isSelected = _filterType == filter;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) setState(() => _filterType = filter);
                    },
                    selectedColor: const Color(0xFFFF0266),
                    backgroundColor: Colors.white.withOpacity(0.05),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white60,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    showCheckmark: false,
                    side: BorderSide(color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.1)),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: filteredSubs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.white.withOpacity(0.1)),
                        const SizedBox(height: 16),
                        const Text("No subscriptions found", style: TextStyle(color: Colors.white38)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredSubs.length,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    itemBuilder: (context, index) {
                      final sub = filteredSubs[index];
                      final bool needsReview = sub['Notes'] != "Ongoing Subscription";
                      final bool isHabit = sub['Type'] == "Habit";
                      final List<dynamic> insights = sub['Insights'] ?? [];
                      final bool hasInsights = insights.isNotEmpty;
                      final double ghostScore = (sub['Ghost Score'] ?? 0.0).toDouble();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isHabit ? Colors.blueAccent.withOpacity(0.05) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasInsights ? Colors.redAccent.withOpacity(0.4) : (isHabit ? Colors.blueAccent.withOpacity(0.2) : (needsReview ? Colors.orange.withOpacity(0.2) : Colors.white.withOpacity(0.1))),
                            width: 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            showDialog(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    backgroundColor: const Color(0xFF16213E),
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(child: Text(sub['Merchant'], style: const TextStyle(color: Colors.white))),
                                        TextButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _cancelSubscription(sub['Merchant']);
                                          },
                                          icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
                                          label: const Text("CANCEL", style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                        )
                                      ],
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Category: ${sub['Category']}", style: const TextStyle(color: Colors.white70)),
                                        const SizedBox(height: 8),
                                        Text("Monthly Cost: ₹${sub['Monthly Cost']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 8),
                                        Text("Next Billing Date: ${sub['Next Billing Date']}", style: const TextStyle(color: Colors.orange)),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            const Text("Ghost Score: ", style: TextStyle(color: Colors.white70)),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: ghostScore > 70 ? Colors.redAccent : (ghostScore > 30 ? Colors.orange : Colors.green),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text("${ghostScore.toInt()}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text("First Seen: ${sub['First Date']}", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                        if (hasInsights) ...[
                                          const SizedBox(height: 16),
                                          const Text("AI Insights:", style: TextStyle(color: Color(0xFFFF0266), fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 4),
                                          ...insights.map((a) => Padding(
                                              padding: const EdgeInsets.only(bottom: 4),
                                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 16),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text(a.toString(), style: const TextStyle(color: Colors.white))),
                                              ]))).toList(),
                                        ]
                                      ],
                                    ),
                                    actions: [
                                      if (!(sub['is_paused'] ?? false))
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _showPauseOptions(context, sub['Merchant']);
                                          },
                                          child: const Text("PAUSE", style: TextStyle(color: Colors.orangeAccent)),
                                        ),
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text("CLOSE", style: TextStyle(color: Color(0xFFFF0266))),
                                      )
                                    ],
                                  );
                                });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: isHabit ? Colors.blueAccent.withOpacity(0.1) : const Color(0xFFFF0266).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: isHabit
                                        ? const Icon(Icons.coffee, color: Colors.blueAccent, size: 20)
                                        : Text(
                                            sub['Merchant'][0].toUpperCase(),
                                            style: const TextStyle(color: Color(0xFFFF0266), fontSize: 20, fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              sub['Merchant'],
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Colors.white,
                                                decoration: (sub['is_paused'] ?? false) ? TextDecoration.lineThrough : null,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (sub['recommendation'] != null) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: sub['recommendation'] == 'KEEP' ? Colors.green.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: sub['recommendation'] == 'KEEP' ? Colors.greenAccent : Colors.redAccent, width: 0.5),
                                              ),
                                              child: Text(
                                                sub['recommendation'],
                                                style: TextStyle(
                                                    color: sub['recommendation'] == 'KEEP' ? Colors.greenAccent : Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "${sub['Category']} • ${sub['Interval (days)']}d",
                                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.timer_outlined, size: 10, color: Colors.white.withOpacity(0.4)),
                                          const SizedBox(width: 4),
                                          Text(
                                            "${_appUsage[_getPackageForMerchant(sub['Merchant'])] ?? 0} mins",
                                            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "₹${sub['Monthly Cost']}",
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: hasInsights ? Colors.redAccent : const Color(0xFF00E676)),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (isHabit)
                                          Container(
                                            margin: const EdgeInsets.only(right: 4),
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                            child: const Text("HABIT", style: TextStyle(fontSize: 8, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                          ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: ghostScore > 70 ? Colors.redAccent.withOpacity(0.2) : (ghostScore > 30 ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2)),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            "${ghostScore.toInt()}%",
                                            style: TextStyle(
                                                fontSize: 9,
                                                color: ghostScore > 70 ? Colors.redAccent : (ghostScore > 30 ? Colors.orange : Colors.greenAccent),
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _getPackageForMerchant(String merchant) {
    final m = merchant.toLowerCase();
    if (m.contains("netflix")) return "com.netflix.mediaclient";
    if (m.contains("spotify")) return "com.spotify.music";
    if (m.contains("youtube")) return "com.google.android.youtube";
    if (m.contains("amazon")) return "com.amazon.mShop.android.shopping";
    if (m.contains("disney")) return "com.disney.disneyplus";
    return m;
  }

  void _showPauseOptions(BuildContext context, String merchantName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text("Pause Subscription", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text("1 Month", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pauseSubscription(merchantName, months: 1);
              },
            ),
            ListTile(
              title: const Text("3 Months", style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pauseSubscription(merchantName, months: 3);
              },
            ),
            ListTile(
              title: const Text("Custom Date", style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 30)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (date != null) {
                  _pauseSubscription(merchantName, untilDate: date.toIso8601String());
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showOptimizationDialog(BuildContext context) {
    // Calculate total savings from insights
    double totalPotentialSavings = 0;
    Set<String> merchantsWithYearly = {};
    Set<String> bundleOpps = {};

    for (var sub in _subscriptions) {
      if (sub['Insights'] != null) {
        for (var insight in sub['Insights']) {
          String insightStr = insight.toString();
          if (insightStr.contains('Billing Opp:')) {
            merchantsWithYearly.add(sub['Merchant']?.toString() ?? '');
            final match = RegExp(r'₹(\d+)').firstMatch(insightStr);
            if (match != null) totalPotentialSavings += double.tryParse(match.group(1) ?? '0') ?? 0;
          }
          if (insightStr.contains('Bundle Opp:')) {
            bundleOpps.add(insightStr);
          }
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          String aiReport = "";
          bool isLoadingAI = false;

          Future<void> fetchAIReport() async {
            setDialogState(() => isLoadingAI = true);
            try {
              final prompt = """Analyze the user's subscriptions and provide a concise, actionable Cost Optimization Report.

Key data:
- ${merchantsWithYearly.isNotEmpty ? 'Yearly billing would save: ₹${totalPotentialSavings.toStringAsFixed(0)}/year across ${merchantsWithYearly.length} subscriptions (${merchantsWithYearly.join(", ")})' : 'No yearly billing opportunities detected.'}
- ${bundleOpps.isNotEmpty ? 'Bundle opportunities: ${bundleOpps.join('; ')}' : 'No bundle opportunities detected.'}

Give top 3 personalized recommendations, prioritized by savings. Be specific with subscription names and savings numbers. Use clear, concise bullet points.""";

              final response = await http.post(
                Uri.parse("$backendUrl/api/ai/chat"),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"message": prompt, "subscriptions": _subscriptions}),
              );
              if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                setDialogState(() { aiReport = data['reply']; isLoadingAI = false; });
              } else {
                setDialogState(() { aiReport = "AI optimization report unavailable right now."; isLoadingAI = false; });
              }
            } catch (e) {
              setDialogState(() { aiReport = "Could not connect to AI."; isLoadingAI = false; });
            }
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF16213E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.monetization_on, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text("Cost Optimization", style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Savings summary
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.savings_outlined, color: Colors.greenAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Potential Yearly Savings", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
                                Text("₹${totalPotentialSavings.toStringAsFixed(0)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 22)),
                              ],
                            ),
                          ),
                          Text("${merchantsWithYearly.length} subscriptions", style: const TextStyle(color: Colors.white54, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Bundle Opportunities
                    if (bundleOpps.isNotEmpty) ...[
                      const Text("Bundle Opportunities", style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 6),
                      ...bundleOpps.map((opp) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.link, color: Color(0xFF7B61FF), size: 15),
                            const SizedBox(width: 8),
                            Expanded(child: Text(opp.replaceAll("Bundle Opp:", "").trim(), style: const TextStyle(color: Colors.white70, fontSize: 13))),
                          ],
                        ),
                      )),
                      const SizedBox(height: 16),
                    ],

                    // AI Report section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("🤖 Slayer AI Report", style: TextStyle(color: Color(0xFFFF0266), fontWeight: FontWeight.bold, fontSize: 13)),
                        if (aiReport.isEmpty && !isLoadingAI)
                          TextButton.icon(
                            onPressed: fetchAIReport,
                            icon: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF7B61FF)),
                            label: const Text("Generate", style: TextStyle(color: Color(0xFF7B61FF), fontSize: 12)),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isLoadingAI)
                      const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Color(0xFF7B61FF))))
                    else if (aiReport.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(aiReport, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                      )
                    else
                      const Text("Tap 'Generate' for an AI-powered analysis.", style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close", style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Optimization applied! Review your subscriptions.", style: TextStyle(color: Colors.white)),
                    backgroundColor: Color(0xFF7B61FF),
                  ));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B61FF)),
                child: const Text("Switch & Save"),
              ),
            ],
          );
        });
      },
    );
  }
}
