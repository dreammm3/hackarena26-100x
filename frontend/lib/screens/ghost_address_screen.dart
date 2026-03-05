import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class GhostAddressScreen extends StatefulWidget {
  final String userId;

  const GhostAddressScreen({super.key, required this.userId});

  @override
  State<GhostAddressScreen> createState() => _GhostAddressScreenState();
}

class _GhostAddressScreenState extends State<GhostAddressScreen> {
  final String backendUrl = "http://10.220.205.25:8000";
  List<dynamic> _ghostAddresses = [];
  bool _isLoading = true;
  String _error = "";
  double _walletBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchGhostAddresses();
    _fetchWalletBalance();
  }

  Future<void> _fetchWalletBalance() async {
    try {
      final response = await http.get(Uri.parse("$backendUrl/api/wallet/balance?user_id=${widget.userId}"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _walletBalance = (data['balance'] as num).toDouble();
        });
      }
    } catch (e) {
      print("Wallet fetch error: $e");
    }
  }

  Future<void> _topupWallet(double amount) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/wallet/topup?user_id=${widget.userId}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"amount": amount}),
      );
      if (response.statusCode == 200) {
        await _fetchWalletBalance();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("₹$amount added to wallet!")));
      }
    } catch (e) {
      setState(() => _error = "Topup error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchGhostAddresses() async {
    setState(() {
      _isLoading = true;
      _error = "";
    });

    try {
      final response = await http.get(
        Uri.parse("$backendUrl/api/ghost/list?user_id=${widget.userId}"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _ghostAddresses = data['ghost_addresses'] ?? [];
        });
      } else {
        setState(() {
          _error = "Failed to load ghost addresses: ${response.statusCode}";
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

  Future<void> _generateGhostAddress() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("$backendUrl/api/ghost/generate?user_id=${widget.userId}"),
      );

      if (response.statusCode == 200) {
        await _fetchGhostAddresses();
      } else {
        setState(() {
          _error = "Failed to generate ghost address: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Error: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _burnGhostAddress(String email) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.delete(
        Uri.parse("$backendUrl/api/ghost/burn?email_address=$email"),
      );

      if (response.statusCode == 200) {
        await _fetchGhostAddresses();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ghost address burned! No more emails will be accepted.")),
        );
      } else {
        setState(() {
          _error = "Failed to burn address: ${response.statusCode}";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "Error: $e";
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String email) {
    Clipboard.setData(ClipboardData(text: email));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$email copied to clipboard!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text("Ghost Addresses"),
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading && _ghostAddresses.isEmpty && _walletBalance == 0
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00DEC1)))
          : Column(
              children: [
                // Premium Wallet Card
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 10)],
                  ),
                  child: Column(
                    children: [
                      const Text("VIRTUAL TRIAL WALLET", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      const SizedBox(height: 10),
                      Text("₹${_walletBalance.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () => _showTopupDialog(),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2), elevation: 0),
                            child: const Text("TOP UP", style: TextStyle(color: Colors.white)),
                          ),
                          const Icon(Icons.shield, color: Colors.white70, size: 20),
                          const Text("SECURE TRIALS", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Text(
                    "Use Ghost IDs for trials. Subscriptions detected here automatically sync to your dashboard.",
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_error, style: const TextStyle(color: Colors.redAccent)),
                  ),
                Expanded(
                  child: _ghostAddresses.isEmpty && !_isLoading
                      ? const Center(child: Text("No ghost addresses yet.", style: TextStyle(color: Colors.white70)))
                      : ListView.builder(
                          itemCount: _ghostAddresses.length,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemBuilder: (context, index) {
                            final ghost = _ghostAddresses[index];
                            return Card(
                              color: Colors.white.withOpacity(0.04),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: const Color(0xFF00DEC1).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.alternate_email, color: Color(0xFF00DEC1), size: 20),
                                ),
                                title: Text(
                                  ghost['email_address'], 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  ghost['active'] ? "Active (Shielded)" : "Burned", 
                                  style: TextStyle(color: ghost['active'] ? Colors.greenAccent : Colors.redAccent, fontSize: 11),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy, color: Colors.white60, size: 20),
                                      onPressed: () => _copyToClipboard(ghost['email_address']),
                                    ),
                                    if (ghost['active'])
                                      IconButton(
                                        icon: const Icon(Icons.flash_on, color: Colors.orangeAccent, size: 20),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              backgroundColor: const Color(0xFF16213E),
                                              title: const Text("Kill Signal?", style: TextStyle(color: Colors.white)),
                                              content: const Text("This blocks all incoming data from this ID. Permanent action.", style: TextStyle(color: Colors.white70)),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(context), child: const Text("BACK")),
                                                TextButton(
                                                  onPressed: () {
                                                    Navigator.pop(context);
                                                    _burnGhostAddress(ghost['email_address']);
                                                  },
                                                  child: const Text("BURN", style: TextStyle(color: Colors.redAccent)),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _generateGhostAddress,
                      icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.add, size: 20),
                      label: const Text("NEW GHOST ID", style: TextStyle(letterSpacing: 1.1, fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00DEC1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showTopupDialog() {
    final TextEditingController _amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF16213E),
        title: const Text("Top Up Wallet", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: "Amount (₹)",
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
            onPressed: () {
              final amt = double.tryParse(_amountController.text) ?? 500.0;
              Navigator.pop(context);
              _topupWallet(amt);
            },
            child: const Text("RECHARGE", style: TextStyle(color: Color(0xFF00DEC1))),
          ),
        ],
      ),
    );
  }
}
