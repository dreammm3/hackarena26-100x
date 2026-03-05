import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class CalendarScreen extends StatefulWidget {
  final List<dynamic> subscriptions;

  const CalendarScreen({super.key, required this.subscriptions});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    final String dayStr = _dateFormat.format(day);
    return widget.subscriptions.where((sub) {
      final nextBillingStr = sub['Next Billing Date']?.toString() ?? "";
      return nextBillingStr == dayStr;
    }).toList();
  }

  Widget _buildDayCell(DateTime date, bool isToday, {bool isSelected = false}) {
    final events = _getEventsForDay(date);
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF7B61FF) : (isToday ? const Color(0xFF7B61FF).withOpacity(0.1) : Colors.transparent),
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: const Color(0xFF7B61FF).withOpacity(0.5)) : null,
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          Text(
            '${date.day}',
            style: TextStyle(
              color: isSelected ? Colors.white : (isToday ? const Color(0xFF7B61FF) : Colors.white70),
              fontWeight: isToday || isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
          const Spacer(),
          if (events.isNotEmpty)
            Column(
              children: events.take(1).map((e) {
                final event = e as Map<String, dynamic>;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFF7B61FF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    event['Merchant']?.toString() ?? "",
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF7B61FF),
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Improved upcoming bills logic
    final List<Map<String, dynamic>> upcomingBills = [];
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    for (var sub in widget.subscriptions) {
      if (sub is Map<String, dynamic>) {
        final nextBillingStr = sub['Next Billing Date']?.toString() ?? "";
        try {
          final nextDate = _dateFormat.parse(nextBillingStr);
          if (nextDate.isAfter(todayMidnight.subtract(const Duration(minutes: 1)))) {
            upcomingBills.add(sub);
          }
        } catch (e) {
          // If date parsing fails, we could optionally still show it or log it
        }
      }
    }

    // Sort upcoming bills by date
    upcomingBills.sort((a, b) {
      try {
        final dateA = _dateFormat.parse(a['Next Billing Date'].toString());
        final dateB = _dateFormat.parse(b['Next Billing Date'].toString());
        return dateA.compareTo(dateB);
      } catch (e) {
        return 0;
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        title: const Text("Calendar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Calendar Card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF16162A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                rowHeight: 90, // Adjusted for labels
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                eventLoader: _getEventsForDay,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  leftChevronIcon: Icon(Icons.chevron_left, color: Color(0xFF7B61FF)),
                  rightChevronIcon: Icon(Icons.chevron_right, color: Color(0xFF7B61FF)),
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, date, _) => _buildDayCell(date, false),
                  todayBuilder: (context, date, _) => _buildDayCell(date, true),
                  selectedBuilder: (context, date, _) => _buildDayCell(date, false, isSelected: true),
                  outsideBuilder: (context, date, _) => const SizedBox.shrink(),
                ),
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: false,
                  markersMaxCount: 0,
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Colors.white38, fontSize: 12),
                  weekendStyle: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ),
            
            // Selected Day Bills Section
            if (_selectedDay != null) ...[
              Builder(
                builder: (context) {
                  final dayBills = _getEventsForDay(_selectedDay!);
                  if (dayBills.isEmpty) return const SizedBox.shrink();
                  
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Text(
                          "Bills for ${DateFormat('MMM dd, yyyy').format(_selectedDay!)}",
                          style: const TextStyle(color: Color(0xFF7B61FF), fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: dayBills.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemBuilder: (context, index) {
                          final sub = dayBills[index] as Map<String, dynamic>;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [const Color(0xFF7B61FF).withOpacity(0.2), const Color(0xFF16162A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF7B61FF).withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7B61FF).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      (sub['Merchant']?.toString() ?? "?")[0].toUpperCase(),
                                      style: const TextStyle(color: Color(0xFF7B61FF), fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sub['Merchant']?.toString() ?? "Unknown",
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      Text(
                                        sub['Category']?.toString() ?? "Subscription",
                                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "₹${sub['Monthly Cost'] ?? '0'}",
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const Icon(Icons.check_circle_outline, color: Color(0xFF7B61FF), size: 14),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],

            // Upcoming Bills Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Upcoming Bills",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text("View All", style: TextStyle(color: Color(0xFF7B61FF))),
                  ),
                ],
              ),
            ),

            if (upcomingBills.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text("No upcoming bills found.", style: TextStyle(color: Colors.white38))),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: upcomingBills.take(10).length,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemBuilder: (context, index) {
                  final sub = upcomingBills[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16162A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.03)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: sub['Icon'] != null 
                                ? Image.network(sub['Icon'], width: 24, errorBuilder: (c, e, s) => Text((sub['Merchant']?.toString() ?? "?")[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                                : Text((sub['Merchant']?.toString() ?? "?")[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sub['Merchant']?.toString() ?? "Unknown",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                "Due ${sub['Next Billing Date']}",
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₹${sub['Monthly Cost'] ?? '0'}",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B61FF).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                sub['Type']?.toUpperCase() ?? "STANDARD",
                                style: const TextStyle(color: Color(0xFF7B61FF), fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
