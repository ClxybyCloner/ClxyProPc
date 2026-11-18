import 'package:flutter/material.dart';
import '../core/prefs.dart';
import '../theme/clxy_colors.dart';

class SplitTunnelPicker extends StatefulWidget {
  const SplitTunnelPicker({super.key});

  @override
  State<SplitTunnelPicker> createState() => _SplitTunnelPickerState();
}

class _SplitTunnelPickerState extends State<SplitTunnelPicker> {
  late List<String> _excluded;
  final TextEditingController _exeCtrl = TextEditingController();

  static const List<Map<String, String>> _commonPrograms = [
    {'name': 'Google Chrome', 'exe': 'chrome.exe'},
    {'name': 'Mozilla Firefox', 'exe': 'firefox.exe'},
    {'name': 'Telegram Desktop', 'exe': 'telegram.exe'},
    {'name': 'Discord', 'exe': 'discord.exe'},
    {'name': 'Steam', 'exe': 'steam.exe'},
    {'name': 'Epic Games Launcher', 'exe': 'EpicGamesLauncher.exe'},
    {'name': 'Spotify', 'exe': 'spotify.exe'},
    {'name': 'Microsoft Edge', 'exe': 'msedge.exe'},
  ];

  @override
  void initState() {
    super.initState();
    _excluded = List.from(Prefs.vpnExcludedApps);
  }

  @override
  void dispose() {
    _exeCtrl.dispose();
    super.dispose();
  }

  void _addExe(String exe) {
    var clean = exe.trim().toLowerCase();
    if (clean.isEmpty) return;
    if (!clean.endsWith('.exe')) clean += '.exe';
    if (!_excluded.contains(clean)) {
      setState(() {
        _excluded.add(clean);
      });
      Prefs.vpnExcludedApps = _excluded;
      _exeCtrl.clear();
    }
  }

  void _removeExe(String exe) {
    setState(() {
      _excluded.remove(exe);
    });
    Prefs.vpnExcludedApps = _excluded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClxyColors.bgTop,
      appBar: AppBar(
        backgroundColor: ClxyColors.cardSurface,
        elevation: 0,
        title: const Text('Split Tunneling', style: TextStyle(color: ClxyColors.textPrimary, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Bypassed Programs',
            style: TextStyle(color: ClxyColors.cyanText, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Selected programs route directly through your local connection outside the VPN tunnel.',
            style: TextStyle(color: ClxyColors.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // Custom executable input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _exeCtrl,
                  style: const TextStyle(color: ClxyColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Enter executable (e.g. app.exe)…',
                    hintStyle: const TextStyle(color: ClxyColors.textDim),
                    filled: true,
                    fillColor: ClxyColors.cardSurface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: const BorderSide(color: ClxyColors.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: const BorderSide(color: ClxyColors.glassBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      borderSide: const BorderSide(color: ClxyColors.cyanGlow),
                    ),
                  ),
                  onSubmitted: _addExe,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _addExe(_exeCtrl.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ClxyColors.blueDeep,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                ),
                child: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Text(
            'Current Bypassed List',
            style: TextStyle(color: ClxyColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          if (_excluded.isEmpty)
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: ClxyColors.cardSurface,
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: ClxyColors.glassBorder),
              ),
              child: const Center(
                child: Text('No programs excluded. All traffic routes through VPN.', style: TextStyle(color: ClxyColors.textDim, fontSize: 12)),
              ),
            )
          else
            ..._excluded.map((exe) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6.0),
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                decoration: BoxDecoration(
                  color: ClxyColors.cardSurface,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: ClxyColors.glassBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.computer_rounded, color: ClxyColors.cyanGlow, size: 18),
                        const SizedBox(width: 10),
                        Text(exe, style: const TextStyle(color: ClxyColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: ClxyColors.redDisconnectStart, size: 18),
                      onPressed: () => _removeExe(exe),
                      splashRadius: 18,
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 24),
          const Text(
            'Quick Add Presets',
            style: TextStyle(color: ClxyColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _commonPrograms.map((p) {
              final isAdded = _excluded.contains(p['exe']!.toLowerCase());
              return ActionChip(
                backgroundColor: isAdded ? ClxyColors.blueDeep.withOpacity(0.3) : ClxyColors.cardSurface,
                side: BorderSide(color: isAdded ? ClxyColors.cyanGlow : ClxyColors.glassBorder),
                label: Text(
                  p['name']!,
                  style: TextStyle(
                    color: isAdded ? ClxyColors.cyanText : ClxyColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                avatar: Icon(
                  isAdded ? Icons.check_rounded : Icons.add_rounded,
                  size: 14,
                  color: isAdded ? ClxyColors.cyanText : ClxyColors.textMuted,
                ),
                onPressed: () {
                  if (isAdded) {
                    _removeExe(p['exe']!);
                  } else {
                    _addExe(p['exe']!);
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
