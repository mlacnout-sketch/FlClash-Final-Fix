import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/common/path.dart';
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
  bool _autoGenerateProfile = true;
  static const platform = MethodChannel('com.follow.clash/hysteria');

  @override
  void initState() {
    super.initState();
    // Default values (optional)
    _ipController.text = "202.10.48.173";
    _passController.text = "asd63";
    _obfsController.text = "hu``hqb`c";
  }

  Future<void> _generateAndApplyProfile(String ip) async {
    final profileId = "zivpn_turbo";
    final profileLabel = "ZIVPN Turbo Config";
    
    final yamlContent = '''
mixed-port: 7890
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
external-controller: '127.0.0.1:9090'
dns:
  enable: true
  ipv6: false
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  use-hosts: true
  nameserver:
    - https://doh.pub/dns-query
    - https://dns.alidns.com/dns-query
  fallback:
    - https://doh.dns.sb/dns-query
    - https://8.8.8.8/dns-query
    - https://1.1.1.1/dns-query
  fallback-filter:
    geoip: true
    ipcidr:
      - 240.0.0.0/4
proxies:
  - name: "Hysteria Turbo"
    type: socks5
    server: 127.0.0.1
    port: 7777
    udp: true
proxy-groups:
  - name: "ZIVPN Turbo"
    type: select
    proxies:
      - "Hysteria Turbo"
      - DIRECT
rules:
  - IP-CIDR, $ip/32, DIRECT
  - MATCH, ZIVPN Turbo
''';

    try {
      final profilePath = await appPath.getProfilePath(profileId);
      final file = File(profilePath);
      await file.create(recursive: true);
      await file.writeAsString(yamlContent);

      final profile = Profile(
        id: profileId,
        label: profileLabel,
        autoUpdateDuration: const Duration(days: 1),
        url: '', // Local file
      );

      // Add to app controller
      await globalState.appController.addProfile(profile);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile generated & applied!')),
        );
      }
    } catch (e) {
      debugPrint("Error generating profile: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating profile: $e')),
        );
      }
    }
  }

  Future<void> _startHysteria() async {
    try {
      final String result = await platform.invokeMethod('start_process', {
        'ip': _ipController.text,
        'pass': _passController.text,
        'obfs': _obfsController.text,
      });

      if (_autoGenerateProfile) {
        await _generateAndApplyProfile(_ipController.text);
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Success'),
            content: Text(result),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text("Failed to start: '${e.message}'"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
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
        child: SingleChildScrollView(
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Checkbox(
                    value: _autoGenerateProfile,
                    onChanged: (val) {
                      setState(() {
                        _autoGenerateProfile = val ?? true;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text('Auto-Generate & Apply Clash Profile'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _startHysteria,
                child: const Text('Start Turbo Engine'),
              ),
              const SizedBox(height: 20),
              const Text(
                "Note: This will start 4 Hysteria cores on ports 1080-1083 and a Load Balancer on port 7777.\\n"
                "Auto-Generate will create a profile pointing to 127.0.0.1:7777 and add a DIRECT rule for the Server IP.",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
