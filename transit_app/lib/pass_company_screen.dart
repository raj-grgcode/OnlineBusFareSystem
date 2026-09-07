import 'package:flutter/material.dart';
import 'pass_screen.dart';

class PassCompanyScreen extends StatelessWidget {
  final String deviceId;
  const PassCompanyScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Bus Company')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Buy a pass for a specific company.\nIt only works on that company\'s buses.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PassScreen(deviceId: deviceId, company: 'Mayuri'),
                    ),
                  );
                },
                child: const Text('Mayuri'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PassScreen(deviceId: deviceId, company: 'Sajha'),
                    ),
                  );
                },
                child: const Text('Sajha'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
