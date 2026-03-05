import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/usage_service.dart';
import 'usage_dashboard_screen.dart';
import 'ghost_address_screen.dart';

class HomeDashboardScreen extends StatelessWidget {
  final String userId;
  final List<dynamic> subscriptions;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;

  const HomeDashboardScreen({
    super.key,
    required this.userId,
    required this.subscriptions,
    required this.onLogout,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    double totalMonthly = subscriptions.fold(0.0, (sum, sub) => sum + (sub['Monthly Cost'] ?? 0.0));
    double potentialSavings = subscriptions
        .where((sub) => (sub['Ghost Score'] ?? 0) > 70 || sub['recommendation'] == 'REDUNDANT')
        .fold(0.0, (sum, sub) => sum + (sub['Monthly Cost'] ?? 0.0));

    final upcoming = subscriptions.where((sub) => sub['Next Billing Date'] != null).toList()
      ..sort((a, b) => (a['Next Billing Date'] ?? '').compareTo(b['Next Billing Date'] ?? ''));

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildFinancialGrid(totalMonthly, potentialSavings),
                  const SizedBox(height: 32),
                  _buildSectionTitle("Priority Alerts"),
                  const SizedBox(height: 12),
                  _buildRecommendations(subscriptions),
                  const SizedBox(height: 32),
                  _buildSectionTitle("Upcoming Payments"),
                  const SizedBox(height: 12),
                  _buildUpcomingPayments(upcoming),
                  const SizedBox(height: 32),
                  _buildQuickActions(context),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      floating: true,
      leading: Container(
        margin: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
          onPressed: onLogout,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white70),
          onPressed: onRefresh,
        ),
        const SizedBox(width: 8),
        Container(
          margin: const EdgeInsets.only(right: 16),
          child: const CircleAvatar(
            backgroundColor: Color(0xFFFF0266),
            child: Icon(Icons.person, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Hey User,",
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Ready to slay some bills?",
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialGrid(double totalMonthly, double potentialSavings) {
    return Column(
      children: [
        _buildSummaryCard(
          "Monthly Budget",
          "₹15,000",
          "Remaining: ₹${(15000 - totalMonthly).toStringAsFixed(0)}",
          const [Color(0xFF6200EE), Color(0xFFBB86FC)],
          Icons.account_balance_wallet,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSmallStatsCard(
                "Subscriptions",
                "₹${totalMonthly.toStringAsFixed(0)}",
                Icons.receipt_long,
                Colors.orangeAccent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSmallStatsCard(
                "AI Savings",
                "₹${potentialSavings.toStringAsFixed(0)}",
                Icons.auto_awesome,
                Colors.greenAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, String sub, List<Color> colors, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(icon, size: 80, color: Colors.white.withOpacity(0.1)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(sub, style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStatsCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        TextButton(
          onPressed: () {},
          child: const Text("View All", style: TextStyle(color: Color(0xFFFF0266), fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildRecommendations(List<dynamic> subs) {
    // ---- Classify every subscription into distinct alert buckets ----
    List<Map<String, dynamic>> alertData = [];

    // 1. URGENT: Ghost (unused) subscriptions — pick the worst 1
    final ghosts = subs.where((s) => (s['Ghost Score'] ?? 0) > 70).toList()
      ..sort((a, b) => ((b['Ghost Score'] ?? 0) - (a['Ghost Score'] ?? 0)).toInt());
    if (ghosts.isNotEmpty) {
      final g = ghosts.first;
      alertData.add({
        'priority': 0,
        'color': const Color(0xFFFF0266),
        'icon': Icons.money_off_rounded,
        'title': '🔴 Zombie Sub: ${g['Merchant']}',
        'body': 'Ghost Score ${((g['Ghost Score'] ?? 0).toDouble()).toStringAsFixed(0)}% — You haven\'t used this in a while. Cancel to save ₹${(g['Monthly Cost'] ?? 0).toStringAsFixed(0)}/mo.',
      });
    }

    // 2. PRICE HIKE — one per merchant
    for (var sub in subs) {
      final insights = (sub['Insights'] ?? []) as List;
      for (var i in insights) {
        if (i.toString().contains('Financial Anomaly')) {
          final match = RegExp(r'(\d+\.\d+)%').firstMatch(i.toString());
          final pct = match?.group(1) ?? '?';
          alertData.add({
            'priority': 1,
            'color': Colors.orangeAccent,
            'icon': Icons.trending_up_rounded,
            'title': '⚠️ Price Hike: ${sub['Merchant']}',
            'body': 'Your bill for ${sub['Merchant']} has increased by $pct%. Consider switching to a cheaper alternative or yearly billing.',
          });
          break;
        }
      }
    }

    // 3. DUPLICATE SUBSCRIPTIONS — group by category, show 1 consolidated alert
    final Map<String, List<String>> dupsByCategory = {};
    for (var sub in subs) {
      final insights = (sub['Insights'] ?? []) as List;
      for (var i in insights) {
        if (i.toString().contains('Redundancy Detected')) {
          final cat = sub['Category'] ?? 'Entertainment';
          dupsByCategory.putIfAbsent(cat, () => []);
          if (!dupsByCategory[cat]!.contains(sub['Merchant'])) {
            dupsByCategory[cat]!.add(sub['Merchant']);
          }
        }
      }
    }
    dupsByCategory.forEach((cat, merchants) {
      alertData.add({
        'priority': 2,
        'color': Colors.redAccent,
        'icon': Icons.content_copy_rounded,
        'title': '🔁 Overlap in $cat',
        'body': 'You\'re paying for ${merchants.join(' + ')} separately. Pick one or bundle them to cut costs.',
      });
    });

    // 4. BUNDLE OPPORTUNITIES — show distinct bundle messages (not per-sub)
    final Set<String> shownBundles = {};
    for (var sub in subs) {
      final insights = (sub['Insights'] ?? []) as List;
      for (var i in insights) {
        if (i.toString().contains('Bundle Opp:')) {
          final clean = i.toString().replaceAll('Bundle Opp:', '').trim();
          if (!shownBundles.contains(clean)) {
            shownBundles.add(clean);
            alertData.add({
              'priority': 3,
              'color': Colors.greenAccent,
              'icon': Icons.account_balance_wallet_rounded,
              'title': '💚 Bundle Opportunity',
              'body': clean,
            });
          }
        }
      }
    }

    // 5. TOP SPENDER insight — pick the most expensive subscription
    if (subs.isNotEmpty) {
      final topSub = subs.reduce((a, b) => (a['Monthly Cost'] ?? 0) > (b['Monthly Cost'] ?? 0) ? a : b);
      alertData.add({
        'priority': 4,
        'color': const Color(0xFF7B61FF),
        'icon': Icons.bar_chart_rounded,
        'title': '💸 Top Spend: ${topSub['Merchant']}',
        'body': '₹${(topSub['Monthly Cost'] ?? 0).toStringAsFixed(0)}/mo — your biggest subscription. Verify it\'s worth the cost!',
      });
    }

    // 6. YEARLY BILLING — pick 1 merchant with the highest potential savings
    Map<String, dynamic>? bestYearly;
    double bestSaving = 0;
    for (var sub in subs) {
      final insights = (sub['Insights'] ?? []) as List;
      for (var i in insights) {
        if (i.toString().contains('Billing Opp:')) {
          final match = RegExp(r'₹(\d+)').firstMatch(i.toString());
          final saving = double.tryParse(match?.group(1) ?? '0') ?? 0;
          if (saving > bestSaving) {
            bestSaving = saving;
            bestYearly = sub;
          }
        }
      }
    }
    if (bestYearly != null) {
      alertData.add({
        'priority': 5,
        'color': Colors.lightBlueAccent,
        'icon': Icons.calendar_today_rounded,
        'title': '📅 Switch to Yearly: ${bestYearly!['Merchant']}',
        'body': 'Switching ${bestYearly!['Merchant']} to annual billing could save you ₹${bestSaving.toStringAsFixed(0)}/year — that\'s 2 months free!',
      });
    }

    // Sort by priority, then limit to 5 unique alerts
    alertData.sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));
    final finalAlerts = alertData.take(5).toList();

    if (finalAlerts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 24),
            SizedBox(width: 16),
            Expanded(child: Text("All good! No urgent alerts detected right now. Keep it up!", style: TextStyle(color: Colors.white70, fontSize: 13))),
          ],
        ),
      );
    }

    return Column(
      children: finalAlerts.map((alert) {
        final Color col = alert['color'] as Color;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: col.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: col.withOpacity(0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: col.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(alert['icon'] as IconData, color: col, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert['title'] as String, style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(alert['body'] as String, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }


  Widget _buildUpcomingPayments(List<dynamic> upcoming) {
    if (upcoming.isEmpty) return const Text("No upcoming payments", style: TextStyle(color: Colors.white38));
    return Column(
      children: upcoming.take(3).map((sub) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.calendar_month, color: Color(0xFFBB86FC), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sub['Merchant'], 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    sub['Next Billing Date'] ?? 'Soon', 
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "₹${sub['Monthly Cost'].toStringAsFixed(0)}", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _quickActionBtn(Icons.timer_outlined, "Usage", () => Navigator.push(context, MaterialPageRoute(builder: (context) => ScreenTimeDashboard(subscriptions: subscriptions)))),
        _quickActionBtn(Icons.vpn_key_outlined, "Ghost ID", () => Navigator.push(context, MaterialPageRoute(builder: (context) => GhostAddressScreen(userId: userId)))),
        _quickActionBtn(Icons.analytics_outlined, "Audit", onRefresh),
      ],
    );
  }

  Widget _quickActionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Icon(icon, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
