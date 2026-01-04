import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HysteriaSettingsPage extends StatefulWidget {
  const HysteriaSettingsPage({super.key});

  @override
  State<HysteriaSettingsPage> createState() => _HysteriaSettingsPageState();
}

class _HysteriaSettingsPageState extends State<HysteriaSettingsPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _obfsController = TextEditingController();
  static const platform = MethodChannel('com.follow.clash/hysteria');

  @override
  void initState() {
    super.initState();
    // Default values (optional)
    _ipController.text = "202.10.48.173";
    _passController.text = "asd63";
    _obfsController.text = "hu``hqb`c";
  }

  Future<void> _startHysteria() async {
    try {
      final String result = await platform.invokeMethod('start_process', {
        'ip': _ipController.text,
        'pass': _passController.text,
        'obfs': _obfsController.text,
      });
      if (mounted) {
        CommonDialog.show(
          context: context,
          title: const Text('Success'),
          content: Text(result),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        CommonDialog.show(
          context: context,
          title: const Text('Error'),
          content: Text("Failed to start: '${e.message}'"),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hysteria Turbo Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(labelText: 'Server IP'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _obfsController,
              decoration: const InputDecoration(labelText: 'Obfs'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startHysteria,
              child: const Text('Start Turbo Engine'),
            ),
            const SizedBox(height: 20),
            const Text(
              "Note: This will start 4 Hysteria cores on ports 1080-1083 and a Load Balancer on port 7777.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
