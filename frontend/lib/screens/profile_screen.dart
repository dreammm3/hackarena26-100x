import 'package:flutter/material.dart';
import '../main.dart'; // To access MyApp.themeNotifier
import 'analysis_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final String userEmail;
  final List<dynamic> subscriptions;

  const ProfileScreen({super.key, required this.onLogout, required this.userEmail, required this.subscriptions});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool pushNotificationsEnabled = true;
  bool emailAlertsEnabled = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: MyApp.themeNotifier,
      builder: (context, themeMode, _) {
        final isDarkMode = themeMode == ThemeMode.dark;
        final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
        final containerBg = isDarkMode ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03);

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: Text("Profile", style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: IconThemeData(color: textColor),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Avatar and basic info
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF00DEC1), width: 3),
                        ),
                        child: const CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey,
                          child: Icon(Icons.person, size: 55, color: Colors.white),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF00DEC1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.edit, color: Colors.white, size: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    widget.userEmail.split('@')[0].toUpperCase(),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                  ),
                ),
                Center(
                  child: Text(
                    widget.userEmail,
                    style: TextStyle(fontSize: 14, color: const Color(0xFF00DEC1).withOpacity(0.8)),
                  ),
                ),
                const SizedBox(height: 36),

                // ACCOUNT SETTINGS Section
                _buildSectionTitle("ACCOUNT SETTINGS", textColor),
                Container(
                  decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildListTile(
                        Icons.analytics_outlined,
                        "Analysis",
                        textColor,
                        trailing: _buildChevron(textColor),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AnalysisScreen(subscriptions: widget.subscriptions),
                          ),
                        ),
                      ),
                      _buildDivider(isDarkMode),
                      _buildListTile(Icons.person_outline, "Personal Information", textColor, trailing: _buildChevron(textColor)),
                      _buildDivider(isDarkMode),
                      _buildListTile(Icons.account_balance_outlined, "Linked Bank Accounts", textColor, trailing: _buildChevron(textColor)),
                      _buildDivider(isDarkMode),
                      _buildListTile(Icons.lock_outline, "Security & Password", textColor, trailing: _buildChevron(textColor)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // PREFERENCES Section
                _buildSectionTitle("PREFERENCES", textColor),
                Container(
                  decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildListTile(
                        Icons.notifications_none,
                        "Push Notifications",
                        textColor,
                        trailing: Switch(
                          value: pushNotificationsEnabled,
                          activeColor: const Color(0xFF00DEC1),
                          onChanged: (val) => setState(() => pushNotificationsEnabled = val),
                        ),
                      ),
                      _buildDivider(isDarkMode),
                      _buildListTile(
                        Icons.email_outlined,
                        "Email Alerts",
                        textColor,
                        trailing: Switch(
                          value: emailAlertsEnabled,
                          activeColor: const Color(0xFF00DEC1),
                          onChanged: (val) => setState(() => emailAlertsEnabled = val),
                        ),
                      ),
                      _buildDivider(isDarkMode),
                      _buildListTile(
                        isDarkMode ? Icons.dark_mode : Icons.light_mode,
                        "Dark Mode",
                        textColor,
                        trailing: Switch(
                          value: isDarkMode,
                          activeColor: const Color(0xFF00DEC1),
                          onChanged: (val) {
                            MyApp.themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                          },
                        ),
                      ),
                      _buildDivider(isDarkMode),
                      _buildListTile(
                        Icons.payments_outlined,
                        "Currency",
                        textColor,
                        trailing: Text(
                          "INR (₹)",
                          style: TextStyle(color: const Color(0xFF00DEC1), fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // INFORMATION Section
                _buildSectionTitle("INFORMATION", textColor),
                Container(
                  decoration: BoxDecoration(color: containerBg, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      _buildListTile(Icons.help_outline, "Help & Support", textColor),
                      _buildDivider(isDarkMode),
                      _buildListTile(Icons.description_outlined, "Terms of Service", textColor),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Logout Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout, color: Colors.white),
                    label: const Text("Log Out", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00DEC1),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    "Version 1.0.0 (Build 001)",
                    style: TextStyle(color: textColor.withOpacity(0.4), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          color: const Color(0xFF00DEC1).withOpacity(0.9),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildListTile(IconData icon, String title, Color textColor, {Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: const Color(0xFF00DEC1), size: 24),
      title: Text(
        title,
        style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w500),
      ),
      trailing: trailing,
      onTap: onTap ?? () {},
    );
  }

  Widget _buildChevron(Color textColor) {
    return Icon(Icons.chevron_right, color: textColor.withOpacity(0.4), size: 24);
  }

  Widget _buildDivider(bool isDarkMode) {
    return Divider(height: 1, thickness: 1, color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), indent: 56, endIndent: 16);
  }
}
