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

  final Color _bgColor = const Color(0xFF0F0F1E); 
  final Color _cardColor = const Color(0xFF1A1A2E); 
  final Color _accentTeal = const Color(0xFF00DEC1); 
  final Color _textColor = Colors.white;
  final Color _subTextColor = Colors.white54;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    return widget.subscriptions.where((sub) {
      final nextBillingStr = sub['Next Billing Date']?.toString() ?? "";
      try {
        final date = _dateFormat.parse(nextBillingStr);
        // Treat subscriptions as recurring monthly for the calendar view
        return date.day == day.day;
      } catch (e) {
        return false;
      }
    }).toList();
  }

  void _showEventPopup(BuildContext context, List<dynamic> events) {
    if (events.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long_rounded, color: _accentTeal),
                    const SizedBox(width: 8),
                    Text(
                      "Bill Details",
                      style: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close, color: _subTextColor),
                      onPressed: () => Navigator.pop(context),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                ...events.map((e) {
                  final sub = e as Map<String, dynamic>;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sub['Merchant']?.toString() ?? "Unknown",
                          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Category: ${sub['Category']?.toString() ?? 'Subscription'}",
                          style: TextStyle(color: _subTextColor, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Amount Due",
                              style: TextStyle(color: _subTextColor, fontSize: 14),
                            ),
                            Text(
                              "₹${sub['Monthly Cost'] ?? '0'}",
                              style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDayCell(DateTime date, bool isToday, {bool isSelected = false}) {
    final events = _getEventsForDay(date);
    final hasEvents = events.isNotEmpty;

    return Container(
      margin: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isSelected
            ? _accentTeal
            : (isToday ? Colors.white.withOpacity(0.05) : Colors.transparent),
        shape: BoxShape.circle,
        boxShadow: isSelected
            ? [BoxShadow(color: _accentTeal.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)]
            : null,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                color: _textColor,
                fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
            if (hasEvents)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : _accentTeal,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Generate upcoming bills logic
    final List<Map<String, dynamic>> upcomingBills = [];
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    for (var sub in widget.subscriptions) {
      if (sub is Map<String, dynamic>) {
        final nextBillingStr = sub['Next Billing Date']?.toString() ?? "";
        try {
          final originalDate = _dateFormat.parse(nextBillingStr);
          
          // Subscriptions recur monthly. Find the next occurrence from today.
          DateTime nextOccurrence = DateTime(now.year, now.month, originalDate.day);
          if (nextOccurrence.isBefore(todayMidnight)) {
            // Already passed this month, so the next bill is next month
            int nextMonth = now.month == 12 ? 1 : now.month + 1;
            int nextYear = now.month == 12 ? now.year + 1 : now.year;
            nextOccurrence = DateTime(nextYear, nextMonth, originalDate.day);
          }

          // Clone sub to modify the display date without changing the global state
          final uiSub = Map<String, dynamic>.from(sub);
          uiSub['Next Billing Date'] = _dateFormat.format(nextOccurrence);
          upcomingBills.add(uiSub);
        } catch (e) {
          // ignore
        }
      }
    }

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
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: Text("Calendar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: _textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.search, color: _accentTeal),
              onPressed: () {},
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Calendar Card
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                rowHeight: 52,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                  final events = _getEventsForDay(selectedDay);
                  
                  // Modify the events so the popup correctly shows the selected month/year
                  final List<Map<String, dynamic>> popupEvents = events.map((e) {
                    final modified = Map<String, dynamic>.from(e as Map<String, dynamic>);
                    final originalDate = _dateFormat.parse(modified['Next Billing Date'].toString());
                    final nextOccurrence = DateTime(selectedDay.year, selectedDay.month, originalDate.day);
                    modified['Next Billing Date'] = _dateFormat.format(nextOccurrence);
                    return modified;
                  }).toList();
                  
                  if (popupEvents.isNotEmpty) {
                    _showEventPopup(context, popupEvents);
                  }
                },
                eventLoader: _getEventsForDay,
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: _textColor, fontSize: 18, fontWeight: FontWeight.bold),
                  leftChevronIcon: Icon(Icons.chevron_left, color: _accentTeal),
                  rightChevronIcon: Icon(Icons.chevron_right, color: _accentTeal),
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, date, _) => _buildDayCell(date, false),
                  todayBuilder: (context, date, _) => _buildDayCell(date, true),
                  selectedBuilder: (context, date, _) => _buildDayCell(date, false, isSelected: true),
                  outsideBuilder: (context, date, _) => const SizedBox.shrink(),
                ),
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: false,
                  markersMaxCount: 0, // We handle markers manually inside cell builder
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Color(0xFFFF0266), fontSize: 12, fontWeight: FontWeight.bold),
                  weekendStyle: TextStyle(color: Color(0xFFFF0266), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            // Upcoming Bills Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Upcoming Bills",
                    style: TextStyle(color: _textColor, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "See all",
                    style: TextStyle(color: _accentTeal, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            if (upcomingBills.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: Text("No upcoming bills found.", style: TextStyle(color: _subTextColor))),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: upcomingBills.take(5).length,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemBuilder: (context, index) {
                  final sub = upcomingBills[index];
                  
                  // Format the due date to "MMM dd" (e.g., Mar 15)
                  String formattedDate = sub['Next Billing Date'] ?? '';
                  try {
                    final d = _dateFormat.parse(formattedDate);
                    formattedDate = DateFormat('MMM dd').format(d);
                  } catch (e) {
                    // ignore
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Icon Box
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: sub['Icon'] != null 
                                ? Image.network(sub['Icon'], width: 24, errorBuilder: (c, e, s) => Text((sub['Merchant']?.toString() ?? "?")[0].toUpperCase(), style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 20)))
                                : Text((sub['Merchant']?.toString() ?? "?")[0].toUpperCase(), style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // Center Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sub['Merchant']?.toString() ?? "Unknown",
                                style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Due $formattedDate",
                                style: TextStyle(color: _accentTeal, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        
                        // Right Amount & Pay Pill
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₹${sub['Monthly Cost'] ?? '0'}",
                              style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: _accentTeal.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "PAY",
                                style: TextStyle(color: _accentTeal, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
