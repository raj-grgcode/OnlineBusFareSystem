import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PassScreen extends StatefulWidget {
  final String deviceId;
  final String company;

  const PassScreen({super.key, required this.deviceId, required this.company});

  @override
  State<PassScreen> createState() => _PassScreenState();
}

class _PassScreenState extends State<PassScreen> {
  static const String _backendUrl = 'https://busam.onrender.com';

  static const int pricePerRide = 20;

  double _rides = 10;

  int _ridesRemaining = 0;

  bool _loading = false;

  String? _message;

  bool? _messageSuccess;

  @override
  void initState() {
    super.initState();
    _fetchPassBalance();
  }

  // ==========================================================
  // FETCH BALANCE
  // ==========================================================

  Future<void> _fetchPassBalance() async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/pass/${widget.deviceId}'),
      );

      final data = jsonDecode(response.body);

      final passes = data['passes'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _ridesRemaining = passes[widget.company] ?? 0;
        });
      }
    } catch (e) {
      // Keep last known value.
    }
  }

  // ==========================================================
  // BUY PASS
  // ==========================================================

  Future<void> _buyPass() async {
    setState(() {
      _loading = true;
      _message = null;
      _messageSuccess = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/pass/buy'),

        headers: {'Content-Type': 'application/json'},

        body: jsonEncode({
          'device_id': widget.deviceId,
          'company': widget.company,
          'rides': _rides.toInt(),
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      final success = data['success'] == true;

      setState(() {
        _loading = false;

        _messageSuccess = success;

        _message =
            data['message'] ??
            (success ? 'Pass purchased successfully!' : 'Purchase failed');

        if (success) {
          _ridesRemaining = data['rides_remaining'] ?? _ridesRemaining;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _messageSuccess = false;
        _message = 'Network error. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int rides = _rides.toInt();

    final int cost = rides * pricePerRide;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.company} Pass'), centerTitle: true),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // =================================================
              // COMPANY HEADER
              // =================================================
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,

                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),

                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.10),
                    ),

                    child: Icon(
                      Icons.directions_bus,
                      size: 30,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),

                  const SizedBox(width: 14),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        widget.company,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 3),

                      const Text(
                        'Digital Bus Pass',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // =================================================
              // CURRENT BALANCE
              // =================================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),

                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.08),
                ),

                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,

                      decoration: BoxDecoration(
                        shape: BoxShape.circle,

                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.12),
                      ),

                      child: Icon(
                        Icons.confirmation_number_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          const Text(
                            'Current pass balance',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            '$_ridesRemaining rides',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // =================================================
              // CHOOSE RIDES
              // =================================================
              const Text(
                'Choose your pass',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 6),

              const Text(
                'Select how many rides you want to purchase.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),

              const SizedBox(height: 20),

              // =================================================
              // PRICE DISPLAY
              // =================================================
              Center(
                child: Column(
                  children: [
                    Text(
                      '$rides',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),

                    const Text(
                      'rides',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'NPR $cost',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // =================================================
              // SLIDER
              // =================================================
              Slider(
                value: _rides,
                min: 10,
                max: 50,
                divisions: 4,
                label: '$rides rides',

                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() {
                          _rides = value;
                        });
                      },
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: const [
                  Text(
                    '10 rides',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    '50 rides',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              // =================================================
              // PRICE INFO
              // =================================================
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),

                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),

                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),

                    SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'NPR 20 per ride. Valid for any distance.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // =================================================
              // BUY BUTTON
              // =================================================
              SizedBox(
                width: double.infinity,
                height: 56,

                child: ElevatedButton(
                  onPressed: _loading ? null : _buyPass,

                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,

                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          'Buy $rides rides • NPR $cost',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              // =================================================
              // MESSAGE
              // =================================================
              if (_message != null) ...[
                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),

                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),

                    color: (_messageSuccess == true)
                        ? Colors.green.withOpacity(0.10)
                        : Colors.red.withOpacity(0.10),
                  ),

                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Icon(
                        _messageSuccess == true
                            ? Icons.check_circle_outline
                            : Icons.error_outline,

                        size: 22,

                        color: _messageSuccess == true
                            ? Colors.green
                            : Colors.red,
                      ),

                      const SizedBox(width: 10),

                      Expanded(
                        child: Text(
                          _message!,
                          style: TextStyle(
                            fontSize: 14,
                            color: _messageSuccess == true
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
