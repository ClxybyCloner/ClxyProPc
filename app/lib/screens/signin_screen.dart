import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../components/brand_header.dart';
import '../core/app_state.dart';
import '../core/prefs.dart';
import '../theme/clxy_colors.dart';

class SignInScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onDone;

  const SignInScreen({
    super.key,
    required this.state,
    required this.onDone,
  });

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _captchaCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _busy = false;
  String _status = '';
  String? _error;
  String? _sessionId;
  String _step = 'credentials'; // credentials, need_email_code, need_totp, need_unblock_code, need_captcha
  String? _captchaBase64;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = Prefs.sessionEmail;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _captchaCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSignIn() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter both email and password.');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Connecting to CLXY Cloud…';
      _error = null;
    });

    final api = widget.state.coreProcess.api;
    if (api == null) {
      setState(() {
        _busy = false;
        _error = 'Core sidecar not connected. Please ensure core is running.';
      });
      return;
    }

    try {
      final url = api.endpoint.baseUri.replace(path: '/api/signin');
      final res = await http.post(
        url,
        headers: {
          'X-Local-Token': api.endpoint.token,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 202) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _sessionId = data['id'] as String?;
        _processStep(data);
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _busy = false;
          _error = err['error']?.toString() ?? 'Sign in rejected';
        });
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Sign-in error: $e';
      });
    }
  }

  Future<void> _submitAnswer(String value) async {
    if (_sessionId == null) return;
    setState(() {
      _busy = true;
      _status = 'Verifying…';
      _error = null;
    });

    final api = widget.state.coreProcess.api;
    if (api == null) return;

    try {
      final url = api.endpoint.baseUri.replace(path: '/api/signin/$_sessionId');
      final res = await http.post(
        url,
        headers: {
          'X-Local-Token': api.endpoint.token,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'value': value.trim()}),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _processStep(data);
      } else {
        setState(() {
          _busy = false;
          _error = 'Verification failed. Please check and retry.';
        });
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  void _processStep(Map<String, dynamic> data) {
    final step = data['step'] as String? ?? '';
    final msg = data['message'] as String? ?? '';
    final err = data['error'] as String?;

    if (err != null && err.isNotEmpty) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }

    if (step == 'done') {
      Prefs.sessionEmail = _emailCtrl.text.trim();
      Prefs.sessionToken = data['account_id']?.toString() ?? 'session_active';
      setState(() {
        _busy = false;
        _status = 'Signed in successfully!';
      });
      widget.onDone();
      return;
    }

    if (step == 'need_captcha') {
      setState(() {
        _busy = false;
        _step = 'need_captcha';
        _captchaBase64 = data['captcha'] as String?;
        _status = 'Please solve the verification challenge';
      });
      return;
    }

    if (step == 'need_email_code' || step == 'need_totp' || step == 'need_unblock_code') {
      setState(() {
        _busy = false;
        _step = step;
        _status = msg.isNotEmpty ? msg : 'Enter verification code';
      });
      return;
    }

    if (step == 'failed') {
      setState(() {
        _busy = false;
        _error = msg.isNotEmpty ? msg : 'Sign-in failed';
      });
      return;
    }

    // Still working: poll
    setState(() {
      _busy = true;
      _status = msg.isNotEmpty ? msg : 'Processing…';
    });
    Future.delayed(const Duration(seconds: 1), _pollSignIn);
  }

  Future<void> _pollSignIn() async {
    if (!mounted || _sessionId == null) return;
    final api = widget.state.coreProcess.api;
    if (api == null) return;

    try {
      final url = api.endpoint.baseUri.replace(path: '/api/signin/$_sessionId');
      final res = await http.get(
        url,
        headers: {'X-Local-Token': api.endpoint.token},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _processStep(data);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const BrandHeader(logoSize: 42.0, labelSize: 22.0),
                const SizedBox(height: 8.0),
                const Text(
                  'Sign in to CLXY Cloud',
                  style: TextStyle(
                    color: ClxyColors.textPrimary,
                    fontSize: 16.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4.0),
                const Text(
                  'Access high-speed mesh endpoints and global relays',
                  style: TextStyle(
                    color: ClxyColors.textMuted,
                    fontSize: 12.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24.0),

                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: ClxyColors.redDisconnectStart.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: ClxyColors.redDisconnectStart, width: 1.0),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: ClxyColors.redDisconnectStart, size: 20.0),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.white, fontSize: 12.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16.0),
                ],

                if (_step == 'credentials') ...[
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: ClxyColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      labelStyle: const TextStyle(color: ClxyColors.textMuted),
                      prefixIcon: const Icon(Icons.mail_outline_rounded, color: ClxyColors.cyanGlow, size: 20.0),
                      filled: true,
                      fillColor: const Color(0xAA070B19),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: ClxyColors.cyanGlow),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14.0),
                  TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: ClxyColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: ClxyColors.textMuted),
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: ClxyColors.cyanGlow, size: 20.0),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: ClxyColors.textMuted,
                          size: 20.0,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: const Color(0xAA070B19),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: ClxyColors.cyanGlow),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20.0),
                  SizedBox(
                    width: double.infinity,
                    height: 48.0,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _startSignIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ClxyColors.blueDeep,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20.0,
                              height: 20.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Sign In',
                              style: TextStyle(color: Colors.white, fontSize: 14.0, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ] else if (_step == 'need_captcha') ...[
                  if (_captchaBase64 != null && _captchaBase64!.isNotEmpty)
                    Container(
                      height: 80.0,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Image.memory(
                        base64Decode(_captchaBase64!),
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(height: 12.0),
                  TextField(
                    controller: _captchaCtrl,
                    style: const TextStyle(color: ClxyColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Enter CAPTCHA characters',
                      labelStyle: const TextStyle(color: ClxyColors.textMuted),
                      filled: true,
                      fillColor: const Color(0xAA070B19),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: ClxyColors.cyanGlow),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  SizedBox(
                    width: double.infinity,
                    height: 48.0,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _submitAnswer(_captchaCtrl.text),
                      style: ElevatedButton.styleFrom(backgroundColor: ClxyColors.blueDeep),
                      child: const Text('Verify CAPTCHA', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ] else ...[
                  // need_email_code or need_totp or need_unblock_code
                  Text(
                    _status,
                    style: const TextStyle(color: ClxyColors.cyanText, fontSize: 13.0),
                  ),
                  const SizedBox(height: 12.0),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ClxyColors.textPrimary,
                      fontSize: 18.0,
                      letterSpacing: 4.0,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: '000000',
                      hintStyle: const TextStyle(color: ClxyColors.textDim, letterSpacing: 4.0),
                      filled: true,
                      fillColor: const Color(0xAA070B19),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.0),
                        borderSide: const BorderSide(color: ClxyColors.cyanGlow),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  SizedBox(
                    width: double.infinity,
                    height: 48.0,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _submitAnswer(_codeCtrl.text),
                      style: ElevatedButton.styleFrom(backgroundColor: ClxyColors.blueDeep),
                      child: const Text('Submit Code', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],

                if (_status.isNotEmpty && _step == 'credentials') ...[
                  const SizedBox(height: 16.0),
                  Text(_status, style: const TextStyle(color: ClxyColors.textMuted, fontSize: 12.0)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
