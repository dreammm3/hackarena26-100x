import 'dart:math' as math;
import 'dart:ui' as ui;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AnalysisScreen extends StatefulWidget {
  final List<dynamic> subscriptions;
  const AnalysisScreen({super.key, required this.subscriptions});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey _shareKey = GlobalKey();
  bool _isSharing = false;
  late TabController _tabController;

  // ── color palette ──
  static const List<Color> _palette = [
    Color(0xFF00DEC1), Color(0xFF7B61FF), Color(0xFFFFD166),
    Color(0xFFEF476F), Color(0xFF06D6A0), Color(0xFF118AB2),
    Color(0xFFFFB347), Color(0xFFB5EAD7), Color(0xFFFF6B6B),
    Color(0xFFA8DADC), Color(0xFFE9C46A), Color(0xFF264653),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Data helpers ──
  Map<String, double> _getCategorySpend() {
    final Map<String, double> cats = {};
    for (final sub in widget.subscriptions) {
      final cat = (sub['Type'] ?? sub['Category'] ?? 'Other').toString();
      cats[cat] = (cats[cat] ?? 0.0) + (sub['Monthly Cost'] ?? 0.0).toDouble();
    }
    return cats;
  }

  Map<String, double> _getSubSpend() {
    final Map<String, double> subs = {};
    for (final sub in widget.subscriptions) {
      final name = (sub['Merchant'] ?? 'Unknown').toString();
      subs[name] = (subs[name] ?? 0.0) + (sub['Monthly Cost'] ?? 0.0).toDouble();
    }
    return subs;
  }

  double get _totalSpend =>
      widget.subscriptions.fold(0.0, (s, sub) => s + (sub['Monthly Cost'] ?? 0.0));

  double get _totalSavings => widget.subscriptions
      .where((s) => (s['Ghost Score'] ?? 0) > 70 || s['recommendation'] == 'REDUNDANT')
      .fold(0.0, (s, sub) => s + (sub['Monthly Cost'] ?? 0.0));

  // ── Share as image (web) ──
  Future<void> _shareAsImage() async {
    setState(() => _isSharing = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _shareKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Could not capture widget');

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode image');

      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final blob = html.Blob([pngBytes], 'image/png');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..download = 'NiyamPe_Analysis.png'
        ..style.display = 'none';
      html.document.body!.children.add(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Image downloaded! Share it anywhere.'),
          ]),
          backgroundColor: const Color(0xFF00DEC1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Share failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryData = _getCategorySpend().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final subData = _getSubSpend().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = _totalSpend;
    final savings = _totalSavings;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1E),
        elevation: 0,
        title: const Text('Analysis',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSharing
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(color: Color(0xFF00DEC1), strokeWidth: 2))
                : TextButton.icon(
                    onPressed: _shareAsImage,
                    icon: const Icon(Icons.download_rounded, color: Color(0xFF00DEC1), size: 20),
                    label: const Text('Save Image',
                        style: TextStyle(color: Color(0xFF00DEC1), fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _shareKey,
        child: Container(
          color: const Color(0xFF0F0F1E),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── NiyamPe header for the exported image ──
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Color(0xFF00DEC1), size: 20),
                    const SizedBox(width: 6),
                    const Text('NiyamPe',
                        style: TextStyle(
                            color: Color(0xFF00DEC1), fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    Text(
                      '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Summary Cards ──
                Row(
                  children: [
                    Expanded(child: _SummaryCard(
                      label: 'Monthly Spend',
                      value: '₹${total.toStringAsFixed(0)}',
                      subLabel: '₹${(total * 12).toStringAsFixed(0)}/year',
                      color: const Color(0xFF00DEC1),
                      icon: Icons.account_balance_wallet_rounded,
                    )),
                    const SizedBox(width: 14),
                    Expanded(child: _SummaryCard(
                      label: 'Savings Found',
                      value: '₹${savings.toStringAsFixed(0)}',
                      subLabel: '₹${(savings * 12).toStringAsFixed(0)}/year',
                      color: const Color(0xFFFFD166),
                      icon: Icons.savings_rounded,
                    )),
                  ],
                ),

                const SizedBox(height: 28),

                // ── Tabs: Category / By Subscription ──
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF0F0F1E),
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    indicator: BoxDecoration(
                      color: const Color(0xFF00DEC1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tabs: const [
                      Tab(text: 'By Category'),
                      Tab(text: 'By Subscription'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Tab content ──
                SizedBox(
                  height: 600,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1 – Category
                      _buildChartSection(
                        data: categoryData,
                        total: total,
                        label: 'Spend by Category',
                        subtitle: 'How your budget is spread across types',
                      ),
                      // Tab 2 – Per subscription
                      _buildChartSection(
                        data: subData.take(10).toList(),
                        total: total,
                        label: 'Spend by Subscription',
                        subtitle: 'Top 10 services by monthly cost',
                      ),
                    ],
                  ),
                ),

                // ── Share CTA card ──
                GestureDetector(
                  onTap: _isSharing ? null : _shareAsImage,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        const Color(0xFF00DEC1).withOpacity(0.15),
                        const Color(0xFF00DEC1).withOpacity(0.04),
                      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00DEC1).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.download_rounded, color: Color(0xFF00DEC1), size: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Save & Share Analysis',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text('Downloads a PNG snapshot of this page\nShare it on WhatsApp, Instagram, Email & more',
                                  style: TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: Color(0xFF00DEC1), size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChartSection({
    required List<MapEntry<String, double>> data,
    required double total,
    required String label,
    required String subtitle,
  }) {
    if (data.isEmpty) {
      return Center(
        child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 16)),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13)),
          const SizedBox(height: 20),

          // Donut pie chart
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: CustomPaint(
                    painter: _PieChartPainter(
                      data: data.map((e) => e.value).toList(),
                      colors: List.generate(data.length, (i) => _palette[i % _palette.length]),
                      total: total,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Total', style: TextStyle(color: Colors.white54, fontSize: 11)),
                          Text('₹${total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text('/mo', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Legend
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(
                      data.length > 7 ? 7 : data.length,
                      (i) {
                        final entry = data[i];
                        final pct = total > 0
                            ? (entry.value / total * 100).toStringAsFixed(1)
                            : '0';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 9, height: 9,
                                decoration: BoxDecoration(
                                    color: _palette[i % _palette.length],
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(entry.key,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Text('$pct%',
                                  style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Progress bar breakdown
          ...List.generate(data.length, (i) {
            final entry = data[i];
            final pct = total > 0 ? entry.value / total : 0.0;
            final color = _palette[i % _palette.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(entry.key,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('₹${entry.value.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 7,
                      backgroundColor: Colors.white.withOpacity(0.05),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Custom Donut Pie Chart Painter ──
class _PieChartPainter extends CustomPainter {
  final List<double> data;
  final List<Color> colors;
  final double total;

  _PieChartPainter({required this.data, required this.colors, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2 - 6;
    const donutFactor = 0.54;
    final strokeW = outerRadius * (1 - donutFactor);
    final arcRadius = outerRadius - strokeW / 2;

    double startAngle = -math.pi / 2;
    const gap = 0.03; // gap between slices in radians

    for (int i = 0; i < data.length; i++) {
      final sweep = total > 0 ? (data[i] / total) * 2 * math.pi : 0.0;
      if (sweep < 0.01) { startAngle += sweep; continue; }

      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: arcRadius),
        startAngle + gap / 2,
        sweep - gap,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter old) =>
      old.data != data || old.total != total;
}

// ── Summary Card ──
class _SummaryCard extends StatelessWidget {
  final String label, value, subLabel;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label, required this.value, required this.subLabel,
    required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(value,
              style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          Text(subLabel,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
