import 'dart:convert';
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
  final TextEditingController _profileNameController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _obfsController = TextEditingController();
  final TextEditingController _portRangeController = TextEditingController();
  final TextEditingController _mtuController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _ipController.text = "";
    _passController.text = "";
    _obfsController.text = "hu``hqb`c";
    _portRangeController.text = "6000-19999";
    _mtuController.text = "9000";
  }

  Future<void> _saveProfile() async {
    final name = _profileNameController.text.trim();
    final host = _ipController.text.trim();
    final pass = _passController.text.trim();
    final obfs = _obfsController.text.trim();
    final portRange = _portRangeController.text.trim();
    final mtu = _mtuController.text.trim();

    if (name.isEmpty || host.isEmpty || pass.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill Profile Name, IP/Domain, and Password')),
        );
      }
      return;
    }

    // 1. Prepare Metadata JSON
    final metadata = {
      "ip": host,
      "pass": pass,
      "obfs": obfs,
      "port_range": portRange,
      "mtu": mtu
    };
    final metadataString = jsonEncode(metadata);

    // 2. Generate YAML Config (Smart Mode)
    final bool isIp = RegExp(r'^[\d\.]+$').hasMatch(host);
    String yamlContent;

    if (!isIp) {
      // TCP Optimized for Domain (Zero Quota)
      yamlContent = '''
# HYSTERIA_CONFIG: $metadataString
# Clash Config (TCP Optimized for $name)
port: 7890
socks-port: 7891
redir-port: 7892
allow-lan: false
mode: rule
log-level: debug
external-controller: 127.0.0.1:9090

proxies:
  - name: "ZIVPN-Core"
    type: socks5
    server: 127.0.0.1
    port: 7777
    udp: false

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "ZIVPN-Core"

rules:
  - MATCH,PROXY

dns:
  enable: true
  ipv6: false
  listen: 0.0.0.0:1053
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  fallback:
    - https://1.0.0.1/dns-query
    - https://8.8.4.4/dns-query
''';
    } else {
      // Standard UDP for IP
      yamlContent = '''
# HYSTERIA_CONFIG: $metadataString
mixed-port: 7890
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
external-controller: '127.0.0.1:9090'
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
    udp: true
proxy-groups:
  - name: "ZIVPN Turbo"
    type: select
    proxies:
      - "Hysteria Turbo"
      - DIRECT
rules:
  - IP-CIDR, $host/32, DIRECT
  - MATCH, ZIVPN Turbo
''';
    }

    try {
      // 3. Save File to Profiles Directory
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final profileFilename = "$safeName.yaml";
      final profilesPath = await appPath.profilesPath;
      final fullPath = "$profilesPath/$profileFilename";
      
      final file = File(fullPath);
      // Fix: Ensure parent directory exists and create file recursively
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsString(yamlContent);

      // 4. Reload Profiles
      await globalState.appController.updateProfiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile "$name" created! Select it in Profiles menu.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint("Save profile error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Hysteria Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _profileNameController,
                decoration: const InputDecoration(
                    labelText: 'Profile Name (e.g. Indo-Game)', 
                    border: OutlineInputBorder(),
                    helperText: "This name will appear in Profiles list"
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _ipController,
                decoration: const InputDecoration(labelText: 'Server IP / Domain', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _portRangeController,
                decoration: const InputDecoration(labelText: 'Port Range', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _mtuController,
                decoration: const InputDecoration(labelText: 'MTU', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passController,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _obfsController,
                decoration: const InputDecoration(labelText: 'Obfs', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save),
                label: const Text('Save & Create Profile', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
