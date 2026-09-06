import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LoadMoneyScreen extends StatefulWidget {
  final String deviceId;
  const LoadMoneyScreen({super.key, required this.deviceId});

  @override
  State<LoadMoneyScreen> createState() => _LoadMoneyScreenState();
}

class _LoadMoneyScreenState extends State<LoadMoneyScreen> {
  static const String _backendUrl = 'https://busam.onrender.com';
  final TextEditingController _amountController = TextEditingController();
  bool _showWebView = false;
  late final WebViewController _webViewController;

  void _startPayment() {
    final amount = _amountController.text.trim();
    if (amount.isEmpty) return;

    final url =
        '$_backendUrl/pay/mock/initiate?amount=$amount&device_id=${widget.deviceId}';

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));

    setState(() => _showWebView = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showWebView) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('eSewa Payment'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _showWebView = false),
          ),
        ),
        body: WebViewWidget(controller: _webViewController),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Load Money')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text(
              'Enter amount to load (NPR)',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: 'NPR ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Pay with eSewa',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Test mode: eSewa ID 9806800001, password Nepal@123',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
