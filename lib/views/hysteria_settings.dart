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
  final TextEditingController _portRangeController = TextEditingController();
  bool _autoGenerateProfile = true;
  static const platform = MethodChannel('com.follow.clash/hysteria');

  @override
  void initState() {
    super.initState();
    // Default values (optional)
    _ipController.text = "103.151.141.221";
    _passController.text = "ajass";
    _obfsController.text = "hu``hqb`c";
    _portRangeController.text = "13001-16500";
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
geo-auto-update: false
geodata-mode: true
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  use-hosts: true
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - https://8.8.4.4/dns-query
  fallback-filter:
    geoip: false
    ipcidr:
      - 240.0.0.0/4
proxies:
  - name: "Hysteria Turbo"
    type: socks5
    server: 127.0.0.1
    port: 7777
    udp: false
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

      final profile = Profile.normal(
        label: profileLabel,
      ).copyWith(
        id: profileId,
      );

      // Add to app controller
      await globalState.appController.addProfile(profile);
      
      // Force select the profile and apply it
      globalState.appController.setProfileAndAutoApply(profile);
      
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
        'port_range': _portRangeController.text,
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
                controller: _portRangeController,
                decoration: const InputDecoration(labelText: 'Port Range (e.g. 13001-16500)'),
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
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.description),
                    label: const Text("View Logs"),
                    onPressed: _viewLogs,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text("Clear Logs"),
                    onPressed: _clearLogs,
                  ),
                ],
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

  Future<void> _viewLogs() async {
    try {
      final appDocPath = await appPath.homeDirPath;
      // appDocPath is usually .../files
      final logFile = File('$appDocPath/zivpn_logs/zivpn_core.log');
      
      String content = "Log file not found at $appDocPath/zivpn_logs/zivpn_core.log";
      if (await logFile.exists()) {
        content = await logFile.readAsString();
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Core Logs"),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(content.isEmpty ? "No logs yet." : content),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ],
          ),
        );
      }
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Err reading logs: $e")));
       }
    }
  }

  Future<void> _clearLogs() async {
     try {
      final appDocPath = await appPath.homeDirPath;
      final logFile = File('$appDocPath/zivpn_logs/zivpn_core.log');
      if (await logFile.exists()) {
        await logFile.writeAsString("");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Logs cleared")));
      }
    } catch (e) {}
  }
}
