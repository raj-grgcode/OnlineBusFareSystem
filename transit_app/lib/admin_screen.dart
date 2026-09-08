import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ======================================================
// ADMIN LOGIN SCREEN
// ======================================================

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _usernameController =
      TextEditingController();

  final TextEditingController _passwordController =
      TextEditingController();

  bool _obscurePassword = true;

  // Temporary credentials
  static const String adminUsername = 'admin';
  static const String adminPassword = 'admin123';

  void _login() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username == adminUsername && password == adminPassword) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AdminDashboardScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid admin username or password'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Login'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  size: 80,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Admin Login',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 30),

                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _login,
                    child: const Text(
                      'Login as Admin',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================
// ADMIN DASHBOARD
// ======================================================

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome, Admin',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 30),

            // STUDENT ID VERIFICATION
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.badge),
                label: const Text(
                  'Student ID Verification',
                  style: TextStyle(fontSize: 17),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const StudentIdAdminScreen(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // LOGOUT
            SizedBox(
              height: 55,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                onPressed: () {
                  Navigator.popUntil(
                    context,
                    (route) => route.isFirst,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================
// STUDENT ID ADMIN SCREEN
// ======================================================

class StudentIdAdminScreen extends StatefulWidget {
  const StudentIdAdminScreen({super.key});

  @override
  State<StudentIdAdminScreen> createState() =>
      _StudentIdAdminScreenState();
}

class _StudentIdAdminScreenState
    extends State<StudentIdAdminScreen> {
  static const String _backendUrl =
      'https://busam.onrender.com';

  Map<String, dynamic> _pendingStudents = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPending();
  }

  // ====================================================
  // FETCH PENDING STUDENTS
  // ====================================================

  Future<void> _fetchPending() async {
    setState(() {
      _loading = true;
    });

    try {
      final response = await http.get(
        Uri.parse(
          '$_backendUrl/admin/student-id/pending',
        ),
      );

      final data = jsonDecode(response.body);

      setState(() {
        _pendingStudents = data['pending'] ?? {};
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load: $e'),
          ),
        );
      }
    }
  }

  // ====================================================
  // APPROVE STUDENT
  // ====================================================

  Future<void> _approveStudent(String deviceId) async {
    final expiryDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(
        const Duration(days: 3650),
      ),
      initialDate: DateTime.now().add(
        const Duration(days: 365),
      ),
    );

    if (expiryDate == null) return;

    final expiryString =
        '${expiryDate.year}-'
        '${expiryDate.month.toString().padLeft(2, '0')}-'
        '${expiryDate.day.toString().padLeft(2, '0')}';

    try {
      final response = await http.post(
        Uri.parse(
          '$_backendUrl/admin/student-id/approve',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'device_id': deviceId,
          'expiry_date': expiryString,
        }),
      );

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Student approved until $expiryString',
              ),
            ),
          );
        }

        _fetchPending();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Approval failed: ${response.body}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e'),
          ),
        );
      }
    }
  }

  // ====================================================
  // REJECT STUDENT
  // ====================================================

  Future<void> _rejectStudent(String deviceId) async {
    try {
      final response = await http.post(
        Uri.parse(
          '$_backendUrl/admin/student-id/reject',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'device_id': deviceId,
        }),
      );

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Student ID rejected'),
            ),
          );
        }

        _fetchPending();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Rejection failed: ${response.body}',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejection failed: $e'),
          ),
        );
      }
    }
  }

  // ====================================================
  // UI
  // ====================================================

  @override
  Widget build(BuildContext context) {
    final entries = _pendingStudents.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Student ID Verification',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPending,
          ),
        ],
      ),

      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : entries.isEmpty
              ? const Center(
                  child: Text(
                    'No pending student IDs',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final deviceId = entries[index].key;
                    final studentData =
                        entries[index].value;

                    return Card(
                      margin: const EdgeInsets.only(
                        bottom: 16,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Student ID Submission',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 10),

                            // =================================
                            // STUDENT ID IMAGE
                            // =================================

                            if (studentData['image_base64'] !=
                                null)
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(8),
                                child: Image.memory(
                                  base64Decode(
                                    studentData[
                                        'image_base64'],
                                  ),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              const Icon(
                                Icons.badge,
                                size: 70,
                              ),

                            const SizedBox(height: 10),

                            Text(
                              'Device ID: $deviceId',
                            ),

                            const SizedBox(height: 20),

                            // =================================
                            // APPROVE / REJECT BUTTONS
                            // =================================

                            Row(
                              children: [
                                Expanded(
                                  child:
                                      ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.check,
                                    ),
                                    label: const Text(
                                      'Approve',
                                    ),
                                    onPressed: () =>
                                        _approveStudent(
                                      deviceId,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 10),

                                Expanded(
                                  child:
                                      ElevatedButton.icon(
                                    icon: const Icon(
                                      Icons.close,
                                    ),
                                    label: const Text(
                                      'Reject',
                                    ),
                                    onPressed: () =>
                                        _rejectStudent(
                                      deviceId,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}