import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class StudentIdScreen extends StatefulWidget {
  final String deviceId;
  const StudentIdScreen({super.key, required this.deviceId});

  @override
  State<StudentIdScreen> createState() => _StudentIdScreenState();
}

class _StudentIdScreenState extends State<StudentIdScreen> {
  static const String _backendUrl = 'https://busam.onrender.com';

  File? _selectedImage;
  bool _loading = false;
  String? _status;
  String? _expiryDate;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/student-id/status/${widget.deviceId}'),
      );
      final data = jsonDecode(response.body);
      setState(() {
        _status = data['status'];
        _expiryDate = data['expiry_date'];
      });
    } catch (e) {
      // silently ignore
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<void> _submitId() async {
    if (_selectedImage == null) return;

    setState(() => _loading = true);

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('$_backendUrl/student-id/submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': widget.deviceId,
          'image_base64': base64Image,
        }),
      );
      final data = jsonDecode(response.body);

      setState(() {
        _loading = false;
        if (data['success'] == true) {
          _status = 'pending';
          _selectedImage = null;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Submitted')));
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Student ID Verification')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ---- Current status ----
            if (_status == 'approved') ...[
              const Icon(Icons.verified, color: Colors.green, size: 64),
              const SizedBox(height: 12),
              const Text(
                'Verified Student',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_expiryDate != null)
                Text(
                  'Valid until: $_expiryDate',
                  style: const TextStyle(color: Colors.grey),
                ),
            ] else if (_status == 'pending') ...[
              const Icon(Icons.hourglass_top, color: Colors.orange, size: 64),
              const SizedBox(height: 12),
              const Text(
                'Your ID is pending review',
                style: TextStyle(fontSize: 16),
              ),
            ] else ...[
              // ---- Upload UI (none submitted, or rejected) ----
              if (_status == 'rejected')
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Your previous submission was rejected. Please try again.',
                    style: TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (_selectedImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_selectedImage!, height: 200),
                )
              else
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.badge_outlined,
                      size: 64,
                      color: Colors.grey,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_selectedImage == null || _loading)
                      ? null
                      : _submitId,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit for verification'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
