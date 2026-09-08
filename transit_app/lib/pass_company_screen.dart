import 'package:flutter/material.dart';
import 'pass_screen.dart';

class PassCompanyScreen extends StatelessWidget {
  final String deviceId;

  const PassCompanyScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Bus Company'),
        centerTitle: true,
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --------------------------------------------------
              // HEADER
              // --------------------------------------------------
              const Text(
                'Buy a Bus Pass',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              const Text(
                'Choose the bus company you use most often.',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),

              const SizedBox(height: 28),

              // --------------------------------------------------
              // INFO CARD
              // --------------------------------------------------
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.08),
                ),

                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 24),

                    SizedBox(width: 12),

                    Expanded(
                      child: Text(
                        'Your pass is valid only on buses operated by the selected company.',
                        style: TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              const Text(
                'Select Company',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),

              const SizedBox(height: 14),

              // --------------------------------------------------
              // MAYURI
              // --------------------------------------------------
              _CompanyCard(
                companyName: 'Mayuri',
                subtitle: 'Mayuri Bus Service',
                icon: Icons.directions_bus,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PassScreen(deviceId: deviceId, company: 'Mayuri'),
                    ),
                  );
                },
              ),

              const SizedBox(height: 14),

              // --------------------------------------------------
              // SAJHA
              // --------------------------------------------------
              _CompanyCard(
                companyName: 'Sajha',
                subtitle: 'Sajha Yatayat',
                icon: Icons.directions_bus_outlined,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PassScreen(deviceId: deviceId, company: 'Sajha'),
                    ),
                  );
                },
              ),

              const SizedBox(height: 30),

              // --------------------------------------------------
              // FOOTER
              // --------------------------------------------------
              Center(
                child: Text(
                  'Choose a company to continue',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// COMPANY CARD
// ============================================================

class _CompanyCard extends StatelessWidget {
  final String companyName;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _CompanyCard({
    required this.companyName,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,

        child: Ink(
          padding: const EdgeInsets.all(18),

          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),

            border: Border.all(color: Colors.grey.withOpacity(0.18)),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),

          child: Row(
            children: [
              // BUS ICON
              Container(
                width: 58,
                height: 58,

                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),

                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.10),
                ),

                child: Icon(
                  icon,
                  size: 30,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),

              const SizedBox(width: 16),

              // COMPANY INFO
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      companyName,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Pass available',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),

              // ARROW
              Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
