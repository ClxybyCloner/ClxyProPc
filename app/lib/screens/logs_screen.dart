import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../theme/clxy_colors.dart';

class LogsScreen extends StatefulWidget {
  final AppState state;

  const LogsScreen({super.key, required this.state});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _selectedLevel = 'ALL';
  final TextEditingController _filterCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _filterCtrl.addListener(() {
      setState(() => _query = _filterCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  void _copyAll(List<LogEntry> logs) {
    final text = logs.map((l) => l.toString()).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  Color _levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return ClxyColors.redDisconnectStart;
      case 'WARN':
        return ClxyColors.amberWarning;
      case 'VPN':
        return ClxyColors.cyanGlow;
      default:
        return ClxyColors.textDim;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.state.logs.where((l) {
      if (_selectedLevel != 'ALL' && l.level.toUpperCase() != _selectedLevel) {
        return false;
      }
      if (_query.isNotEmpty && !l.message.toLowerCase().contains(_query)) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: ClxyColors.bgTop,
      appBar: AppBar(
        backgroundColor: ClxyColors.cardSurface,
        elevation: 0,
        title: const Text('Live Logs', style: TextStyle(color: ClxyColors.textPrimary, fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy_rounded, color: ClxyColors.cyanText, size: 20),
            onPressed: () => _copyAll(filtered),
            tooltip: 'Copy Logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: ClxyColors.textMuted, size: 20),
            onPressed: () {
              setState(() => widget.state.logs.clear());
            },
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            color: ClxyColors.cardSurface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _filterCtrl,
                    style: const TextStyle(color: ClxyColors.textPrimary, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Filter log messages…',
                      hintStyle: TextStyle(color: ClxyColors.textDim),
                      isDense: true,
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.search_rounded, color: ClxyColors.textMuted, size: 16),
                      prefixIconConstraints: BoxConstraints(minWidth: 28, minHeight: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedLevel,
                  dropdownColor: ClxyColors.cardSurface,
                  underline: const SizedBox(),
                  style: const TextStyle(color: ClxyColors.cyanText, fontSize: 12),
                  items: ['ALL', 'VPN', 'SYSTEM', 'ERROR', 'WARN'].map((lvl) {
                    return DropdownMenuItem(value: lvl, child: Text(lvl));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedLevel = val);
                  },
                ),
              ],
            ),
          ),

          // Log List
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text('No log entries match criteria', style: TextStyle(color: ClxyColors.textDim, fontSize: 12)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12.0),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final item = filtered[i];
                      final timeStr =
                          '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              timeStr,
                              style: const TextStyle(color: ClxyColors.textDim, fontSize: 10.5, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                              decoration: BoxDecoration(
                                color: _levelColor(item.level).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4.0),
                              ),
                              child: Text(
                                item.level,
                                style: TextStyle(color: _levelColor(item.level), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.message,
                                style: const TextStyle(color: ClxyColors.textPrimary, fontSize: 11.5, fontFamily: 'monospace'),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
