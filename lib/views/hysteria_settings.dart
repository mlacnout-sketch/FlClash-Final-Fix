import 'dart:convert';
import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/common/path.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  List<HysteriaProfile> _profiles = [];
  String? _selectedProfileId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? profilesJson = prefs.getString('zivpn_profiles_list');
      final String? lastId = prefs.getString('zivpn_active_profile_id');

      if (profilesJson != null) {
        try {
          final List<dynamic> decoded = jsonDecode(profilesJson);
          _profiles = decoded.map((e) => HysteriaProfile.fromJson(e)).toList();
        } catch (e) {
          debugPrint("Error parsing profiles: $e");
        }
      }

      if (_profiles.isEmpty) {
        final defaultProfile = HysteriaProfile(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: "Default Profile",
        );
        _profiles.add(defaultProfile);
        // Removed _saveProfilesToDisk() to prevent I/O blocking during init
      }

      if (lastId != null && _profiles.any((p) => p.id == lastId)) {
        _selectProfile(lastId!);
      } else {
        _selectProfile(_profiles.first.id);
      }
    } catch (e) {
      debugPrint("Critical error loading profiles: $e");
      // Fallback mechanism
      if (_profiles.isEmpty) {
         final fallback = HysteriaProfile(id: "fallback", name: "Default");
         _profiles.add(fallback);
         _selectProfile(fallback.id);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _selectProfile(String id) {
    final profile = _profiles.firstWhere((p) => p.id == id, orElse: () => _profiles.first);
    setState(() {
      _selectedProfileId = profile.id;
      _ipController.text = profile.ip;
      _passController.text = profile.password;
      _obfsController.text = profile.obfs;
      _portRangeController.text = profile.portRange;
    });
    _saveLastActiveId(profile.id);
  }

  Future<void> _saveLastActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zivpn_active_profile_id', id);
  }

  Future<void> _saveProfilesToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonStr = jsonEncode(_profiles.map((e) => e.toJson()).toList());
    await prefs.setString('zivpn_profiles_list', jsonStr);
  }

  Future<void> _saveCurrentProfile() async {
    if (_selectedProfileId == null) return;
    
    final index = _profiles.indexWhere((p) => p.id == _selectedProfileId);
    if (index != -1) {
      setState(() {
        _profiles[index].ip = _ipController.text;
        _profiles[index].password = _passController.text;
        _profiles[index].obfs = _obfsController.text;
        _profiles[index].portRange = _portRangeController.text;
      });
      await _saveProfilesToDisk();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile Saved!')));
    }
  }

  Future<void> _addNewProfile() async {
    final TextEditingController nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Profile Name"),
        content: TextField(
            controller: nameController, 
            autofocus: true,
            decoration: const InputDecoration(hintText: "e.g. Server SG")
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                final newProfile = HysteriaProfile(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                  ip: "",
                  password: "",
                );
                setState(() {
                  _profiles.add(newProfile);
                });
                _saveProfilesToDisk();
                _selectProfile(newProfile.id);
                Navigator.pop(context);
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCurrentProfile() async {
    if (_profiles.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the last profile.')));
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Profile?"),
        content: const Text("Are you sure you want to delete this profile?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
               setState(() {
                 _profiles.removeWhere((p) => p.id == _selectedProfileId);
               });
               _saveProfilesToDisk();
               _selectProfile(_profiles.first.id);
               Navigator.pop(context);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndApplyProfile(String ip) async {
    final profileId = "zivpn_turbo";
    final profileLabel = "ZIVPN Turbo Config";
    
    String serverRule;
    if (RegExp(r'^[\\d\. ]+$').hasMatch(ip)) {
      serverRule = "IP-CIDR, $ip/32, DIRECT";
    } else {
      serverRule = "DOMAIN, $ip, DIRECT";
    }

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
  - $serverRule
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

      await globalState.appController.addProfile(profile);
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
    String currentIp = _ipController.text.trim();
    final String password = _passController.text.trim();

    if (currentIp.isEmpty || password.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter Server IP and Password')),
        );
      }
      return;
    }

    // Logic Host-to-IP
    final isIpFormat = RegExp(r'^[\\d\. ]+$').hasMatch(currentIp);
    if (!isIpFormat) {
      try {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resolving Host...')));
        
        final List<InternetAddress> result = await InternetAddress.lookup(currentIp);
        if (result.isNotEmpty && result[0].type == InternetAddressType.IPv4) {
          final resolvedIp = result[0].address;
          setState(() {
            _ipController.text = resolvedIp;
          });
          currentIp = resolvedIp;
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resolved: $resolvedIp')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('DNS Error: Failed to resolve $currentIp')));
        return;
      }
    }

    try {
      final String result = await platform.invokeMethod('start_process', {
        'ip': currentIp, // Use resolved IP
        'pass': _passController.text,
        'obfs': _obfsController.text,
        'port_range': _portRangeController.text,
      });

      if (_autoGenerateProfile) {
        await _generateAndApplyProfile(currentIp);
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
    if (_isLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hysteria Turbo Multi'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Multi-Account Header
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                        children: [
                            const Icon(Icons.account_circle, size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                                child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                        value: _selectedProfileId,
                                        isExpanded: true,
                                        items: _profiles.map((p) {
                                            return DropdownMenuItem(
                                                value: p.id,
                                                child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                            );
                                        }).toList(),
                                        onChanged: (val) {
                                            if (val != null) _selectProfile(val);
                                        },
                                    ),
                                ),
                            ),
                            IconButton(
                                icon: const Icon(Icons.save, color: Colors.blue),
                                tooltip: "Save Profile",
                                onPressed: _saveCurrentProfile,
                            ),
                            IconButton(
                                icon: const Icon(Icons.add_circle, color: Colors.green),
                                tooltip: "New Profile",
                                onPressed: _addNewProfile,
                            ),
                            IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: "Delete Profile",
                                onPressed: _deleteCurrentProfile,
                            ),
                        ],
                    ),
                ),
              ),

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
                controller: _passController,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _obfsController,
                decoration: const InputDecoration(labelText: 'Obfs', border: OutlineInputBorder()),
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
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                ),
                child: const Text('Start Turbo Engine', style: TextStyle(fontSize: 18)),
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
                "Multi-Account Manager & Auto-Resolve Host included.\n"
                "Save your profile before starting to keep settings.",
                textAlign: TextAlign.center,
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

class HysteriaProfile {
  String id;
  String name;
  String ip;
  String password;
  String obfs;
  String portRange;

  HysteriaProfile({
    required this.id,
    required this.name,
    this.ip = "",
    this.password = "",
    this.obfs = "hu``hqb`c",
    this.portRange = "6000-19999",
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'ip': ip,
    'password': password,
    'obfs': obfs,
    'portRange': portRange,
  };

  factory HysteriaProfile.fromJson(Map<String, dynamic> json) => HysteriaProfile(
    id: json['id'] ?? "",
    name: json['name'] ?? "Unknown",
    ip: json['ip'] ?? "",
    password: json['password'] ?? "",
    obfs: json['obfs'] ?? "hu``hqb`c",
    portRange: json['portRange'] ?? "6000-19999",
  );
}