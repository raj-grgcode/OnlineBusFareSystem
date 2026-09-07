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

  double _rides = 10; // slider value, 10-50 step 10
  int _ridesRemaining = 0;
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _fetchPassBalance();
  }

  Future<void> _fetchPassBalance() async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/pass/${widget.deviceId}'),
      );
      final data = jsonDecode(response.body);
      final passes = data['passes'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() => _ridesRemaining = passes[widget.company] ?? 0);
      }
    } catch (e) {
      // silently ignore, keep last known value
    }
  }

  Future<void> _buyPass() async {
    setState(() {
      _loading = true;
      _message = null;
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

      setState(() {
        _loading = false;
        _message =
            data['message'] ??
            (data['success'] == true ? 'Pass purchased!' : 'Purchase failed');
        if (data['success'] == true) {
          _ridesRemaining = data['rides_remaining'] ?? _ridesRemaining;
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _message = 'Network error, try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int rides = _rides.toInt();
    final int cost = rides * pricePerRide;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.company} Pass')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${widget.company} rides remaining',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      '$_ridesRemaining',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '$rides rides — NPR $cost',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const Text(
              'NPR 20 per ride, any distance',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            Slider(
              value: _rides,
              min: 10,
              max: 50,
              divisions: 4, // 10, 20, 30, 40, 50
              label: '$rides rides',
              onChanged: (v) => setState(() => _rides = v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _buyPass,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Buy $rides rides — NPR $cost'),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.green),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
