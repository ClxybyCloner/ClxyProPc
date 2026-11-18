import 'package:flutter/material.dart';
import '../core/prefs.dart';
import '../core/quantum_serial.dart';
import '../theme/clxy_colors.dart';

class QuantumSerialDialog extends StatefulWidget {
  final VoidCallback onDismiss;
  final VoidCallback onActivated;

  const QuantumSerialDialog({
    super.key,
    required this.onDismiss,
    required this.onActivated,
  });

  @override
  State<QuantumSerialDialog> createState() => _QuantumSerialDialogState();
}

class _QuantumSerialDialogState extends State<QuantumSerialDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _invalid = false;

  void _submit() {
    final code = _controller.text.trim();
    if (QuantumSerial.isValid(code)) {
      Prefs.quantumUnlocked = true;
      widget.onActivated();
    } else {
      setState(() {
        _invalid = true;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: ClxyColors.cardSurface,
          borderRadius: BorderRadius.circular(20.0),
          border: Border.all(
            color: ClxyColors.cyanGlow.withOpacity(0.4),
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.vpn_key_rounded,
              color: ClxyColors.cyanText,
              size: 30.0,
            ),
            const SizedBox(height: 12.0),
            const Text(
              'Quantum Serial',
              style: TextStyle(
                fontSize: 17.0,
                fontWeight: FontWeight.bold,
                color: ClxyColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            const Text(
              'Enter your Quantum serial number to activate CLXY Quantum on this device.',
              style: TextStyle(
                fontSize: 12.0,
                color: ClxyColors.textMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16.0),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: ClxyColors.textPrimary,
                fontSize: 14.0,
                letterSpacing: 2.0,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'XXXXX',
                hintStyle: TextStyle(
                  color: ClxyColors.textDim.withOpacity(0.5),
                  letterSpacing: 2.0,
                ),
                filled: true,
                fillColor: const Color(0xAA070B19),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(
                    color: _invalid
                        ? ClxyColors.redDisconnectStart
                        : const Color(0xFF334155),
                    width: 1.0,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(
                    color: _invalid
                        ? ClxyColors.redDisconnectStart
                        : ClxyColors.cyanGlow,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            if (_invalid) ...[
              const SizedBox(height: 8.0),
              const Text(
                'Invalid serial number. Please check it and try again.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: ClxyColors.redDisconnectStart,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46.0,
                    child: TextButton(
                      onPressed: widget.onDismiss,
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: ClxyColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10.0),
                Expanded(
                  child: SizedBox(
                    height: 46.0,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ClxyColors.blueDeep,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Activate',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
