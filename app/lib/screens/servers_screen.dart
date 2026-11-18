import 'package:flutter/material.dart';
import '../components/brand_header.dart';
import '../components/circular_country_flag.dart';
import '../components/signal_bars.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/prefs.dart';
import '../theme/clxy_colors.dart';

class ServersScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onClose;

  const ServersScreen({
    super.key,
    required this.state,
    required this.onClose,
  });

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final activePinned = Prefs.server('firefox');

    final filtered = state.servers.where((s) {
      if (_query.isEmpty) return true;
      return s.title.toLowerCase().contains(_query) ||
          s.flagCode.toLowerCase().contains(_query) ||
          s.countryName.toLowerCase().contains(_query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        children: [
          const SizedBox(height: 10.0),

          // Top Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  BrandHeader(logoSize: 28.0, showLabel: false),
                  SizedBox(width: 10.0),
                  Text(
                    'Locations & Relays',
                    style: TextStyle(
                      color: ClxyColors.textPrimary,
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              // Ping All Button
              InkWell(
                onTap: state.pingingAll ? null : () => state.pingAllServers(),
                borderRadius: BorderRadius.circular(10.0),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 48.0, minHeight: 38.0),
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
                  decoration: BoxDecoration(
                    color: ClxyColors.cardSurface,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      if (state.pingingAll)
                        const SizedBox(
                          width: 14.0,
                          height: 14.0,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor: AlwaysStoppedAnimation<Color>(ClxyColors.cyan),
                          ),
                        )
                      else
                        const Icon(
                          Icons.speed_rounded,
                          color: ClxyColors.cyan,
                          size: 16.0,
                        ),
                      const SizedBox(width: 6.0),
                      Text(
                        state.pingingAll ? 'Pinging…' : 'Ping All',
                        style: const TextStyle(
                          color: ClxyColors.cyan,
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12.0),

          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: ClxyColors.cardSurface,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: ClxyColors.textMuted,
                  size: 18.0,
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(
                      color: ClxyColors.textPrimary,
                      fontSize: 13.0,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search country, city or relay…',
                      hintStyle: TextStyle(
                        color: ClxyColors.textDim,
                        fontSize: 13.0,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () => _searchCtrl.clear(),
                    child: const Icon(
                      Icons.close_rounded,
                      color: ClxyColors.textMuted,
                      size: 18.0,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12.0),

          // Server List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24.0),
              children: [
                // 1. Auto Route row
                _buildServerCard(
                  key: '',
                  title: 'Auto Route · Recommended',
                  flagCode: 'REC',
                  subtitle: 'Optimal latency and exit path selected dynamically',
                  pingMs: 38,
                  isSelected: activePinned.isEmpty || activePinned == 'fastest',
                  onTap: () {
                    state.selectServer('', 'Auto Route · Recommended');
                    widget.onClose();
                  },
                ),
                const SizedBox(height: 8.0),

                // 2. Filtered servers
                ...filtered.map((srv) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildServerCard(
                      key: srv.key,
                      title: srv.title,
                      flagCode: srv.flagCode,
                      subtitle: srv.city, // Display-only fake VLESS URI
                      pingMs: srv.pingMs,
                      isSelected: activePinned == srv.key,
                      onTap: () {
                        state.selectServer(srv.key, srv.title);
                        widget.onClose();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard({
    required String key,
    required String title,
    required String flagCode,
    required String subtitle,
    required int pingMs,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isSelected
              ? ClxyColors.blueDeep.withOpacity(0.35)
              : ClxyColors.cardSurface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: isSelected ? ClxyColors.cyanGlow : ClxyColors.glassBorder,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            CircularCountryFlag(
              countryCode: flagCode,
              size: 34.0,
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: ClxyColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pingMs > 0) ...[
                        Text(
                          '${pingMs}ms',
                          style: TextStyle(
                            color: pingMs < 150
                                ? ClxyColors.cyanText
                                : ClxyColors.textMuted,
                            fontSize: 11.0,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 5.0),
                        SignalBars(pingMs: pingMs),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: ClxyColors.textMuted,
                      fontSize: 10.0,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 10.0),
              const Icon(
                Icons.check_circle_rounded,
                color: ClxyColors.cyanGlow,
                size: 20.0,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
