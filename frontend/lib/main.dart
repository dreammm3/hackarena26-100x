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
import 'screens/profile_screen.dart';

const String syncUsageTask = "com.niyampe.syncUsage";

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

  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NiyamPe',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00DEC1),
          primary: const Color(0xFF00DEC1),
          secondary: const Color(0xFF00DEC1),
          brightness: Brightness.dark,
          surface: const Color(0xFF1A1A2E),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 32),
          bodyLarge: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00DEC1),
            foregroundColor: const Color(0xFF0F0F1E),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF00DEC1), width: 1.5),
          ),
          labelStyle: const TextStyle(color: Colors.white60),
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

enum OnboardingStep { login, bankConnection, budgetSetup, dashboard }

class _AuthWrapperState extends State<AuthWrapper> {
  OnboardingStep _currentStep = OnboardingStep.login;
  String? _userId;
  String? _userEmail;
  double _monthlyBudget = 0.0;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    // We are disabling auto-login to ensure the login page appears first as requested.
    // To re-enable auto-login, restore the SharedPreferences check below.
    /*
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (isLoggedIn) {
      final String? userId = prefs.getString('userId');
      final String? userEmail = prefs.getString('userEmail');
      final bool bankConnected = prefs.getBool('bankConnected') ?? false;
      final double budget = prefs.getDouble('monthlyBudget') ?? 0.0;

      setState(() {
        _userId = userId;
        _userEmail = userEmail;
        if (!bankConnected) {
          _currentStep = OnboardingStep.bankConnection;
        } else if (budget <= 0) {
          _currentStep = OnboardingStep.budgetSetup;
        } else {
          _monthlyBudget = budget;
          _currentStep = OnboardingStep.dashboard;
        }
      });
    }
    */
  }

  void _onLoginSuccess(String userId, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userId', userId);
    await prefs.setString('userEmail', email);
    setState(() {
      _userId = userId;
      _userEmail = email;
      _currentStep = OnboardingStep.bankConnection;
    });
  }

  void _onBankConnected() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bankConnected', true);
    setState(() {
      _currentStep = OnboardingStep.budgetSetup;
    });
  }

  void _onBudgetSet(double budget) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('monthlyBudget', budget);
    setState(() {
      _monthlyBudget = budget;
      _currentStep = OnboardingStep.dashboard;
    });
  }

  void _onLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    setState(() {
      _userId = null;
      _currentStep = OnboardingStep.login;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_currentStep) {
      case OnboardingStep.login:
        return LoginPage(onLoginSuccess: _onLoginSuccess);
      case OnboardingStep.bankConnection:
        return BankConnectionPage(onConnected: _onBankConnected);
      case OnboardingStep.budgetSetup:
        return BudgetSetupPage(onBudgetSet: _onBudgetSet);
      case OnboardingStep.dashboard:
        return FutureBuilder<bool>(
          future: ScreenTimeService().hasUsagePermission(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.data == false) {
              return UsagePermissionPage(onPermissionGranted: () => setState(() {}));
            }
            return DashboardPage(
              userId: _userId!,
              userEmail: _userEmail ?? 'user@example.com',
              onLogout: _onLogout,
              monthlyBudget: _monthlyBudget,
            );
          },
        );
    }
  }
}

class BankConnectionPage extends StatefulWidget {
  final VoidCallback onConnected;
  const BankConnectionPage({super.key, required this.onConnected});

  @override
  State<BankConnectionPage> createState() => _BankConnectionPageState();
}

class _BankConnectionPageState extends State<BankConnectionPage> {
  bool _isConnecting = false;

  final List<Map<String, dynamic>> _banks = [
    {'name': 'HDFC Bank', 'icon': Icons.account_balance, 'color': Colors.blue},
    {'name': 'ICICI Bank', 'icon': Icons.account_balance, 'color': Colors.orange},
    {'name': 'SBI', 'icon': Icons.account_balance, 'color': Colors.lightBlue},
    {'name': 'Axis Bank', 'icon': Icons.account_balance, 'color': Colors.purple},
    {'name': 'Kotak Bank', 'icon': Icons.account_balance, 'color': Colors.red},
    {'name': 'Paytm Bank', 'icon': Icons.account_balance, 'color': Colors.cyan},
    {'name': 'IDFC First', 'icon': Icons.account_balance, 'color': Colors.indigo},
    {'name': 'Yes Bank', 'icon': Icons.account_balance, 'color': Colors.blueAccent},
    {'name': 'IndusInd', 'icon': Icons.account_balance, 'color': Colors.redAccent},
  ];

  void _handleConnect() async {
    setState(() => _isConnecting = true);
    // Simulate real bank sync
    await Future.delayed(const Duration(seconds: 3));
    widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    if (_isConnecting) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(color: Color(0xFF00DEC1), strokeWidth: 3),
              ),
              const SizedBox(height: 32),
              const Text("Syncing with your Bank...", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text("Securely fetching your transaction history", style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.shield_outlined, color: Color(0xFF00DEC1), size: 40),
              const SizedBox(height: 24),
              const Text("Connect your bank", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text("Link your account to automatically identify and slay hidden subscriptions.", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)),
              const SizedBox(height: 32),
              TextField(
                decoration: InputDecoration(
                  hintText: "Search your bank...",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemCount: _banks.length,
                  itemBuilder: (context, index) {
                    final bank = _banks[index];
                    return InkWell(
                      onTap: _handleConnect,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(bank['icon'], color: bank['color'], size: 28),
                            const SizedBox(height: 8),
                            Text(bank['name'], style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock, color: Colors.greenAccent, size: 14),
                    SizedBox(width: 8),
                    Text("Secure 256-bit Connection", style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BudgetSetupPage extends StatefulWidget {
  final Function(double) onBudgetSet;
  const BudgetSetupPage({super.key, required this.onBudgetSet});

  @override
  State<BudgetSetupPage> createState() => _BudgetSetupPageState();
}

class _BudgetSetupPageState extends State<BudgetSetupPage> {
  final TextEditingController _budgetController = TextEditingController(text: "15000");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              const Text("Target budget", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text("Total monthly cap for all subscriptions.", style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)),
              const SizedBox(height: 48),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFF00DEC1).withOpacity(0.2), const Color(0xFF00DEC1).withOpacity(0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF00DEC1).withOpacity(0.3)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("LIMIT PER MONTH", style: TextStyle(color: Color(0xFF00DEC1), fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _budgetController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          prefixText: "₹",
                          prefixStyle: TextStyle(color: Colors.white30, fontSize: 24),
                          border: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text("We'll alert you if you exceed this mark.", style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () {
                    double? budget = double.tryParse(_budgetController.text);
                    if (budget != null && budget > 0) {
                      widget.onBudgetSet(budget);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00DEC1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("FINISH SETUP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0)),
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
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
            Text("Master Your Expenses", style: Theme.of(context).textTheme.headlineMedium),
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
  final Function(String, String) onLoginSuccess;
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
        widget.onLoginSuccess(data['user_id'], data['email']);
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
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00DEC1).withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        )
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo.jpg',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text("NiyamPe", style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: 8),
                  Text("Niyam ke saath, har kharcha vishwas.", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70)),
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
  final String userEmail;
  final VoidCallback onLogout;
  final double monthlyBudget;
  
  const DashboardPage({
    super.key, 
    required this.userId, 
    required this.userEmail,
    required this.onLogout,
    required this.monthlyBudget,
  });

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
            userEmail: widget.userEmail,
            subscriptions: _subscriptions,
            onLogout: widget.onLogout,
            onRefresh: _fetchSubscriptions,
            monthlyBudget: widget.monthlyBudget,
          ),
          CalendarScreen(subscriptions: _subscriptions),
          _buildSubscriptionList(),
          AiChatScreen(subscriptions: _subscriptions, backendUrl: backendUrl),
          ProfileScreen(onLogout: widget.onLogout, userEmail: widget.userEmail, subscriptions: _subscriptions),
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
          selectedItemColor: const Color(0xFF00DEC1),
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_month_rounded), label: "Calendar"),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: "Subs"),
            BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: "AI"),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "Profile"),
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
            child: Stack(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showOptimizationDialog(context),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text("Optimize & Save", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00DEC1),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: const Color(0xFF00DEC1), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0F0F1E), width: 2)),
                  ),
                )
              ],
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
                    selectedColor: const Color(0xFF00DEC1),
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
                                    color: isHabit ? Colors.blueAccent.withOpacity(0.1) : const Color(0xFF00DEC1).withOpacity(0.1),
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
                                      const SizedBox(height: 6),
                                      // Indian Market Bundle Badge
                                      if (hasInsights && insights.any((i) => i.toString().contains("Bundle Opp:")))
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(colors: [const Color(0xFF00DEC1).withOpacity(0.2), const Color(0xFF00DEC1).withOpacity(0.05)]),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFF00DEC1).withOpacity(0.5), width: 1),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.auto_awesome, color: Color(0xFF00DEC1), size: 12),
                                              SizedBox(width: 6),
                                              Text("BUNDLE SAVINGS AVAILABLE",
                                                  style: TextStyle(color: Color(0xFF00DEC1), fontWeight: FontWeight.bold, fontSize: 9, letterSpacing: 1.0)),
                                            ],
                                          ),
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
            // Look specifically for savings amount at the end
            final match = RegExp(r'Save ₹(\d+)').firstMatch(insightStr);
            if (match != null) {
              totalPotentialSavings += double.tryParse(match.group(1) ?? '0') ?? 0;
            }
          }
          if (insightStr.contains('Bundle Opp:')) {
            bundleOpps.add(insightStr);
            final match = RegExp(r'Save ₹(\d+)').firstMatch(insightStr);
            if (match != null) {
              totalPotentialSavings += (double.tryParse(match.group(1) ?? '0') ?? 0) * 12; // Annualized
            }
          }
        }
      }
    }

    String aiReport = "";
    bool isLoadingAI = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          Future<void> fetchAIReport() async {
            setDialogState(() => isLoadingAI = true);
            try {
              final prompt = """Analyze the user's subscriptions and provide a concise, actionable Cost Optimization Report focused on the Indian market.
Check if individual services can be replaced by cheaper Indian-specific bundled plans (like Apple One India, Amazon Prime, Disney+ Hotstar bundles, Spotify Duo/Family, or OTT aggregators like OTTplay/Tata Play Binge).

Key data:
- ${merchantsWithYearly.isNotEmpty ? 'Yearly billing would save: ₹${totalPotentialSavings.toStringAsFixed(0)}/year across ${merchantsWithYearly.length} subscriptions (${merchantsWithYearly.join(", ")})' : 'No yearly billing opportunities detected.'}
- ${bundleOpps.isNotEmpty ? 'Detected Bundle opportunities: ${bundleOpps.join('; ')}' : 'No bundle opportunities detected yet.'}

Give the top 3 personalized recommendations for Indian users, prioritized by savings. Be specific with subscription names and exact Rs. savings. Use clear, concise bullet points.""";

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
                Text("Indian Cost Optimization", style: TextStyle(color: Colors.white, fontSize: 18)),
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
                            const Icon(Icons.link, color: Color(0xFF00DEC1), size: 15),
                            const SizedBox(width: 8),
                            Expanded(child: Text(opp.replaceAll("Bundle Opp:", "").trim(), style: const TextStyle(color: Colors.white70, fontSize: 13))),
                          ],
                        ),
                      )),
                      const SizedBox(height: 16),
                    ],

                    // AI Report section
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.auto_awesome, color: Color(0xFFFF0266), size: 18),
                                  SizedBox(width: 8),
                                  Text("NIYAMPE AI REPORT",
                                      style: TextStyle(color: Color(0xFFFF0266), fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                                ],
                              ),
                              if (aiReport.isEmpty && !isLoadingAI)
                                ElevatedButton(
                                  onPressed: fetchAIReport,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00DEC1),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  child: const Text("GENERATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (isLoadingAI)
                            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF00DEC1))))
                          else if (aiReport.isNotEmpty)
                            Text(
                              aiReport,
                              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                            )
                          else
                            const Text(
                              "Tap generate for a deep-dive analysis of your spending and potential Indian market bundle savings.",
                              style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    ),
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
                    backgroundColor: Color(0xFF00DEC1),
                  ));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00DEC1)),
                child: const Text("Switch & Save"),
              ),
            ],
          );
        });
      },
    );
  }
}
